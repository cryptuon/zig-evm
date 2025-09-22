// File: src/opcodes/exp.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.EXP),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |b| {
        if (evm.stack.pop()) |a| {
            // Simplified exponentiation - only handle small exponents to avoid overflow
            if (b.fitsInU64() and a.fitsInU64()) {
                const base = a.data[0];
                const exponent = b.data[0];

                if (exponent == 0) {
                    // Any number to the power of 0 is 1
                    try evm.stack.push(evm.allocator, BigInt.init(1));
                } else if (base == 0) {
                    // 0 to any positive power is 0
                    try evm.stack.push(evm.allocator, BigInt.init(0));
                } else if (base == 1) {
                    // 1 to any power is 1
                    try evm.stack.push(evm.allocator, BigInt.init(1));
                } else if (exponent > 64) {
                    // For large exponents with base > 1, return 0 (EVM would run out of gas)
                    try evm.stack.push(evm.allocator, BigInt.init(0));
                } else {
                    // Simple exponentiation by repeated multiplication
                    var result: u64 = 1;
                    var i: u64 = 0;
                    while (i < exponent) : (i += 1) {
                        const overflow = @mulWithOverflow(result, base);
                        if (overflow[1] != 0) {
                            // Overflow occurred, return 0
                            result = 0;
                            break;
                        }
                        result = overflow[0];
                    }
                    try evm.stack.push(evm.allocator, BigInt.init(result));
                }
            } else {
                // For larger numbers, return 0 (would require complex arbitrary precision)
                try evm.stack.push(evm.allocator, BigInt.init(0));
            }
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}