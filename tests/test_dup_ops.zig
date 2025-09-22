// File: tests/test_dup_ops.zig

const std = @import("std");
const testing = std.testing;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/main.zig").BigInt;

test "DUP4: duplicate 4th stack item" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push values: 1, 2, 3, 4 (stack: [1, 2, 3, 4])
    try evm.stack.push(evm.allocator, BigInt.init(1));
    try evm.stack.push(evm.allocator, BigInt.init(2));
    try evm.stack.push(evm.allocator, BigInt.init(3));
    try evm.stack.push(evm.allocator, BigInt.init(4));

    // DUP4 should duplicate the 4th item (value 1)
    evm.code = &[_]u8{0x83}; // DUP4
    evm.pc = 0;

    try evm.execute();

    // Stack should now be [1, 2, 3, 4, 1]
    try testing.expect(evm.stack.items.items.len == 5);
    const top = evm.stack.pop().?;
    try testing.expect(top.data[0] == 1);

    // Verify original stack is intact
    const fourth = evm.stack.pop().?;
    try testing.expect(fourth.data[0] == 4);
    const third = evm.stack.pop().?;
    try testing.expect(third.data[0] == 3);
    const second = evm.stack.pop().?;
    try testing.expect(second.data[0] == 2);
    const first = evm.stack.pop().?;
    try testing.expect(first.data[0] == 1);
}

test "DUP8: duplicate 8th stack item" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push 8 values: 1, 2, 3, 4, 5, 6, 7, 8
    for (1..9) |i| {
        try evm.stack.push(evm.allocator, BigInt.init(@intCast(i)));
    }

    // DUP8 should duplicate the 8th item (value 1)
    evm.code = &[_]u8{0x87}; // DUP8
    evm.pc = 0;

    try evm.execute();

    // Stack should now have 9 items, top should be 1
    try testing.expect(evm.stack.items.items.len == 9);
    const duplicated = evm.stack.pop().?;
    try testing.expect(duplicated.data[0] == 1);

    // Verify 8th item is still there
    const len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 8].data[0] == 1);
}

test "DUP16: duplicate 16th stack item" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push 16 values: 1, 2, 3, ..., 16
    for (1..17) |i| {
        try evm.stack.push(evm.allocator, BigInt.init(@intCast(i)));
    }

    // DUP16 should duplicate the 16th item (value 1)
    evm.code = &[_]u8{0x8f}; // DUP16
    evm.pc = 0;

    try evm.execute();

    // Stack should now have 17 items, top should be 1
    try testing.expect(evm.stack.items.items.len == 17);
    const duplicated = evm.stack.pop().?;
    try testing.expect(duplicated.data[0] == 1);

    // Verify 16th item is still there
    const len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 16].data[0] == 1);
}

test "DUP opcodes: stack underflow error" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Only push 2 items
    try evm.stack.push(evm.allocator, BigInt.init(1));
    try evm.stack.push(evm.allocator, BigInt.init(2));

    // Try DUP4 with insufficient stack items
    evm.code = &[_]u8{0x83}; // DUP4
    evm.pc = 0;

    const result = evm.execute();
    try testing.expectError(error.StackUnderflow, result);
}

test "DUP5 through DUP7: middle range opcodes" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push 7 values for testing DUP5, DUP6, DUP7
    for (1..8) |i| {
        try evm.stack.push(evm.allocator, BigInt.init(@intCast(i)));
    }

    // Test DUP5 (should duplicate value 3)
    evm.code = &[_]u8{0x84}; // DUP5
    evm.pc = 0;
    try evm.execute();

    const dup5_result = evm.stack.pop().?;
    try testing.expect(dup5_result.data[0] == 3);

    // Test DUP6 (should duplicate value 2)
    evm.code = &[_]u8{0x85}; // DUP6
    evm.pc = 0;
    try evm.execute();

    const dup6_result = evm.stack.pop().?;
    try testing.expect(dup6_result.data[0] == 2);

    // Test DUP7 (should duplicate value 1)
    evm.code = &[_]u8{0x86}; // DUP7
    evm.pc = 0;
    try evm.execute();

    const dup7_result = evm.stack.pop().?;
    try testing.expect(dup7_result.data[0] == 1);
}

test "DUP9 through DUP12: higher range opcodes" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push 12 values for testing DUP9-DUP12
    for (1..13) |i| {
        try evm.stack.push(evm.allocator, BigInt.init(@intCast(i)));
    }

    // Test DUP9 (should duplicate value 4)
    evm.code = &[_]u8{0x88}; // DUP9
    evm.pc = 0;
    try evm.execute();

    const dup9_result = evm.stack.pop().?;
    try testing.expect(dup9_result.data[0] == 4);

    // Test DUP10 (should duplicate value 3)
    evm.code = &[_]u8{0x89}; // DUP10
    evm.pc = 0;
    try evm.execute();

    const dup10_result = evm.stack.pop().?;
    try testing.expect(dup10_result.data[0] == 3);

    // Test DUP11 (should duplicate value 2)
    evm.code = &[_]u8{0x8a}; // DUP11
    evm.pc = 0;
    try evm.execute();

    const dup11_result = evm.stack.pop().?;
    try testing.expect(dup11_result.data[0] == 2);

    // Test DUP12 (should duplicate value 1)
    evm.code = &[_]u8{0x8b}; // DUP12
    evm.pc = 0;
    try evm.execute();

    const dup12_result = evm.stack.pop().?;
    try testing.expect(dup12_result.data[0] == 1);
}

test "DUP13 through DUP16: maximum range opcodes" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push 16 values for testing DUP13-DUP16
    for (1..17) |i| {
        try evm.stack.push(evm.allocator, BigInt.init(@intCast(i)));
    }

    // Test DUP13 (should duplicate value 4)
    evm.code = &[_]u8{0x8c}; // DUP13
    evm.pc = 0;
    try evm.execute();

    const dup13_result = evm.stack.pop().?;
    try testing.expect(dup13_result.data[0] == 4);

    // Test DUP14 (should duplicate value 3)
    evm.code = &[_]u8{0x8d}; // DUP14
    evm.pc = 0;
    try evm.execute();

    const dup14_result = evm.stack.pop().?;
    try testing.expect(dup14_result.data[0] == 3);

    // Test DUP15 (should duplicate value 2)
    evm.code = &[_]u8{0x8e}; // DUP15
    evm.pc = 0;
    try evm.execute();

    const dup15_result = evm.stack.pop().?;
    try testing.expect(dup15_result.data[0] == 2);

    // Test DUP16 (should duplicate value 1)
    evm.code = &[_]u8{0x8f}; // DUP16
    evm.pc = 0;
    try evm.execute();

    const dup16_result = evm.stack.pop().?;
    try testing.expect(dup16_result.data[0] == 1);
}

test "DUP with large values: verify BigInt duplication" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Create a large BigInt value
    var large_value = BigInt.init(0);
    large_value.data[0] = 0x123456789abcdef0;
    large_value.data[1] = 0xfedcba9876543210;
    large_value.data[2] = 0x1111222233334444;
    large_value.data[3] = 0x5555666677778888;

    // Push 4 items including the large value at position 4
    try evm.stack.push(evm.allocator, large_value);
    try evm.stack.push(evm.allocator, BigInt.init(100));
    try evm.stack.push(evm.allocator, BigInt.init(200));
    try evm.stack.push(evm.allocator, BigInt.init(300));

    // DUP4 should duplicate the large value
    evm.code = &[_]u8{0x83}; // DUP4
    evm.pc = 0;

    try evm.execute();

    const duplicated = evm.stack.pop().?;
    try testing.expect(duplicated.data[0] == 0x123456789abcdef0);
    try testing.expect(duplicated.data[1] == 0xfedcba9876543210);
    try testing.expect(duplicated.data[2] == 0x1111222233334444);
    try testing.expect(duplicated.data[3] == 0x5555666677778888);
}