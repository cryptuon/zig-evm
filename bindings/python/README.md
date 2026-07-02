# zigevm

Python bindings for **[Zig-EVM](https://zig-evm.cryptuon.com/)** — a high-performance EVM in Zig with wave-based parallel transaction execution (5-6x speedup).

Embed a full Ethereum Virtual Machine in your Python application through a native ctypes wrapper over the Zig-EVM C ABI.

## Install

```bash
pip install zigevm
```

> Requires the Zig-EVM shared library. Build it with `zig build lib` from the [project repository](https://github.com/cryptuon/zig-evm).

## Usage

```python
from zigevm import EVM

evm = EVM()
evm.set_gas_limit(100000)

# PUSH1 3, PUSH1 5, ADD, STOP
code = bytes([0x60, 0x03, 0x60, 0x05, 0x01, 0x00])
result = evm.execute(code)

print(f"Success: {result.success}, Gas used: {result.gas_used}")
evm.destroy()
```

## Links

- Site: https://zig-evm.cryptuon.com/
- Docs: https://docs.cryptuon.com/zig-evm/
- GitHub: https://github.com/cryptuon/zig-evm

---

Part of [Cryptuon Research](https://www.cryptuon.com) · MIT License · contact@cryptuon.com
