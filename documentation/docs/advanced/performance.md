# Performance Tuning

Optimize Zig EVM for maximum throughput and efficiency.

## Baseline Performance

| Metric | Value |
|--------|-------|
| Single execution | ~1M gas/second |
| Parallel throughput | 5-6x improvement (8 threads) |
| Memory overhead | ~100KB per EVM instance |
| Startup time | <1ms for instance creation |

## Parallel Execution Optimization

### Thread Count Selection

| Threads | Typical Speedup |
|---------|-----------------|
| 1 | 1.0x (baseline) |
| 2 | 1.8-2.0x |
| 4 | 3.2-3.8x |
| 8 | 5.0-6.5x |
| 16 | 6.0-8.0x (diminishing returns) |

**Recommendation**: Use `number_of_cpu_cores - 1` for best results.

### Batch Size Optimization

| Batch Size | Throughput | Overhead |
|------------|------------|----------|
| 10 | Low | High (setup dominates) |
| 100 | Medium | Moderate |
| 1000 | High | Low |
| 10000 | Very High | Very Low |
| 100000+ | Maximum | Minimal |

**Recommendation**: 1000-10000 transactions per batch.

### Workload Characteristics

**High Parallelism** (5-6x speedup):

- Independent transfers
- Different senders/receivers
- No shared storage

**Low Parallelism** (1-2x speedup):

- Same sender (nonce ordering)
- Shared contract state
- DEX trades on same pair

### Configuration Tuning

```python
from zigevm import BatchExecutor, BatchConfig

# High-throughput configuration
config = BatchConfig(
    max_threads=8,           # Match CPU cores
    enable_parallel=True,
    enable_speculation=True,  # For low-conflict workloads
    block_gas_limit=30000000,
)
```

## Memory Optimization

### Instance Pooling

Reuse EVM instances instead of creating new ones:

```python
class EVMPool:
    def __init__(self, size=8):
        self.pool = [EVM() for _ in range(size)]
        self.available = list(range(size))

    def acquire(self):
        if self.available:
            idx = self.available.pop()
            self.pool[idx].reset()
            return idx, self.pool[idx]
        return None, None

    def release(self, idx):
        self.available.append(idx)
```

### Memory Limits

Set appropriate memory limits to prevent excessive allocation:

```python
# Limit memory expansion
evm.set_gas_limit(1000000)  # Implicitly limits memory growth
```

### Arena Allocators

In Zig, use arena allocators for temporary operations:

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();

var evm = try EVM.init(arena.allocator());
// All memory freed when arena is deinitialized
```

## Gas Optimization

### Efficient Gas Estimation

```python
def estimate_gas(evm, code, calldata):
    # Use binary search for accurate estimation
    low, high = 21000, 10_000_000

    while low < high:
        mid = (low + high) // 2
        evm.set_gas_limit(mid)
        evm.reset()

        result = evm.execute(code, calldata)

        if result.success:
            high = mid
        else:
            low = mid + 1

    return low * 1.1  # Add 10% buffer
```

### Avoid Expensive Operations

| Operation | Cost | Alternative |
|-----------|------|-------------|
| SSTORE | 5000-20000 | Batch writes |
| CREATE | 32000 | CREATE2 for predictable addresses |
| Memory expansion | Quadratic | Fixed-size buffers |
| LOG4 | 1875+ | Fewer topics |

## Benchmarking

### Running Benchmarks

```bash
# Full benchmark suite
zig build bench-full

# Parallel execution benchmarks
zig build benchmark

# Simple benchmarks
zig build bench
```

### Profiling

```bash
# Build with profiling
zig build -Doptimize=ReleaseFast

# Run with perf
perf record -g ./zig-out/bin/zig-evm
perf report
```

### Metrics to Track

| Metric | Target |
|--------|--------|
| Transactions/second | >10,000 |
| Gas/second | >1M |
| Parallelism ratio | >0.7 |
| Memory per TX | <10KB |

## Optimization Techniques

### 1. Pre-sort Transactions

Sort by sender to improve nonce handling:

```python
transactions.sort(key=lambda tx: (tx.from_addr, tx.nonce))
```

### 2. Group Similar Transactions

Batch transactions with similar characteristics:

```python
# Separate simple transfers from contract calls
simple = [tx for tx in txs if tx.gas_limit < 25000]
complex = [tx for tx in txs if tx.gas_limit >= 25000]

# Execute in separate batches
executor.execute(simple)
executor.execute(complex)
```

### 3. Pre-analyze Dependencies

For known contracts, pre-compute access patterns:

```python
def analyze_erc20_transfer(tx):
    return {
        'reads': [tx.from_addr, tx.to_addr],
        'writes': [tx.from_addr, tx.to_addr],
    }
```

### 4. Use Speculation Wisely

Enable speculation only for low-conflict workloads:

```python
config = BatchConfig(
    enable_speculation=conflict_rate < 0.1
)
```

### 5. Optimize Calldata

Minimize calldata size:

```python
# Use function selectors efficiently
# 4 bytes instead of full function signature
```

## Production Deployment

### Resource Allocation

| Component | Recommendation |
|-----------|---------------|
| CPU | 8+ cores dedicated |
| Memory | 16GB+ |
| Storage | SSD for state access |

### Monitoring

Track these metrics:

- Transaction throughput
- Gas utilization
- Parallel wave count
- Rollback rate (if speculation enabled)
- Memory usage

### Error Handling

```python
def execute_with_retry(executor, transactions, max_retries=3):
    for attempt in range(max_retries):
        try:
            stats = executor.execute(transactions)
            if stats.failed_transactions == 0:
                return stats
            # Handle failures
            failed = get_failed_transactions(executor)
            transactions = retry_failed(failed)
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            time.sleep(0.1 * (2 ** attempt))
```

### Scaling

For very high throughput:

1. **Horizontal scaling**: Multiple executor instances
2. **Sharding**: Partition transactions by sender
3. **Pipelining**: Overlap dependency analysis with execution

## Performance Comparison

### vs. Other EVM Implementations

| Implementation | Throughput | Parallelism |
|---------------|------------|-------------|
| geth | ~1000 tx/s | Sequential |
| reth | ~2000 tx/s | Limited |
| **zig-evm** | ~10000 tx/s | Full parallel |

### Benchmark Results

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

## Troubleshooting Performance Issues

### Low Throughput

**Symptoms**: <5000 tx/s

**Check**:

1. Thread count configuration
2. Batch size (increase if <100)
3. Workload conflicts

### High Memory Usage

**Symptoms**: >1GB for 10000 tx

**Check**:

1. Return data accumulation
2. Log storage
3. Memory leaks in custom code

### Inconsistent Performance

**Symptoms**: Variable tx/s

**Check**:

1. System load
2. GC pauses (in binding languages)
3. I/O contention
