# Contributing to Zig EVM

This guide provides information for contributing to the Zig EVM project, including setup instructions, coding standards, and contribution workflows.

## Table of Contents

1. [Quick Start for Contributors](#quick-start)
2. [Development Environment Setup](#development-setup)
3. [Code Standards and Style](#code-standards)
4. [Architecture Guidelines](#architecture-guidelines)
5. [Testing Requirements](#testing-requirements)
6. [Performance Considerations](#performance-considerations)
7. [Documentation Standards](#documentation-standards)
8. [Pull Request Process](#pull-request-process)
9. [Issue Reporting](#issue-reporting)
10. [Community Guidelines](#community-guidelines)
11. [Recognition and Credits](#recognition)

## Quick Start for Contributors {#quick-start}

### Prerequisites

- **Zig 0.15.x or later**: [Download here](https://ziglang.org/download/)
- **Git**: For version control
- **Basic EVM knowledge**: See our [EVM Fundamentals Guide](EVM_FUNDAMENTALS.md)

### First Contribution Workflow

```bash
# 1. Fork and clone the repository
git clone https://github.com/yourusername/zig-evm.git
cd zig-evm

# 2. Build and test the project
zig build test

# 3. Run benchmarks to understand performance
zig build demo

# 4. Create a feature branch
git checkout -b feature/your-feature-name

# 5. Make your changes and test
zig build test
zig build demo

# 6. Submit your pull request
git push origin feature/your-feature-name
```

### Good First Issues

Look for issues labeled with:
- `good first issue`: Perfect for newcomers
- `help wanted`: Community contributions welcome
- `performance`: Optimization opportunities
- `documentation`: Documentation improvements

## Development Environment Setup {#development-setup}

### Required Tools

```bash
# Install Zig (latest stable)
curl https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz | tar -xJ
export PATH=$PATH:$PWD/zig-linux-x86_64-0.15.1

# Verify installation
zig version

# Install development dependencies
sudo apt-get install build-essential gdb valgrind
```

### IDE Configuration

#### VS Code Setup

Create `.vscode/settings.json`:
```json
{
    "zig.zls.enable": true,
    "zig.zls.path": "zls",
    "zig.initialSetupDone": true,
    "editor.formatOnSave": true,
    "editor.rulers": [100],
    "files.associations": {
        "*.zig": "zig"
    }
}
```

Install recommended extensions:
- Zig Language Server
- GitLens
- Error Lens

#### Vim/Neovim Setup

```lua
-- init.lua configuration for Neovim
require('lspconfig').zls.setup{
    cmd = {'zls'},
    filetypes = {'zig'},
    root_dir = require('lspconfig').util.root_pattern('build.zig', '.git'),
}
```

### Project Structure

```
zig-evm/
├── src/                    # Core implementation
│   ├── main.zig           # Entry point and basic EVM
│   ├── parallel.zig       # Parallel execution engine
│   ├── parallel_optimized.zig  # Advanced optimizations
│   ├── opcodes.zig        # EVM opcode implementations
│   └── utils.zig          # Utility functions
├── docs/                  # Documentation
├── test.zig              # Test runner
├── build.zig             # Build configuration
└── README.md             # Project overview
```

## Code Standards and Style {#code-standards}

### Zig Style Guidelines

We follow the official Zig style guide with some project-specific conventions:

#### Naming Conventions

```zig
// Types: PascalCase
pub const EVMExecutor = struct { ... };
pub const TransactionResult = enum { ... };

// Functions: camelCase
pub fn executeTransaction() void { ... }
pub fn analyzeDependencies() ![]Dependency { ... }

// Variables: snake_case
const transaction_count = 100;
var parallel_efficiency: f64 = 0.85;

// Constants: SCREAMING_SNAKE_CASE
const MAX_STACK_SIZE = 1024;
const DEFAULT_GAS_LIMIT = 21000;

// Private members: leading underscore
const _internal_buffer = std.ArrayList(u8).init(allocator);
```

#### Code Formatting

```zig
// Function definitions
pub fn processTransactionBatch(
    allocator: std.mem.Allocator,
    transactions: []const Transaction,
    options: ExecutionOptions,
) ![]TransactionResult {
    // Implementation
}

// Struct definitions
pub const ExecutionContext = struct {
    allocator: std.mem.Allocator,
    gas_tracker: GasTracker,
    memory: EVMMemory,
    storage: StateStorage,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .gas_tracker = GasTracker.init(),
            .memory = EVMMemory.init(allocator),
            .storage = StateStorage.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.memory.deinit();
        self.storage.deinit();
    }
};

// Error handling
const result = executeOpcode(opcode) catch |err| switch (err) {
    error.StackUnderflow => {
        std.log.err("Stack underflow executing opcode: 0x{X}", .{opcode});
        return error.ExecutionFailed;
    },
    error.OutOfGas => {
        std.log.warn("Out of gas executing opcode: 0x{X}", .{opcode});
        return error.OutOfGas;
    },
    else => return err,
};
```

#### Documentation Comments

```zig
/// Executes a batch of transactions in parallel where possible.
///
/// This function analyzes transaction dependencies and creates execution
/// waves to maximize parallelism while maintaining correctness.
///
/// Args:
///   allocator: Memory allocator for temporary structures
///   transactions: Array of transactions to execute
///   thread_count: Number of worker threads to use
///
/// Returns:
///   Array of transaction results in the same order as input
///
/// Errors:
///   - OutOfMemory: If allocation fails
///   - InvalidTransaction: If transaction validation fails
///   - ExecutionError: If transaction execution fails
///
/// Performance:
///   - O(n) dependency analysis for n transactions
///   - Expected speedup: 4-6x for typical workloads
///   - Memory usage: ~100 bytes per transaction
pub fn executeTransactionBatch(
    allocator: std.mem.Allocator,
    transactions: []const Transaction,
    thread_count: u32,
) ![]TransactionResult {
    // Implementation
}
```

### Performance Guidelines

#### Memory Management

```zig
// ✅ Good: Use arena allocators for temporary data
pub fn processLargeDataset(allocator: std.mem.Allocator, data: []Data) !Result {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // All allocations automatically freed when arena is destroyed
    const temp_buffer = try arena_allocator.alloc(u8, data.len * 2);
    // ... processing
}

// ✅ Good: Reuse allocations when possible
pub const ProcessingContext = struct {
    temp_buffer: std.ArrayList(u8),

    pub fn processItem(self: *Self, item: Item) !void {
        // Reuse buffer instead of allocating new one
        self.temp_buffer.clearRetainingCapacity();
        // ... processing
    }
};

// ❌ Bad: Frequent small allocations
pub fn badProcessing(allocator: std.mem.Allocator, items: []Item) !void {
    for (items) |item| {
        const buffer = try allocator.alloc(u8, item.size); // Allocation per item
        defer allocator.free(buffer);
        // ... processing
    }
}
```

#### Efficient Data Structures

```zig
// ✅ Good: Use appropriate data structures
pub const OptimizedCache = struct {
    // Use HashMap for O(1) lookups
    address_cache: AutoHashMap([20]u8, CacheEntry),

    // Use ArrayList for sequential access
    pending_transactions: std.ArrayList(Transaction),

    // Use packed structs for memory efficiency
    pub const CacheEntry = packed struct {
        timestamp: u32,
        access_count: u16,
        is_valid: bool,
        _padding: u7 = 0,
    };
};

// ✅ Good: Batch operations for better performance
pub fn batchProcessTransactions(self: *Self, transactions: []Transaction) !void {
    // Analyze all dependencies at once
    const dependencies = try self.analyzer.analyzeDependencies(transactions);

    // Create execution waves
    const waves = try self.createExecutionWaves(transactions, dependencies);

    // Execute each wave in parallel
    for (waves) |wave| {
        try self.executeWave(wave);
    }
}
```

### Error Handling Standards

```zig
// Define comprehensive error sets
pub const EVMError = error{
    // Execution errors
    StackUnderflow,
    StackOverflow,
    OutOfGas,
    InvalidOpcode,
    InvalidJumpDestination,

    // State errors
    InsufficientBalance,
    NonceError,
    StorageError,

    // System errors
    OutOfMemory,
    IOError,
    ThreadPoolError,
};

// Use error unions consistently
pub fn executeTransaction(
    self: *Self,
    transaction: Transaction
) EVMError!TransactionResult {
    // Validate transaction
    try self.validateTransaction(transaction);

    // Execute with proper error propagation
    const result = self.doExecuteTransaction(transaction) catch |err| switch (err) {
        error.OutOfGas => {
            std.log.warn("Transaction ran out of gas: {s}", .{transaction.hash});
            return TransactionResult.failed(error.OutOfGas);
        },
        error.StackUnderflow => {
            std.log.err("Stack underflow in transaction: {s}", .{transaction.hash});
            return TransactionResult.failed(error.StackUnderflow);
        },
        else => return err, // Propagate unexpected errors
    };

    return result;
}
```

## Architecture Guidelines {#architecture-guidelines}

### Component Design Principles

#### Single Responsibility

```zig
// ✅ Good: Each component has a single, well-defined responsibility
pub const GasTracker = struct {
    available: u64,
    used: u64,

    pub fn consumeGas(self: *Self, amount: u64) !void {
        if (self.used + amount > self.available) {
            return error.OutOfGas;
        }
        self.used += amount;
    }

    pub fn refundGas(self: *Self, amount: u64) void {
        self.used = if (amount > self.used) 0 else self.used - amount;
    }
};

pub const StackManager = struct {
    items: std.ArrayList(U256),

    pub fn push(self: *Self, value: U256) !void {
        if (self.items.items.len >= MAX_STACK_SIZE) {
            return error.StackOverflow;
        }
        try self.items.append(value);
    }

    pub fn pop(self: *Self) !U256 {
        return self.items.popOrNull() orelse error.StackUnderflow;
    }
};
```

#### Dependency Injection

```zig
// ✅ Good: Use dependency injection for testability
pub const EVMExecutor = struct {
    allocator: std.mem.Allocator,
    gas_tracker: *GasTracker,
    stack: *StackManager,
    memory: *MemoryManager,
    storage: *StorageManager,

    pub fn init(
        allocator: std.mem.Allocator,
        gas_tracker: *GasTracker,
        stack: *StackManager,
        memory: *MemoryManager,
        storage: *StorageManager,
    ) Self {
        return Self{
            .allocator = allocator,
            .gas_tracker = gas_tracker,
            .stack = stack,
            .memory = memory,
            .storage = storage,
        };
    }

    // Easy to test with mock dependencies
    pub fn executeOpcode(self: *Self, opcode: u8) !void {
        switch (opcode) {
            0x01 => try self.opADD(),
            0x02 => try self.opMUL(),
            // ...
            else => return error.InvalidOpcode,
        }
    }
};
```

#### Interface Segregation

```zig
// ✅ Good: Define minimal, focused interfaces
pub const StorageReader = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        read: *const fn (ptr: *anyopaque, key: U256) anyerror!U256,
    };

    pub fn read(self: Self, key: U256) !U256 {
        return self.vtable.read(self.ptr, key);
    }
};

pub const StorageWriter = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        write: *const fn (ptr: *anyopaque, key: U256, value: U256) anyerror!void,
    };

    pub fn write(self: Self, key: U256, value: U256) !void {
        return self.vtable.write(self.ptr, key, value);
    }
};

// Components only depend on what they actually need
pub const ReadOnlyProcessor = struct {
    storage: StorageReader,

    pub fn processReadOnlyOperation(self: *Self, key: U256) !U256 {
        return try self.storage.read(key);
    }
};
```

### Parallel Processing Architecture

```zig
// Thread-safe design patterns
pub const WorkStealingQueue = struct {
    items: std.atomic.Queue(*WorkItem),
    local_queues: []LocalQueue,

    pub const WorkItem = struct {
        task: TaskType,
        data: *anyopaque,
        completion: *std.atomic.Atomic(bool),
    };

    pub fn submitWork(self: *Self, item: *WorkItem) void {
        // Try local queue first, then global queue
        const thread_id = getCurrentThreadId();
        if (!self.local_queues[thread_id].tryPush(item)) {
            self.items.put(item);
        }
    }

    pub fn stealWork(self: *Self, stealing_thread: u32) ?*WorkItem {
        // Try to steal from other threads' local queues
        for (self.local_queues, 0..) |*queue, i| {
            if (i == stealing_thread) continue;
            if (queue.trySteal()) |item| {
                return item;
            }
        }

        // Fall back to global queue
        return self.items.get();
    }
};
```

## Testing Requirements {#testing-requirements}

### Test Structure

```zig
// test.zig - Main test runner
const std = @import("std");
const testing = std.testing;

// Import all test modules
test "all tests" {
    _ = @import("src/test_evm_basic.zig");
    _ = @import("src/test_parallel_execution.zig");
    _ = @import("src/test_dependency_analysis.zig");
    _ = @import("src/test_performance.zig");
}
```

### Unit Testing Standards

```zig
// src/test_evm_basic.zig
const std = @import("std");
const testing = std.testing;
const evm = @import("main.zig");

test "EVM stack operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stack = evm.Stack.init(allocator);
    defer stack.deinit();

    // Test push operation
    try stack.push(evm.U256.init(42));
    try testing.expect(stack.size() == 1);

    // Test pop operation
    const value = try stack.pop();
    try testing.expectEqual(evm.U256.init(42), value);
    try testing.expect(stack.size() == 0);

    // Test stack underflow
    try testing.expectError(error.StackUnderflow, stack.pop());
}

test "gas consumption tracking" {
    var gas_tracker = evm.GasTracker.init(1000);

    // Test normal gas consumption
    try gas_tracker.consumeGas(100);
    try testing.expect(gas_tracker.getUsed() == 100);
    try testing.expect(gas_tracker.getRemaining() == 900);

    // Test out of gas condition
    try testing.expectError(error.OutOfGas, gas_tracker.consumeGas(1000));

    // Test gas refund
    gas_tracker.refundGas(50);
    try testing.expect(gas_tracker.getUsed() == 50);
}
```

### Integration Testing

```zig
// src/test_parallel_execution.zig
const std = @import("std");
const testing = std.testing;
const parallel = @import("parallel.zig");
const evm = @import("main.zig");

test "parallel transaction execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create test transactions
    const transactions = try createTestTransactions(allocator, 100);
    defer allocator.free(transactions);

    // Execute in parallel
    var executor = parallel.ParallelExecutor.init(allocator, 4);
    defer executor.deinit();

    const start = std.time.nanoTimestamp();
    const results = try executor.execute(transactions);
    const end = std.time.nanoTimestamp();

    defer allocator.free(results);

    // Verify results
    try testing.expect(results.len == transactions.len);
    for (results) |result| {
        try testing.expect(result.success);
    }

    // Log performance metrics
    const duration = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    const tps = @as(f64, @floatFromInt(transactions.len)) / (duration / 1000.0);
    std.log.info("Parallel execution: {} TPS", .{tps});

    // Verify speedup compared to sequential execution
    const sequential_results = try executeSequentially(allocator, transactions);
    defer allocator.free(sequential_results);

    // Parallel should be significantly faster for this workload
    // (This is a rough check - actual speedup depends on many factors)
    try testing.expect(tps > 1000); // Should achieve reasonable throughput
}

fn createTestTransactions(allocator: std.mem.Allocator, count: u32) ![]evm.Transaction {
    const transactions = try allocator.alloc(evm.Transaction, count);

    for (transactions, 0..) |*tx, i| {
        tx.* = evm.Transaction{
            .from = createTestAddress(i),
            .to = createTestAddress(i + 1000),
            .value = evm.BigInt.init(100),
            .data = &[_]u8{},
            .gas_limit = 21000,
            .gas_price = evm.BigInt.init(20000000000),
        };
    }

    return transactions;
}
```

### Performance Testing

```zig
// src/test_performance.zig
const std = @import("std");
const testing = std.testing;
const evm = @import("main.zig");
const parallel = @import("parallel.zig");

test "dependency analysis performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const transaction_counts = [_]u32{ 10, 50, 100, 500, 1000 };

    for (transaction_counts) |count| {
        const transactions = try createTestTransactions(allocator, count);
        defer allocator.free(transactions);

        var analyzer = parallel.DependencyAnalyzer.init(allocator);
        defer analyzer.deinit();

        const start = std.time.nanoTimestamp();
        const dependencies = try analyzer.analyzeDependencies(transactions);
        const end = std.time.nanoTimestamp();

        const duration = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

        std.log.info("Dependency analysis for {} transactions: {d:.2}ms", .{ count, duration });

        // Performance regression test - should complete within reasonable time
        const max_time_per_tx = 0.1; // 0.1ms per transaction
        const expected_max_time = @as(f64, @floatFromInt(count)) * max_time_per_tx;

        if (duration > expected_max_time) {
            std.log.err("Performance regression: {d:.2}ms > {d:.2}ms", .{ duration, expected_max_time });
            return error.PerformanceRegression;
        }

        // Verify complexity - should be roughly O(n)
        if (count > 100) {
            const time_per_tx = duration / @as(f64, @floatFromInt(count));
            if (time_per_tx > 0.05) { // More than 0.05ms per transaction
                std.log.warn("High per-transaction analysis time: {d:.3}ms", .{time_per_tx});
            }
        }
    }
}

test "memory usage benchmarks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in benchmark!");
        }
    }
    const allocator = gpa.allocator();

    const initial_memory = getCurrentMemoryUsage();

    // Create large workload
    const transactions = try createTestTransactions(allocator, 1000);
    defer allocator.free(transactions);

    var executor = parallel.ParallelExecutor.init(allocator, 4);
    defer executor.deinit();

    const results = try executor.execute(transactions);
    defer allocator.free(results);

    const final_memory = getCurrentMemoryUsage();
    const memory_per_tx = (final_memory - initial_memory) / transactions.len;

    std.log.info("Memory usage: {} bytes per transaction", .{memory_per_tx});

    // Memory usage should be reasonable
    try testing.expect(memory_per_tx < 1024); // Less than 1KB per transaction
}

fn getCurrentMemoryUsage() usize {
    // Platform-specific memory usage measurement
    // This is a simplified version - actual implementation would use
    // platform-specific APIs
    return 0; // Placeholder
}
```

### Continuous Integration Tests

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        zig-version: ['0.15.1', 'master']

    steps:
    - uses: actions/checkout@v3

    - name: Setup Zig
      uses: goto-bus-stop/setup-zig@v2
      with:
        version: ${{ matrix.zig-version }}

    - name: Run tests
      run: |
        zig build test

    - name: Run benchmarks
      run: |
        zig build demo

    - name: Check formatting
      run: |
        zig fmt --check src/

    - name: Static analysis
      run: |
        zig build-exe src/main.zig -femit-asm=/dev/null

  performance:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Setup Zig
      uses: goto-bus-stop/setup-zig@v2
      with:
        version: '0.15.1'

    - name: Performance regression test
      run: |
        zig build bench
        # Compare with baseline performance metrics

  security:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Security scan
      run: |
        # Run security analysis tools
        # Check for common vulnerabilities
        echo "Security scan placeholder"
```

## Documentation Standards {#documentation-standards}

### Code Documentation

```zig
/// High-level module documentation
///
/// This module implements the core EVM execution engine with support for
/// parallel transaction processing. It provides:
///
/// - Stack-based virtual machine execution
/// - Gas tracking and consumption
/// - Memory and storage management
/// - Parallel dependency analysis
///
/// Performance characteristics:
/// - O(1) stack operations
/// - O(n) dependency analysis
/// - Memory usage: ~100 bytes per transaction
///
/// Example usage:
/// ```zig
/// var executor = EVMExecutor.init(allocator);
/// defer executor.deinit();
///
/// const result = try executor.execute(transaction);
/// std.log.info("Gas used: {}", .{result.gas_used});
/// ```

const std = @import("std");

/// Core EVM execution engine
///
/// Provides a complete implementation of the Ethereum Virtual Machine
/// with optimizations for parallel execution and performance.
pub const EVMExecutor = struct {
    allocator: std.mem.Allocator,
    stack: Stack,
    memory: Memory,
    storage: Storage,
    gas_tracker: GasTracker,

    /// Initialize a new EVM executor instance
    ///
    /// Args:
    ///   allocator: Memory allocator for dynamic allocations
    ///
    /// Returns:
    ///   Initialized executor ready for transaction processing
    ///
    /// Note: Remember to call deinit() to free resources
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .stack = Stack.init(allocator),
            .memory = Memory.init(allocator),
            .storage = Storage.init(allocator),
            .gas_tracker = GasTracker.init(0),
        };
    }

    /// Clean up resources
    ///
    /// Must be called to prevent memory leaks
    pub fn deinit(self: *Self) void {
        self.stack.deinit();
        self.memory.deinit();
        self.storage.deinit();
    }
};
```

### API Documentation

Each public function should have comprehensive documentation:

```zig
/// Execute a single EVM transaction
///
/// Processes a transaction through the complete EVM execution pipeline,
/// including validation, gas calculation, and state changes.
///
/// Args:
///   self: EVM executor instance
///   transaction: Transaction to execute
///   block_context: Current block information
///
/// Returns:
///   TransactionResult containing execution details:
///   - success: Whether transaction completed successfully
///   - gas_used: Amount of gas consumed
///   - return_data: Any data returned by the transaction
///   - state_changes: List of storage/balance modifications
///
/// Errors:
///   - OutOfGas: Transaction consumed all available gas
///   - InvalidTransaction: Transaction failed validation
///   - ExecutionError: Runtime error during execution
///   - OutOfMemory: Memory allocation failed
///
/// Performance:
///   - Time complexity: O(n) where n is number of opcodes
///   - Space complexity: O(m) where m is memory usage
///   - Typical execution time: 1-5ms for simple transfers
///
/// Safety:
///   This function is thread-safe when called on separate executor instances.
///   Do not share executor instances between threads.
///
/// Example:
/// ```zig
/// const transaction = Transaction{
///     .from = sender_address,
///     .to = recipient_address,
///     .value = BigInt.init(1000),
///     .gas_limit = 21000,
///     .gas_price = BigInt.init(20000000000),
///     .data = &[_]u8{},
/// };
///
/// const result = try executor.executeTransaction(transaction, block_context);
/// if (result.success) {
///     std.log.info("Transaction successful, gas used: {}", .{result.gas_used});
/// }
/// ```
pub fn executeTransaction(
    self: *Self,
    transaction: Transaction,
    block_context: BlockContext,
) EVMError!TransactionResult {
    // Implementation...
}
```

### README Standards

See our main [README.md](../README.md) for the template. Key sections:

1. **Clear project description**: What it does, why it's useful
2. **Quick start guide**: Get running in < 5 minutes
3. **Performance metrics**: Concrete numbers and benchmarks
4. **Architecture overview**: High-level design decisions
5. **Contributing guidelines**: Link to this document

## Pull Request Process {#pull-request-process}

### Before Submitting

1. **Run all tests**: `zig build test`
2. **Run benchmarks**: `zig build demo`
3. **Check formatting**: `zig fmt --check src/`
4. **Update documentation**: If you changed APIs
5. **Add tests**: For new functionality

### PR Template

```markdown
## Description
Brief description of changes and motivation.

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Performance improvement
- [ ] Documentation update

## Testing
- [ ] All existing tests pass
- [ ] New tests added for new functionality
- [ ] Performance benchmarks run (include results if relevant)

## Performance Impact
- Throughput change: +X% / -X% / No significant change
- Memory usage change: +X% / -X% / No significant change
- Latency change: +Xms / -Xms / No significant change

## Documentation
- [ ] Code comments updated
- [ ] API documentation updated
- [ ] README updated (if needed)
- [ ] Breaking changes documented

## Checklist
- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review of my own code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing unit tests pass locally with my changes
```

### Review Process

1. **Automated checks**: CI must pass
2. **Code review**: At least one maintainer approval
3. **Performance review**: For performance-related changes
4. **Documentation review**: For API changes
5. **Final approval**: Project maintainer

### Merge Requirements

- All CI checks pass ✅
- At least 1 approving review ✅
- No requested changes ✅
- Branch is up to date ✅
- All conversations resolved ✅

## Issue Reporting {#issue-reporting}

### Bug Reports

Use this template for bug reports:

```markdown
**Bug Description**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Set up environment with '...'
2. Run command '...'
3. See error

**Expected Behavior**
A clear and concise description of what you expected to happen.

**Actual Behavior**
What actually happened.

**Environment**
- OS: [e.g. Ubuntu 20.04]
- Zig version: [e.g. 0.15.1]
- Hardware: [e.g. AMD Ryzen 5, 16GB RAM]

**Code Example**
If applicable, add a minimal code example that reproduces the issue.

**Additional Context**
Add any other context about the problem here.

**Logs**
```
Paste relevant log output here
```
```

### Feature Requests

Use this template for feature requests:

```markdown
**Feature Description**
A clear and concise description of what you want to happen.

**Motivation**
Why is this feature important? What problem does it solve?

**Proposed Solution**
A clear and concise description of what you want to happen.

**Alternatives Considered**
A clear and concise description of any alternative solutions or features you've considered.

**Performance Impact**
How might this feature affect performance? Are there any benchmarks or analysis?

**Implementation Notes**
Any technical details about how this might be implemented.

**Additional Context**
Add any other context or screenshots about the feature request here.
```

### Performance Issues

```markdown
**Performance Issue Description**
Clear description of the performance problem.

**Current Performance**
- Throughput: X TPS
- Latency: X ms
- Memory usage: X MB
- CPU usage: X%

**Expected Performance**
- Throughput: X TPS
- Latency: X ms
- Memory usage: X MB
- CPU usage: X%

**Benchmark Results**
```
Paste benchmark output here
```

**Environment**
- Hardware specs
- OS and version
- Zig version
- Workload characteristics

**Profiling Data**
If available, include profiling information.
```

## Community Guidelines {#community-guidelines}

### Code of Conduct

We are committed to providing a welcoming and inspiring community for all. Please read our full [Code of Conduct](CODE_OF_CONDUCT.md).

Key principles:
- **Be respectful**: Treat everyone with respect and kindness
- **Be inclusive**: Welcome newcomers and diverse perspectives
- **Be constructive**: Focus on improving the project
- **Be patient**: Help others learn and grow

### Communication Channels

- **GitHub Issues**: Bug reports, feature requests
- **GitHub Discussions**: General questions, ideas
- **Pull Requests**: Code contributions
- **Discord**: Real-time chat (link in README)

### Getting Help

1. **Check documentation**: Start with docs and README
2. **Search existing issues**: Your question might be answered
3. **Ask in discussions**: For general questions
4. **Create an issue**: For bugs or specific problems

## Recognition and Credits {#recognition}

### Contributor Recognition

We recognize contributions through:

- **Contributors list**: Maintained in README.md
- **Release notes**: Major contributions highlighted
- **Hall of fame**: Outstanding contributors featured
- **Badges**: GitHub profile badges for regular contributors

### Types of Contributions

We value all types of contributions:

- **Code contributions**: New features, bug fixes, optimizations
- **Documentation**: Improvements to docs, tutorials, examples
- **Testing**: Test cases, performance benchmarks, bug reports
- **Design**: Architecture discussions, API design
- **Community**: Helping others, organizing events, tutorials

### Attribution Guidelines

- All contributors are credited in git history
- Significant contributions mentioned in release notes
- Contributors retain copyright on their contributions
- Project uses MIT license for all contributions

---

## Quick Reference

### Common Commands

```bash
# Development workflow
zig build test              # Run all tests
zig build demo             # Run performance demo
zig fmt src/               # Format code
zig build-exe src/main.zig # Check compilation

# Benchmarking
zig build benchmark        # Full benchmark suite
zig build bench           # Quick benchmark
zig build parallel        # Parallel execution demo

# Testing specific modules
zig test src/test_evm_basic.zig
zig test src/test_parallel_execution.zig
```

### Useful Resources

- [Zig Documentation](https://ziglang.org/documentation/)
- [EVM Fundamentals Guide](EVM_FUNDAMENTALS.md)
- [Developer Guide](DEVELOPER_GUIDE.md)
- [Enterprise Integration](ENTERPRISE_INTEGRATION.md)
- [Performance Optimization Guide](OPTIMIZED_PARALLEL_IMPLEMENTATION.md)

### Contact

- **Maintainers**: See MAINTAINERS.md
- **Security Issues**: security@zig-evm.org
- **General Questions**: Use GitHub Discussions

## Additional Resources

For questions about contributing, create an issue or refer to the documentation above.