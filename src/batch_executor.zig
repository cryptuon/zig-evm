// File: src/batch_executor.zig
// Unified batch execution for parallel transaction processing
// Provides FFI-friendly interface for executing transaction batches

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Atomic = std.atomic.Value;

const main = @import("main.zig");
const EVM = main.EVM;
const BigInt = main.BigInt;
const Account = main.Account;
const parallel = @import("parallel.zig");
const parallel_opt = @import("parallel_optimized.zig");

// ============================================================
// Transaction Types for Batch Execution
// ============================================================

/// Transaction input for batch execution (FFI-friendly)
pub const BatchTransaction = struct {
    /// Sender address (20 bytes)
    from: [20]u8,
    /// Recipient address (20 bytes), null for contract creation
    to: ?[20]u8,
    /// Value to transfer (32 bytes big-endian)
    value: [32]u8,
    /// Input data / calldata
    data: []const u8,
    /// Gas limit
    gas_limit: u64,
    /// Gas price (32 bytes big-endian)
    gas_price: [32]u8,
    /// Nonce (optional, auto-managed if null)
    nonce: ?u64,
};

/// Result of executing a single transaction
pub const BatchTransactionResult = struct {
    /// Transaction index in batch
    tx_index: u32,
    /// Whether execution succeeded
    success: bool,
    /// Whether execution reverted (REVERT opcode)
    reverted: bool,
    /// Gas used
    gas_used: u64,
    /// Return data
    return_data: []u8,
    /// Error message (if failed)
    error_msg: ?[]u8,
    /// Logs emitted
    logs: []BatchLog,
    /// Created contract address (for contract creation)
    created_address: ?[20]u8,

    pub fn deinit(self: *BatchTransactionResult, allocator: Allocator) void {
        if (self.return_data.len > 0) {
            allocator.free(self.return_data);
        }
        if (self.error_msg) |msg| {
            allocator.free(msg);
        }
        for (self.logs) |*log| {
            log.deinit(allocator);
        }
        if (self.logs.len > 0) {
            allocator.free(self.logs);
        }
    }
};

/// Log entry from batch execution
pub const BatchLog = struct {
    address: [20]u8,
    topics: [][32]u8,
    data: []u8,

    pub fn deinit(self: *BatchLog, allocator: Allocator) void {
        if (self.topics.len > 0) {
            allocator.free(self.topics);
        }
        if (self.data.len > 0) {
            allocator.free(self.data);
        }
    }
};

/// Statistics from batch execution
pub const BatchExecutionStats = struct {
    /// Total transactions processed
    total_transactions: u32,
    /// Successfully executed transactions
    successful_transactions: u32,
    /// Failed transactions
    failed_transactions: u32,
    /// Reverted transactions
    reverted_transactions: u32,
    /// Total gas used
    total_gas_used: u64,
    /// Execution time in nanoseconds
    execution_time_ns: u64,
    /// Number of parallel waves (dependency groups)
    parallel_waves: u32,
    /// Maximum parallelism achieved
    max_parallelism: u32,
};

// ============================================================
// Batch Executor Configuration
// ============================================================

/// Configuration for batch execution
pub const BatchConfig = struct {
    /// Maximum number of worker threads
    max_threads: u32 = 4,
    /// Enable parallel execution (vs sequential)
    enable_parallel: bool = true,
    /// Enable speculative execution with rollback
    enable_speculation: bool = false,
    /// Chain ID for EIP-155
    chain_id: u64 = 1,
    /// Block number
    block_number: u64 = 1,
    /// Block timestamp
    block_timestamp: u64 = 0,
    /// Block gas limit
    block_gas_limit: u64 = 30_000_000,
    /// Coinbase address
    coinbase: [20]u8 = [_]u8{0} ** 20,
};

// ============================================================
// Batch Executor
// ============================================================

/// Batch executor for parallel transaction processing
pub const BatchExecutor = struct {
    allocator: Allocator,
    config: BatchConfig,
    /// Shared state for all transactions
    accounts: std.AutoHashMap([20]u8, Account),
    /// Mutex for account access
    accounts_mutex: Mutex,
    /// Worker threads
    workers: []Thread,
    /// Work queue
    work_queue: std.ArrayList(WorkUnit),
    work_mutex: Mutex,
    work_condition: Thread.Condition,
    /// Results
    results: std.ArrayList(BatchTransactionResult),
    results_mutex: Mutex,
    /// Shutdown flag
    shutdown: Atomic(bool),
    /// Active workers count
    active_workers: Atomic(u32),

    const WorkUnit = struct {
        tx_index: u32,
        transaction: BatchTransaction,
        executor: *BatchExecutor,
    };

    pub fn init(allocator: Allocator, config: BatchConfig) !*BatchExecutor {
        const executor = try allocator.create(BatchExecutor);
        executor.* = BatchExecutor{
            .allocator = allocator,
            .config = config,
            .accounts = std.AutoHashMap([20]u8, Account).init(allocator),
            .accounts_mutex = Mutex{},
            .workers = &[_]Thread{},
            .work_queue = std.ArrayList(WorkUnit).init(allocator),
            .work_mutex = Mutex{},
            .work_condition = Thread.Condition{},
            .results = std.ArrayList(BatchTransactionResult).init(allocator),
            .results_mutex = Mutex{},
            .shutdown = Atomic(bool).init(false),
            .active_workers = Atomic(u32).init(0),
        };

        // Start worker threads if parallel enabled
        if (config.enable_parallel and config.max_threads > 1) {
            executor.workers = try allocator.alloc(Thread, config.max_threads);
            for (executor.workers, 0..) |*worker, i| {
                worker.* = try Thread.spawn(.{}, workerLoop, .{ executor, i });
            }
        }

        return executor;
    }

    pub fn deinit(self: *BatchExecutor) void {
        // Signal shutdown
        self.shutdown.store(true, .release);

        // Wake up all workers
        self.work_mutex.lock();
        self.work_condition.broadcast();
        self.work_mutex.unlock();

        // Wait for workers to finish
        for (self.workers) |*worker| {
            worker.join();
        }

        // Clean up accounts
        var account_iter = self.accounts.iterator();
        while (account_iter.next()) |entry| {
            entry.value_ptr.storage.deinit();
        }
        self.accounts.deinit();

        // Clean up results
        for (self.results.items) |*result| {
            result.deinit(self.allocator);
        }
        self.results.deinit();

        self.work_queue.deinit();

        if (self.workers.len > 0) {
            self.allocator.free(self.workers);
        }

        self.allocator.destroy(self);
    }

    /// Set account state before execution
    pub fn setAccount(self: *BatchExecutor, address: [20]u8, balance: [32]u8, nonce: u64, code: []const u8) !void {
        self.accounts_mutex.lock();
        defer self.accounts_mutex.unlock();

        const balance_val = BigInt.fromBytes(balance);
        const code_copy = try self.allocator.dupe(u8, code);

        const account = Account{
            .balance = balance_val,
            .nonce = nonce,
            .code = code_copy,
            .storage = std.AutoHashMap(BigInt, BigInt).init(self.allocator),
        };

        try self.accounts.put(address, account);
    }

    /// Set storage value
    pub fn setStorage(self: *BatchExecutor, address: [20]u8, key: [32]u8, value: [32]u8) !void {
        self.accounts_mutex.lock();
        defer self.accounts_mutex.unlock();

        const key_val = BigInt.fromBytes(key);
        const value_val = BigInt.fromBytes(value);

        if (self.accounts.getPtr(address)) |account| {
            try account.storage.put(key_val, value_val);
        } else {
            var storage = std.AutoHashMap(BigInt, BigInt).init(self.allocator);
            try storage.put(key_val, value_val);

            const account = Account{
                .balance = BigInt.zero(),
                .nonce = 0,
                .code = &[_]u8{},
                .storage = storage,
            };
            try self.accounts.put(address, account);
        }
    }

    /// Execute a batch of transactions
    pub fn executeBatch(self: *BatchExecutor, transactions: []const BatchTransaction) !BatchExecutionStats {
        const start_time = std.time.nanoTimestamp();

        // Clear previous results
        for (self.results.items) |*result| {
            result.deinit(self.allocator);
        }
        self.results.clearRetainingCapacity();

        // Analyze dependencies
        var waves = try self.buildExecutionWaves(transactions);
        defer self.allocator.free(waves);

        var stats = BatchExecutionStats{
            .total_transactions = @intCast(transactions.len),
            .successful_transactions = 0,
            .failed_transactions = 0,
            .reverted_transactions = 0,
            .total_gas_used = 0,
            .execution_time_ns = 0,
            .parallel_waves = @intCast(waves.len),
            .max_parallelism = 0,
        };

        // Execute each wave
        for (waves) |wave| {
            if (wave.len > stats.max_parallelism) {
                stats.max_parallelism = @intCast(wave.len);
            }

            if (self.config.enable_parallel and wave.len > 1) {
                try self.executeWaveParallel(transactions, wave);
            } else {
                try self.executeWaveSequential(transactions, wave);
            }
        }

        // Collect statistics
        for (self.results.items) |result| {
            stats.total_gas_used += result.gas_used;
            if (result.success) {
                if (result.reverted) {
                    stats.reverted_transactions += 1;
                } else {
                    stats.successful_transactions += 1;
                }
            } else {
                stats.failed_transactions += 1;
            }
        }

        const end_time = std.time.nanoTimestamp();
        stats.execution_time_ns = @intCast(end_time - start_time);

        return stats;
    }

    /// Get execution results
    pub fn getResults(self: *BatchExecutor) []BatchTransactionResult {
        return self.results.items;
    }

    // Internal: Build execution waves based on dependencies
    fn buildExecutionWaves(self: *BatchExecutor, transactions: []const BatchTransaction) ![][]u32 {
        var waves = std.ArrayList([]u32).init(self.allocator);
        var remaining = std.ArrayList(u32).init(self.allocator);
        defer remaining.deinit();

        // Initially all transactions are remaining
        for (0..transactions.len) |i| {
            try remaining.append(@intCast(i));
        }

        // Track completed nonces per address
        var completed_nonces = std.AutoHashMap([20]u8, u64).init(self.allocator);
        defer completed_nonces.deinit();

        // Get initial nonces from accounts
        self.accounts_mutex.lock();
        var account_iter = self.accounts.iterator();
        while (account_iter.next()) |entry| {
            try completed_nonces.put(entry.key_ptr.*, entry.value_ptr.nonce);
        }
        self.accounts_mutex.unlock();

        while (remaining.items.len > 0) {
            var wave = std.ArrayList(u32).init(self.allocator);
            var used_addresses = std.AutoHashMap([20]u8, void).init(self.allocator);
            defer used_addresses.deinit();

            var i: usize = 0;
            while (i < remaining.items.len) {
                const tx_idx = remaining.items[i];
                const tx = transactions[tx_idx];

                // Check if this transaction can run in this wave
                var can_run = true;

                // Check nonce ordering for same sender
                const expected_nonce = completed_nonces.get(tx.from) orelse 0;
                if (tx.nonce) |nonce| {
                    if (nonce != expected_nonce) {
                        can_run = false;
                    }
                }

                // Check address conflicts within wave
                if (can_run and used_addresses.contains(tx.from)) {
                    can_run = false;
                }
                if (can_run) {
                    if (tx.to) |to| {
                        if (used_addresses.contains(to)) {
                            can_run = false;
                        }
                    }
                }

                if (can_run) {
                    try wave.append(tx_idx);
                    try used_addresses.put(tx.from, {});
                    if (tx.to) |to| {
                        try used_addresses.put(to, {});
                    }
                    // Update nonce expectation
                    try completed_nonces.put(tx.from, expected_nonce + 1);
                    _ = remaining.orderedRemove(i);
                } else {
                    i += 1;
                }
            }

            if (wave.items.len > 0) {
                try waves.append(try wave.toOwnedSlice());
            } else {
                // Prevent infinite loop if no progress
                if (remaining.items.len > 0) {
                    // Force sequential execution of remaining
                    var forced_wave = try self.allocator.alloc(u32, remaining.items.len);
                    for (remaining.items, 0..) |idx, j| {
                        forced_wave[j] = idx;
                    }
                    try waves.append(forced_wave);
                    remaining.clearRetainingCapacity();
                }
                wave.deinit();
            }
        }

        return try waves.toOwnedSlice();
    }

    fn executeWaveSequential(self: *BatchExecutor, transactions: []const BatchTransaction, wave: []const u32) !void {
        for (wave) |tx_idx| {
            const result = try self.executeSingleTransaction(tx_idx, transactions[tx_idx]);
            self.results_mutex.lock();
            try self.results.append(result);
            self.results_mutex.unlock();
        }
    }

    fn executeWaveParallel(self: *BatchExecutor, transactions: []const BatchTransaction, wave: []const u32) !void {
        // Submit all work
        self.work_mutex.lock();
        for (wave) |tx_idx| {
            try self.work_queue.append(WorkUnit{
                .tx_index = tx_idx,
                .transaction = transactions[tx_idx],
                .executor = self,
            });
        }
        self.work_condition.broadcast();
        self.work_mutex.unlock();

        // Wait for all to complete
        const expected_results = self.results.items.len + wave.len;
        while (true) {
            self.results_mutex.lock();
            const current_count = self.results.items.len;
            self.results_mutex.unlock();

            if (current_count >= expected_results) break;
            std.Thread.sleep(100_000); // 100μs
        }
    }

    fn workerLoop(self: *BatchExecutor, worker_id: usize) void {
        _ = worker_id;

        while (!self.shutdown.load(.acquire)) {
            self.work_mutex.lock();

            while (self.work_queue.items.len == 0 and !self.shutdown.load(.acquire)) {
                self.work_condition.wait(&self.work_mutex);
            }

            if (self.shutdown.load(.acquire)) {
                self.work_mutex.unlock();
                break;
            }

            const work = self.work_queue.orderedRemove(0);
            self.work_mutex.unlock();

            _ = self.active_workers.fetchAdd(1, .acq_rel);

            const result = self.executeSingleTransaction(work.tx_index, work.transaction) catch |err| blk: {
                break :blk BatchTransactionResult{
                    .tx_index = work.tx_index,
                    .success = false,
                    .reverted = false,
                    .gas_used = 0,
                    .return_data = &[_]u8{},
                    .error_msg = self.allocator.dupe(u8, @errorName(err)) catch null,
                    .logs = &[_]BatchLog{},
                    .created_address = null,
                };
            };

            self.results_mutex.lock();
            self.results.append(result) catch {};
            self.results_mutex.unlock();

            _ = self.active_workers.fetchSub(1, .acq_rel);
        }
    }

    fn executeSingleTransaction(self: *BatchExecutor, tx_index: u32, tx: BatchTransaction) !BatchTransactionResult {
        // Create EVM instance
        var evm = try EVM.init(self.allocator);
        defer evm.deinit();

        // Configure EVM
        evm.chain_id = self.config.chain_id;
        evm.block_number = self.config.block_number;
        evm.block_timestamp = self.config.block_timestamp;
        evm.block_gas_limit = self.config.block_gas_limit;
        evm.coinbase = self.config.coinbase;

        // Copy accounts to EVM
        self.accounts_mutex.lock();
        var account_iter = self.accounts.iterator();
        while (account_iter.next()) |entry| {
            var storage_copy = std.AutoHashMap(BigInt, BigInt).init(self.allocator);
            var storage_iter = entry.value_ptr.storage.iterator();
            while (storage_iter.next()) |s_entry| {
                try storage_copy.put(s_entry.key_ptr.*, s_entry.value_ptr.*);
            }

            const account_copy = Account{
                .balance = entry.value_ptr.balance,
                .nonce = entry.value_ptr.nonce,
                .code = entry.value_ptr.code,
                .storage = storage_copy,
            };
            try evm.accounts.put(entry.key_ptr.*, account_copy);
        }
        self.accounts_mutex.unlock();

        // Set up execution context
        evm.caller_address = tx.from;
        evm.origin_address = tx.from;
        evm.call_value = BigInt.fromBytes(tx.value);
        evm.gas_price = BigInt.fromBytes(tx.gas_price);
        evm.calldata = tx.data;

        var result = BatchTransactionResult{
            .tx_index = tx_index,
            .success = false,
            .reverted = false,
            .gas_used = 0,
            .return_data = &[_]u8{},
            .error_msg = null,
            .logs = &[_]BatchLog{},
            .created_address = null,
        };

        if (tx.to) |to_addr| {
            // Regular call
            evm.current_address = to_addr;

            // Get target code
            if (evm.accounts.get(to_addr)) |account| {
                evm.code = account.code;
            } else {
                evm.code = &[_]u8{};
            }
        } else {
            // Contract creation
            // For now, treat data as code
            evm.code = tx.data;
            evm.current_address = [_]u8{0} ** 20; // Will be calculated
        }

        // Set gas limit
        evm.setGasLimit(tx.gas_limit);

        // Execute
        evm.execute() catch |err| {
            result.error_msg = try self.allocator.dupe(u8, @errorName(err));
            result.gas_used = evm.gas_used;
            return result;
        };

        result.success = true;
        result.reverted = evm.execution_reverted;
        result.gas_used = evm.gas_used;

        // Copy return data
        if (evm.return_data.len > 0) {
            result.return_data = try self.allocator.dupe(u8, evm.return_data);
        }

        // Copy logs
        if (evm.logs.items.len > 0) {
            var logs = try self.allocator.alloc(BatchLog, evm.logs.items.len);
            for (evm.logs.items, 0..) |log, i| {
                var topics = try self.allocator.alloc([32]u8, log.topics.items.len);
                for (log.topics.items, 0..) |topic, j| {
                    topics[j] = topic;
                }
                logs[i] = BatchLog{
                    .address = log.address,
                    .topics = topics,
                    .data = if (log.data.len > 0) try self.allocator.dupe(u8, log.data) else &[_]u8{},
                };
            }
            result.logs = logs;
        }

        // Update shared state from successful execution
        if (result.success and !result.reverted) {
            self.accounts_mutex.lock();
            defer self.accounts_mutex.unlock();

            // Update accounts from EVM state
            var evm_account_iter = evm.accounts.iterator();
            while (evm_account_iter.next()) |entry| {
                if (self.accounts.getPtr(entry.key_ptr.*)) |existing| {
                    existing.balance = entry.value_ptr.balance;
                    existing.nonce = entry.value_ptr.nonce;
                    // Copy storage updates
                    var storage_iter = entry.value_ptr.storage.iterator();
                    while (storage_iter.next()) |s_entry| {
                        try existing.storage.put(s_entry.key_ptr.*, s_entry.value_ptr.*);
                    }
                }
            }
        }

        return result;
    }
};

// ============================================================
// Tests
// ============================================================

test "batch executor sequential execution" {
    const allocator = std.testing.allocator;

    const config = BatchConfig{
        .enable_parallel = false,
        .max_threads = 1,
    };

    var executor = try BatchExecutor.init(allocator, config);
    defer executor.deinit();

    // Set up accounts
    const addr1 = [_]u8{0x11} ** 20;
    const addr2 = [_]u8{0x22} ** 20;

    var balance = [_]u8{0} ** 32;
    balance[31] = 100; // 100 wei

    try executor.setAccount(addr1, balance, 0, &[_]u8{});
    try executor.setAccount(addr2, [_]u8{0} ** 32, 0, &[_]u8{});

    // Create simple transaction
    var value = [_]u8{0} ** 32;
    value[31] = 10; // 10 wei

    const transactions = [_]BatchTransaction{
        BatchTransaction{
            .from = addr1,
            .to = addr2,
            .value = value,
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = [_]u8{0} ** 32,
            .nonce = 0,
        },
    };

    const stats = try executor.executeBatch(&transactions);
    try std.testing.expectEqual(@as(u32, 1), stats.total_transactions);
}
