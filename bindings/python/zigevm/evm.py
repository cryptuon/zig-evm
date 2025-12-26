"""
Zig EVM Python Bindings - Core EVM Implementation
"""

import ctypes
from ctypes import (
    c_void_p, c_uint64, c_size_t, c_uint8, c_int, c_bool, c_char_p,
    POINTER, Structure, byref, create_string_buffer
)
from enum import IntEnum
from typing import Optional, List, Tuple
from dataclasses import dataclass
import os
import sys

# ============================================================
# Library Loading
# ============================================================

def _find_library() -> str:
    """Find the zigevm shared library."""
    # Check common locations
    candidates = []

    # Platform-specific library names
    if sys.platform == "darwin":
        lib_name = "libzigevm.dylib"
    elif sys.platform == "win32":
        lib_name = "zigevm.dll"
    else:
        lib_name = "libzigevm.so"

    # Check relative to this file
    module_dir = os.path.dirname(os.path.abspath(__file__))
    candidates.append(os.path.join(module_dir, lib_name))
    candidates.append(os.path.join(module_dir, "..", lib_name))
    candidates.append(os.path.join(module_dir, "..", "..", "zig-out", "lib", lib_name))
    candidates.append(os.path.join(module_dir, "..", "..", "..", "zig-out", "lib", lib_name))

    # Check system paths
    candidates.append(lib_name)

    for path in candidates:
        if os.path.exists(path):
            return path

    # Try loading from system path
    return lib_name

_lib = None

def _get_lib():
    """Get or load the shared library."""
    global _lib
    if _lib is None:
        lib_path = _find_library()
        _lib = ctypes.CDLL(lib_path)
        _setup_functions(_lib)
    return _lib

# ============================================================
# Error Codes
# ============================================================

class EVMError(IntEnum):
    """EVM execution error codes."""
    OK = 0
    OUT_OF_GAS = 1
    STACK_UNDERFLOW = 2
    STACK_OVERFLOW = 3
    INVALID_OPCODE = 4
    INVALID_JUMP = 5
    REVERT = 6
    STATIC_CALL_VIOLATION = 7
    OUT_OF_MEMORY = 8
    CALL_DEPTH_EXCEEDED = 9
    INSUFFICIENT_BALANCE = 10
    INVALID_ARGUMENT = 11
    UNKNOWN_ERROR = 255

    def __str__(self) -> str:
        return self.name

# ============================================================
# Result Structure
# ============================================================

class _EVMResultStruct(Structure):
    """C structure for EVMResult."""
    _fields_ = [
        ("success", c_bool),
        ("error_code", c_int),
        ("gas_used", c_uint64),
        ("gas_remaining", c_uint64),
        ("return_data", POINTER(c_uint8)),
        ("return_data_len", c_size_t),
        ("reverted", c_bool),
    ]

@dataclass
class EVMResult:
    """Result of EVM execution."""
    success: bool
    error_code: EVMError
    gas_used: int
    gas_remaining: int
    return_data: bytes
    reverted: bool

    @classmethod
    def from_struct(cls, s: _EVMResultStruct) -> "EVMResult":
        """Create from C structure."""
        if s.return_data_len > 0 and s.return_data:
            data = bytes(s.return_data[i] for i in range(s.return_data_len))
        else:
            data = b""

        return cls(
            success=s.success,
            error_code=EVMError(s.error_code),
            gas_used=s.gas_used,
            gas_remaining=s.gas_remaining,
            return_data=data,
            reverted=s.reverted,
        )

@dataclass
class Log:
    """EVM log entry (event)."""
    address: bytes  # 20 bytes
    topics: List[bytes]  # List of 32-byte topics
    data: bytes

# ============================================================
# Function Setup
# ============================================================

def _setup_functions(lib):
    """Set up function signatures."""
    # Lifecycle
    lib.evm_create.restype = c_void_p
    lib.evm_create.argtypes = []

    lib.evm_destroy.restype = None
    lib.evm_destroy.argtypes = [c_void_p]

    lib.evm_reset.restype = None
    lib.evm_reset.argtypes = [c_void_p]

    # Configuration
    lib.evm_set_gas_limit.restype = None
    lib.evm_set_gas_limit.argtypes = [c_void_p, c_uint64]

    lib.evm_set_block_number.restype = None
    lib.evm_set_block_number.argtypes = [c_void_p, c_uint64]

    lib.evm_set_timestamp.restype = None
    lib.evm_set_timestamp.argtypes = [c_void_p, c_uint64]

    lib.evm_set_chain_id.restype = None
    lib.evm_set_chain_id.argtypes = [c_void_p, c_uint64]

    lib.evm_set_coinbase.restype = None
    lib.evm_set_coinbase.argtypes = [c_void_p, POINTER(c_uint8)]

    lib.evm_set_address.restype = None
    lib.evm_set_address.argtypes = [c_void_p, POINTER(c_uint8)]

    lib.evm_set_caller.restype = None
    lib.evm_set_caller.argtypes = [c_void_p, POINTER(c_uint8)]

    lib.evm_set_origin.restype = None
    lib.evm_set_origin.argtypes = [c_void_p, POINTER(c_uint8)]

    lib.evm_set_value.restype = None
    lib.evm_set_value.argtypes = [c_void_p, POINTER(c_uint8)]

    # Account management
    lib.evm_set_balance.restype = c_int
    lib.evm_set_balance.argtypes = [c_void_p, POINTER(c_uint8), POINTER(c_uint8)]

    lib.evm_set_code.restype = c_int
    lib.evm_set_code.argtypes = [c_void_p, POINTER(c_uint8), POINTER(c_uint8), c_size_t]

    lib.evm_set_storage.restype = c_int
    lib.evm_set_storage.argtypes = [c_void_p, POINTER(c_uint8), POINTER(c_uint8), POINTER(c_uint8)]

    lib.evm_get_storage.restype = c_int
    lib.evm_get_storage.argtypes = [c_void_p, POINTER(c_uint8), POINTER(c_uint8), POINTER(c_uint8)]

    # Execution
    lib.evm_execute.restype = _EVMResultStruct
    lib.evm_execute.argtypes = [c_void_p, POINTER(c_uint8), c_size_t, POINTER(c_uint8), c_size_t]

    # Results
    lib.evm_gas_used.restype = c_uint64
    lib.evm_gas_used.argtypes = [c_void_p]

    lib.evm_gas_remaining.restype = c_uint64
    lib.evm_gas_remaining.argtypes = [c_void_p]

    lib.evm_return_data_len.restype = c_size_t
    lib.evm_return_data_len.argtypes = [c_void_p]

    lib.evm_return_data_copy.restype = c_size_t
    lib.evm_return_data_copy.argtypes = [c_void_p, POINTER(c_uint8), c_size_t]

    # Logs
    lib.evm_logs_count.restype = c_size_t
    lib.evm_logs_count.argtypes = [c_void_p]

    lib.evm_log_address.restype = c_bool
    lib.evm_log_address.argtypes = [c_void_p, c_size_t, POINTER(c_uint8)]

    lib.evm_log_topics_count.restype = c_size_t
    lib.evm_log_topics_count.argtypes = [c_void_p, c_size_t]

    lib.evm_log_topic.restype = c_bool
    lib.evm_log_topic.argtypes = [c_void_p, c_size_t, c_size_t, POINTER(c_uint8)]

    lib.evm_log_data_len.restype = c_size_t
    lib.evm_log_data_len.argtypes = [c_void_p, c_size_t]

    lib.evm_log_data_copy.restype = c_size_t
    lib.evm_log_data_copy.argtypes = [c_void_p, c_size_t, POINTER(c_uint8), c_size_t]

    # Debugging
    lib.evm_stack_depth.restype = c_size_t
    lib.evm_stack_depth.argtypes = [c_void_p]

    lib.evm_stack_peek.restype = c_bool
    lib.evm_stack_peek.argtypes = [c_void_p, c_size_t, POINTER(c_uint8)]

    lib.evm_memory_size.restype = c_size_t
    lib.evm_memory_size.argtypes = [c_void_p]

    lib.evm_memory_copy.restype = c_size_t
    lib.evm_memory_copy.argtypes = [c_void_p, c_size_t, POINTER(c_uint8), c_size_t]

    # Version
    lib.evm_version.restype = c_char_p
    lib.evm_version.argtypes = []

# ============================================================
# Helper Functions
# ============================================================

def _to_bytes20(value: bytes) -> Tuple[POINTER(c_uint8), bytes]:
    """Convert to 20-byte array."""
    if len(value) != 20:
        raise ValueError(f"Expected 20 bytes, got {len(value)}")
    buf = (c_uint8 * 20)(*value)
    return ctypes.cast(buf, POINTER(c_uint8)), bytes(buf)

def _to_bytes32(value: bytes) -> Tuple[POINTER(c_uint8), bytes]:
    """Convert to 32-byte array."""
    if len(value) > 32:
        raise ValueError(f"Expected at most 32 bytes, got {len(value)}")
    padded = value.rjust(32, b'\x00')
    buf = (c_uint8 * 32)(*padded)
    return ctypes.cast(buf, POINTER(c_uint8)), bytes(buf)

def _int_to_bytes32(value: int) -> bytes:
    """Convert integer to 32-byte big-endian."""
    return value.to_bytes(32, 'big')

def _bytes32_to_int(value: bytes) -> int:
    """Convert 32-byte big-endian to integer."""
    return int.from_bytes(value, 'big')

# ============================================================
# EVM Class
# ============================================================

class EVM:
    """
    Ethereum Virtual Machine instance.

    Example:
        evm = EVM()
        evm.set_gas_limit(1000000)

        # Set up account
        address = bytes.fromhex("1234567890123456789012345678901234567890")
        evm.set_balance(address, 10**18)  # 1 ETH

        # Execute bytecode
        bytecode = bytes.fromhex("6001600101")  # PUSH1 1, PUSH1 1, ADD
        result = evm.execute(bytecode)

        print(f"Success: {result.success}")
        print(f"Gas used: {result.gas_used}")
    """

    def __init__(self):
        """Create a new EVM instance."""
        self._lib = _get_lib()
        self._handle = self._lib.evm_create()
        if not self._handle:
            raise MemoryError("Failed to create EVM instance")

    def __del__(self):
        """Destroy the EVM instance."""
        if hasattr(self, '_handle') and self._handle:
            self._lib.evm_destroy(self._handle)
            self._handle = None

    def reset(self) -> None:
        """Reset EVM state for new execution."""
        self._lib.evm_reset(self._handle)

    # Configuration
    def set_gas_limit(self, gas_limit: int) -> None:
        """Set gas limit for execution."""
        self._lib.evm_set_gas_limit(self._handle, gas_limit)

    def set_block_number(self, number: int) -> None:
        """Set block number."""
        self._lib.evm_set_block_number(self._handle, number)

    def set_timestamp(self, timestamp: int) -> None:
        """Set block timestamp."""
        self._lib.evm_set_timestamp(self._handle, timestamp)

    def set_chain_id(self, chain_id: int) -> None:
        """Set chain ID."""
        self._lib.evm_set_chain_id(self._handle, chain_id)

    def set_coinbase(self, address: bytes) -> None:
        """Set coinbase (block producer) address."""
        ptr, _ = _to_bytes20(address)
        self._lib.evm_set_coinbase(self._handle, ptr)

    def set_address(self, address: bytes) -> None:
        """Set current contract address."""
        ptr, _ = _to_bytes20(address)
        self._lib.evm_set_address(self._handle, ptr)

    def set_caller(self, address: bytes) -> None:
        """Set caller (msg.sender) address."""
        ptr, _ = _to_bytes20(address)
        self._lib.evm_set_caller(self._handle, ptr)

    def set_origin(self, address: bytes) -> None:
        """Set origin (tx.origin) address."""
        ptr, _ = _to_bytes20(address)
        self._lib.evm_set_origin(self._handle, ptr)

    def set_value(self, value: int) -> None:
        """Set call value (msg.value) in wei."""
        value_bytes = _int_to_bytes32(value)
        ptr, _ = _to_bytes32(value_bytes)
        self._lib.evm_set_value(self._handle, ptr)

    # Account management
    def set_balance(self, address: bytes, balance: int) -> None:
        """Set account balance in wei."""
        addr_ptr, _ = _to_bytes20(address)
        balance_bytes = _int_to_bytes32(balance)
        bal_ptr, _ = _to_bytes32(balance_bytes)
        err = self._lib.evm_set_balance(self._handle, addr_ptr, bal_ptr)
        if err != 0:
            raise RuntimeError(f"Failed to set balance: {EVMError(err)}")

    def set_code(self, address: bytes, code: bytes) -> None:
        """Set account code (contract bytecode)."""
        addr_ptr, _ = _to_bytes20(address)
        code_buf = (c_uint8 * len(code))(*code)
        code_ptr = ctypes.cast(code_buf, POINTER(c_uint8))
        err = self._lib.evm_set_code(self._handle, addr_ptr, code_ptr, len(code))
        if err != 0:
            raise RuntimeError(f"Failed to set code: {EVMError(err)}")

    def set_storage(self, address: bytes, key: bytes, value: bytes) -> None:
        """Set storage value."""
        addr_ptr, _ = _to_bytes20(address)
        key_ptr, _ = _to_bytes32(key)
        val_ptr, _ = _to_bytes32(value)
        err = self._lib.evm_set_storage(self._handle, addr_ptr, key_ptr, val_ptr)
        if err != 0:
            raise RuntimeError(f"Failed to set storage: {EVMError(err)}")

    def get_storage(self, address: bytes, key: bytes) -> bytes:
        """Get storage value."""
        addr_ptr, _ = _to_bytes20(address)
        key_ptr, _ = _to_bytes32(key)
        out = (c_uint8 * 32)()
        out_ptr = ctypes.cast(out, POINTER(c_uint8))
        err = self._lib.evm_get_storage(self._handle, addr_ptr, key_ptr, out_ptr)
        if err != 0:
            raise RuntimeError(f"Failed to get storage: {EVMError(err)}")
        return bytes(out)

    # Execution
    def execute(self, code: bytes, calldata: bytes = b"") -> EVMResult:
        """Execute EVM bytecode."""
        code_buf = (c_uint8 * len(code))(*code) if code else (c_uint8 * 0)()
        code_ptr = ctypes.cast(code_buf, POINTER(c_uint8))

        calldata_buf = (c_uint8 * len(calldata))(*calldata) if calldata else (c_uint8 * 0)()
        calldata_ptr = ctypes.cast(calldata_buf, POINTER(c_uint8))

        result = self._lib.evm_execute(
            self._handle,
            code_ptr, len(code),
            calldata_ptr, len(calldata)
        )
        return EVMResult.from_struct(result)

    # Results
    @property
    def gas_used(self) -> int:
        """Get gas used in last execution."""
        return self._lib.evm_gas_used(self._handle)

    @property
    def gas_remaining(self) -> int:
        """Get remaining gas after last execution."""
        return self._lib.evm_gas_remaining(self._handle)

    def get_return_data(self) -> bytes:
        """Get return data from last execution."""
        length = self._lib.evm_return_data_len(self._handle)
        if length == 0:
            return b""
        buf = (c_uint8 * length)()
        ptr = ctypes.cast(buf, POINTER(c_uint8))
        copied = self._lib.evm_return_data_copy(self._handle, ptr, length)
        return bytes(buf[:copied])

    # Logs
    def get_logs(self) -> List[Log]:
        """Get logs emitted during execution."""
        logs = []
        count = self._lib.evm_logs_count(self._handle)

        for i in range(count):
            # Get address
            addr_buf = (c_uint8 * 20)()
            addr_ptr = ctypes.cast(addr_buf, POINTER(c_uint8))
            self._lib.evm_log_address(self._handle, i, addr_ptr)
            address = bytes(addr_buf)

            # Get topics
            topics = []
            topic_count = self._lib.evm_log_topics_count(self._handle, i)
            for j in range(topic_count):
                topic_buf = (c_uint8 * 32)()
                topic_ptr = ctypes.cast(topic_buf, POINTER(c_uint8))
                self._lib.evm_log_topic(self._handle, i, j, topic_ptr)
                topics.append(bytes(topic_buf))

            # Get data
            data_len = self._lib.evm_log_data_len(self._handle, i)
            if data_len > 0:
                data_buf = (c_uint8 * data_len)()
                data_ptr = ctypes.cast(data_buf, POINTER(c_uint8))
                self._lib.evm_log_data_copy(self._handle, i, data_ptr, data_len)
                data = bytes(data_buf)
            else:
                data = b""

            logs.append(Log(address=address, topics=topics, data=data))

        return logs

    # Debugging
    @property
    def stack_depth(self) -> int:
        """Get current stack depth."""
        return self._lib.evm_stack_depth(self._handle)

    def stack_peek(self, index: int = 0) -> Optional[int]:
        """Peek stack value at index (0 = top)."""
        buf = (c_uint8 * 32)()
        ptr = ctypes.cast(buf, POINTER(c_uint8))
        if self._lib.evm_stack_peek(self._handle, index, ptr):
            return _bytes32_to_int(bytes(buf))
        return None

    @property
    def memory_size(self) -> int:
        """Get current memory size."""
        return self._lib.evm_memory_size(self._handle)

    def memory_read(self, offset: int, length: int) -> bytes:
        """Read memory region."""
        buf = (c_uint8 * length)()
        ptr = ctypes.cast(buf, POINTER(c_uint8))
        copied = self._lib.evm_memory_copy(self._handle, offset, ptr, length)
        return bytes(buf[:copied])

def version() -> str:
    """Get library version."""
    lib = _get_lib()
    return lib.evm_version().decode('utf-8')
