// File: src/opcodes/calldatasize.zig
// CALLDATASIZE (0x36): Get size of calldata
// Stack: -> size
// Pushes the size of the input data (calldata) to the stack

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CALLDATASIZE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const size = BigInt.init(@as(u64, evm.calldata.len));
    try evm.stack.push(evm.allocator, size);
}
