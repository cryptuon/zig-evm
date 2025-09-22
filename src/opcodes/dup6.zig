// File: src/opcodes/dup6.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.DUP6),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Duplicate the 6th stack item (index 6 from top)
    if (evm.stack.items.items.len >= 6) {
        const len = evm.stack.items.items.len;
        const value = evm.stack.items.items[len - 6]; // 6th from top
        try evm.stack.push(evm.allocator, value);
    } else return error.StackUnderflow;
}
