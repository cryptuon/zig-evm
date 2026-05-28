// File: src/main.zig

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub const BigInt = @import("bigint.zig").BigInt;
pub const Memory = @import("memory.zig").Memory;
pub const Stack = @import("stack.zig").Stack;
pub const CallStack = @import("call_frame.zig").CallStack;
pub const CallFrame = @import("call_frame.zig").CallFrame;
pub const AccessRecorder = @import("access_set.zig").AccessRecorder;
pub const StateKey = @import("state_key.zig").StateKey;
pub const StateKeyHashMap = @import("state_key.zig").StateKeyHashMap;
pub const VmView = @import("block_stm.zig").VmView;
const crypto = @import("crypto.zig");

pub const Opcode = enum(u8) {
    STOP = 0x00,
    ADD = 0x01,
    MUL = 0x02,
    SUB = 0x03,
    DIV = 0x04,
    SDIV = 0x05,
    MOD = 0x06,
    SMOD = 0x07,
    ADDMOD = 0x08,
    MULMOD = 0x09,
    EXP = 0x0a,
    SIGNEXTEND = 0x0b,
    LT = 0x10,
    GT = 0x11,
    SLT = 0x12,
    SGT = 0x13,
    EQ = 0x14,
    ISZERO = 0x15,
    AND = 0x16,
    OR = 0x17,
    XOR = 0x18,
    NOT = 0x19,
    BYTE = 0x1a,
    SHL = 0x1b,
    SHR = 0x1c,
    SAR = 0x1d,
    SHA3 = 0x20,
    ADDRESS = 0x30,
    BALANCE = 0x31,
    ORIGIN = 0x32,
    CALLER = 0x33,
    CALLVALUE = 0x34,
    CALLDATALOAD = 0x35,
    CALLDATASIZE = 0x36,
    CALLDATACOPY = 0x37,
    CODESIZE = 0x38,
    CODECOPY = 0x39,
    GASPRICE = 0x3a,
    EXTCODESIZE = 0x3b,
    EXTCODECOPY = 0x3c,
    RETURNDATASIZE = 0x3d,
    RETURNDATACOPY = 0x3e,
    EXTCODEHASH = 0x3f,
    BLOCKHASH = 0x40,
    COINBASE = 0x41,
    TIMESTAMP = 0x42,
    NUMBER = 0x43,
    DIFFICULTY = 0x44,
    GASLIMIT = 0x45,
    CHAINID = 0x46,
    SELFBALANCE = 0x47,
    BASEFEE = 0x48,
    POP = 0x50,
    MLOAD = 0x51,
    MSTORE = 0x52,
    MSTORE8 = 0x53,
    SLOAD = 0x54,
    SSTORE = 0x55,
    JUMP = 0x56,
    JUMPI = 0x57,
    PC = 0x58,
    MSIZE = 0x59,
    GAS = 0x5a,
    JUMPDEST = 0x5b,
    PUSH1 = 0x60,
    PUSH2 = 0x61,
    PUSH3 = 0x62,
    PUSH4 = 0x63,
    PUSH5 = 0x64,
    PUSH6 = 0x65,
    PUSH7 = 0x66,
    PUSH8 = 0x67,
    PUSH9 = 0x68,
    PUSH10 = 0x69,
    PUSH11 = 0x6a,
    PUSH12 = 0x6b,
    PUSH13 = 0x6c,
    PUSH14 = 0x6d,
    PUSH15 = 0x6e,
    PUSH16 = 0x6f,
    PUSH17 = 0x70,
    PUSH18 = 0x71,
    PUSH19 = 0x72,
    PUSH20 = 0x73,
    PUSH21 = 0x74,
    PUSH22 = 0x75,
    PUSH23 = 0x76,
    PUSH24 = 0x77,
    PUSH25 = 0x78,
    PUSH26 = 0x79,
    PUSH27 = 0x7a,
    PUSH28 = 0x7b,
    PUSH29 = 0x7c,
    PUSH30 = 0x7d,
    PUSH31 = 0x7e,
    PUSH32 = 0x7f,
    DUP1 = 0x80,
    DUP2 = 0x81,
    DUP3 = 0x82,
    DUP4 = 0x83,
    DUP5 = 0x84,
    DUP6 = 0x85,
    DUP7 = 0x86,
    DUP8 = 0x87,
    DUP9 = 0x88,
    DUP10 = 0x89,
    DUP11 = 0x8a,
    DUP12 = 0x8b,
    DUP13 = 0x8c,
    DUP14 = 0x8d,
    DUP15 = 0x8e,
    DUP16 = 0x8f,
    SWAP1 = 0x90,
    SWAP2 = 0x91,
    SWAP3 = 0x92,
    SWAP4 = 0x93,
    SWAP5 = 0x94,
    SWAP6 = 0x95,
    SWAP7 = 0x96,
    SWAP8 = 0x97,
    SWAP9 = 0x98,
    SWAP10 = 0x99,
    SWAP11 = 0x9a,
    SWAP12 = 0x9b,
    SWAP13 = 0x9c,
    SWAP14 = 0x9d,
    SWAP15 = 0x9e,
    SWAP16 = 0x9f,
    LOG0 = 0xa0,
    LOG1 = 0xa1,
    LOG2 = 0xa2,
    LOG3 = 0xa3,
    LOG4 = 0xa4,
    CREATE = 0xf0,
    CALL = 0xf1,
    CALLCODE = 0xf2,
    RETURN = 0xf3,
    DELEGATECALL = 0xf4,
    CREATE2 = 0xf5,
    STATICCALL = 0xfa,
    REVERT = 0xfd,
    INVALID = 0xfe,
    SELFDESTRUCT = 0xff,
};

pub const OpcodeImpl = struct {
    execute: *const fn (*EVM) anyerror!void,
};

pub const Transaction = struct {
    from: [20]u8,
    to: ?[20]u8,
    value: BigInt,
    data: []const u8,
    gas_limit: u64,
    gas_price: BigInt,
};

pub const Account = struct {
    balance: BigInt,
    nonce: u64,
    code: []const u8,
    storage: std.AutoHashMap(BigInt, BigInt),
};

/// Ethereum log entry
pub const Log = struct {
    address: [20]u8,
    topics: std.array_list.Managed([32]u8),
    data: []u8,

    pub fn init(allocator: Allocator, address: [20]u8) Log {
        return Log{
            .address = address,
            .topics = std.array_list.Managed([32]u8).init(allocator),
            .data = &[_]u8{},
        };
    }

    pub fn deinit(self: *Log, allocator: Allocator) void {
        self.topics.deinit();
        if (self.data.len > 0) {
            allocator.free(self.data);
        }
    }

    pub fn addTopic(self: *Log, topic: [32]u8) !void {
        try self.topics.append(topic);
    }

    pub fn setData(self: *Log, allocator: Allocator, data: []const u8) !void {
        if (self.data.len > 0) {
            allocator.free(self.data);
        }
        self.data = try allocator.dupe(u8, data);
    }
};

pub const EVM = struct {
    // EIP-2929 access-list gas constants.
    pub const COLD_SLOAD_COST: u64 = 2100;
    pub const WARM_STORAGE_READ_COST: u64 = 100;
    pub const COLD_ACCOUNT_ACCESS_COST: u64 = 2600;
    // EIP-2200 / EIP-2929 / EIP-3529 SSTORE constants.
    pub const SSTORE_SET_GAS: u64 = 20000;
    pub const SSTORE_RESET_GAS: u64 = 2900; // 5000 - COLD_SLOAD_COST (EIP-2929)
    pub const SSTORE_CLEARS_SCHEDULE: i64 = 4800; // EIP-3529

    allocator: Allocator,
    stack: Stack,
    memory: Memory,
    pc: usize,
    gas: u64,
    gas_limit: u64,
    gas_used: u64,
    code: []const u8,
    opcodes: std.AutoHashMap(Opcode, OpcodeImpl),
    accounts: std.AutoHashMap([20]u8, Account),
    current_transaction: ?Transaction,

    // Environmental information
    current_address: [20]u8,
    caller_address: [20]u8,
    origin_address: [20]u8,
    call_value: BigInt,
    gas_price: BigInt,
    block_timestamp: u64,
    block_number: u64,
    block_difficulty: BigInt,
    block_gas_limit: u64,
    chain_id: u64,
    base_fee: BigInt,

    // Call data (input to the current execution context)
    calldata: []const u8,

    // Return data from the last external call
    return_data: []u8,

    // Execution state flags
    stop_execution: bool,
    execution_reverted: bool,

    // Block information
    coinbase: [20]u8,
    block_hashes: std.AutoHashMap(u64, [32]u8),

    // Logs generated during execution
    logs: std.array_list.Managed(Log),

    // Call stack for nested calls
    call_stack: CallStack,

    // Optional dynamic access recorder. When non-null, the state-access helpers
    // below log every storage/balance/nonce key read or written, yielding the
    // per-transaction read/write set used to build the block conflict graph for
    // the serializable parallel-execution engine. Null during ordinary
    // single-threaded execution (zero overhead).
    access: ?*AccessRecorder,

    // Optional multi-version view. When non-null, the state-access helpers read
    // and write through the Block-STM `VmView` (versioned store + read/write-set
    // recording + base-state fallback) instead of the flat `accounts` map, so
    // the same opcode code runs unchanged under parallel block execution.
    view: ?*VmView,

    // EIP-2929 per-transaction access list (the "warm set"). An address or
    // storage slot is cold on first touch in a transaction and warm thereafter,
    // which sets the access gas cost. Note this set is the same object the
    // engine records as the transaction's read/write set — the protocol's access
    // list and our conflict-tracking access set coincide.
    warm_accounts: std.AutoHashMap([20]u8, void),
    warm_slots: StateKeyHashMap(void),

    // EIP-2200: the value each storage slot held at the start of the current
    // transaction (captured on first SSTORE), needed to price net changes; and
    // the EIP-3529 gas-refund accumulator (applied, capped, at tx end).
    original_values: StateKeyHashMap(BigInt),
    gas_refund: i64,

    // Revert journal: (key, prior value) for every storage/balance write, so a
    // reverted call frame can restore the state it touched. A frame records the
    // journal length on entry and unwinds back to it on revert.
    journal: std.ArrayListUnmanaged(JournalEntry),

    pub const JournalEntry = struct { key: StateKey, old: BigInt };

    pub fn init(allocator: Allocator) !*EVM {
        var evm = try allocator.create(EVM);
        evm.* = EVM{
            .allocator = allocator,
            .stack = Stack.init(allocator),
            .memory = Memory.init(allocator),
            .pc = 0,
            .gas = 21000, // Default gas for basic transaction
            .gas_limit = 21000,
            .gas_used = 0,
            .code = &[_]u8{},
            .opcodes = std.AutoHashMap(Opcode, OpcodeImpl).init(allocator),
            .accounts = std.AutoHashMap([20]u8, Account).init(allocator),
            .current_transaction = null,

            // Initialize environmental values with defaults
            .current_address = [_]u8{0} ** 20,
            .caller_address = [_]u8{0} ** 20,
            .origin_address = [_]u8{0} ** 20,
            .call_value = BigInt.init(0),
            .gas_price = BigInt.init(20000000000), // 20 gwei default
            .block_timestamp = 1640995200, // Default timestamp (Jan 1, 2022)
            .block_number = 1,
            .block_difficulty = BigInt.init(1000000),
            .block_gas_limit = 30000000, // 30M gas limit
            .chain_id = 1, // Ethereum mainnet
            .base_fee = BigInt.init(10000000000), // 10 gwei default
            .calldata = &[_]u8{},
            .return_data = &[_]u8{},
            .stop_execution = false,
            .execution_reverted = false,
            .coinbase = [_]u8{0} ** 20,
            .block_hashes = std.AutoHashMap(u64, [32]u8).init(allocator),
            .logs = std.array_list.Managed(Log).init(allocator),
            .call_stack = CallStack.init(allocator),
            .access = null,
            .view = null,
            .warm_accounts = std.AutoHashMap([20]u8, void).init(allocator),
            .warm_slots = StateKeyHashMap(void).init(allocator),
            .original_values = StateKeyHashMap(BigInt).init(allocator),
            .gas_refund = 0,
            .journal = .{},
        };
        try evm.loadOpcodes();
        return evm;
    }

    pub fn setGasLimit(self: *EVM, gas_limit: u64) void {
        self.gas_limit = gas_limit;
        self.gas = gas_limit;
        self.gas_used = 0;
    }

    /// Reset transient execution state (stack, memory, pc, gas, flags) so the
    /// instance can run another transaction's bytecode. Used by the parallel
    /// block executor, which reuses one EVM per worker across (re-)executions.
    /// Persistent state (`accounts`) and the attached `view` are left intact.
    pub fn resetForExecution(self: *EVM, code: []const u8, current_address: [20]u8, gas: u64) void {
        self.stack.items.clearRetainingCapacity();
        self.memory.data.clearRetainingCapacity();
        self.pc = 0;
        self.gas = gas;
        self.gas_limit = gas;
        self.gas_used = 0;
        self.stop_execution = false;
        self.execution_reverted = false;
        self.return_data = &[_]u8{};
        self.code = code;
        self.current_address = current_address;
        // EIP-2929: fresh access list per transaction. The executing account is
        // pre-warmed (as the tx target would be); its storage slots start cold.
        self.warm_accounts.clearRetainingCapacity();
        self.warm_slots.clearRetainingCapacity();
        self.original_values.clearRetainingCapacity();
        self.gas_refund = 0;
        self.journal.clearRetainingCapacity();
        self.warm_accounts.put(current_address, {}) catch {};
    }

    /// Read the current value of a word-valued (storage/balance) key without
    /// recording an access — used to capture the pre-write value for the journal.
    fn peekState(self: *EVM, key: StateKey) BigInt {
        if (self.view) |v| return v.peek(key);
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
            else => return BigInt.zero(),
        }
    }

    /// Restore the value of `key` to `value` directly (used when unwinding the
    /// journal on revert); does not itself journal.
    fn restoreState(self: *EVM, key: StateKey, value: BigInt) void {
        if (self.view) |v| {
            v.write(key, value) catch {};
            return;
        }
        switch (key.tag) {
            .storage => {
                const acct = self.getOrCreateAccount(key.address) catch return;
                if (value.isZero()) {
                    _ = acct.storage.remove(key.slot);
                } else {
                    acct.storage.put(key.slot, value) catch {};
                }
            },
            .balance => {
                const acct = self.getOrCreateAccount(key.address) catch return;
                acct.balance = value;
            },
            else => {},
        }
    }

    /// Unwind the journal back to `marker`, restoring each touched key to its
    /// prior value (highest index first, so the earliest prior value wins).
    pub fn revertTo(self: *EVM, marker: usize) void {
        var i = self.journal.items.len;
        while (i > marker) {
            i -= 1;
            const e = self.journal.items[i];
            self.restoreState(e.key, e.old);
        }
        self.journal.shrinkRetainingCapacity(marker);
    }

    /// EIP-2200: return the storage slot's value at the start of this
    /// transaction, capturing it on first SSTORE. `current` is the value read
    /// immediately before the write; on the first SSTORE for a slot it equals
    /// the pre-transaction value (no earlier write this tx), so caching it gives
    /// the original for all subsequent SSTOREs.
    pub fn captureOriginal(self: *EVM, address: [20]u8, slot: BigInt, current: BigInt) !BigInt {
        const gop = try self.original_values.getOrPut(StateKey.storageOf(address, slot));
        if (!gop.found_existing) gop.value_ptr.* = current;
        return gop.value_ptr.*;
    }

    /// EIP-2929: record access to an account, returning whether it was *cold*
    /// (not previously accessed in this transaction). Marks it warm.
    pub fn accessAccount(self: *EVM, address: [20]u8) !bool {
        const gop = try self.warm_accounts.getOrPut(address);
        return !gop.found_existing;
    }

    /// EIP-2929: record access to a storage slot, returning whether it was
    /// *cold*. Marks it warm.
    pub fn accessSlot(self: *EVM, address: [20]u8, slot: BigInt) !bool {
        const gop = try self.warm_slots.getOrPut(StateKey.storageOf(address, slot));
        return !gop.found_existing;
    }

    pub fn getGasCost(opcode: Opcode) u64 {
        return switch (opcode) {
            // Base costs
            .STOP => 0,
            .ADD, .SUB, .MUL, .DIV, .SDIV, .MOD, .SMOD, .ADDMOD, .MULMOD => 3,
            .EXP => 10, // Base cost, actual cost depends on exponent
            .SIGNEXTEND => 5,

            // Comparison operations
            .LT, .GT, .SLT, .SGT, .EQ, .ISZERO => 3,

            // Bitwise operations
            .AND, .OR, .XOR, .NOT, .BYTE => 3,
            .SHL, .SHR, .SAR => 3,

            // Hash operations
            .SHA3 => 30, // Base cost, additional cost per word

            // Environmental operations
            .ADDRESS, .ORIGIN, .CALLER, .GASPRICE, .TIMESTAMP, .NUMBER,
            .DIFFICULTY, .GASLIMIT, .CHAINID, .BASEFEE => 2,
            .BALANCE => 0, // EIP-2929 cold/warm cost charged in-opcode
            .EXTCODESIZE, .EXTCODEHASH, .EXTCODECOPY => 0, // EIP-2929 account access charged in-opcode
            .SELFBALANCE => 5,

            // Stack operations
            .POP => 2,
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8,
            .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16,
            .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24,
            .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => 3,

            .DUP1, .DUP2, .DUP3, .DUP4, .DUP5, .DUP6, .DUP7, .DUP8,
            .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16 => 3,

            .SWAP1, .SWAP2, .SWAP3, .SWAP4, .SWAP5, .SWAP6, .SWAP7, .SWAP8,
            .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16 => 3,

            // Memory operations
            .MLOAD, .MSTORE, .MSTORE8 => 3,
            .MSIZE => 2,

            // Storage operations
            .SLOAD => 0, // EIP-2929 cold/warm cost charged in-opcode
            .SSTORE => 0, // EIP-2929/2200/3529 cost charged in-opcode

            // Flow control
            .JUMP => 8,
            .JUMPI => 10,
            .PC => 2,
            .GAS => 2,
            .JUMPDEST => 1,

            // Other operations with default costs
            else => 3,
        };
    }

    pub fn consumeGas(self: *EVM, amount: u64) !void {
        if (self.gas < amount) {
            return error.OutOfGas;
        }
        self.gas -= amount;
        self.gas_used += amount;
    }

    pub fn getGasInfo(self: *EVM) struct { used: u64, remaining: u64, limit: u64 } {
        return .{
            .used = self.gas_used,
            .remaining = self.gas,
            .limit = self.gas_limit,
        };
    }

    pub fn deinit(self: *EVM) void {
        self.stack.deinit(self.allocator);
        self.memory.deinit(self.allocator);
        self.opcodes.deinit();
        // Each account owns a storage hash map and (when non-empty) an
        // allocator-owned code buffer; free both before the accounts map.
        var account_it = self.accounts.valueIterator();
        while (account_it.next()) |account| {
            account.storage.deinit();
            if (account.code.len > 0) self.allocator.free(account.code);
        }
        self.accounts.deinit();
        self.block_hashes.deinit();
        // Clean up logs
        for (self.logs.items) |*log| {
            log.deinit(self.allocator);
        }
        self.logs.deinit();
        self.call_stack.deinit();
        self.warm_accounts.deinit();
        self.warm_slots.deinit();
        self.original_values.deinit();
        self.journal.deinit(self.allocator);
        // return_data, when non-empty, is an allocator-owned buffer (RETURN /
        // REVERT / CALL); the empty default is a static slice.
        if (self.return_data.len > 0) self.allocator.free(self.return_data);
        self.allocator.destroy(self);
    }

    pub fn loadOpcodes(self: *EVM) !void {
        // Manually register opcodes
        const add_impl = @import("opcodes/add.zig").getImpl();
        try self.opcodes.put(@enumFromInt(add_impl.code), add_impl.impl);

        const mul_impl = @import("opcodes/mul.zig").getImpl();
        try self.opcodes.put(@enumFromInt(mul_impl.code), mul_impl.impl);

        const sub_impl = @import("opcodes/sub.zig").getImpl();
        try self.opcodes.put(@enumFromInt(sub_impl.code), sub_impl.impl);

        const div_impl = @import("opcodes/div.zig").getImpl();
        try self.opcodes.put(@enumFromInt(div_impl.code), div_impl.impl);

        const mod_impl = @import("opcodes/mod.zig").getImpl();
        try self.opcodes.put(@enumFromInt(mod_impl.code), mod_impl.impl);

        const push1_impl = @import("opcodes/push1.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push1_impl.code), push1_impl.impl);

        const stop_impl = @import("opcodes/stop.zig").getImpl();
        try self.opcodes.put(@enumFromInt(stop_impl.code), stop_impl.impl);

        const pop_impl = @import("opcodes/pop.zig").getImpl();
        try self.opcodes.put(@enumFromInt(pop_impl.code), pop_impl.impl);

        // Comparison opcodes
        const lt_impl = @import("opcodes/lt.zig").getImpl();
        try self.opcodes.put(@enumFromInt(lt_impl.code), lt_impl.impl);

        const gt_impl = @import("opcodes/gt.zig").getImpl();
        try self.opcodes.put(@enumFromInt(gt_impl.code), gt_impl.impl);

        const eq_impl = @import("opcodes/eq.zig").getImpl();
        try self.opcodes.put(@enumFromInt(eq_impl.code), eq_impl.impl);

        const iszero_impl = @import("opcodes/iszero.zig").getImpl();
        try self.opcodes.put(@enumFromInt(iszero_impl.code), iszero_impl.impl);

        // Bitwise opcodes
        const and_impl = @import("opcodes/and.zig").getImpl();
        try self.opcodes.put(@enumFromInt(and_impl.code), and_impl.impl);

        const or_impl = @import("opcodes/or.zig").getImpl();
        try self.opcodes.put(@enumFromInt(or_impl.code), or_impl.impl);

        const xor_impl = @import("opcodes/xor.zig").getImpl();
        try self.opcodes.put(@enumFromInt(xor_impl.code), xor_impl.impl);

        const not_impl = @import("opcodes/not.zig").getImpl();
        try self.opcodes.put(@enumFromInt(not_impl.code), not_impl.impl);

        // Stack opcodes
        const dup1_impl = @import("opcodes/dup1.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup1_impl.code), dup1_impl.impl);

        const swap1_impl = @import("opcodes/swap1.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap1_impl.code), swap1_impl.impl);

        // Extended push opcodes
        const push2_impl = @import("opcodes/push2.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push2_impl.code), push2_impl.impl);

        const push4_impl = @import("opcodes/push4.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push4_impl.code), push4_impl.impl);

        const push32_impl = @import("opcodes/push32.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push32_impl.code), push32_impl.impl);

        // Extended stack opcodes
        const dup2_impl = @import("opcodes/dup2.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup2_impl.code), dup2_impl.impl);

        const swap2_impl = @import("opcodes/swap2.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap2_impl.code), swap2_impl.impl);

        // Memory opcodes
        const mload_impl = @import("opcodes/mload.zig").getImpl();
        try self.opcodes.put(@enumFromInt(mload_impl.code), mload_impl.impl);

        const mstore_impl = @import("opcodes/mstore.zig").getImpl();
        try self.opcodes.put(@enumFromInt(mstore_impl.code), mstore_impl.impl);

        const mstore8_impl = @import("opcodes/mstore8.zig").getImpl();
        try self.opcodes.put(@enumFromInt(mstore8_impl.code), mstore8_impl.impl);

        const msize_impl = @import("opcodes/msize.zig").getImpl();
        try self.opcodes.put(@enumFromInt(msize_impl.code), msize_impl.impl);

        // Flow control opcodes
        const jump_impl = @import("opcodes/jump.zig").getImpl();
        try self.opcodes.put(@enumFromInt(jump_impl.code), jump_impl.impl);

        const jumpi_impl = @import("opcodes/jumpi.zig").getImpl();
        try self.opcodes.put(@enumFromInt(jumpi_impl.code), jumpi_impl.impl);

        const jumpdest_impl = @import("opcodes/jumpdest.zig").getImpl();
        try self.opcodes.put(@enumFromInt(jumpdest_impl.code), jumpdest_impl.impl);

        const pc_impl = @import("opcodes/pc.zig").getImpl();
        try self.opcodes.put(@enumFromInt(pc_impl.code), pc_impl.impl);

        // Additional push opcodes
        const push3_impl = @import("opcodes/push3.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push3_impl.code), push3_impl.impl);

        // Signed arithmetic opcodes
        const sdiv_impl = @import("opcodes/sdiv.zig").getImpl();
        try self.opcodes.put(@enumFromInt(sdiv_impl.code), sdiv_impl.impl);

        const slt_impl = @import("opcodes/slt.zig").getImpl();
        try self.opcodes.put(@enumFromInt(slt_impl.code), slt_impl.impl);

        // Additional stack opcodes
        const dup3_impl = @import("opcodes/dup3.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup3_impl.code), dup3_impl.impl);

        const dup4_impl = @import("opcodes/dup4.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup4_impl.code), dup4_impl.impl);

        const dup5_impl = @import("opcodes/dup5.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup5_impl.code), dup5_impl.impl);

        const dup6_impl = @import("opcodes/dup6.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup6_impl.code), dup6_impl.impl);

        const dup7_impl = @import("opcodes/dup7.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup7_impl.code), dup7_impl.impl);

        const dup8_impl = @import("opcodes/dup8.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup8_impl.code), dup8_impl.impl);

        const dup9_impl = @import("opcodes/dup9.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup9_impl.code), dup9_impl.impl);

        const dup10_impl = @import("opcodes/dup10.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup10_impl.code), dup10_impl.impl);

        const dup11_impl = @import("opcodes/dup11.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup11_impl.code), dup11_impl.impl);

        const dup12_impl = @import("opcodes/dup12.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup12_impl.code), dup12_impl.impl);

        const dup13_impl = @import("opcodes/dup13.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup13_impl.code), dup13_impl.impl);

        const dup14_impl = @import("opcodes/dup14.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup14_impl.code), dup14_impl.impl);

        const dup15_impl = @import("opcodes/dup15.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup15_impl.code), dup15_impl.impl);

        const dup16_impl = @import("opcodes/dup16.zig").getImpl();
        try self.opcodes.put(@enumFromInt(dup16_impl.code), dup16_impl.impl);

        const swap3_impl = @import("opcodes/swap3.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap3_impl.code), swap3_impl.impl);

        const swap4_impl = @import("opcodes/swap4.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap4_impl.code), swap4_impl.impl);

        const swap5_impl = @import("opcodes/swap5.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap5_impl.code), swap5_impl.impl);

        const swap6_impl = @import("opcodes/swap6.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap6_impl.code), swap6_impl.impl);

        const swap7_impl = @import("opcodes/swap7.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap7_impl.code), swap7_impl.impl);

        const swap8_impl = @import("opcodes/swap8.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap8_impl.code), swap8_impl.impl);

        const swap9_impl = @import("opcodes/swap9.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap9_impl.code), swap9_impl.impl);

        const swap10_impl = @import("opcodes/swap10.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap10_impl.code), swap10_impl.impl);

        const swap11_impl = @import("opcodes/swap11.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap11_impl.code), swap11_impl.impl);

        const swap12_impl = @import("opcodes/swap12.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap12_impl.code), swap12_impl.impl);

        const swap13_impl = @import("opcodes/swap13.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap13_impl.code), swap13_impl.impl);

        const swap14_impl = @import("opcodes/swap14.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap14_impl.code), swap14_impl.impl);

        const swap15_impl = @import("opcodes/swap15.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap15_impl.code), swap15_impl.impl);

        const swap16_impl = @import("opcodes/swap16.zig").getImpl();
        try self.opcodes.put(@enumFromInt(swap16_impl.code), swap16_impl.impl);

        // Additional arithmetic opcodes
        const smod_impl = @import("opcodes/smod.zig").getImpl();
        try self.opcodes.put(@enumFromInt(smod_impl.code), smod_impl.impl);

        const addmod_impl = @import("opcodes/addmod.zig").getImpl();
        try self.opcodes.put(@enumFromInt(addmod_impl.code), addmod_impl.impl);

        const mulmod_impl = @import("opcodes/mulmod.zig").getImpl();
        try self.opcodes.put(@enumFromInt(mulmod_impl.code), mulmod_impl.impl);

        const exp_impl = @import("opcodes/exp.zig").getImpl();
        try self.opcodes.put(@enumFromInt(exp_impl.code), exp_impl.impl);

        // Additional comparison opcode
        const sgt_impl = @import("opcodes/sgt.zig").getImpl();
        try self.opcodes.put(@enumFromInt(sgt_impl.code), sgt_impl.impl);

        // Shift operations
        const shl_impl = @import("opcodes/shl.zig").getImpl();
        try self.opcodes.put(@enumFromInt(shl_impl.code), shl_impl.impl);

        const shr_impl = @import("opcodes/shr.zig").getImpl();
        try self.opcodes.put(@enumFromInt(shr_impl.code), shr_impl.impl);

        const sar_impl = @import("opcodes/sar.zig").getImpl();
        try self.opcodes.put(@enumFromInt(sar_impl.code), sar_impl.impl);

        // Additional PUSH opcodes
        const push5_impl = @import("opcodes/push5.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push5_impl.code), push5_impl.impl);

        const push6_impl = @import("opcodes/push6.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push6_impl.code), push6_impl.impl);

        const push7_impl = @import("opcodes/push7.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push7_impl.code), push7_impl.impl);

        const push8_impl = @import("opcodes/push8.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push8_impl.code), push8_impl.impl);

        const push9_impl = @import("opcodes/push9.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push9_impl.code), push9_impl.impl);

        const push10_impl = @import("opcodes/push10.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push10_impl.code), push10_impl.impl);

        const push11_impl = @import("opcodes/push11.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push11_impl.code), push11_impl.impl);

        const push12_impl = @import("opcodes/push12.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push12_impl.code), push12_impl.impl);

        const push13_impl = @import("opcodes/push13.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push13_impl.code), push13_impl.impl);

        const push14_impl = @import("opcodes/push14.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push14_impl.code), push14_impl.impl);

        const push15_impl = @import("opcodes/push15.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push15_impl.code), push15_impl.impl);

        const push16_impl = @import("opcodes/push16.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push16_impl.code), push16_impl.impl);

        const push17_impl = @import("opcodes/push17.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push17_impl.code), push17_impl.impl);

        const push18_impl = @import("opcodes/push18.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push18_impl.code), push18_impl.impl);

        const push19_impl = @import("opcodes/push19.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push19_impl.code), push19_impl.impl);

        const push20_impl = @import("opcodes/push20.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push20_impl.code), push20_impl.impl);

        const push21_impl = @import("opcodes/push21.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push21_impl.code), push21_impl.impl);

        const push22_impl = @import("opcodes/push22.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push22_impl.code), push22_impl.impl);

        const push23_impl = @import("opcodes/push23.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push23_impl.code), push23_impl.impl);

        const push24_impl = @import("opcodes/push24.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push24_impl.code), push24_impl.impl);

        const push25_impl = @import("opcodes/push25.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push25_impl.code), push25_impl.impl);

        const push26_impl = @import("opcodes/push26.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push26_impl.code), push26_impl.impl);

        const push27_impl = @import("opcodes/push27.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push27_impl.code), push27_impl.impl);

        const push28_impl = @import("opcodes/push28.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push28_impl.code), push28_impl.impl);

        const push29_impl = @import("opcodes/push29.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push29_impl.code), push29_impl.impl);

        const push30_impl = @import("opcodes/push30.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push30_impl.code), push30_impl.impl);

        const push31_impl = @import("opcodes/push31.zig").getImpl();
        try self.opcodes.put(@enumFromInt(push31_impl.code), push31_impl.impl);

        // Environmental opcodes
        const address_impl = @import("opcodes/address.zig").getImpl();
        try self.opcodes.put(@enumFromInt(address_impl.code), address_impl.impl);

        const balance_impl = @import("opcodes/balance.zig").getImpl();
        try self.opcodes.put(@enumFromInt(balance_impl.code), balance_impl.impl);

        const origin_impl = @import("opcodes/origin.zig").getImpl();
        try self.opcodes.put(@enumFromInt(origin_impl.code), origin_impl.impl);

        const caller_impl = @import("opcodes/caller.zig").getImpl();
        try self.opcodes.put(@enumFromInt(caller_impl.code), caller_impl.impl);

        const gasprice_impl = @import("opcodes/gasprice.zig").getImpl();
        try self.opcodes.put(@enumFromInt(gasprice_impl.code), gasprice_impl.impl);

        const timestamp_impl = @import("opcodes/timestamp.zig").getImpl();
        try self.opcodes.put(@enumFromInt(timestamp_impl.code), timestamp_impl.impl);

        const number_impl = @import("opcodes/number.zig").getImpl();
        try self.opcodes.put(@enumFromInt(number_impl.code), number_impl.impl);

        const difficulty_impl = @import("opcodes/difficulty.zig").getImpl();
        try self.opcodes.put(@enumFromInt(difficulty_impl.code), difficulty_impl.impl);

        const gaslimit_impl = @import("opcodes/gaslimit.zig").getImpl();
        try self.opcodes.put(@enumFromInt(gaslimit_impl.code), gaslimit_impl.impl);

        const chainid_impl = @import("opcodes/chainid.zig").getImpl();
        try self.opcodes.put(@enumFromInt(chainid_impl.code), chainid_impl.impl);

        const selfbalance_impl = @import("opcodes/selfbalance.zig").getImpl();
        try self.opcodes.put(@enumFromInt(selfbalance_impl.code), selfbalance_impl.impl);

        const basefee_impl = @import("opcodes/basefee.zig").getImpl();
        try self.opcodes.put(@enumFromInt(basefee_impl.code), basefee_impl.impl);

        const gas_impl = @import("opcodes/gas.zig").getImpl();
        try self.opcodes.put(@enumFromInt(gas_impl.code), gas_impl.impl);

        // Storage opcodes
        const sload_impl = @import("opcodes/sload.zig").getImpl();
        try self.opcodes.put(@enumFromInt(sload_impl.code), sload_impl.impl);

        const sstore_impl = @import("opcodes/sstore.zig").getImpl();
        try self.opcodes.put(@enumFromInt(sstore_impl.code), sstore_impl.impl);

        // Calldata opcodes
        const calldataload_impl = @import("opcodes/calldataload.zig").getImpl();
        try self.opcodes.put(@enumFromInt(calldataload_impl.code), calldataload_impl.impl);

        const calldatasize_impl = @import("opcodes/calldatasize.zig").getImpl();
        try self.opcodes.put(@enumFromInt(calldatasize_impl.code), calldatasize_impl.impl);

        const calldatacopy_impl = @import("opcodes/calldatacopy.zig").getImpl();
        try self.opcodes.put(@enumFromInt(calldatacopy_impl.code), calldatacopy_impl.impl);

        const callvalue_impl = @import("opcodes/callvalue.zig").getImpl();
        try self.opcodes.put(@enumFromInt(callvalue_impl.code), callvalue_impl.impl);

        // Byte operations
        const byte_impl = @import("opcodes/byte.zig").getImpl();
        try self.opcodes.put(@enumFromInt(byte_impl.code), byte_impl.impl);

        const signextend_impl = @import("opcodes/signextend.zig").getImpl();
        try self.opcodes.put(@enumFromInt(signextend_impl.code), signextend_impl.impl);

        // Return opcodes
        const return_impl = @import("opcodes/return.zig").getImpl();
        try self.opcodes.put(@enumFromInt(return_impl.code), return_impl.impl);

        const revert_impl = @import("opcodes/revert.zig").getImpl();
        try self.opcodes.put(@enumFromInt(revert_impl.code), revert_impl.impl);

        const returndatasize_impl = @import("opcodes/returndatasize.zig").getImpl();
        try self.opcodes.put(@enumFromInt(returndatasize_impl.code), returndatasize_impl.impl);

        const returndatacopy_impl = @import("opcodes/returndatacopy.zig").getImpl();
        try self.opcodes.put(@enumFromInt(returndatacopy_impl.code), returndatacopy_impl.impl);

        // Code opcodes
        const codesize_impl = @import("opcodes/codesize.zig").getImpl();
        try self.opcodes.put(@enumFromInt(codesize_impl.code), codesize_impl.impl);

        const codecopy_impl = @import("opcodes/codecopy.zig").getImpl();
        try self.opcodes.put(@enumFromInt(codecopy_impl.code), codecopy_impl.impl);

        const extcodesize_impl = @import("opcodes/extcodesize.zig").getImpl();
        try self.opcodes.put(@enumFromInt(extcodesize_impl.code), extcodesize_impl.impl);

        const extcodecopy_impl = @import("opcodes/extcodecopy.zig").getImpl();
        try self.opcodes.put(@enumFromInt(extcodecopy_impl.code), extcodecopy_impl.impl);

        const extcodehash_impl = @import("opcodes/extcodehash.zig").getImpl();
        try self.opcodes.put(@enumFromInt(extcodehash_impl.code), extcodehash_impl.impl);

        // Block opcodes
        const blockhash_impl = @import("opcodes/blockhash.zig").getImpl();
        try self.opcodes.put(@enumFromInt(blockhash_impl.code), blockhash_impl.impl);

        const coinbase_impl = @import("opcodes/coinbase.zig").getImpl();
        try self.opcodes.put(@enumFromInt(coinbase_impl.code), coinbase_impl.impl);

        // Hash opcodes
        const sha3_impl = @import("opcodes/sha3.zig").getImpl();
        try self.opcodes.put(@enumFromInt(sha3_impl.code), sha3_impl.impl);

        // Contract creation opcodes
        const create_impl = @import("opcodes/create.zig").getImpl();
        try self.opcodes.put(@enumFromInt(create_impl.code), create_impl.impl);

        const create2_impl = @import("opcodes/create2.zig").getImpl();
        try self.opcodes.put(@enumFromInt(create2_impl.code), create2_impl.impl);

        // Call opcodes
        const call_impl = @import("opcodes/call.zig").getImpl();
        try self.opcodes.put(@enumFromInt(call_impl.code), call_impl.impl);

        const callcode_impl = @import("opcodes/callcode.zig").getImpl();
        try self.opcodes.put(@enumFromInt(callcode_impl.code), callcode_impl.impl);

        const delegatecall_impl = @import("opcodes/delegatecall.zig").getImpl();
        try self.opcodes.put(@enumFromInt(delegatecall_impl.code), delegatecall_impl.impl);

        const staticcall_impl = @import("opcodes/staticcall.zig").getImpl();
        try self.opcodes.put(@enumFromInt(staticcall_impl.code), staticcall_impl.impl);

        // Logging opcodes
        const log0_impl = @import("opcodes/log0.zig").getImpl();
        try self.opcodes.put(@enumFromInt(log0_impl.code), log0_impl.impl);

        const log1_impl = @import("opcodes/log1.zig").getImpl();
        try self.opcodes.put(@enumFromInt(log1_impl.code), log1_impl.impl);

        const log2_impl = @import("opcodes/log2.zig").getImpl();
        try self.opcodes.put(@enumFromInt(log2_impl.code), log2_impl.impl);

        const log3_impl = @import("opcodes/log3.zig").getImpl();
        try self.opcodes.put(@enumFromInt(log3_impl.code), log3_impl.impl);

        const log4_impl = @import("opcodes/log4.zig").getImpl();
        try self.opcodes.put(@enumFromInt(log4_impl.code), log4_impl.impl);
    }

    pub fn execute(self: *EVM) !void {
        // Reset execution flags
        self.stop_execution = false;
        self.execution_reverted = false;

        while (self.pc < self.code.len and !self.stop_execution) {
            const opcode = @as(Opcode, @enumFromInt(self.code[self.pc]));

            // Consume gas for the opcode
            const gas_cost = EVM.getGasCost(opcode);
            try self.consumeGas(gas_cost);

            self.pc += 1;

            const impl = self.opcodes.get(opcode) orelse return error.UnknownOpcode;
            try impl.execute(self);

            if (opcode == .STOP) break;
        }
    }

    pub fn applyTransaction(self: *EVM, transaction: Transaction) !void {
        var from_account = try self.getOrCreateAccount(transaction.from);
        if (from_account.balance.lt(transaction.value)) {
            return error.InsufficientBalance;
        }

        from_account.balance = from_account.balance.sub(transaction.value);
        from_account.nonce += 1;

        if (transaction.to) |to| {
            var to_account = try self.getOrCreateAccount(to);
            to_account.balance = to_account.balance.add(transaction.value);

            if (to_account.code.len > 0) {
                self.current_transaction = transaction;
                self.code = to_account.code;
                self.pc = 0;
                self.gas = transaction.gas_limit;
                try self.execute();
                self.current_transaction = null;
            }
        } else {
            // Contract creation
            const new_account = Account{
                .balance = transaction.value,
                .nonce = 0,
                .code = try self.allocator.dupe(u8, transaction.data),
                .storage = std.AutoHashMap(BigInt, BigInt).init(self.allocator),
            };
            // Generate new address (simplified for this example)
            var new_address: [20]u8 = undefined;
            var hash: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(&transaction.from, &hash, .{});
            for (0..20) |i| {
                new_address[i] = hash[i];
            }
            try self.accounts.put(new_address, new_account);
        }
    }

    /// Execute a complete top-level transaction against the current world
    /// state: intrinsic gas, nonce bump, value transfer, then either contract
    /// execution (callee with code) or contract creation (to == null), with the
    /// EIP-3529 refund applied at the end. Returns whether the transaction
    /// succeeded. This is the entry point a block replay harness drives.
    pub fn executeTransaction(self: *EVM, tx: Transaction) !bool {
        self.resetForExecution(&[_]u8{}, tx.from, tx.gas_limit);
        self.origin_address = tx.from;
        self.caller_address = tx.from;
        self.call_value = tx.value;

        // Intrinsic gas (base; calldata/access-list costs omitted for now).
        try self.consumeGas(21000);

        const from_bal = try self.loadBalance(tx.from);
        if (from_bal.lt(tx.value)) return error.InsufficientBalance;

        const sender_nonce: u64 = if (self.accounts.get(tx.from)) |a| a.nonce else 0;
        if (self.accounts.getPtr(tx.from)) |a| a.nonce += 1;

        if (tx.to) |to_addr| {
            if (!tx.value.isZero()) {
                try self.storeBalance(tx.from, from_bal.sub(tx.value));
                const tb = try self.loadBalance(to_addr);
                try self.storeBalance(to_addr, tb.add(tx.value));
            }
            _ = try self.accessAccount(to_addr);
            const code = if (self.accounts.get(to_addr)) |acc| acc.code else &[_]u8{};
            if (code.len == 0) {
                self.applyRefund();
                return true; // plain value transfer
            }
            const ok = try self.runSubContext(code, to_addr, tx.from, tx.value, tx.data, false, self.gas);
            self.applyRefund();
            return ok;
        }

        // Contract-creation transaction: run tx.data as init code at the
        // CREATE address and adopt its RETURN data as the deployed code.
        const new_address = crypto.createAddress(tx.from, sender_nonce);
        if (!self.accounts.contains(new_address)) {
            try self.accounts.put(new_address, .{
                .balance = BigInt.zero(),
                .nonce = 0,
                .code = &[_]u8{},
                .storage = std.AutoHashMap(BigInt, BigInt).init(self.allocator),
            });
        }
        if (!tx.value.isZero()) {
            try self.storeBalance(tx.from, from_bal.sub(tx.value));
            const nb = try self.loadBalance(new_address);
            try self.storeBalance(new_address, nb.add(tx.value));
        }
        const ok = try self.runSubContext(tx.data, new_address, tx.from, tx.value, &[_]u8{}, false, self.gas);
        if (ok) {
            if (self.accounts.getPtr(new_address)) |acct| {
                if (acct.code.len > 0) self.allocator.free(acct.code);
                acct.code = try self.allocator.dupe(u8, self.return_data);
            }
        }
        self.applyRefund();
        return ok;
    }

    fn getOrCreateAccount(self: *EVM, address: [20]u8) !*Account {
        if (self.accounts.getPtr(address)) |account| {
            return account;
        } else {
            const new_account = Account{
                .balance = BigInt.init(0),
                .nonce = 0,
                .code = &[_]u8{},
                .storage = std.AutoHashMap(BigInt, BigInt).init(self.allocator),
            };
            try self.accounts.put(address, new_account);
            return self.accounts.getPtr(address).?;
        }
    }

    // ============================================================
    // Recording state-access helpers
    //
    // All state-touching opcodes route through these so that, when an
    // AccessRecorder is attached, the transaction's read/write set is captured
    // at storage-slot granularity. The state semantics are identical to the
    // direct map access they replace; the only addition is the recording.
    // ============================================================

    /// SLOAD-style read of a storage slot. Records a read of
    /// storage(address, slot); returns zero for absent slots/accounts.
    pub fn loadStorage(self: *EVM, address: [20]u8, slot: BigInt) !BigInt {
        if (self.view) |v| return try v.read(StateKey.storageOf(address, slot));
        if (self.access) |rec| try rec.recordRead(StateKey.storageOf(address, slot));
        if (self.accounts.getPtr(address)) |account| {
            return account.storage.get(slot) orelse BigInt.zero();
        }
        return BigInt.zero();
    }

    /// SSTORE-style write of a storage slot. Records a write of
    /// storage(address, slot). Writing zero clears the slot, matching the
    /// previous SSTORE behaviour.
    pub fn storeStorage(self: *EVM, address: [20]u8, slot: BigInt, value: BigInt) !void {
        const key = StateKey.storageOf(address, slot);
        try self.journal.append(self.allocator, .{ .key = key, .old = self.peekState(key) });
        if (self.view) |v| {
            try v.write(key, value);
            return;
        }
        if (self.access) |rec| try rec.recordWrite(key);
        const account = try self.getOrCreateAccount(address);
        if (value.isZero()) {
            _ = account.storage.remove(slot);
        } else {
            try account.storage.put(slot, value);
        }
    }

    /// BALANCE/SELFBALANCE-style read. Records a read of balance(address).
    pub fn loadBalance(self: *EVM, address: [20]u8) !BigInt {
        if (self.view) |v| return try v.read(StateKey.balanceOf(address));
        if (self.access) |rec| try rec.recordRead(StateKey.balanceOf(address));
        if (self.accounts.get(address)) |account| return account.balance;
        return BigInt.init(0);
    }

    /// Set an account balance (e.g. a CALL value transfer). Records a write of
    /// balance(address) and routes through the versioned view when attached, so
    /// value transfers are serializable under parallel execution.
    pub fn storeBalance(self: *EVM, address: [20]u8, value: BigInt) !void {
        const key = StateKey.balanceOf(address);
        try self.journal.append(self.allocator, .{ .key = key, .old = self.peekState(key) });
        if (self.view) |v| {
            try v.write(key, value);
            return;
        }
        if (self.access) |rec| try rec.recordWrite(key);
        const account = try self.getOrCreateAccount(address);
        account.balance = value;
    }

    /// Record a read of `key` whose value is read from `accounts` directly
    /// (account code/existence). Routes to the view's read set or the recorder.
    pub fn noteRead(self: *EVM, key: StateKey) !void {
        if (self.view) |v| {
            try v.recordReadKey(key);
        } else if (self.access) |rec| {
            try rec.recordRead(key);
        }
    }

    /// Record a write of `key` whose value is tracked elsewhere.
    pub fn noteWrite(self: *EVM, key: StateKey) !void {
        if (self.view) |v| {
            try v.recordWriteKey(key);
        } else if (self.access) |rec| {
            try rec.recordWrite(key);
        }
    }

    /// Apply the EIP-3529 gas refund at the end of a transaction: refund up to
    /// gas_used/5, moving it back from gas_used to remaining gas.
    pub fn applyRefund(self: *EVM) void {
        const cap = self.gas_used / 5;
        const refund: u64 = if (self.gas_refund <= 0) 0 else @intCast(self.gas_refund);
        const applied = @min(refund, cap);
        self.gas_used -= applied;
        self.gas += applied;
    }

    /// Execute `code` in a nested call frame: a fresh stack and memory, the
    /// given address/caller/value/calldata, sharing the same world state, gas
    /// counter, access list, and access recorder as the parent (so sub-call
    /// state accesses are recorded under the same transaction). Returns whether
    /// the sub-call succeeded (false on revert or error). On return,
    /// `self.return_data` holds the sub-call's output.
    ///
    /// State changes are NOT yet journaled, so a reverted sub-call's writes are
    /// not rolled back — a known limitation tracked for the E1 milestone.
    pub fn runSubContext(
        self: *EVM,
        code: []const u8,
        address: [20]u8,
        caller: [20]u8,
        value: BigInt,
        calldata: []const u8,
        is_static: bool,
        gas_limit: u64,
    ) !bool {
        if (self.call_stack.depth() >= CallStack.MAX_CALL_DEPTH) return false;
        const frame = CallFrame.init(caller, address, address, self.origin_address, value, calldata, self.gas, code, is_static, false, false, @intCast(self.call_stack.depth()));
        self.call_stack.push(frame) catch return false;

        // Snapshot points to undo on revert: the state journal and the refund
        // accumulator are rolled back; the EIP-2929 access list is not (warm
        // stays warm across reverts).
        const journal_marker = self.journal.items.len;
        const refund_marker = self.gas_refund;

        // Gas forwarding: the sub-call runs against a budget (caller already
        // applied the 63/64 reservation + stipend); the reserved remainder is
        // withheld and returned to the parent afterwards, along with any unused
        // sub-call gas.
        const budget = @min(gas_limit, self.gas);
        const reserved = self.gas - budget;
        self.gas = budget;

        // Save the parent execution context.
        const saved_stack = self.stack;
        const saved_memory = self.memory;
        const saved_pc = self.pc;
        const saved_code = self.code;
        const saved_addr = self.current_address;
        const saved_caller = self.caller_address;
        const saved_value = self.call_value;
        const saved_calldata = self.calldata;
        const saved_reverted = self.execution_reverted;

        // Install the sub-frame: own stack/memory; clear prior return data so a
        // sub-call that STOPs (no RETURN) yields empty output.
        if (self.return_data.len > 0) self.allocator.free(self.return_data);
        self.return_data = &[_]u8{};
        self.stack = Stack.init(self.allocator);
        self.memory = Memory.init(self.allocator);
        self.code = code;
        self.calldata = calldata;
        self.current_address = address;
        self.caller_address = caller;
        self.call_value = value;
        self.pc = 0;
        self.execution_reverted = false;

        var ok = true;
        self.execute() catch {
            ok = false;
        };
        if (self.execution_reverted) ok = false;

        // On failure, undo this frame's state changes and refund accrual.
        if (!ok) {
            self.revertTo(journal_marker);
            self.gas_refund = refund_marker;
        }

        // Return the reserved gas plus whatever the sub-call left unspent.
        self.gas = reserved + self.gas;

        // Tear down the sub-frame and restore the parent.
        self.stack.deinit(self.allocator);
        self.memory.deinit(self.allocator);
        self.stack = saved_stack;
        self.memory = saved_memory;
        self.pc = saved_pc;
        self.code = saved_code;
        self.current_address = saved_addr;
        self.caller_address = saved_caller;
        self.call_value = saved_value;
        self.calldata = saved_calldata;
        self.execution_reverted = saved_reverted;
        self.stop_execution = false;
        _ = self.call_stack.pop();
        return ok;
    }
};

// When used as an executable, we provide a main function
// When used as a library, this function won't be called
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Directly test our opcodes
    const bytecode = &[_]u8{ 0x60, 0x03, 0x60, 0x04, 0x01, 0x60, 0x02, 0x02, 0x00 }; // PUSH1 3, PUSH1 4, ADD, PUSH1 2, MUL, STOP
    evm.code = bytecode;
    evm.pc = 0;
    
    try evm.execute();

    std.debug.print("Execution completed successfully\n", .{});
    
    // Print the result of our computation
    if (evm.stack.pop()) |result| {
        std.debug.print("Result: {d}\n", .{result.data[0]});
    } else {
        std.debug.print("Stack is empty\n", .{});
    }
}
