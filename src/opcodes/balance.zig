// File: src/opcodes/balance.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.BALANCE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Pop address from stack
    if (evm.stack.pop()) |address_bigint| {
        // Convert BigInt to 20-byte address
        var address: [20]u8 = [_]u8{0} ** 20;

        // Extract address from BigInt (reverse the encoding)
        for (0..20) |i| {
            const bit_pos = i * 8;
            const word_idx = bit_pos / 64;
            const bit_in_word = bit_pos % 64;

            if (word_idx < 4) {
                const word_val = address_bigint.data[word_idx];
                address[i] = @intCast((word_val >> @intCast(bit_in_word)) & 0xFF);
            }
        }

        // Look up account balance
        if (evm.accounts.get(address)) |account| {
            try evm.stack.push(evm.allocator, account.balance);
        } else {
            // Account doesn't exist, balance is 0
            try evm.stack.push(evm.allocator, BigInt.init(0));
        }
    } else {
        return error.StackUnderflow;
    }
}