// File: src/opcodes/calldataload.zig
// CALLDATALOAD (0x35): Load 32 bytes of calldata
// Stack: offset -> data
// Reads 32 bytes from calldata starting at offset
// Pads with zeros if reading beyond calldata length

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CALLDATALOAD),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const offset_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Get offset as usize (cap at calldata length)
    const offset: usize = if (offset_big.fitsInU64())
        @intCast(@min(offset_big.data[0], evm.calldata.len))
    else
        evm.calldata.len; // Offset too large, return zeros

    // Read 32 bytes from calldata, padding with zeros if needed
    var bytes: [32]u8 = [_]u8{0} ** 32;
    const available = if (offset < evm.calldata.len)
        @min(32, evm.calldata.len - offset)
    else
        0;

    if (available > 0) {
        @memcpy(bytes[0..available], evm.calldata[offset .. offset + available]);
    }

    // Convert to BigInt (big-endian)
    const result = BigInt.fromBytes(bytes);
    try evm.stack.push(evm.allocator, result);
}
