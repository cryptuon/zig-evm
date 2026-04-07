// File: src/opcodes/staticcall.zig
// STATICCALL (0xfa): Call with read-only context
// Stack: gas, addr, argsOffset, argsSize, retOffset, retSize -> success
// Like CALL but no state modifications allowed

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const CallFrame = @import("../main.zig").CallFrame;

// Gas costs
const CALL_BASE_GAS: u64 = 100;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.STATICCALL),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Pop stack arguments (no value parameter in STATICCALL)
    const gas_big = evm.stack.pop() orelse return error.StackUnderflow;
    const addr_big = evm.stack.pop() orelse return error.StackUnderflow;
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

    // Consume base gas
    try evm.consumeGas(CALL_BASE_GAS);

    // Check call depth
    if (evm.call_stack.depth() >= 1024) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }

    // Read calldata from memory
    try evm.memory.ensureCapacity(evm.allocator, args_offset + args_size);

    // Get target's code
    const target_code = if (evm.accounts.get(target_addr)) |acc| acc.code else &[_]u8{};

    // If no code, call succeeds with no execution
    if (target_code.len == 0) {
        try evm.memory.ensureCapacity(evm.allocator, ret_offset + ret_size);
        if (evm.return_data.len > 0) {
            evm.allocator.free(evm.return_data);
        }
        evm.return_data = &[_]u8{};
        try evm.stack.push(evm.allocator, BigInt.init(1));
        return;
    }

    // Calculate gas to pass
    const gas_requested: u64 = if (gas_big.fitsInU64()) gas_big.data[0] else std.math.maxInt(u64);
    const gas_available = evm.gas - (evm.gas / 64);
    const call_gas = @min(gas_requested, gas_available);
    _ = call_gas;

    // In a full implementation:
    // - Push a new call frame with is_static = true
    // - Execute target's code
    // - Any state-modifying operation would fail
    // - msg.sender = current contract
    // - msg.value = 0 (no value in STATICCALL)

    try evm.memory.ensureCapacity(evm.allocator, ret_offset + ret_size);
    if (evm.return_data.len > 0) {
        evm.allocator.free(evm.return_data);
    }
    evm.return_data = &[_]u8{};

    try evm.stack.push(evm.allocator, BigInt.init(1));
}
