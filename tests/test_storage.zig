const std = @import("std");
const expect = std.testing.expect;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/main.zig").BigInt;
const Account = @import("../src/main.zig").Account;
const Opcode = @import("../src/main.zig").Opcode;

test "SSTORE and SLOAD basic" {
    const allocator = std.testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Create an account for the current address
    var account = Account{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    };
    try evm.accounts.put(evm.current_address, account);

    // Set high gas limit to cover SSTORE costs
    evm.setGasLimit(100000);

    // Bytecode: PUSH1 42, PUSH1 0, SSTORE, PUSH1 0, SLOAD
    // This stores 42 at key 0, then loads it back
    evm.code = &[_]u8{
        @intFromEnum(Opcode.PUSH1), 42, // Push value 42
        @intFromEnum(Opcode.PUSH1), 0, // Push key 0
        @intFromEnum(Opcode.SSTORE), // Store 42 at key 0
        @intFromEnum(Opcode.PUSH1), 0, // Push key 0
        @intFromEnum(Opcode.SLOAD), // Load from key 0
    };

    try evm.execute();

    // Stack should have 42
    const result = evm.stack.pop() orelse return error.StackUnderflow;
    try expect(result.data[0] == 42);
}

test "SLOAD non-existent key returns zero" {
    const allocator = std.testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Create an account for the current address (no storage)
    var account = Account{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    };
    try evm.accounts.put(evm.current_address, account);

    evm.setGasLimit(100000);

    // Bytecode: PUSH1 99, SLOAD (load from key 99 which doesn't exist)
    evm.code = &[_]u8{
        @intFromEnum(Opcode.PUSH1), 99,
        @intFromEnum(Opcode.SLOAD),
    };

    try evm.execute();

    // Stack should have 0 (default for non-existent key)
    const result = evm.stack.pop() orelse return error.StackUnderflow;
    try expect(result.isZero());
}

test "SSTORE overwrites existing value" {
    const allocator = std.testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Create an account with existing storage
    var account = Account{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    };
    // Pre-populate storage with key 5 = value 100
    try account.storage.put(BigInt.init(5), BigInt.init(100));
    try evm.accounts.put(evm.current_address, account);

    evm.setGasLimit(100000);

    // Bytecode: PUSH1 200, PUSH1 5, SSTORE, PUSH1 5, SLOAD
    // Overwrite key 5 with 200
    evm.code = &[_]u8{
        @intFromEnum(Opcode.PUSH1), 200, // New value
        @intFromEnum(Opcode.PUSH1), 5, // Key
        @intFromEnum(Opcode.SSTORE),
        @intFromEnum(Opcode.PUSH1), 5,
        @intFromEnum(Opcode.SLOAD),
    };

    try evm.execute();

    const result = evm.stack.pop() orelse return error.StackUnderflow;
    try expect(result.data[0] == 200);
}

test "SSTORE zero clears storage slot" {
    const allocator = std.testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Create an account with existing storage
    var account = Account{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    };
    // Pre-populate storage with key 7 = value 50
    try account.storage.put(BigInt.init(7), BigInt.init(50));
    try evm.accounts.put(evm.current_address, account);

    evm.setGasLimit(100000);

    // Bytecode: PUSH1 0, PUSH1 7, SSTORE, PUSH1 7, SLOAD
    // Set key 7 to 0 (clear)
    evm.code = &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0, // Value 0 (clear)
        @intFromEnum(Opcode.PUSH1), 7, // Key
        @intFromEnum(Opcode.SSTORE),
        @intFromEnum(Opcode.PUSH1), 7,
        @intFromEnum(Opcode.SLOAD),
    };

    try evm.execute();

    const result = evm.stack.pop() orelse return error.StackUnderflow;
    try expect(result.isZero());
}

test "SSTORE with large key and value" {
    const allocator = std.testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    var account = Account{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    };
    try evm.accounts.put(evm.current_address, account);

    evm.setGasLimit(100000);

    // Use PUSH32 for large values
    // Key: 0x123...  Value: 0xABC...
    var code_buffer: [100]u8 = undefined;
    var idx: usize = 0;

    // PUSH32 large_value
    code_buffer[idx] = @intFromEnum(Opcode.PUSH32);
    idx += 1;
    for (0..32) |i| {
        code_buffer[idx] = @as(u8, @truncate(0xAB + i));
        idx += 1;
    }

    // PUSH32 large_key
    code_buffer[idx] = @intFromEnum(Opcode.PUSH32);
    idx += 1;
    for (0..32) |i| {
        code_buffer[idx] = @as(u8, @truncate(0x12 + i));
        idx += 1;
    }

    // SSTORE
    code_buffer[idx] = @intFromEnum(Opcode.SSTORE);
    idx += 1;

    // PUSH32 large_key again
    code_buffer[idx] = @intFromEnum(Opcode.PUSH32);
    idx += 1;
    for (0..32) |i| {
        code_buffer[idx] = @as(u8, @truncate(0x12 + i));
        idx += 1;
    }

    // SLOAD
    code_buffer[idx] = @intFromEnum(Opcode.SLOAD);
    idx += 1;

    evm.code = code_buffer[0..idx];

    try evm.execute();

    // Verify the value was stored correctly
    const result = evm.stack.pop() orelse return error.StackUnderflow;
    // Check first byte of result matches what we stored
    const result_bytes = result.toBytes();
    try expect(result_bytes[0] == 0xAB);
}
