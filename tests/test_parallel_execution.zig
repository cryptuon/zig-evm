// File: tests/test_parallel_execution.zig
// Comprehensive tests for parallel execution functionality

const std = @import("std");
const testing = std.testing;
const main = @import("../src/main.zig");
const parallel = @import("../src/parallel.zig");

const EVM = main.EVM;
const Transaction = main.Transaction;
const BigInt = main.BigInt;
const ThreadPool = parallel.ThreadPool;
const DependencyAnalyzer = parallel.DependencyAnalyzer;
const ParallelScheduler = parallel.ParallelScheduler;
const Dependency = parallel.Dependency;
const ConflictType = parallel.ConflictType;

test "ThreadPool creation and destruction" {
    const allocator = testing.allocator;

    var pool = try ThreadPool.init(allocator, 4);
    defer pool.deinit();

    try testing.expect(pool.threads.len == 4);
    try testing.expect(!pool.shutdown);
    try testing.expect(pool.work_queue.items.len == 0);
}

test "DependencyAnalyzer basic conflict detection" {
    const allocator = testing.allocator;

    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();

    // Create test addresses
    const addr_a = [_]u8{0xAA} ** 20;
    const addr_b = [_]u8{0xBB} ** 20;

    // Create transactions with conflicts
    const transactions = [_]Transaction{
        // TX 0: A -> B
        Transaction{
            .from = addr_a,
            .to = addr_b,
            .value = BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        // TX 1: B -> A (balance dependency)
        Transaction{
            .from = addr_b,
            .to = addr_a,
            .value = BigInt.init(50),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
    };

    const dependencies = try analyzer.analyzeDependencies(&transactions);

    // Should find at least one dependency
    try testing.expect(dependencies.len > 0);

    // Check that the dependency is a balance conflict
    var found_balance_conflict = false;
    for (dependencies) |dep| {
        if (dep.conflict_type == .balance) {
            found_balance_conflict = true;
            break;
        }
    }
    try testing.expect(found_balance_conflict);
}

test "DependencyAnalyzer nonce conflicts" {
    const allocator = testing.allocator;

    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();

    const addr_a = [_]u8{0xAA} ** 20;
    const addr_b = [_]u8{0xBB} ** 20;
    const addr_c = [_]u8{0xCC} ** 20;

    // Create transactions from same sender (nonce conflict)
    const transactions = [_]Transaction{
        Transaction{
            .from = addr_a,
            .to = addr_b,
            .value = BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        Transaction{
            .from = addr_a,
            .to = addr_c,
            .value = BigInt.init(50),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
    };

    const dependencies = try analyzer.analyzeDependencies(&transactions);

    // Should find nonce conflict
    try testing.expect(dependencies.len > 0);

    var found_nonce_conflict = false;
    for (dependencies) |dep| {
        if (dep.conflict_type == .nonce) {
            found_nonce_conflict = true;
            try testing.expect(std.mem.eql(u8, &dep.address, &addr_a));
            break;
        }
    }
    try testing.expect(found_nonce_conflict);
}

test "DependencyAnalyzer write-write conflicts" {
    const allocator = testing.allocator;

    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();

    const addr_a = [_]u8{0xAA} ** 20;
    const addr_b = [_]u8{0xBB} ** 20;
    const addr_c = [_]u8{0xCC} ** 20;

    // Create transactions targeting same address (write-write conflict)
    const transactions = [_]Transaction{
        Transaction{
            .from = addr_a,
            .to = addr_c,
            .value = BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        Transaction{
            .from = addr_b,
            .to = addr_c,
            .value = BigInt.init(50),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
    };

    const dependencies = try analyzer.analyzeDependencies(&transactions);

    // Should find write-write conflict
    try testing.expect(dependencies.len > 0);

    var found_write_conflict = false;
    for (dependencies) |dep| {
        if (dep.conflict_type == .write_write) {
            found_write_conflict = true;
            try testing.expect(std.mem.eql(u8, &dep.address, &addr_c));
            break;
        }
    }
    try testing.expect(found_write_conflict);
}

test "DependencyAnalyzer independent transactions" {
    const allocator = testing.allocator;

    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();

    // Create completely independent transactions
    const transactions = [_]Transaction{
        Transaction{
            .from = [_]u8{0x01} ** 20,
            .to = [_]u8{0x02} ** 20,
            .value = BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        Transaction{
            .from = [_]u8{0x03} ** 20,
            .to = [_]u8{0x04} ** 20,
            .value = BigInt.init(50),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
    };

    const dependencies = try analyzer.analyzeDependencies(&transactions);

    // Should find no dependencies
    try testing.expect(dependencies.len == 0);
}

test "ParallelScheduler creation and destruction" {
    const allocator = testing.allocator;

    var scheduler = try ParallelScheduler.init(allocator, 2);
    defer scheduler.deinit();

    try testing.expect(scheduler.thread_pool.threads.len == 2);
    try testing.expect(scheduler.execution_results.items.len == 0);
    try testing.expect(scheduler.pending_transactions.items.len == 0);
}

test "ParallelScheduler single transaction execution" {
    const allocator = testing.allocator;

    var scheduler = try ParallelScheduler.init(allocator, 1);
    defer scheduler.deinit();

    // Create a simple transaction
    const transactions = [_]Transaction{
        Transaction{
            .from = [_]u8{0x01} ** 20,
            .to = [_]u8{0x02} ** 20,
            .value = BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
    };

    const results = try scheduler.executeTransactionBatch(&transactions);

    try testing.expect(results.len == 1);
    // Note: The execution might not succeed due to account state issues,
    // but we should get a result
}

test "ParallelScheduler multiple independent transactions" {
    const allocator = testing.allocator;

    var scheduler = try ParallelScheduler.init(allocator, 2);
    defer scheduler.deinit();

    // Create independent transactions
    const transactions = [_]Transaction{
        Transaction{
            .from = [_]u8{0x01} ** 20,
            .to = [_]u8{0x02} ** 20,
            .value = BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        Transaction{
            .from = [_]u8{0x03} ** 20,
            .to = [_]u8{0x04} ** 20,
            .value = BigInt.init(50),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
    };

    const results = try scheduler.executeTransactionBatch(&transactions);

    try testing.expect(results.len == 2);

    // Both transactions should have been processed
    var tx0_found = false;
    var tx1_found = false;

    for (results) |result| {
        if (result.tx_id == 0) tx0_found = true;
        if (result.tx_id == 1) tx1_found = true;
    }

    try testing.expect(tx0_found);
    try testing.expect(tx1_found);
}

test "ConflictType enum values" {
    // Test that all conflict types are defined
    const write_write = ConflictType.write_write;
    const balance = ConflictType.balance;
    const nonce = ConflictType.nonce;

    // Just verify they exist and are different
    try testing.expect(write_write != balance);
    try testing.expect(balance != nonce);
    try testing.expect(nonce != write_write);
}

test "StateChange creation and cleanup" {
    const allocator = testing.allocator;

    var state_change = parallel.StateChange{
        .change_type = .balance,
        .address = [_]u8{0x01} ** 20,
        .key = null,
        .old_value = BigInt.init(100),
        .new_value = BigInt.init(200),
    };

    // Test cleanup (currently no-op, but tests the interface)
    state_change.deinit(allocator);
}

test "ExecutionResult creation and cleanup" {
    const allocator = testing.allocator;

    var result = parallel.ExecutionResult{
        .tx_id = 1,
        .success = true,
        .gas_used = 21000,
        .error_msg = null,
        .state_changes = std.ArrayList(parallel.StateChange){},
    };

    defer result.deinit(allocator);

    // Add a state change
    const state_change = parallel.StateChange{
        .change_type = .balance,
        .address = [_]u8{0x01} ** 20,
        .key = null,
        .old_value = BigInt.init(100),
        .new_value = BigInt.init(200),
    };

    try result.state_changes.append(allocator, state_change);

    try testing.expect(result.state_changes.items.len == 1);
    try testing.expect(result.success);
    try testing.expect(result.gas_used == 21000);
}

test "Dependency struct validation" {
    // Test dependency structure
    const dep = Dependency{
        .from_tx = 0,
        .to_tx = 1,
        .address = [_]u8{0xAA} ** 20,
        .conflict_type = .balance,
    };

    try testing.expect(dep.from_tx == 0);
    try testing.expect(dep.to_tx == 1);
    try testing.expect(dep.conflict_type == .balance);
}

test "Parallel execution performance characteristics" {
    const allocator = testing.allocator;

    // Test with different thread counts to verify scalability
    const thread_counts = [_]u32{ 1, 2, 4 };
    const transaction_count = 20;

    for (thread_counts) |thread_count| {
        var scheduler = try ParallelScheduler.init(allocator, thread_count);
        defer scheduler.deinit();

        // Create many independent transactions
        const transactions = try allocator.alloc(Transaction, transaction_count);
        defer allocator.free(transactions);

        for (transactions, 0..) |*tx, i| {
            var from_addr: [20]u8 = undefined;
            var to_addr: [20]u8 = undefined;
            @memset(&from_addr, 0);
            @memset(&to_addr, 0);
            from_addr[19] = @intCast((i * 2) % 255 + 1);
            to_addr[19] = @intCast((i * 2 + 1) % 255 + 1);

            tx.* = Transaction{
                .from = from_addr,
                .to = to_addr,
                .value = BigInt.init(100),
                .data = &[_]u8{},
                .gas_limit = 21000,
                .gas_price = BigInt.init(20000000000),
            };
        }

        const start_time = std.time.nanoTimestamp();
        const results = try scheduler.executeTransactionBatch(transactions);
        const end_time = std.time.nanoTimestamp();

        const execution_time = end_time - start_time;

        try testing.expect(results.len == transaction_count);
        try testing.expect(execution_time > 0);

        // Verify all transactions were processed
        var processed_count: u32 = 0;
        for (results) |result| {
            _ = result;
            processed_count += 1;
        }
        try testing.expect(processed_count == transaction_count);
    }
}

test "Complex dependency chain handling" {
    const allocator = testing.allocator;

    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();

    // Create a chain: A -> B -> C -> D
    const addr_a = [_]u8{0xAA} ** 20;
    const addr_b = [_]u8{0xBB} ** 20;
    const addr_c = [_]u8{0xCC} ** 20;
    const addr_d = [_]u8{0xDD} ** 20;

    const transactions = [_]Transaction{
        // TX 0: A -> B
        Transaction{
            .from = addr_a,
            .to = addr_b,
            .value = BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        // TX 1: B -> C
        Transaction{
            .from = addr_b,
            .to = addr_c,
            .value = BigInt.init(50),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        // TX 2: C -> D
        Transaction{
            .from = addr_c,
            .to = addr_d,
            .value = BigInt.init(25),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
    };

    const dependencies = try analyzer.analyzeDependencies(&transactions);

    // Should find dependencies: 0->1 and 1->2
    try testing.expect(dependencies.len >= 2);

    // Check for the specific dependency chain
    var found_0_to_1 = false;
    var found_1_to_2 = false;

    for (dependencies) |dep| {
        if (dep.from_tx == 0 and dep.to_tx == 1) found_0_to_1 = true;
        if (dep.from_tx == 1 and dep.to_tx == 2) found_1_to_2 = true;
    }

    try testing.expect(found_0_to_1);
    try testing.expect(found_1_to_2);
}

test "Memory safety in parallel execution" {
    const allocator = testing.allocator;

    // Test with a moderate number of transactions to stress test memory management
    const transaction_count = 50;

    var scheduler = try ParallelScheduler.init(allocator, 4);
    defer scheduler.deinit();

    const transactions = try allocator.alloc(Transaction, transaction_count);
    defer allocator.free(transactions);

    // Create a mix of dependent and independent transactions
    for (transactions, 0..) |*tx, i| {
        var from_addr: [20]u8 = undefined;
        var to_addr: [20]u8 = undefined;
        @memset(&from_addr, 0);
        @memset(&to_addr, 0);

        // Create some overlapping addresses to generate dependencies
        from_addr[19] = @intCast((i % 10) + 1);
        to_addr[19] = @intCast(((i + 5) % 10) + 1);

        tx.* = Transaction{
            .from = from_addr,
            .to = to_addr,
            .value = BigInt.init(100 + i),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        };
    }

    const results = try scheduler.executeTransactionBatch(transactions);

    // Verify all transactions were processed
    try testing.expect(results.len == transaction_count);

    // Check that no memory corruption occurred by verifying transaction IDs
    var id_check = try allocator.alloc(bool, transaction_count);
    defer allocator.free(id_check);
    @memset(id_check, false);

    for (results) |result| {
        try testing.expect(result.tx_id < transaction_count);
        id_check[result.tx_id] = true;
    }

    // All transaction IDs should be present
    for (id_check) |checked| {
        try testing.expect(checked);
    }
}