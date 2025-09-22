// File: src/parallel.zig
// Parallel execution infrastructure for the Zig EVM

const std = @import("std");
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const main = @import("main.zig");
const EVM = main.EVM;
const Transaction = main.Transaction;
const BigInt = main.BigInt;

/// Represents a dependency between two transactions
pub const Dependency = struct {
    from_tx: u32, // Transaction ID that must complete first
    to_tx: u32,   // Transaction ID that depends on the first
    address: [20]u8, // Address that creates the dependency
    conflict_type: ConflictType,
};

/// Types of conflicts that can occur between transactions
pub const ConflictType = enum {
    write_write, // Both transactions write to same storage
    balance,     // Balance modification conflicts
    nonce,       // Nonce conflicts
};

/// Execution result for a single transaction
pub const ExecutionResult = struct {
    tx_id: u32,
    success: bool,
    gas_used: u64,
    error_msg: ?[]const u8,
    state_changes: ArrayList(StateChange),

    pub fn deinit(self: *ExecutionResult, allocator: Allocator) void {
        if (self.error_msg) |msg| {
            allocator.free(msg);
        }
        for (self.state_changes.items) |*change| {
            change.deinit(allocator);
        }
        self.state_changes.deinit(allocator);
    }
};

/// Represents a state change made by a transaction
pub const StateChange = struct {
    change_type: ChangeType,
    address: [20]u8,
    key: ?BigInt, // Storage key (null for balance changes)
    old_value: BigInt,
    new_value: BigInt,

    pub fn deinit(self: *StateChange, allocator: Allocator) void {
        _ = self;
        _ = allocator; // Currently no dynamic allocations in StateChange
    }
};

/// Types of state changes
pub const ChangeType = enum {
    balance,
    storage,
    nonce,
    code,
};

/// Thread pool for parallel transaction execution
pub const ThreadPool = struct {
    allocator: Allocator,
    threads: []Thread,
    work_queue: WorkQueue,
    shutdown: bool,
    mutex: Mutex,
    condition: Condition,

    pub fn init(allocator: Allocator, thread_count: u32) !*ThreadPool {
        const pool = try allocator.create(ThreadPool);
        pool.* = ThreadPool{
            .allocator = allocator,
            .threads = try allocator.alloc(Thread, thread_count),
            .work_queue = ArrayList(WorkItem){},
            .shutdown = false,
            .mutex = Mutex{},
            .condition = Condition{},
        };

        // Start worker threads
        for (pool.threads, 0..) |*thread, i| {
            thread.* = try Thread.spawn(.{}, workerThread, .{ pool, i });
        }

        return pool;
    }

    pub fn deinit(self: *ThreadPool) void {
        // Signal shutdown
        self.mutex.lock();
        self.shutdown = true;
        self.condition.broadcast();
        self.mutex.unlock();

        // Wait for all threads to complete
        for (self.threads) |*thread| {
            thread.join();
        }

        self.work_queue.deinit(self.allocator);
        self.allocator.free(self.threads);
        self.allocator.destroy(self);
    }

    pub fn submitWork(self: *ThreadPool, work_item: WorkItem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.work_queue.append(self.allocator, work_item);
        self.condition.signal();
    }

    fn workerThread(self: *ThreadPool, thread_id: usize) void {
        _ = thread_id; // For future use in logging/debugging

        while (true) {
            self.mutex.lock();

            // Wait for work or shutdown signal
            while (self.work_queue.items.len == 0 and !self.shutdown) {
                self.condition.wait(&self.mutex);
            }

            if (self.shutdown) {
                self.mutex.unlock();
                break;
            }

            // Get work item
            var work_item = self.work_queue.orderedRemove(0);
            self.mutex.unlock();

            // Execute the work
            work_item.execute();
        }
    }
};

/// Work queue for managing pending tasks
const WorkQueue = ArrayList(WorkItem);

/// Represents a unit of work for the thread pool
pub const WorkItem = struct {
    execute_fn: *const fn (*WorkItem) void,
    context: *anyopaque,

    pub fn execute(self: *WorkItem) void {
        self.execute_fn(self);
    }
};

/// Dependency analyzer for detecting conflicts between transactions
pub const DependencyAnalyzer = struct {
    allocator: Allocator,
    dependencies: ArrayList(Dependency),

    pub fn init(allocator: Allocator) DependencyAnalyzer {
        return DependencyAnalyzer{
            .allocator = allocator,
            .dependencies = ArrayList(Dependency){},
        };
    }

    pub fn deinit(self: *DependencyAnalyzer) void {
        self.dependencies.deinit(self.allocator);
    }

    /// Analyze a batch of transactions and identify dependencies
    pub fn analyzeDependencies(self: *DependencyAnalyzer, transactions: []const Transaction) ![]Dependency {
        self.dependencies.clearRetainingCapacity();

        // Simple O(n²) analysis - can be optimized with hash maps for larger batches
        for (transactions, 0..) |tx1, i| {
            for (transactions[i + 1 ..], i + 1..) |tx2, j| {
                if (try self.detectConflict(tx1, tx2, @intCast(i), @intCast(j))) |dependency| {
                    try self.dependencies.append(self.allocator, dependency);
                }
            }
        }

        return self.dependencies.items;
    }

    /// Detect if two transactions have a conflict
    fn detectConflict(self: *DependencyAnalyzer, tx1: Transaction, tx2: Transaction, id1: u32, id2: u32) !?Dependency {
        _ = self; // Not used currently

        // Check for address conflicts (both transactions affect same account)
        if (tx1.to != null and tx2.to != null) {
            if (std.mem.eql(u8, &tx1.to.?, &tx2.to.?)) {
                return Dependency{
                    .from_tx = id1,
                    .to_tx = id2,
                    .address = tx1.to.?,
                    .conflict_type = .write_write,
                };
            }
        }

        // Check if one transaction's 'from' matches another's 'to' (balance dependency)
        if (tx2.to != null and std.mem.eql(u8, &tx1.from, &tx2.to.?)) {
            return Dependency{
                .from_tx = id1,
                .to_tx = id2,
                .address = tx1.from,
                .conflict_type = .balance,
            };
        }

        if (tx1.to != null and std.mem.eql(u8, &tx2.from, &tx1.to.?)) {
            return Dependency{
                .from_tx = id1,
                .to_tx = id2,
                .address = tx2.from,
                .conflict_type = .balance,
            };
        }

        // Check for same sender (nonce dependency)
        if (std.mem.eql(u8, &tx1.from, &tx2.from)) {
            return Dependency{
                .from_tx = id1,
                .to_tx = id2,
                .address = tx1.from,
                .conflict_type = .nonce,
            };
        }

        return null;
    }
};

/// Parallel execution scheduler
pub const ParallelScheduler = struct {
    allocator: Allocator,
    thread_pool: *ThreadPool,
    dependency_analyzer: DependencyAnalyzer,
    execution_results: ArrayList(ExecutionResult),
    pending_transactions: ArrayList(Transaction),
    ready_queue: ArrayList(u32), // Transaction IDs ready for execution
    completed_mask: []bool, // Track which transactions completed
    dependency_count: []u32, // How many dependencies each transaction has

    pub fn init(allocator: Allocator, thread_count: u32) !*ParallelScheduler {
        const scheduler = try allocator.create(ParallelScheduler);
        scheduler.* = ParallelScheduler{
            .allocator = allocator,
            .thread_pool = try ThreadPool.init(allocator, thread_count),
            .dependency_analyzer = DependencyAnalyzer.init(allocator),
            .execution_results = ArrayList(ExecutionResult){},
            .pending_transactions = ArrayList(Transaction){},
            .ready_queue = ArrayList(u32){},
            .completed_mask = &[_]bool{},
            .dependency_count = &[_]u32{},
        };
        return scheduler;
    }

    pub fn deinit(self: *ParallelScheduler) void {
        self.thread_pool.deinit();
        self.dependency_analyzer.deinit();

        for (self.execution_results.items) |*result| {
            result.deinit(self.allocator);
        }
        self.execution_results.deinit(self.allocator);
        self.pending_transactions.deinit(self.allocator);
        self.ready_queue.deinit(self.allocator);

        if (self.completed_mask.len > 0) {
            self.allocator.free(self.completed_mask);
        }
        if (self.dependency_count.len > 0) {
            self.allocator.free(self.dependency_count);
        }

        self.allocator.destroy(self);
    }

    /// Execute a batch of transactions in parallel
    pub fn executeTransactionBatch(self: *ParallelScheduler, transactions: []const Transaction) ![]ExecutionResult {
        // Clear previous state
        self.pending_transactions.clearRetainingCapacity();
        self.execution_results.clearRetainingCapacity();
        self.ready_queue.clearRetainingCapacity();

        // Resize tracking arrays
        if (self.completed_mask.len < transactions.len) {
            if (self.completed_mask.len > 0) {
                self.allocator.free(self.completed_mask);
            }
            self.completed_mask = try self.allocator.alloc(bool, transactions.len);
        }

        if (self.dependency_count.len < transactions.len) {
            if (self.dependency_count.len > 0) {
                self.allocator.free(self.dependency_count);
            }
            self.dependency_count = try self.allocator.alloc(u32, transactions.len);
        }

        // Initialize tracking arrays
        @memset(self.completed_mask[0..transactions.len], false);
        @memset(self.dependency_count[0..transactions.len], 0);

        // Copy transactions
        for (transactions) |tx| {
            try self.pending_transactions.append(self.allocator, tx);
        }

        // Analyze dependencies
        const dependencies = try self.dependency_analyzer.analyzeDependencies(transactions);

        // Build dependency count for each transaction
        for (dependencies) |dep| {
            self.dependency_count[dep.to_tx] += 1;
        }

        // Find transactions with no dependencies (ready to execute)
        for (0..transactions.len) |i| {
            if (self.dependency_count[i] == 0) {
                try self.ready_queue.append(self.allocator, @intCast(i));
            }
        }

        // Execute transactions
        var completed_count: u32 = 0;
        while (completed_count < transactions.len) {
            // Submit ready transactions to thread pool
            while (self.ready_queue.items.len > 0) {
                const tx_id = self.ready_queue.orderedRemove(0);
                try self.submitTransactionExecution(tx_id);
            }

            // Wait for at least one transaction to complete
            // In a real implementation, this would use proper synchronization
            std.Thread.sleep(1000000); // 1ms sleep - replace with proper sync

            // Check for completed transactions and update dependencies
            completed_count = self.processCompletedTransactions(dependencies);
        }

        return self.execution_results.items;
    }

    fn submitTransactionExecution(self: *ParallelScheduler, tx_id: u32) !void {
        // Create execution context
        const context = try self.allocator.create(TransactionExecutionContext);
        context.* = TransactionExecutionContext{
            .scheduler = self,
            .tx_id = tx_id,
            .transaction = self.pending_transactions.items[tx_id],
        };

        // Create work item
        const work_item = WorkItem{
            .execute_fn = executeTransactionWork,
            .context = context,
        };

        try self.thread_pool.submitWork(work_item);
    }

    fn processCompletedTransactions(self: *ParallelScheduler, dependencies: []const Dependency) u32 {
        var completed_count: u32 = 0;

        // Count completed transactions
        for (self.completed_mask[0..self.pending_transactions.items.len]) |completed| {
            if (completed) completed_count += 1;
        }

        // Update dependency counts for newly ready transactions
        for (dependencies) |dep| {
            if (self.completed_mask[dep.from_tx] and !self.completed_mask[dep.to_tx]) {
                if (self.dependency_count[dep.to_tx] > 0) {
                    self.dependency_count[dep.to_tx] -= 1;

                    // If all dependencies satisfied, add to ready queue
                    if (self.dependency_count[dep.to_tx] == 0) {
                        self.ready_queue.append(self.allocator, dep.to_tx) catch {};
                    }
                }
            }
        }

        return completed_count;
    }
};

/// Context for executing a single transaction
const TransactionExecutionContext = struct {
    scheduler: *ParallelScheduler,
    tx_id: u32,
    transaction: Transaction,
};

/// Work function for executing a transaction
fn executeTransactionWork(work_item: *WorkItem) void {
    const context: *TransactionExecutionContext = @ptrCast(@alignCast(work_item.context));

    // Create isolated EVM instance for this transaction
    var evm = EVM.init(context.scheduler.allocator) catch {
        // Handle allocation error - could log this in a real implementation
        return;
    };
    defer evm.deinit();

    // Set up transaction context
    evm.current_transaction = context.transaction;
    evm.caller_address = context.transaction.from;
    if (context.transaction.to) |to| {
        evm.current_address = to;
    }

    // Execute transaction
    var result = ExecutionResult{
        .tx_id = context.tx_id,
        .success = false,
        .gas_used = 0,
        .error_msg = null,
        .state_changes = ArrayList(StateChange){},
    };

    // Apply and execute transaction
    evm.applyTransaction(context.transaction) catch |err| {
        result.error_msg = context.scheduler.allocator.dupe(u8, @errorName(err)) catch null;
    };

    if (result.error_msg == null) {
        result.success = true;
        result.gas_used = evm.gas_used;

        // Capture state changes (simplified for now)
        // In a real implementation, this would track all state modifications
    }

    // Store result and mark as completed
    context.scheduler.execution_results.append(context.scheduler.allocator, result) catch {};
    context.scheduler.completed_mask[context.tx_id] = true;

    // Clean up context
    context.scheduler.allocator.destroy(context);
}

/// Statistics for parallel execution performance
pub const ParallelExecutionStats = struct {
    total_transactions: u32,
    parallel_transactions: u32,
    sequential_transactions: u32,
    total_execution_time_ms: u64,
    average_transaction_time_ms: f64,
    parallelism_efficiency: f64, // % of theoretical maximum parallelism achieved
    thread_utilization: []f64, // Per-thread utilization percentages

    pub fn deinit(self: *ParallelExecutionStats, allocator: Allocator) void {
        if (self.thread_utilization.len > 0) {
            allocator.free(self.thread_utilization);
        }
    }
};

/// Configuration for parallel execution
pub const ParallelConfig = struct {
    max_threads: u32 = 4,
    batch_size: u32 = 100,
    dependency_lookahead: u32 = 50, // How many transactions ahead to analyze for dependencies
    enable_speculative_execution: bool = false,
    enable_state_snapshots: bool = true,
    conflict_detection_level: ConflictDetectionLevel = .medium,
};

/// Levels of conflict detection granularity
pub const ConflictDetectionLevel = enum {
    basic,   // Only address-level conflicts
    medium,  // Address + storage key conflicts
    precise, // Full state access tracking
};

test "dependency analyzer basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();

    // Create test transactions
    const addr1 = [_]u8{1} ** 20;
    const addr2 = [_]u8{2} ** 20;

    const transactions = [_]Transaction{
        Transaction{
            .from = addr1,
            .to = addr2,
            .value = BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
        Transaction{
            .from = addr2,
            .to = addr1,
            .value = BigInt.init(50),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = BigInt.init(20000000000),
        },
    };

    const dependencies = try analyzer.analyzeDependencies(&transactions);

    // Should find at least one dependency (balance conflict)
    try testing.expect(dependencies.len > 0);
}

test "thread pool basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var pool = try ThreadPool.init(allocator, 2);
    defer pool.deinit();

    // Test that pool was created successfully
    try testing.expect(pool.threads.len == 2);
    try testing.expect(!pool.shutdown);
}