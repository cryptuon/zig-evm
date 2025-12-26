// File: src/opcodes/returndatacopy.zig
// RETURNDATACOPY (0x3e): Copy return data to memory
// Stack: destOffset, offset, size -> (none)
// Copies 'size' bytes from return data at 'offset' to memory at 'destOffset'

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.RETURNDATACOPY),
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
    if (!size_big.fitsInU64()) return error.OutOfGas;
    const size: usize = @intCast(size_big.data[0]);
    if (size == 0) return; // Nothing to copy

    if (!dest_offset_big.fitsInU64()) return error.OutOfGas;
    const dest_offset: usize = @intCast(dest_offset_big.data[0]);

    if (!data_offset_big.fitsInU64()) return error.OutOfGas;
    const data_offset: usize = @intCast(data_offset_big.data[0]);

    // Check bounds on return data
    if (data_offset + size > evm.return_data.len) {
        return error.ReturnDataOutOfBounds;
    }

    // Expand memory if needed
    try evm.memory.ensureCapacity(evm.allocator, dest_offset + size);

    // Copy from return data to memory
    for (0..size) |i| {
        try evm.memory.storeByte(evm.allocator, dest_offset + i, evm.return_data[data_offset + i]);
    }
}
