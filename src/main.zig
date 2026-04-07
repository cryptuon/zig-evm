// File: src/main.zig

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub const BigInt = @import("bigint.zig").BigInt;
pub const Memory = @import("memory.zig").Memory;
pub const Stack = @import("stack.zig").Stack;
pub const CallStack = @import("call_frame.zig").CallStack;
pub const CallFrame = @import("call_frame.zig").CallFrame;

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
        };
        try evm.loadOpcodes();
        return evm;
    }

    pub fn setGasLimit(self: *EVM, gas_limit: u64) void {
        self.gas_limit = gas_limit;
        self.gas = gas_limit;
        self.gas_used = 0;
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
            .BALANCE => 100, // Account access cost
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

            // Storage operations (high cost)
            .SLOAD => 200,
            .SSTORE => 5000, // Base cost, varies based on storage state

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
        self.accounts.deinit();
        self.block_hashes.deinit();
        // Clean up logs
        for (self.logs.items) |*log| {
            log.deinit(self.allocator);
        }
        self.logs.deinit();
        self.call_stack.deinit();
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
