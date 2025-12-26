// File: src/opcodes/log0.zig
// LOG0 (0xa0): Emit log with no topics
// Stack: offset, size ->
// Gas: 375 + 8*size + memory expansion

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const Log = @import("../main.zig").Log;

const LOG_BASE_GAS: u64 = 375;
const LOG_DATA_GAS: u64 = 8; // Per byte of data
const LOG_TOPIC_GAS: u64 = 375; // Per topic

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.LOG0),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    // Check if in static context
    if (evm.call_stack.isStatic()) {
        return error.StaticCallViolation;
    }

    // Pop stack arguments
    const offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const size_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Convert to usize
    if (!offset_big.fitsInU64() or !size_big.fitsInU64()) {
        return error.OutOfGas;
    }
    const offset: usize = @intCast(offset_big.data[0]);
    const size: usize = @intCast(size_big.data[0]);

    // Calculate gas cost
    const data_gas: u64 = @as(u64, size) * LOG_DATA_GAS;
    try evm.consumeGas(LOG_BASE_GAS + data_gas);

    // Ensure memory capacity
    try evm.memory.ensureCapacity(evm.allocator, offset + size);

    // Read data from memory
    var data = try evm.allocator.alloc(u8, size);
    for (0..size) |i| {
        data[i] = evm.memory.loadByte(offset + i);
    }

    // Create log entry
    var log = Log.init(evm.allocator, evm.current_address);
    try log.setData(evm.allocator, data);
    evm.allocator.free(data);

    // Add to logs
    try evm.logs.append(log);
}
