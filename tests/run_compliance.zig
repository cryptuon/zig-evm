//! Ethereum Compliance Test Runner
//!
//! Executable that runs Ethereum test vectors against the EVM implementation.
//! Can run built-in tests or load external test files.
//!
//! Usage:
//!   zig build compliance          # Run built-in compliance tests
//!   zig build compliance -- file.json  # Run tests from file

const std = @import("std");
const compliance = @import("eth_compliance.zig");
const loader = @import("eth_test_loader.zig");
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/main.zig").BigInt;
const Account = @import("../src/main.zig").Account;
const Opcode = @import("../src/main.zig").Opcode;

const ComplianceRunner = compliance.ComplianceRunner;
const VMTest = compliance.VMTest;
const TestResult = compliance.TestResult;
const TestStatus = compliance.TestStatus;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n", .{});
    try stdout.print("╔══════════════════════════════════════════════════════════╗\n", .{});
    try stdout.print("║       Zig EVM - Ethereum Compliance Test Suite           ║\n", .{});
    try stdout.print("╚══════════════════════════════════════════════════════════╝\n", .{});
    try stdout.print("\n", .{});

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var runner = ComplianceRunner.init(allocator);
    defer runner.deinit();
    runner.verbose = true;

    if (args.len > 1) {
        // Load tests from file
        const file_path = args[1];
        try stdout.print("Loading tests from: {s}\n\n", .{file_path});

        const tests = loader.loadVMTestsFromFile(allocator, file_path) catch |err| {
            try stdout.print("Error loading test file: {}\n", .{err});
            return;
        };
        defer {
            for (tests) |*t| {
                var test_case = t.*;
                test_case.deinit(allocator);
            }
            allocator.free(tests);
        }

        try stdout.print("Loaded {d} test(s)\n\n", .{tests.len});

        for (tests) |*test_case| {
            const result = try runner.runVMTest(test_case);
            try printTestResult(stdout, result);
        }
    } else {
        // Run built-in tests
        try stdout.print("Running built-in compliance tests...\n\n", .{});

        // Test Suite 1: Basic Arithmetic Operations
        try stdout.print("─── Suite 1: Arithmetic Operations ───\n", .{});
        try runArithmeticTests(allocator, &runner, stdout);

        // Test Suite 2: Stack Operations
        try stdout.print("\n─── Suite 2: Stack Operations ───\n", .{});
        try runStackTests(allocator, &runner, stdout);

        // Test Suite 3: Memory Operations
        try stdout.print("\n─── Suite 3: Memory Operations ───\n", .{});
        try runMemoryTests(allocator, &runner, stdout);

        // Test Suite 4: Comparison & Bitwise
        try stdout.print("\n─── Suite 4: Comparison & Bitwise ───\n", .{});
        try runComparisonTests(allocator, &runner, stdout);

        // Test Suite 5: Environmental Info
        try stdout.print("\n─── Suite 5: Environmental Info ───\n", .{});
        try runEnvironmentalTests(allocator, &runner, stdout);

        // Test Suite 6: Flow Control
        try stdout.print("\n─── Suite 6: Flow Control ───\n", .{});
        try runFlowControlTests(allocator, &runner, stdout);
    }

    // Print final statistics
    try stdout.print("\n", .{});
    try runner.printStats(stdout);

    // Exit with appropriate code
    if (runner.stats.failed > 0 or runner.stats.errors > 0) {
        std.process.exit(1);
    }
}

fn printTestResult(writer: anytype, result: TestResult) !void {
    const status_icon = switch (result.status) {
        .passed => "✓",
        .failed => "✗",
        .skipped => "○",
        .error_parsing => "!",
        .error_execution => "⚠",
    };

    const status_color = switch (result.status) {
        .passed => "\x1b[32m", // green
        .failed => "\x1b[31m", // red
        .skipped => "\x1b[33m", // yellow
        .error_parsing, .error_execution => "\x1b[35m", // magenta
    };

    try writer.print("{s}{s}\x1b[0m {s}", .{ status_color, status_icon, result.name });

    if (result.error_message) |msg| {
        try writer.print(" - {s}", .{msg});
    }

    if (result.expected_gas != null and result.actual_gas != null) {
        if (result.expected_gas.? != result.actual_gas.?) {
            try writer.print(" (gas: {d} vs {d})", .{
                result.expected_gas.?,
                result.actual_gas.?,
            });
        }
    }

    try writer.print(" [{d}us]\n", .{result.execution_time_ns / 1000});
}

// ============================================================
// Test Suites
// ============================================================

fn runArithmeticTests(allocator: std.mem.Allocator, runner: *ComplianceRunner, writer: anytype) !void {
    // Test ADD
    var add_result = try runSimpleTest(allocator, runner, "add_3_5", &[_]u8{
        0x60, 0x03, // PUSH1 3
        0x60, 0x05, // PUSH1 5
        0x01, // ADD
    }, 8);
    try printTestResult(writer, add_result);

    // Test SUB
    var sub_result = try runSimpleTest(allocator, runner, "sub_10_3", &[_]u8{
        0x60, 0x03, // PUSH1 3
        0x60, 0x0a, // PUSH1 10
        0x03, // SUB
    }, 7);
    try printTestResult(writer, sub_result);

    // Test MUL
    var mul_result = try runSimpleTest(allocator, runner, "mul_7_8", &[_]u8{
        0x60, 0x07, // PUSH1 7
        0x60, 0x08, // PUSH1 8
        0x02, // MUL
    }, 56);
    try printTestResult(writer, mul_result);

    // Test DIV
    var div_result = try runSimpleTest(allocator, runner, "div_100_5", &[_]u8{
        0x60, 0x05, // PUSH1 5
        0x60, 0x64, // PUSH1 100
        0x04, // DIV
    }, 20);
    try printTestResult(writer, div_result);

    // Test MOD
    var mod_result = try runSimpleTest(allocator, runner, "mod_17_5", &[_]u8{
        0x60, 0x05, // PUSH1 5
        0x60, 0x11, // PUSH1 17
        0x06, // MOD
    }, 2);
    try printTestResult(writer, mod_result);

    // Test EXP
    var exp_result = try runSimpleTest(allocator, runner, "exp_2_8", &[_]u8{
        0x60, 0x08, // PUSH1 8
        0x60, 0x02, // PUSH1 2
        0x0a, // EXP
    }, 256);
    try printTestResult(writer, exp_result);
}

fn runStackTests(allocator: std.mem.Allocator, runner: *ComplianceRunner, writer: anytype) !void {
    // Test DUP1
    var dup1_result = try runSimpleTest(allocator, runner, "dup1_42", &[_]u8{
        0x60, 0x2a, // PUSH1 42
        0x80, // DUP1
        0x01, // ADD (42 + 42)
    }, 84);
    try printTestResult(writer, dup1_result);

    // Test SWAP1
    var swap1_result = try runSimpleTest(allocator, runner, "swap1_order", &[_]u8{
        0x60, 0x01, // PUSH1 1
        0x60, 0x02, // PUSH1 2
        0x90, // SWAP1
        0x03, // SUB (1 - 2 = -1, but unsigned)
    }, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    try printTestResult(writer, swap1_result);

    // Test POP
    var pop_result = try runSimpleTest(allocator, runner, "pop_keep_second", &[_]u8{
        0x60, 0x05, // PUSH1 5
        0x60, 0x0a, // PUSH1 10
        0x50, // POP
    }, 5);
    try printTestResult(writer, pop_result);
}

fn runMemoryTests(allocator: std.mem.Allocator, runner: *ComplianceRunner, writer: anytype) !void {
    // Test MSTORE and MLOAD
    var mstore_result = try runSimpleTest(allocator, runner, "mstore_mload", &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x00, // PUSH1 0
        0x51, // MLOAD
    }, 0x42);
    try printTestResult(writer, mstore_result);

    // Test MSIZE
    var msize_result = try runSimpleTest(allocator, runner, "msize_after_mstore", &[_]u8{
        0x60, 0xff, // PUSH1 255
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x59, // MSIZE
    }, 32);
    try printTestResult(writer, msize_result);
}

fn runComparisonTests(allocator: std.mem.Allocator, runner: *ComplianceRunner, writer: anytype) !void {
    // Test LT (less than)
    var lt_true = try runSimpleTest(allocator, runner, "lt_3_5", &[_]u8{
        0x60, 0x05, // PUSH1 5
        0x60, 0x03, // PUSH1 3
        0x10, // LT
    }, 1);
    try printTestResult(writer, lt_true);

    var lt_false = try runSimpleTest(allocator, runner, "lt_5_3", &[_]u8{
        0x60, 0x03, // PUSH1 3
        0x60, 0x05, // PUSH1 5
        0x10, // LT
    }, 0);
    try printTestResult(writer, lt_false);

    // Test GT (greater than)
    var gt_result = try runSimpleTest(allocator, runner, "gt_5_3", &[_]u8{
        0x60, 0x03, // PUSH1 3
        0x60, 0x05, // PUSH1 5
        0x11, // GT
    }, 1);
    try printTestResult(writer, gt_result);

    // Test EQ (equal)
    var eq_result = try runSimpleTest(allocator, runner, "eq_5_5", &[_]u8{
        0x60, 0x05, // PUSH1 5
        0x60, 0x05, // PUSH1 5
        0x14, // EQ
    }, 1);
    try printTestResult(writer, eq_result);

    // Test ISZERO
    var iszero_true = try runSimpleTest(allocator, runner, "iszero_0", &[_]u8{
        0x60, 0x00, // PUSH1 0
        0x15, // ISZERO
    }, 1);
    try printTestResult(writer, iszero_true);

    var iszero_false = try runSimpleTest(allocator, runner, "iszero_5", &[_]u8{
        0x60, 0x05, // PUSH1 5
        0x15, // ISZERO
    }, 0);
    try printTestResult(writer, iszero_false);

    // Test AND
    var and_result = try runSimpleTest(allocator, runner, "and_0x0f_0xff", &[_]u8{
        0x60, 0xff, // PUSH1 0xff
        0x60, 0x0f, // PUSH1 0x0f
        0x16, // AND
    }, 0x0f);
    try printTestResult(writer, and_result);

    // Test OR
    var or_result = try runSimpleTest(allocator, runner, "or_0x0f_0xf0", &[_]u8{
        0x60, 0xf0, // PUSH1 0xf0
        0x60, 0x0f, // PUSH1 0x0f
        0x17, // OR
    }, 0xff);
    try printTestResult(writer, or_result);

    // Test XOR
    var xor_result = try runSimpleTest(allocator, runner, "xor_0xff_0x0f", &[_]u8{
        0x60, 0x0f, // PUSH1 0x0f
        0x60, 0xff, // PUSH1 0xff
        0x18, // XOR
    }, 0xf0);
    try printTestResult(writer, xor_result);

    // Test NOT
    var not_result = try runSimpleTest(allocator, runner, "not_0", &[_]u8{
        0x60, 0x00, // PUSH1 0
        0x19, // NOT
    }, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    try printTestResult(writer, not_result);
}

fn runEnvironmentalTests(allocator: std.mem.Allocator, runner: *ComplianceRunner, writer: anytype) !void {
    // Test GAS
    var gas_result = try runSimpleTestNoCheck(allocator, runner, "gas_opcode", &[_]u8{
        0x5a, // GAS
    });
    try printTestResult(writer, gas_result);

    // Test PC
    var pc_result = try runSimpleTest(allocator, runner, "pc_at_0", &[_]u8{
        0x58, // PC
    }, 0);
    try printTestResult(writer, pc_result);

    var pc_result2 = try runSimpleTest(allocator, runner, "pc_at_3", &[_]u8{
        0x60, 0x00, // PUSH1 0
        0x50, // POP
        0x58, // PC
    }, 3);
    try printTestResult(writer, pc_result2);
}

fn runFlowControlTests(allocator: std.mem.Allocator, runner: *ComplianceRunner, writer: anytype) !void {
    // Test JUMP
    var jump_result = try runSimpleTest(allocator, runner, "jump_forward", &[_]u8{
        0x60, 0x04, // PUSH1 4 (jump destination)
        0x56, // JUMP
        0x00, // STOP (skipped)
        0x5b, // JUMPDEST
        0x60, 0x42, // PUSH1 66
    }, 66);
    try printTestResult(writer, jump_result);

    // Test JUMPI (conditional jump - true)
    var jumpi_true = try runSimpleTest(allocator, runner, "jumpi_true", &[_]u8{
        0x60, 0x01, // PUSH1 1 (condition = true)
        0x60, 0x06, // PUSH1 6 (jump destination)
        0x57, // JUMPI
        0x00, // STOP (skipped)
        0x5b, // JUMPDEST
        0x60, 0x2a, // PUSH1 42
    }, 42);
    try printTestResult(writer, jumpi_true);

    // Test JUMPI (conditional jump - false)
    var jumpi_false = try runSimpleTest(allocator, runner, "jumpi_false", &[_]u8{
        0x60, 0x00, // PUSH1 0 (condition = false)
        0x60, 0x08, // PUSH1 8 (jump destination)
        0x57, // JUMPI
        0x60, 0x05, // PUSH1 5 (not skipped)
        0x00, // STOP
        0x5b, // JUMPDEST (not reached)
        0x60, 0x2a, // PUSH1 42 (not reached)
    }, 5);
    try printTestResult(writer, jumpi_false);
}

// ============================================================
// Helper Functions
// ============================================================

fn runSimpleTest(allocator: std.mem.Allocator, runner: *ComplianceRunner, name: []const u8, code: []const u8, expected_result: u256) !TestResult {
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // Set up a basic account
    const test_address = [_]u8{0xaa} ** 20;
    var account = Account{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    };
    try evm.accounts.put(test_address, account);

    evm.current_address = test_address;
    evm.setGasLimit(100000);
    evm.code = code;

    const start_time = std.time.nanoTimestamp();

    const exec_result = evm.execute();

    const end_time = std.time.nanoTimestamp();
    const execution_time = @as(u64, @intCast(end_time - start_time));

    if (exec_result) |_| {
        // Check stack result
        if (evm.stack.pop()) |result| {
            const result_val = result.toU256();
            const status: TestStatus = if (result_val == expected_result) .passed else .failed;
            const error_msg: ?[]const u8 = if (result_val != expected_result) "Result mismatch" else null;

            const test_result = TestResult{
                .name = name,
                .status = status,
                .expected_gas = null,
                .actual_gas = evm.gas_limit - evm.gas,
                .expected_output = null,
                .actual_output = null,
                .error_message = error_msg,
                .execution_time_ns = execution_time,
            };
            runner.stats.record(test_result);
            return test_result;
        } else {
            const test_result = TestResult{
                .name = name,
                .status = .failed,
                .expected_gas = null,
                .actual_gas = null,
                .expected_output = null,
                .actual_output = null,
                .error_message = "Empty stack",
                .execution_time_ns = execution_time,
            };
            runner.stats.record(test_result);
            return test_result;
        }
    } else |err| {
        const test_result = TestResult{
            .name = name,
            .status = .error_execution,
            .expected_gas = null,
            .actual_gas = null,
            .expected_output = null,
            .actual_output = null,
            .error_message = @errorName(err),
            .execution_time_ns = execution_time,
        };
        runner.stats.record(test_result);
        return test_result;
    }
}

fn runSimpleTestNoCheck(allocator: std.mem.Allocator, runner: *ComplianceRunner, name: []const u8, code: []const u8) !TestResult {
    var evm = try EVM.init(allocator);
    defer evm.deinit();

    const test_address = [_]u8{0xaa} ** 20;
    var account = Account{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
    };
    try evm.accounts.put(test_address, account);

    evm.current_address = test_address;
    evm.setGasLimit(100000);
    evm.code = code;

    const start_time = std.time.nanoTimestamp();
    const exec_result = evm.execute();
    const end_time = std.time.nanoTimestamp();
    const execution_time = @as(u64, @intCast(end_time - start_time));

    if (exec_result) |_| {
        const test_result = TestResult{
            .name = name,
            .status = .passed,
            .expected_gas = null,
            .actual_gas = evm.gas_limit - evm.gas,
            .expected_output = null,
            .actual_output = null,
            .error_message = null,
            .execution_time_ns = execution_time,
        };
        runner.stats.record(test_result);
        return test_result;
    } else |err| {
        const test_result = TestResult{
            .name = name,
            .status = .error_execution,
            .expected_gas = null,
            .actual_gas = null,
            .expected_output = null,
            .actual_output = null,
            .error_message = @errorName(err),
            .execution_time_ns = execution_time,
        };
        runner.stats.record(test_result);
        return test_result;
    }
}
