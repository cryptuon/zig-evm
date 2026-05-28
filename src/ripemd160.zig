// File: src/ripemd160.zig
//
// RIPEMD-160 hash function, 20-byte output. The Zig standard library does not
// ship a RIPEMD implementation; this is a direct transcription of the
// specification (Dobbertin, Bosselaers, Preneel 1996) with both line orderings
// and round constants from the canonical reference.

const std = @import("std");

const INITIAL_STATE: [5]u32 = .{
    0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0,
};

const K_LEFT: [5]u32 = .{ 0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xA953FD4E };
const K_RIGHT: [5]u32 = .{ 0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x7A6D76E9, 0x00000000 };

const R_LEFT = [80]u8{
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    7,  4,  13, 1,  10, 6,  15, 3,  12, 0,  9,  5,  2,  14, 11, 8,
    3,  10, 14, 4,  9,  15, 8,  1,  2,  7,  0,  6,  13, 11, 5,  12,
    1,  9,  11, 10, 0,  8,  12, 4,  13, 3,  7,  15, 14, 5,  6,  2,
    4,  0,  5,  9,  7,  12, 2,  10, 14, 1,  3,  8,  11, 6,  15, 13,
};

const R_RIGHT = [80]u8{
    5,  14, 7,  0,  9,  2,  11, 4,  13, 6,  15, 8,  1,  10, 3,  12,
    6,  11, 3,  7,  0,  13, 5,  10, 14, 15, 8,  12, 4,  9,  1,  2,
    15, 5,  1,  3,  7,  14, 6,  9,  11, 8,  12, 2,  10, 0,  4,  13,
    8,  6,  4,  1,  3,  11, 15, 0,  5,  12, 2,  13, 9,  7,  10, 14,
    12, 15, 10, 4,  1,  5,  8,  7,  6,  2,  13, 14, 0,  3,  9,  11,
};

const S_LEFT = [80]u8{
    11, 14, 15, 12, 5,  8,  7,  9,  11, 13, 14, 15, 6,  7,  9,  8,
    7,  6,  8,  13, 11, 9,  7,  15, 7,  12, 15, 9,  11, 7,  13, 12,
    11, 13, 6,  7,  14, 9,  13, 15, 14, 8,  13, 6,  5,  12, 7,  5,
    11, 12, 14, 15, 14, 15, 9,  8,  9,  14, 5,  6,  8,  6,  5,  12,
    9,  15, 5,  11, 6,  8,  13, 12, 5,  12, 13, 14, 11, 8,  5,  6,
};

const S_RIGHT = [80]u8{
    8,  9,  9,  11, 13, 15, 15, 5,  7,  7,  8,  11, 14, 14, 12, 6,
    9,  13, 15, 7,  12, 8,  9,  11, 7,  7,  12, 7,  6,  15, 13, 11,
    9,  7,  15, 11, 8,  6,  6,  14, 12, 13, 5,  14, 13, 13, 7,  5,
    15, 5,  8,  11, 14, 14, 6,  14, 6,  9,  12, 9,  12, 5,  15, 8,
    8,  5,  12, 9,  12, 5,  14, 6,  8,  13, 6,  5,  15, 13, 11, 11,
};

fn f(round: usize, x: u32, y: u32, z: u32) u32 {
    return switch (round) {
        0 => x ^ y ^ z,
        1 => (x & y) | (~x & z),
        2 => (x | ~y) ^ z,
        3 => (x & z) | (y & ~z),
        4 => x ^ (y | ~z),
        else => unreachable,
    };
}

fn processBlock(state: *[5]u32, block: *const [64]u8) void {
    var x: [16]u32 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        x[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .little);
    }

    var al = state[0]; var bl = state[1]; var cl = state[2]; var dl = state[3]; var el = state[4];
    var ar = state[0]; var br = state[1]; var cr = state[2]; var dr = state[3]; var er = state[4];

    var j: usize = 0;
    while (j < 80) : (j += 1) {
        const round = j / 16;
        const round_r = 4 - round;

        // Left line.
        const tl = std.math.rotl(u32, al +% f(round, bl, cl, dl) +% x[R_LEFT[j]] +% K_LEFT[round], @as(u32, S_LEFT[j])) +% el;
        al = el; el = dl; dl = std.math.rotl(u32, cl, @as(u32, 10)); cl = bl; bl = tl;

        // Right line.
        const tr = std.math.rotl(u32, ar +% f(round_r, br, cr, dr) +% x[R_RIGHT[j]] +% K_RIGHT[round], @as(u32, S_RIGHT[j])) +% er;
        ar = er; er = dr; dr = std.math.rotl(u32, cr, @as(u32, 10)); cr = br; br = tr;
    }

    const t = state[1] +% cl +% dr;
    state[1] = state[2] +% dl +% er;
    state[2] = state[3] +% el +% ar;
    state[3] = state[4] +% al +% br;
    state[4] = state[0] +% bl +% cr;
    state[0] = t;
}

pub fn hash(input: []const u8) [20]u8 {
    var state = INITIAL_STATE;
    var processed: usize = 0;
    while (processed + 64 <= input.len) : (processed += 64) {
        processBlock(&state, input[processed..][0..64]);
    }

    // Padding: 0x80 byte, then zeros, then 64-bit little-endian bit length.
    var pad: [128]u8 = [_]u8{0} ** 128;
    const rem = input.len - processed;
    @memcpy(pad[0..rem], input[processed..]);
    pad[rem] = 0x80;
    const pad_len: usize = if (rem < 56) 64 else 128;
    const bits: u64 = @as(u64, @intCast(input.len)) * 8;
    std.mem.writeInt(u64, pad[pad_len - 8 ..][0..8], bits, .little);
    processBlock(&state, pad[0..64]);
    if (pad_len == 128) processBlock(&state, pad[64..128]);

    var out: [20]u8 = undefined;
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        std.mem.writeInt(u32, out[i * 4 ..][0..4], state[i], .little);
    }
    return out;
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

fn expectHex(expected_hex: []const u8, got: [20]u8) !void {
    var expected: [20]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, expected_hex);
    try testing.expectEqualSlices(u8, &expected, &got);
}

test "ripemd160: empty string" {
    try expectHex("9c1185a5c5e9fc54612808977ee8f548b2258d31", hash(""));
}

test "ripemd160: 'abc'" {
    try expectHex("8eb208f7e05d987a9b044a8e98c6b087f15a0bfc", hash("abc"));
}

test "ripemd160: 'message digest'" {
    try expectHex("5d0689ef49d2fae572b881b123a85ffa21595f36", hash("message digest"));
}

test "ripemd160: '1234567890' x 8 (cross-block input)" {
    // 80 bytes of input -> the message + padding spans two 64-byte blocks.
    const s = "1234567890" ** 8;
    try expectHex("9b752e45573d4b39f4dbd3323cab82bf63326bfb", hash(s));
}
