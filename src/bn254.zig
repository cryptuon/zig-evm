// File: src/bn254.zig
//
// G1 arithmetic on the alt_bn128 (BN254) curve, just enough to implement the
// ECADD (precompile 0x06) and ECMUL (0x07) precompiles per EIP-196. Pairing
// (precompile 0x08) requires Fp2/Fp12 and a Miller loop and is not implemented
// here — see RESEARCH_PLAN.
//
// Field arithmetic is straightforward: elements are `u256`, multiplication uses
// a `u512` intermediate, and inversion is Fermat (a^(p-2)). Points are stored
// in affine form with an explicit infinity flag. The implementation is
// correctness-focused, not constant-time, and is verified against the EIP-196
// test vector for 2*G (both as G + G under ECADD and G * 2 under ECMUL).

const std = @import("std");

pub const P: u256 = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
pub const B: u256 = 3; // y^2 = x^3 + 3 (curve a = 0)

// --- field arithmetic mod P ------------------------------------------------

pub fn addP(a: u256, b: u256) u256 {
    const sum = @as(u257, a) + @as(u257, b);
    return @intCast(if (sum >= P) sum - P else sum);
}
pub fn subP(a: u256, b: u256) u256 {
    return if (a >= b) a - b else P - (b - a);
}
pub fn mulP(a: u256, b: u256) u256 {
    return @intCast((@as(u512, a) * @as(u512, b)) % P);
}
fn powP(base: u256, exp: u256) u256 {
    var r: u256 = 1;
    var b = base;
    var e = exp;
    while (e > 0) : (e >>= 1) {
        if (e & 1 == 1) r = mulP(r, b);
        b = mulP(b, b);
    }
    return r;
}
pub fn invP(a: u256) u256 {
    return powP(a, P - 2); // Fermat: a^(p-2) = a^-1
}
pub fn isOnCurve(x: u256, y: u256) bool {
    const y2 = mulP(y, y);
    const x3 = mulP(mulP(x, x), x);
    return y2 == addP(x3, B);
}

// --- G1 point in affine coordinates ---------------------------------------

pub const Point = struct {
    x: u256,
    y: u256,
    inf: bool,

    pub const identity = Point{ .x = 0, .y = 0, .inf = true };
};

pub fn double(p: Point) Point {
    if (p.inf) return p;
    if (p.y == 0) return Point.identity;
    // lambda = (3*x^2) / (2*y)   (a = 0 for BN254)
    const lam = mulP(mulP(3, mulP(p.x, p.x)), invP(mulP(2, p.y)));
    const x3 = subP(mulP(lam, lam), mulP(2, p.x));
    const y3 = subP(mulP(lam, subP(p.x, x3)), p.y);
    return .{ .x = x3, .y = y3, .inf = false };
}

pub fn add(p: Point, q: Point) Point {
    if (p.inf) return q;
    if (q.inf) return p;
    if (p.x == q.x) {
        if (p.y == q.y) return double(p);
        return Point.identity; // P + (-P) = O
    }
    const lam = mulP(subP(q.y, p.y), invP(subP(q.x, p.x)));
    const x3 = subP(subP(mulP(lam, lam), p.x), q.x);
    const y3 = subP(mulP(lam, subP(p.x, x3)), p.y);
    return .{ .x = x3, .y = y3, .inf = false };
}

pub fn scalarMul(p: Point, scalar: u256) Point {
    var r = Point.identity;
    var base = p;
    var s = scalar;
    while (s > 0) : (s >>= 1) {
        if (s & 1 == 1) r = add(r, base);
        base = double(base);
    }
    return r;
}

// --- serialization helpers -------------------------------------------------

fn readU256(bytes: *const [32]u8) u256 {
    var v: u256 = 0;
    for (bytes) |b| v = (v << 8) | b;
    return v;
}
fn writeU256(v: u256, out: *[32]u8) void {
    var x = v;
    var i: usize = 32;
    while (i > 0) {
        i -= 1;
        out[i] = @truncate(x);
        x >>= 8;
    }
}

/// Parse a 64-byte (x, y) coordinate pair. (0, 0) denotes the point at
/// infinity; any other point with a coordinate >= P, or off-curve, is invalid.
fn parsePoint(buf: *const [64]u8) !Point {
    const x = readU256(buf[0..32]);
    const y = readU256(buf[32..64]);
    if (x >= P or y >= P) return error.NonCanonical;
    if (x == 0 and y == 0) return Point.identity;
    if (!isOnCurve(x, y)) return error.NotOnCurve;
    return .{ .x = x, .y = y, .inf = false };
}

fn writePoint(p: Point, out: *[64]u8) void {
    if (p.inf) {
        @memset(out, 0);
        return;
    }
    writeU256(p.x, out[0..32]);
    writeU256(p.y, out[32..64]);
}

fn padTo(input: []const u8, comptime N: usize) [N]u8 {
    var buf: [N]u8 = [_]u8{0} ** N;
    const n = @min(input.len, N);
    @memcpy(buf[0..n], input[0..n]);
    return buf;
}

// --- precompiles -----------------------------------------------------------

/// ECADD (0x06): input 128 bytes (zero-padded), output 64 bytes (x || y).
pub fn ecadd(input: []const u8, out: *[64]u8) !void {
    const buf = padTo(input, 128);
    const p = try parsePoint(buf[0..64]);
    const q = try parsePoint(buf[64..128]);
    writePoint(add(p, q), out);
}

/// ECMUL (0x07): input 96 bytes (zero-padded), output 64 bytes.
pub fn ecmul(input: []const u8, out: *[64]u8) !void {
    const buf = padTo(input, 96);
    const p = try parsePoint(buf[0..64]);
    const scalar = readU256(buf[64..96]);
    writePoint(scalarMul(p, scalar), out);
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

// G = (1, 2). 2*G per EIP-196:
const TWO_G_X: u256 = 0x030644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd3;
const TWO_G_Y: u256 = 0x15ed738c0e0a7c92e7845f96b2ae9c0a68a6a449e3538fc7ff3ebf7a5a18a2c4;

test "bn254: G is on the curve" {
    try testing.expect(isOnCurve(1, 2));
}

test "bn254: 2*G via doubling matches EIP-196" {
    const g = Point{ .x = 1, .y = 2, .inf = false };
    const r = double(g);
    try testing.expect(!r.inf);
    try testing.expectEqual(TWO_G_X, r.x);
    try testing.expectEqual(TWO_G_Y, r.y);
}

test "bn254: G + G = 2G (the ECADD-style path)" {
    const g = Point{ .x = 1, .y = 2, .inf = false };
    const r = add(g, g);
    try testing.expectEqual(TWO_G_X, r.x);
    try testing.expectEqual(TWO_G_Y, r.y);
}

test "bn254: G + (-G) = identity" {
    const g = Point{ .x = 1, .y = 2, .inf = false };
    const neg_g = Point{ .x = 1, .y = P - 2, .inf = false };
    const r = add(g, neg_g);
    try testing.expect(r.inf);
}

test "bn254: scalarMul(G, 2) = 2G" {
    const g = Point{ .x = 1, .y = 2, .inf = false };
    const r = scalarMul(g, 2);
    try testing.expectEqual(TWO_G_X, r.x);
    try testing.expectEqual(TWO_G_Y, r.y);
}

test "bn254: scalarMul(G, 0) = identity, scalarMul(G, 1) = G" {
    const g = Point{ .x = 1, .y = 2, .inf = false };
    try testing.expect(scalarMul(g, 0).inf);
    const one = scalarMul(g, 1);
    try testing.expectEqual(@as(u256, 1), one.x);
    try testing.expectEqual(@as(u256, 2), one.y);
}

test "bn254: ECADD precompile for G + G matches EIP-196" {
    var input: [128]u8 = [_]u8{0} ** 128;
    input[31] = 1;  input[63] = 2;   // (x1, y1) = (1, 2)
    input[95] = 1;  input[127] = 2;  // (x2, y2) = (1, 2)
    var out: [64]u8 = undefined;
    try ecadd(&input, &out);
    try testing.expectEqual(TWO_G_X, readU256(out[0..32]));
    try testing.expectEqual(TWO_G_Y, readU256(out[32..64]));
}

test "bn254: ECMUL precompile for G * 2 matches EIP-196" {
    var input: [96]u8 = [_]u8{0} ** 96;
    input[31] = 1; input[63] = 2;     // P = (1, 2)
    input[95] = 2;                    // scalar = 2
    var out: [64]u8 = undefined;
    try ecmul(&input, &out);
    try testing.expectEqual(TWO_G_X, readU256(out[0..32]));
    try testing.expectEqual(TWO_G_Y, readU256(out[32..64]));
}

test "bn254: off-curve point is rejected" {
    var input: [128]u8 = [_]u8{0} ** 128;
    input[31] = 1; input[63] = 3; // (1, 3) is not on the curve
    var out: [64]u8 = undefined;
    try testing.expectError(error.NotOnCurve, ecadd(&input, &out));
}

test "bn254: ECADD with (0,0) treats it as the point at infinity" {
    var input: [128]u8 = [_]u8{0} ** 128;
    // P = (0, 0) (identity), Q = G
    input[95] = 1; input[127] = 2;
    var out: [64]u8 = undefined;
    try ecadd(&input, &out);
    // identity + G = G
    try testing.expectEqual(@as(u256, 1), readU256(out[0..32]));
    try testing.expectEqual(@as(u256, 2), readU256(out[32..64]));
}
