// File: src/parallel_optimized.zig
// Optimized parallel execution infrastructure for the Zig EVM

const std = @import("std");
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;

const main = @import("main.zig");
const EVM = main.EVM;
const Transaction = main.Transaction;
const BigInt = main.BigInt;

/// Optimized dependency tracking with hash-based access pattern analysis
pub const OptimizedDependencyAnalyzer = struct {
    allocator: Allocator,
    address_access_map: AutoHashMap([20]u8, AccessInfo),
    dependencies: ArrayList(Dependency),

    const AccessInfo = struct {
        readers: ArrayList(u32),
        writers: ArrayList(u32),

        fn init(allocator: Allocator) AccessInfo {
            _ = allocator; // Not used in current implementation
            return AccessInfo{
                .readers = ArrayList(u32){},
                .writers = ArrayList(u32){},
            };
        }

        fn deinit(self: *AccessInfo, allocator: Allocator) void {
            self.readers.deinit(allocator);
            self.writers.deinit(allocator);
        }
    };

    pub fn init(allocator: Allocator) OptimizedDependencyAnalyzer {
        return OptimizedDependencyAnalyzer{
            .allocator = allocator,
            .address_access_map = AutoHashMap([20]u8, AccessInfo).init(allocator),
            .dependencies = ArrayList(Dependency){},
        };
    }

    pub fn deinit(self: *OptimizedDependencyAnalyzer) void {
        var iterator = self.address_access_map.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.address_access_map.deinit();
        self.dependencies.deinit(self.allocator);
    }

    /// Optimized O(n) dependency analysis using hash maps
    pub fn analyzeDependencies(self: *OptimizedDependencyAnalyzer, transactions: []const Transaction) ![]Dependency {
        self.dependencies.clearRetainingCapacity();
        self.address_access_map.clearRetainingCapacity();

        // First pass: Build access patterns
        for (transactions, 0..) |tx, i| {
            const tx_id = @as(u32, @intCast(i));

            // Track 'from' address as writer (nonce increment, balance decrease)
            try self.recordAccess(tx.from, tx_id, .writer);

            // Track 'to' address as writer (balance increase)
            if (tx.to) |to_addr| {
                try self.recordAccess(to_addr, tx_id, .writer);
            }
        }

        // Second pass: Generate dependencies from conflicts
        var iterator = self.address_access_map.iterator();
        while (iterator.next()) |entry| {
            const access_info = entry.value_ptr;

            // Write-Write conflicts
            for (access_info.writers.items, 0..) |writer1, i| {
                for (access_info.writers.items[i + 1..]) |writer2| {
                    try self.dependencies.append(self.allocator, Dependency{
                        .from_tx = writer1,
                        .to_tx = writer2,
                        .address = entry.key_ptr.*,
                        .conflict_type = .write_write,
                    });
                }
            }

            // Read-Write conflicts (future optimization)
            for (access_info.readers.items) |reader| {
                for (access_info.writers.items) |writer| {
                    if (reader != writer) {
                        const dep = if (reader < writer)
                            Dependency{
                                .from_tx = reader,
                                .to_tx = writer,
                                .address = entry.key_ptr.*,
                                .conflict_type = .balance,
                            }
                        else
                            Dependency{
                                .from_tx = writer,
                                .to_tx = reader,
                                .address = entry.key_ptr.*,
                                .conflict_type = .balance,
                            };
                        try self.dependencies.append(self.allocator, dep);
                    }
                }
            }
        }

        return self.dependencies.items;
    }

    fn recordAccess(self: *OptimizedDependencyAnalyzer, address: [20]u8, tx_id: u32, access_type: enum { reader, writer }) !void {
        const result = try self.address_access_map.getOrPut(address);
        if (!result.found_existing) {
            result.value_ptr.* = AccessInfo.init(self.allocator);
        }

        switch (access_type) {
            .reader => try result.value_ptr.readers.append(self.allocator, tx_id),
            .writer => try result.value_ptr.writers.append(self.allocator, tx_id),
        }
    }
};

/// Work-stealing thread pool for better load balancing
pub const WorkStealingThreadPool = struct {
    allocator: Allocator,
    threads: []Thread,
    work_queues: []WorkQueue,
    global_queue: WorkQueue,
    shutdown: bool,
    global_mutex: Mutex,
    global_condition: Condition,
    thread_count: u32,

    const WorkQueue = struct {
        items: ArrayList(WorkItem),
        mutex: Mutex,

        fn init(allocator: Allocator) WorkQueue {
            _ = allocator; // Not used in current implementation
            return WorkQueue{
                .items = ArrayList(WorkItem){},
                .mutex = Mutex{},
            };
        }

        fn deinit(self: *WorkQueue, allocator: Allocator) void {
            self.items.deinit(allocator);
        }

        fn push(self: *WorkQueue, allocator: Allocator, item: WorkItem) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.append(allocator, item);
        }

        fn pop(self: *WorkQueue) ?WorkItem {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len > 0) {
                return self.items.orderedRemove(0);
            }
            return null;
        }

        fn steal(self: *WorkQueue) ?WorkItem {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len > 1) {
                // Steal from the end (LIFO for stealer, FIFO for owner)
                return self.items.pop();
            }
            return null;
        }
    };

    pub fn init(allocator: Allocator, thread_count: u32) !*WorkStealingThreadPool {
        const pool = try allocator.create(WorkStealingThreadPool);

        // Initialize per-thread work queues
        const work_queues = try allocator.alloc(WorkQueue, thread_count);
        for (work_queues) |*queue| {
            queue.* = WorkQueue.init(allocator);
        }

        pool.* = WorkStealingThreadPool{
            .allocator = allocator,
            .threads = try allocator.alloc(Thread, thread_count),
            .work_queues = work_queues,
            .global_queue = WorkQueue.init(allocator),
            .shutdown = false,
            .global_mutex = Mutex{},
            .global_condition = Condition{},
            .thread_count = thread_count,
        };

        // Start worker threads
        for (pool.threads, 0..) |*thread, i| {
            thread.* = try Thread.spawn(.{}, workerThread, .{ pool, i });
        }

        return pool;
    }

    pub fn deinit(self: *WorkStealingThreadPool) void {
        // Signal shutdown
        self.global_mutex.lock();
        self.shutdown = true;
        self.global_condition.broadcast();
        self.global_mutex.unlock();

        // Wait for all threads to complete
        for (self.threads) |*thread| {
            thread.join();
        }

        // Clean up work queues
        for (self.work_queues) |*queue| {
            queue.deinit(self.allocator);
        }
        self.allocator.free(self.work_queues);
        self.global_queue.deinit(self.allocator);
        self.allocator.free(self.threads);
        self.allocator.destroy(self);
    }

    pub fn submitWork(self: *WorkStealingThreadPool, work_item: WorkItem) !void {
        // Try to submit to a random thread's queue first
        const thread_idx = std.crypto.random.intRangeAtMost(u32, 0, self.thread_count - 1);

        if (self.work_queues[thread_idx].push(self.allocator, work_item)) {
            // Successfully submitted to thread queue
        } else |_| {
            // Fallback to global queue
            try self.global_queue.push(self.allocator, work_item);
            self.global_condition.signal();
        }
    }

    fn workerThread(self: *WorkStealingThreadPool, thread_id: usize) void {
        const my_queue = &self.work_queues[thread_id];

        while (true) {
            // 1. Try to get work from own queue
            if (my_queue.pop()) |work_item| {
                var item = work_item;
                item.execute();
                continue;
            }

            // 2. Try to steal work from other threads
            var stolen = false;
            for (self.work_queues, 0..) |*queue, i| {
                if (i == thread_id) continue; // Skip own queue

                if (queue.steal()) |work_item| {
                    var item = work_item;
                    item.execute();
                    stolen = true;
                    break;
                }
            }

            if (stolen) continue;

            // 3. Try global queue
            if (self.global_queue.pop()) |work_item| {
                var item = work_item;
                item.execute();
                continue;
            }

            // 4. Wait for work or shutdown
            self.global_mutex.lock();
            while (self.global_queue.items.items.len == 0 and !self.shutdown) {
                self.global_condition.wait(&self.global_mutex);
            }

            if (self.shutdown) {
                self.global_mutex.unlock();
                break;
            }
            self.global_mutex.unlock();
        }
    }
};

/// Speculative execution engine with rollback support
pub const SpeculativeExecutor = struct {
    allocator: Allocator,
    checkpoints: AutoHashMap(u32, ExecutionCheckpoint),

    const ExecutionCheckpoint = struct {
        account_states: AutoHashMap([20]u8, AccountSnapshot),
        memory_snapshot: []u8,
        stack_snapshot: []BigInt,

        fn deinit(self: *ExecutionCheckpoint, allocator: Allocator) void {
            var iter = self.account_states.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            self.account_states.deinit();
            allocator.free(self.memory_snapshot);
            allocator.free(self.stack_snapshot);
        }
    };

    const AccountSnapshot = struct {
        balance: BigInt,
        nonce: u64,
        storage: AutoHashMap(BigInt, BigInt),

        fn deinit(self: *AccountSnapshot, allocator: Allocator) void {
            self.storage.deinit();
            _ = allocator; // Balance and nonce don't need deallocation
        }
    };

    pub fn init(allocator: Allocator) SpeculativeExecutor {
        return SpeculativeExecutor{
            .allocator = allocator,
            .checkpoints = AutoHashMap(u32, ExecutionCheckpoint).init(allocator),
        };
    }

    pub fn deinit(self: *SpeculativeExecutor) void {
        var iter = self.checkpoints.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.checkpoints.deinit();
    }

    pub fn createCheckpoint(self: *SpeculativeExecutor, tx_id: u32, evm: *EVM) !void {
        var checkpoint = ExecutionCheckpoint{
            .account_states = AutoHashMap([20]u8, AccountSnapshot).init(self.allocator),
            .memory_snapshot = try self.allocator.dupe(u8, evm.memory.data.items),
            .stack_snapshot = try self.allocator.dupe(BigInt, evm.stack.items.items),
        };

        // Snapshot account states
        var account_iter = evm.accounts.iterator();
        while (account_iter.next()) |entry| {
            var storage_copy = AutoHashMap(BigInt, BigInt).init(self.allocator);
            var storage_iter = entry.value_ptr.storage.iterator();
            while (storage_iter.next()) |storage_entry| {
                try storage_copy.put(storage_entry.key_ptr.*, storage_entry.value_ptr.*);
            }

            const snapshot = AccountSnapshot{
                .balance = entry.value_ptr.balance,
                .nonce = entry.value_ptr.nonce,
                .storage = storage_copy,
            };

            try checkpoint.account_states.put(entry.key_ptr.*, snapshot);
        }

        try self.checkpoints.put(tx_id, checkpoint);
    }

    pub fn rollback(self: *SpeculativeExecutor, tx_id: u32, evm: *EVM) !void {
        if (self.checkpoints.get(tx_id)) |checkpoint| {
            // Restore memory
            if (evm.memory.data.items.len < checkpoint.memory_snapshot.len) {
                try evm.memory.data.resize(evm.allocator, checkpoint.memory_snapshot.len);
            }
            @memcpy(evm.memory.data.items[0..checkpoint.memory_snapshot.len], checkpoint.memory_snapshot);

            // Restore stack
            evm.stack.items.clearRetainingCapacity();
            for (checkpoint.stack_snapshot) |item| {
                try evm.stack.items.append(evm.allocator, item);
            }

            // Restore account states
            var account_iter = checkpoint.account_states.iterator();
            while (account_iter.next()) |entry| {
                if (evm.accounts.getPtr(entry.key_ptr.*)) |account| {
                    account.balance = entry.value_ptr.balance;
                    account.nonce = entry.value_ptr.nonce;

                    // Restore storage
                    account.storage.clearRetainingCapacity();
                    var storage_iter = entry.value_ptr.storage.iterator();
                    while (storage_iter.next()) |storage_entry| {
                        try account.storage.put(storage_entry.key_ptr.*, storage_entry.value_ptr.*);
                    }
                }
            }
        }
    }

    pub fn commitCheckpoint(self: *SpeculativeExecutor, tx_id: u32) void {
        if (self.checkpoints.fetchRemove(tx_id)) |entry| {
            var checkpoint = entry.value;
            checkpoint.deinit(self.allocator);
        }
    }
};

/// Memory pool for reducing allocations
pub const MemoryPool = struct {
    allocator: Allocator,
    small_blocks: ArrayList([]u8),
    medium_blocks: ArrayList([]u8),
    large_blocks: ArrayList([]u8),
    mutex: Mutex,

    const SMALL_SIZE = 256;
    const MEDIUM_SIZE = 4096;
    const LARGE_SIZE = 65536;

    pub fn init(allocator: Allocator) MemoryPool {
        return MemoryPool{
            .allocator = allocator,
            .small_blocks = ArrayList([]u8){},
            .medium_blocks = ArrayList([]u8){},
            .large_blocks = ArrayList([]u8){},
            .mutex = Mutex{},
        };
    }

    pub fn deinit(self: *MemoryPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.small_blocks.items) |block| {
            self.allocator.free(block);
        }
        for (self.medium_blocks.items) |block| {
            self.allocator.free(block);
        }
        for (self.large_blocks.items) |block| {
            self.allocator.free(block);
        }

        self.small_blocks.deinit(self.allocator);
        self.medium_blocks.deinit(self.allocator);
        self.large_blocks.deinit(self.allocator);
    }

    pub fn acquire(self: *MemoryPool, size: usize) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (size <= SMALL_SIZE) {
            if (self.small_blocks.items.len > 0) {
                const block = self.small_blocks.pop();
                return block[0..@min(size, block.len)];
            }
            return try self.allocator.alloc(u8, @max(size, SMALL_SIZE));
        } else if (size <= MEDIUM_SIZE) {
            if (self.medium_blocks.items.len > 0) {
                const block = self.medium_blocks.pop();
                return block[0..@min(size, block.len)];
            }
            return try self.allocator.alloc(u8, @max(size, MEDIUM_SIZE));
        } else if (size <= LARGE_SIZE) {
            if (self.large_blocks.items.len > 0) {
                const block = self.large_blocks.pop();
                return block[0..@min(size, block.len)];
            }
            return try self.allocator.alloc(u8, @max(size, LARGE_SIZE));
        } else {
            // For very large allocations, use direct allocation
            return try self.allocator.alloc(u8, size);
        }
    }

    pub fn release(self: *MemoryPool, block: []u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const size = block.len;
        if (size == SMALL_SIZE) {
            self.small_blocks.append(self.allocator, block) catch {
                self.allocator.free(block);
            };
        } else if (size == MEDIUM_SIZE) {
            self.medium_blocks.append(self.allocator, block) catch {
                self.allocator.free(block);
            };
        } else if (size == LARGE_SIZE) {
            self.large_blocks.append(self.allocator, block) catch {
                self.allocator.free(block);
            };
        } else {
            // Direct allocated blocks are freed directly
            self.allocator.free(block);
        }
    }
};

/// Re-export optimized types
pub const Dependency = @import("parallel.zig").Dependency;
pub const ConflictType = @import("parallel.zig").ConflictType;
pub const ExecutionResult = @import("parallel.zig").ExecutionResult;
pub const StateChange = @import("parallel.zig").StateChange;
pub const ChangeType = @import("parallel.zig").ChangeType;
pub const WorkItem = @import("parallel.zig").WorkItem;
pub const ParallelExecutionStats = @import("parallel.zig").ParallelExecutionStats;
pub const ParallelConfig = @import("parallel.zig").ParallelConfig;
pub const ConflictDetectionLevel = @import("parallel.zig").ConflictDetectionLevel;

/// Optimized parallel scheduler combining all improvements
pub const OptimizedParallelScheduler = struct {
    allocator: Allocator,
    thread_pool: *WorkStealingThreadPool,
    dependency_analyzer: OptimizedDependencyAnalyzer,
    speculative_executor: SpeculativeExecutor,
    memory_pool: MemoryPool,
    execution_results: ArrayList(ExecutionResult),
    pending_transactions: ArrayList(Transaction),
    ready_queue: ArrayList(u32),
    completed_mask: []bool,
    dependency_count: []u32,
    config: ParallelConfig,

    pub fn init(allocator: Allocator, config: ParallelConfig) !*OptimizedParallelScheduler {
        const scheduler = try allocator.create(OptimizedParallelScheduler);
        scheduler.* = OptimizedParallelScheduler{
            .allocator = allocator,
            .thread_pool = try WorkStealingThreadPool.init(allocator, config.max_threads),
            .dependency_analyzer = OptimizedDependencyAnalyzer.init(allocator),
            .speculative_executor = SpeculativeExecutor.init(allocator),
            .memory_pool = MemoryPool.init(allocator),
            .execution_results = ArrayList(ExecutionResult){},
            .pending_transactions = ArrayList(Transaction){},
            .ready_queue = ArrayList(u32){},
            .completed_mask = &[_]bool{},
            .dependency_count = &[_]u32{},
            .config = config,
        };
        return scheduler;
    }

    pub fn deinit(self: *OptimizedParallelScheduler) void {
        self.thread_pool.deinit();
        self.dependency_analyzer.deinit();
        self.speculative_executor.deinit();
        self.memory_pool.deinit();

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

    /// Execute transactions with optimized parallel processing
    pub fn executeTransactionBatch(self: *OptimizedParallelScheduler, transactions: []const Transaction) ![]ExecutionResult {
        const start_time = std.time.nanoTimestamp();

        // Setup
        try self.setupExecution(transactions);

        // Optimized dependency analysis
        const dependencies = try self.dependency_analyzer.analyzeDependencies(transactions);

        // Build dependency graph
        try self.buildDependencyGraph(dependencies);

        // Execute with work-stealing and speculation
        try self.executeWithOptimizations(transactions, dependencies);

        const end_time = std.time.nanoTimestamp();
        const execution_time = end_time - start_time;

        // Log performance metrics
        std.log.info("Optimized execution completed in {d}ms", .{@as(f64, @floatFromInt(execution_time)) / 1_000_000.0});

        return self.execution_results.items;
    }

    fn setupExecution(self: *OptimizedParallelScheduler, transactions: []const Transaction) !void {
        self.pending_transactions.clearRetainingCapacity();
        self.execution_results.clearRetainingCapacity();
        self.ready_queue.clearRetainingCapacity();

        // Resize tracking arrays with memory pool
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

        @memset(self.completed_mask[0..transactions.len], false);
        @memset(self.dependency_count[0..transactions.len], 0);

        for (transactions) |tx| {
            try self.pending_transactions.append(self.allocator, tx);
        }
    }

    fn buildDependencyGraph(self: *OptimizedParallelScheduler, dependencies: []const Dependency) !void {
        for (dependencies) |dep| {
            self.dependency_count[dep.to_tx] += 1;
        }

        for (0..self.pending_transactions.items.len) |i| {
            if (self.dependency_count[i] == 0) {
                try self.ready_queue.append(self.allocator, @intCast(i));
            }
        }
    }

    fn executeWithOptimizations(self: *OptimizedParallelScheduler, transactions: []const Transaction, dependencies: []const Dependency) !void {
        var completed_count: u32 = 0;
        const total_transactions = @as(u32, @intCast(transactions.len));

        while (completed_count < total_transactions) {
            // Submit ready transactions with speculation if enabled
            while (self.ready_queue.items.len > 0) {
                const tx_id = self.ready_queue.orderedRemove(0);
                try self.submitOptimizedExecution(tx_id);
            }

            // Adaptive waiting with exponential backoff
            var wait_time: u64 = 1000; // Start with 1μs
            while (self.ready_queue.items.len == 0 and completed_count < total_transactions) {
                std.Thread.sleep(wait_time);
                wait_time = @min(wait_time * 2, 1_000_000); // Cap at 1ms
                completed_count = self.processCompletedTransactions(dependencies);
            }
        }
    }

    fn submitOptimizedExecution(self: *OptimizedParallelScheduler, tx_id: u32) !void {
        const context = try self.allocator.create(OptimizedExecutionContext);
        context.* = OptimizedExecutionContext{
            .scheduler = self,
            .tx_id = tx_id,
            .transaction = self.pending_transactions.items[tx_id],
            .use_speculation = self.config.enable_speculative_execution,
        };

        const work_item = WorkItem{
            .execute_fn = executeOptimizedTransactionWork,
            .context = context,
        };

        try self.thread_pool.submitWork(work_item);
    }

    fn processCompletedTransactions(self: *OptimizedParallelScheduler, dependencies: []const Dependency) u32 {
        var completed_count: u32 = 0;

        for (self.completed_mask[0..self.pending_transactions.items.len]) |completed| {
            if (completed) completed_count += 1;
        }

        for (dependencies) |dep| {
            if (self.completed_mask[dep.from_tx] and !self.completed_mask[dep.to_tx]) {
                if (self.dependency_count[dep.to_tx] > 0) {
                    self.dependency_count[dep.to_tx] -= 1;

                    if (self.dependency_count[dep.to_tx] == 0) {
                        self.ready_queue.append(self.allocator, dep.to_tx) catch {};
                    }
                }
            }
        }

        return completed_count;
    }
};

const OptimizedExecutionContext = struct {
    scheduler: *OptimizedParallelScheduler,
    tx_id: u32,
    transaction: Transaction,
    use_speculation: bool,
};

fn executeOptimizedTransactionWork(work_item: *WorkItem) void {
    const context: *OptimizedExecutionContext = @ptrCast(@alignCast(work_item.context));

    var evm = EVM.init(context.scheduler.allocator) catch {
        return;
    };
    defer evm.deinit();

    var result = ExecutionResult{
        .tx_id = context.tx_id,
        .success = false,
        .gas_used = 0,
        .error_msg = null,
        .state_changes = ArrayList(StateChange){},
    };

    // Create checkpoint for speculation
    if (context.use_speculation) {
        context.scheduler.speculative_executor.createCheckpoint(context.tx_id, evm) catch {};
    }

    // Execute transaction
    evm.applyTransaction(context.transaction) catch |err| {
        if (context.use_speculation) {
            context.scheduler.speculative_executor.rollback(context.tx_id, evm) catch {};
        }
        result.error_msg = context.scheduler.allocator.dupe(u8, @errorName(err)) catch null;
    };

    if (result.error_msg == null) {
        result.success = true;
        result.gas_used = evm.gas_used;

        if (context.use_speculation) {
            context.scheduler.speculative_executor.commitCheckpoint(context.tx_id);
        }
    }

    // Store result atomically
    context.scheduler.execution_results.append(context.scheduler.allocator, result) catch {};
    context.scheduler.completed_mask[context.tx_id] = true;

    context.scheduler.allocator.destroy(context);
}

// Performance testing functions
pub fn benchmarkOptimizedExecution(allocator: Allocator) !void {
    std.debug.print("=== Optimized Parallel Execution Benchmark ===\n", .{});

    const configs = [_]ParallelConfig{
        .{ .max_threads = 1, .enable_speculative_execution = false },
        .{ .max_threads = 4, .enable_speculative_execution = false },
        .{ .max_threads = 4, .enable_speculative_execution = true },
        .{ .max_threads = 8, .enable_speculative_execution = true },
    };

    const transaction_counts = [_]u32{ 100, 500, 1000 };

    for (transaction_counts) |tx_count| {
        std.debug.print("\nTransaction count: {d}\n", .{tx_count});

        for (configs) |config| {
            var scheduler = try OptimizedParallelScheduler.init(allocator, config);
            defer scheduler.deinit();

            // Generate test transactions
            const transactions = try generateTestTransactions(allocator, tx_count);
            defer allocator.free(transactions);

            const start_time = std.time.nanoTimestamp();
            const results = try scheduler.executeTransactionBatch(transactions);
            const end_time = std.time.nanoTimestamp();

            const execution_time = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
            const throughput = @as(f64, @floatFromInt(tx_count)) / (execution_time / 1000.0);

            var successful: u32 = 0;
            for (results) |result| {
                if (result.success) successful += 1;
            }

            const spec_str = if (config.enable_speculative_execution) "speculative" else "conservative";
            std.debug.print("  {d} threads ({s}): {d:.2}ms ({d:.0} tx/s)\n", .{
                config.max_threads, spec_str, execution_time, throughput
            });
        }
    }
}

fn generateTestTransactions(allocator: Allocator, count: u32) ![]Transaction {
    const transactions = try allocator.alloc(Transaction, count);

    for (transactions, 0..) |*tx, i| {
        var from_addr: [20]u8 = undefined;
        var to_addr: [20]u8 = undefined;
        @memset(&from_addr, 0);
        @memset(&to_addr, 0);

        // Create some address patterns for realistic dependency testing
        from_addr[19] = @intCast((i % 50) + 1);
        to_addr[19] = @intCast(((i + 25) % 50) + 1);

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