# Architecture

This document provides an overview of Zig EVM's architecture and design.

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
│  │  (141 impl)  │  │  (nested)    │  │    (LOG0-LOG4)       │   │
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

### EVM Struct

The central execution engine in `src/main.zig`:

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

### Stack

LIFO stack for 256-bit EVM words (`src/stack.zig`):

| Property | Value |
|----------|-------|
| Maximum depth | 1024 items |
| Word size | 256 bits (32 bytes) |
| Operations | push, pop, peek, dup, swap |

```zig
pub const Stack = struct {
    items: [1024]BigInt,
    depth: usize,

    pub fn push(self: *Stack, value: BigInt) !void;
    pub fn pop(self: *Stack) ?BigInt;
    pub fn peek(self: *Stack, index: usize) ?BigInt;
    pub fn dup(self: *Stack, n: usize) !void;
    pub fn swap(self: *Stack, n: usize) !void;
};
```

### Memory

Dynamic byte array with word-aligned access (`src/memory.zig`):

| Property | Description |
|----------|-------------|
| Expansion | Automatic on access |
| Word size | 32 bytes |
| Gas cost | Quadratic for expansion |

```zig
pub const Memory = struct {
    data: ArrayList(u8),

    pub fn load(self: *Memory, offset: usize) !BigInt;
    pub fn store(self: *Memory, offset: usize, value: BigInt) !void;
    pub fn store8(self: *Memory, offset: usize, value: u8) !void;
    pub fn size(self: *Memory) usize;
};
```

### BigInt

256-bit integer arithmetic (`src/bigint.zig`):

```zig
pub const BigInt = struct {
    data: [4]u64,  // 4 x 64-bit words = 256 bits

    // Arithmetic
    pub fn add(self: BigInt, other: BigInt) BigInt;
    pub fn sub(self: BigInt, other: BigInt) BigInt;
    pub fn mul(self: BigInt, other: BigInt) BigInt;
    pub fn div(self: BigInt, other: BigInt) BigInt;
    pub fn mod(self: BigInt, other: BigInt) BigInt;
    pub fn exp(self: BigInt, other: BigInt) BigInt;

    // Modular arithmetic
    pub fn addmod(a: BigInt, b: BigInt, n: BigInt) BigInt;
    pub fn mulmod(a: BigInt, b: BigInt, n: BigInt) BigInt;

    // Bitwise
    pub fn @"and"(self: BigInt, other: BigInt) BigInt;
    pub fn @"or"(self: BigInt, other: BigInt) BigInt;
    pub fn xor(self: BigInt, other: BigInt) BigInt;
    pub fn not(self: BigInt) BigInt;
    pub fn shl(self: BigInt, shift: u8) BigInt;
    pub fn shr(self: BigInt, shift: u8) BigInt;

    // Comparison
    pub fn lt(self: BigInt, other: BigInt) bool;
    pub fn gt(self: BigInt, other: BigInt) bool;
    pub fn eq(self: BigInt, other: BigInt) bool;
};
```

### Account State

```zig
pub const Account = struct {
    balance: BigInt,
    nonce: u64,
    code: []const u8,
    storage: HashMap(BigInt, BigInt),
};
```

### Call Frame

Nested execution contexts for CALL operations (`src/call_frame.zig`):

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

Each opcode is implemented as a separate file in `src/opcodes/`:

```zig
// Example: src/opcodes/add.zig
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

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
| Arithmetic | ADD, SUB, MUL, DIV, MOD, EXP, etc. | 12 |
| Comparison | LT, GT, EQ, ISZERO, etc. | 6 |
| Bitwise | AND, OR, XOR, NOT, SHL, SHR, etc. | 8 |
| Stack | PUSH1-32, DUP1-16, SWAP1-16, POP | 66 |
| Memory | MLOAD, MSTORE, MSTORE8, MSIZE | 4 |
| Storage | SLOAD, SSTORE | 2 |
| Flow | JUMP, JUMPI, JUMPDEST, PC, STOP | 5 |
| Environment | ADDRESS, BALANCE, CALLER, etc. | 16 |
| Block | NUMBER, TIMESTAMP, COINBASE, etc. | 9 |
| Logging | LOG0-LOG4 | 5 |
| Call | CALL, DELEGATECALL, STATICCALL, etc. | 6 |
| Create | CREATE, CREATE2 | 2 |

## Execution Flow

### Single Transaction

```
1. Transaction Validation
   ├─ Check gas limit
   ├─ Verify balance
   └─ Validate nonce

2. EVM Initialization
   ├─ Set execution context
   ├─ Load contract code
   └─ Initialize stack/memory

3. Opcode Execution Loop
   ├─ Fetch opcode at PC
   ├─ Check gas cost
   ├─ Execute opcode
   ├─ Update PC
   └─ Repeat until STOP/RETURN/REVERT

4. Result Processing
   ├─ Apply state changes
   ├─ Emit logs
   └─ Return result
```

### Parallel Execution

```
1. Dependency Analysis
   ├─ Detect address conflicts
   ├─ Detect storage conflicts
   └─ Build dependency graph

2. Wave Creation
   ├─ Group independent transactions
   └─ Order waves by dependencies

3. Parallel Execution
   ├─ Execute wave transactions concurrently
   ├─ Thread pool with work-stealing
   └─ Process waves sequentially

4. State Merging
   ├─ Combine results
   └─ Maintain consistency
```

## File Structure

```
zig-evm/
├── src/
│   ├── main.zig              # Core EVM struct
│   ├── stack.zig             # Stack implementation
│   ├── memory.zig            # Memory implementation
│   ├── bigint.zig            # 256-bit integers
│   ├── call_frame.zig        # Call stack
│   ├── ffi.zig               # C ABI exports
│   ├── batch_executor.zig    # Parallel execution
│   ├── parallel_optimized.zig # Optimized scheduler
│   └── opcodes/              # Opcode implementations
│       ├── add.zig
│       ├── sub.zig
│       ├── call.zig
│       └── ... (141 files)
├── include/
│   └── zigevm.h              # C header
├── bindings/
│   ├── python/               # Python bindings
│   ├── rust/                 # Rust bindings
│   └── js/                   # JavaScript bindings
└── tests/
    ├── test_*.zig            # Unit tests
    └── eth_compliance.zig    # Ethereum tests
```

## Performance Characteristics

| Metric | Value |
|--------|-------|
| Single execution | ~1M gas/second |
| Parallel throughput | 5-6x improvement (8 threads) |
| Memory overhead | ~100KB per EVM instance |
| Startup time | <1ms for instance creation |

## Thread Safety

- Each EVM instance is **not thread-safe**
- Create separate instances for concurrent use
- BatchExecutor handles internal threading
- FFI functions are safe to call from any thread
