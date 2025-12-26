// File: src/opcodes/log4.zig
// LOG4 (0xa4): Emit log with 4 topics
// Stack: offset, size, topic1, topic2, topic3, topic4 ->

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;
const Log = @import("../main.zig").Log;

const LOG_BASE_GAS: u64 = 375;
const LOG_DATA_GAS: u64 = 8;
const LOG_TOPIC_GAS: u64 = 375;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.LOG4),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    if (evm.call_stack.isStatic()) {
        return error.StaticCallViolation;
    }

    const offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const size_big = evm.stack.pop() orelse return error.StackUnderflow;
    const topic1_big = evm.stack.pop() orelse return error.StackUnderflow;
    const topic2_big = evm.stack.pop() orelse return error.StackUnderflow;
    const topic3_big = evm.stack.pop() orelse return error.StackUnderflow;
    const topic4_big = evm.stack.pop() orelse return error.StackUnderflow;

    if (!offset_big.fitsInU64() or !size_big.fitsInU64()) {
        return error.OutOfGas;
    }
    const offset: usize = @intCast(offset_big.data[0]);
    const size: usize = @intCast(size_big.data[0]);

    const data_gas: u64 = @as(u64, size) * LOG_DATA_GAS;
    try evm.consumeGas(LOG_BASE_GAS + data_gas + LOG_TOPIC_GAS * 4);

    try evm.memory.ensureCapacity(evm.allocator, offset + size);

    var data = try evm.allocator.alloc(u8, size);
    for (0..size) |i| {
        data[i] = evm.memory.loadByte(offset + i);
    }

    var log = Log.init(evm.allocator, evm.current_address);
    try log.addTopic(topic1_big.toBytes());
    try log.addTopic(topic2_big.toBytes());
    try log.addTopic(topic3_big.toBytes());
    try log.addTopic(topic4_big.toBytes());
    try log.setData(evm.allocator, data);
    evm.allocator.free(data);

    try evm.logs.append(log);
}
