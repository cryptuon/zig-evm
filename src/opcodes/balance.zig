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
    // Pop address from stack. An address is the low 20 bytes of the 256-bit
    // word, big-endian (matching EXTCODESIZE/CALL and the rest of the EVM).
    if (evm.stack.pop()) |address_bigint| {
        const addr_bytes = address_bigint.toBytes();
        var address: [20]u8 = undefined;
        @memcpy(&address, addr_bytes[12..32]);

        // EIP-2929: 2600 gas if the account is cold this tx, else 100.
        const cold = try evm.accessAccount(address);
        try evm.consumeGas(if (cold) EVM.COLD_ACCOUNT_ACCESS_COST else EVM.WARM_STORAGE_READ_COST);

        // Look up account balance through the recording helper.
        const bal = try evm.loadBalance(address);
        try evm.stack.push(evm.allocator, bal);
    } else {
        return error.StackUnderflow;
    }
}