# EVM Fundamentals - A Comprehensive Learning Guide

## Table of Contents
1. [Introduction to the Ethereum Virtual Machine](#introduction)
2. [EVM Architecture & Design](#architecture)
3. [Understanding the Stack Machine](#stack-machine)
4. [Memory Management](#memory-management)
5. [Storage System](#storage-system)
6. [Gas Economics](#gas-economics)
7. [Opcodes Reference](#opcodes-reference)
8. [Transaction Lifecycle](#transaction-lifecycle)
9. [Smart Contracts](#smart-contracts)
10. [Parallel Execution Concepts](#parallel-execution)
11. [Implementation Examples](#examples)
12. [Advanced Topics](#advanced-topics)

## Introduction to the Ethereum Virtual Machine {#introduction}

The Ethereum Virtual Machine (EVM) is a stack-based virtual machine that executes smart contracts on the Ethereum blockchain. It provides a deterministic execution environment that runs consistently across all network nodes.

### Key Characteristics
- **Deterministic**: Same input always produces same output
- **Sandboxed**: Isolated execution environment
- **Turing Complete**: Can perform any computation (with gas limits)
- **State-based**: Maintains global state across transactions

### Understanding EVM
- Foundation for smart contract development and blockchain applications
- Essential for optimizing gas costs and transaction efficiency
- Required knowledge for security auditing and vulnerability analysis
- Enables advanced development patterns and system optimizations

## EVM Architecture & Design {#architecture}

### The Virtual Machine Model

```
┌─────────────────┐
│   Transaction   │  ← Input: Bytecode + Data
└─────────┬───────┘
          │
┌─────────▼───────┐
│      EVM        │  ← Execution Engine
│   ┌─────────┐   │
│   │  Stack  │   │  ← 256-bit words, max 1024 items
│   ├─────────┤   │
│   │ Memory  │   │  ← Temporary storage
│   ├─────────┤   │
│   │ Storage │   │  ← Persistent key-value store
│   └─────────┘   │
└─────────┬───────┘
          │
┌─────────▼───────┐
│     Result      │  ← Output: State Changes
└─────────────────┘
```

### Components Overview

1. **Stack**: Primary data structure (LIFO - Last In, First Out)
2. **Memory**: Temporary byte array for operations
3. **Storage**: Persistent key-value mapping
4. **Program Counter**: Tracks current instruction
5. **Gas**: Execution cost tracking

## Understanding the Stack Machine {#stack-machine}

### Stack Operations

The EVM stack can hold up to **1024 items**, each 256 bits (32 bytes) wide.

```zig
// Example: Adding two numbers
// Initial stack: []
PUSH1 0x05    // Stack: [5]
PUSH1 0x03    // Stack: [3, 5]
ADD           // Stack: [8]  (3 + 5 = 8)
```

### Stack Manipulation Opcodes

| Opcode | Description | Gas Cost |
|--------|-------------|----------|
| `PUSH1-PUSH32` | Push 1-32 bytes onto stack | 3 |
| `POP` | Remove top item | 2 |
| `DUP1-DUP16` | Duplicate stack item | 3 |
| `SWAP1-SWAP16` | Swap top with nth item | 3 |

### Practical Example

```zig
// Computing (a + b) * c where a=10, b=20, c=3
PUSH1 0x0A    // Stack: [10]
PUSH1 0x14    // Stack: [20, 10]
ADD           // Stack: [30]        (10 + 20)
PUSH1 0x03    // Stack: [3, 30]
MUL           // Stack: [90]        (30 * 3)
```

## Memory Management {#memory-management}

### Memory Layout

EVM memory is a **linear byte array** that expands during execution:

```
Memory Offset:  0    32   64   96   128  ...
               ┌────┬────┬────┬────┬─────┐
Memory:        │ A  │ B  │ C  │ D  │ ... │
               └────┴────┴────┴────┴─────┘
                32   32   32   32    32 bytes each
```

### Memory Operations

```zig
// Store 32 bytes in memory at offset 0
PUSH1 0x42      // Stack: [0x42] (value to store)
PUSH1 0x00      // Stack: [0x00, 0x42] (offset)
MSTORE          // Memory[0:32] = 0x42...

// Load 32 bytes from memory at offset 0
PUSH1 0x00      // Stack: [0x00] (offset)
MLOAD           // Stack: [0x42...] (loaded value)
```

### Gas Costs for Memory

Memory expansion costs grow quadratically:
- **Linear cost**: 3 gas per word
- **Quadratic cost**: Prevents memory abuse

## Storage System {#storage-system}

### Persistent Storage

Storage is a **key-value mapping** that persists between transactions:

```zig
// Store value 0x123 at storage slot 0
PUSH2 0x0123    // Stack: [0x123] (value)
PUSH1 0x00      // Stack: [0x00, 0x123] (key)
SSTORE          // Storage[0] = 0x123

// Load value from storage slot 0
PUSH1 0x00      // Stack: [0x00] (key)
SLOAD           // Stack: [0x123] (loaded value)
```

### Storage Gas Economics

| Operation | Cold Access | Warm Access |
|-----------|-------------|-------------|
| `SLOAD` | 2,100 gas | 100 gas |
| `SSTORE` (new) | 20,000 gas | - |
| `SSTORE` (modify) | 5,000 gas | 100 gas |
| `SSTORE` (delete) | Refund 4,800 gas | - |

## Gas Economics {#gas-economics}

### Understanding Gas

Gas serves multiple purposes:
1. **Prevents infinite loops**: Every operation costs gas
2. **Resource allocation**: Expensive operations cost more
3. **Network security**: Spam protection
4. **Miner incentives**: Gas fees reward miners

### Gas Calculation Example

```zig
// Transaction: Transfer 1 ETH
// Base transaction cost: 21,000 gas
// If gas price = 20 Gwei:
// Total cost = 21,000 × 20 × 10^-9 ETH = 0.00042 ETH
```

### Common Gas Costs

| Operation | Gas Cost | Notes |
|-----------|----------|-------|
| Basic arithmetic | 3-5 gas | ADD, SUB, MUL |
| Hash operations | 30 gas | SHA3/KECCAK256 |
| Storage read | 800-2,100 gas | SLOAD |
| Storage write | 5,000-20,000 gas | SSTORE |
| Contract creation | 32,000 gas | CREATE |

## Opcodes Reference {#opcodes-reference}

### Arithmetic Operations

```zig
// Basic arithmetic
ADD     // a + b
SUB     // a - b
MUL     // a * b
DIV     // a / b (integer division)
MOD     // a % b
ADDMOD  // (a + b) % N
MULMOD  // (a * b) % N
EXP     // a^b
SIGNEXTEND // Sign extension
```

### Comparison & Bitwise

```zig
// Comparison
LT      // a < b
GT      // a > b
SLT     // signed a < b
SGT     // signed a > b
EQ      // a == b
ISZERO  // a == 0

// Bitwise operations
AND     // a & b
OR      // a | b
XOR     // a ^ b
NOT     // ~a
BYTE    // nth byte of word
SHL     // shift left
SHR     // shift right
SAR     // arithmetic shift right
```

### Control Flow

```zig
// Jumps
JUMP     // Unconditional jump
JUMPI    // Conditional jump
JUMPDEST // Valid jump destination
PC       // Program counter
```

## Transaction Lifecycle {#transaction-lifecycle}

### Transaction Flow

```
1. Transaction Submitted
   ├─ Signature verification
   ├─ Nonce validation
   ├─ Gas limit check
   └─ Balance verification

2. EVM Execution
   ├─ Initialize execution context
   ├─ Load contract bytecode
   ├─ Execute opcodes sequentially
   ├─ Track gas consumption
   └─ Handle state changes

3. Transaction Completion
   ├─ Apply state changes
   ├─ Emit events/logs
   ├─ Calculate gas refund
   └─ Update account balances
```

### Execution Context

```zig
pub const ExecutionContext = struct {
    caller: [20]u8,           // msg.sender
    origin: [20]u8,           // tx.origin
    gas_price: BigInt,        // tx.gasprice
    block_number: u64,        // block.number
    timestamp: u64,           // block.timestamp
    gas_limit: u64,           // Available gas
    value: BigInt,            // msg.value
};
```

## Smart Contracts {#smart-contracts}

### Contract Structure

```solidity
// High-level Solidity
contract Token {
    mapping(address => uint256) balances;

    function transfer(address to, uint256 amount) {
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
}
```

Compiles to EVM bytecode:
```
PUSH1 0x80 PUSH1 0x40 MSTORE PUSH1 0x04 CALLDATASIZE LT PUSH2 0x0041 JUMPI
PUSH1 0x00 CALLDATALOAD PUSH29 0x0100000000000000000000000000000000000000000000000000000000 SWAP1 DIV
```

### Contract Deployment

1. **Creation transaction**: Contains contract bytecode
2. **Constructor execution**: Initializes contract state
3. **Code storage**: Runtime code stored at address
4. **Address generation**: Deterministic based on creator + nonce

## Parallel Execution Concepts {#parallel-execution}

### Why Parallel Execution?

Traditional EVM executes transactions sequentially:
```
TX1 → TX2 → TX3 → TX4  (Sequential)
```

Parallel execution allows:
```
TX1 ↘     ↙ TX3
      ╳      (Parallel where possible)
TX2 ↗     ↘ TX4
```

### Dependency Analysis

Transactions can run in parallel if they don't conflict:

```zig
// Independent transactions (can run in parallel)
TX1: Alice → Bob (100 ETH)
TX2: Carol → Dave (50 ETH)

// Dependent transactions (must run sequentially)
TX1: Alice → Bob (100 ETH)
TX2: Bob → Carol (50 ETH)  // Depends on TX1 completing first
```

### Conflict Types

1. **Balance conflicts**: Same account sends in multiple TXs
2. **Storage conflicts**: Same storage slot accessed
3. **Nonce conflicts**: Same account's transactions
4. **Contract state**: Shared contract storage

### Implementation Strategy

```zig
// Simplified parallel execution flow
fn executeParallel(transactions: []Transaction) ![]Receipt {
    // 1. Analyze dependencies
    const deps = try analyzeDependencies(transactions);

    // 2. Create execution waves
    const waves = try createExecutionWaves(transactions, deps);

    // 3. Execute each wave in parallel
    var receipts = std.ArrayList(Receipt).init(allocator);
    for (waves) |wave| {
        const wave_receipts = try executeWave(wave);
        try receipts.appendSlice(wave_receipts);
    }

    return receipts.toOwnedSlice();
}
```

## Implementation Examples {#examples}

### Basic EVM Implementation

```zig
pub const SimpleEVM = struct {
    stack: std.ArrayList(U256),
    memory: std.ArrayList(u8),
    storage: AutoHashMap(U256, U256),
    pc: usize,
    gas: u64,

    pub fn execute(self: *Self, bytecode: []const u8) !void {
        while (self.pc < bytecode.len and self.gas > 0) {
            const opcode = bytecode[self.pc];
            try self.executeOpcode(opcode);
            self.pc += 1;
        }
    }

    fn executeOpcode(self: *Self, opcode: u8) !void {
        switch (opcode) {
            0x01 => try self.opADD(),
            0x02 => try self.opMUL(),
            0x60 => try self.opPUSH1(),
            // ... more opcodes
            else => return error.InvalidOpcode,
        }
    }

    fn opADD(self: *Self) !void {
        if (self.stack.items.len < 2) return error.StackUnderflow;
        const a = self.stack.pop();
        const b = self.stack.pop();
        try self.stack.append(a.add(b));
        self.gas -= 3; // ADD costs 3 gas
    }
};
```

### Gas Tracking

```zig
pub const GasTracker = struct {
    available: u64,
    used: u64,

    pub fn consumeGas(self: *Self, amount: u64) !void {
        if (self.used + amount > self.available) {
            return error.OutOfGas;
        }
        self.used += amount;
    }

    pub fn refund(self: *Self, amount: u64) void {
        self.used = if (amount > self.used) 0 else self.used - amount;
    }
};
```

### Memory Management

```zig
pub const EVMMemory = struct {
    data: std.ArrayList(u8),

    pub fn store(self: *Self, offset: usize, value: U256) !void {
        const required_size = offset + 32;
        if (self.data.items.len < required_size) {
            try self.data.resize(required_size);
        }
        std.mem.writeIntBig(U256, self.data.items[offset..offset+32], value);
    }

    pub fn load(self: *Self, offset: usize) !U256 {
        if (offset + 32 > self.data.items.len) {
            try self.data.resize(offset + 32);
        }
        return std.mem.readIntBig(U256, self.data.items[offset..offset+32]);
    }
};
```

## Advanced Topics {#advanced-topics}

### 1. EIP-1559 Gas Model

```zig
pub fn calculateGasFee(
    base_fee: u64,
    max_fee: u64,
    max_priority_fee: u64,
    gas_used: u64
) u64 {
    const effective_gas_price = std.math.min(
        max_fee,
        base_fee + max_priority_fee
    );
    return effective_gas_price * gas_used;
}
```

### 2. State Trie Structure

```zig
pub const StateTrie = struct {
    // Merkle Patricia Trie for state storage
    root: [32]u8,
    nodes: AutoHashMap([32]u8, TrieNode),

    pub fn get(self: *Self, key: [32]u8) ?[]const u8 {
        return self.traverseTrie(self.root, key, 0);
    }

    pub fn set(self: *Self, key: [32]u8, value: []const u8) !void {
        self.root = try self.insertTrie(self.root, key, value, 0);
    }
};
```

### 3. Precompiled Contracts

```zig
pub const PrecompiledContracts = struct {
    pub fn ecRecover(input: []const u8) ![]const u8 {
        // ECDSA signature recovery
        // Address: 0x01
    }

    pub fn sha256Hash(input: []const u8) ![]const u8 {
        // SHA-256 hashing
        // Address: 0x02
    }

    pub fn ripemd160Hash(input: []const u8) ![]const u8 {
        // RIPEMD-160 hashing
        // Address: 0x03
    }
};
```

### 4. MEV and Transaction Ordering

```zig
pub const MEVProtection = struct {
    pub fn detectFrontrunning(
        pending: []Transaction,
        new_tx: Transaction
    ) bool {
        for (pending) |tx| {
            if (isSimilarTransaction(tx, new_tx) and
                tx.gas_price.gt(new_tx.gas_price)) {
                return true; // Potential frontrunning
            }
        }
        return false;
    }
};
```

## Learning Path Recommendations

### Beginner (0-3 months)
1. **Start here**: Understand blockchain basics
2. **Learn**: Stack machine concepts
3. **Practice**: Simple opcode execution
4. **Build**: Basic calculator in EVM assembly

### Intermediate (3-6 months)
1. **Study**: Gas optimization techniques
2. **Implement**: Memory and storage operations
3. **Explore**: Smart contract patterns
4. **Project**: Token contract from scratch

### Advanced (6+ months)
1. **Master**: Parallel execution concepts
2. **Research**: Latest EIPs and improvements
3. **Contribute**: Open source EVM implementations
4. **Innovate**: Novel optimization strategies

## Resources and References

### Official Documentation
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)
- [EVM Opcodes](https://ethereum.org/en/developers/docs/evm/opcodes/)
- [Gas and Fees](https://ethereum.org/en/developers/docs/gas/)

### Tools and Utilities
- **evm.codes**: Interactive opcode reference
- **Remix**: Online Solidity IDE
- **Foundry**: Development framework
- **Hardhat**: Development environment

### This Implementation
- See `src/main.zig` for core EVM implementation
- See `src/parallel.zig` for parallel execution
- See `src/parallel_optimized.zig` for optimizations
- Run `zig build demo` for practical examples

---

*This guide provides a comprehensive foundation for understanding EVM internals. Continue to the [Developer Guide](DEVELOPER_GUIDE.md) for implementation details and the [Enterprise Integration Guide](ENTERPRISE_INTEGRATION.md) for production deployment strategies.*