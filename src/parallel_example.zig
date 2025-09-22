// File: src/parallel_example.zig
// Example demonstrating parallel transaction execution

const std = @import("std");
const evm = @import("main.zig");
const parallel = @import("parallel.zig");

const EVM = evm.EVM;
const Transaction = evm.Transaction;
const BigInt = evm.BigInt;
const ParallelScheduler = parallel.ParallelScheduler;

/// Example demonstrating basic parallel execution
pub fn runParallelExample(allocator: std.mem.Allocator) !void {
    std.debug.print("=== Parallel EVM Execution Example ===\n", .{});

    // Create parallel scheduler with 4 threads
    var scheduler = try ParallelScheduler.init(allocator, 4);
    defer scheduler.deinit();

    // Create sample transactions
    const transactions = try createSampleTransactions(allocator);
    defer allocator.free(transactions);

    std.debug.print("Executing {d} transactions in parallel...\n", .{transactions.len});

    // Measure execution time
    const start_time = std.time.nanoTimestamp();

    // Execute transactions in parallel
    const results = try scheduler.executeTransactionBatch(transactions);

    const end_time = std.time.nanoTimestamp();
    const execution_time_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Print results
    std.debug.print("Execution completed in {d:.2} ms\n", .{execution_time_ms});
    std.debug.print("Results:\n", .{});

    var successful: u32 = 0;
    var total_gas: u64 = 0;

    for (results) |result| {
        if (result.success) {
            successful += 1;
            total_gas += result.gas_used;
            std.debug.print("  TX {d}: SUCCESS (Gas: {d})\n", .{ result.tx_id, result.gas_used });
        } else {
            const error_msg = result.error_msg orelse "Unknown error";
            std.debug.print("  TX {d}: FAILED ({s})\n", .{ result.tx_id, error_msg });
        }
    }

    std.debug.print("\nSummary:\n", .{});
    std.debug.print("  Successful: {d}/{d}\n", .{ successful, transactions.len });
    std.debug.print("  Total Gas Used: {d}\n", .{total_gas});
    std.debug.print("  Average Gas per TX: {d:.1}\n", .{@as(f64, @floatFromInt(total_gas)) / @as(f64, @floatFromInt(successful))});
}

/// Create sample transactions for testing
fn createSampleTransactions(allocator: std.mem.Allocator) ![]Transaction {
    const tx_count = 10;
    const transactions = try allocator.alloc(Transaction, tx_count);

    // Generate different addresses
    for (transactions, 0..) |*tx, i| {
        var from_addr: [20]u8 = undefined;
        var to_addr: [20]u8 = undefined;

        // Create simple address patterns
        @memset(&from_addr, 0);
        @memset(&to_addr, 0);
        from_addr[19] = @intCast(i + 1);      // from address
        to_addr[19] = @intCast((i + 5) % 10 + 1); // to address (creates some overlap)

        tx.* = Transaction{
            .from = from_addr,
            .to = to_addr,
            .value = BigInt.init(100 + i * 10), // Varying amounts
            .data = &[_]u8{}, // No contract code for simple transfers
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000), // 20 gwei
        };
    }

    return transactions;
}

/// Demonstration of dependency analysis
pub fn demonstrateDependencyAnalysis(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Dependency Analysis Demo ===\n", .{});

    var analyzer = parallel.DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();

    // Create transactions with known dependencies
    const addr_a = [_]u8{0xAA} ** 20;
    const addr_b = [_]u8{0xBB} ** 20;
    const addr_c = [_]u8{0xCC} ** 20;

    const dependent_transactions = [_]Transaction{
        // TX 0: A -> B (100 units)
        Transaction{
            .from = addr_a,
            .to = addr_b,
            .value = BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        // TX 1: B -> C (50 units) - depends on TX 0
        Transaction{
            .from = addr_b,
            .to = addr_c,
            .value = BigInt.init(50),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        // TX 2: A -> C (25 units) - independent
        Transaction{
            .from = addr_a,
            .to = addr_c,
            .value = BigInt.init(25),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        // TX 3: A -> B (10 units) - conflicts with TX 0 (same sender)
        Transaction{
            .from = addr_a,
            .to = addr_b,
            .value = BigInt.init(10),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
    };

    const dependencies = try analyzer.analyzeDependencies(&dependent_transactions);

    std.debug.print("Found {d} dependencies:\n", .{dependencies.len});
    for (dependencies) |dep| {
        const conflict_name = switch (dep.conflict_type) {
            .write_write => "write-write",
            .balance => "balance",
            .nonce => "nonce",
        };
        std.debug.print("  TX {d} -> TX {d} ({s} conflict)\n", .{ dep.from_tx, dep.to_tx, conflict_name });
    }

    // Demonstrate parallel vs sequential execution ordering
    std.debug.print("\nExecution Order Analysis:\n", .{});
    std.debug.print("Sequential order: TX 0 -> TX 1 -> TX 2 -> TX 3\n", .{});
    std.debug.print("Parallel potential:\n", .{});
    std.debug.print("  Wave 1: TX 0, TX 2 (independent)\n", .{});
    std.debug.print("  Wave 2: TX 1 (after TX 0)\n", .{});
    std.debug.print("  Wave 3: TX 3 (after TX 0, nonce dependency)\n", .{});
}

/// Benchmark parallel vs sequential execution
pub fn benchmarkParallelExecution(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Parallel vs Sequential Benchmark ===\n", .{});

    const batch_sizes = [_]u32{ 10, 50, 100 };
    const thread_counts = [_]u32{ 1, 2, 4, 8 };

    for (batch_sizes) |batch_size| {
        std.debug.print("\nBatch size: {d} transactions\n", .{batch_size});

        for (thread_counts) |thread_count| {
            // Create scheduler
            var scheduler = try ParallelScheduler.init(allocator, thread_count);
            defer scheduler.deinit();

            // Generate transactions
            const transactions = try allocator.alloc(Transaction, batch_size);
            defer allocator.free(transactions);

            for (transactions, 0..) |*tx, i| {
                var from_addr: [20]u8 = undefined;
                var to_addr: [20]u8 = undefined;
                @memset(&from_addr, 0);
                @memset(&to_addr, 0);
                from_addr[19] = @intCast((i % 20) + 1);
                to_addr[19] = @intCast(((i + 10) % 20) + 1);

                tx.* = Transaction{
                    .from = from_addr,
                    .to = to_addr,
                    .value = BigInt.init(100),
                    .data = &[_]u8{},
                    .gas_limit = 21000,
                    .gas_price = BigInt.init(20000000000),
                };
            }

            // Benchmark execution
            const start_time = std.time.nanoTimestamp();
            const results = try scheduler.executeTransactionBatch(transactions);
            const end_time = std.time.nanoTimestamp();

            const execution_time_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
            const throughput = @as(f64, @floatFromInt(batch_size)) / (execution_time_ms / 1000.0);

            // Calculate success rate
            var successful: u32 = 0;
            for (results) |result| {
                if (result.success) successful += 1;
            }

            const success_rate = @as(f64, @floatFromInt(successful)) / @as(f64, @floatFromInt(batch_size)) * 100.0;

            std.debug.print("  {d} threads: {d:.2}ms ({d:.1} tx/s, {d:.1}% success)\n", .{
                thread_count,
                execution_time_ms,
                throughput,
                success_rate,
            });
        }
    }
}

// Example main function for the parallel execution demo
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runParallelExample(allocator);
    try demonstrateDependencyAnalysis(allocator);
    try benchmarkParallelExecution(allocator);
}