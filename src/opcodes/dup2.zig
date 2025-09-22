// File: src/opcodes/dup2.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = 0x81, // DUP2
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Duplicate the second stack item (index 1 from top)
    if (evm.stack.items.items.len >= 2) {
        const len = evm.stack.items.items.len;
        const value = evm.stack.items.items[len - 2]; // Second from top
        try evm.stack.push(evm.allocator, value);
    } else return error.StackUnderflow;
}