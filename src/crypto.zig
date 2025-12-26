// File: src/crypto.zig
// Keccak-256 implementation for Ethereum
// This is the original Keccak-256, NOT SHA3-256 (NIST standardized version)
// Ethereum uses Keccak-256 with the original padding scheme

const std = @import("std");

/// Keccak-256 hash function (Ethereum variant)
pub fn keccak256(data: []const u8) [32]u8 {
    var state = KeccakState{};
    state.absorb(data);
    return state.squeeze();
}

/// Keccak-256 state (1600-bit state = 25 x 64-bit words)
const KeccakState = struct {
    state: [25]u64 = [_]u64{0} ** 25,
    buffer: [136]u8 = undefined, // Rate for Keccak-256 = 1088 bits = 136 bytes
    buffer_len: usize = 0,

    const RATE = 136; // Rate in bytes (1088 bits)
    const ROUNDS = 24;

    // Round constants
    const RC: [24]u64 = .{
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    };

    // Rotation offsets
    const ROTATIONS: [25]u6 = .{
        0,  1,  62, 28, 27,
        36, 44, 6,  55, 20,
        3,  10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2,  61, 56, 14,
    };

    fn absorb(self: *KeccakState, data: []const u8) void {
        var offset: usize = 0;

        while (offset < data.len) {
            const available = RATE - self.buffer_len;
            const to_copy = @min(available, data.len - offset);

            @memcpy(self.buffer[self.buffer_len..][0..to_copy], data[offset..][0..to_copy]);
            self.buffer_len += to_copy;
            offset += to_copy;

            if (self.buffer_len == RATE) {
                self.absorbBlock();
                self.buffer_len = 0;
            }
        }
    }

    fn absorbBlock(self: *KeccakState) void {
        // XOR block into state (little-endian)
        for (0..17) |i| { // 136 bytes / 8 = 17 u64s
            const word = std.mem.readInt(u64, self.buffer[i * 8 ..][0..8], .little);
            self.state[i] ^= word;
        }
        self.keccakF();
    }

    fn squeeze(self: *KeccakState) [32]u8 {
        // Apply Keccak padding (0x01 for Keccak, NOT 0x06 for SHA3)
        self.buffer[self.buffer_len] = 0x01;
        @memset(self.buffer[self.buffer_len + 1 .. RATE - 1], 0);
        self.buffer[RATE - 1] |= 0x80;

        self.absorbBlock();

        // Extract 256 bits (32 bytes) from state
        var result: [32]u8 = undefined;
        for (0..4) |i| {
            std.mem.writeInt(u64, result[i * 8 ..][0..8], self.state[i], .little);
        }
        return result;
    }

    fn keccakF(self: *KeccakState) void {
        var s = &self.state;

        for (0..ROUNDS) |round| {
            // θ (theta) step
            var c: [5]u64 = undefined;
            var d: [5]u64 = undefined;

            for (0..5) |x| {
                c[x] = s[x] ^ s[x + 5] ^ s[x + 10] ^ s[x + 15] ^ s[x + 20];
            }

            for (0..5) |x| {
                d[x] = c[(x + 4) % 5] ^ std.math.rotl(u64, c[(x + 1) % 5], 1);
            }

            for (0..5) |x| {
                for (0..5) |y| {
                    s[x + y * 5] ^= d[x];
                }
            }

            // ρ (rho) and π (pi) steps combined
            var b: [25]u64 = undefined;
            for (0..25) |i| {
                const x = i % 5;
                const y = i / 5;
                const new_x = y;
                const new_y = (2 * x + 3 * y) % 5;
                b[new_x + new_y * 5] = std.math.rotl(u64, s[i], ROTATIONS[i]);
            }

            // χ (chi) step
            for (0..5) |y| {
                for (0..5) |x| {
                    s[x + y * 5] = b[x + y * 5] ^ (~b[(x + 1) % 5 + y * 5] & b[(x + 2) % 5 + y * 5]);
                }
            }

            // ι (iota) step
            s[0] ^= RC[round];
        }
    }
};

// ============================================================
// Helper functions for address derivation
// ============================================================

/// Compute address from CREATE: keccak256(rlp([sender, nonce]))[12:]
pub fn createAddress(sender: [20]u8, nonce: u64) [20]u8 {
    // RLP encode [sender, nonce]
    var rlp_buffer: [64]u8 = undefined;
    var rlp_len: usize = 0;

    // RLP list prefix (will be updated)
    const list_start = rlp_len;
    rlp_len += 1;

    // RLP encode sender (20 bytes, so 0x80 + 20 = 0x94 prefix)
    rlp_buffer[rlp_len] = 0x94;
    rlp_len += 1;
    @memcpy(rlp_buffer[rlp_len..][0..20], &sender);
    rlp_len += 20;

    // RLP encode nonce
    if (nonce == 0) {
        rlp_buffer[rlp_len] = 0x80; // Empty byte string
        rlp_len += 1;
    } else if (nonce < 128) {
        rlp_buffer[rlp_len] = @truncate(nonce);
        rlp_len += 1;
    } else {
        // Count bytes needed for nonce
        var temp_nonce = nonce;
        var nonce_bytes: usize = 0;
        while (temp_nonce > 0) : (temp_nonce >>= 8) {
            nonce_bytes += 1;
        }
        rlp_buffer[rlp_len] = @truncate(0x80 + nonce_bytes);
        rlp_len += 1;
        // Write nonce bytes (big-endian)
        var i: usize = nonce_bytes;
        temp_nonce = nonce;
        while (i > 0) {
            i -= 1;
            rlp_buffer[rlp_len + i] = @truncate(temp_nonce);
            temp_nonce >>= 8;
        }
        rlp_len += nonce_bytes;
    }

    // Update list prefix
    const list_len = rlp_len - list_start - 1;
    if (list_len < 56) {
        rlp_buffer[list_start] = @truncate(0xc0 + list_len);
    } else {
        // For longer lists, would need length-of-length encoding
        // But sender(21) + nonce(max 9) = 30, always < 56
        rlp_buffer[list_start] = @truncate(0xc0 + list_len);
    }

    // Hash and take last 20 bytes
    const hash = keccak256(rlp_buffer[0..rlp_len]);
    var address: [20]u8 = undefined;
    @memcpy(&address, hash[12..32]);
    return address;
}

/// Compute address from CREATE2: keccak256(0xff ++ sender ++ salt ++ keccak256(init_code))[12:]
pub fn create2Address(sender: [20]u8, salt: [32]u8, init_code: []const u8) [20]u8 {
    // Hash the init code
    const code_hash = keccak256(init_code);

    // Construct: 0xff ++ sender ++ salt ++ code_hash
    var buffer: [1 + 20 + 32 + 32]u8 = undefined;
    buffer[0] = 0xff;
    @memcpy(buffer[1..21], &sender);
    @memcpy(buffer[21..53], &salt);
    @memcpy(buffer[53..85], &code_hash);

    // Hash and take last 20 bytes
    const hash = keccak256(&buffer);
    var address: [20]u8 = undefined;
    @memcpy(&address, hash[12..32]);
    return address;
}

// ============================================================
// Tests
// ============================================================

test "keccak256 empty string" {
    const hash = keccak256("");
    // keccak256("") = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
    const expected = [_]u8{
        0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c,
        0x92, 0x7e, 0x7d, 0xb2, 0xdc, 0xc7, 0x03, 0xc0,
        0xe5, 0x00, 0xb6, 0x53, 0xca, 0x82, 0x27, 0x3b,
        0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85, 0xa4, 0x70,
    };
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "keccak256 hello" {
    const hash = keccak256("hello");
    // keccak256("hello") = 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8
    const expected = [_]u8{
        0x1c, 0x8a, 0xff, 0x95, 0x06, 0x85, 0xc2, 0xed,
        0x4b, 0xc3, 0x17, 0x4f, 0x34, 0x72, 0x28, 0x7b,
        0x56, 0xd9, 0x51, 0x7b, 0x9c, 0x94, 0x81, 0x27,
        0x31, 0x9a, 0x09, 0xa7, 0xa3, 0x6d, 0xea, 0xc8,
    };
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "keccak256 longer message" {
    const hash = keccak256("The quick brown fox jumps over the lazy dog");
    // Known hash value
    const expected = [_]u8{
        0x4d, 0x74, 0x1b, 0x6f, 0x1e, 0xb2, 0x9c, 0xb2,
        0xa9, 0xb9, 0x91, 0x1c, 0x82, 0xf5, 0x6f, 0xa8,
        0xd7, 0x3b, 0x04, 0x95, 0x9d, 0x3d, 0x9d, 0x22,
        0x28, 0x95, 0xdf, 0x6c, 0x0b, 0x28, 0xaa, 0x15,
    };
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}
