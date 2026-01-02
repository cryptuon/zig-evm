# EVM Fundamentals

A comprehensive guide to understanding the Ethereum Virtual Machine.

## Introduction

The Ethereum Virtual Machine (EVM) is a stack-based virtual machine that executes smart contracts on the Ethereum blockchain. It provides a deterministic execution environment that runs consistently across all network nodes.

### Key Characteristics

| Characteristic | Description |
|----------------|-------------|
| **Deterministic** | Same input always produces same output |
| **Sandboxed** | Isolated execution environment |
| **Turing Complete** | Can perform any computation (with gas limits) |
| **State-based** | Maintains global state across transactions |

## The Virtual Machine Model

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

### Components

1. **Stack**: Primary data structure (LIFO - Last In, First Out)
2. **Memory**: Temporary byte array for operations
3. **Storage**: Persistent key-value mapping
4. **Program Counter**: Tracks current instruction
5. **Gas**: Execution cost tracking

## The Stack Machine

The EVM stack can hold up to **1024 items**, each 256 bits (32 bytes) wide.

### Stack Operations

```
# Adding two numbers
# Initial stack: []

PUSH1 0x05    # Stack: [5]
PUSH1 0x03    # Stack: [3, 5]
ADD           # Stack: [8]  (pops 3 and 5, pushes 8)
```

### Stack Manipulation Opcodes

| Opcode | Description | Gas | Stack Change |
|--------|-------------|-----|--------------|
| PUSH1-PUSH32 | Push 1-32 bytes | 3 | +1 |
| POP | Remove top item | 2 | -1 |
| DUP1-DUP16 | Duplicate item | 3 | +1 |
| SWAP1-SWAP16 | Swap items | 3 | 0 |

### Example: Computing (a + b) * c

```
# Where a=10, b=20, c=3
PUSH1 0x0A    # Stack: [10]
PUSH1 0x14    # Stack: [20, 10]
ADD           # Stack: [30]        (10 + 20)
PUSH1 0x03    # Stack: [3, 30]
MUL           # Stack: [90]        (30 * 3)
```

## Memory Management

EVM memory is a **linear byte array** that expands during execution.

### Memory Layout

```
Memory Offset:  0    32   64   96   128  ...
               ┌────┬────┬────┬────┬─────┐
Memory:        │ A  │ B  │ C  │ D  │ ... │
               └────┴────┴────┴────┴─────┘
                32   32   32   32    32 bytes each
```

### Memory Operations

```
# Store 32 bytes in memory at offset 0
PUSH1 0x42      # Stack: [0x42] (value to store)
PUSH1 0x00      # Stack: [0x00, 0x42] (offset)
MSTORE          # Memory[0:32] = 0x42 (right-padded)

# Load 32 bytes from memory at offset 0
PUSH1 0x00      # Stack: [0x00] (offset)
MLOAD           # Stack: [0x42...] (loaded value)
```

### Memory Gas Costs

Memory expansion costs grow **quadratically** to prevent abuse:

```
memory_cost = 3 * words + words² / 512
```

## Storage System

Storage is a **persistent key-value mapping** that survives between transactions.

### Storage Operations

```
# Store value 0x123 at storage slot 0
PUSH2 0x0123    # Stack: [0x123] (value)
PUSH1 0x00      # Stack: [0x00, 0x123] (key)
SSTORE          # Storage[0] = 0x123

# Load value from storage slot 0
PUSH1 0x00      # Stack: [0x00] (key)
SLOAD           # Stack: [0x123] (loaded value)
```

### Storage Gas Economics

| Operation | Cold Access | Warm Access |
|-----------|-------------|-------------|
| SLOAD | 2,100 gas | 100 gas |
| SSTORE (new) | 20,000 gas | - |
| SSTORE (modify) | 5,000 gas | 100 gas |
| SSTORE (delete) | Refund 4,800 | - |

## Gas Economics

### Why Gas Exists

1. **Prevents infinite loops**: Every operation costs gas
2. **Resource allocation**: Expensive operations cost more
3. **Network security**: Spam protection
4. **Miner incentives**: Gas fees reward miners

### Gas Calculation

```
# Transaction: Transfer 1 ETH
# Base transaction cost: 21,000 gas
# If gas price = 20 Gwei:
# Total cost = 21,000 × 20 × 10^-9 ETH = 0.00042 ETH
```

### Common Gas Costs

| Operation | Gas Cost | Notes |
|-----------|----------|-------|
| Basic arithmetic | 3-5 | ADD, SUB, MUL |
| Hash operations | 30+ | SHA3/KECCAK256 |
| Storage read | 100-2100 | SLOAD |
| Storage write | 100-20000 | SSTORE |
| Contract creation | 32000 | CREATE |

## Transaction Lifecycle

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

## Execution Context

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

## Smart Contracts

### High-Level to Bytecode

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
PUSH1 0x80 PUSH1 0x40 MSTORE PUSH1 0x04 CALLDATASIZE LT ...
```

### Contract Deployment

1. **Creation transaction**: Contains constructor bytecode
2. **Constructor execution**: Initializes state
3. **Code storage**: Runtime code stored at address
4. **Address generation**: Deterministic from creator + nonce

## Call Types

### CALL

Standard message call to another contract:

- Separate execution context
- Can transfer value
- Caller pays for gas

### DELEGATECALL

Execute code in caller's context:

- Uses caller's storage
- Uses caller's msg.sender
- Uses caller's msg.value

### STATICCALL

Read-only call:

- No state modifications allowed
- Reverts on state-changing opcodes

## Parallel Execution

### Traditional Sequential Execution

```
TX1 → TX2 → TX3 → TX4  (Sequential)
```

### Parallel Execution

```
TX1 ↘     ↙ TX3
      ╳      (Parallel where possible)
TX2 ↗     ↘ TX4
```

### When Transactions Can Run in Parallel

**Independent** (can run in parallel):
```
TX1: Alice → Bob (100 ETH)
TX2: Carol → Dave (50 ETH)
```

**Dependent** (must run sequentially):
```
TX1: Alice → Bob (100 ETH)
TX2: Bob → Carol (50 ETH)  // Depends on TX1 completing
```

### Conflict Types

1. **Balance conflicts**: Same account sends in multiple TXs
2. **Storage conflicts**: Same storage slot accessed
3. **Nonce conflicts**: Same account's transactions
4. **Contract state**: Shared contract storage

## Advanced Topics

### EIP-1559 Gas Model

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

### Precompiled Contracts

Special contracts at low addresses with optimized implementations:

| Address | Function |
|---------|----------|
| 0x01 | ECDSA recovery |
| 0x02 | SHA-256 |
| 0x03 | RIPEMD-160 |
| 0x04 | Identity |
| 0x05 | Modular exponentiation |
| 0x06-0x08 | BN256 curve operations |
| 0x09 | BLAKE2b |

### State Trie

Ethereum uses a Merkle Patricia Trie for state storage:

```
                Root Hash
                    │
        ┌───────────┼───────────┐
        │           │           │
    Account 1   Account 2   Account 3
        │
    ┌───┴───┐
    │       │
Storage Storage
 Key 1   Key 2
```

## Learning Path

### Beginner

1. Understand blockchain basics
2. Learn stack machine concepts
3. Practice simple opcode execution
4. Build a basic calculator in EVM

### Intermediate

1. Study gas optimization
2. Implement memory/storage operations
3. Explore smart contract patterns
4. Write a token contract from scratch

### Advanced

1. Master parallel execution
2. Research latest EIPs
3. Contribute to open source
4. Develop novel optimizations

## Resources

- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)
- [EVM Opcodes Reference](https://www.evm.codes/)
- [Ethereum Gas Documentation](https://ethereum.org/en/developers/docs/gas/)
- [Solidity Documentation](https://docs.soliditylang.org/)
