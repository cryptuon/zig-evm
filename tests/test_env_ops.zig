// File: tests/test_env_ops.zig

const std = @import("std");
const testing = std.testing;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/main.zig").BigInt;

test "ADDRESS: returns current contract address" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set a test address
    evm.current_address = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc };

    evm.code = &[_]u8{0x30}; // ADDRESS
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;

    // The address should be stored in data[2] and data[3]
    // We'll verify a few bytes from the address
    try testing.expect(result.data[2] != 0 or result.data[3] != 0);
}

test "CALLER: returns caller address" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set a test caller address
    evm.caller_address = [_]u8{ 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee };

    evm.code = &[_]u8{0x33}; // CALLER
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;

    // The caller address should be stored in data[2] and data[3]
    try testing.expect(result.data[2] != 0 or result.data[3] != 0);
}

test "ORIGIN: returns transaction origin address" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set a test origin address
    evm.origin_address = [_]u8{ 0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00, 0xff, 0xee, 0xdd, 0xcc };

    evm.code = &[_]u8{0x32}; // ORIGIN
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;

    // The origin address should be stored in data[2] and data[3]
    try testing.expect(result.data[2] != 0 or result.data[3] != 0);
}

test "GASPRICE: returns gas price" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set a specific gas price
    evm.gas_price = BigInt.init(50000000000); // 50 gwei

    evm.code = &[_]u8{0x3a}; // GASPRICE
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 50000000000);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "TIMESTAMP: returns block timestamp" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set a specific timestamp
    evm.block_timestamp = 1672531200; // Jan 1, 2023

    evm.code = &[_]u8{0x42}; // TIMESTAMP
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 1672531200);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "NUMBER: returns block number" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set a specific block number
    evm.block_number = 123456789;

    evm.code = &[_]u8{0x43}; // NUMBER
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 123456789);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "DIFFICULTY: returns block difficulty" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set a specific difficulty
    evm.block_difficulty = BigInt.init(5000000000);

    evm.code = &[_]u8{0x44}; // DIFFICULTY
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 5000000000);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "GASLIMIT: returns block gas limit" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set a specific gas limit
    evm.block_gas_limit = 15000000; // 15M gas

    evm.code = &[_]u8{0x45}; // GASLIMIT
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 15000000);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "CHAINID: returns chain ID" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set chain ID to BSC (56)
    evm.chain_id = 56;

    evm.code = &[_]u8{0x46}; // CHAINID
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 56);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "BASEFEE: returns base fee" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set a specific base fee
    evm.base_fee = BigInt.init(25000000000); // 25 gwei

    evm.code = &[_]u8{0x48}; // BASEFEE
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 25000000000);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "BALANCE: returns account balance" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Create a test account with balance
    const test_address = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc };
    const test_balance = BigInt.init(1000000000000000000); // 1 ETH in wei

    var account = @import("../src/main.zig").Account{
        .balance = test_balance,
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(testing.allocator),
    };
    defer account.storage.deinit();

    try evm.accounts.put(test_address, account);

    // Push the address onto the stack (convert to BigInt format)
    var address_bigint = BigInt.init(0);
    for (0..20) |i| {
        const byte_val = test_address[i];
        const bit_pos = i * 8;
        const word_idx = bit_pos / 64;
        const bit_in_word = bit_pos % 64;

        if (word_idx < 4) {
            address_bigint.data[word_idx] |= (@as(u64, byte_val) << @intCast(bit_in_word));
        }
    }

    try evm.stack.push(evm.allocator, address_bigint);

    evm.code = &[_]u8{0x31}; // BALANCE
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 1000000000000000000);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "BALANCE: returns zero for non-existent account" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Push a non-existent address onto the stack
    var nonexistent_address = BigInt.init(0);
    nonexistent_address.data[2] = 0x1234567890abcdef;
    nonexistent_address.data[3] = 0xfedcba0987654321;

    try evm.stack.push(evm.allocator, nonexistent_address);

    evm.code = &[_]u8{0x31}; // BALANCE
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 0);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}

test "SELFBALANCE: returns current contract balance" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set current contract address
    evm.current_address = [_]u8{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00, 0x11, 0x22, 0x33, 0x44 };

    // Create account for current contract with balance
    const self_balance = BigInt.init(500000000000000000); // 0.5 ETH

    var account = @import("../src/main.zig").Account{
        .balance = self_balance,
        .nonce = 1,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(testing.allocator),
    };
    defer account.storage.deinit();

    try evm.accounts.put(evm.current_address, account);

    evm.code = &[_]u8{0x47}; // SELFBALANCE
    evm.pc = 0;

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 500000000000000000);
    try testing.expect(result.data[1] == 0);
    try testing.expect(result.data[2] == 0);
    try testing.expect(result.data[3] == 0);
}