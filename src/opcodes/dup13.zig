// File: src/opcodes/dup13.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.DUP13),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Duplicate the 13th stack item (index 13 from top)
    if (evm.stack.items.items.len >= 13) {
        const len = evm.stack.items.items.len;
        const value = evm.stack.items.items[len - 13]; // 13th from top
        try evm.stack.push(evm.allocator, value);
    } else return error.StackUnderflow;
}
