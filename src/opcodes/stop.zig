// File: src/opcodes/stop.zig

const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.STOP),
        .impl = OpcodeImpl{
            .execute = execute,
        },
    };
}

fn execute(ev: *EVM) !void {
    // STOP opcode doesn't do anything except halt execution
    // The execution loop in EVM.execute() will break when it encounters STOP
    _ = ev; // Suppress unused parameter warning
}