const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/bigint.zig").BigInt;

test "AND opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 0xFF & 0x0F = 0x0F (15)
    try evm.stack.push(allocator, BigInt.init(0xFF));
    try evm.stack.push(allocator, BigInt.init(0x0F));

    // Execute AND bytecode
    const bytecode = &[_]u8{0x16}; // AND
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0x0F);
    } else {
        try expect(false);
    }
}

test "OR opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 0xF0 | 0x0F = 0xFF (255)
    try evm.stack.push(allocator, BigInt.init(0xF0));
    try evm.stack.push(allocator, BigInt.init(0x0F));

    // Execute OR bytecode
    const bytecode = &[_]u8{0x17}; // OR
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0xFF);
    } else {
        try expect(false);
    }
}

test "XOR opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 0xFF ^ 0x0F = 0xF0 (240)
    try evm.stack.push(allocator, BigInt.init(0xFF));
    try evm.stack.push(allocator, BigInt.init(0x0F));

    // Execute XOR bytecode
    const bytecode = &[_]u8{0x18}; // XOR
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0xF0);
    } else {
        try expect(false);
    }
}

test "NOT opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push value: ~0x0F = 0xFFFFFFFFFFFFFFF0 (for the least significant word)
    try evm.stack.push(allocator, BigInt.init(0x0F));

    // Execute NOT bytecode
    const bytecode = &[_]u8{0x19}; // NOT
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result - NOT of 0x0F should be 0xFFFFFFFFFFFFFFF0
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0xFFFFFFFFFFFFFFF0);
        try expect(result.data[1] == 0xFFFFFFFFFFFFFFFF);
        try expect(result.data[2] == 0xFFFFFFFFFFFFFFFF);
        try expect(result.data[3] == 0xFFFFFFFFFFFFFFFF);
    } else {
        try expect(false);
    }
}

test "Complex bitwise: (A & B) | (C ^ D)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Calculate: (0xFF & 0x0F) | (0xF0 ^ 0x0F)
    // = 0x0F | 0xFF = 0xFF
    const bytecode = &[_]u8{
        0x60, 0xFF, // PUSH1 0xFF
        0x60, 0x0F, // PUSH1 0x0F
        0x16, // AND
        0x60, 0xF0, // PUSH1 0xF0
        0x60, 0x0F, // PUSH1 0x0F
        0x18, // XOR
        0x17, // OR
        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check final result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0xFF);
    } else {
        try expect(false);
    }
}