// Integration test: real EVM bytecode populates the dynamic read/write set.
//
// This closes the loop on engine milestone M2 — it exercises the actual opcode
// execution path (not the data structures in isolation) and asserts that an
// attached AccessRecorder captures storage and balance accesses at slot
// granularity. These captured sets are the raw material for the block conflict
// graph used by the parallel-execution engine and the contention measurements.

const std = @import("std");
const testing = std.testing;
const main = @import("../src/main.zig");
const EVM = main.EVM;
const BigInt = main.BigInt;
const StateKey = main.StateKey;
const AccessRecorder = main.AccessRecorder;
const crypto = @import("../src/crypto.zig");

const Opcode = main.Opcode;

fn op(o: Opcode) u8 {
    return @intFromEnum(o);
}

test "access-recording: SSTORE then SLOAD record a write and a read of the same slot" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    var recorder = AccessRecorder.init(allocator);
    defer recorder.deinit();
    evm.access = &recorder;
    evm.setGasLimit(10_000_000);

    // PUSH1 0x2a, PUSH1 0x01, SSTORE   ; storage[1] = 42
    // PUSH1 0x01, SLOAD                ; load storage[1]
    // STOP
    const bytecode = [_]u8{
        op(.PUSH1), 0x2a,
        op(.PUSH1), 0x01,
        op(.SSTORE),
        op(.PUSH1), 0x01,
        op(.SLOAD),
        op(.STOP),
    };
    evm.code = &bytecode;
    evm.pc = 0;
    try evm.execute();

    // The value round-tripped through storage.
    const top = evm.stack.pop() orelse return error.TestUnexpectedResult;
    try testing.expect(top.eq(BigInt.init(42)));

    // Slot 1 of the executing account was both written and read.
    const slot1 = StateKey.storageOf(evm.current_address, BigInt.init(1));
    try testing.expect(recorder.write_set.contains(slot1));
    try testing.expect(recorder.readKey(slot1));

    // A slot we never touched is absent from both sets.
    const slot2 = StateKey.storageOf(evm.current_address, BigInt.init(2));
    try testing.expect(!recorder.write_set.contains(slot2));
    try testing.expect(!recorder.readKey(slot2));
}

test "access-recording: opt-in, no recorder means no overhead and no capture" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();
    // evm.access stays null.
    evm.setGasLimit(10_000_000);

    const bytecode = [_]u8{
        op(.PUSH1), 0x07,
        op(.PUSH1), 0x09,
        op(.SSTORE),
        op(.STOP),
    };
    evm.code = &bytecode;
    evm.pc = 0;
    try evm.execute();

    // The write still happened (semantics unchanged), proven via a read.
    const v = try evm.loadStorage(evm.current_address, BigInt.init(9));
    try testing.expect(v.eq(BigInt.init(7)));
}

test "access-recording: EXTCODESIZE records a code read of the queried account" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    var recorder = AccessRecorder.init(allocator);
    defer recorder.deinit();
    evm.access = &recorder;
    evm.setGasLimit(10_000_000);

    // PUSH1 0x05, EXTCODESIZE, STOP  -> queries code of 0x00..05
    const bytecode = [_]u8{ op(.PUSH1), 0x05, op(.EXTCODESIZE), op(.STOP) };
    evm.code = &bytecode;
    evm.pc = 0;
    try evm.execute();

    var queried: [20]u8 = [_]u8{0} ** 20;
    queried[19] = 0x05;
    try testing.expect(recorder.readKey(StateKey.codeOf(queried)));
}

test "access-recording: CALL with value records balance reads/writes of caller and callee" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Fund the executing account so the value transfer can proceed.
    const caller: [20]u8 = [_]u8{0xC0} ** 20;
    try evm.accounts.put(caller, .{
        .balance = BigInt.init(1000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    });
    evm.current_address = caller;

    var recorder = AccessRecorder.init(allocator);
    defer recorder.deinit();
    evm.access = &recorder;
    evm.setGasLimit(10_000_000);

    // CALL pops gas, addr, value, argsOffset, argsSize, retOffset, retSize (top
    // first), so push them in reverse: retSize,retOffset,argsSize,argsOffset,
    // value, addr, gas. Transfer value 5 to 0x00..09.
    const bytecode = [_]u8{
        op(.PUSH1), 0x00, // retSize
        op(.PUSH1), 0x00, // retOffset
        op(.PUSH1), 0x00, // argsSize
        op(.PUSH1), 0x00, // argsOffset
        op(.PUSH1), 0x05, // value
        op(.PUSH1), 0x09, // addr
        op(.PUSH1), 0x00, // gas
        op(.CALL),
        op(.STOP),
    };
    evm.code = &bytecode;
    evm.pc = 0;
    try evm.execute();

    var callee: [20]u8 = [_]u8{0} ** 20;
    callee[19] = 0x09;
    // Both balances were written (the transfer), and the callee's code was read.
    try testing.expect(recorder.write_set.contains(StateKey.balanceOf(caller)));
    try testing.expect(recorder.write_set.contains(StateKey.balanceOf(callee)));
    try testing.expect(recorder.readKey(StateKey.codeOf(callee)));
    // The caller now holds 995.
    try testing.expect((try evm.loadBalance(caller)).eq(BigInt.init(995)));
}

test "access-recording: CREATE records sender nonce read/write and new-contract code write" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    const creator: [20]u8 = [_]u8{0xCE} ** 20;
    try evm.accounts.put(creator, .{
        .balance = BigInt.init(100),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    });
    evm.current_address = creator;

    var recorder = AccessRecorder.init(allocator);
    defer recorder.deinit();
    evm.access = &recorder;
    evm.setGasLimit(10_000_000);

    // CREATE pops value, offset, size (value first), so push size,offset,value.
    // size=0 (empty init code), value=0.
    const bytecode = [_]u8{ op(.PUSH1), 0x00, op(.PUSH1), 0x00, op(.PUSH1), 0x00, op(.CREATE), op(.STOP) };
    evm.code = &bytecode;
    evm.pc = 0;
    try evm.execute();

    // Sender nonce was read and written; the new contract's code was written.
    try testing.expect(recorder.readKey(StateKey.nonceOf(creator)));
    try testing.expect(recorder.write_set.contains(StateKey.nonceOf(creator)));
    var code_writes: usize = 0;
    for (recorder.write_set.keys.items) |k| {
        if (k.tag == .code) code_writes += 1;
    }
    try testing.expectEqual(@as(usize, 1), code_writes);
}

test "access-recording: nested CALL executes the target's code (state change persists, return data propagates)" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();
    evm.setGasLimit(10_000_000);

    // Callee B at 0x00..42: store 99 at slot 7, then RETURN the 32-byte word at
    // memory[0..32] (which MSTORE wrote = 0xAB).
    //   PUSH1 99, PUSH1 7, SSTORE,            ; storage[7] = 99
    //   PUSH1 0xAB, PUSH1 0, MSTORE,          ; memory[0..32] = 0xAB
    //   PUSH1 32, PUSH1 0, RETURN             ; return 32 bytes
    const callee_code = [_]u8{
        op(.PUSH1), 99,   op(.PUSH1), 7,    op(.SSTORE),
        op(.PUSH1), 0xAB, op(.PUSH1), 0,    op(.MSTORE),
        op(.PUSH1), 32,   op(.PUSH1), 0,    op(.RETURN),
    };
    var B: [20]u8 = [_]u8{0} ** 20;
    B[19] = 0x42;
    try evm.accounts.put(B, .{
        .balance = BigInt.init(0),
        .nonce = 0,
        .code = try allocator.dupe(u8, &callee_code),
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    });

    const A: [20]u8 = [_]u8{0xA0} ** 20;
    evm.current_address = A;

    // Caller A: CALL B with no value, no args, capturing 32 bytes of return data
    // into memory[0..32]. retSize=32,retOff=0,argsSize=0,argsOff=0,value=0,addr=B,gas=0
    const caller_code = [_]u8{
        op(.PUSH1), 32,   // retSize
        op(.PUSH1), 0,    // retOffset
        op(.PUSH1), 0,    // argsSize
        op(.PUSH1), 0,    // argsOffset
        op(.PUSH1), 0,    // value
        op(.PUSH1), 0x42, // addr = B
        op(.GAS),         // gas: forward (almost) all
        op(.CALL),
        op(.STOP),
    };
    evm.code = &caller_code;
    evm.pc = 0;
    try evm.execute();

    // CALL pushed success.
    try testing.expect((evm.stack.pop() orelse return error.TestUnexpectedResult).eq(BigInt.init(1)));
    // The sub-call's SSTORE persisted to B's storage.
    try testing.expect((evm.accounts.getPtr(B).?).storage.get(BigInt.init(7)).?.eq(BigInt.init(99)));
    // The sub-call's RETURN data (0xAB in the low byte of a 32-byte word) is the
    // current return data and was copied into the caller's memory window.
    try testing.expectEqual(@as(usize, 32), evm.return_data.len);
    try testing.expectEqual(@as(u8, 0xAB), evm.return_data[31]);
}

test "access-recording: CREATE executes init code and adopts the returned runtime code" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();
    evm.setGasLimit(10_000_000);

    const C: [20]u8 = [_]u8{0xCE} ** 20;
    try evm.accounts.put(C, .{
        .balance = BigInt.init(0),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    });
    evm.current_address = C;

    // Creator C writes a 5-byte init code into memory, then CREATEs it.
    // init code = { PUSH1 1, PUSH1 0, RETURN } = 60 01 60 00 F3, which returns
    // memory[0..1] (= 0x00) as the deployed runtime code.
    // For each init byte: PUSH1 <byte>, PUSH1 <offset>, MSTORE8.
    const code = [_]u8{
        op(.PUSH1), 0x60, op(.PUSH1), 0, op(.MSTORE8),
        op(.PUSH1), 0x01, op(.PUSH1), 1, op(.MSTORE8),
        op(.PUSH1), 0x60, op(.PUSH1), 2, op(.MSTORE8),
        op(.PUSH1), 0x00, op(.PUSH1), 3, op(.MSTORE8),
        op(.PUSH1), 0xF3, op(.PUSH1), 4, op(.MSTORE8),
        // CREATE: pops value, offset, size -> push size, offset, value.
        op(.PUSH1), 5, op(.PUSH1), 0, op(.PUSH1), 0, op(.CREATE),
        op(.STOP),
    };
    evm.code = &code;
    evm.pc = 0;
    try evm.execute();

    // The created address is keccak256(rlp([C, nonce=0]))[12:].
    const new_address = crypto.createAddress(C, 0);
    const created = evm.accounts.getPtr(new_address) orelse return error.TestUnexpectedResult;
    // Deployed code is the init code's RETURN data: a single 0x00 byte.
    try testing.expectEqual(@as(usize, 1), created.code.len);
    try testing.expectEqual(@as(u8, 0x00), created.code[0]);
    // Sender nonce was bumped.
    try testing.expectEqual(@as(u64, 1), evm.accounts.getPtr(C).?.nonce);
}

test "access-recording: forwarded gas is capped; a starved sub-call fails and is rolled back, parent survives" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();
    evm.setGasLimit(100_000);

    // Callee B: SSTORE slot 4 = 55 (needs >22000 gas), STOP.
    const callee_code = [_]u8{ op(.PUSH1), 55, op(.PUSH1), 4, op(.SSTORE), op(.STOP) };
    var B: [20]u8 = [_]u8{0} ** 20;
    B[19] = 0x42;
    try evm.accounts.put(B, .{
        .balance = BigInt.init(0),
        .nonce = 0,
        .code = try allocator.dupe(u8, &callee_code),
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    });

    const A: [20]u8 = [_]u8{0xA0} ** 20;
    evm.current_address = A;

    // A CALLs B forwarding only 5 gas (the `gas` arg) — far too little for the
    // SSTORE — then STOPs.
    const caller_code = [_]u8{
        op(.PUSH1), 0,    // retSize
        op(.PUSH1), 0,    // retOffset
        op(.PUSH1), 0,    // argsSize
        op(.PUSH1), 0,    // argsOffset
        op(.PUSH1), 0,    // value
        op(.PUSH1), 0x42, // addr = B
        op(.PUSH1), 5,    // gas = 5 (insufficient)
        op(.CALL),
        op(.STOP),
    };
    evm.code = &caller_code;
    evm.pc = 0;
    try evm.execute(); // parent does NOT run out of gas (kept its 63/64)

    // CALL reported failure and B's storage was rolled back.
    try testing.expect((evm.stack.pop() orelse return error.TestUnexpectedResult).eq(BigInt.zero()));
    try testing.expect((evm.accounts.getPtr(B).?).storage.get(BigInt.init(4)) == null);
    // The parent retained gas to finish.
    try testing.expect(evm.gas > 0);
}

test "access-recording: a reverted sub-call's state changes are rolled back" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();
    evm.setGasLimit(10_000_000);

    // Callee B: SSTORE slot 3 = 88, then REVERT(0,0). The write must be undone.
    const callee_code = [_]u8{
        op(.PUSH1), 88, op(.PUSH1), 3, op(.SSTORE),
        op(.PUSH1), 0,  op(.PUSH1), 0, op(.REVERT),
    };
    var B: [20]u8 = [_]u8{0} ** 20;
    B[19] = 0x42;
    try evm.accounts.put(B, .{
        .balance = BigInt.init(0),
        .nonce = 0,
        .code = try allocator.dupe(u8, &callee_code),
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    });

    const A: [20]u8 = [_]u8{0xA0} ** 20;
    evm.current_address = A;

    // A CALLs B (no value/args/return).
    const caller_code = [_]u8{
        op(.PUSH1), 0, op(.PUSH1), 0, op(.PUSH1), 0, op(.PUSH1), 0,
        op(.PUSH1), 0, op(.PUSH1), 0x42, op(.GAS),
        op(.CALL),
        op(.STOP),
    };
    evm.code = &caller_code;
    evm.pc = 0;
    try evm.execute();

    // CALL reported failure (0), and B's storage slot 3 was rolled back.
    try testing.expect((evm.stack.pop() orelse return error.TestUnexpectedResult).eq(BigInt.zero()));
    try testing.expect((evm.accounts.getPtr(B).?).storage.get(BigInt.init(3)) == null);
}

test "access-recording: DELEGATECALL runs library code in the caller's storage context" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();
    evm.setGasLimit(10_000_000);

    // Library L at 0x00..4C: SSTORE slot 5 = 77, STOP.
    const lib_code = [_]u8{ op(.PUSH1), 77, op(.PUSH1), 5, op(.SSTORE), op(.STOP) };
    var L: [20]u8 = [_]u8{0} ** 20;
    L[19] = 0x4C;
    try evm.accounts.put(L, .{
        .balance = BigInt.init(0),
        .nonce = 0,
        .code = try allocator.dupe(u8, &lib_code),
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    });

    const A: [20]u8 = [_]u8{0xA0} ** 20;
    evm.current_address = A;

    // A DELEGATECALLs L. Pop order: gas, addr, argsOffset, argsSize, retOffset,
    // retSize -> push reversed.
    const caller_code = [_]u8{
        op(.PUSH1), 0,    // retSize
        op(.PUSH1), 0,    // retOffset
        op(.PUSH1), 0,    // argsSize
        op(.PUSH1), 0,    // argsOffset
        op(.PUSH1), 0x4C, // addr = L
        op(.GAS),         // gas: forward (almost) all
        op(.DELEGATECALL),
        op(.STOP),
    };
    evm.code = &caller_code;
    evm.pc = 0;
    try evm.execute();

    try testing.expect((evm.stack.pop() orelse return error.TestUnexpectedResult).eq(BigInt.init(1)));
    // DELEGATECALL writes to the CALLER's (A's) storage, not the library's.
    try testing.expect((evm.accounts.getPtr(A).?).storage.get(BigInt.init(5)).?.eq(BigInt.init(77)));
    try testing.expect((evm.accounts.getPtr(L).?).storage.get(BigInt.init(5)) == null);
}

test "access-recording: CALL to the SHA-256 precompile returns the hash" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();
    evm.setGasLimit(10_000_000);

    // CALL with empty calldata to 0x00..02 (SHA-256). Pop order: gas, addr,
    // value, argsOffset, argsSize, retOffset, retSize -> push reversed.
    const bytecode = [_]u8{
        op(.PUSH1), 0x00, // retSize
        op(.PUSH1), 0x00, // retOffset
        op(.PUSH1), 0x00, // argsSize (empty input)
        op(.PUSH1), 0x00, // argsOffset
        op(.PUSH1), 0x00, // value
        op(.PUSH1), 0x02, // addr = SHA-256 precompile
        op(.PUSH1), 0x00, // gas
        op(.CALL),
        op(.STOP),
    };
    evm.code = &bytecode;
    evm.pc = 0;
    try evm.execute();

    // CALL pushed success.
    try testing.expect((evm.stack.pop() orelse return error.TestUnexpectedResult).eq(BigInt.init(1)));
    // return_data is SHA-256("").
    const sha_empty = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    try testing.expectEqualSlices(u8, &sha_empty, evm.return_data);
}

test "access-recording: BALANCE records a balance read of the queried address" {
    const allocator = testing.allocator;
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    var recorder = AccessRecorder.init(allocator);
    defer recorder.deinit();
    evm.access = &recorder;
    evm.setGasLimit(10_000_000);

    // Query the balance of address 0x00..01.
    const bytecode = [_]u8{
        op(.PUSH1), 0x01,
        op(.BALANCE),
        op(.STOP),
    };
    evm.code = &bytecode;
    evm.pc = 0;
    try evm.execute();

    // The stack word 0x01 decodes (big-endian, low 20 bytes) to address
    // 0x00..01, so exactly that account's balance was read.
    var queried: [20]u8 = [_]u8{0} ** 20;
    queried[19] = 0x01;
    try testing.expect(recorder.readKey(StateKey.balanceOf(queried)));

    var balance_reads: usize = 0;
    for (recorder.read_set.entries.items) |rd| {
        if (rd.key.tag == .balance) balance_reads += 1;
    }
    try testing.expectEqual(@as(usize, 1), balance_reads);
}
