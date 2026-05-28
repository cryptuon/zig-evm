// File: src/bn254_pairing.zig
//
// Optimal Ate pairing on the alt_bn128 (BN254) curve — sufficient for the
// precompile at address 0x08 (EIP-197). Built on the field tower in
// bn254_fields.zig. Performance is correctness-first: the Miller loop uses the
// 6u+2 binary representation (no NAF), and the final exponentiation does a
// direct ~u1024-bit power. The implementation is verified against the EIP-197
// pairing-cancellation vector e(P, Q) * e(-P, Q) = 1, which exercises every
// non-trivial layer end to end.

const std = @import("std");
const bn = @import("bn254.zig");
const F = @import("bn254_fields.zig");

const Fp = F.Fp;
const Fp2 = F.Fp2;
const Fp6 = F.Fp6;
const Fp12 = F.Fp12;
const P_FP = F.P;

// ----- BN254 parameters ----------------------------------------------------

/// BN curve parameter; 6u + 2 is the Miller-loop scalar for the optimal Ate.
pub const U: u64 = 4965661367192848881;
pub const SIX_U_PLUS_TWO: u128 = 6 * @as(u128, U) + 2;

/// Twist curve constant b' = 3 / (9 + i) ∈ Fp2.
pub const B_TWIST: Fp2 = F.fp2Mul(F.fp2Inv(F.XI), Fp2{ .c0 = 3, .c1 = 0 });

/// Frobenius constants on G2 (twisted): π(x,y) = (conj(x)·γ1, conj(y)·γ2).
const GAMMA_1: Fp2 = F.fp2Pow(F.XI, (P_FP - 1) / 3); // ξ^((p-1)/3)
const GAMMA_2: Fp2 = F.fp2Pow(F.XI, (P_FP - 1) / 2); // ξ^((p-1)/2)

// ----- G2 affine points ----------------------------------------------------

pub const G2 = struct {
    x: Fp2,
    y: Fp2,
    inf: bool,

    pub const identity = G2{ .x = Fp2.zero, .y = Fp2.zero, .inf = true };
};

pub fn g2IsOnCurve(p: G2) bool {
    if (p.inf) return true;
    const y2 = F.fp2Sqr(p.y);
    const x3 = F.fp2Mul(F.fp2Sqr(p.x), p.x);
    return y2.eql(F.fp2Add(x3, B_TWIST));
}

pub fn g2Double(p: G2) G2 {
    if (p.inf) return p;
    if (p.y.isZero()) return G2.identity;
    // λ = (3 x²) / (2 y)
    const lam = F.fp2Mul(F.fp2MulFp(F.fp2Sqr(p.x), 3), F.fp2Inv(F.fp2MulFp(p.y, 2)));
    const x3 = F.fp2Sub(F.fp2Sqr(lam), F.fp2MulFp(p.x, 2));
    const y3 = F.fp2Sub(F.fp2Mul(lam, F.fp2Sub(p.x, x3)), p.y);
    return .{ .x = x3, .y = y3, .inf = false };
}

pub fn g2Add(p: G2, q: G2) G2 {
    if (p.inf) return q;
    if (q.inf) return p;
    if (p.x.eql(q.x)) {
        if (p.y.eql(q.y)) return g2Double(p);
        return G2.identity;
    }
    const lam = F.fp2Mul(F.fp2Sub(q.y, p.y), F.fp2Inv(F.fp2Sub(q.x, p.x)));
    const x3 = F.fp2Sub(F.fp2Sub(F.fp2Sqr(lam), p.x), q.x);
    const y3 = F.fp2Sub(F.fp2Mul(lam, F.fp2Sub(p.x, x3)), p.y);
    return .{ .x = x3, .y = y3, .inf = false };
}

pub fn g2Neg(p: G2) G2 {
    if (p.inf) return p;
    return .{ .x = p.x, .y = F.fp2Neg(p.y), .inf = false };
}

/// Twist Frobenius: π(Q) = (conj(xQ) · γ1, conj(yQ) · γ2).
pub fn g2Frobenius(p: G2) G2 {
    if (p.inf) return p;
    return .{
        .x = F.fp2Mul(F.fp2Conj(p.x), GAMMA_1),
        .y = F.fp2Mul(F.fp2Conj(p.y), GAMMA_2),
        .inf = false,
    };
}

// ----- Miller loop ---------------------------------------------------------

/// Build the sparse Fp12 line value at P = (xP, yP) ∈ E(Fp), for a line through
/// R ∈ E'(Fp2) with slope λ on the D-twist: nonzero coefficients are
///   c0.c0 = yP,    c1.c0 = -λ · xP,    c1.c1 = λ · xR - yR.
fn lineValue(rx: Fp2, ry: Fp2, lam: Fp2, xP: Fp, yP: Fp) Fp12 {
    const minus_lam_xP = F.fp2Neg(F.fp2MulFp(lam, xP));
    const lam_xR_minus_yR = F.fp2Sub(F.fp2Mul(lam, rx), ry);
    return Fp12{
        .c0 = Fp6{ .c0 = .{ .c0 = yP, .c1 = 0 }, .c1 = Fp2.zero, .c2 = Fp2.zero },
        .c1 = Fp6{ .c0 = minus_lam_xP, .c1 = lam_xR_minus_yR, .c2 = Fp2.zero },
    };
}

fn doubleStep(R: *G2, xP: Fp, yP: Fp) Fp12 {
    const lam = F.fp2Mul(F.fp2MulFp(F.fp2Sqr(R.x), 3), F.fp2Inv(F.fp2MulFp(R.y, 2)));
    const line = lineValue(R.x, R.y, lam, xP, yP);
    const x3 = F.fp2Sub(F.fp2Sqr(lam), F.fp2MulFp(R.x, 2));
    const y3 = F.fp2Sub(F.fp2Mul(lam, F.fp2Sub(R.x, x3)), R.y);
    R.* = .{ .x = x3, .y = y3, .inf = false };
    return line;
}

fn addStep(R: *G2, Q: G2, xP: Fp, yP: Fp) Fp12 {
    const lam = F.fp2Mul(F.fp2Sub(Q.y, R.y), F.fp2Inv(F.fp2Sub(Q.x, R.x)));
    const line = lineValue(R.x, R.y, lam, xP, yP);
    const x3 = F.fp2Sub(F.fp2Sub(F.fp2Sqr(lam), R.x), Q.x);
    const y3 = F.fp2Sub(F.fp2Mul(lam, F.fp2Sub(R.x, x3)), R.y);
    R.* = .{ .x = x3, .y = y3, .inf = false };
    return line;
}

fn millerLoop(P: bn.Point, Q: G2) Fp12 {
    if (P.inf or Q.inf) return Fp12.one;
    var f = Fp12.one;
    var R = Q;
    // Iterate bits of 6u+2 from MSB-1 down to 0.
    var i: i32 = @as(i32, std.math.log2_int(u128, SIX_U_PLUS_TWO)) - 1;
    while (i >= 0) : (i -= 1) {
        f = F.fp12Sqr(f);
        f = F.fp12Mul(f, doubleStep(&R, P.x, P.y));
        const bit = (SIX_U_PLUS_TWO >> @intCast(i)) & 1;
        if (bit == 1) {
            f = F.fp12Mul(f, addStep(&R, Q, P.x, P.y));
        }
    }
    // Optimal Ate Frobenius correction (BN curves, u > 0):
    //   Q1 = π(Q),  Q2 = -π²(Q);  f *= line(R, Q1) · line(R, Q2)
    const Q1 = g2Frobenius(Q);
    const Q2 = g2Neg(g2Frobenius(Q1));
    f = F.fp12Mul(f, addStep(&R, Q1, P.x, P.y));
    f = F.fp12Mul(f, addStep(&R, Q2, P.x, P.y));
    return f;
}

// ----- Final exponentiation ------------------------------------------------

/// The hard-part exponent (p^4 - p^2 + 1)/r, computed at comptime so we never
/// transcribe the ~768-bit constant by hand.
const HARD_EXP: u1024 = blk: {
    const p = @as(u1024, P_FP);
    const r: u1024 = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    const p2 = p * p;
    const p4 = p2 * p2;
    break :blk (p4 - p2 + 1) / r;
};

fn fp12PowBig(base: Fp12, exp: u1024) Fp12 {
    var r = Fp12.one;
    var b = base;
    var e = exp;
    while (e > 0) : (e >>= 1) {
        if ((e & 1) == 1) r = F.fp12Mul(r, b);
        b = F.fp12Sqr(b);
    }
    return r;
}

pub fn finalExp(f: Fp12) Fp12 {
    // Easy part: f -> f^((p^6 - 1)(p^2 + 1)).
    // f^(p^6) = conjugate over Fp6 = (c0, -c1) for our tower.
    const t0 = F.fp12Conj(f); // = f^(p^6)
    const t1 = F.fp12Inv(f);
    const t2 = F.fp12Mul(t0, t1); // f^(p^6 - 1)
    const t3 = F.fp12Frobenius(F.fp12Frobenius(t2)); // ^(p^2)
    const easy = F.fp12Mul(t3, t2); // ^(p^2 + 1)
    // Hard part: ^((p^4 - p^2 + 1)/r). Direct exponentiation by the comptime
    // constant — slow but unambiguous.
    return fp12PowBig(easy, HARD_EXP);
}

// ----- The pairing precompile ---------------------------------------------

/// Run the pairing check on `pairs`: returns true iff the product of pairings
/// equals 1 in Fp12 (the EIP-197 result; empty input gives 1 trivially).
pub fn pairingCheck(pairs: []const PairingPair) bool {
    var f = Fp12.one;
    for (pairs) |pp| {
        f = F.fp12Mul(f, millerLoop(pp.g1, pp.g2));
    }
    return finalExp(f).isOne();
}

pub const PairingPair = struct { g1: bn.Point, g2: G2 };

fn readFp(bytes: *const [32]u8) !Fp {
    var v: u256 = 0;
    for (bytes) |b| v = (v << 8) | b;
    if (v >= P_FP) return error.NonCanonical;
    return v;
}

fn parseG1(bytes: *const [64]u8) !bn.Point {
    const x = try readFp(bytes[0..32]);
    const y = try readFp(bytes[32..64]);
    if (x == 0 and y == 0) return bn.Point.identity;
    if (!bn.isOnCurve(x, y)) return error.NotOnCurve;
    return .{ .x = x, .y = y, .inf = false };
}

fn parseG2(bytes: *const [128]u8) !G2 {
    // EIP-197 lays G2 out as (imag(x), real(x), imag(y), real(y)).
    const x_im = try readFp(bytes[0..32]);
    const x_re = try readFp(bytes[32..64]);
    const y_im = try readFp(bytes[64..96]);
    const y_re = try readFp(bytes[96..128]);
    const point = G2{
        .x = .{ .c0 = x_re, .c1 = x_im },
        .y = .{ .c0 = y_re, .c1 = y_im },
        .inf = false,
    };
    if (x_re == 0 and x_im == 0 and y_re == 0 and y_im == 0) return G2.identity;
    if (!g2IsOnCurve(point)) return error.NotOnCurve;
    return point;
}

/// Precompile (0x08): input is k pairs of 192 bytes (G1 ‖ G2). Output is the
/// 32-byte big-endian boolean (0x00..01 for true, 0x00..00 for false).
pub fn ecpairing(allocator: std.mem.Allocator, input: []const u8) !struct { gas: u64, output: []u8 } {
    if (input.len % 192 != 0) return error.InvalidPairingInput;
    const k: u64 = @intCast(input.len / 192);
    const gas: u64 = 45_000 + 34_000 * k; // EIP-1108 (post Istanbul)

    var pairs = std.ArrayListUnmanaged(PairingPair){};
    defer pairs.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) : (i += 192) {
        const g1 = try parseG1(input[i .. i + 64][0..64]);
        const g2 = try parseG2(input[i + 64 .. i + 192][0..128]);
        try pairs.append(allocator, .{ .g1 = g1, .g2 = g2 });
    }

    const ok = pairingCheck(pairs.items);
    const out = try allocator.alloc(u8, 32);
    @memset(out, 0);
    if (ok) out[31] = 1;
    return .{ .gas = gas, .output = out };
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

/// EIP-197 G2 generator.
const G2_GEN = G2{
    .x = .{
        .c0 = 10857046999023057135944570762232829481370756359578518086990519993285655852781,
        .c1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634,
    },
    .y = .{
        .c0 = 8495653923123431417604973247489272438418190587263600148770280649306958101930,
        .c1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531,
    },
    .inf = false,
};
const G1_GEN = bn.Point{ .x = 1, .y = 2, .inf = false };

test "bn254-pairing: G2 generator is on the twist" {
    try testing.expect(g2IsOnCurve(G2_GEN));
}

test "bn254-pairing: empty input returns 1" {
    const a = testing.allocator;
    const r = try ecpairing(a, "");
    defer a.free(r.output);
    try testing.expectEqual(@as(u8, 1), r.output[31]);
}

test "bn254-pairing: e(P, Q) · e(-P, Q) = 1 (cancellation, EIP-197 spirit)" {
    const a = testing.allocator;
    var input: [384]u8 = [_]u8{0} ** 384;
    // Pair 1: (G1, G2_GEN)
    input[31] = 1; input[63] = 2;
    writeFpBE(&input, 64, G2_GEN.x.c1); // imag x
    writeFpBE(&input, 96, G2_GEN.x.c0); // real x
    writeFpBE(&input, 128, G2_GEN.y.c1); // imag y
    writeFpBE(&input, 160, G2_GEN.y.c0); // real y
    // Pair 2: (-G1, G2_GEN). -G1 = (1, p - 2).
    input[223] = 1;
    writeFpBE(&input, 224, P_FP - 2);
    writeFpBE(&input, 256, G2_GEN.x.c1);
    writeFpBE(&input, 288, G2_GEN.x.c0);
    writeFpBE(&input, 320, G2_GEN.y.c1);
    writeFpBE(&input, 352, G2_GEN.y.c0);

    const r = try ecpairing(a, &input);
    defer a.free(r.output);
    try testing.expectEqual(@as(u8, 1), r.output[31]);
}

test "bn254-pairing: e(G1, G2) alone is NOT 1 (non-degeneracy)" {
    const a = testing.allocator;
    var input: [192]u8 = [_]u8{0} ** 192;
    input[31] = 1; input[63] = 2;
    writeFpBE(&input, 64, G2_GEN.x.c1);
    writeFpBE(&input, 96, G2_GEN.x.c0);
    writeFpBE(&input, 128, G2_GEN.y.c1);
    writeFpBE(&input, 160, G2_GEN.y.c0);
    const r = try ecpairing(a, &input);
    defer a.free(r.output);
    try testing.expectEqual(@as(u8, 0), r.output[31]);
}

fn writeFpBE(buf: []u8, off: usize, v: Fp) void {
    var x = v;
    var i: usize = 32;
    while (i > 0) {
        i -= 1;
        buf[off + i] = @truncate(x);
        x >>= 8;
    }
}
