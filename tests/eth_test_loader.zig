//! Ethereum Test Vector JSON Loader
//!
//! Parses JSON test files from the ethereum/tests repository.
//! Supports VMTests and GeneralStateTests formats.

const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const compliance = @import("eth_compliance.zig");
const BigInt = @import("../src/main.zig").BigInt;

const VMTest = compliance.VMTest;
const TestEnv = compliance.TestEnv;
const TestExec = compliance.TestExec;
const TestAccountState = compliance.TestAccountState;
const ComplianceRunner = compliance.ComplianceRunner;

/// Error types for test loading
pub const LoadError = error{
    InvalidJson,
    MissingField,
    InvalidHexValue,
    InvalidAddress,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    Unexpected,
};

/// Load VM tests from a JSON file
pub fn loadVMTestsFromFile(allocator: Allocator, path: []const u8) ![]VMTest {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied => error.AccessDenied,
            else => error.Unexpected,
        };
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch {
        return error.OutOfMemory;
    };
    defer allocator.free(content);

    return loadVMTestsFromJson(allocator, content);
}

/// Load VM tests from JSON string
pub fn loadVMTestsFromJson(allocator: Allocator, json_str: []const u8) ![]VMTest {
    const parsed = json.parseFromSlice(json.Value, allocator, json_str, .{}) catch {
        return error.InvalidJson;
    };
    defer parsed.deinit();

    return loadVMTestsFromValue(allocator, parsed.value);
}

/// Load VM tests from parsed JSON value
fn loadVMTestsFromValue(allocator: Allocator, root: json.Value) ![]VMTest {
    if (root != .object) {
        return error.InvalidJson;
    }

    const obj = root.object;
    var tests = std.ArrayList(VMTest).init(allocator);
    errdefer {
        for (tests.items) |*t| {
            t.deinit(allocator);
        }
        tests.deinit();
    }

    var iter = obj.iterator();
    while (iter.next()) |entry| {
        const test_name = entry.key_ptr.*;
        const test_value = entry.value_ptr.*;

        if (test_value != .object) continue;

        const test_obj = test_value.object;

        // Parse environment
        const env = try parseEnv(test_obj.get("env") orelse continue);

        // Parse execution context
        const exec = try parseExec(allocator, test_obj.get("exec") orelse continue);

        // Parse pre-state
        const pre = try parsePre(allocator, test_obj.get("pre") orelse continue);

        // Parse post-state (optional)
        const post = if (test_obj.get("post")) |post_val|
            try parsePre(allocator, post_val)
        else
            null;

        // Parse expected output (optional)
        const expected_output = if (test_obj.get("out")) |out_val| blk: {
            if (out_val == .string) {
                break :blk try ComplianceRunner.parseHex(allocator, out_val.string);
            }
            break :blk null;
        } else null;

        // Parse expected gas (optional)
        const expected_gas = if (test_obj.get("gas")) |gas_val| blk: {
            if (gas_val == .string) {
                break :blk try ComplianceRunner.parseHexU64(gas_val.string);
            }
            break :blk null;
        } else null;

        // Copy test name
        const name_copy = try allocator.dupe(u8, test_name);

        try tests.append(VMTest{
            .name = name_copy,
            .env = env,
            .exec = exec,
            .pre = pre,
            .post = post,
            .expected_output = expected_output,
            .expected_gas = expected_gas,
            .expected_logs_hash = null,
        });
    }

    return tests.toOwnedSlice();
}

/// Parse environment from JSON
fn parseEnv(value: json.Value) !TestEnv {
    if (value != .object) return error.InvalidJson;

    const obj = value.object;

    return TestEnv{
        .coinbase = try parseAddressField(obj, "currentCoinbase"),
        .difficulty = try parseHexBigIntField(obj, "currentDifficulty"),
        .gas_limit = try parseHexU64Field(obj, "currentGasLimit"),
        .number = try parseHexU64Field(obj, "currentNumber"),
        .timestamp = try parseHexU64Field(obj, "currentTimestamp"),
        .base_fee = if (obj.get("currentBaseFee")) |v|
            if (v == .string) try ComplianceRunner.parseHexBigInt(v.string) else null
        else
            null,
    };
}

/// Parse execution context from JSON
fn parseExec(allocator: Allocator, value: json.Value) !TestExec {
    if (value != .object) return error.InvalidJson;

    const obj = value.object;

    const code = if (obj.get("code")) |v|
        if (v == .string) try ComplianceRunner.parseHex(allocator, v.string) else &[_]u8{}
    else
        &[_]u8{};

    const data = if (obj.get("data")) |v|
        if (v == .string) try ComplianceRunner.parseHex(allocator, v.string) else &[_]u8{}
    else
        &[_]u8{};

    return TestExec{
        .address = try parseAddressField(obj, "address"),
        .caller = try parseAddressField(obj, "caller"),
        .origin = try parseAddressField(obj, "origin"),
        .code = code,
        .data = data,
        .gas = try parseHexU64Field(obj, "gas"),
        .gas_price = try parseHexBigIntField(obj, "gasPrice"),
        .value = try parseHexBigIntField(obj, "value"),
    };
}

/// Parse pre/post state from JSON
fn parsePre(allocator: Allocator, value: json.Value) !std.AutoHashMap([20]u8, TestAccountState) {
    var result = std.AutoHashMap([20]u8, TestAccountState).init(allocator);
    errdefer result.deinit();

    if (value != .object) return result;

    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        const addr_str = entry.key_ptr.*;
        const account_val = entry.value_ptr.*;

        if (account_val != .object) continue;

        const addr = try ComplianceRunner.parseAddress(addr_str);
        const account_obj = account_val.object;

        // Parse balance
        const balance = if (account_obj.get("balance")) |v|
            if (v == .string) try ComplianceRunner.parseHexBigInt(v.string) else BigInt.zero()
        else
            BigInt.zero();

        // Parse nonce
        const nonce = if (account_obj.get("nonce")) |v|
            if (v == .string) try ComplianceRunner.parseHexU64(v.string) else 0
        else
            0;

        // Parse code
        const code = if (account_obj.get("code")) |v|
            if (v == .string) try ComplianceRunner.parseHex(allocator, v.string) else &[_]u8{}
        else
            &[_]u8{};

        // Parse storage
        var storage = std.AutoHashMap(BigInt, BigInt).init(allocator);
        if (account_obj.get("storage")) |storage_val| {
            if (storage_val == .object) {
                var storage_iter = storage_val.object.iterator();
                while (storage_iter.next()) |storage_entry| {
                    const key_str = storage_entry.key_ptr.*;
                    const val_v = storage_entry.value_ptr.*;

                    if (val_v == .string) {
                        const key = try ComplianceRunner.parseHexBigInt(key_str);
                        const val = try ComplianceRunner.parseHexBigInt(val_v.string);
                        try storage.put(key, val);
                    }
                }
            }
        }

        try result.put(addr, TestAccountState{
            .balance = balance,
            .nonce = nonce,
            .code = code,
            .storage = storage,
        });
    }

    return result;
}

/// Helper to parse address field
fn parseAddressField(obj: std.json.ObjectMap, field: []const u8) ![20]u8 {
    if (obj.get(field)) |v| {
        if (v == .string) {
            return ComplianceRunner.parseAddress(v.string);
        }
    }
    return [_]u8{0} ** 20;
}

/// Helper to parse hex BigInt field
fn parseHexBigIntField(obj: std.json.ObjectMap, field: []const u8) !BigInt {
    if (obj.get(field)) |v| {
        if (v == .string) {
            return ComplianceRunner.parseHexBigInt(v.string);
        }
    }
    return BigInt.zero();
}

/// Helper to parse hex u64 field
fn parseHexU64Field(obj: std.json.ObjectMap, field: []const u8) !u64 {
    if (obj.get(field)) |v| {
        if (v == .string) {
            return ComplianceRunner.parseHexU64(v.string);
        }
    }
    return 0;
}

// ============================================================
// Sample Test Vectors (Embedded)
// ============================================================

/// Sample VM test in Ethereum test format
pub const sample_add_test =
    \\{
    \\  "add": {
    \\    "env": {
    \\      "currentCoinbase": "0x0000000000000000000000000000000000000000",
    \\      "currentDifficulty": "0x0",
    \\      "currentGasLimit": "0x989680",
    \\      "currentNumber": "0x0",
    \\      "currentTimestamp": "0x0"
    \\    },
    \\    "exec": {
    \\      "address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    \\      "caller": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "origin": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "code": "0x6003600501",
    \\      "data": "0x",
    \\      "gas": "0x5f5e100",
    \\      "gasPrice": "0x1",
    \\      "value": "0x0"
    \\    },
    \\    "pre": {
    \\      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {
    \\        "balance": "0xf4240",
    \\        "code": "0x",
    \\        "nonce": "0x0",
    \\        "storage": {}
    \\      }
    \\    },
    \\    "gas": "0x5f5e0f9"
    \\  }
    \\}
;

/// Sample MUL test
pub const sample_mul_test =
    \\{
    \\  "mul": {
    \\    "env": {
    \\      "currentCoinbase": "0x0000000000000000000000000000000000000000",
    \\      "currentDifficulty": "0x0",
    \\      "currentGasLimit": "0x989680",
    \\      "currentNumber": "0x0",
    \\      "currentTimestamp": "0x0"
    \\    },
    \\    "exec": {
    \\      "address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    \\      "caller": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "origin": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "code": "0x6007600802",
    \\      "data": "0x",
    \\      "gas": "0x5f5e100",
    \\      "gasPrice": "0x1",
    \\      "value": "0x0"
    \\    },
    \\    "pre": {
    \\      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {
    \\        "balance": "0xf4240",
    \\        "code": "0x",
    \\        "nonce": "0x0",
    \\        "storage": {}
    \\      }
    \\    }
    \\  }
    \\}
;

/// Sample arithmetic tests
pub const sample_arithmetic_tests =
    \\{
    \\  "sub_basic": {
    \\    "env": {
    \\      "currentCoinbase": "0x0000000000000000000000000000000000000000",
    \\      "currentDifficulty": "0x0",
    \\      "currentGasLimit": "0x989680",
    \\      "currentNumber": "0x0",
    \\      "currentTimestamp": "0x0"
    \\    },
    \\    "exec": {
    \\      "address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    \\      "caller": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "origin": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "code": "0x6003600a03",
    \\      "data": "0x",
    \\      "gas": "0x5f5e100",
    \\      "gasPrice": "0x1",
    \\      "value": "0x0"
    \\    },
    \\    "pre": {
    \\      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {
    \\        "balance": "0xf4240",
    \\        "code": "0x",
    \\        "nonce": "0x0",
    \\        "storage": {}
    \\      }
    \\    }
    \\  },
    \\  "div_basic": {
    \\    "env": {
    \\      "currentCoinbase": "0x0000000000000000000000000000000000000000",
    \\      "currentDifficulty": "0x0",
    \\      "currentGasLimit": "0x989680",
    \\      "currentNumber": "0x0",
    \\      "currentTimestamp": "0x0"
    \\    },
    \\    "exec": {
    \\      "address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    \\      "caller": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "origin": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "code": "0x6002600a04",
    \\      "data": "0x",
    \\      "gas": "0x5f5e100",
    \\      "gasPrice": "0x1",
    \\      "value": "0x0"
    \\    },
    \\    "pre": {
    \\      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {
    \\        "balance": "0xf4240",
    \\        "code": "0x",
    \\        "nonce": "0x0",
    \\        "storage": {}
    \\      }
    \\    }
    \\  },
    \\  "mod_basic": {
    \\    "env": {
    \\      "currentCoinbase": "0x0000000000000000000000000000000000000000",
    \\      "currentDifficulty": "0x0",
    \\      "currentGasLimit": "0x989680",
    \\      "currentNumber": "0x0",
    \\      "currentTimestamp": "0x0"
    \\    },
    \\    "exec": {
    \\      "address": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    \\      "caller": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "origin": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    \\      "code": "0x6003600a06",
    \\      "data": "0x",
    \\      "gas": "0x5f5e100",
    \\      "gasPrice": "0x1",
    \\      "value": "0x0"
    \\    },
    \\    "pre": {
    \\      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {
    \\        "balance": "0xf4240",
    \\        "code": "0x",
    \\        "nonce": "0x0",
    \\        "storage": {}
    \\      }
    \\    }
    \\  }
    \\}
;

// ============================================================
// Tests
// ============================================================

test "load sample add test" {
    const allocator = std.testing.allocator;

    const tests = try loadVMTestsFromJson(allocator, sample_add_test);
    defer {
        for (tests) |*t| {
            var test_case = t.*;
            test_case.deinit(allocator);
        }
        allocator.free(tests);
    }

    try std.testing.expect(tests.len == 1);
    try std.testing.expectEqualStrings("add", tests[0].name);
    try std.testing.expect(tests[0].exec.gas == 0x5f5e100);
}

test "load sample arithmetic tests" {
    const allocator = std.testing.allocator;

    const tests = try loadVMTestsFromJson(allocator, sample_arithmetic_tests);
    defer {
        for (tests) |*t| {
            var test_case = t.*;
            test_case.deinit(allocator);
        }
        allocator.free(tests);
    }

    try std.testing.expect(tests.len == 3);
}

test "parse bytecode from json" {
    const allocator = std.testing.allocator;

    // 0x6003600501 = PUSH1 3, PUSH1 5, ADD
    const code = try ComplianceRunner.parseHex(allocator, "0x6003600501");
    defer allocator.free(code);

    try std.testing.expect(code.len == 5);
    try std.testing.expect(code[0] == 0x60); // PUSH1
    try std.testing.expect(code[1] == 0x03); // 3
    try std.testing.expect(code[2] == 0x60); // PUSH1
    try std.testing.expect(code[3] == 0x05); // 5
    try std.testing.expect(code[4] == 0x01); // ADD
}
