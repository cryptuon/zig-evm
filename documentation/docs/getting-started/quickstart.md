# Quick Start

Get up and running with Zig EVM in minutes.

## Your First EVM Execution

Let's execute a simple program that adds two numbers: `3 + 5 = 8`.

The EVM bytecode for this is:

```
PUSH1 0x03  (0x60 0x03)  - Push 3 onto the stack
PUSH1 0x05  (0x60 0x05)  - Push 5 onto the stack
ADD         (0x01)       - Pop two values, push their sum
STOP        (0x00)       - Halt execution
```

=== "Zig"

    ```zig
    const std = @import("std");
    const EVM = @import("main.zig").EVM;

    pub fn main() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        // Create EVM instance
        var evm = try EVM.init(gpa.allocator());
        defer evm.deinit();

        // Set bytecode: PUSH1 3, PUSH1 5, ADD, STOP
        evm.code = &[_]u8{ 0x60, 0x03, 0x60, 0x05, 0x01, 0x00 };

        // Set gas limit
        evm.setGasLimit(100000);

        // Execute
        try evm.execute();

        // Get result from stack
        const result = evm.stack.pop().?;
        std.debug.print("3 + 5 = {}\n", .{result.data[0]});
    }
    ```

=== "Python"

    ```python
    from zigevm import EVM

    # Create EVM instance
    evm = EVM()

    # Configure
    evm.set_gas_limit(100000)

    # Bytecode: PUSH1 3, PUSH1 5, ADD, STOP
    code = bytes([0x60, 0x03, 0x60, 0x05, 0x01, 0x00])

    # Execute
    result = evm.execute(code)

    print(f"Success: {result.success}")
    print(f"Gas used: {result.gas_used}")

    # Cleanup
    evm.destroy()
    ```

=== "JavaScript"

    ```javascript
    const { EVM } = require('zigevm');

    // Create EVM instance
    const evm = new EVM();

    // Configure
    evm.setGasLimit(100000n);

    // Bytecode: PUSH1 3, PUSH1 5, ADD, STOP
    const code = Buffer.from([0x60, 0x03, 0x60, 0x05, 0x01, 0x00]);

    // Execute
    const result = evm.execute(code);

    console.log(`Success: ${result.success}`);
    console.log(`Gas used: ${result.gasUsed}`);

    // Cleanup
    evm.destroy();
    ```

=== "C"

    ```c
    #include <stdio.h>
    #include "zigevm.h"

    int main() {
        // Create EVM instance
        EVMHandle evm = evm_create();
        if (!evm) {
            fprintf(stderr, "Failed to create EVM\n");
            return 1;
        }

        // Configure
        evm_set_gas_limit(evm, 100000);

        // Bytecode: PUSH1 3, PUSH1 5, ADD, STOP
        uint8_t code[] = {0x60, 0x03, 0x60, 0x05, 0x01, 0x00};

        // Execute
        EVMResult result = evm_execute(evm, code, sizeof(code), NULL, 0);

        printf("Success: %d\n", result.success);
        printf("Gas used: %lu\n", result.gas_used);

        // Cleanup
        evm_destroy(evm);
        return 0;
    }
    ```

=== "Rust"

    ```rust
    use zigevm::{Evm, EvmError};

    fn main() -> Result<(), EvmError> {
        // Create EVM instance
        let mut evm = Evm::new()?;

        // Configure
        evm.set_gas_limit(100_000);

        // Bytecode: PUSH1 3, PUSH1 5, ADD, STOP
        let code = vec![0x60, 0x03, 0x60, 0x05, 0x01, 0x00];

        // Execute
        let result = evm.execute(&code, &[])?;

        println!("Success: {}", result.success);
        println!("Gas used: {}", result.gas_used);

        Ok(())
    }
    ```

## Running from CLI

If you've built the project, you can run the demo:

```bash
zig build run
```

This executes a sample program and shows the result.

## Working with Memory

Store and retrieve values from EVM memory:

=== "Python"

    ```python
    from zigevm import EVM

    evm = EVM()
    evm.set_gas_limit(100000)

    # Store 42 at memory offset 0, then return it
    # PUSH1 42, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
    code = bytes([
        0x60, 0x2a,  # PUSH1 42
        0x60, 0x00,  # PUSH1 0
        0x52,        # MSTORE
        0x60, 0x20,  # PUSH1 32
        0x60, 0x00,  # PUSH1 0
        0xf3         # RETURN
    ])

    result = evm.execute(code)

    print(f"Return data: {result.return_data.hex()}")
    # Output: 000000000000000000000000000000000000000000000000000000000000002a
    # (42 in hex is 0x2a, padded to 32 bytes)

    evm.destroy()
    ```

=== "JavaScript"

    ```javascript
    const { EVM } = require('zigevm');

    const evm = new EVM();
    evm.setGasLimit(100000n);

    // Store 42 at memory offset 0, then return it
    const code = Buffer.from([
        0x60, 0x2a,  // PUSH1 42
        0x60, 0x00,  // PUSH1 0
        0x52,        // MSTORE
        0x60, 0x20,  // PUSH1 32
        0x60, 0x00,  // PUSH1 0
        0xf3         // RETURN
    ]);

    const result = evm.execute(code);

    console.log(`Return data: ${result.returnData.toString('hex')}`);

    evm.destroy();
    ```

## Working with Storage

Persistent storage operations:

=== "Python"

    ```python
    from zigevm import EVM

    evm = EVM()
    evm.set_gas_limit(100000)

    # Set up account
    address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    evm.set_address(address)

    # Pre-set storage slot 0 to 100
    evm.set_storage(address, 0, 100)

    # Load storage slot 0: PUSH1 0, SLOAD, STOP
    code = bytes([
        0x60, 0x00,  # PUSH1 0 (storage slot)
        0x54,        # SLOAD
        0x00         # STOP
    ])

    result = evm.execute(code)

    # Peek at stack to see loaded value
    value = evm.stack_peek(0)
    print(f"Storage value: {int.from_bytes(value, 'big')}")  # 100

    evm.destroy()
    ```

## Parallel Execution

Process multiple transactions in parallel:

=== "Python"

    ```python
    from zigevm import BatchExecutor, BatchConfig, BatchTransaction

    # Configure parallel execution
    config = BatchConfig(
        max_threads=8,
        enable_parallel=True,
        chain_id=1,
        block_number=12345678,
    )

    executor = BatchExecutor(config)

    # Set up accounts
    for i in range(10):
        executor.set_account(
            address=f"0x{'%040x' % i}",
            balance=100 * 10**18,
            nonce=0,
        )

    # Create transactions
    transactions = []
    for i in range(100):
        transactions.append(BatchTransaction(
            from_addr=f"0x{'%040x' % (i % 10)}",
            to_addr=f"0x{'%040x' % ((i + 1) % 10)}",
            value=1 * 10**18,
            gas_limit=21000,
        ))

    # Execute in parallel
    stats = executor.execute(transactions)

    print(f"Transactions: {stats.total_transactions}")
    print(f"Parallel waves: {stats.parallel_waves}")
    print(f"Throughput: {stats.total_transactions / (stats.execution_time_ns / 1e9):.0f} tx/s")
    ```

## Next Steps

- [Basic Usage](basic-usage.md) - Learn more about EVM configuration
- [Architecture](../user-guide/architecture.md) - Understand how Zig EVM works
- [API Reference](../api-reference/zig-api.md) - Complete API documentation
