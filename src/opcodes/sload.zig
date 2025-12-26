// File: src/opcodes/sload.zig
// SLOAD (0x54): Load word from storage
// Stack: key -> value
// Reads from the current contract's storage at the given key

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SLOAD),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Pop the storage key from stack
    const key = evm.stack.pop() orelse return error.StackUnderflow;

    // Get the current contract's account
    if (evm.accounts.getPtr(evm.current_address)) |account| {
        // Look up the value in storage
        const value = account.storage.get(key) orelse BigInt.zero();
        try evm.stack.push(evm.allocator, value);
    } else {
        // Account doesn't exist, return 0
        try evm.stack.push(evm.allocator, BigInt.zero());
    }
}
