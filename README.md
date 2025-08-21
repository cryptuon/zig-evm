# Ethereum Virtual Machine (EVM) in Zig

<Breaking changes everyday, do not use in production!>

This project is an experimental implementation of the Ethereum Virtual Machine (EVM) using the Zig programming language. It aims to provide a lightweight, modular, and educational EVM implementation for learning and experimentation purposes.

## Features

- Basic EVM opcodes implementation
- Support for contract deployment and execution
- Simplified account and storage model
- Gas calculation and management
- Support for precompiled contracts
- Dynamic opcode loading from separate files
- Example implementation of a simple ERC20-like token contract
- Available as both a library and an executable

## Prerequisites

- Zig compiler (latest version recommended)
- Basic understanding of Ethereum and EVM concepts

## Project Structure

```
.
├── src/
│   ├── main.zig
│   ├── bigint.zig
│   ├── memory.zig
│   ├── stack.zig
│   └── opcodes/
│       ├── add.zig
│       ├── mul.zig
│       ├── push1.zig
│       ├── pop.zig
│       └── stop.zig
├── README.md
└── build.zig
```

## Setup

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/zig-evm.git
   cd zig-evm
   ```

## Building

This project now uses the Zig build system. You can:

1. Build the executable:
   ```
   zig build
   ```

2. Run the executable directly:
   ```
   zig build run
   ```

3. Run tests (if any):
   ```
   zig build test
   ```

## Installation

To install the executable globally:
```
zig build install
```

This will install the `zig-evm` executable to the default installation prefix.

## Usage

### As an Executable

Run the installed executable:
```
zig-evm
```

This will execute the example scenario defined in `main.zig`, which includes:
1. Deploying an ERC20-like contract
2. Checking the balance of an address
3. Performing a token transfer
4. Checking the balance after the transfer

### As a Library

To use this project as a library in your own Zig project:

1. Add it as a dependency in your `build.zig`:
   ```zig
   const evm = b.addModule("evm", .{
       .source_file = .{ .path = "path/to/zig-evm/src/main.zig" },
   });
   ```

2. Import and use in your code:
   ```zig
   const EVM = @import("evm").EVM;
   const Transaction = @import("evm").Transaction;
   // ... use the EVM functionality
   ```

## Extending the EVM

### Adding new opcodes

1. Create a new file in the `src/opcodes/` directory (e.g., `src/opcodes/newop.zig`)
2. Implement the opcode following the structure in existing opcode files
3. Register the opcode in the `loadOpcodes` function in `main.zig`

### Modifying gas costs

Adjust the `useGas` function calls in the opcode implementations to change gas costs for operations.

### Implementing more precompiled contracts

Add new precompiled contracts in the `loadPrecompiled` function in `main.zig`.

## Current Status

The EVM implementation is still in early development stages. We have successfully implemented:

- Core data structures: BigInt (256-bit integer), Memory, Stack
- Basic opcodes: ADD, MUL, PUSH1, POP, STOP
- Basic EVM execution framework
- Simple test demonstrating correct execution of bytecode

The EVM can now execute simple arithmetic operations correctly, as demonstrated by our test that computes (3 + 4) * 2 = 14.

For a complete implementation plan, see [PLAN.md](PLAN.md).

## Limitations

This is an experimental implementation and has several limitations:

- Not all EVM opcodes are implemented
- Gas calculation is simplified
- The state and storage models are basic
- Error handling and edge cases may not be fully covered
- Performance optimizations are not implemented
- Dynamic opcode loading has limitations when used as a library

## Contributing

Contributions to this experimental project are welcome! Please feel free to submit issues, feature requests, or pull requests.

## Disclaimer

This project is for educational and experimental purposes only. It is not intended for use in production environments or with real cryptocurrency transactions.

## License

This project is open-source and available under the MIT License.
