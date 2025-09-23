# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Build and Run
```bash
# Build and run the basic EVM
zig build run

# Run all tests
zig build test

# Run specific test file (example)
zig test tests/test_bigint.zig

# Install globally
zig build install
```

### Demos and Benchmarks
```bash
# Run parallel execution demo
zig build parallel

# Run optimized parallel execution demo
zig build parallel-opt

# Run performance benchmarks
zig build benchmark
zig build bench

# Run benchmark demonstration
zig build demo
```

### Build Options
The build system supports standard Zig options:
```bash
# Release builds
zig build run -Doptimize=ReleaseFast
zig build test -Doptimize=ReleaseFast

# Different targets
zig build run -Dtarget=x86_64-linux
```

## Architecture Overview

### Core EVM Structure
The EVM implementation is centered around the `EVM` struct in `src/main.zig` which contains:
- **Stack**: 256-bit word stack with 1024-item limit
- **Memory**: Dynamic byte array for temporary storage
- **Storage**: Persistent key-value store (HashMap)
- **Gas tracking**: Consumption and limit enforcement
- **Opcodes**: HashMap registry of opcode implementations
- **Environmental context**: Block and transaction information

### Opcode Implementation Pattern
Each opcode is implemented as a separate file in `src/opcodes/` following this pattern:
- File name matches opcode (e.g., `add.zig` for ADD opcode)
- Exports `getImpl()` function returning code and implementation
- Implementation function takes `*EVM` and manipulates stack/memory/storage
- Automatic registration in `loadOpcodes()` function in main.zig

### Parallel Execution Architecture
The project implements two parallel execution systems:

1. **Basic Parallel (`src/parallel.zig`)**:
   - O(n²) dependency analysis
   - Simple thread pool
   - Basic conflict detection

2. **Optimized Parallel (`src/parallel_optimized.zig`)**:
   - O(n) hash-based dependency analysis
   - Work-stealing thread pool
   - Speculative execution with rollback
   - Memory pool optimization

Both systems analyze transaction dependencies based on:
- Address conflicts (read/write)
- Balance modifications
- Nonce conflicts

### Key Components

#### BigInt System (`src/bigint.zig`)
- 256-bit integers using 4×64-bit words
- Arithmetic operations for EVM compatibility
- Comparison and bitwise operations

#### Stack Management (`src/stack.zig`)
- LIFO stack with 256-bit word elements
- 1024-item maximum depth
- Push/pop with overflow/underflow protection

#### Memory Management (`src/memory.zig`)
- Dynamic byte array with automatic expansion
- Word-aligned operations (32-byte words)
- Gas cost calculation for memory expansion

#### Gas System
- Realistic gas costs matching Ethereum specifications
- Per-opcode gas consumption in `getGasCost()` function
- Out-of-gas protection and tracking

### Test Structure
Tests are organized by functionality in `tests/` directory:
- `test_bigint.zig`: BigInt arithmetic operations
- `test_opcodes.zig`: Basic opcode functionality
- `test_arithmetic.zig`: Arithmetic opcode tests
- `test_stack_ops.zig`: Stack manipulation tests
- `test_memory.zig`: Memory operations
- `test_parallel_execution.zig`: Parallel execution tests

All tests are imported through `test.zig` using `comptime` blocks.

### Transaction Execution Flow
1. **Transaction validation**: Gas limit, balance checks
2. **Opcode dispatch**: Lookup in opcodes HashMap
3. **Gas consumption**: Deduct gas cost before execution
4. **Stack/memory manipulation**: Execute opcode logic
5. **State updates**: Apply account and storage changes

### Parallel Execution Flow
1. **Dependency analysis**: Detect conflicts between transactions
2. **Wave creation**: Group independent transactions
3. **Parallel execution**: Execute waves concurrently
4. **State merging**: Combine results maintaining consistency

## Working with Opcodes

### Adding New Opcodes
1. Create implementation file in `src/opcodes/` (e.g., `newop.zig`)
2. Follow existing pattern with `getImpl()` function
3. Add to `loadOpcodes()` function in `src/main.zig`
4. Add gas cost in `getGasCost()` function
5. Write tests in appropriate test file

### Opcode Implementation Template
```zig
const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.NEWOP),
        .impl = OpcodeImpl{ .execute = execute },
    };
}

fn execute(evm: *EVM) !void {
    // Implementation logic
}
```

### Current Implementation Status
- **96 opcodes implemented** out of the full EVM instruction set
- **Stack operations**: Complete (PUSH1-32, DUP1-16, SWAP1-16, POP)
- **Arithmetic**: Complete basic set (ADD, SUB, MUL, DIV, MOD, etc.)
- **Memory operations**: MLOAD, MSTORE, MSTORE8, MSIZE
- **Flow control**: JUMP, JUMPI, JUMPDEST, PC
- **Environmental**: ADDRESS, BALANCE, TIMESTAMP, etc.
- **Missing**: Storage operations (SLOAD/SSTORE), contract operations, logging

## Performance Considerations

### Parallel Execution Benefits
- 5-6x throughput improvement for independent transactions
- Linear scaling up to 8 threads
- Optimized dependency analysis provides 10-100x speedup for large batches

### Memory Management
- Use arena allocators for temporary operations
- Memory pools reduce allocation overhead
- Stack and memory have built-in size limits for safety

### Gas Optimization
- All opcodes include accurate gas costs
- Early gas checking prevents expensive operations
- Gas tracking matches Ethereum specifications