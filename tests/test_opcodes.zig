const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/bigint.zig").BigInt;

test "ADD opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values onto stack
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(20));

    // Execute ADD bytecode
    const bytecode = &[_]u8{0x01}; // ADD
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 30);
    } else {
        try expect(false); // Stack should not be empty
    }
}

test "MUL opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values onto stack
    try evm.stack.push(allocator, BigInt.init(5));
    try evm.stack.push(allocator, BigInt.init(7));

    // Execute MUL bytecode
    const bytecode = &[_]u8{0x02}; // MUL
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 35);
    } else {
        try expect(false); // Stack should not be empty
    }
}

test "PUSH1 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Execute PUSH1 42 bytecode
    const bytecode = &[_]u8{ 0x60, 0x2A }; // PUSH1 42
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 42);
    } else {
        try expect(false); // Stack should not be empty
    }
}

test "POP opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push a value and then pop it
    try evm.stack.push(allocator, BigInt.init(123));

    // Execute POP bytecode
    const bytecode = &[_]u8{0x50}; // POP
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Stack should be empty
    const result = evm.stack.pop();
    try expect(result == null);
}

test "Complete arithmetic sequence" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Execute: (3 + 4) * 2 = 14
    const bytecode = &[_]u8{ 0x60, 0x03, 0x60, 0x04, 0x01, 0x60, 0x02, 0x02, 0x00 };
    // PUSH1 3, PUSH1 4, ADD, PUSH1 2, MUL, STOP
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check final result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 14);
    } else {
        try expect(false); // Stack should not be empty
    }
}

test "Stack underflow on ADD" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push only one value (ADD needs two)
    try evm.stack.push(allocator, BigInt.init(10));

    // Execute ADD bytecode - should fail
    const bytecode = &[_]u8{0x01}; // ADD
    evm.code = bytecode;
    evm.pc = 0;

    const result = evm.execute();
    try expect(result == error.StackUnderflow);
}