// File: src/opcodes/jumpdest.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.JUMPDEST),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // JUMPDEST is a no-op instruction that marks valid jump destinations
    // It consumes no stack items and produces no effects
    _ = evm; // Suppress unused parameter warning
}