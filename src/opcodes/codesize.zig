// File: src/opcodes/codesize.zig
// CODESIZE (0x38): Get size of code running in current environment
// Stack: -> size
// Pushes the size of the currently executing contract's code

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CODESIZE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const size = BigInt.init(@as(u64, evm.code.len));
    try evm.stack.push(evm.allocator, size);
}
