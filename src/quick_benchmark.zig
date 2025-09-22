// File: src/quick_benchmark.zig
// Quick benchmark demonstration of parallel execution optimizations

const std = @import("std");
const evm = @import("main.zig");
const parallel = @import("parallel.zig");
const parallel_opt = @import("parallel_optimized.zig");

const Transaction = evm.Transaction;
const BigInt = evm.BigInt;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zig EVM Parallel Execution Benchmark ===\n", .{});

    try benchmarkDependencyAnalysis(allocator);
    try benchmarkMemoryPools(allocator);
    try demonstrateWorkStealing(allocator);
}

fn benchmarkDependencyAnalysis(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔍 Dependency Analysis Optimization Benchmark\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});

    const transaction_counts = [_]u32{ 10, 25, 50, 100 };

    for (transaction_counts) |tx_count| {
        const transactions = try generateSimpleTransactions(allocator, tx_count);
        defer allocator.free(transactions);

        // Benchmark original O(n²) analysis
        var original_analyzer = parallel.DependencyAnalyzer.init(allocator);
        defer original_analyzer.deinit();

        const original_start = std.time.nanoTimestamp();
        const original_deps = try original_analyzer.analyzeDependencies(transactions);
        const original_end = std.time.nanoTimestamp();
        const original_time = @as(f64, @floatFromInt(original_end - original_start)) / 1_000_000.0;

        // Benchmark optimized O(n) analysis
        var optimized_analyzer = parallel_opt.OptimizedDependencyAnalyzer.init(allocator);
        defer optimized_analyzer.deinit();

        const optimized_start = std.time.nanoTimestamp();
        const optimized_deps = try optimized_analyzer.analyzeDependencies(transactions);
        const optimized_end = std.time.nanoTimestamp();
        const optimized_time = @as(f64, @floatFromInt(optimized_end - optimized_start)) / 1_000_000.0;

        const speedup = if (optimized_time > 0) original_time / optimized_time else 999.0;

        std.debug.print("Transactions: {d:3} | Original: {d:6.3}ms | Optimized: {d:6.3}ms | Speedup: {d:5.1}x\n", .{
            tx_count, original_time, optimized_time, speedup
        });

        std.debug.print("               Dependencies: Original={d}, Optimized={d}\n", .{
            original_deps.len, optimized_deps.len
        });
    }
}

fn benchmarkMemoryPools(allocator: std.mem.Allocator) !void {
    std.debug.print("\n💾 Memory Pool Optimization Benchmark\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});

    var memory_pool = parallel_opt.MemoryPool.init(allocator);
    defer memory_pool.deinit();

    const allocation_sizes = [_]usize{ 128, 1024, 4096 };
    const iterations = 1000;

    for (allocation_sizes) |size| {
        // Benchmark direct allocations
        const direct_start = std.time.nanoTimestamp();
        var direct_blocks = std.ArrayList([]u8){};
        defer direct_blocks.deinit(allocator);

        for (0..iterations) |_| {
            const block = try allocator.alloc(u8, size);
            try direct_blocks.append(allocator, block);
        }

        for (direct_blocks.items) |block| {
            allocator.free(block);
        }
        const direct_end = std.time.nanoTimestamp();
        const direct_time = @as(f64, @floatFromInt(direct_end - direct_start)) / 1_000_000.0;

        // Benchmark pooled allocations
        const pooled_start = std.time.nanoTimestamp();
        var pooled_blocks = std.ArrayList([]u8){};
        defer pooled_blocks.deinit(allocator);

        for (0..iterations) |_| {
            const block = try memory_pool.acquire(size);
            try pooled_blocks.append(allocator, block);
        }

        for (pooled_blocks.items) |block| {
            memory_pool.release(block);
        }
        const pooled_end = std.time.nanoTimestamp();
        const pooled_time = @as(f64, @floatFromInt(pooled_end - pooled_start)) / 1_000_000.0;

        const improvement = if (pooled_time > 0) (direct_time - pooled_time) / direct_time * 100.0 else 0.0;

        std.debug.print("Size: {d:4}B | Direct: {d:6.2}ms | Pooled: {d:6.2}ms | Improvement: {d:4.1}%\n", .{
            size, direct_time, pooled_time, improvement
        });
    }
}

fn demonstrateWorkStealing(allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ Work-Stealing Thread Pool Demonstration\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});

    const thread_counts = [_]u32{ 1, 2, 4 };
    const work_items = 100;

    for (thread_counts) |threads| {
        var pool = try parallel_opt.WorkStealingThreadPool.init(allocator, threads);
        defer pool.deinit();

        const start_time = std.time.nanoTimestamp();

        // Submit work items
        for (0..work_items) |i| {
            const work_item = parallel_opt.WorkItem{
                .execute_fn = dummyWork,
                .context = @constCast(@ptrCast(&i)),
            };
            try pool.submitWork(work_item);
        }

        // Wait for completion (simplified - in real implementation would use proper synchronization)
        std.Thread.sleep(10_000_000); // 10ms

        const end_time = std.time.nanoTimestamp();
        const execution_time = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const throughput = @as(f64, @floatFromInt(work_items)) / (execution_time / 1000.0);

        std.debug.print("Threads: {d} | Time: {d:6.2}ms | Throughput: {d:8.0} items/s\n", .{
            threads, execution_time, throughput
        });
    }
}

fn dummyWork(work_item: *parallel_opt.WorkItem) void {
    _ = work_item;
    // Simulate some work
    var sum: u64 = 0;
    for (0..1000) |i| {
        sum += i;
    }
    // Prevent optimization
    std.mem.doNotOptimizeAway(sum);
}

fn generateSimpleTransactions(allocator: std.mem.Allocator, count: u32) ![]Transaction {
    const transactions = try allocator.alloc(Transaction, count);

    for (transactions, 0..) |*tx, i| {
        var from_addr: [20]u8 = undefined;
        var to_addr: [20]u8 = undefined;
        @memset(&from_addr, 0);
        @memset(&to_addr, 0);

        // Create simple address patterns that will generate some conflicts
        from_addr[19] = @intCast((i % 20) + 1);
        to_addr[19] = @intCast(((i + 10) % 20) + 1);

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