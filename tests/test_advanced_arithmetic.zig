// File: tests/test_advanced_arithmetic.zig

const std = @import("std");
const testing = std.testing;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/main.zig").BigInt;

test "SMOD: signed modulo operation" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test positive % positive: 7 % 3 = 1
    try evm.stack.push(evm.allocator, BigInt.init(7));
    try evm.stack.push(evm.allocator, BigInt.init(3));

    evm.code = &[_]u8{0x07}; // SMOD
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 1);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "SMOD: signed modulo with negative dividend" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test -7 % 3 = -1 (signed remainder behavior)
    const neg_seven = BigInt.init(@as(u64, @bitCast(@as(i64, -7))));
    try evm.stack.push(evm.allocator, neg_seven);
    try evm.stack.push(evm.allocator, BigInt.init(3));

    evm.code = &[_]u8{0x07}; // SMOD
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    const result_signed = @as(i64, @bitCast(result.data[0]));
    try testing.expect(result_signed == -1);
}

test "SMOD: modulo by zero returns zero" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    try evm.stack.push(evm.allocator, BigInt.init(7));
    try evm.stack.push(evm.allocator, BigInt.init(0));

    evm.code = &[_]u8{0x07}; // SMOD
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "ADDMOD: addition modulo operation" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test (5 + 3) % 4 = 0
    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(3));
    try evm.stack.push(evm.allocator, BigInt.init(4));

    evm.code = &[_]u8{0x08}; // ADDMOD
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "ADDMOD: large numbers modulo" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test (10 + 15) % 7 = 4
    try evm.stack.push(evm.allocator, BigInt.init(10));
    try evm.stack.push(evm.allocator, BigInt.init(15));
    try evm.stack.push(evm.allocator, BigInt.init(7));

    evm.code = &[_]u8{0x08}; // ADDMOD
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 4);
}

test "ADDMOD: modulo by zero returns zero" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(3));
    try evm.stack.push(evm.allocator, BigInt.init(0));

    evm.code = &[_]u8{0x08}; // ADDMOD
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "MULMOD: multiplication modulo operation" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test (3 * 4) % 5 = 2
    try evm.stack.push(evm.allocator, BigInt.init(3));
    try evm.stack.push(evm.allocator, BigInt.init(4));
    try evm.stack.push(evm.allocator, BigInt.init(5));

    evm.code = &[_]u8{0x09}; // MULMOD
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 2);
}

test "MULMOD: large multiplication modulo" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test (7 * 8) % 10 = 6
    try evm.stack.push(evm.allocator, BigInt.init(7));
    try evm.stack.push(evm.allocator, BigInt.init(8));
    try evm.stack.push(evm.allocator, BigInt.init(10));

    evm.code = &[_]u8{0x09}; // MULMOD
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 6);
}

test "MULMOD: modulo by zero returns zero" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    try evm.stack.push(evm.allocator, BigInt.init(3));
    try evm.stack.push(evm.allocator, BigInt.init(4));
    try evm.stack.push(evm.allocator, BigInt.init(0));

    evm.code = &[_]u8{0x09}; // MULMOD
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "EXP: basic exponentiation" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 2^3 = 8
    try evm.stack.push(evm.allocator, BigInt.init(2));
    try evm.stack.push(evm.allocator, BigInt.init(3));

    evm.code = &[_]u8{0x0a}; // EXP
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 8);
}

test "EXP: power of zero" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 5^0 = 1
    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(0));

    evm.code = &[_]u8{0x0a}; // EXP
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 1);
}

test "EXP: zero to positive power" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 0^5 = 0
    try evm.stack.push(evm.allocator, BigInt.init(0));
    try evm.stack.push(evm.allocator, BigInt.init(5));

    evm.code = &[_]u8{0x0a}; // EXP
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "EXP: one to any power" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 1^100 = 1
    try evm.stack.push(evm.allocator, BigInt.init(1));
    try evm.stack.push(evm.allocator, BigInt.init(100));

    evm.code = &[_]u8{0x0a}; // EXP
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 1);
}

test "EXP: large exponent returns zero (gas limit)" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 2^100 = 0 (would exceed gas limit)
    try evm.stack.push(evm.allocator, BigInt.init(2));
    try evm.stack.push(evm.allocator, BigInt.init(100));

    evm.code = &[_]u8{0x0a}; // EXP
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "EXP: overflow protection" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 100^10 (would overflow) = 0
    try evm.stack.push(evm.allocator, BigInt.init(100));
    try evm.stack.push(evm.allocator, BigInt.init(10));

    evm.code = &[_]u8{0x0a}; // EXP
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "SGT: signed greater than comparison - positive numbers" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 10 > 5 = true (1)
    try evm.stack.push(evm.allocator, BigInt.init(10));
    try evm.stack.push(evm.allocator, BigInt.init(5));

    evm.code = &[_]u8{0x13}; // SGT
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 1);
}

test "SGT: signed greater than comparison - equal numbers" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 5 > 5 = false (0)
    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(5));

    evm.code = &[_]u8{0x13}; // SGT
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 0);
}

test "SGT: signed greater than - positive vs negative" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 5 > -3 = true (1)
    const neg_three = BigInt.init(@as(u64, @bitCast(@as(i64, -3))));
    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, neg_three);

    evm.code = &[_]u8{0x13}; // SGT
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 1);
}

test "SGT: signed greater than - negative vs positive" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test -3 > 5 = false (0)
    const neg_three = BigInt.init(@as(u64, @bitCast(@as(i64, -3))));
    try evm.stack.push(evm.allocator, neg_three);
    try evm.stack.push(evm.allocator, BigInt.init(5));

    evm.code = &[_]u8{0x13}; // SGT
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 0);
}

test "SGT: signed greater than - negative numbers" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test -2 > -5 = true (1)
    const neg_two = BigInt.init(@as(u64, @bitCast(@as(i64, -2))));
    const neg_five = BigInt.init(@as(u64, @bitCast(@as(i64, -5))));
    try evm.stack.push(evm.allocator, neg_two);
    try evm.stack.push(evm.allocator, neg_five);

    evm.code = &[_]u8{0x13}; // SGT
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 1);
}