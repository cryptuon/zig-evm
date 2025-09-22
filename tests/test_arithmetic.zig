const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/bigint.zig").BigInt;

test "SUB opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 30 - 10 = 20
    try evm.stack.push(allocator, BigInt.init(30));
    try evm.stack.push(allocator, BigInt.init(10));

    // Execute SUB bytecode
    const bytecode = &[_]u8{0x03}; // SUB
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 20);
    } else {
        try expect(false);
    }
}

test "DIV opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 20 / 4 = 5
    try evm.stack.push(allocator, BigInt.init(20));
    try evm.stack.push(allocator, BigInt.init(4));

    // Execute DIV bytecode
    const bytecode = &[_]u8{0x04}; // DIV
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 5);
    } else {
        try expect(false);
    }
}

test "DIV by zero" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push values: 10 / 0 = 0 (EVM rule)
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(0));

    // Execute DIV bytecode
    const bytecode = &[_]u8{0x04}; // DIV
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result is 0
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0);
    } else {
        try expect(false);
    }
}

test "MOD opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 17 % 5 = 2
    try evm.stack.push(allocator, BigInt.init(17));
    try evm.stack.push(allocator, BigInt.init(5));

    // Execute MOD bytecode
    const bytecode = &[_]u8{0x06}; // MOD
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 2);
    } else {
        try expect(false);
    }
}

test "Complex arithmetic: (100 - 30) / 7" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Execute: PUSH1 100, PUSH1 30, SUB, PUSH1 7, DIV, STOP
    const bytecode = &[_]u8{ 0x60, 0x64, 0x60, 0x1E, 0x03, 0x60, 0x07, 0x04, 0x00 };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // (100 - 30) / 7 = 70 / 7 = 10
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 10);
    } else {
        try expect(false);
    }
}