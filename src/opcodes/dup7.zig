// File: src/opcodes/dup7.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.DUP7),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Duplicate the 7th stack item (index 7 from top)
    if (evm.stack.items.items.len >= 7) {
        const len = evm.stack.items.items.len;
        const value = evm.stack.items.items[len - 7]; // 7th from top
        try evm.stack.push(evm.allocator, value);
    } else return error.StackUnderflow;
}
