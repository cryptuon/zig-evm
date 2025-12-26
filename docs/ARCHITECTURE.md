# Zig EVM Architecture

This document provides an overview of the Zig EVM architecture, designed for high-performance L2/Rollup execution with embeddability across multiple languages.

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Language Bindings                         │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │  Python  │    │   Rust   │    │    JS    │    │    C     │  │
│  │ (ctypes) │    │  (FFI)   │    │ (N-API)  │    │ (native) │  │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘    └────┬─────┘  │
└───────┼───────────────┼───────────────┼───────────────┼─────────┘
        │               │               │               │
        └───────────────┴───────┬───────┴───────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                         FFI Layer (C ABI)                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  src/ffi.zig                                            │    │
│  │  - Opaque handles (EVMHandle, BatchHandle)              │    │
│  │  - Error codes enum                                      │    │
│  │  - C-compatible structs                                  │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────┐
│                         Core EVM Engine                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │    Stack     │  │    Memory    │  │      Accounts        │   │
│  │  (1024 max)  │  │  (dynamic)   │  │  (balance, storage)  │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │   Opcodes    │  │  Call Stack  │  │        Logs          │   │
│  │  (96 impl)   │  │  (nested)    │  │    (LOG0-LOG4)       │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────┐
│                     Parallel Execution Layer                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  BatchExecutor                                          │    │
│  │  - Dependency analysis (O(n) hash-based)                │    │
│  │  - Work-stealing thread pool                            │    │
│  │  - Wave-based parallel execution                        │    │
│  │  - Speculative execution with rollback                  │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. EVM Struct (`src/main.zig`)

The central execution engine containing:

```zig
pub const EVM = struct {
    // Execution state
    stack: Stack,           // 256-bit word stack (max 1024)
    memory: Memory,         // Dynamic byte array
    pc: usize,              // Program counter
    gas: u64,               // Remaining gas
    code: []const u8,       // Bytecode being executed

    // Account state
    accounts: HashMap([20]u8, Account),

    // Environment
    current_address: [20]u8,
    caller_address: [20]u8,
    origin_address: [20]u8,
    call_value: BigInt,
    calldata: []const u8,

    // Block context
    block_number: u64,
    block_timestamp: u64,
    coinbase: [20]u8,
    chain_id: u64,

    // Execution results
    return_data: []u8,
    logs: ArrayList(Log),
    stop_execution: bool,
    execution_reverted: bool,
};
```

### 2. Stack (`src/stack.zig`)

LIFO stack for 256-bit EVM words:

- Maximum depth: 1024 items
- Operations: push, pop, peek, dup, swap
- Overflow/underflow protection

### 3. Memory (`src/memory.zig`)

Dynamic byte array with word-aligned access:

- Auto-expansion on access
- MLOAD: 32-byte aligned reads
- MSTORE: 32-byte aligned writes
- MSTORE8: Single byte writes
- Gas cost for expansion

### 4. BigInt (`src/bigint.zig`)

256-bit integer arithmetic:

- 4×64-bit word representation
- Full arithmetic: add, sub, mul, div, mod, exp
- Modular arithmetic: addmod, mulmod
- Bitwise operations: and, or, xor, not, shl, shr
- Signed operations: sdiv, smod, signextend

### 5. Account State

```zig
pub const Account = struct {
    balance: BigInt,
    nonce: u64,
    code: []const u8,
    storage: HashMap(BigInt, BigInt),
};
```

### 6. Call Stack (`src/call_frame.zig`)

Nested execution contexts for CALL operations:

```zig
pub const CallFrame = struct {
    caller: [20]u8,
    callee: [20]u8,
    value: BigInt,
    calldata: []const u8,
    gas: u64,
    return_offset: usize,
    return_size: usize,
    is_static: bool,
    is_delegate: bool,
    depth: u16,
};
```

## Opcode Implementation

Opcodes are implemented as individual files in `src/opcodes/`:

```zig
// Example: src/opcodes/add.zig
pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.ADD),
        .impl = OpcodeImpl{ .execute = execute },
    };
}

fn execute(evm: *EVM) !void {
    const a = evm.stack.pop() orelse return error.StackUnderflow;
    const b = evm.stack.pop() orelse return error.StackUnderflow;
    try evm.stack.push(a.add(b));
}
```

### Opcode Categories

| Category | Opcodes | Count |
|----------|---------|-------|
| Arithmetic | ADD, SUB, MUL, DIV, MOD, EXP, etc. | 17 |
| Comparison | LT, GT, EQ, ISZERO, etc. | 6 |
| Bitwise | AND, OR, XOR, NOT, SHL, SHR, etc. | 9 |
| Stack | PUSH1-32, DUP1-16, SWAP1-16, POP | 66 |
| Memory | MLOAD, MSTORE, MSTORE8, MSIZE | 4 |
| Storage | SLOAD, SSTORE | 2 |
| Flow | JUMP, JUMPI, JUMPDEST, PC, STOP | 5 |
| Environment | ADDRESS, BALANCE, CALLER, etc. | 15 |
| Block | NUMBER, TIMESTAMP, COINBASE, etc. | 8 |
| Logging | LOG0-LOG4 | 5 |
| Call | CALL, DELEGATECALL, STATICCALL, etc. | 6 |
| Create | CREATE, CREATE2 | 2 |
| Return | RETURN, REVERT | 2 |

## Gas Metering

Gas costs follow Ethereum specifications:

```zig
pub fn getGasCost(opcode: Opcode) u64 {
    return switch (opcode) {
        .STOP => 0,
        .ADD, .SUB => 3,
        .MUL, .DIV => 5,
        .EXP => 10, // + dynamic cost
        .SLOAD => 800, // cold access
        .SSTORE => 20000, // new value
        .CALL => 700, // + memory + value transfer
        // ... etc
    };
}
```

### Dynamic Gas Costs

- **Memory expansion**: `3 * words + words² / 512`
- **SSTORE**: EIP-2200 gas metering (cold/warm access)
- **CALL**: Base + memory + value transfer costs
- **LOG**: 375 + 8 * data_size + 375 * topic_count

## Parallel Execution

### Dependency Analysis

Transactions are analyzed for conflicts:

1. **Address conflicts**: Same sender/receiver
2. **Storage conflicts**: Same storage slots accessed
3. **Nonce ordering**: Same sender transactions ordered

### Wave-Based Execution

```
Wave 1: [Tx0, Tx2, Tx5]  ─── parallel ───▶
Wave 2: [Tx1, Tx3]       ─── parallel ───▶
Wave 3: [Tx4, Tx6]       ─── parallel ───▶
```

### Speculative Execution

For optimistic parallelism:

1. Execute transactions speculatively
2. Track state modifications
3. Validate no conflicts occurred
4. Rollback and re-execute on conflict

## Memory Management

### Allocator Strategy

- Arena allocators for execution context
- Memory pools for frequent allocations
- Explicit cleanup on context exit

### Thread Safety

- Per-thread EVM instances
- Lock-free work queue
- Atomic state updates for shared data

## Error Handling

```zig
pub const EVMError = error{
    OutOfGas,
    StackUnderflow,
    StackOverflow,
    InvalidOpcode,
    InvalidJump,
    Revert,
    StaticCallViolation,
    OutOfMemory,
    CallDepthExceeded,
    InsufficientBalance,
};
```

## Build Targets

| Target | Command | Description |
|--------|---------|-------------|
| Executable | `zig build run` | CLI demo |
| Shared Library | `zig build lib` | libzigevm.so/dll |
| Static Library | `zig build lib` | libzigevm.a |
| Tests | `zig build test` | Unit tests |
| Compliance | `zig build compliance` | Ethereum tests |
| Benchmarks | `zig build benchmark` | Performance tests |

## File Structure

```
zig-evm/
├── src/
│   ├── main.zig           # Core EVM struct
│   ├── stack.zig          # Stack implementation
│   ├── memory.zig         # Memory implementation
│   ├── bigint.zig         # 256-bit integers
│   ├── call_frame.zig     # Call stack
│   ├── ffi.zig            # C ABI exports
│   ├── batch_executor.zig # Parallel execution
│   └── opcodes/           # Opcode implementations
│       ├── add.zig
│       ├── sub.zig
│       └── ...
├── include/
│   └── zigevm.h           # C header
├── bindings/
│   ├── python/            # Python bindings
│   ├── rust/              # Rust bindings
│   └── js/                # JavaScript bindings
├── tests/
│   ├── test_*.zig         # Unit tests
│   ├── eth_compliance.zig # Ethereum test runner
│   └── run_compliance.zig # Compliance test CLI
└── docs/
    ├── ARCHITECTURE.md    # This file
    ├── FFI.md             # C ABI reference
    ├── BINDINGS.md        # Language binding guide
    └── PARALLEL.md        # Parallel execution guide
```

## Performance Characteristics

- **Single execution**: ~1M gas/second
- **Parallel throughput**: 5-6x improvement with 8 threads
- **Memory overhead**: ~100KB per EVM instance
- **Startup time**: <1ms for instance creation
