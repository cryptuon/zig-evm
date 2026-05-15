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

## Using the Batch Executor

!!! info "Where the API lives"
    Batch / parallel execution is implemented inside Zig
    (`src/batch_executor.zig`, `src/parallel_optimized.zig`) and exposed
    through the **C ABI** in `include/zigevm.h`
    (`batch_create`, `batch_set_account`, `batch_set_storage`,
    `batch_execute`, `batch_get_result`, `batch_destroy`). The current
    Python, Rust, and JavaScript wrappers in `bindings/` only wrap the
    single-EVM API; to drive parallel execution today, call the C ABI
    directly (e.g. via `ctypes` / N-API / `bindgen`) or use the Zig API.

### C ABI Example

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

For a Zig-side example, see `src/parallel_optimized_example.zig` and run
`zig build parallel-opt`.

## Configuration Options

The `BatchConfig` struct in `include/zigevm.h`:

| Field | Type | Meaning |
|-------|------|---------|
| `max_threads` | `uint32_t` | Maximum worker threads |
| `enable_parallel` | `bool` | Enable wave-based parallel execution |
| `enable_speculation` | `bool` | Enable speculative execution + rollback |
| `chain_id` | `uint64_t` | Chain ID applied to every transaction |
| `block_number` | `uint64_t` | Block number |
| `block_timestamp` | `uint64_t` | Block timestamp |
| `block_gas_limit` | `uint64_t` | Block gas limit |
| `coinbase` | `uint8_t[20]` | Coinbase address |

### enable_parallel

When `false`, transactions are executed sequentially — useful as a
baseline for benchmarking or for deterministic debugging.

### enable_speculation

| Setting | Pros | Cons |
|---------|------|------|
| `true` | Higher parallelism for low-conflict workloads | Conflicting transactions are re-executed |
| `false` | No wasted work | Lower achievable parallelism |

## Performance Tuning

The only published numbers from the project README are the speedups in
the table at the top of this page (5.1x / 5.9x / 6.0x at 100 / 500 /
1000 independent transactions on 8 threads). Use the bundled benchmarks
(`zig build benchmark`, `zig build parallel-opt`, `zig build bench-full`)
to measure your own workload before tuning, and see
[Performance Tuning](../advanced/performance.md).

### Workload Characteristics

The dependency analyzer detects conflicts on sender / receiver addresses
and on storage slots that are read or written. Workloads parallelize
well when senders, receivers, and storage slots are largely disjoint;
they serialize when many transactions share a sender (forcing nonce
ordering) or hit the same hot storage slots.

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

1. **Pre-sort by sender + nonce.** Same-sender transactions must
   serialize, so grouping them keeps the dependency graph compact.
2. **Monitor parallelism via `BatchStats`.** The `parallel_waves` and
   `max_parallelism` fields tell you whether you are bottlenecked on
   dependency chains; if `max_parallelism` is consistently far below
   `max_threads`, the workload itself is the limit.
3. **Iterate `batch_get_result` for per-transaction outcomes.** The
   `BatchResult` struct exposes `success`, `reverted`, `gas_used`,
   `error_code`, `logs_count`, and (for contract creations)
   `created_address`.
4. **Disable speculation under high conflict rates.** Re-execution
   from rollback costs gas and time.

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
