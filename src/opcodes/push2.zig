// File: src/opcodes/push2.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.PUSH2),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Check if there are enough bytes to read
    if (evm.pc + 1 >= evm.code.len) {
        return error.InvalidCode;
    }

    // Read the next 2 bytes as the value to push
    const byte1 = evm.code[evm.pc];
    const byte2 = evm.code[evm.pc + 1];
    evm.pc += 2;

    // Combine bytes into a 16-bit value
    const value = (@as(u64, byte1) << 8) | @as(u64, byte2);

    // Push the value onto the stack as a BigInt
    try evm.stack.push(evm.allocator, BigInt.init(value));
}