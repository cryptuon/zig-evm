// File: src/opcodes/msize.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.MSIZE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Get the current memory size
    const memory_size = evm.memory.size();

    // Push memory size onto stack as BigInt
    try evm.stack.push(evm.allocator, BigInt.init(@as(u64, @intCast(memory_size))));
}