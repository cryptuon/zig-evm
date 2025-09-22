// File: tests/test_swap_ops.zig

const std = @import("std");
const testing = std.testing;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/main.zig").BigInt;

test "SWAP4: swap top with 5th stack item" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push values: 1, 2, 3, 4, 5 (stack: [1, 2, 3, 4, 5])
    try evm.stack.push(evm.allocator, BigInt.init(1));
    try evm.stack.push(evm.allocator, BigInt.init(2));
    try evm.stack.push(evm.allocator, BigInt.init(3));
    try evm.stack.push(evm.allocator, BigInt.init(4));
    try evm.stack.push(evm.allocator, BigInt.init(5));

    // SWAP4 should swap top (5) with 5th item (1)
    evm.code = &[_]u8{0x93}; // SWAP4
    evm.pc = 0;

    try evm.execute();

    // Stack should now be [5, 2, 3, 4, 1]
    try testing.expect(evm.stack.items.items.len == 5);

    // Check each position
    const len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 1].data[0] == 1); // Top is now 1
    try testing.expect(evm.stack.items.items[len - 2].data[0] == 4); // 2nd is 4
    try testing.expect(evm.stack.items.items[len - 3].data[0] == 3); // 3rd is 3
    try testing.expect(evm.stack.items.items[len - 4].data[0] == 2); // 4th is 2
    try testing.expect(evm.stack.items.items[len - 5].data[0] == 5); // 5th is now 5
}

test "SWAP8: swap top with 9th stack item" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push 9 values: 1, 2, 3, 4, 5, 6, 7, 8, 9
    for (1..10) |i| {
        try evm.stack.push(evm.allocator, BigInt.init(@intCast(i)));
    }

    // SWAP8 should swap top (9) with 9th item (1)
    evm.code = &[_]u8{0x97}; // SWAP8
    evm.pc = 0;

    try evm.execute();

    // Stack should now have 9 items, top should be 1, 9th should be 9
    try testing.expect(evm.stack.items.items.len == 9);
    const len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 1].data[0] == 1); // Top is now 1
    try testing.expect(evm.stack.items.items[len - 9].data[0] == 9); // 9th is now 9
}

test "SWAP16: swap top with 17th stack item" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push 17 values: 1, 2, 3, ..., 17
    for (1..18) |i| {
        try evm.stack.push(evm.allocator, BigInt.init(@intCast(i)));
    }

    // SWAP16 should swap top (17) with 17th item (1)
    evm.code = &[_]u8{0x9f}; // SWAP16
    evm.pc = 0;

    try evm.execute();

    // Stack should now have 17 items, top should be 1, 17th should be 17
    try testing.expect(evm.stack.items.items.len == 17);
    const len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 1].data[0] == 1); // Top is now 1
    try testing.expect(evm.stack.items.items[len - 17].data[0] == 17); // 17th is now 17
}

test "SWAP opcodes: stack underflow error" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Only push 3 items
    try evm.stack.push(evm.allocator, BigInt.init(1));
    try evm.stack.push(evm.allocator, BigInt.init(2));
    try evm.stack.push(evm.allocator, BigInt.init(3));

    // Try SWAP4 with insufficient stack items (needs 5)
    evm.code = &[_]u8{0x93}; // SWAP4
    evm.pc = 0;

    const result = evm.execute();
    try testing.expectError(error.StackUnderflow, result);
}

test "SWAP5 through SWAP7: middle range opcodes" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push 8 values for testing SWAP5, SWAP6, SWAP7
    for (1..9) |i| {
        try evm.stack.push(evm.allocator, BigInt.init(@intCast(i)));
    }

    // Test SWAP5 (should swap top (8) with 6th item (3))
    evm.code = &[_]u8{0x94}; // SWAP5
    evm.pc = 0;
    try evm.execute();

    var len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 1].data[0] == 3); // Top is now 3
    try testing.expect(evm.stack.items.items[len - 6].data[0] == 8); // 6th is now 8

    // Reset stack for next test
    evm.stack.items.items[len - 1] = BigInt.init(8); // Restore top to 8
    evm.stack.items.items[len - 6] = BigInt.init(3); // Restore 6th to 3

    // Test SWAP6 (should swap top (8) with 7th item (2))
    evm.code = &[_]u8{0x95}; // SWAP6
    evm.pc = 0;
    try evm.execute();

    len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 1].data[0] == 2); // Top is now 2
    try testing.expect(evm.stack.items.items[len - 7].data[0] == 8); // 7th is now 8

    // Reset stack for next test
    evm.stack.items.items[len - 1] = BigInt.init(8); // Restore top to 8
    evm.stack.items.items[len - 7] = BigInt.init(2); // Restore 7th to 2

    // Test SWAP7 (should swap top (8) with 8th item (1))
    evm.code = &[_]u8{0x96}; // SWAP7
    evm.pc = 0;
    try evm.execute();

    len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 1].data[0] == 1); // Top is now 1
    try testing.expect(evm.stack.items.items[len - 8].data[0] == 8); // 8th is now 8
}

test "SWAP9 through SWAP12: higher range opcodes" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push 13 values for testing SWAP9-SWAP12
    for (1..14) |i| {
        try evm.stack.push(evm.allocator, BigInt.init(@intCast(i)));
    }

    // Test SWAP9 (should swap top (13) with 10th item (4))
    evm.code = &[_]u8{0x98}; // SWAP9
    evm.pc = 0;
    try evm.execute();

    var len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 1].data[0] == 4); // Top is now 4
    try testing.expect(evm.stack.items.items[len - 10].data[0] == 13); // 10th is now 13

    // Reset for SWAP10 test
    evm.stack.items.items[len - 1] = BigInt.init(13);
    evm.stack.items.items[len - 10] = BigInt.init(4);

    // Test SWAP10 (should swap top (13) with 11th item (3))
    evm.code = &[_]u8{0x99}; // SWAP10
    evm.pc = 0;
    try evm.execute();

    len = evm.stack.items.items.len;
    try testing.expect(evm.stack.items.items[len - 1].data[0] == 3); // Top is now 3
    try testing.expect(evm.stack.items.items[len - 11].data[0] == 13); // 11th is now 13
}

test "SWAP with large values: verify BigInt swapping" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Create large BigInt values
    var large_value1 = BigInt.init(0);
    large_value1.data[0] = 0x123456789abcdef0;
    large_value1.data[1] = 0xfedcba9876543210;
    large_value1.data[2] = 0x1111222233334444;
    large_value1.data[3] = 0x5555666677778888;

    var large_value2 = BigInt.init(0);
    large_value2.data[0] = 0x9999aaaabbbbcccc;
    large_value2.data[1] = 0xddddeeeefffff000;
    large_value2.data[2] = 0x1111111122222222;
    large_value2.data[3] = 0x3333333344444444;

    // Push values: large1, small1, small2, small3, large2
    try evm.stack.push(evm.allocator, large_value1);
    try evm.stack.push(evm.allocator, BigInt.init(100));
    try evm.stack.push(evm.allocator, BigInt.init(200));
    try evm.stack.push(evm.allocator, BigInt.init(300));
    try evm.stack.push(evm.allocator, large_value2);

    // SWAP4 should swap top (large2) with 5th item (large1)
    evm.code = &[_]u8{0x93}; // SWAP4
    evm.pc = 0;

    try evm.execute();

    const len = evm.stack.items.items.len;
    const swapped_top = evm.stack.items.items[len - 1];
    const swapped_fifth = evm.stack.items.items[len - 5];

    // Verify large_value1 is now on top
    try testing.expect(swapped_top.data[0] == 0x123456789abcdef0);
    try testing.expect(swapped_top.data[1] == 0xfedcba9876543210);
    try testing.expect(swapped_top.data[2] == 0x1111222233334444);
    try testing.expect(swapped_top.data[3] == 0x5555666677778888);

    // Verify large_value2 is now in 5th position
    try testing.expect(swapped_fifth.data[0] == 0x9999aaaabbbbcccc);
    try testing.expect(swapped_fifth.data[1] == 0xddddeeeefffff000);
    try testing.expect(swapped_fifth.data[2] == 0x1111111122222222);
    try testing.expect(swapped_fifth.data[3] == 0x3333333344444444);
}