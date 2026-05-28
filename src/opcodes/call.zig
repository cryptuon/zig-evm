// File: src/opcodes/call.zig
// CALL (0xf1): Call another contract
// Stack: gas, addr, value, argsOffset, argsSize, retOffset, retSize -> success
// Transfers value and executes code at address

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const Account = @import("../main.zig").Account;
const CallFrame = @import("../main.zig").CallFrame;
const StateKey = @import("../main.zig").StateKey;
const precompiles = @import("../precompiles.zig");

// Gas costs
const CALL_BASE_GAS: u64 = 100;
const CALL_VALUE_TRANSFER_GAS: u64 = 9000;
const CALL_NEW_ACCOUNT_GAS: u64 = 25000;
const CALL_STIPEND: u64 = 2300;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CALL),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Pop stack arguments
    const gas_big = evm.stack.pop() orelse return error.StackUnderflow;
    const addr_big = evm.stack.pop() orelse return error.StackUnderflow;
    const value_big = evm.stack.pop() orelse return error.StackUnderflow;
    const args_offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const args_size_big = evm.stack.pop() orelse return error.StackUnderflow;
    const ret_offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const ret_size_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Check if in static context and value is non-zero
    if (evm.call_stack.isStatic() and !value_big.isZero()) {
        return error.StaticCallViolation;
    }

    // Extract address (last 20 bytes)
    const addr_bytes = addr_big.toBytes();
    var target_addr: [20]u8 = undefined;
    @memcpy(&target_addr, addr_bytes[12..32]);

    // Convert sizes
    if (!args_offset_big.fitsInU64() or !args_size_big.fitsInU64() or
        !ret_offset_big.fitsInU64() or !ret_size_big.fitsInU64())
    {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }
    const args_offset: usize = @intCast(args_offset_big.data[0]);
    const args_size: usize = @intCast(args_size_big.data[0]);
    const ret_offset: usize = @intCast(ret_offset_big.data[0]);
    const ret_size: usize = @intCast(ret_size_big.data[0]);

    // EIP-2929 account access (2600 cold / 100 warm) + record the dependency on
    // the target's code, so the call edge appears in the conflict graph.
    const cold = try evm.accessAccount(target_addr);
    try evm.noteRead(StateKey.codeOf(target_addr));

    // Calculate gas cost
    var extra_gas: u64 = if (cold) EVM.COLD_ACCOUNT_ACCESS_COST else EVM.WARM_STORAGE_READ_COST;

    // Value transfer cost
    if (!value_big.isZero()) {
        extra_gas += CALL_VALUE_TRANSFER_GAS;
    }

    // New account creation cost
    const target_exists = evm.accounts.contains(target_addr);
    if (!value_big.isZero() and !target_exists) {
        extra_gas += CALL_NEW_ACCOUNT_GAS;
    }

    try evm.consumeGas(extra_gas);

    // Check call depth
    if (evm.call_stack.depth() >= 1024) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }

    // Read calldata from memory
    try evm.memory.ensureCapacity(evm.allocator, args_offset + args_size);
    var calldata = try evm.allocator.alloc(u8, args_size);
    defer evm.allocator.free(calldata);
    for (0..args_size) |i| {
        calldata[i] = evm.memory.loadByte(args_offset + i);
    }

    // Transfer value through the versioned balance helpers: the transfer enters
    // both transactions' read/write sets and is serializable under parallel
    // execution (caller and target balances are 256-bit, so they live in the
    // multi-version store when a view is attached).
    if (!value_big.isZero()) {
        const caller_bal = try evm.loadBalance(evm.current_address);
        if (caller_bal.lt(value_big)) {
            try evm.stack.push(evm.allocator, BigInt.zero());
            return;
        }
        try evm.storeBalance(evm.current_address, caller_bal.sub(value_big));
        const target_bal = try evm.loadBalance(target_addr);
        try evm.storeBalance(target_addr, target_bal.add(value_big));
    }

    // Precompiled contracts (0x01..0x09): run directly rather than executing
    // account code. (Value, if any, was transferred above.)
    if (precompiles.isPrecompile(target_addr)) {
        if (precompiles.run(evm.allocator, target_addr, calldata)) |res| {
            defer evm.allocator.free(res.output);
            try evm.consumeGas(res.gas);
            try evm.memory.ensureCapacity(evm.allocator, ret_offset + ret_size);
            const n = @min(ret_size, res.output.len);
            for (0..n) |i| try evm.memory.storeByte(evm.allocator, ret_offset + i, res.output[i]);
            if (evm.return_data.len > 0) evm.allocator.free(evm.return_data);
            evm.return_data = try evm.allocator.dupe(u8, res.output);
            try evm.stack.push(evm.allocator, BigInt.init(1));
            return;
        } else |_| {
            // Unsupported precompile: the call fails.
            try evm.stack.push(evm.allocator, BigInt.zero());
            return;
        }
    }

    // Target code/existence lives in the persistent accounts map.
    const target_account = evm.accounts.get(target_addr);
    const target_code = if (target_account) |acc| acc.code else &[_]u8{};

    // If no code, the call succeeds with no execution and empty return data.
    if (target_code.len == 0) {
        try evm.memory.ensureCapacity(evm.allocator, ret_offset + ret_size);
        if (evm.return_data.len > 0) evm.allocator.free(evm.return_data);
        evm.return_data = &[_]u8{};
        try evm.stack.push(evm.allocator, BigInt.init(1)); // Success
        return;
    }

    // Gas to forward: at most 63/64 of remaining (EIP-150), plus the 2300-gas
    // stipend on a value transfer.
    const gas_requested: u64 = if (gas_big.fitsInU64()) gas_big.data[0] else std.math.maxInt(u64);
    var call_gas = @min(gas_requested, evm.gas - evm.gas / 64);
    if (!value_big.isZero()) call_gas += CALL_STIPEND;

    // Execute the target's code in a nested frame: a CALL runs in the target's
    // own context (its address, its storage), with the parent as caller.
    const ok = try evm.runSubContext(target_code, target_addr, evm.current_address, value_big, calldata, evm.call_stack.isStatic(), call_gas);

    // Copy the sub-call's output into the parent's return memory window.
    try evm.memory.ensureCapacity(evm.allocator, ret_offset + ret_size);
    const ncopy = @min(ret_size, evm.return_data.len);
    for (0..ncopy) |i| try evm.memory.storeByte(evm.allocator, ret_offset + i, evm.return_data[i]);

    try evm.stack.push(evm.allocator, if (ok) BigInt.init(1) else BigInt.zero());
}
