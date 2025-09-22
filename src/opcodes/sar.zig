// File: src/opcodes/sar.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SAR),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |shift_bigint| {
        if (evm.stack.pop()) |value_bigint| {
            // SAR: arithmetic right shift (sign-extending)
            // For BigInt, if it fits in u64, check sign bit in data[0], otherwise check data[3]
            const is_negative = if (value_bigint.fitsInU64())
                (value_bigint.data[0] & 0x8000000000000000) != 0
            else
                (value_bigint.data[3] & 0x8000000000000000) != 0;

            if (shift_bigint.fitsInU64()) {
                const shift_amount = shift_bigint.data[0];
                if (shift_amount >= 256) {
                    // For very large shifts, result depends on sign
                    if (is_negative) {
                        // All bits set (maximum negative value)
                        try evm.stack.push(evm.allocator, BigInt{ .data = [_]u64{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } });
                    } else {
                        try evm.stack.push(evm.allocator, BigInt.init(0));
                    }
                } else if (shift_amount == 0) {
                    try evm.stack.push(evm.allocator, value_bigint);
                } else {
                    // For simple case where value fits in u64, use native arithmetic shift
                    if (value_bigint.fitsInU64() and shift_amount < 64) {
                        const signed_value = @as(i64, @bitCast(value_bigint.data[0]));
                        const shifted_signed = signed_value >> @as(u6, @intCast(shift_amount));
                        const result = BigInt.init(@as(u64, @bitCast(shifted_signed)));
                        try evm.stack.push(evm.allocator, result);
                    } else {
                        // Complex multi-word arithmetic shift - for now, fallback to logical shift for positive
                        if (!is_negative) {
                            // Use logical right shift for positive numbers
                            var result = value_bigint;
                            var remaining_shift = shift_amount;

                            while (remaining_shift >= 64) {
                                result.data[0] = result.data[1];
                                result.data[1] = result.data[2];
                                result.data[2] = result.data[3];
                                result.data[3] = 0;
                                remaining_shift -= 64;
                            }

                            if (remaining_shift > 0) {
                                const shift_bits = @as(u6, @intCast(remaining_shift));
                                const carry_shift = @as(u6, @intCast(64 - remaining_shift));
                                var carry: u64 = 0;
                                var i: usize = 4;
                                while (i > 0) {
                                    i -= 1;
                                    const new_carry = result.data[i] & ((@as(u64, 1) << shift_bits) - 1);
                                    result.data[i] = (result.data[i] >> shift_bits) | (carry << carry_shift);
                                    carry = new_carry;
                                }
                            }
                            try evm.stack.push(evm.allocator, result);
                        } else {
                            // For negative numbers with complex shifts, use all 1s for large shifts
                            try evm.stack.push(evm.allocator, BigInt{ .data = [_]u64{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } });
                        }
                    }
                }
            } else {
                // Shift amount doesn't fit in u64
                if (is_negative) {
                    try evm.stack.push(evm.allocator, BigInt{ .data = [_]u64{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } });
                } else {
                    try evm.stack.push(evm.allocator, BigInt.init(0));
                }
            }
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}