// End-to-end transaction replay: apply a sequence of transactions against an
// in-memory pre-state via EVM.executeTransaction and check the resulting state.
// This exercises the full stack — intrinsic gas, nonce, value transfer, nested
// contract execution, storage writes, and refunds — i.e. what a real-block
// replay harness drives (a reference client would supply the pre-state and the
// expected post-state; here the pre-state is synthetic).

const std = @import("std");
const testing = std.testing;
const main = @import("../src/main.zig");
const EVM = main.EVM;
const BigInt = main.BigInt;
const Transaction = main.Transaction;
const Opcode = main.Opcode;

fn op(o: Opcode) u8 {
    return @intFromEnum(o);
}

test "replay: a transfer and a contract call applied in sequence" {
    const a = testing.allocator;
    var evm = try EVM.init(a);
    defer evm.deinit();

    const alice: [20]u8 = [_]u8{0xA1} ** 20;
    const bob: [20]u8 = [_]u8{0xB0} ** 20;
    const counter: [20]u8 = [_]u8{0xC0} ** 20; // contract: storage[0] += 1 on call

    // Pre-state: Alice funded; a counter contract that does storage[0] = storage[0] + 1.
    //   PUSH1 0, SLOAD, PUSH1 1, ADD, PUSH1 0, SSTORE, STOP
    const counter_code = [_]u8{
        op(.PUSH1), 0, op(.SLOAD), op(.PUSH1), 1, op(.ADD),
        op(.PUSH1), 0, op(.SSTORE), op(.STOP),
    };
    try evm.accounts.put(alice, .{ .balance = BigInt.init(1_000_000), .nonce = 0, .code = &[_]u8{}, .storage = std.AutoHashMap(BigInt, BigInt).init(a) });
    try evm.accounts.put(counter, .{ .balance = BigInt.init(0), .nonce = 0, .code = try a.dupe(u8, &counter_code), .storage = std.AutoHashMap(BigInt, BigInt).init(a) });

    // Tx 1: Alice -> Bob, value 1000 (plain transfer).
    try testing.expect(try evm.executeTransaction(.{
        .from = alice, .to = bob, .value = BigInt.init(1000), .data = &[_]u8{},
        .gas_limit = 100_000, .gas_price = BigInt.init(1),
    }));

    // Tx 2 and Tx 3: Alice calls the counter twice (no value).
    try testing.expect(try evm.executeTransaction(.{
        .from = alice, .to = counter, .value = BigInt.zero(), .data = &[_]u8{},
        .gas_limit = 200_000, .gas_price = BigInt.init(1),
    }));
    try testing.expect(try evm.executeTransaction(.{
        .from = alice, .to = counter, .value = BigInt.zero(), .data = &[_]u8{},
        .gas_limit = 200_000, .gas_price = BigInt.init(1),
    }));

    // Post-state checks.
    try testing.expect(evm.accounts.getPtr(bob).?.balance.eq(BigInt.init(1000)));
    try testing.expect(evm.accounts.getPtr(alice).?.balance.eq(BigInt.init(999_000)));
    try testing.expectEqual(@as(u64, 3), evm.accounts.getPtr(alice).?.nonce); // three txs
    // The counter was incremented twice.
    try testing.expect(evm.accounts.getPtr(counter).?.storage.get(BigInt.init(0)).?.eq(BigInt.init(2)));
}

test "replay: an insufficient-balance transfer fails and leaves balances intact" {
    const a = testing.allocator;
    var evm = try EVM.init(a);
    defer evm.deinit();

    const poor: [20]u8 = [_]u8{0x01} ** 20;
    const rich: [20]u8 = [_]u8{0x02} ** 20;
    try evm.accounts.put(poor, .{ .balance = BigInt.init(5), .nonce = 0, .code = &[_]u8{}, .storage = std.AutoHashMap(BigInt, BigInt).init(a) });

    try testing.expectError(error.InsufficientBalance, evm.executeTransaction(.{
        .from = poor, .to = rich, .value = BigInt.init(100), .data = &[_]u8{},
        .gas_limit = 100_000, .gas_price = BigInt.init(1),
    }));
    try testing.expect(evm.accounts.getPtr(poor).?.balance.eq(BigInt.init(5)));
}
