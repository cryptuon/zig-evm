# Zig EVM

A high-performance, embeddable Ethereum Virtual Machine written in Zig. It runs
independent transactions in parallel — a **measured 5-6x throughput gain over
sequential execution** — and exposes a stable C ABI so Python, Rust,
JavaScript, and C can embed the execution core directly. It's an execution
engine, not a chain: link it into your L2 sequencer, rollup prover, agent
runtime, simulator, or indexer and get parallel EVM execution without adopting
a new network, consensus layer, or token.

[![CI](https://github.com/cryptuon/zig-evm/actions/workflows/ci.yml/badge.svg)](https://github.com/cryptuon/zig-evm/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**[🌐 Site](https://zig-evm.cryptuon.com/) · [📚 Docs](https://docs.cryptuon.com/zig-evm/) · [🗺️ Roadmap](ROADMAP.md) · [🔬 Cryptuon Research](https://github.com/cryptuon)**

## Why this matters in 2026

Single-threaded EVM execution has become the bottleneck. The 2026 workloads
pushing hardest on it are new: **agentic payments** and machine-initiated,
high-frequency transactions; **on-chain and verifiable AI** that settles
results to the EVM; and **RWA settlement** that needs deterministic, auditable
execution. The **parallel-EVM** wave (Monad, MegaETH, Sei, Reth's execution
extensions) is the industry's answer — but it almost always ships as a whole
new chain or client.

Zig EVM takes the opposite approach: **the parallel execution core is a small,
embeddable library.** Wave-based parallelism groups independent transactions
and runs them concurrently, delivering the 5-6x throughput headroom that
agent-driven, high-frequency workloads need — without asking you to migrate to
a new network. If your transaction mix is largely independent (many distinct
senders/receivers, little shared-state contention), you get most of that gain;
if it's contention-heavy, you get less. See [Limitations](#limitations) and
[`docs/PARALLEL.md`](docs/PARALLEL.md) for the honest version.

### How it compares

Qualitative positioning — Zig EVM is an *embeddable engine*, the others are
mostly *chains or full clients*. Cross-project performance numbers vary by
hardware and workload; treat this table as directional, not a benchmark.

| Project | What it is | Parallel execution | Embeddable as a library | Notes |
|---------|-----------|--------------------|--------------------------|-------|
| **Zig EVM** | Embeddable EVM engine (Zig) | Wave-based, 5-6x measured on independent tx | **Yes** — stable C ABI + Python/Rust/JS bindings | Not a chain; you bring the network |
| **Monad** | Full L1 chain / client | Optimistic parallel execution | No — you run/join the chain | High-throughput chain, not a drop-in engine |
| **reth** (revm) | Full Ethereum execution client | Sequential by default; parallel via extensions | Partially — `revm` is embeddable in Rust | Mature, widely used reference EVM |
| **geth** | Full Ethereum execution client | Sequential | No — client, not a library | The de-facto reference implementation |
| **Solana SVM** | Non-EVM runtime (Sealevel) | Parallel via declared access lists | Partially (via Agave/sig) | Not EVM-compatible; different programming model |

If you want an EVM you can *link into your own system* and run in parallel, Zig
EVM occupies a spot the chains and full clients don't.

## Features

### Complete EVM Implementation
- **96+ opcodes implemented** - Full instruction set including:
  - Arithmetic, comparison, bitwise, and shift operations
  - Stack operations (PUSH1-32, DUP1-16, SWAP1-16)
  - Memory and storage operations (MLOAD, MSTORE, SLOAD, SSTORE)
  - Control flow (JUMP, JUMPI, CALL, CREATE, RETURN, REVERT)
  - Logging (LOG0-LOG4)
  - Cryptographic operations (SHA3/Keccak-256)
- **256-bit arithmetic** - Full BigInt support with modular operations
- **Gas metering** - Ethereum-compliant gas costs for all operations
- **Call stack** - Nested execution with CALL, DELEGATECALL, STATICCALL

### Parallel Execution
- **Wave-based parallelism** - measured 5-6x throughput gain over sequential execution on independent-transaction workloads
- **O(n) dependency analysis** - Hash-based conflict detection (address, nonce, and storage-slot conflicts)
- **Work-stealing thread pool** - Efficient load balancing
- **Speculative execution** - Optimistic parallelism with rollback

> The speedup depends on the transaction conflict rate. Independent transfers
> across many senders parallelize well; workloads dominated by shared state
> (e.g. many trades against one AMM pair, or long single-sender nonce chains)
> see far less. See [Limitations](#limitations).

### Embeddable via FFI
- **C ABI** - Use from any language with FFI support
- **Python bindings** - Native ctypes wrapper
- **Rust bindings** - Safe Rust API
- **JavaScript bindings** - Node.js N-API addon

## Quick Start

```bash
# Build and run
zig build run

# Run tests
zig build test

# Run Ethereum compliance tests
zig build compliance

# Build shared library for FFI
zig build lib

# Run parallel execution demo
zig build parallel-opt
```

## Usage Examples

### Zig - Direct Usage

```zig
const std = @import("std");
const EVM = @import("main.zig").EVM;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var evm = try EVM.init(gpa.allocator());
    defer evm.deinit();

    // Execute: PUSH1 3, PUSH1 5, ADD, STOP
    evm.code = &[_]u8{ 0x60, 0x03, 0x60, 0x05, 0x01, 0x00 };
    evm.setGasLimit(100000);

    try evm.execute();

    const result = evm.stack.pop().?;
    std.debug.print("Result: {}\n", .{result.data[0]}); // 8
}
```

### C - FFI Usage

```c
#include "zigevm.h"

int main() {
    EVMHandle evm = evm_create();
    evm_set_gas_limit(evm, 100000);

    uint8_t code[] = {0x60, 0x03, 0x60, 0x05, 0x01, 0x00};
    EVMResult result = evm_execute(evm, code, sizeof(code), NULL, 0);

    printf("Success: %d, Gas used: %lu\n", result.success, result.gas_used);

    evm_destroy(evm);
    return 0;
}
```

### Python

```python
from zigevm import EVM

evm = EVM()
evm.set_gas_limit(100000)

code = bytes([0x60, 0x03, 0x60, 0x05, 0x01, 0x00])
result = evm.execute(code)

print(f"Success: {result.success}, Gas used: {result.gas_used}")
evm.destroy()
```

### JavaScript

```javascript
const { EVM } = require('zigevm');

const evm = new EVM();
evm.setGasLimit(100000n);

const code = Buffer.from([0x60, 0x03, 0x60, 0x05, 0x01, 0x00]);
const result = evm.execute(code);

console.log(`Success: ${result.success}, Gas used: ${result.gasUsed}`);
evm.destroy();
```

## Performance

The headline result is a **5-6x throughput gain over sequential execution** on
batches of largely independent transactions (8 threads). The table below is a
representative run; absolute numbers are illustrative and depend on hardware,
build mode, and — critically — the transaction conflict rate. Reproduce them
with `zig build benchmark -Doptimize=ReleaseFast` and see
[`docs/BENCHMARK.md`](docs/BENCHMARK.md) for methodology.

| Transactions | Sequential | Parallel (8 threads) | Speedup |
|-------------|------------|---------------------|---------|
| 100         | 96.8ms     | 18.9ms              | 5.1x    |
| 500         | 485ms      | 82ms                | 5.9x    |
| 1000        | 970ms      | 162ms               | 6.0x    |

## Project Structure

```
zig-evm/
├── src/
│   ├── main.zig              # Core EVM implementation
│   ├── bigint.zig            # 256-bit arithmetic
│   ├── stack.zig             # EVM stack
│   ├── memory.zig            # EVM memory
│   ├── call_frame.zig        # Call stack for nested calls
│   ├── ffi.zig               # C ABI exports
│   ├── batch_executor.zig    # Parallel batch execution
│   ├── parallel_optimized.zig # Optimized parallel scheduler
│   └── opcodes/              # 96+ opcode implementations
├── include/
│   └── zigevm.h              # C header file
├── bindings/
│   ├── python/               # Python ctypes bindings
│   ├── rust/                 # Rust FFI bindings
│   └── js/                   # Node.js N-API bindings
├── tests/
│   ├── test_*.zig            # Unit tests
│   ├── eth_compliance.zig    # Ethereum test infrastructure
│   └── run_compliance.zig    # Compliance test runner
└── docs/                     # Documentation
```

## Build Targets

| Command | Description |
|---------|-------------|
| `zig build run` | Build and run CLI demo |
| `zig build test` | Run unit tests |
| `zig build compliance` | Run Ethereum compliance tests |
| `zig build lib` | Build shared/static libraries |
| `zig build parallel-opt` | Run parallel execution demo |
| `zig build bench-full` | Run comprehensive benchmark suite |
| `zig build benchmark` | Run parallel optimization benchmarks |
| `zig build bench` | Run simple benchmarks |

## Documentation

### Architecture & API
- [Architecture Overview](docs/ARCHITECTURE.md) - System design and components
- [FFI Reference](docs/FFI.md) - Complete C ABI documentation
- [Language Bindings](docs/BINDINGS.md) - Python, Rust, JavaScript guides
- [Parallel Execution](docs/PARALLEL.md) - Batch processing guide
- [Benchmarks](docs/BENCHMARK.md) - Performance numbers and optimization

### Development
- [Developer Guide](docs/DEVELOPER_GUIDE.md) - Setup and development workflows
- [EVM Fundamentals](docs/EVM_FUNDAMENTALS.md) - Educational EVM concepts
- [Opcodes](docs/OPCODES.md) - Implementation status
- [Contributing](docs/CONTRIBUTING.md) - Contribution guidelines

## Requirements

- Zig 0.13.0 or later
- For bindings:
  - Python 3.8+ (Python bindings)
  - Rust 1.70+ (Rust bindings)
  - Node.js 18+ (JavaScript bindings)

## Limitations

Zig EVM is an execution engine under active development. Being honest about
what it is and isn't:

- **Parallel speedup is workload-dependent.** The 5-6x figure holds for
  batches of independent transactions. High shared-state contention (hot
  contracts, single-sender nonce chains) reduces achievable parallelism toward
  1-2x. Measure on your own workload.
- **Batch-level constraints.** Cross-transaction `CALL`s within the same batch,
  `CREATE`/`CREATE2` address dependencies, and block-level operations have
  restrictions — see the [Limitations section of `docs/PARALLEL.md`](docs/PARALLEL.md#limitations).
- **Conformance is in progress.** Broadening Ethereum execution-spec /
  consensus-test coverage, differential fuzzing against a reference EVM, and an
  independent security audit are tracked roadmap items, not yet complete.
- **Not a chain.** There's no consensus, networking, or mempool here by design.
  You embed the engine and bring your own network.

For where this is going and what "production" means for an embeddable engine,
see the [Roadmap](ROADMAP.md) — including the **Cheapest path to production**
section.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)
- [EVM Opcodes Reference](https://www.evm.codes/)
- [Zig Programming Language](https://ziglang.org/)

---

## Part of Cryptuon Research

`zig-evm` is one of [20 open-source blockchain-infrastructure projects](https://www.cryptuon.com/projects) from **[Cryptuon Research](https://www.cryptuon.com)** — blockchain theory, shipped as protocols.

**Related projects:** [SolScript](https://solscript.cryptuon.com/) · [Tesseract](https://tesseract.cryptuon.com/) · [EVMORE](https://evmore.cryptuon.com/)

Docs: [docs.cryptuon.com/zig-evm](https://docs.cryptuon.com/zig-evm/) · Contact: [contact@cryptuon.com](mailto:contact@cryptuon.com)
