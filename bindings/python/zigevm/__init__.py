"""
Zig EVM Python Bindings

A high-performance EVM implementation for L2/Rollup execution.

Usage:
    from zigevm import EVM

    evm = EVM()
    evm.set_gas_limit(1000000)
    result = evm.execute(bytecode, calldata)
    print(f"Gas used: {result.gas_used}")
"""

from .evm import EVM, EVMResult, EVMError, Log

__version__ = "0.1.0"
__all__ = ["EVM", "EVMResult", "EVMError", "Log"]
