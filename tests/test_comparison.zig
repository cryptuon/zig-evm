const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/bigint.zig").BigInt;

test "LT opcode - less than true" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 5 < 10 = true (1)
    try evm.stack.push(allocator, BigInt.init(5));
    try evm.stack.push(allocator, BigInt.init(10));

    // Execute LT bytecode
    const bytecode = &[_]u8{0x10}; // LT
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result is 1 (true)
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 1);
    } else {
        try expect(false);
    }
}

test "LT opcode - less than false" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 15 < 10 = false (0)
    try evm.stack.push(allocator, BigInt.init(15));
    try evm.stack.push(allocator, BigInt.init(10));

    // Execute LT bytecode
    const bytecode = &[_]u8{0x10}; // LT
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result is 0 (false)
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0);
    } else {
        try expect(false);
    }
}

test "GT opcode - greater than true" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 15 > 10 = true (1)
    try evm.stack.push(allocator, BigInt.init(15));
    try evm.stack.push(allocator, BigInt.init(10));

    // Execute GT bytecode
    const bytecode = &[_]u8{0x11}; // GT
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result is 1 (true)
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 1);
    } else {
        try expect(false);
    }
}

test "EQ opcode - equal true" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 42 == 42 = true (1)
    try evm.stack.push(allocator, BigInt.init(42));
    try evm.stack.push(allocator, BigInt.init(42));

    // Execute EQ bytecode
    const bytecode = &[_]u8{0x14}; // EQ
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result is 1 (true)
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 1);
    } else {
        try expect(false);
    }
}

test "EQ opcode - equal false" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push two values: 42 == 43 = false (0)
    try evm.stack.push(allocator, BigInt.init(42));
    try evm.stack.push(allocator, BigInt.init(43));

    // Execute EQ bytecode
    const bytecode = &[_]u8{0x14}; // EQ
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result is 0 (false)
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0);
    } else {
        try expect(false);
    }
}

test "ISZERO opcode - zero true" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push zero value
    try evm.stack.push(allocator, BigInt.init(0));

    // Execute ISZERO bytecode
    const bytecode = &[_]u8{0x15}; // ISZERO
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result is 1 (true)
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 1);
    } else {
        try expect(false);
    }
}

test "ISZERO opcode - non-zero false" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push non-zero value
    try evm.stack.push(allocator, BigInt.init(42));

    // Execute ISZERO bytecode
    const bytecode = &[_]u8{0x15}; // ISZERO
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result is 0 (false)
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0);
    } else {
        try expect(false);
    }
}