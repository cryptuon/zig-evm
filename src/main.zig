// File: src/main.zig

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub const BigInt = @import("bigint.zig").BigInt;
pub const Memory = @import("memory.zig").Memory;
pub const Stack = @import("stack.zig").Stack;

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
    // ... Add PUSH2 to PUSH32
    DUP1 = 0x80,
    // ... Add DUP2 to DUP16
    SWAP1 = 0x90,
    // ... Add SWAP2 to SWAP16
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
    execute: fn (*EVM) anyerror!void,
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

pub const EVM = struct {
    allocator: Allocator,
    stack: Stack,
    memory: Memory,
    pc: usize,
    gas: u64,
    code: []const u8,
    opcodes: std.AutoHashMap(Opcode, OpcodeImpl),
    accounts: std.AutoHashMap([20]u8, Account),
    current_transaction: ?Transaction,

    pub fn init(allocator: Allocator) !*EVM {
        var evm = try allocator.create(EVM);
        evm.* = EVM{
            .allocator = allocator,
            .stack = Stack.init(allocator),
            .memory = Memory.init(allocator),
            .pc = 0,
            .gas = 0,
            .code = &[_]u8{},
            .opcodes = std.AutoHashMap(Opcode, OpcodeImpl).init(allocator),
            .accounts = std.AutoHashMap([20]u8, Account).init(allocator),
            .current_transaction = null,
        };
        try evm.loadOpcodes();
        return evm;
    }

    pub fn deinit(self: *EVM) void {
        self.stack.deinit();
        self.memory.deinit();
        self.opcodes.deinit();
        self.accounts.deinit();
        self.allocator.destroy(self);
    }

    pub fn loadOpcodes(self: *EVM) !void {
        var dir = try fs.cwd().openDir("src/opcodes", .{});
        defer dir.close();

        var dir_iterator = dir.iterate();
        while (try dir_iterator.next()) |entry| {
            if (entry.kind != .File or !std.mem.endsWith(u8, entry.name, ".zig")) {
                continue;
            }

            const opcode_module = try std.zig.build.CreateModule.loadFromFile(self.allocator, entry.name);
            const opcode_impl = @import(opcode_module).getImpl();
            const opcode = @intToEnum(Opcode, opcode_impl.code);
            try self.opcodes.put(opcode, opcode_impl.impl);
        }
    }

    pub fn execute(self: *EVM) !void {
        while (self.pc < self.code.len) {
            const opcode = @intToEnum(Opcode, self.code[self.pc]);
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
            std.crypto.hash.Sha256.hash(&transaction.from, &new_address, .{});
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Example transaction
    const from_address: [20]u8 = [_]u8{1} ** 20;
    const to_address: [20]u8 = [_]u8{2} ** 20;
    const transaction = Transaction{
        .from = from_address,
        .to = to_address,
        .value = BigInt.init(100),
        .data = &[_]u8{ 0x60, 0x03, 0x60, 0x04, 0x01, 0x60, 0x02, 0x02, 0x00 }, // PUSH1 3, PUSH1 4, ADD, PUSH1 2, MUL, STOP
        .gas_limit = 21000,
        .gas_price = BigInt.init(1),
    };

    try evm.applyTransaction(transaction);

    std.debug.print("Transaction applied successfully\n", .{});
}
