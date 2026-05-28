// File: src/precompiles.zig
//
// Ethereum precompiled contracts at addresses 0x01..0x09. Only the two that the
// Zig standard library lets us implement faithfully and verify against published
// test vectors are provided: SHA-256 (0x02) and the identity/datacopy (0x04).
// The cryptographic precompiles that need secp256k1 recovery, big-integer
// modexp, BN254 curve arithmetic, or the BLAKE2 compression function return
// `error.UnsupportedPrecompile` rather than a fabricated result, so a caller
// never mistakes a stub for a correct output.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ourcrypto = @import("crypto.zig"); // Keccak-256 for address derivation
const ripemd = @import("ripemd160.zig");

pub const Result = struct { gas: u64, output: []u8 };

/// True for addresses 0x00..01 through 0x00..09 (19 leading zero bytes).
pub fn isPrecompile(addr: [20]u8) bool {
    var i: usize = 0;
    while (i < 19) : (i += 1) {
        if (addr[i] != 0) return false;
    }
    return addr[19] >= 1 and addr[19] <= 9;
}

fn words(len: usize) u64 {
    return @intCast((len + 31) / 32);
}

/// Execute the precompile at `addr` on `input`. Returns its gas cost and a
/// freshly-allocated output (caller owns/frees), or `error.UnsupportedPrecompile`
/// for the ones not yet implemented.
pub fn run(allocator: Allocator, addr: [20]u8, input: []const u8) !Result {
    return switch (addr[19]) {
        0x01 => try ecrecover(allocator, input), // secp256k1 public-key recovery
        0x02 => blk: { // SHA-256
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
            const out = try allocator.dupe(u8, &digest);
            break :blk Result{ .gas = 60 + 12 * words(input.len), .output = out };
        },
        0x04 => blk: { // identity (datacopy)
            const out = try allocator.dupe(u8, input);
            break :blk Result{ .gas = 15 + 3 * words(input.len), .output = out };
        },
        0x03 => blk: { // RIPEMD-160 (left-padded to 32 bytes per the spec)
            const h = ripemd.hash(input);
            const out = try allocator.alloc(u8, 32);
            @memset(out, 0);
            @memcpy(out[12..32], &h);
            break :blk Result{ .gas = 600 + 120 * words(input.len), .output = out };
        },
        0x05 => try modexp(allocator, input), // modular exponentiation
        // 0x06/0x07/0x08 BN254 add/mul/pairing, 0x09 blake2f: not yet implemented.
        else => error.UnsupportedPrecompile,
    };
}

// --- ecrecover (0x01) ------------------------------------------------------

/// Recover the signer address from a 128-byte ecrecover input
/// (hash || v || r || s, each 32 bytes), or null on any invalid input.
fn recoverAddress(input: []const u8) ?[20]u8 {
    const S = std.crypto.ecc.Secp256k1;

    var buf: [128]u8 = [_]u8{0} ** 128;
    const n = @min(input.len, 128);
    @memcpy(buf[0..n], input[0..n]);

    // v at bytes [32,64): must be exactly 27 or 28.
    var i: usize = 32;
    while (i < 63) : (i += 1) {
        if (buf[i] != 0) return null;
    }
    if (buf[63] != 27 and buf[63] != 28) return null;
    const recid_odd = (buf[63] - 27) == 1;

    const r_bytes: [32]u8 = buf[64..96].*;
    const s_bytes: [32]u8 = buf[96..128].*;

    // r, s must be canonical scalars in [1, n-1].
    const r_scalar = S.scalar.Scalar.fromBytes(r_bytes, .big) catch return null;
    const s_scalar = S.scalar.Scalar.fromBytes(s_bytes, .big) catch return null;
    if (r_scalar.isZero() or s_scalar.isZero()) return null;

    // Recover R from x = r with the parity given by the recovery id.
    const x = S.Fe.fromBytes(r_bytes, .big) catch return null;
    const y = S.recoverY(x, recid_odd) catch return null;
    const R = S.fromAffineCoordinates(.{ .x = x, .y = y }) catch return null;

    // Message hash reduced mod the curve order (zero-extend to 48 bytes).
    var h48: [48]u8 = [_]u8{0} ** 48;
    @memcpy(h48[16..48], buf[0..32]);
    const h_scalar = S.scalar.Scalar.fromBytes48(h48, .big);

    // Q = r^-1 (s*R - h*G) = (s*r^-1)*R + (-h*r^-1)*G.
    const r_inv = r_scalar.invert();
    const c1 = h_scalar.neg().mul(r_inv); // -h * r^-1  (coefficient of G)
    const c2 = s_scalar.mul(r_inv); //  s * r^-1  (coefficient of R)
    const Q = S.mulDoubleBasePublic(S.basePoint, c1.toBytes(.big), R, c2.toBytes(.big), .big) catch return null;

    // Address = keccak256(uncompressed pubkey x||y)[12:].
    const aff = Q.affineCoordinates();
    var pub64: [64]u8 = undefined;
    const xb = aff.x.toBytes(.big);
    const yb = aff.y.toBytes(.big);
    @memcpy(pub64[0..32], &xb);
    @memcpy(pub64[32..64], &yb);
    const kh = ourcrypto.keccak256(&pub64);
    var addr: [20]u8 = undefined;
    @memcpy(&addr, kh[12..32]);
    return addr;
}

fn ecrecover(allocator: Allocator, input: []const u8) !Result {
    // Fixed 3000 gas; on invalid input the precompile returns empty output (the
    // call still succeeds), so we never error here.
    const maybe = recoverAddress(input);
    const out = try allocator.alloc(u8, if (maybe != null) 32 else 0);
    if (maybe) |addr| {
        @memset(out, 0);
        @memcpy(out[12..32], &addr);
    }
    return Result{ .gas = 3000, .output = out };
}

// --- modexp (0x05) ---------------------------------------------------------

const big = std.math.big.int;

/// Big-endian 32-byte length word at `off` (zero-padded past the input), capped
/// to a sane size — the EVM bounds this with gas; we cap to avoid pathological
/// allocation in the offline harness.
fn lenWord(input: []const u8, off: usize) usize {
    var v: u256 = 0;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        const idx = off + i;
        v = (v << 8) | (if (idx < input.len) input[idx] else 0);
    }
    const cap: u256 = 1 << 20; // 1 MiB per field
    if (v > cap) return @intCast(cap);
    return @intCast(v);
}

/// Big-endian slice [off, off+len) of `input`, zero-padded, freshly allocated.
fn padded(allocator: Allocator, input: []const u8, off: usize, len: usize) ![]u8 {
    const out = try allocator.alloc(u8, len);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const idx = off + i;
        out[i] = if (idx < input.len) input[idx] else 0;
    }
    return out;
}

fn bytesToU256(bytes: []const u8) u256 {
    var v: u256 = 0;
    const n = @min(bytes.len, 32);
    var i: usize = 0;
    while (i < n) : (i += 1) v = (v << 8) | bytes[i];
    return v;
}

fn bitLen(v: u256) u64 {
    if (v == 0) return 0;
    return 256 - @clz(v);
}

fn managedFromBytes(allocator: Allocator, bytes: []const u8) !big.Managed {
    var acc = try big.Managed.init(allocator);
    errdefer acc.deinit();
    try acc.set(0);
    var tmp = try big.Managed.init(allocator);
    defer tmp.deinit();
    for (bytes) |byte| {
        try acc.shiftLeft(&acc, 8);
        try tmp.set(@as(u64, byte));
        try acc.add(&acc, &tmp);
    }
    return acc;
}

fn modpow(allocator: Allocator, base: *const big.Managed, exp: *const big.Managed, mod: *const big.Managed) !big.Managed {
    var result = try big.Managed.init(allocator);
    errdefer result.deinit();
    try result.set(1);
    var q = try big.Managed.init(allocator);
    defer q.deinit();
    var b = try big.Managed.init(allocator);
    defer b.deinit();
    var tmp = try big.Managed.init(allocator);
    defer tmp.deinit();
    try q.divFloor(&b, base, mod); // b = base mod mod
    var e = try exp.clone();
    defer e.deinit();
    while (!e.eqlZero()) {
        if ((e.toConst().limbs[0] & 1) == 1) {
            try tmp.mul(&result, &b);
            try q.divFloor(&result, &tmp, mod); // result = (result*b) mod mod
        }
        try tmp.mul(&b, &b);
        try q.divFloor(&b, &tmp, mod); // b = (b*b) mod mod
        try e.shiftRight(&e, 1);
    }
    return result;
}

/// EIP-2565 gas: max(200, floor(mult_complexity * iteration_count / 3)).
fn modexpGas(bsize: usize, esize: usize, msize: usize, exp_bytes: []const u8) u64 {
    const wmax: u64 = @intCast((@max(bsize, msize) + 7) / 8);
    const mult_complexity = wmax * wmax;
    var iter: u64 = 0;
    if (esize <= 32) {
        const e = bytesToU256(exp_bytes);
        iter = if (e == 0) 0 else bitLen(e) - 1;
    } else {
        const head = bytesToU256(exp_bytes[0..32]);
        const head_bits: u64 = if (head == 0) 0 else bitLen(head) - 1;
        iter = 8 * @as(u64, @intCast(esize - 32)) + head_bits;
    }
    const cost = (mult_complexity * iter) / 3;
    return @max(@as(u64, 200), cost);
}

fn modexp(allocator: Allocator, input: []const u8) !Result {
    const bsize = lenWord(input, 0);
    const esize = lenWord(input, 32);
    const msize = lenWord(input, 64);

    const base_bytes = try padded(allocator, input, 96, bsize);
    defer allocator.free(base_bytes);
    const exp_bytes = try padded(allocator, input, 96 + bsize, esize);
    defer allocator.free(exp_bytes);
    const mod_bytes = try padded(allocator, input, 96 + bsize + esize, msize);
    defer allocator.free(mod_bytes);

    const gas = modexpGas(bsize, esize, msize, exp_bytes);

    const out = try allocator.alloc(u8, msize);
    errdefer allocator.free(out);
    @memset(out, 0);
    if (msize == 0) return Result{ .gas = gas, .output = out };

    var base_m = try managedFromBytes(allocator, base_bytes);
    defer base_m.deinit();
    var exp_m = try managedFromBytes(allocator, exp_bytes);
    defer exp_m.deinit();
    var mod_m = try managedFromBytes(allocator, mod_bytes);
    defer mod_m.deinit();
    if (mod_m.eqlZero()) return Result{ .gas = gas, .output = out }; // mod 0 -> zeros

    var res_m = try modpow(allocator, &base_m, &exp_m, &mod_m);
    defer res_m.deinit();

    // Write the result big-endian, right-aligned in the msize-byte output.
    const limbs = res_m.toConst().limbs;
    var i: usize = 0;
    while (i < msize) : (i += 1) {
        const limb_idx = i / 8;
        const byte_in_limb = i % 8;
        const limb: u64 = if (limb_idx < limbs.len) @intCast(limbs[limb_idx]) else 0;
        out[msize - 1 - i] = @truncate(limb >> @intCast(8 * byte_in_limb));
    }
    return Result{ .gas = gas, .output = out };
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

fn precompileAddr(n: u8) [20]u8 {
    var a: [20]u8 = [_]u8{0} ** 20;
    a[19] = n;
    return a;
}

test "precompile: address identification" {
    try testing.expect(isPrecompile(precompileAddr(2)));
    try testing.expect(isPrecompile(precompileAddr(9)));
    try testing.expect(!isPrecompile(precompileAddr(0)));
    try testing.expect(!isPrecompile(precompileAddr(10)));
    var hi = precompileAddr(4);
    hi[0] = 1; // a nonzero high byte means it is not a precompile address
    try testing.expect(!isPrecompile(hi));
}

test "precompile: SHA-256 matches known vectors with correct gas" {
    const a = testing.allocator;

    const empty = try run(a, precompileAddr(2), "");
    defer a.free(empty.output);
    try testing.expectEqual(@as(u64, 60), empty.gas);
    const sha_empty = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    try testing.expectEqualSlices(u8, &sha_empty, empty.output);

    const abc = try run(a, precompileAddr(2), "abc");
    defer a.free(abc.output);
    try testing.expectEqual(@as(u64, 60 + 12), abc.gas); // 3 bytes -> 1 word
    const sha_abc = [_]u8{
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
    };
    try testing.expectEqualSlices(u8, &sha_abc, abc.output);
}

test "precompile: identity copies input with correct gas" {
    const a = testing.allocator;
    const r = try run(a, precompileAddr(4), "hello world!!");
    defer a.free(r.output);
    try testing.expectEqualSlices(u8, "hello world!!", r.output);
    try testing.expectEqual(@as(u64, 15 + 3), r.gas); // 13 bytes -> 1 word
}

test "precompile: unimplemented ones report unsupported" {
    const a = testing.allocator;
    try testing.expectError(error.UnsupportedPrecompile, run(a, precompileAddr(6), "")); // bn254 add
    try testing.expectError(error.UnsupportedPrecompile, run(a, precompileAddr(8), "")); // bn254 pairing
    try testing.expectError(error.UnsupportedPrecompile, run(a, precompileAddr(9), "")); // blake2f
}

test "precompile: ripemd160 hashes 'abc' with left-padded output" {
    const a = testing.allocator;
    const r = try run(a, precompileAddr(3), "abc");
    defer a.free(r.output);
    try testing.expectEqual(@as(usize, 32), r.output.len);
    try testing.expectEqual(@as(u64, 600 + 120), r.gas); // 3 bytes -> 1 word
    var expected: [20]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc");
    try testing.expectEqualSlices(u8, &expected, r.output[12..32]);
    for (r.output[0..12]) |b| try testing.expectEqual(@as(u8, 0), b);
}

test "precompile: ecrecover recovers the signer address" {
    const a = testing.allocator;
    var input: [128]u8 = undefined;
    _ = try std.fmt.hexToBytes(input[0..32], "456e9aea5e197a1f1af7a3e85a3212fa4049a3ba34c2289b4c860fc0b0c64ef3");
    @memset(input[32..64], 0);
    input[63] = 28; // v
    _ = try std.fmt.hexToBytes(input[64..96], "9242685bf161793cc25603c231bc2f568eb630ea16aa137d2664ac8038825608"); // r
    _ = try std.fmt.hexToBytes(input[96..128], "4f8ae3bd7535248d0bd448298cc2e2071e56992d0774dc340c368ae950852ada"); // s

    const r = try run(a, precompileAddr(1), &input);
    defer a.free(r.output);
    try testing.expectEqual(@as(u64, 3000), r.gas);
    try testing.expectEqual(@as(usize, 32), r.output.len);

    var expected: [20]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, "7156526fbd7a3c72969b54f64e42c10fbb768c8a");
    try testing.expectEqualSlices(u8, &expected, r.output[12..32]);
    // The high 12 bytes are zero padding.
    for (r.output[0..12]) |b| try testing.expectEqual(@as(u8, 0), b);
}

test "precompile: ecrecover returns empty output on invalid signature" {
    const a = testing.allocator;
    var input: [128]u8 = [_]u8{0} ** 128;
    input[63] = 27; // valid v, but r = s = 0 -> invalid
    const r = try run(a, precompileAddr(1), &input);
    defer a.free(r.output);
    try testing.expectEqual(@as(usize, 0), r.output.len);
}

test "precompile: modexp computes base^exp mod m" {
    const a = testing.allocator;
    // Bsize=1, Esize=1, Msize=1, base=3, exp=2, mod=5 -> 3^2 mod 5 = 4.
    const input = [_]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, // Bsize
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, // Esize
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, // Msize
        3, 2, 5, // base, exp, mod
    };
    const r = try run(a, precompileAddr(5), &input);
    defer a.free(r.output);
    try testing.expectEqual(@as(usize, 1), r.output.len);
    try testing.expectEqual(@as(u8, 4), r.output[0]);
    try testing.expectEqual(@as(u64, 200), r.gas); // EIP-2565 floor for this tiny case
}

test "precompile: modexp with a larger modulus (2^16 mod 1000 = 536)" {
    const a = testing.allocator;
    // base=2 (1 byte), exp=16 (1 byte), mod=1000 (2 bytes, 0x03e8) -> 65536 mod 1000 = 536.
    const input = [_]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, // Bsize 1
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, // Esize 1
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, // Msize 2
        2, 16, 0x03, 0xe8, // base=2, exp=16, mod=1000
    };
    const r = try run(a, precompileAddr(5), &input);
    defer a.free(r.output);
    try testing.expectEqual(@as(usize, 2), r.output.len);
    // 536 = 0x0218
    try testing.expectEqual(@as(u8, 0x02), r.output[0]);
    try testing.expectEqual(@as(u8, 0x18), r.output[1]);
}
