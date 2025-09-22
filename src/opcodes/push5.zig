// File: src/opcodes/push5.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.PUSH5),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.pc + 5 > evm.code.len) {
        return error.InvalidOpcode;
    }

    var value = BigInt.init(0);

    // Read 5 bytes and store them in the BigInt (big-endian)
    for (0..5) |i| {
        const byte_val = evm.code[evm.pc + i];
        const word_idx = i / 8;
        const shift_amount = @as(u6, @intCast((4 - i) * 8)); // Start from highest bits for first byte
        value.data[word_idx] |= (@as(u64, byte_val) << shift_amount);
    }

    evm.pc += 5;
    try evm.stack.push(evm.allocator, value);
}