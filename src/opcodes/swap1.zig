// File: src/opcodes/swap1.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SWAP1),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Swap the top two stack items
    if (evm.stack.items.items.len >= 2) {
        const len = evm.stack.items.items.len;
        const temp = evm.stack.items.items[len - 1];
        evm.stack.items.items[len - 1] = evm.stack.items.items[len - 2];
        evm.stack.items.items[len - 2] = temp;
    } else return error.StackUnderflow;
}