// File: src/opcodes/jump.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.JUMP),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |dest_bigint| {
        // Convert BigInt destination to usize
        const dest = @as(usize, @intCast(dest_bigint.data[0]));

        // Validate jump destination
        if (dest >= evm.code.len) {
            return error.InvalidJump;
        }

        // Validate that destination is a JUMPDEST (0x5b)
        if (evm.code[dest] != 0x5b) {
            return error.InvalidJump;
        }

        // Set program counter to jump destination
        evm.pc = dest;
    } else return error.StackUnderflow;
}