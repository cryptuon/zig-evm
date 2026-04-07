// File: src/call_frame.zig
// Call frame management for nested EVM calls
// Supports CALL, CALLCODE, DELEGATECALL, STATICCALL, CREATE, CREATE2

const std = @import("std");
const Allocator = std.mem.Allocator;
const BigInt = @import("bigint.zig").BigInt;
const Memory = @import("memory.zig").Memory;
const Stack = @import("stack.zig").Stack;

/// Represents the type of call being made
pub const CallType = enum {
    CALL,
    CALLCODE,
    DELEGATECALL,
    STATICCALL,
    CREATE,
    CREATE2,
};

/// A single call frame representing an execution context
pub const CallFrame = struct {
    // Addresses
    caller: [20]u8, // msg.sender
    address: [20]u8, // Address of the contract being executed
    code_address: [20]u8, // Address where code is loaded from (differs for DELEGATECALL)
    origin: [20]u8, // tx.origin (constant across all frames)

    // Value
    value: BigInt, // msg.value

    // Input/Output
    calldata: []const u8, // Input data
    return_offset: usize, // Where to write return data in parent memory
    return_size: usize, // How much return data to copy

    // Gas
    gas: u64, // Gas allocated to this frame
    gas_used: u64, // Gas consumed so far

    // Code
    code: []const u8, // Bytecode being executed
    pc: usize, // Program counter

    // State
    is_static: bool, // STATICCALL context - no state modifications allowed
    is_delegate: bool, // DELEGATECALL context - use caller's storage
    is_create: bool, // CREATE/CREATE2 context
    depth: u16, // Call depth (max 1024)

    // Saved context for returning
    saved_memory: ?[]u8, // Parent's memory state (optional, for rollback)

    pub fn init(
        caller: [20]u8,
        address: [20]u8,
        code_address: [20]u8,
        origin: [20]u8,
        value: BigInt,
        calldata: []const u8,
        gas: u64,
        code: []const u8,
        is_static: bool,
        is_delegate: bool,
        is_create: bool,
        depth: u16,
    ) CallFrame {
        return CallFrame{
            .caller = caller,
            .address = address,
            .code_address = code_address,
            .origin = origin,
            .value = value,
            .calldata = calldata,
            .return_offset = 0,
            .return_size = 0,
            .gas = gas,
            .gas_used = 0,
            .code = code,
            .pc = 0,
            .is_static = is_static,
            .is_delegate = is_delegate,
            .is_create = is_create,
            .depth = depth,
            .saved_memory = null,
        };
    }

    pub fn setReturnTarget(self: *CallFrame, offset: usize, size: usize) void {
        self.return_offset = offset;
        self.return_size = size;
    }

    pub fn consumeGas(self: *CallFrame, amount: u64) !void {
        if (self.gas < amount) {
            return error.OutOfGas;
        }
        self.gas -= amount;
        self.gas_used += amount;
    }

    pub fn remainingGas(self: *const CallFrame) u64 {
        return self.gas;
    }
};

/// Call stack managing nested call frames
pub const CallStack = struct {
    frames: std.array_list.Managed(CallFrame),
    max_depth: u16,
    allocator: Allocator,

    pub const MAX_CALL_DEPTH: u16 = 1024;

    pub fn init(allocator: Allocator) CallStack {
        return CallStack{
            .frames = std.array_list.Managed(CallFrame).init(allocator),
            .max_depth = MAX_CALL_DEPTH,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CallStack) void {
        self.frames.deinit();
    }

    pub fn push(self: *CallStack, frame: CallFrame) !void {
        if (self.frames.items.len >= self.max_depth) {
            return error.CallDepthExceeded;
        }
        try self.frames.append(frame);
    }

    pub fn pop(self: *CallStack) ?CallFrame {
        return self.frames.popOrNull();
    }

    pub fn current(self: *CallStack) ?*CallFrame {
        if (self.frames.items.len == 0) return null;
        return &self.frames.items[self.frames.items.len - 1];
    }

    pub fn depth(self: *const CallStack) u16 {
        return @intCast(self.frames.items.len);
    }

    pub fn isEmpty(self: *const CallStack) bool {
        return self.frames.items.len == 0;
    }

    /// Check if current execution context is static (read-only)
    pub fn isStatic(self: *const CallStack) bool {
        if (self.frames.items.len == 0) return false;
        // Check if any frame in the stack is static
        for (self.frames.items) |frame| {
            if (frame.is_static) return true;
        }
        return false;
    }
};

/// Result of a call execution
pub const CallResult = struct {
    success: bool,
    return_data: []u8,
    gas_left: u64,
    gas_refund: u64,

    pub fn init(success: bool, return_data: []u8, gas_left: u64, gas_refund: u64) CallResult {
        return CallResult{
            .success = success,
            .return_data = return_data,
            .gas_left = gas_left,
            .gas_refund = gas_refund,
        };
    }
};

/// Calculate the stipend for a call with value transfer
/// Per EIP-2929: 2300 gas stipend for calls with value
pub fn callStipend(value: BigInt) u64 {
    if (value.isZero()) {
        return 0;
    }
    return 2300;
}

/// Calculate gas to pass to a sub-call
/// Per EIP-150: All but 1/64th of gas is available
pub fn maxCallGas(available_gas: u64) u64 {
    return available_gas - (available_gas / 64);
}

/// Calculate actual gas for a call
/// Takes minimum of requested gas and max available
pub fn calculateCallGas(requested: u64, available: u64, value: BigInt) u64 {
    const max_gas = maxCallGas(available);
    const gas = @min(requested, max_gas);
    return gas + callStipend(value);
}

// Tests
test "CallFrame basic" {
    const caller = [_]u8{0x11} ** 20;
    const address = [_]u8{0x22} ** 20;
    const origin = [_]u8{0x33} ** 20;

    var frame = CallFrame.init(
        caller,
        address,
        address,
        origin,
        BigInt.init(1000),
        "",
        100000,
        "",
        false,
        false,
        false,
        0,
    );

    try frame.consumeGas(1000);
    try std.testing.expectEqual(@as(u64, 99000), frame.remainingGas());
    try std.testing.expectEqual(@as(u64, 1000), frame.gas_used);
}

test "CallStack depth" {
    const allocator = std.testing.allocator;
    var stack = CallStack.init(allocator);
    defer stack.deinit();

    const frame = CallFrame.init(
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        BigInt.zero(),
        "",
        100000,
        "",
        false,
        false,
        false,
        0,
    );

    try stack.push(frame);
    try std.testing.expectEqual(@as(u16, 1), stack.depth());

    _ = stack.pop();
    try std.testing.expectEqual(@as(u16, 0), stack.depth());
}

test "static context propagation" {
    const allocator = std.testing.allocator;
    var stack = CallStack.init(allocator);
    defer stack.deinit();

    // First frame is static
    const static_frame = CallFrame.init(
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        BigInt.zero(),
        "",
        100000,
        "",
        true, // is_static
        false,
        false,
        0,
    );
    try stack.push(static_frame);

    // Nested frame is not explicitly static, but inherits from parent
    const nested_frame = CallFrame.init(
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        BigInt.zero(),
        "",
        50000,
        "",
        false, // not explicitly static
        false,
        false,
        1,
    );
    try stack.push(nested_frame);

    // Stack should report as static because parent is static
    try std.testing.expect(stack.isStatic());
}

test "call gas calculation" {
    // No value transfer
    const no_value_gas = calculateCallGas(50000, 100000, BigInt.zero());
    try std.testing.expect(no_value_gas <= 100000);

    // With value transfer (gets stipend)
    const with_value_gas = calculateCallGas(50000, 100000, BigInt.init(1));
    try std.testing.expectEqual(no_value_gas + 2300, with_value_gas);
}
