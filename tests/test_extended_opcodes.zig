const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/bigint.zig").BigInt;

test "PUSH4 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Execute PUSH4 with value 0x12345678
    const bytecode = &[_]u8{ 0x63, 0x12, 0x34, 0x56, 0x78 }; // PUSH4 0x12345678
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0x12345678);
    } else {
        try expect(false);
    }
}

test "PUSH32 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Execute PUSH32 with a pattern
    var bytecode: [33]u8 = undefined;
    bytecode[0] = 0x7f; // PUSH32

    // Fill with pattern: 0x01, 0x02, ..., 0x20 (32 bytes)
    for (1..33) |i| {
        bytecode[i] = @as(u8, @intCast(i));
    }

    evm.code = &bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result - verify the pattern was loaded correctly
    if (evm.stack.pop()) |result| {
        // First word should contain bytes 1-8 in big-endian
        const expected_word0: u64 = 0x0102030405060708;
        try expect(result.data[0] == expected_word0);

        // Second word should contain bytes 9-16
        const expected_word1: u64 = 0x090A0B0C0D0E0F10;
        try expect(result.data[1] == expected_word1);
    } else {
        try expect(false);
    }
}

test "DUP2 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 10, 20 (stack: [10, 20])
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(20));

    // Execute DUP2 - should duplicate the second item (10)
    const bytecode = &[_]u8{0x81}; // DUP2
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have [10, 20, 10] on stack
    try expect(evm.stack.items.items.len == 3);

    if (evm.stack.pop()) |val1| {
        if (evm.stack.pop()) |val2| {
            if (evm.stack.pop()) |val3| {
                try expect(val1.data[0] == 10); // Duplicated value
                try expect(val2.data[0] == 20); // Original top
                try expect(val3.data[0] == 10); // Original second
            } else try expect(false);
        } else try expect(false);
    } else try expect(false);
}

test "SWAP2 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push three values: 10, 20, 30 (stack: [10, 20, 30])
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(20));
    try evm.stack.push(allocator, BigInt.init(30));

    // Execute SWAP2 - should swap top (30) with third (10)
    const bytecode = &[_]u8{0x91}; // SWAP2
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have [30, 20, 10] on stack
    if (evm.stack.pop()) |val1| {
        if (evm.stack.pop()) |val2| {
            if (evm.stack.pop()) |val3| {
                try expect(val1.data[0] == 10); // Was third, now top
                try expect(val2.data[0] == 20); // Unchanged
                try expect(val3.data[0] == 30); // Was top, now third
            } else try expect(false);
        } else try expect(false);
    } else try expect(false);
}

test "BigInt improved multiplication" {
    const a = BigInt.init(0xFFFFFFFF);
    const b = BigInt.init(0xFFFFFFFF);
    const result = a.mul(b);

    // 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE00000001
    try expect(result.data[0] == 0xFFFFFFFE00000001);
    try expect(result.data[1] == 0);
}

test "Complex operation with extended opcodes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Simpler test: PUSH4 0x1000, PUSH2 0x100, MUL
    // Result should be: 0x1000 * 0x100 = 0x100000
    const bytecode = &[_]u8{
        0x63, 0x00, 0x00, 0x10, 0x00, // PUSH4 0x1000
        0x61, 0x01, 0x00, // PUSH2 0x100
        0x02, // MUL
        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check final result: 0x1000 * 0x100 = 0x100000
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0x100000);
    } else {
        try expect(false);
    }
}