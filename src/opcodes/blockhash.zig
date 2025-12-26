// File: src/opcodes/blockhash.zig
// BLOCKHASH (0x40): Get the hash of one of the 256 most recent blocks
// Stack: blockNumber -> hash
// Returns the hash of the given block number
// Returns 0 if the block number is not in the valid range
// (current - 256 to current - 1)

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.BLOCKHASH),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const block_num_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Get block number as u64
    if (!block_num_big.fitsInU64()) {
        // Block number too large, return 0
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }
    const block_num = block_num_big.data[0];

    // Check if block is in valid range (current - 256 to current - 1)
    const current = evm.block_number;
    if (block_num >= current or current - block_num > 256) {
        // Block number not in valid range
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }

    // Look up block hash
    if (evm.block_hashes.get(block_num)) |hash| {
        const result = BigInt.fromBytes(hash);
        try evm.stack.push(evm.allocator, result);
    } else {
        // Block hash not available
        try evm.stack.push(evm.allocator, BigInt.zero());
    }
}
