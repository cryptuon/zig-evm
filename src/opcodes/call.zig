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

    // Calculate gas cost
    var extra_gas: u64 = CALL_BASE_GAS;

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

    // Get caller account
    const caller_ptr = evm.accounts.getPtr(evm.current_address);
    if (caller_ptr == null) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }
    var caller = caller_ptr.?;

    // Check balance
    if (caller.balance.lt(value_big)) {
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

    // Transfer value
    caller.balance = caller.balance.sub(value_big);

    // Get or create target account
    if (!target_exists) {
        const new_account = Account{
            .balance = value_big,
            .nonce = 0,
            .code = &[_]u8{},
            .storage = std.AutoHashMap(BigInt, BigInt).init(evm.allocator),
        };
        try evm.accounts.put(target_addr, new_account);
    } else {
        const target_ptr = evm.accounts.getPtr(target_addr).?;
        target_ptr.balance = target_ptr.balance.add(value_big);
    }

    // Get target's code
    const target_account = evm.accounts.get(target_addr);
    const target_code = if (target_account) |acc| acc.code else &[_]u8{};

    // If no code, call succeeds with no execution
    if (target_code.len == 0) {
        // Ensure return memory is available
        try evm.memory.ensureCapacity(evm.allocator, ret_offset + ret_size);
        // Clear return data
        if (evm.return_data.len > 0) {
            evm.allocator.free(evm.return_data);
        }
        evm.return_data = &[_]u8{};
        try evm.stack.push(evm.allocator, BigInt.init(1)); // Success
        return;
    }

    // Calculate gas to pass (all but 1/64th)
    const gas_requested: u64 = if (gas_big.fitsInU64()) gas_big.data[0] else std.math.maxInt(u64);
    const gas_available = evm.gas - (evm.gas / 64);
    var call_gas = @min(gas_requested, gas_available);

    // Add stipend if value transfer
    if (!value_big.isZero()) {
        call_gas += CALL_STIPEND;
    }

    // For a full implementation, we would execute the target code here
    // with a new call frame. For now, we simulate success.

    // Ensure return memory is available
    try evm.memory.ensureCapacity(evm.allocator, ret_offset + ret_size);

    // In a full implementation, return data would come from sub-execution
    if (evm.return_data.len > 0) {
        evm.allocator.free(evm.return_data);
    }
    evm.return_data = &[_]u8{};

    // Push success (1)
    try evm.stack.push(evm.allocator, BigInt.init(1));
}
