// File: src/opcodes/callvalue.zig
// CALLVALUE (0x34): Get deposited value
// Stack: -> value
// Pushes the value (in wei) sent with the current call

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CALLVALUE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    try evm.stack.push(evm.allocator, evm.call_value);
}
