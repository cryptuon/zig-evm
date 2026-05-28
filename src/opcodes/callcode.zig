// File: src/opcodes/callcode.zig
// CALLCODE (0xf2): Call with another contract's code but own storage
// Stack: gas, addr, value, argsOffset, argsSize, retOffset, retSize -> success
// Like CALL but executes target's code in caller's context

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const StateKey = @import("../main.zig").StateKey;

// Gas costs
const CALL_BASE_GAS: u64 = 100;
const CALL_VALUE_TRANSFER_GAS: u64 = 9000;
const CALL_STIPEND: u64 = 2300;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CALLCODE),
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
    if (!value_big.isZero()) {
        extra_gas += CALL_VALUE_TRANSFER_GAS;
    }
    try evm.consumeGas(extra_gas);

    // Check call depth
    if (evm.call_stack.depth() >= 1024) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }

    // Sufficient balance for the (to-self) value is required.
    const self_bal = try evm.loadBalance(evm.current_address);
    if (self_bal.lt(value_big)) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }

    // Record the dependency on the target's code (EIP-2929 account access + read).
    _ = try evm.accessAccount(target_addr);
    try evm.noteRead(StateKey.codeOf(target_addr));

    const target_code = if (evm.accounts.get(target_addr)) |acc| acc.code else &[_]u8{};

    // If no code, call succeeds with no execution and empty return data.
    if (target_code.len == 0) {
        try evm.memory.ensureCapacity(evm.allocator, ret_offset + ret_size);
        if (evm.return_data.len > 0) evm.allocator.free(evm.return_data);
        evm.return_data = &[_]u8{};
        try evm.stack.push(evm.allocator, BigInt.init(1));
        return;
    }

    // Read calldata and run the target's code in the CURRENT contract's storage
    // context (CALLCODE): address and storage stay this contract's; value is to
    // self, so no balance moves between accounts.
    var calldata = try evm.allocator.alloc(u8, args_size);
    defer evm.allocator.free(calldata);
    for (0..args_size) |i| calldata[i] = evm.memory.loadByte(args_offset + i);

    const gas_requested: u64 = if (gas_big.fitsInU64()) gas_big.data[0] else std.math.maxInt(u64);
    var call_gas = @min(gas_requested, evm.gas - evm.gas / 64);
    if (!value_big.isZero()) call_gas += CALL_STIPEND;

    const ok = try evm.runSubContext(target_code, evm.current_address, evm.current_address, value_big, calldata, evm.call_stack.isStatic(), call_gas);

    try evm.memory.ensureCapacity(evm.allocator, ret_offset + ret_size);
    const ncopy = @min(ret_size, evm.return_data.len);
    for (0..ncopy) |i| try evm.memory.storeByte(evm.allocator, ret_offset + i, evm.return_data[i]);

    try evm.stack.push(evm.allocator, if (ok) BigInt.init(1) else BigInt.zero());
}
