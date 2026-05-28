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

    // EIP-2929: 2100 gas if this slot is cold (first access this tx), else 100.
    const cold = try evm.accessSlot(evm.current_address, key);
    try evm.consumeGas(if (cold) EVM.COLD_SLOAD_COST else EVM.WARM_STORAGE_READ_COST);

    // Read through the recording helper so the access is captured in the
    // transaction's read set when an AccessRecorder is attached.
    const value = try evm.loadStorage(evm.current_address, key);
    try evm.stack.push(evm.allocator, value);
}
