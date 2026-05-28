// File: src/evm_block.zig
//
// Bridges the EVM interpreter to the Block-STM executor (src/block_stm.zig).
//
// A block of EVM transactions is run through `executeBlock` by wrapping each in
// an `EvmTx` whose `run` resets a shared EVM, attaches the executor's `VmView`,
// and interprets the transaction's bytecode. Because every state-touching
// opcode routes through `EVM.loadStorage` / `storeStorage` / `loadBalance`, and
// those prefer the attached `VmView`, the interpreter reads from / writes to the
// multi-version store and records its read/write set with no opcode changes.
// Reads that miss every prior writer fall through to `AccountsBase`, the
// pre-block persistent world state.
//
// This is the integration that turns the executor from a tester of abstract
// closures into one that runs real bytecode while preserving serializability.

const std = @import("std");
const main = @import("main.zig");
const EVM = main.EVM;
const Account = main.Account;
const BigInt = main.BigInt;
const sk = @import("state_key.zig");
const StateKey = sk.StateKey;
const bs = @import("block_stm.zig");
const VmView = bs.VmView;
const Transaction = bs.Transaction;
const BaseState = bs.BaseState;

/// A `BaseState` backed by a flat persistent accounts map (the pre-block world
/// state). Returns zero for any key the map does not contain.
pub const AccountsBase = struct {
    accounts: *std.AutoHashMap([20]u8, Account),

    pub fn base(self: *AccountsBase) BaseState {
        return .{ .ctx = self, .get = get };
    }

    fn get(ctx: *anyopaque, key: StateKey) BigInt {
        const self: *AccountsBase = @ptrCast(@alignCast(ctx));
        switch (key.tag) {
            .storage => {
                if (self.accounts.getPtr(key.address)) |acct| {
                    return acct.storage.get(key.slot) orelse BigInt.zero();
                }
                return BigInt.zero();
            },
            .balance => {
                if (self.accounts.get(key.address)) |acct| return acct.balance;
                return BigInt.zero();
            },
            // Nonce/code base reads are not modelled yet (out of scope until the
            // nonce/code opcodes are routed through the view).
            else => return BigInt.zero(),
        }
    }
};

/// One EVM transaction in a block: the bytecode to run and the executing
/// account. The shared `evm` is reset before each (re-)execution.
pub const EvmTx = struct {
    evm: *EVM,
    code: []const u8,
    current_address: [20]u8,
    gas: u64 = 30_000_000,

    pub fn tx(self: *EvmTx) Transaction {
        return .{ .ctx = self, .run = run };
    }

    fn run(ctx: *anyopaque, view: *VmView) anyerror!void {
        const self: *EvmTx = @ptrCast(@alignCast(ctx));
        const evm = self.evm;
        evm.resetForExecution(self.code, self.current_address, self.gas);
        evm.view = view;
        defer evm.view = null;
        try evm.execute();
    }
};
