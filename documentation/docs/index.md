# Zig EVM

A high-performance, embeddable Ethereum Virtual Machine implementation in Zig, designed for L2/Rollup execution with parallel transaction processing.

<div class="grid cards" markdown>

-   :zap: **High Performance**

    ---

    5-6x throughput improvement with parallel execution and O(n) dependency analysis.

-   :package: **Embeddable**

    ---

    Use from C, Python, Rust, or JavaScript via FFI bindings.

-   :white_check_mark: **Complete EVM**

    ---

    141 opcodes implemented with Ethereum-compliant gas metering.

-   :rocket: **Production Ready**

    ---

    Built with Zig for reliability, safety, and performance.

</div>

## Features

### Complete EVM Implementation

- **141 opcodes implemented** - Full instruction set including arithmetic, memory, storage, control flow, and system operations
- **256-bit arithmetic** - Full BigInt support with modular operations
- **Gas metering** - Ethereum-compliant gas costs for all operations
- **Call stack** - Nested execution with CALL, DELEGATECALL, STATICCALL

### Parallel Execution

- **Wave-based parallelism** - 5-6x throughput improvement
- **O(n) dependency analysis** - Hash-based conflict detection
- **Work-stealing thread pool** - Efficient load balancing
- **Speculative execution** - Optimistic parallelism with rollback

### Multi-Language Support

- **C ABI** - Use from any language with FFI support
- **Python bindings** - Native ctypes wrapper
- **Rust bindings** - Safe Rust API
- **JavaScript bindings** - Node.js N-API addon

## Quick Example

=== "Zig"

    ```zig
    const std = @import("std");
    const EVM = @import("main.zig").EVM;

    pub fn main() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        var evm = try EVM.init(gpa.allocator());
        defer evm.deinit();

        // Execute: PUSH1 3, PUSH1 5, ADD, STOP
        evm.code = &[_]u8{ 0x60, 0x03, 0x60, 0x05, 0x01, 0x00 };
        evm.setGasLimit(100000);

        try evm.execute();

        const result = evm.stack.pop().?;
        std.debug.print("Result: {}\n", .{result.data[0]}); // 8
    }
    ```

=== "Python"

    ```python
    from zigevm import EVM

    evm = EVM()
    evm.set_gas_limit(100000)

    code = bytes([0x60, 0x03, 0x60, 0x05, 0x01, 0x00])
    result = evm.execute(code)

    print(f"Success: {result.success}, Gas used: {result.gas_used}")
    evm.destroy()
    ```

=== "JavaScript"

    ```javascript
    const { EVM } = require('zigevm');

    const evm = new EVM();
    evm.setGasLimit(100000n);

    const code = Buffer.from([0x60, 0x03, 0x60, 0x05, 0x01, 0x00]);
    const result = evm.execute(code);

    console.log(`Success: ${result.success}, Gas used: ${result.gasUsed}`);
    evm.destroy();
    ```

=== "C"

    ```c
    #include "zigevm.h"

    int main() {
        EVMHandle evm = evm_create();
        evm_set_gas_limit(evm, 100000);

        uint8_t code[] = {0x60, 0x03, 0x60, 0x05, 0x01, 0x00};
        EVMResult result = evm_execute(evm, code, sizeof(code), NULL, 0);

        printf("Success: %d, Gas used: %lu\n", result.success, result.gas_used);

        evm_destroy(evm);
        return 0;
    }
    ```

## Performance

| Transactions | Sequential | Parallel (8 threads) | Speedup |
|-------------|------------|---------------------|---------|
| 100         | 96.8ms     | 18.9ms              | 5.1x    |
| 500         | 485ms      | 82ms                | 5.9x    |
| 1000        | 970ms      | 162ms               | 6.0x    |

## Getting Started

Ready to start using Zig EVM? Check out the [Installation Guide](getting-started/installation.md) to get started.

## License

Zig EVM is released under the MIT License. See [LICENSE](https://github.com/cryptuon/zig-evm/blob/main/LICENSE) for details.
