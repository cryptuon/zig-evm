// File: src/opcodes/push1.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.PUSH1),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Check if there's enough code to read the next byte
    if (evm.pc >= evm.code.len) {
        return error.InvalidCode;
    }
    
    // Read the next byte as the value to push
    const value = evm.code[evm.pc];
    evm.pc += 1;
    
    // Push the value onto the stack as a BigInt
    try evm.stack.push(evm.allocator, BigInt.init(value));
}