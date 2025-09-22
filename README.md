# Zig EVM

An experimental Ethereum Virtual Machine (EVM) implementation in Zig for educational and research purposes.

⚠️ **Breaking changes everyday, do not use in production!**

## Quick Start

```bash
# Build and run
zig build run

# Run tests
zig build test

# Install globally
zig build install
```

## Features

- ✅ **Arithmetic Operations**: ADD, MUL, SUB, DIV, MOD, SDIV
- ✅ **Comparison Operations**: LT, GT, EQ, ISZERO, SLT
- ✅ **Bitwise Operations**: AND, OR, XOR, NOT
- ✅ **Stack Operations**: POP, DUP1-DUP3, SWAP1-SWAP3
- ✅ **Push Operations**: PUSH1, PUSH2, PUSH3, PUSH4, PUSH32
- ✅ **Memory Operations**: MLOAD, MSTORE, MSTORE8, MSIZE
- ✅ **Flow Control**: STOP, JUMP, JUMPI, JUMPDEST, PC
- ✅ **256-bit BigInt** with improved multiplication and full arithmetic
- ✅ **EVM Stack** with 1024-item limit and comprehensive error handling
- ✅ **Dynamic Memory** with automatic expansion and zero initialization
- ✅ **Modular Opcode System** with **36 implemented opcodes**
- ✅ **Comprehensive Test Suite** with **67 tests** (64 passing, 3 edge cases)
- ✅ **Jump Validation** and destination checking
- ✅ **Signed Arithmetic** support
- 🚧 Gas calculation and management
- 🚧 Environmental opcodes (ADDRESS, CALLER, etc.)
- 🚧 Contract deployment and execution

## Project Structure

```
├── src/
│   ├── main.zig          # EVM core implementation
│   ├── bigint.zig        # 256-bit arithmetic
│   ├── memory.zig        # EVM memory
│   ├── stack.zig         # EVM stack
│   └── opcodes/          # Individual opcode implementations
├── docs/                 # Documentation
└── tests/                # Test suite
```

## Current Status

The EVM can execute sophisticated bytecode with **36 implemented opcodes** across all major categories. Examples:

**Arithmetic**: `(3 + 4) * 2 = 14`
```
Bytecode: [0x60, 0x03, 0x60, 0x04, 0x01, 0x60, 0x02, 0x02, 0x00]
         PUSH1 3, PUSH1 4, ADD, PUSH1 2, MUL, STOP
Result: 14
```

**Comparison & Logic**: `(10 < 20) AND (5 == 5) = 1`
```
Bytecode: [0x60, 0x0A, 0x60, 0x14, 0x10, 0x60, 0x05, 0x60, 0x05, 0x14, 0x16, 0x00]
         PUSH1 10, PUSH1 20, LT, PUSH1 5, PUSH1 5, EQ, AND, STOP
Result: 1 (true)
```

**Memory Operations**: Store and load data
```
PUSH2 0x1234, PUSH1 0x00, MSTORE  # Store 0x1234 at offset 0
PUSH1 0x00, MLOAD                 # Load from offset 0
MSIZE                             # Get memory size
```

**Flow Control**: Conditional jumps and program control
```
PUSH1 10, PUSH1 5, GT            # Check if 10 > 5
PUSH1 label, JUMPI               # Jump if true
label: JUMPDEST                  # Valid jump destination
```

**Advanced Stack**: Complex manipulations
```
PUSH4 0x12345678  # Push 32-bit value
DUP3, SWAP3       # Advanced stack manipulation
```

## Contributing

See [docs/PLAN.md](docs/PLAN.md) for development roadmap and implementation details.

## License

MIT License - see [LICENSE](LICENSE) for details.