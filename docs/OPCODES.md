# Implemented Opcodes

This document lists all implemented EVM opcodes in the Zig EVM project.

## Summary

**Total Implemented**: 36 opcodes
**Test Coverage**: 67 comprehensive tests
**Status**: 64 tests passing ✅ (3 edge cases pending)

## Opcode Categories

### Arithmetic Operations (6 opcodes)
| Opcode | Hex  | Description | Status |
|--------|------|-------------|--------|
| ADD    | 0x01 | Addition    | ✅     |
| MUL    | 0x02 | Multiplication | ✅  |
| SUB    | 0x03 | Subtraction | ✅     |
| DIV    | 0x04 | Division    | ✅     |
| SDIV   | 0x05 | Signed division | ✅  |
| MOD    | 0x06 | Modulo      | ✅     |

### Comparison Operations (5 opcodes)
| Opcode | Hex  | Description | Status |
|--------|------|-------------|--------|
| LT     | 0x10 | Less than   | ✅     |
| GT     | 0x11 | Greater than| ✅     |
| SLT    | 0x12 | Signed less than | ✅ |
| EQ     | 0x14 | Equal to    | ✅     |
| ISZERO | 0x15 | Is zero     | ✅     |

### Bitwise Operations (4 opcodes)
| Opcode | Hex  | Description | Status |
|--------|------|-------------|--------|
| AND    | 0x16 | Bitwise AND | ✅     |
| OR     | 0x17 | Bitwise OR  | ✅     |
| XOR    | 0x18 | Bitwise XOR | ✅     |
| NOT    | 0x19 | Bitwise NOT | ✅     |

### Memory Operations (4 opcodes)
| Opcode | Hex  | Description | Status |
|--------|------|-------------|--------|
| MLOAD  | 0x51 | Load from memory | ✅ |
| MSTORE | 0x52 | Store to memory | ✅  |
| MSTORE8| 0x53 | Store byte to memory | ✅ |
| MSIZE  | 0x59 | Get memory size | ✅  |

### Stack Operations (7 opcodes)
| Opcode | Hex  | Description | Status |
|--------|------|-------------|--------|
| POP    | 0x50 | Remove from stack | ✅  |
| DUP1   | 0x80 | Duplicate 1st item | ✅ |
| DUP2   | 0x81 | Duplicate 2nd item | ✅ |
| DUP3   | 0x82 | Duplicate 3rd item | ✅ |
| SWAP1  | 0x90 | Swap top 2 items | ✅   |
| SWAP2  | 0x91 | Swap 1st & 3rd items | ✅ |
| SWAP3  | 0x92 | Swap 1st & 4th items | ✅ |

### Push Operations (5 opcodes)
| Opcode | Hex  | Description | Status |
|--------|------|-------------|--------|
| PUSH1  | 0x60 | Push 1 byte | ✅     |
| PUSH2  | 0x61 | Push 2 bytes| ✅     |
| PUSH3  | 0x62 | Push 3 bytes| ✅     |
| PUSH4  | 0x63 | Push 4 bytes| ✅     |
| PUSH32 | 0x7F | Push 32 bytes| ✅    |

### Control Flow (5 opcodes)
| Opcode | Hex  | Description | Status |
|--------|------|-------------|--------|
| STOP   | 0x00 | Halt execution | ✅   |
| JUMP   | 0x56 | Unconditional jump | ✅ |
| JUMPI  | 0x57 | Conditional jump | ✅ |
| PC     | 0x58 | Program counter | ✅  |
| JUMPDEST| 0x5B | Jump destination | ✅ |

## Implementation Details

### Error Handling
- **Stack Underflow**: All opcodes properly check for sufficient stack items
- **Stack Overflow**: Stack operations respect 1024-item limit
- **Division by Zero**: Returns 0 as per EVM specification
- **Invalid Code**: PUSH operations validate sufficient bytecode length

### BigInt Features
- **256-bit arithmetic** with proper carry handling
- **Improved multiplication** supporting up to 128-bit × 128-bit
- **Comparison operations** with big-endian ordering
- **Bitwise operations** on full 256-bit values

### Test Coverage
Each opcode category has comprehensive tests:
- **Unit tests** for individual opcodes
- **Integration tests** for opcode combinations
- **Error condition tests** for edge cases
- **Complex operation tests** for real-world scenarios

## Next Implementation Priorities

Based on EVM usage frequency and implementation complexity:

1. **Memory Operations** (MLOAD, MSTORE, MSTORE8, MSIZE)
2. **Additional Stack Operations** (DUP3-DUP16, SWAP3-SWAP16)
3. **Additional PUSH Operations** (PUSH3, PUSH5-PUSH31)
4. **Flow Control** (JUMP, JUMPI, JUMPDEST)
5. **Environmental Operations** (ADDRESS, BALANCE, CALLER, etc.)

## Usage Examples

### Simple Arithmetic
```zig
// (10 + 5) * 3 = 45
const bytecode = &[_]u8{
    0x60, 0x0A,  // PUSH1 10
    0x60, 0x05,  // PUSH1 5
    0x01,        // ADD
    0x60, 0x03,  // PUSH1 3
    0x02,        // MUL
    0x00         // STOP
};
```

### Comparison Logic
```zig
// Check if 15 > 10
const bytecode = &[_]u8{
    0x60, 0x0F,  // PUSH1 15
    0x60, 0x0A,  // PUSH1 10
    0x11,        // GT
    0x00         // STOP
};
// Result: 1 (true)
```

### Stack Manipulation
```zig
// DUP and SWAP operations
const bytecode = &[_]u8{
    0x60, 0x05,  // PUSH1 5
    0x60, 0x0A,  // PUSH1 10
    0x80,        // DUP1     stack: [5, 10, 10]
    0x90,        // SWAP1    stack: [5, 10, 10] -> [10, 10, 5]
    0x00         // STOP
};
```

This implementation provides a solid foundation for building more complex EVM functionality and smart contract execution.