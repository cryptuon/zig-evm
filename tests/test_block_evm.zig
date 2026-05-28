// Integration: a block of real EVM bytecode executed through the Block-STM
// executor over the multi-version store. Proves the executor drives the actual
// interpreter (not abstract closures), captures the conflict graph, and yields
// a serializable result identical under forward and reverse execution order.

const std = @import("std");
const testing = std.testing;
const main = @import("../src/main.zig");
const EVM = main.EVM;
const BigInt = main.BigInt;
const StateKey = main.StateKey;
const Opcode = main.Opcode;
const bs = @import("../src/block_stm.zig");
const mvcc = @import("../src/mvcc.zig");
const evm_block = @import("../src/evm_block.zig");
const as = @import("../src/access_set.zig");
const AccessRecorder = as.AccessRecorder;

fn op(o: Opcode) u8 {
    return @intFromEnum(o);
}

fn initRecorders(allocator: std.mem.Allocator, n: usize) ![]AccessRecorder {
    const recs = try allocator.alloc(AccessRecorder, n);
    for (recs) |*r| r.* = AccessRecorder.init(allocator);
    return recs;
}
fn deinitRecorders(allocator: std.mem.Allocator, recs: []AccessRecorder) void {
    for (recs) |*r| r.deinit();
    allocator.free(recs);
}

test "access-recording: two-tx EVM block runs through MVMemory, serializable, with RAW edge" {
    const a = testing.allocator;

    // Shared interpreter and pre-block persistent state (empty: all base reads 0).
    var evm = try EVM.init(a);
    defer evm.deinit();

    const contract: [20]u8 = [_]u8{0xAB} ** 20;

    // tx0: storage[0] = 42        -> PUSH1 42, PUSH1 0, SSTORE, STOP
    const code0 = [_]u8{ op(.PUSH1), 0x2a, op(.PUSH1), 0x00, op(.SSTORE), op(.STOP) };
    // tx1: storage[1] = storage[0] -> PUSH1 0, SLOAD, PUSH1 1, SSTORE, STOP
    const code1 = [_]u8{ op(.PUSH1), 0x00, op(.SLOAD), op(.PUSH1), 0x01, op(.SSTORE), op(.STOP) };

    var t0 = evm_block.EvmTx{ .evm = evm, .code = &code0, .current_address = contract };
    var t1 = evm_block.EvmTx{ .evm = evm, .code = &code1, .current_address = contract };
    const txs = [_]bs.Transaction{ t0.tx(), t1.tx() };

    var ab = evm_block.AccountsBase{ .accounts = &evm.accounts };

    const slot0 = StateKey.storageOf(contract, BigInt.init(0));
    const slot1 = StateKey.storageOf(contract, BigInt.init(1));

    inline for (.{ bs.Strategy.forward, bs.Strategy.reverse }) |strat| {
        var mv = mvcc.MvMemory.init(a);
        defer mv.deinit();
        const recs = try initRecorders(a, txs.len);
        defer deinitRecorders(a, recs);

        _ = try bs.executeBlock(a, &mv, &txs, recs, ab.base(), strat);

        // tx1 copied tx0's write through the versioned store: both slots are 42.
        try testing.expect(bs.finalValue(&mv, slot0, txs.len).eq(BigInt.init(42)));
        try testing.expect(bs.finalValue(&mv, slot1, txs.len).eq(BigInt.init(42)));

        // The conflict graph has the single RAW edge tx0 -> tx1 (tx1 read slot0).
        const m = try bs.analyzeBlock(a, recs);
        try testing.expectEqual(@as(usize, 1), m.raw_edges);
        try testing.expectEqual(@as(usize, 2), m.critical_path);
    }
}

test "access-recording: read-your-own-writes within one tx through the view" {
    const a = testing.allocator;
    var evm = try EVM.init(a);
    defer evm.deinit();
    const contract: [20]u8 = [_]u8{0xCD} ** 20;

    // One tx: storage[0]=42; load storage[0] (must see 42, not the prior 0);
    // store that into storage[1]. If read-your-own-writes were broken, slot1=0.
    //   PUSH1 42, PUSH1 0, SSTORE, PUSH1 0, SLOAD, PUSH1 1, SSTORE, STOP
    const code = [_]u8{
        op(.PUSH1), 0x2a, op(.PUSH1), 0x00, op(.SSTORE),
        op(.PUSH1), 0x00, op(.SLOAD),
        op(.PUSH1), 0x01, op(.SSTORE),
        op(.STOP),
    };
    var t0 = evm_block.EvmTx{ .evm = evm, .code = &code, .current_address = contract };
    const txs = [_]bs.Transaction{t0.tx()};
    var ab = evm_block.AccountsBase{ .accounts = &evm.accounts };

    var mv = mvcc.MvMemory.init(a);
    defer mv.deinit();
    const recs = try initRecorders(a, txs.len);
    defer deinitRecorders(a, recs);

    _ = try bs.executeBlock(a, &mv, &txs, recs, ab.base(), .forward);

    const slot1 = StateKey.storageOf(contract, BigInt.init(1));
    try testing.expect(bs.finalValue(&mv, slot1, txs.len).eq(BigInt.init(42)));
}

test "access-recording: CALL value transfers are versioned and serializable through MVMemory" {
    const a = testing.allocator;
    const A: [20]u8 = [_]u8{0xA0} ** 20; // funded sender, caller of both txs
    var X: [20]u8 = [_]u8{0} ** 20; // recipient 0x00..09
    X[19] = 0x09;

    // Two CALLs from A sending value to X: 5 then 3. Each reads+writes A's and
    // X's balances, so tx1 depends on tx0 (RAW on both balances).
    //   PUSH1 retSize,retOffset,argsSize,argsOffset, value, addr(0x09), gas(0), CALL, STOP
    const code5 = [_]u8{ op(.PUSH1), 0, op(.PUSH1), 0, op(.PUSH1), 0, op(.PUSH1), 0, op(.PUSH1), 0x05, op(.PUSH1), 0x09, op(.PUSH1), 0, op(.CALL), op(.STOP) };
    const code3 = [_]u8{ op(.PUSH1), 0, op(.PUSH1), 0, op(.PUSH1), 0, op(.PUSH1), 0, op(.PUSH1), 0x03, op(.PUSH1), 0x09, op(.PUSH1), 0, op(.CALL), op(.STOP) };

    const bal_a = StateKey.balanceOf(A);
    const bal_x = StateKey.balanceOf(X);

    inline for (.{ bs.Strategy.forward, bs.Strategy.reverse }) |strat| {
        var evm = try EVM.init(a);
        defer evm.deinit();
        // Fund A in the persistent (base) state.
        try evm.accounts.put(A, .{ .balance = BigInt.init(1000), .nonce = 0, .code = &[_]u8{}, .storage = std.AutoHashMap(BigInt, BigInt).init(a) });

        var t0 = evm_block.EvmTx{ .evm = evm, .code = &code5, .current_address = A };
        var t1 = evm_block.EvmTx{ .evm = evm, .code = &code3, .current_address = A };
        const txs = [_]bs.Transaction{ t0.tx(), t1.tx() };
        var ab = evm_block.AccountsBase{ .accounts = &evm.accounts };

        var mv = mvcc.MvMemory.init(a);
        defer mv.deinit();
        const recs = try initRecorders(a, txs.len);
        defer deinitRecorders(a, recs);

        _ = try bs.executeBlock(a, &mv, &txs, recs, ab.base(), strat);

        // Regardless of execution order: A spent 8, X received 8.
        try testing.expect(bs.finalValue(&mv, bal_a, txs.len).eq(BigInt.init(992)));
        try testing.expect(bs.finalValue(&mv, bal_x, txs.len).eq(BigInt.init(8)));
    }
}
