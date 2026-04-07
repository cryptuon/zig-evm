// File: src/opcodes/create2.zig
// CREATE2 (0xf5): Create a new contract with deterministic address
// Stack: value, offset, size, salt -> address
// Deploys using keccak256(0xff ++ sender ++ salt ++ keccak256(init_code))

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const Account = @import("../main.zig").Account;
const crypto = @import("../crypto.zig");

// Gas costs for CREATE2
const CREATE2_GAS: u64 = 32000;
const HASH_WORD_GAS: u64 = 6; // Gas per 32 bytes of init_code to hash

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.CREATE2),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Check if in static context (CREATE2 not allowed)
    if (evm.call_stack.isStatic()) {
        return error.StaticCallViolation;
    }

    // Consume base gas
    try evm.consumeGas(CREATE2_GAS);

    // Pop stack arguments
    const value_big = evm.stack.pop() orelse return error.StackUnderflow;
    const offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const size_big = evm.stack.pop() orelse return error.StackUnderflow;
    const salt_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Convert to usize
    if (!offset_big.fitsInU64() or !size_big.fitsInU64()) {
        // Push 0 on failure
        try evm.stack.push(evm.allocator, BigInt.zero());
        return;
    }
    const offset: usize = @intCast(offset_big.data[0]);
    const size: usize = @intCast(size_big.data[0]);

    // Convert salt to 32 bytes
    const salt = salt_big.toBytes();

    // Calculate and consume dynamic gas for hashing init_code
    const word_count = (size + 31) / 32;
    const hash_gas: u64 = @as(u64, word_count) * HASH_WORD_GAS;
    try evm.consumeGas(hash_gas);

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

    // Calculate new contract address: keccak256(0xff ++ sender ++ salt ++ keccak256(init_code))[12:]
    const new_address = crypto.create2Address(evm.current_address, salt, init_code);

    // Check if account already exists with code (collision)
    if (evm.accounts.get(new_address)) |existing| {
        if (existing.code.len > 0 or existing.nonce > 0) {
            // Address collision - return 0
            try evm.stack.push(evm.allocator, BigInt.zero());
            return;
        }
    }

    // Increment sender's nonce (CREATE2 also increments nonce)
    sender.nonce += 1;

    // Transfer value from sender to new contract
    sender.balance = sender.balance.sub(value_big);

    // Create new account
    const new_account = Account{
        .balance = value_big,
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(evm.allocator),
    };
    try evm.accounts.put(new_address, new_account);

    // Simplified: Store init_code directly as contract code
    // Full implementation would execute init_code and use return data
    const new_account_ptr = evm.accounts.getPtr(new_address).?;
    new_account_ptr.code = try evm.allocator.dupe(u8, init_code);

    // Push new address to stack
    var addr_bytes: [32]u8 = [_]u8{0} ** 32;
    @memcpy(addr_bytes[12..32], &new_address);
    const result = BigInt.fromBytes(addr_bytes);
    try evm.stack.push(evm.allocator, result);
}
