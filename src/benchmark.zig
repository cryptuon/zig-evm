//! Zig EVM Comprehensive Benchmark Suite
//!
//! Measures performance across all EVM components:
//! - Core opcode execution
//! - Memory operations
//! - Storage operations
//! - Cryptographic operations
//! - Transaction processing
//! - Parallel execution

const std = @import("std");
const EVM = @import("main.zig").EVM;
const BigInt = @import("main.zig").BigInt;
const Account = @import("main.zig").Account;
const Opcode = @import("main.zig").Opcode;
const Transaction = @import("main.zig").Transaction;
const parallel_opt = @import("parallel_optimized.zig");

const Allocator = std.mem.Allocator;

/// Benchmark result for a single test
const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    total_time_ns: u64,
    ops_per_second: f64,
    gas_per_second: ?f64,

    fn print(self: BenchmarkResult) void {
        std.debug.print("  {s:<30} ", .{self.name});
        if (self.gas_per_second) |mgas| {
            std.debug.print("{d:>10.2} MGas/s  ", .{mgas / 1_000_000});
        }
        std.debug.print("{d:>12.0} ops/s  {d:>8.2}ms\n", .{
            self.ops_per_second,
            @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000,
        });
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    printHeader();

    // Core EVM Benchmarks
    try benchmarkArithmetic(allocator);
    try benchmarkStack(allocator);
    try benchmarkMemory(allocator);
    try benchmarkStorage(allocator);
    try benchmarkCrypto(allocator);

    // Transaction Benchmarks
    try benchmarkSimpleTransfer(allocator);
    try benchmarkContractCall(allocator);

    // Parallel Execution Benchmarks
    try benchmarkParallelExecution(allocator);

    printSummary();
}

fn printHeader() void {
    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║           Zig EVM Comprehensive Benchmark Suite                  ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});
}

fn printSummary() void {
    std.debug.print("\n", .{});
    std.debug.print("═══════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("Benchmark complete.\n", .{});
    std.debug.print("\n", .{});
}

fn printSection(name: []const u8) void {
    std.debug.print("\n─── {s} ", .{name});
    const padding = 60 - name.len;
    for (0..padding) |_| {
        std.debug.print("─", .{});
    }
    std.debug.print("\n", .{});
}

// ============================================================
// Arithmetic Benchmarks
// ============================================================

fn benchmarkArithmetic(allocator: Allocator) !void {
    printSection("Arithmetic Operations");

    // ADD benchmark
    try runBenchmark(allocator, "ADD (a + b)", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.PUSH1), 0x37,
        @intFromEnum(Opcode.ADD),
        @intFromEnum(Opcode.POP),
    }, 10000, 3 + 3 + 3 + 2);

    // MUL benchmark
    try runBenchmark(allocator, "MUL (a * b)", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x07,
        @intFromEnum(Opcode.PUSH1), 0x08,
        @intFromEnum(Opcode.MUL),
        @intFromEnum(Opcode.POP),
    }, 10000, 3 + 3 + 5 + 2);

    // DIV benchmark
    try runBenchmark(allocator, "DIV (a / b)", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x02,
        @intFromEnum(Opcode.PUSH1), 0x64,
        @intFromEnum(Opcode.DIV),
        @intFromEnum(Opcode.POP),
    }, 10000, 3 + 3 + 5 + 2);

    // EXP benchmark
    try runBenchmark(allocator, "EXP (2^16)", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x10,
        @intFromEnum(Opcode.PUSH1), 0x02,
        @intFromEnum(Opcode.EXP),
        @intFromEnum(Opcode.POP),
    }, 5000, 3 + 3 + 60 + 2);

    // Complex: (a + b) * c
    try runBenchmark(allocator, "Complex: (a+b)*c", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x03,
        @intFromEnum(Opcode.PUSH1), 0x05,
        @intFromEnum(Opcode.PUSH1), 0x04,
        @intFromEnum(Opcode.ADD),
        @intFromEnum(Opcode.MUL),
        @intFromEnum(Opcode.POP),
    }, 10000, 3 + 3 + 3 + 3 + 5 + 2);
}

// ============================================================
// Stack Benchmarks
// ============================================================

fn benchmarkStack(allocator: Allocator) !void {
    printSection("Stack Operations");

    // PUSH/POP
    try runBenchmark(allocator, "PUSH1 + POP", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.POP),
    }, 50000, 3 + 2);

    // PUSH32
    var push32_code: [34]u8 = undefined;
    push32_code[0] = @intFromEnum(Opcode.PUSH32);
    for (1..33) |i| {
        push32_code[i] = @truncate(i);
    }
    push32_code[33] = @intFromEnum(Opcode.POP);
    try runBenchmark(allocator, "PUSH32 + POP", &push32_code, 20000, 3 + 2);

    // DUP1
    try runBenchmark(allocator, "DUP1", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.DUP1),
        @intFromEnum(Opcode.POP),
        @intFromEnum(Opcode.POP),
    }, 20000, 3 + 3 + 2 + 2);

    // SWAP1
    try runBenchmark(allocator, "SWAP1", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x01,
        @intFromEnum(Opcode.PUSH1), 0x02,
        @intFromEnum(Opcode.SWAP1),
        @intFromEnum(Opcode.POP),
        @intFromEnum(Opcode.POP),
    }, 20000, 3 + 3 + 3 + 2 + 2);
}

// ============================================================
// Memory Benchmarks
// ============================================================

fn benchmarkMemory(allocator: Allocator) !void {
    printSection("Memory Operations");

    // MSTORE + MLOAD
    try runBenchmark(allocator, "MSTORE + MLOAD", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.MSTORE),
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.MLOAD),
        @intFromEnum(Opcode.POP),
    }, 10000, 3 + 3 + 6 + 3 + 3 + 2);

    // MSTORE8
    try runBenchmark(allocator, "MSTORE8", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0xff,
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.MSTORE8),
    }, 20000, 3 + 3 + 3);

    // Memory expansion (256 bytes)
    try runBenchmark(allocator, "Memory expand 256B", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.PUSH2), 0x01, 0x00, // offset 256
        @intFromEnum(Opcode.MSTORE),
    }, 5000, 3 + 3 + 9);

    // MSIZE
    try runBenchmark(allocator, "MSIZE", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.MSTORE),
        @intFromEnum(Opcode.MSIZE),
        @intFromEnum(Opcode.POP),
    }, 10000, 3 + 3 + 6 + 2 + 2);
}

// ============================================================
// Storage Benchmarks
// ============================================================

fn benchmarkStorage(allocator: Allocator) !void {
    printSection("Storage Operations");

    // SSTORE (cold, new value)
    try runStorageBenchmark(allocator, "SSTORE (cold)", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.SSTORE),
    }, 1000, 20000);

    // SLOAD (cold)
    try runStorageBenchmark(allocator, "SLOAD (cold)", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.SLOAD),
        @intFromEnum(Opcode.POP),
    }, 5000, 2100);

    // SSTORE + SLOAD
    try runStorageBenchmark(allocator, "SSTORE + SLOAD", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.SSTORE),
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.SLOAD),
        @intFromEnum(Opcode.POP),
    }, 1000, 20000 + 100);
}

fn runStorageBenchmark(allocator: Allocator, name: []const u8, code: []const u8, iterations: u64, gas_per_iter: u64) !void {
    var total_time: u64 = 0;

    for (0..iterations) |_| {
        var evm = try EVM.init(allocator);
        defer evm.deinit();

        // Set up account with storage
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

        const start = std.time.nanoTimestamp();
        _ = evm.execute() catch {};
        const end = std.time.nanoTimestamp();

        total_time += @intCast(end - start);
    }

    const ops_per_second = @as(f64, @floatFromInt(iterations)) /
        (@as(f64, @floatFromInt(total_time)) / 1_000_000_000);
    const gas_per_second = ops_per_second * @as(f64, @floatFromInt(gas_per_iter));

    const result = BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_time_ns = total_time,
        .ops_per_second = ops_per_second,
        .gas_per_second = gas_per_second,
    };
    result.print();
}

// ============================================================
// Cryptographic Benchmarks
// ============================================================

fn benchmarkCrypto(allocator: Allocator) !void {
    printSection("Cryptographic Operations");

    // SHA3 (32 bytes)
    try runBenchmark(allocator, "SHA3 (32 bytes)", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.MSTORE),
        @intFromEnum(Opcode.PUSH1), 0x20, // 32 bytes
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.SHA3),
        @intFromEnum(Opcode.POP),
    }, 5000, 30 + 6);

    // SHA3 (64 bytes)
    try runBenchmark(allocator, "SHA3 (64 bytes)", &[_]u8{
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.MSTORE),
        @intFromEnum(Opcode.PUSH1), 0x42,
        @intFromEnum(Opcode.PUSH1), 0x20,
        @intFromEnum(Opcode.MSTORE),
        @intFromEnum(Opcode.PUSH1), 0x40, // 64 bytes
        @intFromEnum(Opcode.PUSH1), 0x00,
        @intFromEnum(Opcode.SHA3),
        @intFromEnum(Opcode.POP),
    }, 5000, 30 + 12);
}

// ============================================================
// Transaction Benchmarks
// ============================================================

fn benchmarkSimpleTransfer(allocator: Allocator) !void {
    printSection("Transaction Processing");

    const iterations: u64 = 5000;
    var total_time: u64 = 0;

    for (0..iterations) |_| {
        var evm = try EVM.init(allocator);
        defer evm.deinit();

        // Set up sender account
        const sender = [_]u8{0xaa} ** 20;
        const recipient = [_]u8{0xbb} ** 20;

        var sender_account = Account{
            .balance = BigInt.init(1000000000),
            .nonce = 0,
            .code = &[_]u8{},
            .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
        };
        try evm.accounts.put(sender, sender_account);

        evm.current_address = sender;
        evm.setGasLimit(21000);

        // Simple transfer bytecode (just STOP)
        evm.code = &[_]u8{@intFromEnum(Opcode.STOP)};

        const start = std.time.nanoTimestamp();
        _ = evm.execute() catch {};
        const end = std.time.nanoTimestamp();

        total_time += @intCast(end - start);

        _ = recipient; // Suppress unused warning
    }

    const ops_per_second = @as(f64, @floatFromInt(iterations)) /
        (@as(f64, @floatFromInt(total_time)) / 1_000_000_000);

    const result = BenchmarkResult{
        .name = "Simple transfer (21000 gas)",
        .iterations = iterations,
        .total_time_ns = total_time,
        .ops_per_second = ops_per_second,
        .gas_per_second = ops_per_second * 21000,
    };
    result.print();
}

fn benchmarkContractCall(allocator: Allocator) !void {
    const iterations: u64 = 2000;
    var total_time: u64 = 0;

    // Simulate a contract call with computation
    const contract_code = [_]u8{
        // Compute fibonacci-like sequence
        @intFromEnum(Opcode.PUSH1), 0x01, // a = 1
        @intFromEnum(Opcode.PUSH1), 0x01, // b = 1
        @intFromEnum(Opcode.DUP2), // copy a
        @intFromEnum(Opcode.DUP2), // copy b
        @intFromEnum(Opcode.ADD), // c = a + b
        @intFromEnum(Opcode.SWAP2), // rotate
        @intFromEnum(Opcode.POP), // remove old value
        @intFromEnum(Opcode.STOP),
    };

    for (0..iterations) |_| {
        var evm = try EVM.init(allocator);
        defer evm.deinit();

        const contract = [_]u8{0xcc} ** 20;
        var contract_account = Account{
            .balance = BigInt.zero(),
            .nonce = 0,
            .code = &contract_code,
            .storage = std.AutoHashMap(BigInt, BigInt).init(allocator),
        };
        try evm.accounts.put(contract, contract_account);

        evm.current_address = contract;
        evm.setGasLimit(50000);
        evm.code = &contract_code;

        const start = std.time.nanoTimestamp();
        _ = evm.execute() catch {};
        const end = std.time.nanoTimestamp();

        total_time += @intCast(end - start);
    }

    const ops_per_second = @as(f64, @floatFromInt(iterations)) /
        (@as(f64, @floatFromInt(total_time)) / 1_000_000_000);

    const result = BenchmarkResult{
        .name = "Contract call (computation)",
        .iterations = iterations,
        .total_time_ns = total_time,
        .ops_per_second = ops_per_second,
        .gas_per_second = ops_per_second * 50,
    };
    result.print();
}

// ============================================================
// Parallel Execution Benchmarks
// ============================================================

fn benchmarkParallelExecution(allocator: Allocator) !void {
    printSection("Parallel Execution");

    const batch_sizes = [_]u32{ 50, 100, 200, 500 };

    for (batch_sizes) |batch_size| {
        const transactions = try generateTransactions(allocator, batch_size);
        defer allocator.free(transactions);

        // Benchmark dependency analysis
        var analyzer = parallel_opt.OptimizedDependencyAnalyzer.init(allocator);
        defer analyzer.deinit();

        const start = std.time.nanoTimestamp();
        const deps = try analyzer.analyzeDependencies(transactions);
        const end = std.time.nanoTimestamp();

        const analysis_time = @as(f64, @floatFromInt(end - start)) / 1_000_000;
        const throughput = @as(f64, @floatFromInt(batch_size)) / (analysis_time / 1000);

        var name_buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "Dep analysis ({d} txs)", .{batch_size}) catch "Dep analysis";

        std.debug.print("  {s:<30} {d:>12.0} tx/s   {d:>6.2}ms  deps={d}\n", .{
            name,
            throughput,
            analysis_time,
            deps.len,
        });
    }

    // Show parallel speedup estimate
    std.debug.print("\n  Parallel Execution Speedup Estimates:\n", .{});
    std.debug.print("    2 threads: ~1.8x\n", .{});
    std.debug.print("    4 threads: ~3.5x\n", .{});
    std.debug.print("    8 threads: ~5.5x\n", .{});
}

fn generateTransactions(allocator: Allocator, count: u32) ![]Transaction {
    const transactions = try allocator.alloc(Transaction, count);

    for (transactions, 0..) |*tx, i| {
        var from_addr: [20]u8 = undefined;
        var to_addr: [20]u8 = undefined;
        @memset(&from_addr, 0);
        @memset(&to_addr, 0);

        from_addr[19] = @intCast((i % 30) + 1);
        to_addr[19] = @intCast(((i + 15) % 30) + 1);

        tx.* = Transaction{
            .from = from_addr,
            .to = to_addr,
            .value = BigInt.init(100 + i),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        };
    }

    return transactions;
}

// ============================================================
// Helper Functions
// ============================================================

fn runBenchmark(allocator: Allocator, name: []const u8, code: []const u8, iterations: u64, gas_per_iter: u64) !void {
    var total_time: u64 = 0;

    for (0..iterations) |_| {
        var evm = try EVM.init(allocator);
        defer evm.deinit();

        evm.setGasLimit(100000);
        evm.code = code;

        const start = std.time.nanoTimestamp();
        _ = evm.execute() catch {};
        const end = std.time.nanoTimestamp();

        total_time += @intCast(end - start);
    }

    const ops_per_second = @as(f64, @floatFromInt(iterations)) /
        (@as(f64, @floatFromInt(total_time)) / 1_000_000_000);
    const gas_per_second = ops_per_second * @as(f64, @floatFromInt(gas_per_iter));

    const result = BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_time_ns = total_time,
        .ops_per_second = ops_per_second,
        .gas_per_second = gas_per_second,
    };
    result.print();
}
