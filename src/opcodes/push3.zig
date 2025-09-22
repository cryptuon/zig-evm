// File: src/opcodes/push3.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = 0x62, // PUSH3
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Check if there are enough bytes to read
    if (evm.pc + 2 >= evm.code.len) {
        return error.InvalidCode;
    }

    // Read the next 3 bytes as the value to push
    const byte1 = evm.code[evm.pc];
    const byte2 = evm.code[evm.pc + 1];
    const byte3 = evm.code[evm.pc + 2];
    evm.pc += 3;

    // Combine bytes into a 24-bit value
    const value = (@as(u64, byte1) << 16) | (@as(u64, byte2) << 8) | @as(u64, byte3);

    // Push the value onto the stack as a BigInt
    try evm.stack.push(evm.allocator, BigInt.init(value));
}