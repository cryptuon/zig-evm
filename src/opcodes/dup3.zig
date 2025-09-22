// File: src/opcodes/dup3.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = 0x82, // DUP3
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Duplicate the third stack item (index 2 from top)
    if (evm.stack.items.items.len >= 3) {
        const len = evm.stack.items.items.len;
        const value = evm.stack.items.items[len - 3]; // Third from top
        try evm.stack.push(evm.allocator, value);
    } else return error.StackUnderflow;
}