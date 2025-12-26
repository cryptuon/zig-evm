//! Ethereum Test Compliance Runner
//!
//! This module provides infrastructure for running Ethereum test vectors
//! (from ethereum/tests repository) against our EVM implementation.
//!
//! Supports:
//! - VMTests: Direct bytecode execution tests
//! - GeneralStateTests: Full transaction execution tests

const std = @import("std");
const Allocator = std.mem.Allocator;
const EVM = @import("../src/main.zig").EVM;
const BigInt = @import("../src/main.zig").BigInt;
const Account = @import("../src/main.zig").Account;

/// Test result status
pub const TestStatus = enum {
    passed,
    failed,
    skipped,
    error_parsing,
    error_execution,
};

/// Result of a single test case
pub const TestResult = struct {
    name: []const u8,
    status: TestStatus,
    expected_gas: ?u64,
    actual_gas: ?u64,
    expected_output: ?[]const u8,
    actual_output: ?[]const u8,
    error_message: ?[]const u8,
    execution_time_ns: u64,
};

/// Statistics for a test suite run
pub const TestStats = struct {
    total: u32,
    passed: u32,
    failed: u32,
    skipped: u32,
    errors: u32,
    total_time_ns: u64,

    pub fn init() TestStats {
        return .{
            .total = 0,
            .passed = 0,
            .failed = 0,
            .skipped = 0,
            .errors = 0,
            .total_time_ns = 0,
        };
    }

    pub fn record(self: *TestStats, result: TestResult) void {
        self.total += 1;
        self.total_time_ns += result.execution_time_ns;
        switch (result.status) {
            .passed => self.passed += 1,
            .failed => self.failed += 1,
            .skipped => self.skipped += 1,
            .error_parsing, .error_execution => self.errors += 1,
        }
    }

    pub fn passRate(self: TestStats) f64 {
        if (self.total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.passed)) / @as(f64, @floatFromInt(self.total)) * 100.0;
    }
};

/// Environment block for test execution
pub const TestEnv = struct {
    coinbase: [20]u8,
    difficulty: BigInt,
    gas_limit: u64,
    number: u64,
    timestamp: u64,
    base_fee: ?BigInt,
};

/// Execution context for VM tests
pub const TestExec = struct {
    address: [20]u8,
    caller: [20]u8,
    origin: [20]u8,
    code: []const u8,
    data: []const u8,
    gas: u64,
    gas_price: BigInt,
    value: BigInt,
};

/// Account state for pre/post conditions
pub const TestAccountState = struct {
    balance: BigInt,
    nonce: u64,
    code: []const u8,
    storage: std.AutoHashMap(BigInt, BigInt),

    pub fn deinit(self: *TestAccountState) void {
        self.storage.deinit();
    }
};

/// A single VM test case
pub const VMTest = struct {
    name: []const u8,
    env: TestEnv,
    exec: TestExec,
    pre: std.AutoHashMap([20]u8, TestAccountState),
    post: ?std.AutoHashMap([20]u8, TestAccountState),
    expected_output: ?[]const u8,
    expected_gas: ?u64,
    expected_logs_hash: ?[32]u8,

    pub fn deinit(self: *VMTest, allocator: Allocator) void {
        _ = allocator;
        var pre_iter = self.pre.iterator();
        while (pre_iter.next()) |entry| {
            var state = entry.value_ptr.*;
            state.deinit();
        }
        self.pre.deinit();

        if (self.post) |*post| {
            var post_iter = post.iterator();
            while (post_iter.next()) |entry| {
                var state = entry.value_ptr.*;
                state.deinit();
            }
            post.deinit();
        }
    }
};

/// Ethereum Test Compliance Runner
pub const ComplianceRunner = struct {
    allocator: Allocator,
    results: std.ArrayList(TestResult),
    stats: TestStats,
    verbose: bool,

    pub fn init(allocator: Allocator) ComplianceRunner {
        return .{
            .allocator = allocator,
            .results = std.ArrayList(TestResult).init(allocator),
            .stats = TestStats.init(),
            .verbose = false,
        };
    }

    pub fn deinit(self: *ComplianceRunner) void {
        self.results.deinit();
    }

    /// Run a single VM test case
    pub fn runVMTest(self: *ComplianceRunner, test_case: *VMTest) !TestResult {
        const start_time = std.time.nanoTimestamp();

        // Create EVM instance
        var evm = try EVM.init(self.allocator);
        defer evm.deinit();

        // Set up environment
        evm.coinbase = test_case.env.coinbase;
        evm.block_number = test_case.env.number;
        evm.block_timestamp = test_case.env.timestamp;
        evm.setGasLimit(test_case.exec.gas);

        // Set execution context
        evm.current_address = test_case.exec.address;
        evm.caller_address = test_case.exec.caller;
        evm.origin_address = test_case.exec.origin;
        evm.call_value = test_case.exec.value;
        evm.calldata = test_case.exec.data;

        // Set up pre-state accounts
        var pre_iter = test_case.pre.iterator();
        while (pre_iter.next()) |entry| {
            const addr = entry.key_ptr.*;
            const state = entry.value_ptr.*;

            var account = Account{
                .balance = state.balance,
                .nonce = state.nonce,
                .code = state.code,
                .storage = std.AutoHashMap(BigInt, BigInt).init(self.allocator),
            };

            // Copy storage
            var storage_iter = state.storage.iterator();
            while (storage_iter.next()) |storage_entry| {
                try account.storage.put(storage_entry.key_ptr.*, storage_entry.value_ptr.*);
            }

            try evm.accounts.put(addr, account);
        }

        // Set bytecode
        evm.code = test_case.exec.code;

        // Execute
        const exec_result = evm.execute();

        const end_time = std.time.nanoTimestamp();
        const execution_time = @as(u64, @intCast(end_time - start_time));

        // Compare results
        var status: TestStatus = .passed;
        var error_message: ?[]const u8 = null;

        if (exec_result) |_| {
            // Execution succeeded - check expected results
            if (test_case.expected_gas) |expected| {
                const actual = evm.gas_limit - evm.gas;
                if (actual != expected) {
                    status = .failed;
                    error_message = "Gas mismatch";
                }
            }

            if (test_case.expected_output) |expected| {
                if (!std.mem.eql(u8, evm.return_data, expected)) {
                    status = .failed;
                    error_message = "Output mismatch";
                }
            }

            // Compare post-state if provided
            if (test_case.post) |post| {
                var post_iter = post.iterator();
                while (post_iter.next()) |entry| {
                    const addr = entry.key_ptr.*;
                    const expected_state = entry.value_ptr.*;

                    if (evm.accounts.get(addr)) |actual_account| {
                        // Compare balance
                        if (!actual_account.balance.eql(expected_state.balance)) {
                            status = .failed;
                            error_message = "Balance mismatch";
                            break;
                        }

                        // Compare nonce
                        if (actual_account.nonce != expected_state.nonce) {
                            status = .failed;
                            error_message = "Nonce mismatch";
                            break;
                        }

                        // Compare storage
                        var storage_iter = expected_state.storage.iterator();
                        while (storage_iter.next()) |storage_entry| {
                            const key = storage_entry.key_ptr.*;
                            const expected_val = storage_entry.value_ptr.*;

                            if (actual_account.storage.get(key)) |actual_val| {
                                if (!actual_val.eql(expected_val)) {
                                    status = .failed;
                                    error_message = "Storage value mismatch";
                                    break;
                                }
                            } else {
                                if (!expected_val.isZero()) {
                                    status = .failed;
                                    error_message = "Missing storage key";
                                    break;
                                }
                            }
                        }
                    } else {
                        status = .failed;
                        error_message = "Missing account in post-state";
                        break;
                    }
                }
            }
        } else |err| {
            // Execution failed
            if (test_case.post == null and test_case.expected_output == null) {
                // Expected failure
                status = .passed;
            } else {
                status = .error_execution;
                error_message = @errorName(err);
            }
        }

        const result = TestResult{
            .name = test_case.name,
            .status = status,
            .expected_gas = test_case.expected_gas,
            .actual_gas = if (exec_result) |_| evm.gas_limit - evm.gas else null,
            .expected_output = test_case.expected_output,
            .actual_output = if (exec_result) |_| if (evm.return_data.len > 0) evm.return_data else null else null,
            .error_message = error_message,
            .execution_time_ns = execution_time,
        };

        try self.results.append(result);
        self.stats.record(result);

        return result;
    }

    /// Parse hex string to bytes
    pub fn parseHex(allocator: Allocator, hex: []const u8) ![]u8 {
        var start: usize = 0;
        if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X')) {
            start = 2;
        }

        const hex_chars = hex[start..];
        if (hex_chars.len == 0) {
            return allocator.alloc(u8, 0);
        }

        const len = hex_chars.len / 2;
        var result = try allocator.alloc(u8, len);

        for (0..len) |i| {
            const high = hexCharToNibble(hex_chars[i * 2]);
            const low = hexCharToNibble(hex_chars[i * 2 + 1]);
            if (high == null or low == null) {
                allocator.free(result);
                return error.InvalidHexChar;
            }
            result[i] = (high.? << 4) | low.?;
        }

        return result;
    }

    fn hexCharToNibble(c: u8) ?u4 {
        return switch (c) {
            '0'...'9' => @truncate(c - '0'),
            'a'...'f' => @truncate(c - 'a' + 10),
            'A'...'F' => @truncate(c - 'A' + 10),
            else => null,
        };
    }

    /// Parse hex string to BigInt
    pub fn parseHexBigInt(hex: []const u8) !BigInt {
        var start: usize = 0;
        if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X')) {
            start = 2;
        }

        const hex_chars = hex[start..];
        if (hex_chars.len == 0) {
            return BigInt.zero();
        }

        var result = BigInt.zero();
        for (hex_chars) |c| {
            const nibble = hexCharToNibble(c) orelse return error.InvalidHexChar;

            // Multiply by 16
            result = result.shl(4);
            // Add nibble
            result = result.add(BigInt.init(nibble));
        }

        return result;
    }

    /// Parse hex string to address (20 bytes)
    pub fn parseAddress(hex: []const u8) ![20]u8 {
        var start: usize = 0;
        if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X')) {
            start = 2;
        }

        const hex_chars = hex[start..];
        if (hex_chars.len != 40) {
            return error.InvalidAddressLength;
        }

        var result: [20]u8 = undefined;
        for (0..20) |i| {
            const high = hexCharToNibble(hex_chars[i * 2]) orelse return error.InvalidHexChar;
            const low = hexCharToNibble(hex_chars[i * 2 + 1]) orelse return error.InvalidHexChar;
            result[i] = (@as(u8, high) << 4) | low;
        }

        return result;
    }

    /// Parse hex string to u64
    pub fn parseHexU64(hex: []const u8) !u64 {
        var start: usize = 0;
        if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X')) {
            start = 2;
        }

        const hex_chars = hex[start..];
        if (hex_chars.len == 0) {
            return 0;
        }

        var result: u64 = 0;
        for (hex_chars) |c| {
            const nibble = hexCharToNibble(c) orelse return error.InvalidHexChar;
            result = (result << 4) | nibble;
        }

        return result;
    }

    /// Print test statistics
    pub fn printStats(self: *ComplianceRunner, writer: anytype) !void {
        try writer.print("\n=== Ethereum Compliance Test Results ===\n", .{});
        try writer.print("Total:   {d}\n", .{self.stats.total});
        try writer.print("Passed:  {d} ({d:.1}%)\n", .{ self.stats.passed, self.stats.passRate() });
        try writer.print("Failed:  {d}\n", .{self.stats.failed});
        try writer.print("Skipped: {d}\n", .{self.stats.skipped});
        try writer.print("Errors:  {d}\n", .{self.stats.errors});
        try writer.print("Time:    {d}ms\n", .{self.stats.total_time_ns / 1_000_000});
    }

    /// Print detailed results
    pub fn printResults(self: *ComplianceRunner, writer: anytype) !void {
        for (self.results.items) |result| {
            const status_str = switch (result.status) {
                .passed => "PASS",
                .failed => "FAIL",
                .skipped => "SKIP",
                .error_parsing => "ERR_PARSE",
                .error_execution => "ERR_EXEC",
            };

            try writer.print("[{s}] {s}", .{ status_str, result.name });

            if (result.error_message) |msg| {
                try writer.print(" - {s}", .{msg});
            }

            if (result.expected_gas != null and result.actual_gas != null) {
                try writer.print(" (gas: expected={d}, actual={d})", .{
                    result.expected_gas.?,
                    result.actual_gas.?,
                });
            }

            try writer.print("\n", .{});
        }
    }
};

// ============================================================
// Built-in VM Test Vectors
// ============================================================

/// Create a simple ADD test
pub fn createAddTest(allocator: Allocator) !VMTest {
    var pre = std.AutoHashMap([20]u8, TestAccountState).init(allocator);

    const test_address = [_]u8{0xaa} ** 20;

    var storage = std.AutoHashMap(BigInt, BigInt).init(allocator);
    try pre.put(test_address, TestAccountState{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = storage,
    });

    // Bytecode: PUSH1 3, PUSH1 5, ADD, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
    const code = [_]u8{
        0x60, 0x03, // PUSH1 3
        0x60, 0x05, // PUSH1 5
        0x01, // ADD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xf3, // RETURN
    };

    // Expected output: 0x0000...0008 (8 as 32-byte value)
    var expected_output = try allocator.alloc(u8, 32);
    @memset(expected_output, 0);
    expected_output[31] = 8;

    return VMTest{
        .name = "add_basic",
        .env = TestEnv{
            .coinbase = [_]u8{0} ** 20,
            .difficulty = BigInt.init(0),
            .gas_limit = 100000,
            .number = 0,
            .timestamp = 0,
            .base_fee = null,
        },
        .exec = TestExec{
            .address = test_address,
            .caller = [_]u8{0xbb} ** 20,
            .origin = [_]u8{0xbb} ** 20,
            .code = &code,
            .data = &[_]u8{},
            .gas = 100000,
            .gas_price = BigInt.init(1),
            .value = BigInt.zero(),
        },
        .pre = pre,
        .post = null,
        .expected_output = expected_output,
        .expected_gas = null, // Will compare output only
        .expected_logs_hash = null,
    };
}

/// Create a simple MUL test
pub fn createMulTest(allocator: Allocator) !VMTest {
    var pre = std.AutoHashMap([20]u8, TestAccountState).init(allocator);

    const test_address = [_]u8{0xaa} ** 20;

    var storage = std.AutoHashMap(BigInt, BigInt).init(allocator);
    try pre.put(test_address, TestAccountState{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = storage,
    });

    // Bytecode: PUSH1 7, PUSH1 8, MUL (7*8=56)
    const code = [_]u8{
        0x60, 0x07, // PUSH1 7
        0x60, 0x08, // PUSH1 8
        0x02, // MUL
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xf3, // RETURN
    };

    var expected_output = try allocator.alloc(u8, 32);
    @memset(expected_output, 0);
    expected_output[31] = 56; // 7 * 8 = 56

    return VMTest{
        .name = "mul_basic",
        .env = TestEnv{
            .coinbase = [_]u8{0} ** 20,
            .difficulty = BigInt.init(0),
            .gas_limit = 100000,
            .number = 0,
            .timestamp = 0,
            .base_fee = null,
        },
        .exec = TestExec{
            .address = test_address,
            .caller = [_]u8{0xbb} ** 20,
            .origin = [_]u8{0xbb} ** 20,
            .code = &code,
            .data = &[_]u8{},
            .gas = 100000,
            .gas_price = BigInt.init(1),
            .value = BigInt.zero(),
        },
        .pre = pre,
        .post = null,
        .expected_output = expected_output,
        .expected_gas = null,
        .expected_logs_hash = null,
    };
}

/// Create a SSTORE/SLOAD test
pub fn createStorageTest(allocator: Allocator) !VMTest {
    var pre = std.AutoHashMap([20]u8, TestAccountState).init(allocator);

    const test_address = [_]u8{0xaa} ** 20;

    var storage = std.AutoHashMap(BigInt, BigInt).init(allocator);
    try pre.put(test_address, TestAccountState{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = storage,
    });

    // Bytecode: PUSH1 42, PUSH1 0, SSTORE, PUSH1 0, SLOAD, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
    const code = [_]u8{
        0x60, 0x2a, // PUSH1 42
        0x60, 0x00, // PUSH1 0
        0x55, // SSTORE
        0x60, 0x00, // PUSH1 0
        0x54, // SLOAD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xf3, // RETURN
    };

    var expected_output = try allocator.alloc(u8, 32);
    @memset(expected_output, 0);
    expected_output[31] = 42;

    // Expected post-state
    var post = std.AutoHashMap([20]u8, TestAccountState).init(allocator);
    var post_storage = std.AutoHashMap(BigInt, BigInt).init(allocator);
    try post_storage.put(BigInt.zero(), BigInt.init(42));
    try post.put(test_address, TestAccountState{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = post_storage,
    });

    return VMTest{
        .name = "storage_basic",
        .env = TestEnv{
            .coinbase = [_]u8{0} ** 20,
            .difficulty = BigInt.init(0),
            .gas_limit = 100000,
            .number = 0,
            .timestamp = 0,
            .base_fee = null,
        },
        .exec = TestExec{
            .address = test_address,
            .caller = [_]u8{0xbb} ** 20,
            .origin = [_]u8{0xbb} ** 20,
            .code = &code,
            .data = &[_]u8{},
            .gas = 100000,
            .gas_price = BigInt.init(1),
            .value = BigInt.zero(),
        },
        .pre = pre,
        .post = post,
        .expected_output = expected_output,
        .expected_gas = null,
        .expected_logs_hash = null,
    };
}

/// Create a CALLDATALOAD test
pub fn createCalldataTest(allocator: Allocator) !VMTest {
    var pre = std.AutoHashMap([20]u8, TestAccountState).init(allocator);

    const test_address = [_]u8{0xaa} ** 20;

    var storage = std.AutoHashMap(BigInt, BigInt).init(allocator);
    try pre.put(test_address, TestAccountState{
        .balance = BigInt.init(1000000),
        .nonce = 0,
        .code = &[_]u8{},
        .storage = storage,
    });

    // Bytecode: PUSH1 0, CALLDATALOAD, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
    const code = [_]u8{
        0x60, 0x00, // PUSH1 0
        0x35, // CALLDATALOAD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xf3, // RETURN
    };

    // Calldata: 0x1234567890... (32 bytes)
    var calldata = try allocator.alloc(u8, 32);
    for (0..32) |i| {
        calldata[i] = @truncate(i + 0x10);
    }

    // Expected output: same as calldata (padded to 32 bytes)
    var expected_output = try allocator.alloc(u8, 32);
    @memcpy(expected_output, calldata);

    return VMTest{
        .name = "calldata_basic",
        .env = TestEnv{
            .coinbase = [_]u8{0} ** 20,
            .difficulty = BigInt.init(0),
            .gas_limit = 100000,
            .number = 0,
            .timestamp = 0,
            .base_fee = null,
        },
        .exec = TestExec{
            .address = test_address,
            .caller = [_]u8{0xbb} ** 20,
            .origin = [_]u8{0xbb} ** 20,
            .code = &code,
            .data = calldata,
            .gas = 100000,
            .gas_price = BigInt.init(1),
            .value = BigInt.zero(),
        },
        .pre = pre,
        .post = null,
        .expected_output = expected_output,
        .expected_gas = null,
        .expected_logs_hash = null,
    };
}

// ============================================================
// Tests
// ============================================================

test "compliance runner basic" {
    const allocator = std.testing.allocator;
    var runner = ComplianceRunner.init(allocator);
    defer runner.deinit();

    try std.testing.expect(runner.stats.total == 0);
    try std.testing.expect(runner.stats.passed == 0);
}

test "parse hex to bytes" {
    const allocator = std.testing.allocator;

    const result1 = try ComplianceRunner.parseHex(allocator, "0x1234");
    defer allocator.free(result1);
    try std.testing.expect(result1.len == 2);
    try std.testing.expect(result1[0] == 0x12);
    try std.testing.expect(result1[1] == 0x34);

    const result2 = try ComplianceRunner.parseHex(allocator, "abcdef");
    defer allocator.free(result2);
    try std.testing.expect(result2.len == 3);
    try std.testing.expect(result2[0] == 0xab);
    try std.testing.expect(result2[1] == 0xcd);
    try std.testing.expect(result2[2] == 0xef);
}

test "parse hex to BigInt" {
    const result1 = try ComplianceRunner.parseHexBigInt("0xff");
    try std.testing.expect(result1.data[0] == 255);

    const result2 = try ComplianceRunner.parseHexBigInt("0x100");
    try std.testing.expect(result2.data[0] == 256);

    const result3 = try ComplianceRunner.parseHexBigInt("0x");
    try std.testing.expect(result3.isZero());
}

test "parse address" {
    const addr = try ComplianceRunner.parseAddress("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    for (addr) |byte| {
        try std.testing.expect(byte == 0xaa);
    }
}

test "parse hex u64" {
    const val1 = try ComplianceRunner.parseHexU64("0x64");
    try std.testing.expect(val1 == 100);

    const val2 = try ComplianceRunner.parseHexU64("0xffffffff");
    try std.testing.expect(val2 == 0xffffffff);
}
