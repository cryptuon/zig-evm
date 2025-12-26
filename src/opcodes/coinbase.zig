// File: src/opcodes/coinbase.zig
// COINBASE (0x41): Get the block's beneficiary address
// Stack: -> address
// Pushes the address of the current block's miner/validator (coinbase)

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.COINBASE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Convert coinbase address to BigInt
    // Address is 20 bytes, pad to 32 bytes
    var bytes: [32]u8 = [_]u8{0} ** 32;
    @memcpy(bytes[12..32], &evm.coinbase);

    const result = BigInt.fromBytes(bytes);
    try evm.stack.push(evm.allocator, result);
}
