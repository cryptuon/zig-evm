// File: src/opcodes/caller.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CALLER),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Push the caller address onto the stack
    var caller_value = BigInt.init(0);

    // Convert 20-byte address to BigInt (store in lower 20 bytes)
    for (0..20) |i| {
        const byte_val = evm.caller_address[i];
        const bit_pos = i * 8;
        const word_idx = bit_pos / 64;
        const bit_in_word = bit_pos % 64;

        if (word_idx < 4) {
            caller_value.data[word_idx] |= (@as(u64, byte_val) << @intCast(bit_in_word));
        }
    }

    try evm.stack.push(evm.allocator, caller_value);
}