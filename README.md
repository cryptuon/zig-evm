# Ethereum Virtual Machine (EVM) in Zig

This project is an experimental implementation of the Ethereum Virtual Machine (EVM) using the Zig programming language. It aims to provide a lightweight, modular, and educational EVM implementation for learning and experimentation purposes.

## Features

- Basic EVM opcodes implementation
- Support for contract deployment and execution
- Simplified account and storage model
- Gas calculation and management
- Support for precompiled contracts
- Dynamic opcode loading from separate files
- Example implementation of a simple ERC20-like token contract

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
│       ├── sub.zig
│       ├── mul.zig
│       └── ...
├── README.md
└── build.zig
```

## Setup

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/zig-evm.git
   cd zig-evm
   ```

2. Build the project:
   ```
   zig build-exe src/main.zig
   ```

## Usage

Run the compiled executable:

```
./main
```

This will execute the example scenario defined in `main.zig`, which includes:
1. Deploying an ERC20-like contract
2. Checking the balance of an address
3. Performing a token transfer
4. Checking the balance after the transfer

## Extending the EVM

### Adding new opcodes

1. Create a new file in the `src/opcodes/` directory (e.g., `src/opcodes/newop.zig`)
2. Implement the opcode following the structure in existing opcode files
3. The EVM will automatically load and use the new opcode

### Modifying gas costs

Adjust the `useGas` function calls in the opcode implementations to change gas costs for operations.

### Implementing more precompiled contracts

Add new precompiled contracts in the `loadPrecompiled` function in `main.zig`.

## Limitations

This is an experimental implementation and has several limitations:

- Not all EVM opcodes are implemented
- Gas calculation is simplified
- The state and storage models are basic
- Error handling and edge cases may not be fully covered
- Performance optimizations are not implemented

## Contributing

Contributions to this experimental project are welcome! Please feel free to submit issues, feature requests, or pull requests.

## Disclaimer

This project is for educational and experimental purposes only. It is not intended for use in production environments or with real cryptocurrency transactions.

## License

This project is open-source and available under the MIT License.