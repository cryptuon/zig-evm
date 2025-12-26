# Parallel Execution Guide

This guide explains how to use Zig EVM's parallel transaction execution for L2/Rollup block processing.

## Overview

Zig EVM supports parallel execution of independent transactions within a block, providing significant throughput improvements for L2/Rollup scenarios.

### Key Features

- **Dependency Analysis**: O(n) hash-based conflict detection
- **Wave-Based Execution**: Groups independent transactions
- **Work-Stealing Thread Pool**: Efficient load balancing
- **Speculative Execution**: Optimistic parallelism with rollback

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Transaction Batch                         │
│  [Tx0] [Tx1] [Tx2] [Tx3] [Tx4] [Tx5] [Tx6] [Tx7] [Tx8]     │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  Dependency Analyzer                         │
│                                                              │
│  Address Conflicts:                                          │
│    Tx0.from == Tx3.to  → Tx0 ─depends─▶ Tx3                 │
│    Tx1.from == Tx5.from → Tx1 ─depends─▶ Tx5 (nonce order)  │
│                                                              │
│  Storage Conflicts:                                          │
│    Tx2 writes slot X, Tx6 reads slot X → Tx2 ─depends─▶ Tx6 │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Wave Builder                              │
│                                                              │
│  Wave 1: [Tx0, Tx2, Tx4, Tx7]  ← No dependencies            │
│  Wave 2: [Tx1, Tx3, Tx6]       ← Depends on Wave 1          │
│  Wave 3: [Tx5, Tx8]            ← Depends on Wave 2          │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│               Work-Stealing Thread Pool                      │
│                                                              │
│  Thread 0: [Tx0] ────▶ [Tx1] ────▶ [Tx5]                   │
│  Thread 1: [Tx2] ────▶ [Tx3] ────▶ [Tx8]                   │
│  Thread 2: [Tx4] ────▶ [Tx6]                                │
│  Thread 3: [Tx7]       (steals work from Thread 2)          │
└─────────────────────────────────────────────────────────────┘
```

## Dependency Types

### 1. Address Conflicts

Transactions conflict if they share sender or receiver:

```
Tx0: A → B (transfer from A to B)
Tx1: B → C (transfer from B to C)
      ↑
      └── Tx0's output affects Tx1's input
```

**Result**: Tx1 must execute after Tx0.

### 2. Nonce Ordering

Same-sender transactions must maintain nonce order:

```
Tx0: from=A, nonce=5
Tx1: from=A, nonce=6
Tx2: from=A, nonce=7
```

**Result**: Tx0 → Tx1 → Tx2 (sequential).

### 3. Storage Conflicts

Transactions accessing same storage slots:

```
Tx0: SSTORE(slot=0x1, value=100)
Tx1: SLOAD(slot=0x1)
```

**Result**: Tx1 must execute after Tx0.

## Using Batch Executor

### C API

```c
#include "zigevm.h"

int main() {
    // Configure batch execution
    BatchConfig config = {
        .max_threads = 8,           // Use 8 worker threads
        .enable_parallel = true,    // Enable parallel execution
        .enable_speculation = false, // Conservative mode
        .chain_id = 1,
        .block_number = 12345678,
        .block_timestamp = 1234567890,
        .block_gas_limit = 30000000,
    };

    // Create batch executor
    BatchHandle batch = batch_create(&config);

    // Set up initial state
    uint8_t addr1[20] = {0x11, ...};
    uint8_t balance1[32] = {0x00, ..., 0x64}; // 100 ETH
    batch_set_account(batch, addr1, balance1, 0, NULL, 0);

    // Prepare transactions
    BatchTransaction txs[1000];
    for (int i = 0; i < 1000; i++) {
        txs[i] = (BatchTransaction){
            .from = {...},
            .to = {...},
            .has_to = true,
            .value = {...},
            .data = tx_data[i],
            .data_len = tx_data_len[i],
            .gas_limit = 100000,
        };
    }

    // Execute batch
    BatchStats stats;
    EVMError err = batch_execute(batch, txs, 1000, &stats);

    if (err == EVM_OK) {
        printf("Executed %u transactions\n", stats.total_transactions);
        printf("Successful: %u\n", stats.successful_transactions);
        printf("Failed: %u\n", stats.failed_transactions);
        printf("Total gas: %lu\n", stats.total_gas_used);
        printf("Time: %lu ns\n", stats.execution_time_ns);
        printf("Parallel waves: %u\n", stats.parallel_waves);
        printf("Max parallelism: %u\n", stats.max_parallelism);
    }

    // Get individual results
    for (size_t i = 0; i < batch_results_count(batch); i++) {
        BatchResult result;
        if (batch_get_result(batch, i, &result)) {
            printf("Tx %u: success=%d, gas=%lu\n",
                   result.tx_index, result.success, result.gas_used);
        }
    }

    batch_destroy(batch);
    return 0;
}
```

### Python

```python
from zigevm import BatchExecutor, BatchConfig, BatchTransaction

# Configure
config = BatchConfig(
    max_threads=8,
    enable_parallel=True,
    chain_id=1,
    block_number=12345678,
)

# Create executor
executor = BatchExecutor(config)

# Set up state
executor.set_account(
    address="0x1111...",
    balance=100 * 10**18,
    nonce=0,
)

# Prepare transactions
transactions = [
    BatchTransaction(
        from_addr="0x1111...",
        to_addr="0x2222...",
        value=1 * 10**18,
        gas_limit=21000,
    )
    for _ in range(1000)
]

# Execute
stats = executor.execute(transactions)

print(f"Throughput: {stats.total_transactions / (stats.execution_time_ns / 1e9):.0f} tx/s")
print(f"Parallel efficiency: {stats.max_parallelism / config.max_threads:.1%}")
```

### JavaScript

```javascript
const { BatchExecutor } = require('zigevm');

const executor = new BatchExecutor({
    maxThreads: 8,
    enableParallel: true,
    chainId: 1n,
    blockNumber: 12345678n,
});

// Set up state
executor.setAccount({
    address: '0x1111...',
    balance: 100n * 10n**18n,
});

// Prepare transactions
const transactions = Array(1000).fill(null).map(() => ({
    from: '0x1111...',
    to: '0x2222...',
    value: 1n * 10n**18n,
    gasLimit: 21000n,
}));

// Execute
const stats = await executor.execute(transactions);

console.log(`Transactions: ${stats.totalTransactions}`);
console.log(`Parallel waves: ${stats.parallelWaves}`);
console.log(`Speedup: ${stats.maxParallelism}x`);
```

## Configuration Options

### max_threads

Number of worker threads for parallel execution.

**Recommended**: Number of CPU cores, or slightly less.

```c
.max_threads = 8  // Use 8 threads
```

### enable_parallel

Enable/disable parallel execution.

```c
.enable_parallel = true   // Parallel mode
.enable_parallel = false  // Sequential mode (for debugging)
```

### enable_speculation

Enable speculative execution for higher parallelism.

```c
.enable_speculation = true   // Optimistic parallelism
.enable_speculation = false  // Conservative (no rollbacks)
```

**Trade-offs**:
- `true`: Higher parallelism, but may need rollbacks
- `false`: Lower parallelism, guaranteed no wasted work

## Performance Tuning

### Optimal Batch Size

```
Batch Size    Throughput    Overhead
─────────────────────────────────────
10            Low           High (setup cost dominates)
100           Medium        Moderate
1000          High          Low
10000         Very High     Very Low
100000+       Maximum       Minimal
```

**Recommendation**: Batch sizes of 100-10000 transactions.

### Thread Count

```
Threads    Speedup (typical workload)
─────────────────────────────────────
1          1.0x (baseline)
2          1.8-2.0x
4          3.2-3.8x
8          5.0-6.5x
16         6.0-8.0x (diminishing returns)
```

### Workload Characteristics

**High Parallelism** (5-6x speedup):
- Many independent transfers
- Different senders/receivers
- No shared storage access

**Low Parallelism** (1-2x speedup):
- Same sender (nonce ordering)
- Shared contract state
- DEX trades on same pair

## Benchmarking

### Running Benchmarks

```bash
zig build benchmark
```

### Sample Output

```
Zig EVM Parallel Execution Benchmark
====================================

Batch size: 10000 transactions
Threads: 8

Sequential execution:
  Time: 2450 ms
  Throughput: 4,081 tx/s

Parallel execution:
  Time: 410 ms
  Throughput: 24,390 tx/s
  Waves: 127
  Max parallelism: 8
  Speedup: 5.97x

Dependency analysis:
  Time: 12 ms
  Overhead: 2.9%
```

## Best Practices

### 1. Batch Similar Transactions

Group transactions with similar gas requirements:

```python
# Good: Uniform gas limits
simple_transfers = [tx for tx in txs if tx.gas_limit < 25000]
contract_calls = [tx for tx in txs if tx.gas_limit >= 25000]

executor.execute(simple_transfers)
executor.execute(contract_calls)
```

### 2. Pre-sort by Sender

Sort transactions by sender to improve nonce handling:

```python
txs.sort(key=lambda tx: (tx.from_addr, tx.nonce))
```

### 3. Monitor Parallelism

Track actual parallelism achieved:

```python
stats = executor.execute(transactions)
parallelism_ratio = stats.max_parallelism / config.max_threads

if parallelism_ratio < 0.5:
    print("Warning: Low parallelism, consider transaction ordering")
```

### 4. Handle Failures Gracefully

```python
for i, result in enumerate(executor.get_results()):
    if not result.success:
        if result.reverted:
            handle_revert(transactions[i], result.return_data)
        else:
            handle_error(transactions[i], result.error_code)
```

## Speculative Execution

### How It Works

1. **Optimistic Phase**: Execute transactions assuming no conflicts
2. **Validation Phase**: Check for actual conflicts
3. **Rollback Phase**: Re-execute conflicting transactions

```
Transaction    Optimistic    Validation    Final
───────────────────────────────────────────────
Tx0            Execute       OK            ✓
Tx1            Execute       OK            ✓
Tx2            Execute       Conflict!     Rollback → Re-execute
Tx3            Execute       OK            ✓
```

### When to Use

**Enable speculation when**:
- Low expected conflict rate (<10%)
- High value of parallelism
- Large batches (1000+ transactions)

**Disable speculation when**:
- High conflict rate (>30%)
- Deterministic ordering required
- Debugging

## Limitations

1. **No Cross-Transaction Calls**: CALL between transactions in same batch not supported
2. **CREATE/CREATE2**: Contract creation addresses must be pre-computed
3. **Block-Level Operations**: BLOCKHASH limited to current block context
4. **Gas Refunds**: Calculated per-transaction, not aggregated

## Troubleshooting

### Low Parallelism

**Symptoms**: `max_parallelism` much lower than `max_threads`

**Causes**:
- Same sender for many transactions
- Shared contract state
- Sequential dependencies

**Solutions**:
- Distribute transactions across more senders
- Batch by contract/state access pattern
- Use speculative execution

### High Rollback Rate

**Symptoms**: Many transactions re-executed with speculation

**Causes**:
- High storage conflict rate
- Incorrect dependency analysis

**Solutions**:
- Disable speculation for this workload
- Pre-analyze storage access patterns
- Increase wave granularity

### Memory Usage

**Symptoms**: High memory consumption during batch execution

**Causes**:
- Large return data
- Many logs per transaction
- Deep call stacks

**Solutions**:
- Limit return data size
- Process results in chunks
- Increase memory pool size
