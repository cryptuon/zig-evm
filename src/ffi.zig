// File: src/ffi.zig
// C ABI exports for embedding the Zig EVM in other languages
// Provides opaque pointer-based API with error codes

const std = @import("std");
const main = @import("main.zig");
const EVM = main.EVM;
const BigInt = main.BigInt;
const Account = main.Account;
const Log = main.Log;

// ============================================================
// Error Codes
// ============================================================

pub const EVMError = enum(c_int) {
    OK = 0,
    OUT_OF_GAS = 1,
    STACK_UNDERFLOW = 2,
    STACK_OVERFLOW = 3,
    INVALID_OPCODE = 4,
    INVALID_JUMP = 5,
    REVERT = 6,
    STATIC_CALL_VIOLATION = 7,
    OUT_OF_MEMORY = 8,
    CALL_DEPTH_EXCEEDED = 9,
    INSUFFICIENT_BALANCE = 10,
    INVALID_ARGUMENT = 11,
    UNKNOWN_ERROR = 255,
};

// ============================================================
// Result Structure
// ============================================================

pub const EVMResult = extern struct {
    success: bool,
    error_code: EVMError,
    gas_used: u64,
    gas_remaining: u64,
    return_data: [*]u8,
    return_data_len: usize,
    reverted: bool,
};

// ============================================================
// Internal State
// ============================================================

var global_allocator: std.mem.Allocator = undefined;
var allocator_initialized: bool = false;

fn getGlobalAllocator() std.mem.Allocator {
    if (!allocator_initialized) {
        global_allocator = std.heap.page_allocator;
        allocator_initialized = true;
    }
    return global_allocator;
}

// ============================================================
// EVM Lifecycle
// ============================================================

/// Create a new EVM instance
/// Returns opaque handle or null on failure
export fn evm_create() callconv(.C) ?*anyopaque {
    const allocator = getGlobalAllocator();
    const evm = EVM.init(allocator) catch return null;
    return @ptrCast(evm);
}

/// Destroy an EVM instance and free resources
export fn evm_destroy(handle: ?*anyopaque) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        evm.deinit();
    }
}

/// Reset EVM state for new execution
export fn evm_reset(handle: ?*anyopaque) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        evm.pc = 0;
        evm.gas_used = 0;
        evm.stop_execution = false;
        evm.execution_reverted = false;
        // Clear stack
        while (evm.stack.pop()) |_| {}
        // Note: memory, storage, and accounts are preserved
    }
}

// ============================================================
// Configuration
// ============================================================

/// Set gas limit for execution
export fn evm_set_gas_limit(handle: ?*anyopaque, gas_limit: u64) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        evm.setGasLimit(gas_limit);
    }
}

/// Set block number
export fn evm_set_block_number(handle: ?*anyopaque, number: u64) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        evm.block_number = number;
    }
}

/// Set block timestamp
export fn evm_set_timestamp(handle: ?*anyopaque, timestamp: u64) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        evm.block_timestamp = timestamp;
    }
}

/// Set chain ID
export fn evm_set_chain_id(handle: ?*anyopaque, chain_id: u64) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        evm.chain_id = chain_id;
    }
}

/// Set coinbase (block producer) address
export fn evm_set_coinbase(handle: ?*anyopaque, addr: [*]const u8) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        @memcpy(&evm.coinbase, addr[0..20]);
    }
}

/// Set current contract address
export fn evm_set_address(handle: ?*anyopaque, addr: [*]const u8) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        @memcpy(&evm.current_address, addr[0..20]);
    }
}

/// Set caller (msg.sender) address
export fn evm_set_caller(handle: ?*anyopaque, addr: [*]const u8) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        @memcpy(&evm.caller_address, addr[0..20]);
    }
}

/// Set origin (tx.origin) address
export fn evm_set_origin(handle: ?*anyopaque, addr: [*]const u8) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        @memcpy(&evm.origin_address, addr[0..20]);
    }
}

/// Set call value (msg.value) - 32 bytes big-endian
export fn evm_set_value(handle: ?*anyopaque, value: [*]const u8) callconv(.C) void {
    if (handle) |h| {
        const evm: *EVM = @ptrCast(@alignCast(h));
        var bytes: [32]u8 = undefined;
        @memcpy(&bytes, value[0..32]);
        evm.call_value = BigInt.fromBytes(bytes);
    }
}

// ============================================================
// Account Management
// ============================================================

/// Set account balance - addr is 20 bytes, balance is 32 bytes big-endian
export fn evm_set_balance(handle: ?*anyopaque, addr: [*]const u8, balance: [*]const u8) callconv(.C) EVMError {
    const h = handle orelse return EVMError.INVALID_ARGUMENT;
    const evm: *EVM = @ptrCast(@alignCast(h));

    var address: [20]u8 = undefined;
    @memcpy(&address, addr[0..20]);

    var balance_bytes: [32]u8 = undefined;
    @memcpy(&balance_bytes, balance[0..32]);
    const balance_val = BigInt.fromBytes(balance_bytes);

    if (evm.accounts.getPtr(address)) |account| {
        account.balance = balance_val;
    } else {
        const new_account = Account{
            .balance = balance_val,
            .nonce = 0,
            .code = &[_]u8{},
            .storage = std.AutoHashMap(BigInt, BigInt).init(evm.allocator),
        };
        evm.accounts.put(address, new_account) catch return EVMError.OUT_OF_MEMORY;
    }
    return EVMError.OK;
}

/// Set account code
export fn evm_set_code(handle: ?*anyopaque, addr: [*]const u8, code: [*]const u8, code_len: usize) callconv(.C) EVMError {
    const h = handle orelse return EVMError.INVALID_ARGUMENT;
    const evm: *EVM = @ptrCast(@alignCast(h));

    var address: [20]u8 = undefined;
    @memcpy(&address, addr[0..20]);

    const code_copy = evm.allocator.dupe(u8, code[0..code_len]) catch return EVMError.OUT_OF_MEMORY;

    if (evm.accounts.getPtr(address)) |account| {
        account.code = code_copy;
    } else {
        const new_account = Account{
            .balance = BigInt.zero(),
            .nonce = 0,
            .code = code_copy,
            .storage = std.AutoHashMap(BigInt, BigInt).init(evm.allocator),
        };
        evm.accounts.put(address, new_account) catch return EVMError.OUT_OF_MEMORY;
    }
    return EVMError.OK;
}

/// Set storage value - key and value are 32 bytes big-endian
export fn evm_set_storage(handle: ?*anyopaque, addr: [*]const u8, key: [*]const u8, value: [*]const u8) callconv(.C) EVMError {
    const h = handle orelse return EVMError.INVALID_ARGUMENT;
    const evm: *EVM = @ptrCast(@alignCast(h));

    var address: [20]u8 = undefined;
    @memcpy(&address, addr[0..20]);

    var key_bytes: [32]u8 = undefined;
    @memcpy(&key_bytes, key[0..32]);
    const key_val = BigInt.fromBytes(key_bytes);

    var value_bytes: [32]u8 = undefined;
    @memcpy(&value_bytes, value[0..32]);
    const value_val = BigInt.fromBytes(value_bytes);

    if (evm.accounts.getPtr(address)) |account| {
        account.storage.put(key_val, value_val) catch return EVMError.OUT_OF_MEMORY;
    } else {
        var storage = std.AutoHashMap(BigInt, BigInt).init(evm.allocator);
        storage.put(key_val, value_val) catch return EVMError.OUT_OF_MEMORY;

        const new_account = Account{
            .balance = BigInt.zero(),
            .nonce = 0,
            .code = &[_]u8{},
            .storage = storage,
        };
        evm.accounts.put(address, new_account) catch return EVMError.OUT_OF_MEMORY;
    }
    return EVMError.OK;
}

/// Get storage value - returns 32 bytes via out parameter
export fn evm_get_storage(handle: ?*anyopaque, addr: [*]const u8, key: [*]const u8, out: [*]u8) callconv(.C) EVMError {
    const h = handle orelse return EVMError.INVALID_ARGUMENT;
    const evm: *EVM = @ptrCast(@alignCast(h));

    var address: [20]u8 = undefined;
    @memcpy(&address, addr[0..20]);

    var key_bytes: [32]u8 = undefined;
    @memcpy(&key_bytes, key[0..32]);
    const key_val = BigInt.fromBytes(key_bytes);

    if (evm.accounts.get(address)) |account| {
        if (account.storage.get(key_val)) |value| {
            const bytes = value.toBytes();
            @memcpy(out[0..32], &bytes);
        } else {
            @memset(out[0..32], 0);
        }
    } else {
        @memset(out[0..32], 0);
    }
    return EVMError.OK;
}

// ============================================================
// Execution
// ============================================================

/// Execute bytecode with calldata
/// Returns EVMResult with execution details
export fn evm_execute(
    handle: ?*anyopaque,
    code: [*]const u8,
    code_len: usize,
    calldata: [*]const u8,
    calldata_len: usize,
) callconv(.C) EVMResult {
    const h = handle orelse return EVMResult{
        .success = false,
        .error_code = EVMError.INVALID_ARGUMENT,
        .gas_used = 0,
        .gas_remaining = 0,
        .return_data = undefined,
        .return_data_len = 0,
        .reverted = false,
    };

    const evm: *EVM = @ptrCast(@alignCast(h));

    // Set code and calldata
    evm.code = code[0..code_len];
    evm.calldata = calldata[0..calldata_len];
    evm.pc = 0;

    // Execute
    evm.execute() catch |err| {
        const error_code: EVMError = switch (err) {
            error.OutOfGas => EVMError.OUT_OF_GAS,
            error.StackUnderflow => EVMError.STACK_UNDERFLOW,
            error.StackOverflow => EVMError.STACK_OVERFLOW,
            error.UnknownOpcode => EVMError.INVALID_OPCODE,
            error.InvalidJumpDest => EVMError.INVALID_JUMP,
            error.StaticCallViolation => EVMError.STATIC_CALL_VIOLATION,
            error.CallDepthExceeded => EVMError.CALL_DEPTH_EXCEEDED,
            error.InsufficientBalance => EVMError.INSUFFICIENT_BALANCE,
            else => EVMError.UNKNOWN_ERROR,
        };

        return EVMResult{
            .success = false,
            .error_code = error_code,
            .gas_used = evm.gas_used,
            .gas_remaining = evm.gas,
            .return_data = evm.return_data.ptr,
            .return_data_len = evm.return_data.len,
            .reverted = evm.execution_reverted,
        };
    };

    return EVMResult{
        .success = !evm.execution_reverted,
        .error_code = if (evm.execution_reverted) EVMError.REVERT else EVMError.OK,
        .gas_used = evm.gas_used,
        .gas_remaining = evm.gas,
        .return_data = evm.return_data.ptr,
        .return_data_len = evm.return_data.len,
        .reverted = evm.execution_reverted,
    };
}

// ============================================================
// Results Access
// ============================================================

/// Get gas used in last execution
export fn evm_gas_used(handle: ?*anyopaque) callconv(.C) u64 {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));
    return evm.gas_used;
}

/// Get remaining gas after last execution
export fn evm_gas_remaining(handle: ?*anyopaque) callconv(.C) u64 {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));
    return evm.gas;
}

/// Get return data length
export fn evm_return_data_len(handle: ?*anyopaque) callconv(.C) usize {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));
    return evm.return_data.len;
}

/// Copy return data to buffer
export fn evm_return_data_copy(handle: ?*anyopaque, out: [*]u8, max_len: usize) callconv(.C) usize {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));

    const copy_len = @min(evm.return_data.len, max_len);
    if (copy_len > 0) {
        @memcpy(out[0..copy_len], evm.return_data[0..copy_len]);
    }
    return copy_len;
}

/// Get number of logs emitted
export fn evm_logs_count(handle: ?*anyopaque) callconv(.C) usize {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));
    return evm.logs.items.len;
}

/// Get log address at index
export fn evm_log_address(handle: ?*anyopaque, index: usize, out: [*]u8) callconv(.C) bool {
    const h = handle orelse return false;
    const evm: *EVM = @ptrCast(@alignCast(h));

    if (index >= evm.logs.items.len) return false;
    @memcpy(out[0..20], &evm.logs.items[index].address);
    return true;
}

/// Get log topics count at index
export fn evm_log_topics_count(handle: ?*anyopaque, index: usize) callconv(.C) usize {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));

    if (index >= evm.logs.items.len) return 0;
    return evm.logs.items[index].topics.items.len;
}

/// Get log topic at index
export fn evm_log_topic(handle: ?*anyopaque, log_index: usize, topic_index: usize, out: [*]u8) callconv(.C) bool {
    const h = handle orelse return false;
    const evm: *EVM = @ptrCast(@alignCast(h));

    if (log_index >= evm.logs.items.len) return false;
    const log = evm.logs.items[log_index];
    if (topic_index >= log.topics.items.len) return false;

    @memcpy(out[0..32], &log.topics.items[topic_index]);
    return true;
}

/// Get log data length at index
export fn evm_log_data_len(handle: ?*anyopaque, index: usize) callconv(.C) usize {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));

    if (index >= evm.logs.items.len) return 0;
    return evm.logs.items[index].data.len;
}

/// Copy log data at index
export fn evm_log_data_copy(handle: ?*anyopaque, index: usize, out: [*]u8, max_len: usize) callconv(.C) usize {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));

    if (index >= evm.logs.items.len) return 0;
    const log = evm.logs.items[index];

    const copy_len = @min(log.data.len, max_len);
    if (copy_len > 0) {
        @memcpy(out[0..copy_len], log.data[0..copy_len]);
    }
    return copy_len;
}

// ============================================================
// Stack Access (for debugging)
// ============================================================

/// Get stack depth
export fn evm_stack_depth(handle: ?*anyopaque) callconv(.C) usize {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));
    return evm.stack.items.items.len;
}

/// Get stack item at index (0 = top), returns 32 bytes
export fn evm_stack_peek(handle: ?*anyopaque, index: usize, out: [*]u8) callconv(.C) bool {
    const h = handle orelse return false;
    const evm: *EVM = @ptrCast(@alignCast(h));

    const depth = evm.stack.items.items.len;
    if (index >= depth) return false;

    const value = evm.stack.items.items[depth - 1 - index];
    const bytes = value.toBytes();
    @memcpy(out[0..32], &bytes);
    return true;
}

// ============================================================
// Memory Access (for debugging)
// ============================================================

/// Get memory size
export fn evm_memory_size(handle: ?*anyopaque) callconv(.C) usize {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));
    return evm.memory.size();
}

/// Copy memory region
export fn evm_memory_copy(handle: ?*anyopaque, offset: usize, out: [*]u8, len: usize) callconv(.C) usize {
    const h = handle orelse return 0;
    const evm: *EVM = @ptrCast(@alignCast(h));

    const mem_size = evm.memory.size();
    if (offset >= mem_size) return 0;

    const available = mem_size - offset;
    const copy_len = @min(len, available);

    for (0..copy_len) |i| {
        out[i] = evm.memory.loadByte(offset + i);
    }
    return copy_len;
}

// ============================================================
// Version
// ============================================================

/// Get library version string
export fn evm_version() callconv(.C) [*:0]const u8 {
    return "zig-evm 0.1.0";
}

// ============================================================
// Batch Execution (Parallel Processing)
// ============================================================

const batch = @import("batch_executor.zig");
const BatchExecutor = batch.BatchExecutor;
const BatchConfig = batch.BatchConfig;
const BatchTransaction = batch.BatchTransaction;

/// Batch execution configuration (C-compatible)
pub const BatchConfigFFI = extern struct {
    max_threads: u32,
    enable_parallel: bool,
    enable_speculation: bool,
    chain_id: u64,
    block_number: u64,
    block_timestamp: u64,
    block_gas_limit: u64,
    coinbase: [20]u8,
};

/// Transaction for batch execution (C-compatible)
pub const BatchTransactionFFI = extern struct {
    from: [20]u8,
    to: [20]u8,
    has_to: bool,
    value: [32]u8,
    data: [*]const u8,
    data_len: usize,
    gas_limit: u64,
    gas_price: [32]u8,
    nonce: u64,
    has_nonce: bool,
};

/// Result from batch execution (C-compatible)
pub const BatchResultFFI = extern struct {
    tx_index: u32,
    success: bool,
    reverted: bool,
    gas_used: u64,
    return_data: [*]u8,
    return_data_len: usize,
    error_code: EVMError,
    logs_count: usize,
    created_address: [20]u8,
    has_created_address: bool,
};

/// Statistics from batch execution (C-compatible)
pub const BatchStatsFFI = extern struct {
    total_transactions: u32,
    successful_transactions: u32,
    failed_transactions: u32,
    reverted_transactions: u32,
    total_gas_used: u64,
    execution_time_ns: u64,
    parallel_waves: u32,
    max_parallelism: u32,
};

/// Create a batch executor
export fn batch_create(config: *const BatchConfigFFI) callconv(.C) ?*anyopaque {
    const allocator = getGlobalAllocator();

    const zig_config = BatchConfig{
        .max_threads = config.max_threads,
        .enable_parallel = config.enable_parallel,
        .enable_speculation = config.enable_speculation,
        .chain_id = config.chain_id,
        .block_number = config.block_number,
        .block_timestamp = config.block_timestamp,
        .block_gas_limit = config.block_gas_limit,
        .coinbase = config.coinbase,
    };

    const executor = BatchExecutor.init(allocator, zig_config) catch return null;
    return @ptrCast(executor);
}

/// Destroy a batch executor
export fn batch_destroy(handle: ?*anyopaque) callconv(.C) void {
    if (handle) |h| {
        const executor: *BatchExecutor = @ptrCast(@alignCast(h));
        executor.deinit();
    }
}

/// Set account state in batch executor
export fn batch_set_account(
    handle: ?*anyopaque,
    addr: [*]const u8,
    balance: [*]const u8,
    nonce: u64,
    code: [*]const u8,
    code_len: usize,
) callconv(.C) EVMError {
    const h = handle orelse return EVMError.INVALID_ARGUMENT;
    const executor: *BatchExecutor = @ptrCast(@alignCast(h));

    var address: [20]u8 = undefined;
    @memcpy(&address, addr[0..20]);

    var balance_bytes: [32]u8 = undefined;
    @memcpy(&balance_bytes, balance[0..32]);

    executor.setAccount(address, balance_bytes, nonce, code[0..code_len]) catch return EVMError.OUT_OF_MEMORY;
    return EVMError.OK;
}

/// Set storage in batch executor
export fn batch_set_storage(
    handle: ?*anyopaque,
    addr: [*]const u8,
    key: [*]const u8,
    value: [*]const u8,
) callconv(.C) EVMError {
    const h = handle orelse return EVMError.INVALID_ARGUMENT;
    const executor: *BatchExecutor = @ptrCast(@alignCast(h));

    var address: [20]u8 = undefined;
    @memcpy(&address, addr[0..20]);

    var key_bytes: [32]u8 = undefined;
    @memcpy(&key_bytes, key[0..32]);

    var value_bytes: [32]u8 = undefined;
    @memcpy(&value_bytes, value[0..32]);

    executor.setStorage(address, key_bytes, value_bytes) catch return EVMError.OUT_OF_MEMORY;
    return EVMError.OK;
}

/// Execute a batch of transactions
export fn batch_execute(
    handle: ?*anyopaque,
    transactions: [*]const BatchTransactionFFI,
    tx_count: usize,
    stats_out: *BatchStatsFFI,
) callconv(.C) EVMError {
    const h = handle orelse return EVMError.INVALID_ARGUMENT;
    const executor: *BatchExecutor = @ptrCast(@alignCast(h));

    // Convert FFI transactions to Zig transactions
    var zig_txs = getGlobalAllocator().alloc(BatchTransaction, tx_count) catch return EVMError.OUT_OF_MEMORY;
    defer getGlobalAllocator().free(zig_txs);

    for (0..tx_count) |i| {
        const ffi_tx = transactions[i];
        zig_txs[i] = BatchTransaction{
            .from = ffi_tx.from,
            .to = if (ffi_tx.has_to) ffi_tx.to else null,
            .value = ffi_tx.value,
            .data = ffi_tx.data[0..ffi_tx.data_len],
            .gas_limit = ffi_tx.gas_limit,
            .gas_price = ffi_tx.gas_price,
            .nonce = if (ffi_tx.has_nonce) ffi_tx.nonce else null,
        };
    }

    const stats = executor.executeBatch(zig_txs) catch return EVMError.UNKNOWN_ERROR;

    stats_out.* = BatchStatsFFI{
        .total_transactions = stats.total_transactions,
        .successful_transactions = stats.successful_transactions,
        .failed_transactions = stats.failed_transactions,
        .reverted_transactions = stats.reverted_transactions,
        .total_gas_used = stats.total_gas_used,
        .execution_time_ns = stats.execution_time_ns,
        .parallel_waves = stats.parallel_waves,
        .max_parallelism = stats.max_parallelism,
    };

    return EVMError.OK;
}

/// Get number of results from batch execution
export fn batch_results_count(handle: ?*anyopaque) callconv(.C) usize {
    const h = handle orelse return 0;
    const executor: *BatchExecutor = @ptrCast(@alignCast(h));
    return executor.getResults().len;
}

/// Get a specific result from batch execution
export fn batch_get_result(handle: ?*anyopaque, index: usize, result_out: *BatchResultFFI) callconv(.C) bool {
    const h = handle orelse return false;
    const executor: *BatchExecutor = @ptrCast(@alignCast(h));

    const results = executor.getResults();
    if (index >= results.len) return false;

    const result = results[index];

    result_out.tx_index = result.tx_index;
    result_out.success = result.success;
    result_out.reverted = result.reverted;
    result_out.gas_used = result.gas_used;
    result_out.return_data = result.return_data.ptr;
    result_out.return_data_len = result.return_data.len;
    result_out.error_code = if (result.error_msg != null) EVMError.UNKNOWN_ERROR else EVMError.OK;
    result_out.logs_count = result.logs.len;

    if (result.created_address) |addr| {
        result_out.has_created_address = true;
        result_out.created_address = addr;
    } else {
        result_out.has_created_address = false;
        result_out.created_address = [_]u8{0} ** 20;
    }

    return true;
}

/// Get result return data
export fn batch_result_return_data(handle: ?*anyopaque, index: usize, out: [*]u8, max_len: usize) callconv(.C) usize {
    const h = handle orelse return 0;
    const executor: *BatchExecutor = @ptrCast(@alignCast(h));

    const results = executor.getResults();
    if (index >= results.len) return 0;

    const result = results[index];
    const copy_len = @min(result.return_data.len, max_len);
    if (copy_len > 0) {
        @memcpy(out[0..copy_len], result.return_data[0..copy_len]);
    }
    return copy_len;
}
