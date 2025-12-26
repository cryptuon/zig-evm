// File: src/opcodes/sstore.zig
// SSTORE (0x55): Save word to storage
// Stack: key, value -> (none)
// Writes to the current contract's storage at the given key
//
// Gas costs (simplified, per EIP-2200):
// - SSTORE_SET (zero to non-zero): 20000 gas
// - SSTORE_RESET (non-zero to non-zero or non-zero to zero): 2900 gas
// - SLOAD_GAS (cold access): 2100 gas
// Note: Full EIP-2200 implementation would track warm/cold access

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const Account = @import("../main.zig").Account;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SSTORE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Pop key and value from stack
    const key = evm.stack.pop() orelse return error.StackUnderflow;
    const value = evm.stack.pop() orelse return error.StackUnderflow;

    // Get or create the current contract's account
    const account_ptr = evm.accounts.getPtr(evm.current_address);

    if (account_ptr) |account| {
        // Get current value for gas calculation
        const current_value = account.storage.get(key) orelse BigInt.zero();

        // Calculate dynamic gas cost based on storage change
        const dynamic_gas = calculateSstoreGas(current_value, value);
        try evm.consumeGas(dynamic_gas);

        // Store the value
        if (value.isZero()) {
            // If setting to zero, remove the key (storage cleanup)
            _ = account.storage.remove(key);
        } else {
            try account.storage.put(key, value);
        }
    } else {
        // Account doesn't exist - this shouldn't happen in normal execution
        // because the current contract should always exist
        // For robustness, create the account
        var new_account = Account{
            .balance = BigInt.zero(),
            .nonce = 0,
            .code = &[_]u8{},
            .storage = std.AutoHashMap(BigInt, BigInt).init(evm.allocator),
        };

        // Calculate gas for new storage slot
        const dynamic_gas = calculateSstoreGas(BigInt.zero(), value);
        try evm.consumeGas(dynamic_gas);

        if (!value.isZero()) {
            try new_account.storage.put(key, value);
        }
        try evm.accounts.put(evm.current_address, new_account);
    }
}

/// Calculate SSTORE gas cost based on EIP-2200
/// Simplified version - full implementation would track warm/cold slots
fn calculateSstoreGas(current: BigInt, new: BigInt) u64 {
    const current_is_zero = current.isZero();
    const new_is_zero = new.isZero();

    if (current.eq(new)) {
        // No change - minimal gas (warm access)
        return 100;
    } else if (current_is_zero and !new_is_zero) {
        // Zero to non-zero: SSTORE_SET
        return 20000;
    } else if (!current_is_zero and new_is_zero) {
        // Non-zero to zero: SSTORE_RESET (with refund, but refunds handled elsewhere)
        return 2900;
    } else {
        // Non-zero to different non-zero: SSTORE_RESET
        return 2900;
    }
}
