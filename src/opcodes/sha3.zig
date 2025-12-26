// File: src/opcodes/sha3.zig
// SHA3/KECCAK256 (0x20): Compute Keccak-256 hash
// Stack: offset, size -> hash
// Computes the Keccak-256 hash of memory[offset:offset+size]
//
// Gas cost: 30 + 6 * ceil(size / 32)

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const crypto = @import("../crypto.zig");

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SHA3),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const size_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Convert to usize
    if (!size_big.fitsInU64()) {
        return error.OutOfGas;
    }
    const size: usize = @intCast(size_big.data[0]);

    if (!offset_big.fitsInU64()) {
        return error.OutOfGas;
    }
    const offset: usize = @intCast(offset_big.data[0]);

    // Calculate dynamic gas cost: 6 * ceil(size / 32)
    const word_count = (size + 31) / 32;
    const dynamic_gas: u64 = @as(u64, word_count) * 6;
    try evm.consumeGas(dynamic_gas);

    // Handle empty data case
    if (size == 0) {
        // keccak256("") is a known constant
        const empty_hash = crypto.keccak256("");
        const result = BigInt.fromBytes(empty_hash);
        try evm.stack.push(evm.allocator, result);
        return;
    }

    // Ensure memory is expanded
    try evm.memory.ensureCapacity(evm.allocator, offset + size);

    // Read data from memory
    var data = try evm.allocator.alloc(u8, size);
    defer evm.allocator.free(data);

    for (0..size) |i| {
        data[i] = evm.memory.loadByte(offset + i);
    }

    // Compute hash
    const hash = crypto.keccak256(data);
    const result = BigInt.fromBytes(hash);
    try evm.stack.push(evm.allocator, result);
}
