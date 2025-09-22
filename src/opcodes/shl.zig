// File: src/opcodes/shl.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SHL),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |shift_bigint| {
        if (evm.stack.pop()) |value_bigint| {
            // SHL: shift left
            // If shift amount >= 256, result is 0
            if (shift_bigint.fitsInU64()) {
                const shift_amount = shift_bigint.data[0];
                if (shift_amount >= 256) {
                    try evm.stack.push(evm.allocator, BigInt.init(0));
                } else if (shift_amount == 0) {
                    try evm.stack.push(evm.allocator, value_bigint);
                } else {
                    // Perform left shift
                    var result = value_bigint;
                    var remaining_shift = shift_amount;

                    // Shift by full 64-bit chunks first
                    while (remaining_shift >= 64) {
                        // Shift all words left by one position
                        result.data[3] = result.data[2];
                        result.data[2] = result.data[1];
                        result.data[1] = result.data[0];
                        result.data[0] = 0;
                        remaining_shift -= 64;
                    }

                    // Handle remaining shift (< 64 bits)
                    if (remaining_shift > 0) {
                        const shift_bits = @as(u6, @intCast(remaining_shift));
                        const carry_mask = (@as(u64, 1) << shift_bits) - 1;
                        const carry_shift = @as(u6, @intCast(64 - remaining_shift));

                        var carry: u64 = 0;
                        for (0..4) |i| {
                            const new_carry = (result.data[i] >> carry_shift) & carry_mask;
                            result.data[i] = (result.data[i] << shift_bits) | carry;
                            carry = new_carry;
                        }
                    }

                    try evm.stack.push(evm.allocator, result);
                }
            } else {
                // Shift amount doesn't fit in u64, result is 0
                try evm.stack.push(evm.allocator, BigInt.init(0));
            }
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}