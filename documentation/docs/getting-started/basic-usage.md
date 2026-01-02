# Basic Usage

Learn the fundamentals of working with Zig EVM.

## EVM Lifecycle

### Creating an Instance

=== "Zig"

    ```zig
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var evm = try EVM.init(gpa.allocator());
    defer evm.deinit();
    ```

=== "Python"

    ```python
    from zigevm import EVM

    evm = EVM()
    # ... use evm ...
    evm.destroy()
    ```

=== "JavaScript"

    ```javascript
    const { EVM } = require('zigevm');

    const evm = new EVM();
    // ... use evm ...
    evm.destroy();
    ```

=== "C"

    ```c
    EVMHandle evm = evm_create();
    // ... use evm ...
    evm_destroy(evm);
    ```

### Resetting State

Reset execution state while preserving account data:

=== "Python"

    ```python
    evm.reset()  # Clears stack, memory, PC; keeps accounts
    ```

=== "JavaScript"

    ```javascript
    evm.reset();
    ```

## Configuration

### Gas Limit

Set the maximum gas for execution:

=== "Python"

    ```python
    evm.set_gas_limit(1000000)
    ```

=== "JavaScript"

    ```javascript
    evm.setGasLimit(1000000n);
    ```

=== "C"

    ```c
    evm_set_gas_limit(evm, 1000000);
    ```

### Block Context

Set block-related information:

=== "Python"

    ```python
    evm.set_block_number(12345678)
    evm.set_timestamp(1640000000)
    evm.set_chain_id(1)  # 1 = mainnet
    evm.set_coinbase("0x0000000000000000000000000000000000000000")
    ```

=== "JavaScript"

    ```javascript
    evm.setBlockNumber(12345678n);
    evm.setTimestamp(1640000000n);
    evm.setChainId(1n);
    evm.setCoinbase('0x0000000000000000000000000000000000000000');
    ```

### Transaction Context

Set transaction-related information:

=== "Python"

    ```python
    evm.set_address("0xaaaa...")      # Current contract address
    evm.set_caller("0xbbbb...")       # msg.sender
    evm.set_origin("0xcccc...")       # tx.origin
    evm.set_value(1000000000000000000)  # 1 ETH in wei
    ```

=== "JavaScript"

    ```javascript
    evm.setAddress('0xaaaa...');
    evm.setCaller('0xbbbb...');
    evm.setOrigin('0xcccc...');
    evm.setValue(1000000000000000000n);  // 1 ETH in wei
    ```

## Account Management

### Setting Balances

=== "Python"

    ```python
    address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    evm.set_balance(address, 100 * 10**18)  # 100 ETH
    ```

=== "JavaScript"

    ```javascript
    const address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    evm.setBalance(address, 100n * 10n**18n);  // 100 ETH
    ```

### Setting Contract Code

=== "Python"

    ```python
    address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    bytecode = bytes.fromhex("6080604052...")
    evm.set_code(address, bytecode)
    ```

=== "JavaScript"

    ```javascript
    const address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const bytecode = Buffer.from('6080604052...', 'hex');
    evm.setCode(address, bytecode);
    ```

### Storage Operations

=== "Python"

    ```python
    address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    # Set storage
    evm.set_storage(address, key=0, value=42)
    evm.set_storage(address, key=1, value=0xdeadbeef)

    # Get storage
    value = evm.get_storage(address, key=0)
    print(int.from_bytes(value, 'big'))  # 42
    ```

=== "JavaScript"

    ```javascript
    const address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    // Set storage
    evm.setStorage(address, 0, 42);
    evm.setStorage(address, 1, 0xdeadbeefn);

    // Get storage
    const value = evm.getStorage(address, 0);
    console.log(value);
    ```

## Executing Code

### Basic Execution

=== "Python"

    ```python
    # Bytecode: PUSH1 3, PUSH1 5, ADD, STOP
    code = bytes([0x60, 0x03, 0x60, 0x05, 0x01, 0x00])

    result = evm.execute(code)

    if result.success:
        print(f"Gas used: {result.gas_used}")
    else:
        print(f"Error: {result.error_name}")
    ```

=== "JavaScript"

    ```javascript
    const code = Buffer.from([0x60, 0x03, 0x60, 0x05, 0x01, 0x00]);

    const result = evm.execute(code);

    if (result.success) {
        console.log(`Gas used: ${result.gasUsed}`);
    } else {
        console.log(`Error: ${result.errorName}`);
    }
    ```

### Execution with Calldata

=== "Python"

    ```python
    code = bytes.fromhex("6080604052...")  # Contract bytecode
    calldata = bytes.fromhex("a9059cbb...")  # Function call

    result = evm.execute(code, calldata)
    ```

=== "JavaScript"

    ```javascript
    const code = Buffer.from('6080604052...', 'hex');
    const calldata = Buffer.from('a9059cbb...', 'hex');

    const result = evm.execute(code, calldata);
    ```

## Handling Results

### EVMResult Structure

| Field | Description |
|-------|-------------|
| `success` | Whether execution completed without error |
| `error_code` | Error code (if failed) |
| `error_name` | Human-readable error name |
| `gas_used` | Gas consumed during execution |
| `gas_remaining` | Gas remaining after execution |
| `return_data` | Data returned by RETURN opcode |
| `reverted` | Whether REVERT was called |

### Checking Results

=== "Python"

    ```python
    result = evm.execute(code)

    if result.success:
        print(f"Execution successful")
        print(f"Gas used: {result.gas_used}")
        print(f"Return data: {result.return_data.hex()}")
    elif result.reverted:
        print(f"Transaction reverted")
        print(f"Revert reason: {result.return_data}")
    else:
        print(f"Execution failed: {result.error_name}")
    ```

=== "JavaScript"

    ```javascript
    const result = evm.execute(code);

    if (result.success) {
        console.log('Execution successful');
        console.log(`Gas used: ${result.gasUsed}`);
        console.log(`Return data: ${result.returnData.toString('hex')}`);
    } else if (result.reverted) {
        console.log('Transaction reverted');
        console.log(`Revert reason: ${result.returnData}`);
    } else {
        console.log(`Execution failed: ${result.errorName}`);
    }
    ```

## Reading Logs

Access logs emitted during execution:

=== "Python"

    ```python
    result = evm.execute(code)

    for log in evm.get_logs():
        print(f"Address: {log.address.hex()}")
        print(f"Topics: {[t.hex() for t in log.topics]}")
        print(f"Data: {log.data.hex()}")
    ```

=== "JavaScript"

    ```javascript
    const result = evm.execute(code);

    for (const log of evm.getLogs()) {
        console.log(`Address: ${log.address.toString('hex')}`);
        console.log(`Topics: ${log.topics.map(t => t.toString('hex'))}`);
        console.log(`Data: ${log.data.toString('hex')}`);
    }
    ```

## Debugging

### Stack Inspection

=== "Python"

    ```python
    # Check stack depth
    depth = evm.stack_depth
    print(f"Stack has {depth} items")

    # Peek at stack (0 = top)
    if depth > 0:
        top = evm.stack_peek(0)
        print(f"Top of stack: {int.from_bytes(top, 'big')}")
    ```

### Memory Inspection

=== "Python"

    ```python
    # Check memory size
    size = evm.memory_size
    print(f"Memory size: {size} bytes")

    # Read memory region
    data = evm.memory_read(offset=0, length=32)
    print(f"Memory[0:32]: {data.hex()}")
    ```

## Error Handling

### Error Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | OK | Success |
| 1 | OutOfGas | Insufficient gas |
| 2 | StackUnderflow | Pop from empty stack |
| 3 | StackOverflow | Stack exceeds 1024 items |
| 4 | InvalidOpcode | Unknown opcode |
| 5 | InvalidJump | Jump to non-JUMPDEST |
| 6 | Revert | REVERT opcode called |
| 7 | StaticCallViolation | State modification in static call |
| 8 | OutOfMemory | Memory allocation failed |
| 9 | CallDepthExceeded | Call depth > 1024 |
| 10 | InsufficientBalance | Not enough balance |

### Handling Errors

=== "Python"

    ```python
    result = evm.execute(code)

    if not result.success:
        if result.error_code == 1:  # OutOfGas
            print("Increase gas limit")
        elif result.error_code == 6:  # Revert
            print(f"Reverted: {result.return_data}")
        else:
            print(f"Error {result.error_code}: {result.error_name}")
    ```

## Next Steps

- [Architecture](../user-guide/architecture.md) - Deep dive into EVM internals
- [Parallel Execution](../user-guide/parallel-execution.md) - Process transactions in parallel
- [API Reference](../api-reference/zig-api.md) - Complete API documentation
