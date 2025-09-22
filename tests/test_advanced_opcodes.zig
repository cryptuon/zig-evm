const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/bigint.zig").BigInt;

test "PUSH3 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Execute PUSH3 with value 0x123456
    const bytecode = &[_]u8{ 0x62, 0x12, 0x34, 0x56 }; // PUSH3 0x123456
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check result
    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0x123456);
    } else {
        try expect(false);
    }
}

test "SDIV signed division" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Test positive division: 20 / 4 = 5
    try evm.stack.push(allocator, BigInt.init(20));
    try evm.stack.push(allocator, BigInt.init(4));

    const bytecode = &[_]u8{0x05}; // SDIV
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 5);
    } else {
        try expect(false);
    }
}

test "SDIV signed division by zero" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Test division by zero: 10 / 0 = 0 (EVM rule)
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(0));

    const bytecode = &[_]u8{0x05}; // SDIV
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 0);
    } else {
        try expect(false);
    }
}

test "SLT signed less than" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Test positive comparison: 5 < 10 = true
    try evm.stack.push(allocator, BigInt.init(5));
    try evm.stack.push(allocator, BigInt.init(10));

    const bytecode = &[_]u8{0x12}; // SLT
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    if (evm.stack.pop()) |result| {
        try expect(result.data[0] == 1); // true
    } else {
        try expect(false);
    }
}

test "DUP3 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push three values: 10, 20, 30 (stack: [10, 20, 30])
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(20));
    try evm.stack.push(allocator, BigInt.init(30));

    // Execute DUP3 - should duplicate the third item (10)
    const bytecode = &[_]u8{0x82}; // DUP3
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have [10, 20, 30, 10] on stack
    try expect(evm.stack.items.items.len == 4);

    if (evm.stack.pop()) |val1| {
        if (evm.stack.pop()) |val2| {
            if (evm.stack.pop()) |val3| {
                if (evm.stack.pop()) |val4| {
                    try expect(val1.data[0] == 10); // Duplicated value
                    try expect(val2.data[0] == 30); // Original top
                    try expect(val3.data[0] == 20); // Original middle
                    try expect(val4.data[0] == 10); // Original third
                } else try expect(false);
            } else try expect(false);
        } else try expect(false);
    } else try expect(false);
}

test "SWAP3 opcode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push four values: 10, 20, 30, 40 (stack: [10, 20, 30, 40])
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(20));
    try evm.stack.push(allocator, BigInt.init(30));
    try evm.stack.push(allocator, BigInt.init(40));

    // Execute SWAP3 - should swap top (40) with fourth (10)
    const bytecode = &[_]u8{0x92}; // SWAP3
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Should have [40, 20, 30, 10] on stack
    if (evm.stack.pop()) |val1| {
        if (evm.stack.pop()) |val2| {
            if (evm.stack.pop()) |val3| {
                if (evm.stack.pop()) |val4| {
                    try expect(val1.data[0] == 10); // Was fourth, now top
                    try expect(val2.data[0] == 30); // Unchanged
                    try expect(val3.data[0] == 20); // Unchanged
                    try expect(val4.data[0] == 40); // Was top, now fourth
                } else try expect(false);
            } else try expect(false);
        } else try expect(false);
    } else try expect(false);
}

test "Advanced stack operations combination" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Complex operation: PUSH3, DUP3, SWAP3, arithmetic
    const bytecode = &[_]u8{
        0x62, 0x01, 0x00, 0x00, // PUSH3 0x010000 (65536)
        0x60, 0x02, // PUSH1 2
        0x60, 0x03, // PUSH1 3
        0x82, // DUP3     stack: [65536, 2, 3, 65536]
        0x92, // SWAP3    stack: [65536, 2, 3, 65536] -> [65536, 2, 3, 65536] (swap top with 4th)
        0x01, // ADD      stack: [65536, 2, (3 + 65536)]
        0x02, // MUL      stack: [65536, (2 * 65539)]
        0x00, // STOP
    };
    evm.code = bytecode;
    evm.pc = 0;

    try evm.execute();

    // Check final results
    if (evm.stack.pop()) |result1| {
        if (evm.stack.pop()) |result2| {
            // result1 should be 2 * (3 + 65536) = 2 * 65539 = 131078
            try expect(result1.data[0] == 131078);
            // result2 should be original 65536
            try expect(result2.data[0] == 65536);
        } else try expect(false);
    } else try expect(false);
}

test "DUP3 underflow error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push only two values, try DUP3 (needs 3)
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(20));

    const bytecode = &[_]u8{0x82}; // DUP3
    evm.code = bytecode;
    evm.pc = 0;

    const result = evm.execute();
    try expect(result == error.StackUnderflow);
}

test "SWAP3 underflow error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Push only three values, try SWAP3 (needs 4)
    try evm.stack.push(allocator, BigInt.init(10));
    try evm.stack.push(allocator, BigInt.init(20));
    try evm.stack.push(allocator, BigInt.init(30));

    const bytecode = &[_]u8{0x92}; // SWAP3
    evm.code = bytecode;
    evm.pc = 0;

    const result = evm.execute();
    try expect(result == error.StackUnderflow);
}