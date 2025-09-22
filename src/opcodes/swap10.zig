// File: src/opcodes/swap10.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SWAP10),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Swap the top item with the 11th item (indices 0 and 10 from top)
    if (evm.stack.items.items.len >= 11) {
        const len = evm.stack.items.items.len;
        const temp = evm.stack.items.items[len - 1]; // Top
        evm.stack.items.items[len - 1] = evm.stack.items.items[len - 11]; // 11th from top
        evm.stack.items.items[len - 11] = temp;
    } else return error.StackUnderflow;
}
