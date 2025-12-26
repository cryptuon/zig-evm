// File: src/opcodes/extcodecopy.zig
// EXTCODECOPY (0x3c): Copy an account's code to memory
// Stack: address, destOffset, offset, size -> (none)
// Copies 'size' bytes of code from account at 'address' to memory

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.EXTCODECOPY),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const addr_big = evm.stack.pop() orelse return error.StackUnderflow;
    const dest_offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const code_offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const size_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Convert address
    const addr_bytes = addr_big.toBytes();
    var address: [20]u8 = undefined;
    @memcpy(&address, addr_bytes[12..32]);

    // Convert sizes
    if (!size_big.fitsInU64()) return;
    const size: usize = @intCast(size_big.data[0]);
    if (size == 0) return;

    if (!dest_offset_big.fitsInU64()) return error.OutOfGas;
    const dest_offset: usize = @intCast(dest_offset_big.data[0]);

    // Get external code
    const ext_code: []const u8 = if (evm.accounts.get(address)) |account|
        account.code
    else
        &[_]u8{};

    const code_offset: usize = if (code_offset_big.fitsInU64())
        @intCast(@min(code_offset_big.data[0], ext_code.len))
    else
        ext_code.len;

    // Expand memory if needed
    try evm.memory.ensureCapacity(evm.allocator, dest_offset + size);

    // Copy from external code to memory, with zero padding
    for (0..size) |i| {
        const src_idx = code_offset + i;
        const byte: u8 = if (src_idx < ext_code.len) ext_code[src_idx] else 0;
        try evm.memory.storeByte(evm.allocator, dest_offset + i, byte);
    }
}
