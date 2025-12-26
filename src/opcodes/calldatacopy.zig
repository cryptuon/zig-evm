// File: src/opcodes/calldatacopy.zig
// CALLDATACOPY (0x37): Copy calldata to memory
// Stack: destOffset, offset, size -> (none)
// Copies 'size' bytes from calldata at 'offset' to memory at 'destOffset'
// Pads with zeros if reading beyond calldata length

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CALLDATACOPY),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const dest_offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const data_offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const size_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Convert to usize with bounds checking
    if (!size_big.fitsInU64()) return; // Size too large, do nothing
    const size: usize = @intCast(size_big.data[0]);
    if (size == 0) return; // Nothing to copy

    if (!dest_offset_big.fitsInU64()) return error.OutOfGas; // Memory offset too large
    const dest_offset: usize = @intCast(dest_offset_big.data[0]);

    const data_offset: usize = if (data_offset_big.fitsInU64())
        @intCast(@min(data_offset_big.data[0], evm.calldata.len))
    else
        evm.calldata.len;

    // Calculate memory expansion gas cost
    const memory_cost = calculateMemoryCost(dest_offset + size);
    try evm.consumeGas(memory_cost);

    // Expand memory if needed and copy data
    try evm.memory.ensureCapacity(evm.allocator, dest_offset + size);

    // Copy from calldata, with zero padding for out-of-bounds reads
    for (0..size) |i| {
        const src_idx = data_offset + i;
        const byte: u8 = if (src_idx < evm.calldata.len)
            evm.calldata[src_idx]
        else
            0;
        try evm.memory.storeByte(evm.allocator, dest_offset + i, byte);
    }
}

fn calculateMemoryCost(size: usize) u64 {
    if (size == 0) return 0;
    const word_size = (size + 31) / 32;
    // Memory cost = 3 * word_size + word_size^2 / 512
    return @as(u64, 3 * word_size) + @as(u64, (word_size * word_size) / 512);
}
