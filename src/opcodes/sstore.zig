// File: src/opcodes/sstore.zig
// SSTORE (0x55): Save word to storage
// Stack: key, value -> (none)
//
// Gas follows EIP-2929 (cold/warm access), EIP-2200 (net gas metering by the
// original/current/new value triple), and EIP-3529 (reduced refunds). The
// refund is accumulated on the EVM and applied, capped, at transaction end.

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.SSTORE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const key = evm.stack.pop() orelse return error.StackUnderflow;
    const new_value = evm.stack.pop() orelse return error.StackUnderflow;

    // EIP-2929 cold/warm slot access.
    const cold = try evm.accessSlot(evm.current_address, key);
    // Current value (records the read), and the transaction-start original.
    const current = try evm.loadStorage(evm.current_address, key);
    const original = try evm.captureOriginal(evm.current_address, key, current);

    var gas = sstoreDynamicGas(original, current, new_value);
    if (cold) gas += EVM.COLD_SLOAD_COST;
    try evm.consumeGas(gas);

    evm.gas_refund += sstoreRefund(original, current, new_value);

    try evm.storeStorage(evm.current_address, key, new_value);
}

/// EIP-2200 net-gas-metering dynamic cost (warm; the EIP-2929 cold surcharge is
/// added by the caller).
pub fn sstoreDynamicGas(original: BigInt, current: BigInt, new_value: BigInt) u64 {
    if (current.eq(new_value)) return EVM.WARM_STORAGE_READ_COST; // no-op store
    if (original.eq(current)) {
        // Slot untouched so far this tx: first real change.
        if (original.isZero()) return EVM.SSTORE_SET_GAS; // 0 -> non-zero
        return EVM.SSTORE_RESET_GAS; // non-zero -> different
    }
    // Slot already changed earlier this tx ("dirty"): only warm read cost.
    return EVM.WARM_STORAGE_READ_COST;
}

/// EIP-3529 refund delta for this SSTORE (signed; refunds can be retracted).
pub fn sstoreRefund(original: BigInt, current: BigInt, new_value: BigInt) i64 {
    if (current.eq(new_value)) return 0;

    var r: i64 = 0;
    if (original.eq(current)) {
        // First change this tx.
        if (!original.isZero() and new_value.isZero()) r += EVM.SSTORE_CLEARS_SCHEDULE;
    } else {
        // Dirty slot.
        if (!original.isZero()) {
            if (current.isZero()) {
                r -= EVM.SSTORE_CLEARS_SCHEDULE; // un-clear: it was cleared earlier
            } else if (new_value.isZero()) {
                r += EVM.SSTORE_CLEARS_SCHEDULE; // clearing now
            }
        }
        if (original.eq(new_value)) {
            // Restored to its original value: refund the earlier over-charge.
            if (original.isZero()) {
                r += @as(i64, @intCast(EVM.SSTORE_SET_GAS - EVM.WARM_STORAGE_READ_COST)); // 19900
            } else {
                r += @as(i64, @intCast(EVM.SSTORE_RESET_GAS - EVM.WARM_STORAGE_READ_COST)); // 2800
            }
        }
    }
    return r;
}
