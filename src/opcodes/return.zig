// File: src/opcodes/return.zig
// RETURN (0xf3): Halt execution and return output data
// Stack: offset, size -> (none)
// Copies 'size' bytes from memory at 'offset' to return data and halts execution

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;
const BigInt = @import("../main.zig").BigInt;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.RETURN),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(evm: *EVM) !void {
    const offset_big = evm.stack.pop() orelse return error.StackUnderflow;
    const size_big = evm.stack.pop() orelse return error.StackUnderflow;

    // Convert to usize with bounds checking
    if (!size_big.fitsInU64()) {
        evm.stop_execution = true;
        return;
    }
    const size: usize = @intCast(size_big.data[0]);

    if (!offset_big.fitsInU64()) {
        evm.stop_execution = true;
        return;
    }
    const offset: usize = @intCast(offset_big.data[0]);

    // Allocate return data buffer
    if (size > 0) {
        var return_buffer = try evm.allocator.alloc(u8, size);

        // Copy from memory to return buffer
        for (0..size) |i| {
            return_buffer[i] = evm.memory.loadByte(offset + i);
        }

        // Store as return data
        evm.return_data = return_buffer;
    }

    // Stop execution (successful return)
    evm.stop_execution = true;
    evm.execution_reverted = false;
}
