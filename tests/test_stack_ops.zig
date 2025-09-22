const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/bigint.zig").BigInt;

test "DUP1 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push a value and duplicate it
    try evm.stack.push(allocator, BigInt.init(42));

    // Execute DUP1 bytecode
    const bytecode = &[_]u8{0x80}; // DUP1
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have two identical values on stack
    try expect(evm.stack.items.items.len == 2);

    if (evm.stack.pop()) |val1| {
        if (evm.stack.pop()) |val2| {
            try expect(val1.data[0] == 42);
            try expect(val2.data[0] == 42);
        } else {
            try expect(false);
        }
    } else {
        try expect(false);
    }
}

test "SWAP1 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(20));

    // Execute SWAP1 bytecode
    const bytecode = &[_]u8{0x90}; // SWAP1
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Values should be swapped
    if (evm.stack.pop()) |val1| {
        if (evm.stack.pop()) |val2| {
            try expect(val1.data[0] == 10); // Was second, now first
            try expect(val2.data[0] == 20); // Was first, now second
        } else {
            try expect(false);
        }
    } else {
        try expect(false);
    }
}

test "PUSH2 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Execute PUSH2 with value 0x1234
    const bytecode = &[_]u8{ 0x61, 0x12, 0x34 }; // PUSH2 0x1234
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0x1234);
    } else {
        try expect(false);
    }
}

test "Complex stack operations: DUP, SWAP, arithmetic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push 5, DUP1 (stack: [5, 5]), PUSH1 3, SWAP1 (stack: [5, 3, 5]), ADD (stack: [5, 8])
    const bytecode = &[_]u8{
        0x60, 0x05, // PUSH1 5
        0x80, // DUP1     stack: [5, 5]
        0x60, 0x03, // PUSH1 3  stack: [5, 5, 3]
        0x90, // SWAP1    stack: [5, 3, 5]
        0x01, // ADD      stack: [5, 8]
        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have [5, 8] on stack
    if (evm.stack.pop()) |val1| {
        if (evm.stack.pop()) |val2| {
            try expect(val1.data[0] == 8);
            try expect(val2.data[0] == 5);
        } else {
            try expect(false);
        }
    } else {
        try expect(false);
    }
}

test "DUP1 underflow error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Try to DUP1 on empty stack
    const bytecode = &[_]u8{0x80}; // DUP1
    evm.code = bytecode;
    evm.pc = 0;

    const result = evm.execute();
    try expect(result == error.StackUnderflow);
}

test "SWAP1 underflow error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push only one value, then try to SWAP1 (needs 2)
    try evm.stack.push(allocator, BigInt.init(42));

    const bytecode = &[_]u8{0x90}; // SWAP1
    evm.code = bytecode;
    evm.pc = 0;

    const result = evm.execute();
    try expect(result == error.StackUnderflow);
}