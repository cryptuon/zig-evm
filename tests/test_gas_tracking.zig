// File: tests/test_gas_tracking.zig

const std = @import("std");
const testing = std.testing;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/main.zig").BigInt;

test "gas tracking: basic gas consumption" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set initial gas limit
    evm.setGasLimit(1000);

    // Execute a simple ADD operation (costs 3 gas)
    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(10));

    evm.code = &[_]u8{0x01}; // ADD
    evm.pc = 0;

    try evm.execute();

    // Check gas consumption
    try testing.expect(evm.gas_used == 3);
    try testing.expect(evm.gas == 997); // 1000 - 3
}

test "gas tracking: multiple operations" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    evm.setGasLimit(1000);

    // Execute ADD (3 gas) + MUL (3 gas) + SUB (3 gas) = 9 gas total
    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(10));
    try evm.stack.push(evm.allocator, BigInt.init(2));
    try evm.stack.push(evm.allocator, BigInt.init(3));

    evm.code = &[_]u8{ 0x01, 0x02, 0x03 }; // ADD, MUL, SUB
    evm.pc = 0;

    try evm.execute();

    try testing.expect(evm.gas_used == 9);
    try testing.expect(evm.gas == 991); // 1000 - 9
}

test "gas tracking: GAS opcode returns remaining gas" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    evm.setGasLimit(1000);

    // Execute GAS opcode (costs 2 gas)
    evm.code = &[_]u8{0x5a}; // GAS
    evm.pc = 0;

    try evm.execute();

    // The GAS opcode should have consumed 2 gas, then pushed 998 onto the stack
    try testing.expect(evm.gas_used == 2);
    try testing.expect(evm.gas == 998);

    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 998);
}

test "gas tracking: out of gas error" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set very low gas limit
    evm.setGasLimit(2);

    // Try to execute ADD (costs 3 gas, but we only have 2)
    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(10));

    evm.code = &[_]u8{0x01}; // ADD
    evm.pc = 0;

    // Should fail with OutOfGas error
    const result = evm.execute();
    try testing.expectError(error.OutOfGas, result);

    // Gas should not have been consumed
    try testing.expect(evm.gas_used == 0);
    try testing.expect(evm.gas == 2);
}

test "gas tracking: exact gas consumption" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Set gas limit to exactly what we need for one ADD operation
    evm.setGasLimit(3);

    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(10));

    evm.code = &[_]u8{0x01}; // ADD
    evm.pc = 0;

    try evm.execute();

    // Should consume exactly all gas
    try testing.expect(evm.gas_used == 3);
    try testing.expect(evm.gas == 0);

    // Result should still be correct
    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 15);
}

test "gas tracking: expensive operations" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    evm.setGasLimit(1000);

    // Execute BALANCE opcode (costs 100 gas)
    var address = BigInt.init(0);
    address.data[0] = 0x1234567890abcdef;
    try evm.stack.push(evm.allocator, address);

    evm.code = &[_]u8{0x31}; // BALANCE
    evm.pc = 0;

    try evm.execute();

    try testing.expect(evm.gas_used == 100);
    try testing.expect(evm.gas == 900);
}

test "gas tracking: different gas costs for different opcodes" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    evm.setGasLimit(1000);

    // Test different opcodes with different costs
    // PUSH1 (3 gas) + ADDRESS (2 gas) + EQ (3 gas) = 8 gas total
    evm.code = &[_]u8{ 0x60, 0x01, 0x30, 0x14 }; // PUSH1 1, ADDRESS, EQ
    evm.pc = 0;

    try evm.execute();

    try testing.expect(evm.gas_used == 8);
    try testing.expect(evm.gas == 992);
}

test "gas tracking: STOP opcode costs zero gas" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    evm.setGasLimit(1000);

    // Execute STOP opcode (costs 0 gas)
    evm.code = &[_]u8{0x00}; // STOP
    evm.pc = 0;

    try evm.execute();

    try testing.expect(evm.gas_used == 0);
    try testing.expect(evm.gas == 1000);
}

test "gas tracking: gas reset when setting new limit" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    evm.setGasLimit(500);

    // Consume some gas
    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(10));

    evm.code = &[_]u8{0x01}; // ADD
    evm.pc = 0;

    try evm.execute();

    try testing.expect(evm.gas_used == 3);
    try testing.expect(evm.gas == 497);

    // Reset gas limit
    evm.setGasLimit(1000);

    try testing.expect(evm.gas_used == 0);
    try testing.expect(evm.gas == 1000);
    try testing.expect(evm.gas_limit == 1000);
}

test "gas tracking: complex operation sequence" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    evm.setGasLimit(1000);

    // Simple sequence: PUSH1 (3) + PUSH1 (3) + ADD (3) = 9 gas
    evm.code = &[_]u8{ 0x60, 0x02, 0x60, 0x04, 0x01 }; // PUSH1 2, PUSH1 4, ADD
    evm.pc = 0;

    try evm.execute();

    // Gas costs: PUSH1(3) + PUSH1(3) + ADD(3) = 9
    try testing.expect(evm.gas_used == 9);
    try testing.expect(evm.gas == 991);

    // Stack should have result of 2+4 = 6
    const result = evm.stack.pop().?;
    try testing.expect(result.data[0] == 6);
}

test "gas tracking: gas info helper function" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    evm.setGasLimit(1000);

    // Execute a few operations
    try evm.stack.push(evm.allocator, BigInt.init(5));
    try evm.stack.push(evm.allocator, BigInt.init(10));

    evm.code = &[_]u8{0x01}; // ADD
    evm.pc = 0;

    try evm.execute();

    const gas_info = evm.getGasInfo();
    try testing.expect(gas_info.used == 3); // ADD(3)
    try testing.expect(gas_info.remaining == 997);
    try testing.expect(gas_info.limit == 1000);
}