# Zig EVM

A high-performance, embeddable Ethereum Virtual Machine implementation in Zig, designed for L2/Rollup execution with parallel transaction processing.

[![CI](https://github.com/cryptuon/zig-evm/actions/workflows/ci.yml/badge.svg)](https://github.com/cryptuon/zig-evm/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

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
- **Wave-based parallelism** - 5-6x throughput improvement
- **O(n) dependency analysis** - Hash-based conflict detection
- **Work-stealing thread pool** - Efficient load balancing
- **Speculative execution** - Optimistic parallelism with rollback

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

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)(https://ethereum.github.io/yellowpaper/paper.pdf)
- [EVM Opcodes Reference](https://www.evm.codes/)
- [Zig Programming Language](https://ziglang.org/)
