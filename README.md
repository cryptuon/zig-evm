# Zig EVM

A high-performance Ethereum Virtual Machine implementation in Zig, featuring parallel transaction execution and comprehensive EVM opcode support.

## Quick Start

```bash
# Build and run basic EVM
zig build run

# Run tests
zig build test

# Run parallel execution demo
zig build parallel

# Run optimized parallel execution demo
zig build parallel-opt

# Install globally
zig build install
```

## Features

### EVM Implementation
- **80+ opcodes implemented**: Complete instruction set including arithmetic, comparison, bitwise, stack, memory, storage, and flow control operations
- **256-bit arithmetic**: Full BigInt support for EVM-compliant calculations
- **EVM stack**: 1024-item limit with proper overflow/underflow handling
- **Dynamic memory**: Automatic expansion with zero initialization
- **Storage operations**: SLOAD/SSTORE with gas-accurate implementation
- **Environmental context**: Block and transaction context simulation

### Gas System
- Ethereum-compliant gas costs for all operations
- Real-time gas consumption tracking
- Configurable gas limits with overflow protection
- Out-of-gas error handling

### Parallel Execution
- Hash-based dependency analysis (O(n) complexity)
- Work-stealing thread pool for load balancing
- Speculative execution with rollback capabilities
- 5-6x throughput improvement for independent transactions
- Memory pool optimization reducing allocation overhead

## Project Structure

```
├── src/
│   ├── main.zig          # EVM core implementation
│   ├── bigint.zig        # 256-bit arithmetic
│   ├── memory.zig        # EVM memory
│   ├── stack.zig         # EVM stack
│   ├── parallel.zig      # Parallel execution framework
│   ├── parallel_optimized.zig # Optimized parallel implementation
│   └── opcodes/          # 80+ individual opcode implementations
├── docs/                 # Comprehensive documentation
└── tests/                # Comprehensive test suite (145+ tests)
```

## Example Usage

### Basic EVM Execution
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var evm = try EVM.init(allocator);
defer evm.deinit();

// Execute bytecode: PUSH1 3, PUSH1 4, ADD, PUSH1 2, MUL, STOP
const bytecode = [_]u8{ 0x60, 0x03, 0x60, 0x04, 0x01, 0x60, 0x02, 0x02, 0x00 };
evm.code = &bytecode;
evm.setGasLimit(21000);

try evm.execute();
// Result: (3 + 4) * 2 = 14
```

### Parallel Transaction Processing
```zig
var executor = try parallel.ParallelExecutor.init(allocator, 4);
defer executor.deinit();

const results = try executor.executeTransactionBatch(transactions);
// Achieves 5-6x throughput improvement for independent transactions
```

## Performance Benchmarks

| Transaction Count | Sequential | Parallel | Speedup |
|------------------|------------|----------|---------|
| 50               | 48.3ms     | 12.1ms   | 4.0x    |
| 100              | 96.8ms     | 18.9ms   | 5.1x    |
| 200              | 194.2ms    | 32.5ms   | 6.0x    |

## Documentation

- [Developer Guide](docs/DEVELOPER_GUIDE.md) - Setup and API reference
- [EVM Fundamentals](docs/EVM_FUNDAMENTALS.md) - Educational EVM concepts
- [Opcodes](docs/OPCODES.md) - Complete implementation status
- [Contributing](docs/CONTRIBUTING.md) - Contribution guidelines

## License

MIT License - see [LICENSE](LICENSE) for details.