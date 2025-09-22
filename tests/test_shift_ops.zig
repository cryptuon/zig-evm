// File: tests/test_shift_ops.zig

const std = @import("std");
const testing = std.testing;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/main.zig").BigInt;

test "SHL: basic left shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 8 << 2 = 32
    try evm.stack.push(evm.allocator, BigInt.init(8));
    try evm.stack.push(evm.allocator, BigInt.init(2));

    evm.code = &[_]u8{0x1b}; // SHL
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 32);
}

test "SHL: zero shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 42 << 0 = 42
    try evm.stack.push(evm.allocator, BigInt.init(42));
    try evm.stack.push(evm.allocator, BigInt.init(0));

    evm.code = &[_]u8{0x1b}; // SHL
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 42);
}

test "SHL: large shift returns zero" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 42 << 256 = 0
    try evm.stack.push(evm.allocator, BigInt.init(42));
    try evm.stack.push(evm.allocator, BigInt.init(256));

    evm.code = &[_]u8{0x1b}; // SHL
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "SHL: word boundary shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 1 << 64 = 0x10000000000000000 (moves to next word)
    try evm.stack.push(evm.allocator, BigInt.init(1));
    try evm.stack.push(evm.allocator, BigInt.init(64));

    evm.code = &[_]u8{0x1b}; // SHL
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 0);
    try testing.expect(result.data[1] == 1);
}

test "SHR: basic right shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 32 >> 2 = 8
    try evm.stack.push(evm.allocator, BigInt.init(32));
    try evm.stack.push(evm.allocator, BigInt.init(2));

    evm.code = &[_]u8{0x1c}; // SHR
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 8);
}

test "SHR: zero shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 42 >> 0 = 42
    try evm.stack.push(evm.allocator, BigInt.init(42));
    try evm.stack.push(evm.allocator, BigInt.init(0));

    evm.code = &[_]u8{0x1c}; // SHR
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 42);
}

test "SHR: large shift returns zero" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 42 >> 256 = 0
    try evm.stack.push(evm.allocator, BigInt.init(42));
    try evm.stack.push(evm.allocator, BigInt.init(256));

    evm.code = &[_]u8{0x1c}; // SHR
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "SHR: word boundary shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Create BigInt with value in data[1] = 1, then shift right by 64
    var big_value = BigInt.init(0);
    big_value.data[1] = 1; // Value is 2^64

    try evm.stack.push(evm.allocator, big_value);
    try evm.stack.push(evm.allocator, BigInt.init(64));

    evm.code = &[_]u8{0x1c}; // SHR
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 1);
    try testing.expect(result.data[1] == 0);
}

test "SAR: positive number arithmetic right shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 32 >>> 2 = 8 (same as logical shift for positive)
    try evm.stack.push(evm.allocator, BigInt.init(32));
    try evm.stack.push(evm.allocator, BigInt.init(2));

    evm.code = &[_]u8{0x1d}; // SAR
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 8);
}

test "SAR: negative number arithmetic right shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test -8 >>> 1 = -4 (sign extension)
    const neg_eight = BigInt.init(@as(u64, @bitCast(@as(i64, -8))));
    try evm.stack.push(evm.allocator, neg_eight);
    try evm.stack.push(evm.allocator, BigInt.init(1));

    evm.code = &[_]u8{0x1d}; // SAR
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    const result_signed = @as(i64, @bitCast(result.data[0]));
    try testing.expect(result_signed == -4);
}

test "SAR: large negative shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test -1 >>> 256 = -1 (all ones)
    const neg_one = BigInt{ .data = [_]u64{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    try evm.stack.push(evm.allocator, neg_one);
    try evm.stack.push(evm.allocator, BigInt.init(256));

    evm.code = &[_]u8{0x1d}; // SAR
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 0xFFFFFFFFFFFFFFFF);
    try testing.expect(result.data[1] == 0xFFFFFFFFFFFFFFFF);
    try testing.expect(result.data[2] == 0xFFFFFFFFFFFFFFFF);
    try testing.expect(result.data[3] == 0xFFFFFFFFFFFFFFFF);
}

test "SAR: large positive shift" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test 42 >>> 256 = 0
    try evm.stack.push(evm.allocator, BigInt.init(42));
    try evm.stack.push(evm.allocator, BigInt.init(256));

    evm.code = &[_]u8{0x1d}; // SAR
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.isZero());
}

test "SAR: zero shift preserves value" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Test -42 >>> 0 = -42
    const neg_fortytwo = BigInt.init(@as(u64, @bitCast(@as(i64, -42))));
    try evm.stack.push(evm.allocator, neg_fortytwo);
    try evm.stack.push(evm.allocator, BigInt.init(0));

    evm.code = &[_]u8{0x1d}; // SAR
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    const result_signed = @as(i64, @bitCast(result.data[0]));
    try testing.expect(result_signed == -42);
}