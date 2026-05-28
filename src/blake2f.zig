// File: src/blake2f.zig
//
// Blake2b compression function with a configurable round count, as exposed by
// the precompile at address 0x09 (EIP-152). The Zig standard library has
// Blake2b but not the round-configurable F precompile; this is a direct
// implementation of the spec, verified against the canonical EIP-152 vector.

const std = @import("std");

const IV = [8]u64{
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
};

const SIGMA = [10][16]u8{
    .{ 0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15 },
    .{ 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3 },
    .{ 11,  8, 12,  0,  5,  2, 15, 13, 10, 14,  3,  6,  7,  1,  9,  4 },
    .{  7,  9,  3,  1, 13, 12, 11, 14,  2,  6,  5, 10,  4,  0, 15,  8 },
    .{  9,  0,  5,  7,  2,  4, 10, 15, 14,  1, 11, 12,  6,  8,  3, 13 },
    .{  2, 12,  6, 10,  0, 11,  8,  3,  4, 13,  7,  5, 15, 14,  1,  9 },
    .{ 12,  5,  1, 15, 14, 13,  4, 10,  0,  7,  6,  3,  9,  2,  8, 11 },
    .{ 13, 11,  7, 14, 12,  1,  3,  9,  5,  0, 15,  4,  8,  6,  2, 10 },
    .{  6, 15, 14,  9, 11,  3,  0,  8, 12,  2, 13,  7,  1,  4, 10,  5 },
    .{ 10,  2,  8,  4,  7,  6,  1,  5, 15, 11,  9, 14,  3, 12, 13,  0 },
};

fn G(v: *[16]u64, a: usize, b: usize, c: usize, d: usize, x: u64, y: u64) void {
    v[a] = v[a] +% v[b] +% x;
    v[d] = std.math.rotr(u64, v[d] ^ v[a], @as(u6, 32));
    v[c] = v[c] +% v[d];
    v[b] = std.math.rotr(u64, v[b] ^ v[c], @as(u6, 24));
    v[a] = v[a] +% v[b] +% y;
    v[d] = std.math.rotr(u64, v[d] ^ v[a], @as(u6, 16));
    v[c] = v[c] +% v[d];
    v[b] = std.math.rotr(u64, v[b] ^ v[c], @as(u6, 63));
}

/// Run the Blake2b compression function for `rounds` iterations.
pub fn compress(h: *[8]u64, m: *const [16]u64, t: [2]u64, final: bool, rounds: u32) void {
    var v: [16]u64 = undefined;
    for (0..8) |i| v[i] = h[i];
    for (0..8) |i| v[8 + i] = IV[i];
    v[12] ^= t[0];
    v[13] ^= t[1];
    if (final) v[14] = ~v[14];

    var r: u32 = 0;
    while (r < rounds) : (r += 1) {
        const s = SIGMA[r % 10];
        // column step
        G(&v, 0, 4,  8, 12, m[s[0]],  m[s[1]]);
        G(&v, 1, 5,  9, 13, m[s[2]],  m[s[3]]);
        G(&v, 2, 6, 10, 14, m[s[4]],  m[s[5]]);
        G(&v, 3, 7, 11, 15, m[s[6]],  m[s[7]]);
        // diagonal step
        G(&v, 0, 5, 10, 15, m[s[8]],  m[s[9]]);
        G(&v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
        G(&v, 2, 7,  8, 13, m[s[12]], m[s[13]]);
        G(&v, 3, 4,  9, 14, m[s[14]], m[s[15]]);
    }

    for (0..8) |i| h[i] = h[i] ^ v[i] ^ v[i + 8];
}

/// Parse the 213-byte precompile input and return the 64-byte output. The
/// caller is responsible for charging gas (= rounds, per EIP-152).
pub fn precompile(input: []const u8, output: *[64]u8) !u32 {
    if (input.len != 213) return error.InvalidPrecompileInput;
    if (input[212] != 0 and input[212] != 1) return error.InvalidPrecompileInput;

    const rounds = std.mem.readInt(u32, input[0..4], .big);
    var h: [8]u64 = undefined;
    for (0..8) |i| h[i] = std.mem.readInt(u64, input[4 + i * 8 ..][0..8], .little);
    var m: [16]u64 = undefined;
    for (0..16) |i| m[i] = std.mem.readInt(u64, input[68 + i * 8 ..][0..8], .little);
    const t = [2]u64{
        std.mem.readInt(u64, input[196..204], .little),
        std.mem.readInt(u64, input[204..212], .little),
    };
    const final = input[212] == 1;

    compress(&h, &m, t, final, rounds);

    for (0..8) |i| std.mem.writeInt(u64, output[i * 8 ..][0..8], h[i], .little);
    return rounds;
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

test "blake2f: EIP-152 canonical test vector" {
    var input: [213]u8 = undefined;
    // rounds = 12
    _ = try std.fmt.hexToBytes(input[0..4], "0000000c");
    // h
    _ = try std.fmt.hexToBytes(input[4..68],
        "48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5" ++
        "d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b");
    // m: "abc" + zero-pad to 128 bytes
    @memset(input[68..196], 0);
    input[68] = 0x61;
    input[69] = 0x62;
    input[70] = 0x63;
    // t = (3, 0)
    @memset(input[196..212], 0);
    input[196] = 0x03;
    // final = 1
    input[212] = 0x01;

    var out: [64]u8 = undefined;
    const rounds = try precompile(&input, &out);
    try testing.expectEqual(@as(u32, 12), rounds);

    var expected: [64]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected,
        "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1" ++
        "7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923");
    try testing.expectEqualSlices(u8, &expected, &out);
}

test "blake2f: invalid length is rejected" {
    var out: [64]u8 = undefined;
    try testing.expectError(error.InvalidPrecompileInput, precompile(&[_]u8{}, &out));
}

test "blake2f: invalid final flag (not 0 or 1) is rejected" {
    var input: [213]u8 = [_]u8{0} ** 213;
    input[212] = 2;
    var out: [64]u8 = undefined;
    try testing.expectError(error.InvalidPrecompileInput, precompile(&input, &out));
}
