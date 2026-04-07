// File: src/execution_tracer.zig
// Step-by-step EVM execution tracing for the web demo
// Wraps the EVM execute loop to capture state at each opcode

const std = @import("std");
const Allocator = std.mem.Allocator;
const main = @import("main.zig");
const EVM = main.EVM;
const BigInt = main.BigInt;
const Opcode = main.Opcode;

// ============================================================
// Trace Data Types
// ============================================================

pub const ExecutionStep = struct {
    step: u32,
    pc: usize,
    opcode: u8,
    opcode_name: []const u8,
    operand: ?[]const u8, // hex string for PUSH operands
    gas_cost: u64,
    gas_remaining: u64,
    gas_used_total: u64,
    stack: [][]const u8, // hex strings of each stack item (bottom to top)
    stack_depth: usize,
    memory_size: usize,
    error_msg: ?[]const u8,
};

pub const ExecutionTrace = struct {
    steps: []ExecutionStep,
    success: bool,
    error_msg: ?[]const u8,
    return_data: []const u8, // hex string
    total_gas_used: u64,
    gas_limit: u64,
    final_stack: [][]const u8, // hex strings
    storage_state: []StorageEntry,
    logs: []LogEntry,
};

pub const StorageEntry = struct {
    key: []const u8, // hex
    value: []const u8, // hex
};

pub const LogEntry = struct {
    address: []const u8, // hex
    topics: [][]const u8, // hex strings
    data: []const u8, // hex
};

pub const DisassembledOp = struct {
    pc: usize,
    opcode: u8,
    opcode_name: []const u8,
    operand: ?[]const u8, // hex string
    gas_cost: u64,
};

// ============================================================
// Hex Encoding Helpers
// ============================================================

const hex_chars = "0123456789abcdef";

fn bytesToHex(allocator: Allocator, bytes: []const u8) ![]const u8 {
    if (bytes.len == 0) return try allocator.dupe(u8, "0x");
    var result = try allocator.alloc(u8, 2 + bytes.len * 2);
    result[0] = '0';
    result[1] = 'x';
    for (bytes, 0..) |b, i| {
        result[2 + i * 2] = hex_chars[b >> 4];
        result[2 + i * 2 + 1] = hex_chars[b & 0x0f];
    }
    return result;
}

fn bigintToHex(allocator: Allocator, value: BigInt) ![]const u8 {
    const bytes = value.toBytes();
    // Find first non-zero byte for compact representation
    var start: usize = 0;
    while (start < 31 and bytes[start] == 0) : (start += 1) {}
    return bytesToHex(allocator, bytes[start..]);
}

fn snapshotStack(allocator: Allocator, evm: *EVM) ![][]const u8 {
    const depth = evm.stack.items.items.len;
    if (depth == 0) return try allocator.alloc([]const u8, 0);

    var result = try allocator.alloc([]const u8, depth);
    for (0..depth) |i| {
        result[i] = try bigintToHex(allocator, evm.stack.items.items[i]);
    }
    return result;
}

// ============================================================
// Opcode Name Lookup
// ============================================================

pub fn opcodeName(code: u8) []const u8 {
    return switch (code) {
        0x00 => "STOP",
        0x01 => "ADD",
        0x02 => "MUL",
        0x03 => "SUB",
        0x04 => "DIV",
        0x05 => "SDIV",
        0x06 => "MOD",
        0x07 => "SMOD",
        0x08 => "ADDMOD",
        0x09 => "MULMOD",
        0x0a => "EXP",
        0x0b => "SIGNEXTEND",
        0x10 => "LT",
        0x11 => "GT",
        0x12 => "SLT",
        0x13 => "SGT",
        0x14 => "EQ",
        0x15 => "ISZERO",
        0x16 => "AND",
        0x17 => "OR",
        0x18 => "XOR",
        0x19 => "NOT",
        0x1a => "BYTE",
        0x1b => "SHL",
        0x1c => "SHR",
        0x1d => "SAR",
        0x20 => "SHA3",
        0x30 => "ADDRESS",
        0x31 => "BALANCE",
        0x32 => "ORIGIN",
        0x33 => "CALLER",
        0x34 => "CALLVALUE",
        0x35 => "CALLDATALOAD",
        0x36 => "CALLDATASIZE",
        0x37 => "CALLDATACOPY",
        0x38 => "CODESIZE",
        0x39 => "CODECOPY",
        0x3a => "GASPRICE",
        0x3b => "EXTCODESIZE",
        0x3c => "EXTCODECOPY",
        0x3d => "RETURNDATASIZE",
        0x3e => "RETURNDATACOPY",
        0x3f => "EXTCODEHASH",
        0x40 => "BLOCKHASH",
        0x41 => "COINBASE",
        0x42 => "TIMESTAMP",
        0x43 => "NUMBER",
        0x44 => "DIFFICULTY",
        0x45 => "GASLIMIT",
        0x46 => "CHAINID",
        0x47 => "SELFBALANCE",
        0x48 => "BASEFEE",
        0x50 => "POP",
        0x51 => "MLOAD",
        0x52 => "MSTORE",
        0x53 => "MSTORE8",
        0x54 => "SLOAD",
        0x55 => "SSTORE",
        0x56 => "JUMP",
        0x57 => "JUMPI",
        0x58 => "PC",
        0x59 => "MSIZE",
        0x5a => "GAS",
        0x5b => "JUMPDEST",
        0x60 => "PUSH1",
        0x61 => "PUSH2",
        0x62 => "PUSH3",
        0x63 => "PUSH4",
        0x64 => "PUSH5",
        0x65 => "PUSH6",
        0x66 => "PUSH7",
        0x67 => "PUSH8",
        0x68 => "PUSH9",
        0x69 => "PUSH10",
        0x6a => "PUSH11",
        0x6b => "PUSH12",
        0x6c => "PUSH13",
        0x6d => "PUSH14",
        0x6e => "PUSH15",
        0x6f => "PUSH16",
        0x70 => "PUSH17",
        0x71 => "PUSH18",
        0x72 => "PUSH19",
        0x73 => "PUSH20",
        0x74 => "PUSH21",
        0x75 => "PUSH22",
        0x76 => "PUSH23",
        0x77 => "PUSH24",
        0x78 => "PUSH25",
        0x79 => "PUSH26",
        0x7a => "PUSH27",
        0x7b => "PUSH28",
        0x7c => "PUSH29",
        0x7d => "PUSH30",
        0x7e => "PUSH31",
        0x7f => "PUSH32",
        0x80 => "DUP1",
        0x81 => "DUP2",
        0x82 => "DUP3",
        0x83 => "DUP4",
        0x84 => "DUP5",
        0x85 => "DUP6",
        0x86 => "DUP7",
        0x87 => "DUP8",
        0x88 => "DUP9",
        0x89 => "DUP10",
        0x8a => "DUP11",
        0x8b => "DUP12",
        0x8c => "DUP13",
        0x8d => "DUP14",
        0x8e => "DUP15",
        0x8f => "DUP16",
        0x90 => "SWAP1",
        0x91 => "SWAP2",
        0x92 => "SWAP3",
        0x93 => "SWAP4",
        0x94 => "SWAP5",
        0x95 => "SWAP6",
        0x96 => "SWAP7",
        0x97 => "SWAP8",
        0x98 => "SWAP9",
        0x99 => "SWAP10",
        0x9a => "SWAP11",
        0x9b => "SWAP12",
        0x9c => "SWAP13",
        0x9d => "SWAP14",
        0x9e => "SWAP15",
        0x9f => "SWAP16",
        0xa0 => "LOG0",
        0xa1 => "LOG1",
        0xa2 => "LOG2",
        0xa3 => "LOG3",
        0xa4 => "LOG4",
        0xf0 => "CREATE",
        0xf1 => "CALL",
        0xf2 => "CALLCODE",
        0xf3 => "RETURN",
        0xf4 => "DELEGATECALL",
        0xf5 => "CREATE2",
        0xfa => "STATICCALL",
        0xfd => "REVERT",
        0xfe => "INVALID",
        0xff => "SELFDESTRUCT",
        else => "UNKNOWN",
    };
}

/// Get the number of bytes a PUSH opcode reads
fn pushSize(code: u8) ?u8 {
    if (code >= 0x60 and code <= 0x7f) {
        return code - 0x60 + 1;
    }
    return null;
}

// ============================================================
// Execution Tracer
// ============================================================

pub fn executeWithTrace(allocator: Allocator, bytecode: []const u8, gas_limit: u64, calldata: []const u8) !ExecutionTrace {
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    evm.code = bytecode;
    evm.pc = 0;
    evm.setGasLimit(gas_limit);
    if (calldata.len > 0) {
        evm.calldata = calldata;
    }

    var steps: std.ArrayList(ExecutionStep) = .empty;
    var step_num: u32 = 0;
    const max_steps: u32 = 10000; // Safety limit

    evm.stop_execution = false;
    evm.execution_reverted = false;

    var exec_error: ?[]const u8 = null;

    while (evm.pc < evm.code.len and !evm.stop_execution and step_num < max_steps) {
        const pc_before = evm.pc;
        const opcode_byte = evm.code[evm.pc];
        const op_name = opcodeName(opcode_byte);
        const gas_cost = EVM.getGasCost(@enumFromInt(opcode_byte));

        // Snapshot stack before execution
        const stack_snapshot = try snapshotStack(allocator, evm);

        // Extract PUSH operand if applicable
        var operand: ?[]const u8 = null;
        if (pushSize(opcode_byte)) |psize| {
            const start = evm.pc + 1;
            const end = @min(start + psize, evm.code.len);
            if (start < evm.code.len) {
                operand = try bytesToHex(allocator, evm.code[start..end]);
            }
        }

        // Try to consume gas and execute
        const gas_before = evm.gas;
        evm.consumeGas(gas_cost) catch {
            try steps.append(allocator, ExecutionStep{
                .step = step_num,
                .pc = pc_before,
                .opcode = opcode_byte,
                .opcode_name = op_name,
                .operand = operand,
                .gas_cost = gas_cost,
                .gas_remaining = evm.gas,
                .gas_used_total = evm.gas_used,
                .stack = stack_snapshot,
                .stack_depth = evm.stack.items.items.len,
                .memory_size = evm.memory.data.items.len,
                .error_msg = try allocator.dupe(u8, "Out of gas"),
            });
            exec_error = try allocator.dupe(u8, "Out of gas");
            break;
        };

        evm.pc += 1;

        const impl = evm.opcodes.get(@enumFromInt(opcode_byte));
        if (impl == null) {
            try steps.append(allocator, ExecutionStep{
                .step = step_num,
                .pc = pc_before,
                .opcode = opcode_byte,
                .opcode_name = op_name,
                .operand = operand,
                .gas_cost = gas_cost,
                .gas_remaining = evm.gas,
                .gas_used_total = evm.gas_used,
                .stack = stack_snapshot,
                .stack_depth = evm.stack.items.items.len,
                .memory_size = evm.memory.data.items.len,
                .error_msg = try allocator.dupe(u8, "Unknown opcode"),
            });
            exec_error = try allocator.dupe(u8, "Unknown opcode");
            break;
        }

        impl.?.execute(evm) catch |err| {
            try steps.append(allocator, ExecutionStep{
                .step = step_num,
                .pc = pc_before,
                .opcode = opcode_byte,
                .opcode_name = op_name,
                .operand = operand,
                .gas_cost = gas_cost,
                .gas_remaining = evm.gas,
                .gas_used_total = evm.gas_used,
                .stack = stack_snapshot,
                .stack_depth = evm.stack.items.items.len,
                .memory_size = evm.memory.data.items.len,
                .error_msg = try allocator.dupe(u8, @errorName(err)),
            });
            exec_error = try allocator.dupe(u8, @errorName(err));
            break;
        };

        _ = gas_before;

        try steps.append(allocator, ExecutionStep{
            .step = step_num,
            .pc = pc_before,
            .opcode = opcode_byte,
            .opcode_name = op_name,
            .operand = operand,
            .gas_cost = gas_cost,
            .gas_remaining = evm.gas,
            .gas_used_total = evm.gas_used,
            .stack = try snapshotStack(allocator, evm),
            .stack_depth = evm.stack.items.items.len,
            .memory_size = evm.memory.data.items.len,
            .error_msg = null,
        });

        step_num += 1;

        if (@as(Opcode, @enumFromInt(opcode_byte)) == .STOP) break;
    }

    // Build final stack
    const final_stack = try snapshotStack(allocator, evm);

    // Build return data
    const return_data_hex = if (evm.return_data.len > 0)
        try bytesToHex(allocator, evm.return_data)
    else
        try allocator.dupe(u8, "0x");

    // Build storage state (from all accounts)
    var storage_entries: std.ArrayList(StorageEntry) = .empty;
    var account_iter = evm.accounts.iterator();
    while (account_iter.next()) |entry| {
        var storage_iter = entry.value_ptr.storage.iterator();
        while (storage_iter.next()) |s_entry| {
            try storage_entries.append(allocator, StorageEntry{
                .key = try bigintToHex(allocator, s_entry.key_ptr.*),
                .value = try bigintToHex(allocator, s_entry.value_ptr.*),
            });
        }
    }

    // Build logs
    var log_entries: std.ArrayList(LogEntry) = .empty;
    for (evm.logs.items) |log| {
        var topics = try allocator.alloc([]const u8, log.topics.items.len);
        for (log.topics.items, 0..) |topic, i| {
            topics[i] = try bytesToHex(allocator, &topic);
        }
        try log_entries.append(allocator, LogEntry{
            .address = try bytesToHex(allocator, &log.address),
            .topics = topics,
            .data = if (log.data.len > 0) try bytesToHex(allocator, log.data) else try allocator.dupe(u8, "0x"),
        });
    }

    return ExecutionTrace{
        .steps = try steps.toOwnedSlice(allocator),
        .success = exec_error == null and !evm.execution_reverted,
        .error_msg = exec_error,
        .return_data = return_data_hex,
        .total_gas_used = evm.gas_used,
        .gas_limit = gas_limit,
        .final_stack = final_stack,
        .storage_state = try storage_entries.toOwnedSlice(allocator),
        .logs = try log_entries.toOwnedSlice(allocator),
    };
}

// ============================================================
// Disassembler
// ============================================================

pub fn disassemble(allocator: Allocator, bytecode: []const u8) ![]DisassembledOp {
    var ops: std.ArrayList(DisassembledOp) = .empty;
    var pc: usize = 0;

    while (pc < bytecode.len) {
        const opcode_byte = bytecode[pc];
        const op_name = opcodeName(opcode_byte);
        const gas_cost = EVM.getGasCost(@enumFromInt(opcode_byte));

        var operand: ?[]const u8 = null;
        var advance: usize = 1;

        if (pushSize(opcode_byte)) |psize| {
            const start = pc + 1;
            const end = @min(start + psize, bytecode.len);
            if (start < bytecode.len) {
                operand = try bytesToHex(allocator, bytecode[start..end]);
            }
            advance = 1 + @as(usize, psize);
        }

        try ops.append(allocator, DisassembledOp{
            .pc = pc,
            .opcode = opcode_byte,
            .opcode_name = op_name,
            .operand = operand,
            .gas_cost = gas_cost,
        });

        pc += advance;
    }

    return try ops.toOwnedSlice(allocator);
}

// ============================================================
// Opcode Info (for reference table)
// ============================================================

pub const OpcodeInfo = struct {
    code: u8,
    name: []const u8,
    gas: u64,
    stack_in: u8,
    stack_out: u8,
    description: []const u8,
    category: []const u8,
};

pub fn getAllOpcodeInfo(allocator: Allocator) ![]OpcodeInfo {
    var infos: std.ArrayList(OpcodeInfo) = .empty;

    const opcodes = [_]struct { code: u8, name: []const u8, gas: u64, sin: u8, sout: u8, desc: []const u8, cat: []const u8 }{
        .{ .code = 0x00, .name = "STOP", .gas = 0, .sin = 0, .sout = 0, .desc = "Halts execution", .cat = "control" },
        .{ .code = 0x01, .name = "ADD", .gas = 3, .sin = 2, .sout = 1, .desc = "Addition", .cat = "arithmetic" },
        .{ .code = 0x02, .name = "MUL", .gas = 3, .sin = 2, .sout = 1, .desc = "Multiplication", .cat = "arithmetic" },
        .{ .code = 0x03, .name = "SUB", .gas = 3, .sin = 2, .sout = 1, .desc = "Subtraction", .cat = "arithmetic" },
        .{ .code = 0x04, .name = "DIV", .gas = 3, .sin = 2, .sout = 1, .desc = "Integer division", .cat = "arithmetic" },
        .{ .code = 0x05, .name = "SDIV", .gas = 3, .sin = 2, .sout = 1, .desc = "Signed integer division", .cat = "arithmetic" },
        .{ .code = 0x06, .name = "MOD", .gas = 3, .sin = 2, .sout = 1, .desc = "Modulo remainder", .cat = "arithmetic" },
        .{ .code = 0x07, .name = "SMOD", .gas = 3, .sin = 2, .sout = 1, .desc = "Signed modulo remainder", .cat = "arithmetic" },
        .{ .code = 0x08, .name = "ADDMOD", .gas = 3, .sin = 3, .sout = 1, .desc = "Modular addition", .cat = "arithmetic" },
        .{ .code = 0x09, .name = "MULMOD", .gas = 3, .sin = 3, .sout = 1, .desc = "Modular multiplication", .cat = "arithmetic" },
        .{ .code = 0x0a, .name = "EXP", .gas = 10, .sin = 2, .sout = 1, .desc = "Exponentiation", .cat = "arithmetic" },
        .{ .code = 0x0b, .name = "SIGNEXTEND", .gas = 5, .sin = 2, .sout = 1, .desc = "Sign extend", .cat = "arithmetic" },
        .{ .code = 0x10, .name = "LT", .gas = 3, .sin = 2, .sout = 1, .desc = "Less than comparison", .cat = "comparison" },
        .{ .code = 0x11, .name = "GT", .gas = 3, .sin = 2, .sout = 1, .desc = "Greater than comparison", .cat = "comparison" },
        .{ .code = 0x12, .name = "SLT", .gas = 3, .sin = 2, .sout = 1, .desc = "Signed less than", .cat = "comparison" },
        .{ .code = 0x13, .name = "SGT", .gas = 3, .sin = 2, .sout = 1, .desc = "Signed greater than", .cat = "comparison" },
        .{ .code = 0x14, .name = "EQ", .gas = 3, .sin = 2, .sout = 1, .desc = "Equality check", .cat = "comparison" },
        .{ .code = 0x15, .name = "ISZERO", .gas = 3, .sin = 1, .sout = 1, .desc = "Is zero check", .cat = "comparison" },
        .{ .code = 0x16, .name = "AND", .gas = 3, .sin = 2, .sout = 1, .desc = "Bitwise AND", .cat = "bitwise" },
        .{ .code = 0x17, .name = "OR", .gas = 3, .sin = 2, .sout = 1, .desc = "Bitwise OR", .cat = "bitwise" },
        .{ .code = 0x18, .name = "XOR", .gas = 3, .sin = 2, .sout = 1, .desc = "Bitwise XOR", .cat = "bitwise" },
        .{ .code = 0x19, .name = "NOT", .gas = 3, .sin = 1, .sout = 1, .desc = "Bitwise NOT", .cat = "bitwise" },
        .{ .code = 0x1a, .name = "BYTE", .gas = 3, .sin = 2, .sout = 1, .desc = "Retrieve single byte", .cat = "bitwise" },
        .{ .code = 0x1b, .name = "SHL", .gas = 3, .sin = 2, .sout = 1, .desc = "Shift left", .cat = "bitwise" },
        .{ .code = 0x1c, .name = "SHR", .gas = 3, .sin = 2, .sout = 1, .desc = "Logical shift right", .cat = "bitwise" },
        .{ .code = 0x1d, .name = "SAR", .gas = 3, .sin = 2, .sout = 1, .desc = "Arithmetic shift right", .cat = "bitwise" },
        .{ .code = 0x20, .name = "SHA3", .gas = 30, .sin = 2, .sout = 1, .desc = "Keccak-256 hash", .cat = "crypto" },
        .{ .code = 0x30, .name = "ADDRESS", .gas = 2, .sin = 0, .sout = 1, .desc = "Current contract address", .cat = "environment" },
        .{ .code = 0x31, .name = "BALANCE", .gas = 100, .sin = 1, .sout = 1, .desc = "Account balance", .cat = "environment" },
        .{ .code = 0x32, .name = "ORIGIN", .gas = 2, .sin = 0, .sout = 1, .desc = "Transaction origin", .cat = "environment" },
        .{ .code = 0x33, .name = "CALLER", .gas = 2, .sin = 0, .sout = 1, .desc = "Message caller", .cat = "environment" },
        .{ .code = 0x34, .name = "CALLVALUE", .gas = 2, .sin = 0, .sout = 1, .desc = "Message value (wei)", .cat = "environment" },
        .{ .code = 0x35, .name = "CALLDATALOAD", .gas = 3, .sin = 1, .sout = 1, .desc = "Load calldata word", .cat = "environment" },
        .{ .code = 0x36, .name = "CALLDATASIZE", .gas = 2, .sin = 0, .sout = 1, .desc = "Calldata size", .cat = "environment" },
        .{ .code = 0x37, .name = "CALLDATACOPY", .gas = 3, .sin = 3, .sout = 0, .desc = "Copy calldata to memory", .cat = "environment" },
        .{ .code = 0x38, .name = "CODESIZE", .gas = 2, .sin = 0, .sout = 1, .desc = "Code size", .cat = "environment" },
        .{ .code = 0x39, .name = "CODECOPY", .gas = 3, .sin = 3, .sout = 0, .desc = "Copy code to memory", .cat = "environment" },
        .{ .code = 0x3a, .name = "GASPRICE", .gas = 2, .sin = 0, .sout = 1, .desc = "Transaction gas price", .cat = "environment" },
        .{ .code = 0x3b, .name = "EXTCODESIZE", .gas = 100, .sin = 1, .sout = 1, .desc = "External code size", .cat = "environment" },
        .{ .code = 0x3c, .name = "EXTCODECOPY", .gas = 100, .sin = 4, .sout = 0, .desc = "Copy external code", .cat = "environment" },
        .{ .code = 0x3d, .name = "RETURNDATASIZE", .gas = 2, .sin = 0, .sout = 1, .desc = "Return data size", .cat = "environment" },
        .{ .code = 0x3e, .name = "RETURNDATACOPY", .gas = 3, .sin = 3, .sout = 0, .desc = "Copy return data", .cat = "environment" },
        .{ .code = 0x3f, .name = "EXTCODEHASH", .gas = 100, .sin = 1, .sout = 1, .desc = "External code hash", .cat = "environment" },
        .{ .code = 0x40, .name = "BLOCKHASH", .gas = 20, .sin = 1, .sout = 1, .desc = "Block hash", .cat = "block" },
        .{ .code = 0x41, .name = "COINBASE", .gas = 2, .sin = 0, .sout = 1, .desc = "Block coinbase", .cat = "block" },
        .{ .code = 0x42, .name = "TIMESTAMP", .gas = 2, .sin = 0, .sout = 1, .desc = "Block timestamp", .cat = "block" },
        .{ .code = 0x43, .name = "NUMBER", .gas = 2, .sin = 0, .sout = 1, .desc = "Block number", .cat = "block" },
        .{ .code = 0x44, .name = "DIFFICULTY", .gas = 2, .sin = 0, .sout = 1, .desc = "Block difficulty", .cat = "block" },
        .{ .code = 0x45, .name = "GASLIMIT", .gas = 2, .sin = 0, .sout = 1, .desc = "Block gas limit", .cat = "block" },
        .{ .code = 0x46, .name = "CHAINID", .gas = 2, .sin = 0, .sout = 1, .desc = "Chain ID", .cat = "block" },
        .{ .code = 0x47, .name = "SELFBALANCE", .gas = 5, .sin = 0, .sout = 1, .desc = "Contract balance", .cat = "block" },
        .{ .code = 0x48, .name = "BASEFEE", .gas = 2, .sin = 0, .sout = 1, .desc = "Base fee", .cat = "block" },
        .{ .code = 0x50, .name = "POP", .gas = 2, .sin = 1, .sout = 0, .desc = "Remove top stack item", .cat = "stack" },
        .{ .code = 0x51, .name = "MLOAD", .gas = 3, .sin = 1, .sout = 1, .desc = "Load word from memory", .cat = "memory" },
        .{ .code = 0x52, .name = "MSTORE", .gas = 3, .sin = 2, .sout = 0, .desc = "Store word to memory", .cat = "memory" },
        .{ .code = 0x53, .name = "MSTORE8", .gas = 3, .sin = 2, .sout = 0, .desc = "Store byte to memory", .cat = "memory" },
        .{ .code = 0x54, .name = "SLOAD", .gas = 200, .sin = 1, .sout = 1, .desc = "Load from storage", .cat = "storage" },
        .{ .code = 0x55, .name = "SSTORE", .gas = 5000, .sin = 2, .sout = 0, .desc = "Store to storage", .cat = "storage" },
        .{ .code = 0x56, .name = "JUMP", .gas = 8, .sin = 1, .sout = 0, .desc = "Jump to destination", .cat = "control" },
        .{ .code = 0x57, .name = "JUMPI", .gas = 10, .sin = 2, .sout = 0, .desc = "Conditional jump", .cat = "control" },
        .{ .code = 0x58, .name = "PC", .gas = 2, .sin = 0, .sout = 1, .desc = "Program counter", .cat = "control" },
        .{ .code = 0x59, .name = "MSIZE", .gas = 2, .sin = 0, .sout = 1, .desc = "Memory size", .cat = "memory" },
        .{ .code = 0x5a, .name = "GAS", .gas = 2, .sin = 0, .sout = 1, .desc = "Remaining gas", .cat = "control" },
        .{ .code = 0x5b, .name = "JUMPDEST", .gas = 1, .sin = 0, .sout = 0, .desc = "Jump destination marker", .cat = "control" },
        .{ .code = 0x60, .name = "PUSH1", .gas = 3, .sin = 0, .sout = 1, .desc = "Push 1 byte", .cat = "stack" },
        .{ .code = 0x61, .name = "PUSH2", .gas = 3, .sin = 0, .sout = 1, .desc = "Push 2 bytes", .cat = "stack" },
        .{ .code = 0x62, .name = "PUSH3", .gas = 3, .sin = 0, .sout = 1, .desc = "Push 3 bytes", .cat = "stack" },
        .{ .code = 0x63, .name = "PUSH4", .gas = 3, .sin = 0, .sout = 1, .desc = "Push 4 bytes", .cat = "stack" },
        .{ .code = 0x7f, .name = "PUSH32", .gas = 3, .sin = 0, .sout = 1, .desc = "Push 32 bytes", .cat = "stack" },
        .{ .code = 0x80, .name = "DUP1", .gas = 3, .sin = 1, .sout = 2, .desc = "Duplicate 1st stack item", .cat = "stack" },
        .{ .code = 0x81, .name = "DUP2", .gas = 3, .sin = 2, .sout = 3, .desc = "Duplicate 2nd stack item", .cat = "stack" },
        .{ .code = 0x90, .name = "SWAP1", .gas = 3, .sin = 2, .sout = 2, .desc = "Swap 1st and 2nd", .cat = "stack" },
        .{ .code = 0x91, .name = "SWAP2", .gas = 3, .sin = 3, .sout = 3, .desc = "Swap 1st and 3rd", .cat = "stack" },
        .{ .code = 0xa0, .name = "LOG0", .gas = 375, .sin = 2, .sout = 0, .desc = "Log with 0 topics", .cat = "logging" },
        .{ .code = 0xa1, .name = "LOG1", .gas = 750, .sin = 3, .sout = 0, .desc = "Log with 1 topic", .cat = "logging" },
        .{ .code = 0xa2, .name = "LOG2", .gas = 1125, .sin = 4, .sout = 0, .desc = "Log with 2 topics", .cat = "logging" },
        .{ .code = 0xa3, .name = "LOG3", .gas = 1500, .sin = 5, .sout = 0, .desc = "Log with 3 topics", .cat = "logging" },
        .{ .code = 0xa4, .name = "LOG4", .gas = 1875, .sin = 6, .sout = 0, .desc = "Log with 4 topics", .cat = "logging" },
        .{ .code = 0xf0, .name = "CREATE", .gas = 32000, .sin = 3, .sout = 1, .desc = "Create contract", .cat = "system" },
        .{ .code = 0xf1, .name = "CALL", .gas = 100, .sin = 7, .sout = 1, .desc = "Call contract", .cat = "system" },
        .{ .code = 0xf2, .name = "CALLCODE", .gas = 100, .sin = 7, .sout = 1, .desc = "Call with caller's storage", .cat = "system" },
        .{ .code = 0xf3, .name = "RETURN", .gas = 0, .sin = 2, .sout = 0, .desc = "Return from execution", .cat = "control" },
        .{ .code = 0xf4, .name = "DELEGATECALL", .gas = 100, .sin = 6, .sout = 1, .desc = "Delegate call", .cat = "system" },
        .{ .code = 0xf5, .name = "CREATE2", .gas = 32000, .sin = 4, .sout = 1, .desc = "Create contract with salt", .cat = "system" },
        .{ .code = 0xfa, .name = "STATICCALL", .gas = 100, .sin = 6, .sout = 1, .desc = "Static call (read-only)", .cat = "system" },
        .{ .code = 0xfd, .name = "REVERT", .gas = 0, .sin = 2, .sout = 0, .desc = "Revert execution", .cat = "control" },
        .{ .code = 0xfe, .name = "INVALID", .gas = 0, .sin = 0, .sout = 0, .desc = "Invalid opcode", .cat = "control" },
        .{ .code = 0xff, .name = "SELFDESTRUCT", .gas = 5000, .sin = 1, .sout = 0, .desc = "Destroy contract", .cat = "system" },
    };

    for (opcodes) |op| {
        try infos.append(allocator, OpcodeInfo{
            .code = op.code,
            .name = op.name,
            .gas = op.gas,
            .stack_in = op.sin,
            .stack_out = op.sout,
            .description = op.desc,
            .category = op.cat,
        });
    }

    return try infos.toOwnedSlice(allocator);
}
