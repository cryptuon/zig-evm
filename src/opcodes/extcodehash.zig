// File: src/opcodes/extcodehash.zig
// EXTCODEHASH (0x3f): Get hash of an account's code
// Stack: address -> hash
// Returns the keccak256 hash of the account's code
// Returns 0 if the account doesn't exist
// Returns empty code hash if account exists but has no code

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const crypto = @import("../crypto.zig");

// keccak256("") - empty code hash constant
const EMPTY_CODE_HASH: [32]u8 = .{
    0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c,
    0x92, 0x7e, 0x7d, 0xb2, 0xdc, 0xc7, 0x03, 0xc0,
    0xe5, 0x00, 0xb6, 0x53, 0xca, 0x82, 0x27, 0x3b,
    0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85, 0xa4, 0x70,
};

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.EXTCODEHASH),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const addr_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Convert BigInt to address (take last 20 bytes)
    const addr_bytes = addr_big.toBytes();
    var address: [20]u8 = undefined;
    @memcpy(&address, addr_bytes[12..32]);

    // Look up account
    if (evm.accounts.get(address)) |account| {
        if (account.code.len == 0) {
            // Empty code - return empty code hash
            const result = BigInt.fromBytes(EMPTY_CODE_HASH);
            try evm.stack.push(evm.allocator, result);
        } else {
            // Compute keccak256 of code
            const hash = crypto.keccak256(account.code);
            const result = BigInt.fromBytes(hash);
            try evm.stack.push(evm.allocator, result);
        }
    } else {
        // Account doesn't exist - return 0
        try evm.stack.push(evm.allocator, BigInt.zero());
    }
}
