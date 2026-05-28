// File: src/opcodes/create.zig
// CREATE (0xf0): Create a new contract
// Stack: value, offset, size -> address
// Deploys a new contract using keccak256(rlp([sender, nonce]))

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const Account = @import("../main.zig").Account;
const StateKey = @import("../main.zig").StateKey;
const crypto = @import("../crypto.zig");

// Gas costs for CREATE
const CREATE_GAS: u64 = 32000;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CREATE),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Check if in static context (CREATE not allowed)
    if (evm.call_stack.isStatic()) {
        return error.StaticCallViolation;
    }

    // Consume base gas
    try evm.consumeGas(CREATE_GAS);

    // Pop stack arguments
    const value_big = evm.stack.pop() orelse return error.StackUnderflow;
    const offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const size_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Convert to usize
    if (!offset_big.fitsInU64() or !size_big.fitsInU64()) {
        // Push 0 on failure (address creation failed)
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }
    const offset: usize = @intCast(offset_big.data[0]);
    const size: usize = @intCast(size_big.data[0]);

    // Check call depth
    if (evm.call_stack.depth() >= 1024) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }

    // Sender balance check (read through the recording helper; no account
    // pointer is held across the map mutations that follow).
    const sender_bal = try evm.loadBalance(evm.current_address);
    if (sender_bal.lt(value_big)) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }
    const sender_nonce: u64 = if (evm.accounts.get(evm.current_address)) |acc| acc.nonce else 0;

    // Read init_code from memory.
    try evm.memory.ensureCapacity(evm.allocator, offset + size);
    var init_code = try evm.allocator.alloc(u8, size);
    defer evm.allocator.free(init_code);
    for (0..size) |i| {
        init_code[i] = evm.memory.loadByte(offset + i);
    }

    // The created address derives from the sender's nonce, and CREATE bumps it.
    try evm.noteRead(StateKey.nonceOf(evm.current_address));
    const new_address = crypto.createAddress(evm.current_address, sender_nonce);
    if (evm.accounts.getPtr(evm.current_address)) |s| s.nonce += 1;
    try evm.noteWrite(StateKey.nonceOf(evm.current_address));

    // Ensure the new account exists (empty) before its init code runs.
    if (!evm.accounts.contains(new_address)) {
        try evm.accounts.put(new_address, .{
            .balance = BigInt.zero(),
            .nonce = 0,
            .code = &[_]u8{},
            .storage = std.AutoHashMap(BigInt, BigInt).init(evm.allocator),
        });
    }

    // Transfer value to the new contract (journaled; rolls back on revert).
    if (!value_big.isZero()) {
        try evm.storeBalance(evm.current_address, sender_bal.sub(value_big));
        const nb = try evm.loadBalance(new_address);
        try evm.storeBalance(new_address, nb.add(value_big));
    }

    // Execute the init code in the new account's context; its RETURN data
    // becomes the deployed code. On revert the journaled state changes unwind.
    const call_gas = evm.gas - evm.gas / 64;
    const ok = try evm.runSubContext(init_code, new_address, evm.current_address, value_big, &[_]u8{}, false, call_gas);
    if (!ok) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }

    if (evm.accounts.getPtr(new_address)) |acct| {
        if (acct.code.len > 0) evm.allocator.free(acct.code);
        acct.code = try evm.allocator.dupe(u8, evm.return_data);
    }
    try evm.noteWrite(StateKey.codeOf(new_address));

    // Push new address to stack
    var addr_bytes: [32]u8 = [_]u8{0} ** 32;
    @memcpy(addr_bytes[12..32], &new_address);
    const result = BigInt.fromBytes(addr_bytes);
    try evm.stack.push(evm.allocator, result);
}
