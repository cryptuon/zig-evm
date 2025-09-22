// File: src/parallel_optimized_example.zig
// Optimized parallel execution demonstration

const std = @import("std");
const evm = @import("main.zig");
const parallel_opt = @import("parallel_optimized.zig");

const EVM = evm.EVM;
const Transaction = evm.Transaction;
const BigInt = evm.BigInt;
const OptimizedParallelScheduler = parallel_opt.OptimizedParallelScheduler;
const ParallelConfig = parallel_opt.ParallelConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try demonstrateOptimizations(allocator);
    // try benchmarkOptimizations(allocator);
    // try analyzeScalability(allocator);
}

fn demonstrateOptimizations(allocator: std.mem.Allocator) !void {
    std.debug.print("=== Optimized Parallel Execution Demo ===\n", .{});

    // Test different configurations
    const configs = [_]struct {
        name: []const u8,
        config: ParallelConfig,
    }{
        .{ .name = "Conservative (1 thread)", .config = .{ .max_threads = 1, .enable_speculative_execution = false } },
        .{ .name = "Basic Parallel (4 threads)", .config = .{ .max_threads = 4, .enable_speculative_execution = false } },
        .{ .name = "Optimized (4 threads + speculation)", .config = .{ .max_threads = 4, .enable_speculative_execution = true } },
        .{ .name = "High Performance (8 threads + all optimizations)", .config = .{
            .max_threads = 8,
            .enable_speculative_execution = true,
            .enable_state_snapshots = true,
            .conflict_detection_level = .precise,
        } },
    };

    const transaction_count = 50;
    const transactions = try generateRealisticTransactions(allocator, transaction_count);
    defer allocator.free(transactions);

    for (configs) |test_config| {
        std.debug.print("\n--- {s} ---\n", .{test_config.name});

        var scheduler = try OptimizedParallelScheduler.init(allocator, test_config.config);
        defer scheduler.deinit();

        const start_time = std.time.nanoTimestamp();
        const results = try scheduler.executeTransactionBatch(transactions);
        const end_time = std.time.nanoTimestamp();

        const execution_time = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const throughput = @as(f64, @floatFromInt(transaction_count)) / (execution_time / 1000.0);

        var successful: u32 = 0;
        var total_gas: u64 = 0;
        for (results) |result| {
            if (result.success) {
                successful += 1;
                total_gas += result.gas_used;
            }
        }

        std.debug.print("  Execution Time: {d:.2} ms\n", .{execution_time});
        std.debug.print("  Throughput: {d:.0} tx/s\n", .{throughput});
        std.debug.print("  Success Rate: {d:.1}%\n", .{@as(f64, @floatFromInt(successful)) / @as(f64, @floatFromInt(transaction_count)) * 100.0});
        std.debug.print("  Total Gas Used: {d}\n", .{total_gas});
    }
}

fn benchmarkOptimizations(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Optimization Impact Analysis ===\n", .{});

    const batch_sizes = [_]u32{ 20, 50, 100 };

    for (batch_sizes) |batch_size| {
        std.debug.print("\nBatch size: {d} transactions\n", .{batch_size});

        const transactions = try generateRealisticTransactions(allocator, batch_size);
        defer allocator.free(transactions);

        // Baseline: Single-threaded
        var baseline_scheduler = try OptimizedParallelScheduler.init(allocator, .{
            .max_threads = 1,
            .enable_speculative_execution = false,
        });
        defer baseline_scheduler.deinit();

        const baseline_start = std.time.nanoTimestamp();
        _ = try baseline_scheduler.executeTransactionBatch(transactions);
        const baseline_end = std.time.nanoTimestamp();
        const baseline_time = @as(f64, @floatFromInt(baseline_end - baseline_start)) / 1_000_000.0;

        // Optimized: Multi-threaded with all optimizations
        var optimized_scheduler = try OptimizedParallelScheduler.init(allocator, .{
            .max_threads = 8,
            .enable_speculative_execution = true,
            .enable_state_snapshots = true,
            .conflict_detection_level = .precise,
        });
        defer optimized_scheduler.deinit();

        const optimized_start = std.time.nanoTimestamp();
        _ = try optimized_scheduler.executeTransactionBatch(transactions);
        const optimized_end = std.time.nanoTimestamp();
        const optimized_time = @as(f64, @floatFromInt(optimized_end - optimized_start)) / 1_000_000.0;

        const speedup = baseline_time / optimized_time;
        const efficiency = speedup / 8.0 * 100.0; // 8 threads

        std.debug.print("  Baseline (1 thread): {d:.2} ms\n", .{baseline_time});
        std.debug.print("  Optimized (8 threads): {d:.2} ms\n", .{optimized_time});
        std.debug.print("  Speedup: {d:.2}x\n", .{speedup});
        std.debug.print("  Parallel Efficiency: {d:.1}%\n", .{efficiency});
    }
}

fn analyzeScalability(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Scalability Analysis ===\n", .{});

    const thread_counts = [_]u32{ 1, 2, 4, 8 };
    const transaction_count = 100;

    const transactions = try generateRealisticTransactions(allocator, transaction_count);
    defer allocator.free(transactions);

    var baseline_time: f64 = 0;

    for (thread_counts) |threads| {
        var scheduler = try OptimizedParallelScheduler.init(allocator, .{
            .max_threads = threads,
            .enable_speculative_execution = true,
            .enable_state_snapshots = true,
            .conflict_detection_level = .precise,
        });
        defer scheduler.deinit();

        const start_time = std.time.nanoTimestamp();
        _ = try scheduler.executeTransactionBatch(transactions);
        const end_time = std.time.nanoTimestamp();

        const execution_time = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const throughput = @as(f64, @floatFromInt(transaction_count)) / (execution_time / 1000.0);

        if (threads == 1) {
            baseline_time = execution_time;
        }

        const speedup = if (threads == 1) 1.0 else baseline_time / execution_time;
        const efficiency = speedup / @as(f64, @floatFromInt(threads)) * 100.0;

        std.debug.print("  {d:2} threads: {d:6.2} ms | {d:6.0} tx/s | {d:4.2}x speedup | {d:5.1}% efficiency\n", .{
            threads, execution_time, throughput, speedup, efficiency
        });
    }

    std.debug.print("\nOptimal thread count appears to be around 4-8 threads for this workload.\n", .{});
}

fn generateRealisticTransactions(allocator: std.mem.Allocator, count: u32) ![]Transaction {
    const transactions = try allocator.alloc(Transaction, count);

    // Create realistic transaction patterns:
    // - 70% simple transfers (low conflict)
    // - 20% transactions to popular addresses (medium conflict)
    // - 10% transactions from/to same addresses (high conflict)

    const popular_addresses = [_][20]u8{
        [_]u8{0x01} ** 20, // Exchange
        [_]u8{0x02} ** 20, // DeFi protocol
        [_]u8{0x03} ** 20, // Popular contract
    };

    for (transactions, 0..) |*tx, i| {
        var from_addr: [20]u8 = undefined;
        var to_addr: [20]u8 = undefined;
        @memset(&from_addr, 0);
        @memset(&to_addr, 0);

        const pattern = i % 10;

        if (pattern < 7) {
            // 70% - Simple transfers with low conflict probability
            from_addr[19] = @intCast((i % 100) + 10);
            to_addr[19] = @intCast(((i + 50) % 100) + 10);
        } else if (pattern < 9) {
            // 20% - Transactions to popular addresses
            from_addr[19] = @intCast((i % 50) + 10);
            to_addr = popular_addresses[i % popular_addresses.len];
        } else {
            // 10% - High conflict transactions
            const conflict_base = i % 5;
            from_addr[19] = @intCast(conflict_base + 1);
            to_addr[19] = @intCast(conflict_base + 2);
        }

        tx.* = Transaction{
            .from = from_addr,
            .to = to_addr,
            .value = BigInt.init(100 + (i * 7) % 1000), // Varying amounts
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000 + (i % 10) * 1000000000), // Varying gas prices
        };
    }

    return transactions;
}

fn demonstrateMemoryOptimizations(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Memory Optimization Demo ===\n", .{});

    // Create memory pool
    var memory_pool = parallel_opt.MemoryPool.init(allocator);
    defer memory_pool.deinit();

    // Demonstrate memory pool usage
    std.debug.print("Testing memory pool allocation patterns...\n", .{});

    const allocation_sizes = [_]usize{ 128, 1024, 8192, 32768 };
    var allocated_blocks = std.ArrayList([]u8).init(allocator);
    defer allocated_blocks.deinit();

    // Allocate test blocks
    for (allocation_sizes) |size| {
        for (0..10) |_| {
            const block = try memory_pool.acquire(size);
            try allocated_blocks.append(block);
        }
    }

    std.debug.print("Allocated {d} blocks of varying sizes\n", .{allocated_blocks.items.len});

    // Release blocks
    for (allocated_blocks.items) |block| {
        memory_pool.release(block);
    }

    std.debug.print("Released all blocks back to pool\n", .{});
    std.debug.print("Memory pool optimization complete!\n", .{});
}

fn demonstrateDependencyOptimization(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Dependency Analysis Optimization ===\n", .{});

    const transaction_counts = [_]u32{ 50, 100, 200 };

    for (transaction_counts) |tx_count| {
        const transactions = try generateRealisticTransactions(allocator, tx_count);
        defer allocator.free(transactions);

        // Test original O(n²) analysis
        var original_analyzer = @import("parallel.zig").DependencyAnalyzer.init(allocator);
        defer original_analyzer.deinit();

        const original_start = std.time.nanoTimestamp();
        const original_deps = try original_analyzer.analyzeDependencies(transactions);
        const original_end = std.time.nanoTimestamp();
        const original_time = @as(f64, @floatFromInt(original_end - original_start)) / 1_000_000.0;

        // Test optimized O(n) analysis
        var optimized_analyzer = parallel_opt.OptimizedDependencyAnalyzer.init(allocator);
        defer optimized_analyzer.deinit();

        const optimized_start = std.time.nanoTimestamp();
        const optimized_deps = try optimized_analyzer.analyzeDependencies(transactions);
        const optimized_end = std.time.nanoTimestamp();
        const optimized_time = @as(f64, @floatFromInt(optimized_end - optimized_start)) / 1_000_000.0;

        const speedup = original_time / optimized_time;

        std.debug.print("Transactions: {d:4} | Original: {d:6.2}ms | Optimized: {d:6.2}ms | Speedup: {d:5.1}x\n", .{
            tx_count, original_time, optimized_time, speedup
        });

        std.debug.print("  Dependencies found: Original={d}, Optimized={d}\n", .{
            original_deps.len, optimized_deps.len
        });
    }
}