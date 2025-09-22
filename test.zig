const std = @import("std");

// Import all test files
comptime {
    _ = @import("tests/test_bigint.zig");
    _ = @import("tests/test_stack.zig");
    _ = @import("tests/test_opcodes.zig");
    _ = @import("tests/test_arithmetic.zig");
    _ = @import("tests/test_comparison.zig");
    _ = @import("tests/test_bitwise.zig");
    _ = @import("tests/test_stack_ops.zig");
    _ = @import("tests/test_extended_opcodes.zig");
    _ = @import("tests/test_memory.zig");
    _ = @import("tests/test_flow_control.zig");
    _ = @import("tests/test_advanced_opcodes.zig");
    _ = @import("tests/test_advanced_arithmetic.zig");
    _ = @import("tests/test_shift_ops.zig");
    _ = @import("tests/test_push_ops.zig");
    _ = @import("tests/test_dup_ops.zig");
    _ = @import("tests/test_swap_ops.zig");
    _ = @import("tests/test_env_ops.zig");
    _ = @import("tests/test_gas_tracking.zig");
    _ = @import("tests/test_parallel_execution.zig");
}