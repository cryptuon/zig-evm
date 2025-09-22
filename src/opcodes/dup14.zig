// File: src/opcodes/dup14.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.DUP14),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Duplicate the 14th stack item (index 14 from top)
    if (evm.stack.items.items.len >= 14) {
        const len = evm.stack.items.items.len;
        const value = evm.stack.items.items[len - 14]; // 14th from top
        try evm.stack.push(evm.allocator, value);
    } else return error.StackUnderflow;
}
