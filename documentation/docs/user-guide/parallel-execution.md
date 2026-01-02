# Parallel Execution

Learn how to use Zig EVM's parallel transaction execution for high-throughput block processing.

## Overview

Zig EVM supports parallel execution of independent transactions, providing significant throughput improvements for L2/Rollup scenarios.

### Key Features

| Feature | Description |
|---------|-------------|
| **Dependency Analysis** | O(n) hash-based conflict detection |
| **Wave-Based Execution** | Groups independent transactions |
| **Work-Stealing Thread Pool** | Efficient load balancing |
| **Speculative Execution** | Optimistic parallelism with rollback |

### Performance

| Transactions | Sequential | Parallel (8 threads) | Speedup |
|-------------|------------|---------------------|---------|
| 100 | 96.8ms | 18.9ms | 5.1x |
| 500 | 485ms | 82ms | 5.9x |
| 1000 | 970ms | 162ms | 6.0x |

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

### Address Conflicts

Transactions conflict if they share sender or receiver:

```
Tx0: A → B (transfer from A to B)
Tx1: B → C (transfer from B to C)
      ↑
      └── Tx0's output affects Tx1's input

Result: Tx1 must execute after Tx0
```

### Nonce Ordering

Same-sender transactions must maintain nonce order:

```
Tx0: from=A, nonce=5
Tx1: from=A, nonce=6
Tx2: from=A, nonce=7

Result: Tx0 → Tx1 → Tx2 (sequential)
```

### Storage Conflicts

Transactions accessing same storage slots:

```
Tx0: SSTORE(slot=0x1, value=100)
Tx1: SLOAD(slot=0x1)

Result: Tx1 must execute after Tx0
```

## Using Batch Executor

=== "Python"

    ```python
    from zigevm import BatchExecutor, BatchConfig, BatchTransaction

    # Configure batch execution
    config = BatchConfig(
        max_threads=8,           # Worker threads
        enable_parallel=True,    # Enable parallel mode
        enable_speculation=False, # Conservative mode
        chain_id=1,
        block_number=12345678,
        block_timestamp=1234567890,
        block_gas_limit=30000000,
    )

    # Create executor
    executor = BatchExecutor(config)

    # Set up initial state
    executor.set_account(
        address="0x1111111111111111111111111111111111111111",
        balance=100 * 10**18,
        nonce=0,
    )

    # Prepare transactions
    transactions = [
        BatchTransaction(
            from_addr="0x1111111111111111111111111111111111111111",
            to_addr="0x2222222222222222222222222222222222222222",
            value=1 * 10**18,
            gas_limit=21000,
        )
        for _ in range(1000)
    ]

    # Execute batch
    stats = executor.execute(transactions)

    print(f"Transactions: {stats.total_transactions}")
    print(f"Successful: {stats.successful_transactions}")
    print(f"Failed: {stats.failed_transactions}")
    print(f"Total gas: {stats.total_gas_used}")
    print(f"Time: {stats.execution_time_ns / 1e6:.2f} ms")
    print(f"Parallel waves: {stats.parallel_waves}")
    print(f"Max parallelism: {stats.max_parallelism}")

    # Get individual results
    for i, result in enumerate(executor.get_results()):
        if not result.success:
            print(f"Tx {i} failed: {result.error_code}")
    ```

=== "JavaScript"

    ```javascript
    const { BatchExecutor } = require('zigevm');

    const executor = new BatchExecutor({
        maxThreads: 8,
        enableParallel: true,
        enableSpeculation: false,
        chainId: 1n,
        blockNumber: 12345678n,
        blockTimestamp: 1234567890n,
        blockGasLimit: 30000000n,
    });

    // Set up state
    executor.setAccount({
        address: '0x1111111111111111111111111111111111111111',
        balance: 100n * 10n**18n,
    });

    // Prepare transactions
    const transactions = Array(1000).fill(null).map(() => ({
        from: '0x1111111111111111111111111111111111111111',
        to: '0x2222222222222222222222222222222222222222',
        value: 1n * 10n**18n,
        gasLimit: 21000n,
    }));

    // Execute
    const stats = await executor.execute(transactions);

    console.log(`Transactions: ${stats.totalTransactions}`);
    console.log(`Parallel waves: ${stats.parallelWaves}`);
    console.log(`Speedup: ${stats.maxParallelism}x`);
    ```

=== "C"

    ```c
    #include "zigevm.h"

    int main() {
        BatchConfig config = {
            .max_threads = 8,
            .enable_parallel = true,
            .enable_speculation = false,
            .chain_id = 1,
            .block_number = 12345678,
            .block_timestamp = 1234567890,
            .block_gas_limit = 30000000,
        };

        BatchHandle batch = batch_create(&config);

        // Set up accounts
        uint8_t addr[20] = {0x11, /* ... */};
        uint8_t balance[32] = {/* 100 ETH */};
        batch_set_account(batch, addr, balance, 0, NULL, 0);

        // Prepare transactions
        BatchTransaction txs[1000];
        for (int i = 0; i < 1000; i++) {
            txs[i] = (BatchTransaction){
                .from = {0x11, /* ... */},
                .to = {0x22, /* ... */},
                .has_to = true,
                .value = {/* 1 ETH */},
                .gas_limit = 21000,
            };
        }

        // Execute
        BatchStats stats;
        batch_execute(batch, txs, 1000, &stats);

        printf("Transactions: %u\n", stats.total_transactions);
        printf("Time: %lu ns\n", stats.execution_time_ns);
        printf("Parallel waves: %u\n", stats.parallel_waves);

        batch_destroy(batch);
        return 0;
    }
    ```

## Configuration Options

### max_threads

Number of worker threads for parallel execution.

**Recommendation**: Number of CPU cores, or slightly less.

```python
config = BatchConfig(max_threads=8)
```

### enable_parallel

Enable/disable parallel execution.

```python
config = BatchConfig(
    enable_parallel=True,   # Parallel mode
    # enable_parallel=False  # Sequential mode (debugging)
)
```

### enable_speculation

Enable speculative execution for higher parallelism.

```python
config = BatchConfig(
    enable_speculation=True,   # Optimistic parallelism
    # enable_speculation=False  # Conservative (no rollbacks)
)
```

**Trade-offs**:

| Setting | Pros | Cons |
|---------|------|------|
| `True` | Higher parallelism | May need rollbacks |
| `False` | No wasted work | Lower parallelism |

## Performance Tuning

### Optimal Batch Size

| Batch Size | Throughput | Overhead |
|------------|------------|----------|
| 10 | Low | High (setup cost dominates) |
| 100 | Medium | Moderate |
| 1000 | High | Low |
| 10000 | Very High | Very Low |
| 100000+ | Maximum | Minimal |

**Recommendation**: Batch sizes of 100-10000 transactions.

### Thread Scaling

| Threads | Speedup (typical) |
|---------|------------------|
| 1 | 1.0x (baseline) |
| 2 | 1.8-2.0x |
| 4 | 3.2-3.8x |
| 8 | 5.0-6.5x |
| 16 | 6.0-8.0x (diminishing) |

### Workload Characteristics

**High Parallelism** (5-6x speedup):

- Many independent transfers
- Different senders/receivers
- No shared storage access

**Low Parallelism** (1-2x speedup):

- Same sender (nonce ordering)
- Shared contract state
- DEX trades on same pair

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

## Best Practices

### 1. Batch Similar Transactions

Group transactions with similar gas requirements:

```python
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

## Limitations

1. **No Cross-Transaction Calls**: CALL between transactions in same batch not supported
2. **CREATE/CREATE2**: Contract creation addresses must be pre-computed
3. **Block-Level Operations**: BLOCKHASH limited to current block context
4. **Gas Refunds**: Calculated per-transaction, not aggregated
