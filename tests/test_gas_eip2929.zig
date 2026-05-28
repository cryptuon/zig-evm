// EIP-2929 cold/warm access metering. Verified against the spec's gas constants
// (cold SLOAD 2100, warm 100; cold account access 2600, warm 100) by running
// crafted bytecode and checking the exact gas consumed.

const std = @import("std");
const testing = std.testing;
const main = @import("../src/main.zig");
const EVM = main.EVM;
const BigInt = main.BigInt;
const Opcode = main.Opcode;

fn op(o: Opcode) u8 {
    return @intFromEnum(o);
}

const contract: [20]u8 = [_]u8{0xAB} ** 20;

test "eip2929: SLOAD is cold (2100) then warm (100) for the same slot" {
    const a = testing.allocator;
    var evm = try EVM.init(a);
    defer evm.deinit();

    // PUSH1 5, SLOAD, PUSH1 5, SLOAD, STOP
    const code = [_]u8{ op(.PUSH1), 0x05, op(.SLOAD), op(.PUSH1), 0x05, op(.SLOAD), op(.STOP) };
    evm.resetForExecution(&code, contract, 1_000_000);
    try evm.execute();

    // PUSH1(3) + SLOAD_cold(2100) + PUSH1(3) + SLOAD_warm(100) = 2206
    try testing.expectEqual(@as(u64, 3 + 2100 + 3 + 100), evm.gas_used);
}

test "eip2929: BALANCE is cold (2600) then warm (100) for the same account" {
    const a = testing.allocator;
    var evm = try EVM.init(a);
    defer evm.deinit();

    // Query balance of 0x00..01 twice. It differs from the (pre-warmed)
    // executing contract, so the first access is cold.
    const code = [_]u8{ op(.PUSH1), 0x01, op(.BALANCE), op(.PUSH1), 0x01, op(.BALANCE), op(.STOP) };
    evm.resetForExecution(&code, contract, 1_000_000);
    try evm.execute();

    // PUSH1(3) + BALANCE_cold(2600) + PUSH1(3) + BALANCE_warm(100) = 2706
    try testing.expectEqual(@as(u64, 3 + 2600 + 3 + 100), evm.gas_used);
}

test "eip2929: the executing account is pre-warmed at reset" {
    const a = testing.allocator;
    var evm = try EVM.init(a);
    defer evm.deinit();

    evm.resetForExecution(&[_]u8{op(.STOP)}, contract, 1_000_000);
    // The executing contract is warm from the start (so a self BALANCE/CALL
    // would not pay the cold surcharge); a different account is still cold.
    try testing.expect(!(try evm.accessAccount(contract)));
    const other: [20]u8 = [_]u8{0xCD} ** 20;
    try testing.expect(try evm.accessAccount(other));
}

const sstore = @import("../src/opcodes/sstore.zig");

fn bi(n: u64) BigInt {
    return BigInt.init(n);
}

test "eip2929: SSTORE dynamic gas by (original,current,new) per EIP-2200" {
    // no-op store
    try testing.expectEqual(@as(u64, 100), sstore.sstoreDynamicGas(bi(5), bi(5), bi(5)));
    // fresh set 0 -> non-zero
    try testing.expectEqual(@as(u64, 20000), sstore.sstoreDynamicGas(bi(0), bi(0), bi(7)));
    // fresh reset non-zero -> different non-zero
    try testing.expectEqual(@as(u64, 2900), sstore.sstoreDynamicGas(bi(5), bi(5), bi(9)));
    // fresh reset non-zero -> zero
    try testing.expectEqual(@as(u64, 2900), sstore.sstoreDynamicGas(bi(5), bi(5), bi(0)));
    // dirty (already changed this tx) -> warm only
    try testing.expectEqual(@as(u64, 100), sstore.sstoreDynamicGas(bi(0), bi(7), bi(9)));
}

test "eip2929: SSTORE refunds per EIP-3529" {
    // clearing a slot that was non-zero at tx start: +4800
    try testing.expectEqual(@as(i64, 4800), sstore.sstoreRefund(bi(5), bi(5), bi(0)));
    // restoring a dirty slot back to a zero original: +19900
    try testing.expectEqual(@as(i64, 19900), sstore.sstoreRefund(bi(0), bi(7), bi(0)));
    // restoring a dirty slot back to a non-zero original: +2800
    try testing.expectEqual(@as(i64, 2800), sstore.sstoreRefund(bi(5), bi(7), bi(5)));
    // re-setting a slot that was cleared earlier this tx: -4800
    try testing.expectEqual(@as(i64, -4800), sstore.sstoreRefund(bi(5), bi(0), bi(9)));
    // plain no-op / non-refunding cases
    try testing.expectEqual(@as(i64, 0), sstore.sstoreRefund(bi(5), bi(5), bi(5)));
    try testing.expectEqual(@as(i64, 0), sstore.sstoreRefund(bi(0), bi(0), bi(7)));
}

test "eip2929: SSTORE total gas — cold fresh set is 22100" {
    const a = testing.allocator;
    var evm = try EVM.init(a);
    defer evm.deinit();

    // PUSH1 7, PUSH1 0, SSTORE, STOP : store 7 at slot 0 (cold, 0 -> non-zero)
    const code = [_]u8{ op(.PUSH1), 0x07, op(.PUSH1), 0x00, op(.SSTORE), op(.STOP) };
    evm.resetForExecution(&code, contract, 1_000_000);
    try evm.execute();

    // PUSH1(3) + PUSH1(3) + SSTORE(20000 set + 2100 cold) = 22106
    try testing.expectEqual(@as(u64, 3 + 3 + 20000 + 2100), evm.gas_used);
    // And a fresh set carries no refund.
    try testing.expectEqual(@as(i64, 0), evm.gas_refund);
}

test "eip2929: refund application is capped at gas_used/5" {
    const a = testing.allocator;
    var evm = try EVM.init(a);
    defer evm.deinit();

    // Refund exceeds the cap: applied = gas_used/5.
    evm.gas_used = 100_000;
    evm.gas = 0;
    evm.gas_refund = 30_000;
    evm.applyRefund();
    try testing.expectEqual(@as(u64, 80_000), evm.gas_used); // 100k - min(30k, 20k)
    try testing.expectEqual(@as(u64, 20_000), evm.gas);

    // Refund below the cap: applied in full.
    evm.gas_used = 100_000;
    evm.gas = 0;
    evm.gas_refund = 5_000;
    evm.applyRefund();
    try testing.expectEqual(@as(u64, 95_000), evm.gas_used);
    try testing.expectEqual(@as(u64, 5_000), evm.gas);
}

test "eip2929: access methods report cold-then-warm; SSTORE-style touch warms a slot" {
    const a = testing.allocator;
    var evm = try EVM.init(a);
    defer evm.deinit();

    try testing.expect(try evm.accessSlot(contract, BigInt.init(1))); // cold
    try testing.expect(!(try evm.accessSlot(contract, BigInt.init(1)))); // warm
    try testing.expect(try evm.accessSlot(contract, BigInt.init(2))); // distinct slot cold

    const a1: [20]u8 = [_]u8{0x11} ** 20;
    try testing.expect(try evm.accessAccount(a1)); // cold
    try testing.expect(!(try evm.accessAccount(a1))); // warm
}
