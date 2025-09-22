// File: src/opcodes/jumpi.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.JUMPI),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |dest_bigint| {
        if (evm.stack.pop()) |condition_bigint| {
            // Check if condition is non-zero (truthy)
            if (!condition_bigint.isZero()) {
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
            }
            // If condition is zero, continue to next instruction (no jump)
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}