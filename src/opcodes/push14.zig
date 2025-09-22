// File: src/opcodes/push14.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.PUSH14),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.pc + 14 > evm.code.len) {
        return error.InvalidOpcode;
    }

    var value = BigInt.init(0);

    // Read 14 bytes and store them in the BigInt (big-endian)
    for (0..14) |byte_idx| {
        const byte_val = evm.code[evm.pc + byte_idx];
        
        // Calculate position from most significant byte
        const global_pos = 14 - 1 - byte_idx;
        const word_idx = global_pos / 8;
        const byte_in_word = global_pos % 8;
        const shift_amount = @as(u6, @intCast(byte_in_word * 8));
        
        // Store in appropriate word (data[3] is most significant)
        value.data[3 - word_idx] |= (@as(u64, byte_val) << shift_amount);
    }

    evm.pc += 14;
    try evm.stack.push(evm.allocator, value);
}
