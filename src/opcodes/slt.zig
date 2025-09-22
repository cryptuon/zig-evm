// File: src/opcodes/slt.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SLT),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.stack.pop()) |b| {
        if (evm.stack.pop()) |a| {
            // Signed less-than comparison
            // For simplicity, handle cases that fit in 64 bits as signed
            var result: u64 = 0;

            if (a.fitsInU64() and b.fitsInU64()) {
                const a_signed = @as(i64, @bitCast(a.data[0]));
                const b_signed = @as(i64, @bitCast(b.data[0]));
                if (a_signed < b_signed) result = 1;
            } else {
                // For larger numbers, check sign bit (MSB of highest word)
                const a_negative = (a.data[3] & 0x8000000000000000) != 0;
                const b_negative = (b.data[3] & 0x8000000000000000) != 0;

                if (a_negative and !b_negative) {
                    result = 1; // negative < positive
                } else if (!a_negative and b_negative) {
                    result = 0; // positive >= negative
                } else {
                    // Same sign, use magnitude comparison
                    if (a_negative) {
                        // Both negative, larger magnitude is smaller value
                        result = if (a.gt(b)) 1 else 0;
                    } else {
                        // Both positive, normal comparison
                        result = if (a.lt(b)) 1 else 0;
                    }
                }
            }

            try evm.stack.push(evm.allocator, BigInt.init(result));
        } else return error.StackUnderflow;
    } else return error.StackUnderflow;
}