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

    // Get sender account
    const sender_ptr = evm.accounts.getPtr(evm.current_address);
    if (sender_ptr == null) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }
    var sender = sender_ptr.?;

    // Check if sender has sufficient balance
    if (sender.balance.lt(value_big)) {
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }

    // Read init_code from memory
    try evm.memory.ensureCapacity(evm.allocator, offset + size);
    var init_code = try evm.allocator.alloc(u8, size);
    defer evm.allocator.free(init_code);
    for (0..size) |i| {
        init_code[i] = evm.memory.loadByte(offset + i);
    }

    // Calculate new contract address: keccak256(rlp([sender, nonce]))[12:]
    const new_address = crypto.createAddress(evm.current_address, sender.nonce);

    // Increment sender's nonce
    sender.nonce += 1;

    // Transfer value from sender to new contract
    sender.balance = sender.balance.sub(value_big);

    // Create new account
    const new_account = Account{
        .balance = value_big,
        .nonce = 0, // Contracts start with nonce 0 (or 1 per EIP-161)
        .code = &[_]u8{}, // Will be set after execution
        .storage = std.AutoHashMap(BigInt, BigInt).init(evm.allocator),
    };
    try evm.accounts.put(new_address, new_account);

    // For a full implementation, we would:
    // 1. Push a new call frame
    // 2. Execute init_code
    // 3. Use return data as the contract code
    // 4. Handle reverts and errors

    // Simplified: Store init_code directly as the contract code
    // In a full implementation, init_code would be executed and
    // the return data would become the contract code
    const new_account_ptr = evm.accounts.getPtr(new_address).?;
    new_account_ptr.code = try evm.allocator.dupe(u8, init_code);

    // Push new address to stack
    var addr_bytes: [32]u8 = [_]u8{0} ** 32;
    @memcpy(addr_bytes[12..32], &new_address);
    const result = BigInt.fromBytes(addr_bytes);
    try evm.stack.push(evm.allocator, result);
}
