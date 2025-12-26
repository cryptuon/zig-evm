const std = @import("std");
const expect = std.testing.expect;
const BigInt = @import("../src/bigint.zig").BigInt;

// ============================================================
// Basic Initialization Tests
// ============================================================

test "BigInt initialization" {
    const a = BigInt.init(42);
    try expect(a.data[0] == 42);
    try expect(a.data[1] == 0);
    try expect(a.data[2] == 0);
    try expect(a.data[3] == 0);
}

test "BigInt zero and one" {
    const zero = BigInt.zero();
    const one = BigInt.one();
    try expect(zero.isZero());
    try expect(!one.isZero());
    try expect(one.data[0] == 1);
}

test "BigInt max" {
    const max_val = BigInt.max();
    try expect(max_val.data[0] == 0xFFFFFFFFFFFFFFFF);
    try expect(max_val.data[1] == 0xFFFFFFFFFFFFFFFF);
    try expect(max_val.data[2] == 0xFFFFFFFFFFFFFFFF);
    try expect(max_val.data[3] == 0xFFFFFFFFFFFFFFFF);
}

// ============================================================
// Addition Tests
// ============================================================

test "BigInt addition" {
    const a = BigInt.init(10);
    const b = BigInt.init(20);
    const result = a.add(b);
    try expect(result.data[0] == 30);
}

test "BigInt addition with carry" {
    const a = BigInt{ .data = .{ 0xFFFFFFFFFFFFFFFF, 0, 0, 0 } };
    const b = BigInt.init(1);
    const result = a.add(b);
    try expect(result.data[0] == 0);
    try expect(result.data[1] == 1);
}

test "BigInt addition multi-word carry" {
    const a = BigInt{ .data = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0, 0 } };
    const b = BigInt.init(1);
    const result = a.add(b);
    try expect(result.data[0] == 0);
    try expect(result.data[1] == 0);
    try expect(result.data[2] == 1);
}

// ============================================================
// Subtraction Tests
// ============================================================

test "BigInt subtraction" {
    const a = BigInt.init(30);
    const b = BigInt.init(10);
    const result = a.sub(b);
    try expect(result.data[0] == 20);
}

test "BigInt subtraction with borrow" {
    const a = BigInt{ .data = .{ 0, 1, 0, 0 } };
    const b = BigInt.init(1);
    const result = a.sub(b);
    try expect(result.data[0] == 0xFFFFFFFFFFFFFFFF);
    try expect(result.data[1] == 0);
}

// ============================================================
// Multiplication Tests
// ============================================================

test "BigInt multiplication" {
    const a = BigInt.init(5);
    const b = BigInt.init(7);
    const result = a.mul(b);
    try expect(result.data[0] == 35);
}

test "BigInt multiplication with overflow to second word" {
    const a = BigInt.init(0xFFFFFFFFFFFFFFFF);
    const b = BigInt.init(2);
    const result = a.mul(b);
    try expect(result.data[0] == 0xFFFFFFFFFFFFFFFE);
    try expect(result.data[1] == 1);
}

test "BigInt multiplication large numbers" {
    // 2^64 * 2^64 = 2^128
    const a = BigInt{ .data = .{ 0, 1, 0, 0 } }; // 2^64
    const b = BigInt{ .data = .{ 0, 1, 0, 0 } }; // 2^64
    const result = a.mul(b);
    try expect(result.data[0] == 0);
    try expect(result.data[1] == 0);
    try expect(result.data[2] == 1);
}

// ============================================================
// Division Tests (Full 256-bit)
// ============================================================

test "BigInt division simple" {
    const a = BigInt.init(100);
    const b = BigInt.init(10);
    const result = a.div(b);
    try expect(result.data[0] == 10);
}

test "BigInt division by zero returns zero" {
    const a = BigInt.init(100);
    const b = BigInt.zero();
    const result = a.div(b);
    try expect(result.isZero());
}

test "BigInt division smaller by larger returns zero" {
    const a = BigInt.init(5);
    const b = BigInt.init(10);
    const result = a.div(b);
    try expect(result.isZero());
}

test "BigInt division equal numbers" {
    const a = BigInt.init(42);
    const b = BigInt.init(42);
    const result = a.div(b);
    try expect(result.data[0] == 1);
}

test "BigInt division large numbers" {
    // 2^128 / 2^64 = 2^64
    const a = BigInt{ .data = .{ 0, 0, 1, 0 } }; // 2^128
    const b = BigInt{ .data = .{ 0, 1, 0, 0 } }; // 2^64
    const result = a.div(b);
    try expect(result.data[0] == 0);
    try expect(result.data[1] == 1); // Result is 2^64
}

test "BigInt division 256-bit by 128-bit" {
    // Large dividend divided by smaller divisor
    const a = BigInt{ .data = .{ 0, 0, 0, 1 } }; // 2^192
    const b = BigInt{ .data = .{ 0, 1, 0, 0 } }; // 2^64
    const result = a.div(b);
    try expect(result.data[0] == 0);
    try expect(result.data[1] == 0);
    try expect(result.data[2] == 1); // 2^192 / 2^64 = 2^128
}

// ============================================================
// Modulo Tests (Full 256-bit)
// ============================================================

test "BigInt modulo simple" {
    const a = BigInt.init(17);
    const b = BigInt.init(5);
    const result = a.mod(b);
    try expect(result.data[0] == 2);
}

test "BigInt modulo by zero returns zero" {
    const a = BigInt.init(100);
    const b = BigInt.zero();
    const result = a.mod(b);
    try expect(result.isZero());
}

test "BigInt modulo smaller by larger returns self" {
    const a = BigInt.init(5);
    const b = BigInt.init(10);
    const result = a.mod(b);
    try expect(result.data[0] == 5);
}

test "BigInt modulo equal numbers returns zero" {
    const a = BigInt.init(42);
    const b = BigInt.init(42);
    const result = a.mod(b);
    try expect(result.isZero());
}

test "BigInt modulo large numbers" {
    // 2^128 + 5 mod 2^64 = 5
    var a = BigInt{ .data = .{ 5, 0, 1, 0 } };
    const b = BigInt{ .data = .{ 0, 1, 0, 0 } }; // 2^64
    const result = a.mod(b);
    try expect(result.data[0] == 5);
    _ = &a;
}

// ============================================================
// Signed Arithmetic Tests
// ============================================================

test "BigInt isNegative" {
    const positive = BigInt.init(42);
    const negative = BigInt{ .data = .{ 0, 0, 0, 0x8000000000000000 } };
    try expect(!positive.isNegative());
    try expect(negative.isNegative());
}

test "BigInt negate" {
    const a = BigInt.init(42);
    const neg_a = a.negate();
    const back = neg_a.negate();
    try expect(back.eq(a));
}

test "BigInt signed division positive" {
    const a = BigInt.init(100);
    const b = BigInt.init(10);
    const result = a.sdiv(b);
    try expect(result.data[0] == 10);
}

test "BigInt signed division negative dividend" {
    const a = BigInt.init(100).negate(); // -100
    const b = BigInt.init(10);
    const result = a.sdiv(b);
    // Result should be -10
    try expect(result.isNegative());
    try expect(result.negate().data[0] == 10);
}

test "BigInt signed division negative divisor" {
    const a = BigInt.init(100);
    const b = BigInt.init(10).negate(); // -10
    const result = a.sdiv(b);
    // Result should be -10
    try expect(result.isNegative());
    try expect(result.negate().data[0] == 10);
}

test "BigInt signed division both negative" {
    const a = BigInt.init(100).negate(); // -100
    const b = BigInt.init(10).negate(); // -10
    const result = a.sdiv(b);
    // Result should be +10
    try expect(!result.isNegative());
    try expect(result.data[0] == 10);
}

test "BigInt signed modulo" {
    const a = BigInt.init(17).negate(); // -17
    const b = BigInt.init(5);
    const result = a.smod(b);
    // Result should be -2 (sign matches dividend)
    try expect(result.isNegative());
    try expect(result.negate().data[0] == 2);
}

// ============================================================
// Comparison Tests
// ============================================================

test "BigInt comparison" {
    const a = BigInt.init(10);
    const b = BigInt.init(20);
    const c = BigInt.init(10);

    try expect(a.lt(b));
    try expect(!b.lt(a));
    try expect(!a.lt(c));
}

test "BigInt large number comparison" {
    const a = BigInt{ .data = .{ 0, 0, 0, 1 } };
    const b = BigInt{ .data = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0 } };

    try expect(b.lt(a));
    try expect(!a.lt(b));
}

test "BigInt gte and lte" {
    const a = BigInt.init(10);
    const b = BigInt.init(10);
    const c = BigInt.init(20);

    try expect(a.gte(b));
    try expect(a.lte(b));
    try expect(c.gte(a));
    try expect(a.lte(c));
}

test "BigInt signed comparison slt" {
    const positive = BigInt.init(10);
    const negative = BigInt.init(10).negate();

    try expect(negative.slt(positive)); // negative < positive
    try expect(!positive.slt(negative));
}

// ============================================================
// Bitwise Operations Tests
// ============================================================

test "BigInt bitwise AND" {
    const a = BigInt.init(0xFF00);
    const b = BigInt.init(0x0FF0);
    const result = a.bitwiseAnd(b);
    try expect(result.data[0] == 0x0F00);
}

test "BigInt bitwise OR" {
    const a = BigInt.init(0xFF00);
    const b = BigInt.init(0x00FF);
    const result = a.bitwiseOr(b);
    try expect(result.data[0] == 0xFFFF);
}

test "BigInt bitwise XOR" {
    const a = BigInt.init(0xFF00);
    const b = BigInt.init(0xF0F0);
    const result = a.bitwiseXor(b);
    try expect(result.data[0] == 0x0FF0);
}

test "BigInt bitwise NOT" {
    const a = BigInt.init(0);
    const result = a.bitwiseNot();
    try expect(result.data[0] == 0xFFFFFFFFFFFFFFFF);
    try expect(result.data[1] == 0xFFFFFFFFFFFFFFFF);
    try expect(result.data[2] == 0xFFFFFFFFFFFFFFFF);
    try expect(result.data[3] == 0xFFFFFFFFFFFFFFFF);
}

// ============================================================
// Shift Operations Tests
// ============================================================

test "BigInt shift left" {
    const a = BigInt.init(1);
    const result = a.shl(64);
    try expect(result.data[0] == 0);
    try expect(result.data[1] == 1);
}

test "BigInt shift left partial" {
    const a = BigInt.init(1);
    const result = a.shl(4);
    try expect(result.data[0] == 16);
}

test "BigInt shift left large" {
    const a = BigInt.init(1);
    const result = a.shl(192);
    try expect(result.data[0] == 0);
    try expect(result.data[1] == 0);
    try expect(result.data[2] == 0);
    try expect(result.data[3] == 1);
}

test "BigInt shift left overflow returns zero" {
    const a = BigInt.init(1);
    const result = a.shl(256);
    try expect(result.isZero());
}

test "BigInt shift right" {
    const a = BigInt{ .data = .{ 0, 1, 0, 0 } };
    const result = a.shr(64);
    try expect(result.data[0] == 1);
    try expect(result.data[1] == 0);
}

test "BigInt shift right partial" {
    const a = BigInt.init(16);
    const result = a.shr(4);
    try expect(result.data[0] == 1);
}

test "BigInt arithmetic shift right positive" {
    const a = BigInt.init(16);
    const result = a.sar(2);
    try expect(result.data[0] == 4);
}

test "BigInt arithmetic shift right negative" {
    // -16 >> 2 should be -4 (sign extended)
    const a = BigInt.init(16).negate();
    const result = a.sar(2);
    try expect(result.isNegative());
    try expect(result.negate().data[0] == 4);
}

// ============================================================
// Byte Operations Tests
// ============================================================

test "BigInt getByte" {
    // Create a value where each byte is distinct
    const a = BigInt{ .data = .{ 0x0706050403020100, 0x0F0E0D0C0B0A0908, 0x1716151413121110, 0x1F1E1D1C1B1A1918 } };

    // Byte 31 (LSB) should be 0x00
    try expect(a.getByte(31).data[0] == 0x00);
    // Byte 0 (MSB) should be 0x1F
    try expect(a.getByte(0).data[0] == 0x1F);
    // Byte 30 should be 0x01
    try expect(a.getByte(30).data[0] == 0x01);
}

test "BigInt getByte out of range returns zero" {
    const a = BigInt.init(0xFF);
    try expect(a.getByte(32).isZero());
    try expect(a.getByte(100).isZero());
}

test "BigInt signExtend positive" {
    // Small positive number, extend from byte 0
    const a = BigInt.init(0x7F); // 127, MSB of byte is 0
    const result = a.signExtend(0);
    try expect(result.data[0] == 0x7F);
    try expect(!result.isNegative());
}

test "BigInt signExtend negative" {
    // Small negative number (in byte 0), extend from byte 0
    const a = BigInt.init(0xFF); // -1 in signed byte, MSB is 1
    const result = a.signExtend(0);
    // Should extend 1s to fill all upper bits
    try expect(result.isNegative());
    try expect(result.data[0] == 0xFFFFFFFFFFFFFFFF);
}

// ============================================================
// Modular Arithmetic Tests
// ============================================================

test "BigInt addmod simple" {
    const a = BigInt.init(10);
    const b = BigInt.init(10);
    const n = BigInt.init(8);
    const result = BigInt.addmod(a, b, n);
    try expect(result.data[0] == 4); // (10 + 10) % 8 = 4
}

test "BigInt addmod with zero modulus returns zero" {
    const a = BigInt.init(10);
    const b = BigInt.init(10);
    const n = BigInt.zero();
    const result = BigInt.addmod(a, b, n);
    try expect(result.isZero());
}

test "BigInt mulmod simple" {
    const a = BigInt.init(10);
    const b = BigInt.init(10);
    const n = BigInt.init(8);
    const result = BigInt.mulmod(a, b, n);
    try expect(result.data[0] == 4); // (10 * 10) % 8 = 100 % 8 = 4
}

test "BigInt mulmod with zero modulus returns zero" {
    const a = BigInt.init(10);
    const b = BigInt.init(10);
    const n = BigInt.zero();
    const result = BigInt.mulmod(a, b, n);
    try expect(result.isZero());
}

test "BigInt mulmod large numbers" {
    // Test with numbers that overflow 256 bits when multiplied
    const a = BigInt{ .data = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0, 0 } };
    const b = BigInt{ .data = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0, 0 } };
    const n = BigInt.init(1000000007);
    const result = BigInt.mulmod(a, b, n);
    // Result should be less than n
    try expect(result.lt(n));
}

// ============================================================
// Bytes Conversion Tests
// ============================================================

test "BigInt toBytes and fromBytes roundtrip" {
    const original = BigInt{ .data = .{ 0x0123456789ABCDEF, 0xFEDCBA9876543210, 0x1111111111111111, 0x2222222222222222 } };
    const bytes = original.toBytes();
    const restored = BigInt.fromBytes(bytes);
    try expect(original.eq(restored));
}

test "BigInt toBytes big-endian order" {
    const a = BigInt.init(0x0102030405060708);
    const bytes = a.toBytes();
    // LSB should be at byte[31]
    try expect(bytes[31] == 0x08);
    try expect(bytes[30] == 0x07);
    try expect(bytes[24] == 0x01);
}

// ============================================================
// Utility Function Tests
// ============================================================

test "BigInt fitsInU64" {
    const small = BigInt.init(100);
    const large = BigInt{ .data = .{ 0, 1, 0, 0 } };
    try expect(small.fitsInU64());
    try expect(!large.fitsInU64());
}

test "BigInt fitsInU128" {
    const small = BigInt{ .data = .{ 100, 200, 0, 0 } };
    const large = BigInt{ .data = .{ 0, 0, 1, 0 } };
    try expect(small.fitsInU128());
    try expect(!large.fitsInU128());
}

test "BigInt bitLength" {
    try expect(BigInt.init(0).bitLength() == 0);
    try expect(BigInt.init(1).bitLength() == 1);
    try expect(BigInt.init(2).bitLength() == 2);
    try expect(BigInt.init(255).bitLength() == 8);
    try expect(BigInt.init(256).bitLength() == 9);
}
