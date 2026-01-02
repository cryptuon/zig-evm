# Installation

This guide covers how to install Zig EVM and its language bindings.

## Prerequisites

- **Zig 0.13.0 or later** - [Download Zig](https://ziglang.org/download/)

For language bindings:

- **Python 3.8+** (for Python bindings)
- **Rust 1.70+** (for Rust bindings)
- **Node.js 18+** (for JavaScript bindings)

## Building from Source

### Clone the Repository

```bash
git clone https://github.com/cryptuon/zig-evm.git
cd zig-evm
```

### Build the EVM

```bash
# Build and run the CLI demo
zig build run

# Run all tests
zig build test

# Build with optimizations
zig build -Doptimize=ReleaseFast
```

### Build the Shared Library

To use Zig EVM from other languages, build the shared library:

```bash
zig build lib
```

This produces:

| Platform | Shared Library | Static Library | Header |
|----------|---------------|----------------|--------|
| Linux | `zig-out/lib/libzigevm.so` | `zig-out/lib/libzigevm.a` | `zig-out/include/zigevm.h` |
| macOS | `zig-out/lib/libzigevm.dylib` | `zig-out/lib/libzigevm.a` | `zig-out/include/zigevm.h` |
| Windows | `zig-out/lib/zigevm.dll` | `zig-out/lib/zigevm.lib` | `zig-out/include/zigevm.h` |

## Language Bindings

### Python

```bash
cd bindings/python
pip install -e .
```

Or install after building the library:

```bash
zig build lib
pip install ./bindings/python
```

Verify the installation:

```python
from zigevm import EVM
evm = EVM()
print("Zig EVM Python bindings installed successfully!")
evm.destroy()
```

### Rust

Add to your `Cargo.toml`:

```toml
[dependencies]
zigevm = { path = "path/to/zig-evm/bindings/rust/zigevm" }
```

Or build from source:

```bash
cd bindings/rust/zigevm
cargo build --release
```

### JavaScript / Node.js

```bash
cd bindings/js
npm install
npm run build
```

Or when published to npm:

```bash
npm install zigevm
```

## Verifying Installation

### Run Tests

```bash
# Unit tests
zig build test

# Ethereum compliance tests
zig build compliance
```

### Run Demos

```bash
# Basic EVM demo
zig build run

# Parallel execution demo
zig build parallel-opt

# Performance benchmarks
zig build benchmark
```

## Build Targets Reference

| Command | Description |
|---------|-------------|
| `zig build run` | Build and run CLI demo |
| `zig build test` | Run unit tests |
| `zig build compliance` | Run Ethereum compliance tests |
| `zig build lib` | Build shared/static libraries |
| `zig build parallel` | Run parallel execution demo |
| `zig build parallel-opt` | Run optimized parallel demo |
| `zig build benchmark` | Run performance benchmarks |
| `zig build bench` | Run simple benchmarks |
| `zig build demo` | Run benchmark demonstration |

## Build Options

```bash
# Release build with optimizations
zig build run -Doptimize=ReleaseFast

# Cross-compile for different targets
zig build run -Dtarget=x86_64-linux
zig build run -Dtarget=aarch64-macos
zig build run -Dtarget=x86_64-windows
```

## Next Steps

- [Quick Start](quickstart.md) - Run your first EVM code
- [Basic Usage](basic-usage.md) - Learn the fundamentals
