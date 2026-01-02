# Zig API Reference

Complete API reference for using Zig EVM directly in Zig projects.

## EVM Struct

The main EVM execution engine.

### Initialization

```zig
const EVM = @import("main.zig").EVM;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var evm = try EVM.init(gpa.allocator());
    defer evm.deinit();
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `stack` | `Stack` | 256-bit word stack |
| `memory` | `Memory` | Dynamic byte array |
| `pc` | `usize` | Program counter |
| `gas` | `u64` | Remaining gas |
| `gas_limit` | `u64` | Maximum gas allowed |
| `code` | `[]const u8` | Bytecode being executed |
| `accounts` | `HashMap` | Account state |
| `current_address` | `[20]u8` | Current contract address |
| `caller_address` | `[20]u8` | Message caller |
| `origin_address` | `[20]u8` | Transaction origin |
| `call_value` | `BigInt` | Call value |
| `calldata` | `[]const u8` | Input data |
| `block_number` | `u64` | Block number |
| `block_timestamp` | `u64` | Block timestamp |
| `coinbase` | `[20]u8` | Block producer |
| `chain_id` | `u64` | Chain ID |
| `return_data` | `[]u8` | Return data |
| `logs` | `ArrayList(Log)` | Emitted logs |
| `stop_execution` | `bool` | Execution halted |
| `execution_reverted` | `bool` | Execution reverted |

### Methods

#### init

```zig
pub fn init(allocator: Allocator) !*EVM
```

Create a new EVM instance.

**Parameters**:
- `allocator`: Memory allocator to use

**Returns**: Pointer to EVM instance

**Errors**: `OutOfMemory`

---

#### deinit

```zig
pub fn deinit(self: *EVM) void
```

Destroy EVM instance and free resources.

---

#### reset

```zig
pub fn reset(self: *EVM) void
```

Reset execution state. Clears stack, memory, and PC. Preserves accounts.

---

#### setGasLimit

```zig
pub fn setGasLimit(self: *EVM, limit: u64) void
```

Set maximum gas for execution.

---

#### execute

```zig
pub fn execute(self: *EVM) !void
```

Execute loaded bytecode.

**Errors**:
- `OutOfGas`
- `StackUnderflow`
- `StackOverflow`
- `InvalidOpcode`
- `InvalidJump`
- `Revert`

---

#### setBalance

```zig
pub fn setBalance(self: *EVM, addr: [20]u8, balance: BigInt) !void
```

Set account balance.

---

#### setCode

```zig
pub fn setCode(self: *EVM, addr: [20]u8, code: []const u8) !void
```

Set account bytecode.

---

#### setStorage

```zig
pub fn setStorage(self: *EVM, addr: [20]u8, key: BigInt, value: BigInt) !void
```

Set storage slot value.

---

#### getStorage

```zig
pub fn getStorage(self: *EVM, addr: [20]u8, key: BigInt) ?BigInt
```

Get storage slot value.

## Stack

256-bit word stack with 1024 item limit.

### Methods

#### push

```zig
pub fn push(self: *Stack, value: BigInt) !void
```

Push value onto stack.

**Errors**: `StackOverflow`

---

#### pop

```zig
pub fn pop(self: *Stack) ?BigInt
```

Pop value from stack. Returns `null` if empty.

---

#### peek

```zig
pub fn peek(self: *Stack, index: usize) ?BigInt
```

Peek at stack value without removing. Index 0 = top.

---

#### dup

```zig
pub fn dup(self: *Stack, n: usize) !void
```

Duplicate nth stack item.

**Errors**: `StackOverflow`, `StackUnderflow`

---

#### swap

```zig
pub fn swap(self: *Stack, n: usize) !void
```

Swap top with nth item.

**Errors**: `StackUnderflow`

## Memory

Dynamic byte array for EVM memory.

### Methods

#### load

```zig
pub fn load(self: *Memory, offset: usize) !BigInt
```

Load 32-byte word from offset.

---

#### store

```zig
pub fn store(self: *Memory, offset: usize, value: BigInt) !void
```

Store 32-byte word at offset.

---

#### store8

```zig
pub fn store8(self: *Memory, offset: usize, value: u8) !void
```

Store single byte at offset.

---

#### size

```zig
pub fn size(self: *Memory) usize
```

Get current memory size in bytes.

---

#### read

```zig
pub fn read(self: *Memory, offset: usize, len: usize) ![]u8
```

Read bytes from memory.

## BigInt

256-bit unsigned integer.

### Construction

```zig
// From u64
const a = BigInt.fromU64(42);

// From bytes (big-endian)
const b = BigInt.fromBytes(&[_]u8{0x01, 0x02, ...});

// Zero
const c = BigInt.zero();

// Max value
const d = BigInt.max();
```

### Arithmetic

```zig
const result = a.add(b);
const result = a.sub(b);
const result = a.mul(b);
const result = a.div(b);
const result = a.mod(b);
const result = a.exp(b);
```

### Modular Arithmetic

```zig
const result = BigInt.addmod(a, b, n);
const result = BigInt.mulmod(a, b, n);
```

### Bitwise Operations

```zig
const result = a.@"and"(b);
const result = a.@"or"(b);
const result = a.xor(b);
const result = a.not();
const result = a.shl(shift);
const result = a.shr(shift);
```

### Comparison

```zig
const isLess = a.lt(b);
const isGreater = a.gt(b);
const isEqual = a.eq(b);
const isZero = a.isZero();
```

### Conversion

```zig
// To bytes (big-endian)
const bytes = a.toBytes();

// To u64 (truncated)
const value = a.toU64();
```

## Error Types

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

## Log Struct

```zig
pub const Log = struct {
    address: [20]u8,
    topics: ArrayList([32]u8),
    data: ArrayList(u8),
};
```

## Account Struct

```zig
pub const Account = struct {
    balance: BigInt,
    nonce: u64,
    code: []const u8,
    storage: HashMap(BigInt, BigInt),
};
```

## CallFrame Struct

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

## Example: Complete Program

```zig
const std = @import("std");
const EVM = @import("main.zig").EVM;
const BigInt = @import("bigint.zig").BigInt;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Create EVM
    var evm = try EVM.init(gpa.allocator());
    defer evm.deinit();

    // Configure
    evm.setGasLimit(1000000);
    evm.chain_id = 1;
    evm.block_number = 12345678;
    evm.block_timestamp = 1640000000;

    // Set up account
    const addr = [_]u8{0xaa} ** 20;
    try evm.setBalance(addr, BigInt.fromU64(1000000000000000000));
    evm.current_address = addr;

    // Load bytecode: PUSH1 3, PUSH1 5, ADD, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
    evm.code = &[_]u8{
        0x60, 0x03, // PUSH1 3
        0x60, 0x05, // PUSH1 5
        0x01,       // ADD
        0x60, 0x00, // PUSH1 0
        0x52,       // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xf3,       // RETURN
    };

    // Execute
    try evm.execute();

    // Check results
    std.debug.print("Gas used: {}\n", .{evm.gas_limit - evm.gas});
    std.debug.print("Return data length: {}\n", .{evm.return_data.len});

    if (evm.return_data.len >= 32) {
        const result = std.mem.readIntBig(u256, evm.return_data[0..32]);
        std.debug.print("Result: {}\n", .{result});  // 8
    }
}
```
