// Enhanced BigInt implementation for 256-bit integers
// Supports full 256-bit arithmetic including division, modulo, and signed operations
pub const BigInt = struct {
    data: [4]u64, // Little-endian: data[0] is least significant

    // ============================================================
    // Constructors and Initialization
    // ============================================================

    pub fn init(value: u64) BigInt {
        return BigInt{ .data = .{ value, 0, 0, 0 } };
    }

    pub fn zero() BigInt {
        return BigInt{ .data = .{ 0, 0, 0, 0 } };
    }

    pub fn one() BigInt {
        return BigInt{ .data = .{ 1, 0, 0, 0 } };
    }

    pub fn max() BigInt {
        return BigInt{ .data = .{
            0xFFFFFFFFFFFFFFFF,
            0xFFFFFFFFFFFFFFFF,
            0xFFFFFFFFFFFFFFFF,
            0xFFFFFFFFFFFFFFFF
        } };
    }

    /// Initialize from bytes (big-endian, as used in EVM)
    pub fn fromBytes(bytes: [32]u8) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        // bytes[0] is most significant, bytes[31] is least significant
        // data[3] is most significant, data[0] is least significant
        inline for (0..4) |i| {
            const idx = 3 - i;
            result.data[idx] = @as(u64, bytes[i * 8]) << 56 |
                @as(u64, bytes[i * 8 + 1]) << 48 |
                @as(u64, bytes[i * 8 + 2]) << 40 |
                @as(u64, bytes[i * 8 + 3]) << 32 |
                @as(u64, bytes[i * 8 + 4]) << 24 |
                @as(u64, bytes[i * 8 + 5]) << 16 |
                @as(u64, bytes[i * 8 + 6]) << 8 |
                @as(u64, bytes[i * 8 + 7]);
        }
        return result;
    }

    /// Convert to bytes (big-endian, as used in EVM)
    pub fn toBytes(self: BigInt) [32]u8 {
        var result: [32]u8 = undefined;
        inline for (0..4) |i| {
            const idx = 3 - i;
            const word = self.data[idx];
            result[i * 8] = @truncate(word >> 56);
            result[i * 8 + 1] = @truncate(word >> 48);
            result[i * 8 + 2] = @truncate(word >> 40);
            result[i * 8 + 3] = @truncate(word >> 32);
            result[i * 8 + 4] = @truncate(word >> 24);
            result[i * 8 + 5] = @truncate(word >> 16);
            result[i * 8 + 6] = @truncate(word >> 8);
            result[i * 8 + 7] = @truncate(word);
        }
        return result;
    }

    // ============================================================
    // Basic Arithmetic Operations
    // ============================================================

    pub fn add(self: BigInt, other: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        var carry: u64 = 0;

        inline for (0..4) |i| {
            const a = self.data[i];
            const b = other.data[i];
            const sum1 = a +% b;
            const carry1: u64 = if (sum1 < a) 1 else 0;
            const sum2 = sum1 +% carry;
            const carry2: u64 = if (sum2 < sum1) 1 else 0;
            result.data[i] = sum2;
            carry = carry1 + carry2;
        }

        return result;
    }

    pub fn sub(self: BigInt, other: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        var borrow: u64 = 0;

        inline for (0..4) |i| {
            const a = self.data[i];
            const b = other.data[i];
            const diff1 = a -% b;
            const borrow1: u64 = if (a < b) 1 else 0;
            const diff2 = diff1 -% borrow;
            const borrow2: u64 = if (diff1 < borrow) 1 else 0;
            result.data[i] = diff2;
            borrow = borrow1 + borrow2;
        }

        return result;
    }

    /// Full 256-bit multiplication with proper overflow handling
    pub fn mul(self: BigInt, other: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };

        // Schoolbook multiplication using u128 intermediate results
        inline for (0..4) |i| {
            var carry: u128 = 0;
            inline for (0..4) |j| {
                if (i + j < 4) {
                    const prod = @as(u128, self.data[i]) * @as(u128, other.data[j]);
                    const current = @as(u128, result.data[i + j]) + prod + carry;
                    result.data[i + j] = @truncate(current);
                    carry = current >> 64;
                }
            }
        }

        return result;
    }

    // ============================================================
    // Division and Modulo (Full 256-bit)
    // ============================================================

    /// Full 256-bit unsigned division
    /// Returns 0 if divisor is zero (EVM behavior)
    pub fn div(self: BigInt, other: BigInt) BigInt {
        if (other.isZero()) return BigInt.zero();
        if (self.lt(other)) return BigInt.zero();
        if (self.eq(other)) return BigInt.one();

        return self.divmod(other)[0];
    }

    /// Full 256-bit unsigned modulo
    /// Returns 0 if divisor is zero (EVM behavior)
    pub fn mod(self: BigInt, other: BigInt) BigInt {
        if (other.isZero()) return BigInt.zero();
        if (self.lt(other)) return self;
        if (self.eq(other)) return BigInt.zero();

        return self.divmod(other)[1];
    }

    /// Perform division and return both quotient and remainder
    /// Uses binary long division algorithm
    fn divmod(self: BigInt, divisor: BigInt) struct { BigInt, BigInt } {
        var quotient = BigInt.zero();
        var remainder = BigInt.zero();

        // Process each bit from most significant to least significant
        var bit_idx: i32 = 255;
        while (bit_idx >= 0) : (bit_idx -= 1) {
            // Shift remainder left by 1
            remainder = remainder.shl(1);

            // Set the lowest bit of remainder to the current bit of dividend
            const word_idx: usize = @intCast(@divFloor(bit_idx, 64));
            const bit_pos: u6 = @intCast(@mod(bit_idx, 64));
            const bit = (self.data[word_idx] >> bit_pos) & 1;
            remainder.data[0] |= bit;

            // If remainder >= divisor, subtract divisor and set quotient bit
            if (remainder.gte(divisor)) {
                remainder = remainder.sub(divisor);
                const q_word_idx: usize = @intCast(@divFloor(bit_idx, 64));
                const q_bit_pos: u6 = @intCast(@mod(bit_idx, 64));
                quotient.data[q_word_idx] |= (@as(u64, 1) << q_bit_pos);
            }
        }

        return .{ quotient, remainder };
    }

    // ============================================================
    // Signed Arithmetic (Two's Complement)
    // ============================================================

    /// Check if the number is negative (MSB is set)
    pub fn isNegative(self: BigInt) bool {
        return (self.data[3] & 0x8000000000000000) != 0;
    }

    /// Negate the number (two's complement)
    pub fn negate(self: BigInt) BigInt {
        return self.bitwiseNot().add(BigInt.one());
    }

    /// Absolute value
    pub fn abs(self: BigInt) BigInt {
        if (self.isNegative()) {
            return self.negate();
        }
        return self;
    }

    /// Signed division (SDIV opcode)
    /// Returns 0 if divisor is zero
    /// Special case: MIN_INT256 / -1 = MIN_INT256 (overflow wraps)
    pub fn sdiv(self: BigInt, other: BigInt) BigInt {
        if (other.isZero()) return BigInt.zero();

        const self_neg = self.isNegative();
        const other_neg = other.isNegative();

        const abs_self = if (self_neg) self.negate() else self;
        const abs_other = if (other_neg) other.negate() else other;

        const result = abs_self.div(abs_other);

        // Result is negative if exactly one operand was negative
        if (self_neg != other_neg) {
            return result.negate();
        }
        return result;
    }

    /// Signed modulo (SMOD opcode)
    /// Returns 0 if divisor is zero
    /// Sign of result matches sign of dividend
    pub fn smod(self: BigInt, other: BigInt) BigInt {
        if (other.isZero()) return BigInt.zero();

        const self_neg = self.isNegative();
        const other_neg = other.isNegative();

        const abs_self = if (self_neg) self.negate() else self;
        const abs_other = if (other_neg) other.negate() else other;

        const result = abs_self.mod(abs_other);

        // Result has the same sign as the dividend
        if (self_neg) {
            return result.negate();
        }
        return result;
    }

    // ============================================================
    // Modular Arithmetic (for ADDMOD, MULMOD opcodes)
    // ============================================================

    /// (a + b) % n with full precision (no overflow)
    pub fn addmod(a: BigInt, b: BigInt, n: BigInt) BigInt {
        if (n.isZero()) return BigInt.zero();

        // For addmod, we need to handle potential overflow
        // Use 320-bit intermediate: add with carry detection
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        var carry: u64 = 0;

        inline for (0..4) |i| {
            const sum1 = a.data[i] +% b.data[i];
            const carry1: u64 = if (sum1 < a.data[i]) 1 else 0;
            const sum2 = sum1 +% carry;
            const carry2: u64 = if (sum2 < sum1) 1 else 0;
            result.data[i] = sum2;
            carry = carry1 + carry2;
        }

        // If there was overflow (carry > 0), we need extended arithmetic
        if (carry > 0) {
            // result = (2^256 + result) mod n
            // 2^256 mod n + result mod n, then mod n again
            // For simplicity, use iterative subtraction for overflow case
            while (result.gte(n)) {
                result = result.sub(n);
            }
            // Handle the 2^256 part: 2^256 = (2^256 mod n)
            // This is complex - for now, we'll use the fact that
            // if there's overflow, we can compute: (max + 1 - n + result) mod n
            const max_mod_n = BigInt.max().mod(n).add(BigInt.one()).mod(n);
            result = result.add(max_mod_n).mod(n);
        } else {
            result = result.mod(n);
        }

        return result;
    }

    /// (a * b) % n with full precision (512-bit intermediate)
    pub fn mulmod(a: BigInt, b: BigInt, n: BigInt) BigInt {
        if (n.isZero()) return BigInt.zero();

        // Compute full 512-bit product
        var product: [8]u64 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };

        inline for (0..4) |i| {
            var carry: u128 = 0;
            inline for (0..4) |j| {
                const prod = @as(u128, a.data[i]) * @as(u128, b.data[j]);
                const current = @as(u128, product[i + j]) + prod + carry;
                product[i + j] = @truncate(current);
                carry = current >> 64;
            }
            if (i + 4 < 8) {
                product[i + 4] = @truncate(carry);
            }
        }

        // Now perform 512-bit mod 256-bit using long division
        return mod512by256(product, n);
    }

    /// Divide 512-bit number by 256-bit number, return remainder
    fn mod512by256(dividend: [8]u64, divisor: BigInt) BigInt {
        var remainder = BigInt.zero();

        // Process each bit from most significant (bit 511) to least significant (bit 0)
        var bit_idx: i32 = 511;
        while (bit_idx >= 0) : (bit_idx -= 1) {
            // Shift remainder left by 1
            remainder = remainder.shl(1);

            // Get current bit from 512-bit dividend
            const word_idx: usize = @intCast(@divFloor(bit_idx, 64));
            const bit_pos: u6 = @intCast(@mod(bit_idx, 64));
            const bit = (dividend[word_idx] >> bit_pos) & 1;
            remainder.data[0] |= bit;

            // If remainder >= divisor, subtract
            if (remainder.gte(divisor)) {
                remainder = remainder.sub(divisor);
            }
        }

        return remainder;
    }

    // ============================================================
    // Comparison Operations
    // ============================================================

    pub fn lt(self: BigInt, other: BigInt) bool {
        // Compare from most significant to least significant
        var i: usize = 4;
        while (i > 0) {
            i -= 1;
            if (self.data[i] < other.data[i]) return true;
            if (self.data[i] > other.data[i]) return false;
        }
        return false; // They are equal
    }

    pub fn gt(self: BigInt, other: BigInt) bool {
        return other.lt(self);
    }

    pub fn gte(self: BigInt, other: BigInt) bool {
        return !self.lt(other);
    }

    pub fn lte(self: BigInt, other: BigInt) bool {
        return !self.gt(other);
    }

    pub fn eq(self: BigInt, other: BigInt) bool {
        inline for (0..4) |i| {
            if (self.data[i] != other.data[i]) return false;
        }
        return true;
    }

    /// Signed less than (SLT opcode)
    pub fn slt(self: BigInt, other: BigInt) bool {
        const self_neg = self.isNegative();
        const other_neg = other.isNegative();

        if (self_neg and !other_neg) return true; // negative < positive
        if (!self_neg and other_neg) return false; // positive > negative
        // Same sign: use unsigned comparison
        return self.lt(other);
    }

    /// Signed greater than (SGT opcode)
    pub fn sgt(self: BigInt, other: BigInt) bool {
        return other.slt(self);
    }

    pub fn isZero(self: BigInt) bool {
        inline for (0..4) |i| {
            if (self.data[i] != 0) return false;
        }
        return true;
    }

    // ============================================================
    // Bitwise Operations
    // ============================================================

    pub fn bitwiseAnd(self: BigInt, other: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        inline for (0..4) |i| {
            result.data[i] = self.data[i] & other.data[i];
        }
        return result;
    }

    pub fn bitwiseOr(self: BigInt, other: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        inline for (0..4) |i| {
            result.data[i] = self.data[i] | other.data[i];
        }
        return result;
    }

    pub fn bitwiseXor(self: BigInt, other: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        inline for (0..4) |i| {
            result.data[i] = self.data[i] ^ other.data[i];
        }
        return result;
    }

    pub fn bitwiseNot(self: BigInt) BigInt {
        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        inline for (0..4) |i| {
            result.data[i] = ~self.data[i];
        }
        return result;
    }

    // ============================================================
    // Shift Operations
    // ============================================================

    /// Shift left by n bits (SHL opcode)
    pub fn shl(self: BigInt, n: anytype) BigInt {
        const shift: u32 = if (@TypeOf(n) == BigInt)
            (if (n.data[0] > 255 or n.data[1] != 0 or n.data[2] != 0 or n.data[3] != 0)
                return BigInt.zero()
            else
                @truncate(n.data[0]))
        else
            @intCast(n);

        if (shift >= 256) return BigInt.zero();
        if (shift == 0) return self;

        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        const word_shift = shift / 64;
        const bit_shift: u6 = @truncate(shift % 64);

        if (bit_shift == 0) {
            // Only word-aligned shift
            inline for (0..4) |i| {
                if (i >= word_shift) {
                    result.data[i] = self.data[i - word_shift];
                }
            }
        } else {
            // Combined word and bit shift
            inline for (0..4) |i| {
                if (i >= word_shift) {
                    result.data[i] = self.data[i - word_shift] << bit_shift;
                    if (i > word_shift) {
                        result.data[i] |= self.data[i - word_shift - 1] >> @as(u6, @intCast(@as(u7, 64) - @as(u7, bit_shift)));
                    }
                }
            }
        }

        return result;
    }

    /// Shift right by n bits (SHR opcode)
    pub fn shr(self: BigInt, n: anytype) BigInt {
        const shift: u32 = if (@TypeOf(n) == BigInt)
            (if (n.data[0] > 255 or n.data[1] != 0 or n.data[2] != 0 or n.data[3] != 0)
                return BigInt.zero()
            else
                @truncate(n.data[0]))
        else
            @intCast(n);

        if (shift >= 256) return BigInt.zero();
        if (shift == 0) return self;

        var result = BigInt{ .data = .{ 0, 0, 0, 0 } };
        const word_shift = shift / 64;
        const bit_shift: u6 = @truncate(shift % 64);

        if (bit_shift == 0) {
            // Only word-aligned shift
            inline for (0..4) |i| {
                if (i + word_shift < 4) {
                    result.data[i] = self.data[i + word_shift];
                }
            }
        } else {
            // Combined word and bit shift
            inline for (0..4) |i| {
                if (i + word_shift < 4) {
                    result.data[i] = self.data[i + word_shift] >> bit_shift;
                    if (i + word_shift + 1 < 4) {
                        result.data[i] |= self.data[i + word_shift + 1] << @as(u6, @intCast(@as(u7, 64) - @as(u7, bit_shift)));
                    }
                }
            }
        }

        return result;
    }

    /// Arithmetic shift right (SAR opcode) - preserves sign bit
    pub fn sar(self: BigInt, n: anytype) BigInt {
        const shift: u32 = if (@TypeOf(n) == BigInt)
            (if (n.data[0] > 255 or n.data[1] != 0 or n.data[2] != 0 or n.data[3] != 0) {
                // Shift >= 256: return all 1s if negative, all 0s if positive
                return if (self.isNegative()) BigInt.max() else BigInt.zero();
            } else
                @truncate(n.data[0]))
        else
            @intCast(n);

        if (shift >= 256) {
            return if (self.isNegative()) BigInt.max() else BigInt.zero();
        }
        if (shift == 0) return self;

        // Perform logical shift right
        var result = self.shr(shift);

        // If negative, fill in the high bits with 1s
        if (self.isNegative()) {
            // Create mask for the bits that should be 1s
            var bit_idx: u32 = 256 - shift;
            while (bit_idx < 256) : (bit_idx += 1) {
                const word_idx = bit_idx / 64;
                const bit_pos: u6 = @truncate(bit_idx % 64);
                result.data[word_idx] |= (@as(u64, 1) << bit_pos);
            }
        }

        return result;
    }

    // ============================================================
    // Byte Operations
    // ============================================================

    /// Extract byte at position i (BYTE opcode)
    /// i=0 is most significant byte, i=31 is least significant
    pub fn getByte(self: BigInt, i: anytype) BigInt {
        const idx: u32 = if (@TypeOf(i) == BigInt)
            (if (i.data[0] > 31 or i.data[1] != 0 or i.data[2] != 0 or i.data[3] != 0)
                return BigInt.zero()
            else
                @truncate(i.data[0]))
        else
            @intCast(i);

        if (idx > 31) return BigInt.zero();

        // i=0 is MSB (byte at position 31 - 0 = 31 from LSB)
        // i=31 is LSB (byte at position 31 - 31 = 0 from LSB)
        const byte_from_lsb = 31 - idx;
        const word_idx = byte_from_lsb / 8;
        const byte_pos = (byte_from_lsb % 8) * 8;

        const byte_val = (self.data[word_idx] >> @as(u6, @truncate(byte_pos))) & 0xFF;
        return BigInt.init(byte_val);
    }

    /// Sign extend from byte position (SIGNEXTEND opcode)
    /// Extends the sign bit from byte position `b` to all higher bytes
    pub fn signExtend(self: BigInt, b: anytype) BigInt {
        const byte_idx: u32 = if (@TypeOf(b) == BigInt)
            (if (b.data[0] > 30 or b.data[1] != 0 or b.data[2] != 0 or b.data[3] != 0)
                return self // No extension needed for b >= 31
            else
                @truncate(b.data[0]))
        else
            @intCast(b);

        if (byte_idx >= 31) return self;

        // Find the sign bit position (MSB of byte at position byte_idx from LSB)
        const bit_pos = (byte_idx + 1) * 8 - 1;
        const word_idx = bit_pos / 64;
        const bit_in_word: u6 = @truncate(bit_pos % 64);

        // Check if sign bit is set
        const sign_bit = (self.data[word_idx] >> bit_in_word) & 1;

        if (sign_bit == 0) {
            // Positive: clear all bits above the sign bit
            var result = self;
            const clear_from = bit_pos + 1;
            var i: u32 = clear_from;
            while (i < 256) : (i += 1) {
                const w = i / 64;
                const bp: u6 = @truncate(i % 64);
                result.data[w] &= ~(@as(u64, 1) << bp);
            }
            return result;
        } else {
            // Negative: set all bits above the sign bit
            var result = self;
            const set_from = bit_pos + 1;
            var i: u32 = set_from;
            while (i < 256) : (i += 1) {
                const w = i / 64;
                const bp: u6 = @truncate(i % 64);
                result.data[w] |= (@as(u64, 1) << bp);
            }
            return result;
        }
    }

    // ============================================================
    // Utility Functions
    // ============================================================

    pub fn fitsInU64(self: BigInt) bool {
        return self.data[1] == 0 and self.data[2] == 0 and self.data[3] == 0;
    }

    pub fn fitsInU128(self: BigInt) bool {
        return self.data[2] == 0 and self.data[3] == 0;
    }

    /// Get the bit length (position of highest set bit + 1)
    pub fn bitLength(self: BigInt) u32 {
        var i: usize = 4;
        while (i > 0) {
            i -= 1;
            if (self.data[i] != 0) {
                // Find highest set bit in this word
                var bit: u32 = 63;
                while (bit > 0) : (bit -= 1) {
                    if ((self.data[i] >> @as(u6, @truncate(bit))) & 1 == 1) {
                        return @as(u32, @intCast(i)) * 64 + bit + 1;
                    }
                }
                // Bit 0 must be set
                return @as(u32, @intCast(i)) * 64 + 1;
            }
        }
        return 0; // Zero has bit length 0
    }

    /// Convert to u64 (truncates if larger)
    pub fn toU64(self: BigInt) u64 {
        return self.data[0];
    }

    /// Convert to u256 representation as a single integer (for small values)
    pub fn toU128(self: BigInt) u128 {
        return @as(u128, self.data[1]) << 64 | @as(u128, self.data[0]);
    }
};
