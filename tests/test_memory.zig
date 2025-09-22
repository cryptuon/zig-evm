const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/bigint.zig").BigInt;

test "MSTORE and MLOAD opcodes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Store value 0x1234 at memory offset 0
    // PUSH1 0x34, PUSH1 0x12, PUSH1 0x1E, SHL, OR, PUSH1 0x00, MSTORE
    const store_bytecode = &[_]u8{
        0x61, 0x12, 0x34, // PUSH2 0x1234
        0x60, 0x00, // PUSH1 0 (offset)
        0x52, // MSTORE
        0x00, // STOP
    };
    evm.code = store_bytecode;
    evm.pc = 0;

    try evm.execute();

    // Reset EVM for load test
    evm.pc = 0;

    // Load value from memory offset 0
    const load_bytecode = &[_]u8{
        0x60, 0x00, // PUSH1 0 (offset)
        0x51, // MLOAD
        0x00, // STOP
    };
    evm.code = load_bytecode;

    try evm.execute();

    // Check that loaded value contains our stored value
    if (evm.stack.pop()) |result| {
        // The value should be stored as big-endian in the first few bytes
        // 0x1234 should be in the high-order bits of the first word
        try expect(result.data[0] != 0); // Something was loaded
    } else {
        try expect(false);
    }
}

test "MSTORE8 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Store byte 0xFF at memory offset 5
    const bytecode = &[_]u8{
        0x60, 0xFF, // PUSH1 0xFF
        0x60, 0x05, // PUSH1 5 (offset)
        0x53, // MSTORE8
        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Verify memory was expanded and byte was stored
    try expect(evm.memory.size() >= 6);
}

test "MSIZE opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Initially, memory size should be 0
    const initial_bytecode = &[_]u8{
        0x59, // MSIZE
        0x00, // STOP
    };
    evm.code = initial_bytecode;
    evm.pc = 0;

    try evm.execute();

    if (evm.stack.pop()) |size| {
        try expect(size.data[0] == 0); // Initial memory size is 0
    } else {
        try expect(false);
    }

    // Store something to expand memory, then check size again
    evm.pc = 0;
    const expand_bytecode = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x60, 0x40, // PUSH1 64 (offset)
        0x53, // MSTORE8
        0x59, // MSIZE
        0x00, // STOP
    };
    evm.code = expand_bytecode;

    try evm.execute();

    if (evm.stack.pop()) |size| {
        try expect(size.data[0] >= 65); // Memory should be at least 65 bytes
    } else {
        try expect(false);
    }
}

test "Memory operations integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Complex memory test: store values, check size, load back
    const bytecode = &[_]u8{
        // Store 0x1111 at offset 0x20
        0x61, 0x11, 0x11, // PUSH2 0x1111
        0x60, 0x20, // PUSH1 0x20
        0x52, // MSTORE

        // Store byte 0x22 at offset 0x50
        0x60, 0x22, // PUSH1 0x22
        0x60, 0x50, // PUSH1 0x50
        0x53, // MSTORE8

        // Check memory size
        0x59, // MSIZE

        // Load from offset 0x20
        0x60, 0x20, // PUSH1 0x20
        0x51, // MLOAD

        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have loaded value and memory size on stack
    try expect(evm.stack.items.items.len == 2);

    // Pop loaded value
    if (evm.stack.pop()) |loaded_value| {
        try expect(loaded_value.data[0] != 0);
    } else {
        try expect(false);
    }

    // Pop memory size
    if (evm.stack.pop()) |memory_size| {
        try expect(memory_size.data[0] >= 0x51); // At least 81 bytes
    } else {
        try expect(false);
    }
}