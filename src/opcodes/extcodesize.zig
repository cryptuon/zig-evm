// File: src/opcodes/extcodesize.zig
// EXTCODESIZE (0x3b): Get size of an account's code
// Stack: address -> size
// Pushes the size of the code at the given address

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.EXTCODESIZE),
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
        const size = BigInt.init(@as(u64, account.code.len));
        try evm.stack.push(evm.allocator, size);
    } else {
        // Account doesn't exist, code size is 0
        try evm.stack.push(evm.allocator, BigInt.zero());
    }
}
