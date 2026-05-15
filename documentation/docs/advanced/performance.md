# Performance Tuning

How to get the most out of Zig EVM's parallel batch executor.

!!! note "Source of numbers"
    The only published performance numbers for Zig EVM come from the
    project README: 5.1x / 5.9x / 6.0x speedup for 100 / 500 / 1000
    independent transactions at 8 threads. All other numbers depend on
    your hardware, workload, and build mode — measure with the bundled
    benchmark targets before tuning.

## Build Mode

Always benchmark and deploy with an optimized build:

```bash
zig build -Doptimize=ReleaseFast
zig build bench -Doptimize=ReleaseFast
zig build benchmark -Doptimize=ReleaseFast
zig build bench-full -Doptimize=ReleaseFast
```

`Debug` builds include safety checks and are not representative of
production performance.

## Parallel Execution Tuning

The optimized scheduler lives in `src/parallel_optimized.zig` and is
driven via the C ABI `BatchConfig` struct
(see `include/zigevm.h`). Tunables:

| Field | Meaning |
|-------|---------|
| `max_threads` | Maximum worker threads in the pool |
| `enable_parallel` | Enable wave-based parallel execution |
| `enable_speculation` | Enable optimistic / speculative execution |
| `chain_id`, `block_*`, `coinbase` | Block context applied to every tx |

### Workload Characteristics

Parallelism is bounded by transaction conflicts. The dependency
analyzer detects conflicts on:

- Sender / receiver addresses (balance + nonce)
- Storage slots read or written

**Higher parallelism**: independent transfers, distinct senders, no
shared contract state.

**Lower parallelism**: bursts from the same sender (nonce ordering
forces serialization), hot contracts (DEX pairs, single AMM pool),
or write-heavy access to the same storage slots.

### Thread Count

There is no universally optimal value — it depends on physical core
count, hyper-threading behaviour, and your workload's parallelism
ceiling. The README's 5–6x table was measured with `max_threads = 8`;
start there and benchmark for your machine.

## Measuring

Use the bundled targets to collect numbers on your own hardware:

```bash
zig build benchmark      # parallel optimization benchmarks
zig build bench          # simple benchmarks
zig build bench-full     # comprehensive suite
zig build demo           # benchmark demonstration
zig build parallel-opt   # optimized parallel example
```

The `BatchStats` struct returned from `batch_execute` exposes:

- `total_transactions`, `successful_transactions`, `failed_transactions`,
  `reverted_transactions`
- `total_gas_used`
- `execution_time_ns`
- `parallel_waves`, `max_parallelism`

Track these to understand whether you are bottlenecked on dependency
chains (low `max_parallelism`) or raw execution speed.

## Memory and Allocators

In Zig you can pass any allocator into `EVM.init`. For short-lived
runs (e.g. simulating a single batch) an arena allocator avoids
per-call free overhead:

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();

var evm = try EVM.init(arena.allocator());
// no need to deinit individual structures; arena frees in bulk
```

For long-running services, prefer a general-purpose allocator and
reuse EVM instances by calling `evm_reset` between executions instead
of destroying and recreating them.

## Gas

Gas costs in `src/main.zig`'s `getGasCost` match Ethereum semantics:
zero-cost ops (`STOP`), cheap ops (most arithmetic and bitwise = 3),
medium ops (`SIGNEXTEND`, `SELFBALANCE` = 5), `SHA3` = 30 base, and
storage / account access charged in-opcode per EIP-2929. The fastest
way to reduce gas is to reduce `SSTORE` and external account access.

## What's Not Yet Benchmarked

The README's performance table is the only published, source-grounded
number. The repo does not currently include comparison data against
other EVM implementations; do not rely on third-party numbers without
measuring under identical workloads.
