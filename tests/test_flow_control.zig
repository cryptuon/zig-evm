const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/bigint.zig").BigInt;

test "JUMPDEST and JUMP opcodes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Simple jump: PUSH1 5, JUMP, ..., JUMPDEST, PUSH1 42, STOP
    const bytecode = &[_]u8{
        0x60, 0x05, // PUSH1 5 (jump destination)
        0x56, // JUMP
        0x60, 0x99, // PUSH1 0x99 (this should be skipped)
        0x5b, // JUMPDEST (at position 5)
        0x60, 0x2A, // PUSH1 42
        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have 42 on stack (0x99 should be skipped)
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 42);
    } else {
        try expect(false);
    }

    // Stack should not contain 0x99
    const remaining = evm.stack.pop();
    try expect(remaining == null);
}

test "JUMPI conditional jump - true condition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Simple test - just check that JUMPI can jump successfully
    const bytecode = &[_]u8{
        0x60, 0x01, // PUSH1 1 (true condition) - positions 0,1
        0x60, 0x05, // PUSH1 5 (jump destination) - positions 2,3
        0x57, // JUMPI - position 4
        0x5b, // JUMPDEST (at position 5)
        0x60, 0x2A, // PUSH1 42 - positions 6,7
        0x00, // STOP - position 8
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have 42 on stack
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 42);
    } else {
        try expect(false);
    }
}

test "JUMPI conditional jump - false condition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Conditional jump with false condition - no jump should occur
    const bytecode = &[_]u8{
        0x60, 0x00, // PUSH1 0 (false condition)
        0x60, 0x09, // PUSH1 9 (jump destination)
        0x57, // JUMPI
        0x60, 0x63, // PUSH1 99 (should NOT be skipped) - positions 5,6
        0x60, 0x2A, // PUSH1 42 - positions 7,8
        0x5b, // JUMPDEST (at position 9) - fallback if condition were true
        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have both 42 and 99 on stack (no jump occurred)
    if (evm.stack.pop()) |result1| {
        if (evm.stack.pop()) |result2| {
            try expect(result1.data[0] == 42);
            try expect(result2.data[0] == 99);
        } else {
            try expect(false);
        }
    } else {
        try expect(false);
    }
}

test "PC opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Simple PC test
    const bytecode = &[_]u8{
        0x58, // PC (should push 0) - position 0
        0x60, 0x42, // PUSH1 42 - positions 1,2
        0x00, // STOP - position 3
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have PC value and 42 on stack
    if (evm.stack.pop()) |value| {
        if (evm.stack.pop()) |pc1| {
            try expect(pc1.data[0] == 0); // First PC
            try expect(value.data[0] == 0x42); // The PUSH1 value (0x42 = 66)
        } else try expect(false);
    } else try expect(false);
}

test "Invalid jump destination" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Jump to invalid destination (not JUMPDEST)
    const bytecode = &[_]u8{
        0x60, 0x03, // PUSH1 3
        0x56, // JUMP
        0x60, 0x42, // PUSH1 42 (at position 3, not JUMPDEST)
        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    const result = evm.execute();
    try expect(result == error.InvalidJump);
}

test "Jump out of bounds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Jump beyond code length
    const bytecode = &[_]u8{
        0x60, 0xFF, // PUSH1 255 (out of bounds)
        0x56, // JUMP
        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    const result = evm.execute();
    try expect(result == error.InvalidJump);
}

test "Complex flow control" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Complex flow: conditional jumps and loops simulation
    // Position 0: PUSH1 5 (2 bytes)
    // Position 2: PUSH1 3 (2 bytes)
    // Position 4: GT (1 byte)
    // Position 5: PUSH1 12 (2 bytes)
    // Position 7: JUMPI (1 byte)
    // Position 8: PUSH1 0 (2 bytes)
    // Position 10: STOP (1 byte)
    // Position 11: STOP (1 byte)
    // Position 12: JUMPDEST (1 byte)
    // Position 13: PUSH1 42 (2 bytes)
    // Position 15: STOP (1 byte)
    const bytecode = &[_]u8{
        0x60, 0x05, // PUSH1 5 - positions 0,1
        0x60, 0x03, // PUSH1 3 - positions 2,3
        0x11, // GT (5 > 3 = true) - position 4
        0x60, 0x0C, // PUSH1 12 (jump dest) - positions 5,6
        0x57, // JUMPI (jump if true) - position 7
        0x60, 0x00, // PUSH1 0 (shouldn't execute) - positions 8,9
        0x00, // STOP (shouldn't execute) - position 10
        0x00, // STOP (padding) - position 11
        0x5b, // JUMPDEST (at position 12)
        0x60, 0x2A, // PUSH1 42 - positions 13,14
        0x00, // STOP - position 15
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have only 42 on stack
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 42);
    } else {
        try expect(false);
    }

    // No other values should be on stack
    try expect(evm.stack.pop() == null);
}