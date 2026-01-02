# Gas Metering

Understanding and working with gas costs in Zig EVM.

## What is Gas?

Gas is the unit of computational effort in the EVM. Every operation costs gas, and transactions must include enough gas to complete execution.

### Purpose of Gas

| Purpose | Description |
|---------|-------------|
| **Prevent infinite loops** | Every operation costs gas |
| **Resource allocation** | Expensive operations cost more |
| **Network security** | Spam protection |
| **Miner incentives** | Gas fees reward block producers |

## Gas Costs

### Base Costs by Category

| Operation | Gas Cost | Example |
|-----------|----------|---------|
| Zero-cost | 0 | STOP |
| Very low | 2 | ADDRESS, CALLER |
| Low | 3 | ADD, SUB, PUSH, POP |
| Medium | 5 | MUL, DIV |
| High | 8-10 | ADDMOD, EXP |
| Storage read | 100-2100 | SLOAD |
| Storage write | 100-20000 | SSTORE |
| Contract creation | 32000 | CREATE |

### Arithmetic Operations

```zig
STOP      => 0
ADD, SUB  => 3
MUL, DIV  => 5
MOD       => 5
ADDMOD    => 8
MULMOD    => 8
EXP       => 10 + 50 * byte_size(exponent)
```

### Stack Operations

```zig
POP      => 2
PUSH1-32 => 3
DUP1-16  => 3
SWAP1-16 => 3
```

### Memory Operations

```zig
MLOAD    => 3 + memory_expansion_cost
MSTORE   => 3 + memory_expansion_cost
MSTORE8  => 3 + memory_expansion_cost
MSIZE    => 2
```

### Storage Operations

```zig
// SLOAD
Cold access    => 2100
Warm access    => 100

// SSTORE
Set (0 -> non-0)     => 20000
Reset (non-0 -> non-0) => 5000
Clear (non-0 -> 0)    => 5000 (+ 4800 refund)
No-op (same value)    => 100
```

### Call Operations

```zig
CALL, STATICCALL, DELEGATECALL => 100 + memory_cost + value_transfer
CREATE  => 32000 + code_deposit
CREATE2 => 32000 + hash_cost + code_deposit
```

## Memory Expansion Cost

Memory gas grows quadratically to prevent excessive memory use:

```
memory_cost = (memory_size_words * 3) + (memory_size_words² / 512)
```

Example:

| Memory Size | Words | Cost |
|-------------|-------|------|
| 32 bytes | 1 | 3 |
| 64 bytes | 2 | 6 |
| 256 bytes | 8 | 24 |
| 1 KB | 32 | 98 |
| 1 MB | 32768 | 2,195,456 |

## Setting Gas Limits

=== "Python"

    ```python
    from zigevm import EVM

    evm = EVM()

    # Set gas limit for execution
    evm.set_gas_limit(1000000)

    result = evm.execute(code)

    print(f"Gas used: {result.gas_used}")
    print(f"Gas remaining: {result.gas_remaining}")
    ```

=== "JavaScript"

    ```javascript
    const { EVM } = require('zigevm');

    const evm = new EVM();

    // Set gas limit for execution
    evm.setGasLimit(1000000n);

    const result = evm.execute(code);

    console.log(`Gas used: ${result.gasUsed}`);
    console.log(`Gas remaining: ${result.gasRemaining}`);
    ```

=== "C"

    ```c
    EVMHandle evm = evm_create();

    // Set gas limit for execution
    evm_set_gas_limit(evm, 1000000);

    EVMResult result = evm_execute(evm, code, code_len, NULL, 0);

    printf("Gas used: %lu\n", result.gas_used);
    printf("Gas remaining: %lu\n", result.gas_remaining);
    ```

## Out of Gas Handling

When gas is exhausted:

1. Execution halts immediately
2. All state changes are reverted
3. `OutOfGas` error is returned
4. Consumed gas is not refunded

=== "Python"

    ```python
    result = evm.execute(code)

    if not result.success and result.error_code == 1:  # OutOfGas
        print("Out of gas!")
        print(f"Gas used before failure: {result.gas_used}")
    ```

=== "JavaScript"

    ```javascript
    const result = evm.execute(code);

    if (!result.success && result.errorCode === 1) {  // OutOfGas
        console.log('Out of gas!');
        console.log(`Gas used before failure: ${result.gasUsed}`);
    }
    ```

## Gas Estimation

Estimate gas before execution:

```python
# Start with a high gas limit
evm.set_gas_limit(10_000_000)

result = evm.execute(code)

if result.success:
    estimated_gas = result.gas_used
    # Add 10% buffer for safety
    recommended_gas = int(estimated_gas * 1.1)
    print(f"Recommended gas limit: {recommended_gas}")
```

## Gas Refunds

Certain operations provide gas refunds:

| Operation | Refund |
|-----------|--------|
| SSTORE (clear) | 4800 |
| SELFDESTRUCT | 0 (removed in recent EIPs) |

**Maximum refund**: Capped at 20% of total gas used (post-EIP-3529).

## Intrinsic Gas

Transaction base costs:

| Component | Cost |
|-----------|------|
| Base transaction | 21000 |
| Zero data byte | 4 |
| Non-zero data byte | 16 |
| Contract creation | +32000 |
| Access list (address) | 2400 |
| Access list (slot) | 1900 |

## EIP-2929 Access Lists

Cold/warm access model for addresses and storage:

```
Cold address access:   2600 gas
Warm address access:   100 gas

Cold storage access:   2100 gas
Warm storage access:   100 gas
```

First access to an address or storage slot is "cold" and costs more.

## Gas Optimization Tips

### 1. Minimize Storage Operations

Storage is expensive. Cache values in memory:

```solidity
// Bad: Multiple SLOADs
for (uint i = 0; i < array.length; i++) {
    total += array[i];  // SLOAD each iteration
}

// Good: Single SLOAD
uint len = array.length;  // SLOAD once
for (uint i = 0; i < len; i++) {
    total += array[i];
}
```

### 2. Pack Storage

Use smaller types to pack multiple values in one slot:

```solidity
// Bad: 3 storage slots
uint256 a;
uint256 b;
uint256 c;

// Good: 1 storage slot
uint128 a;
uint64 b;
uint64 c;
```

### 3. Short-Circuit Conditions

Order conditions by likelihood and cost:

```solidity
// Bad: Expensive check first
if (expensiveCheck() && cheapCheck()) { ... }

// Good: Cheap check first
if (cheapCheck() && expensiveCheck()) { ... }
```

### 4. Use Memory over Storage

Memory is much cheaper than storage:

```solidity
// Bad: Modify storage directly
storageArray.push(value);

// Good: Build in memory, then store
uint[] memory temp = new uint[](length);
// ... fill temp ...
storageArray = temp;
```

## Gas Cost Reference Table

| Opcode | Base Cost | Dynamic Cost |
|--------|-----------|--------------|
| ADD | 3 | - |
| MUL | 5 | - |
| EXP | 10 | 50 * byte_size |
| SHA3 | 30 | 6 * word_size |
| BALANCE | 100/2600 | cold/warm |
| SLOAD | 100/2100 | warm/cold |
| SSTORE | 100-20000 | varies |
| CALL | 100 | + memory + value |
| CREATE | 32000 | + memory + deposit |
| LOG0 | 375 | + 8 * data_size |
| LOG1 | 750 | + 8 * data_size |
| LOG2 | 1125 | + 8 * data_size |
| LOG3 | 1500 | + 8 * data_size |
| LOG4 | 1875 | + 8 * data_size |
