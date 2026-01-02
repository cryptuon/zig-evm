# Python API Reference

Complete API reference for the Python bindings.

## Installation

```bash
cd bindings/python
pip install -e .
```

Or after building the library:

```bash
zig build lib
pip install ./bindings/python
```

## EVM Class

```python
from zigevm import EVM
```

### Constructor

```python
evm = EVM()
```

Create a new EVM instance.

### Methods

#### destroy

```python
def destroy(self) -> None
```

Destroy EVM and free resources.

!!! warning
    Always call `destroy()` when done to prevent memory leaks.

---

#### reset

```python
def reset(self) -> None
```

Reset execution state (keeps accounts).

---

#### set_gas_limit

```python
def set_gas_limit(self, gas: int) -> None
```

Set the maximum gas for execution.

---

#### set_block_number

```python
def set_block_number(self, number: int) -> None
```

Set the current block number.

---

#### set_timestamp

```python
def set_timestamp(self, timestamp: int) -> None
```

Set the block timestamp.

---

#### set_chain_id

```python
def set_chain_id(self, chain_id: int) -> None
```

Set the chain ID.

---

#### set_coinbase

```python
def set_coinbase(self, address: str | bytes) -> None
```

Set the coinbase address.

---

#### set_address

```python
def set_address(self, address: str | bytes) -> None
```

Set the current contract address.

---

#### set_caller

```python
def set_caller(self, address: str | bytes) -> None
```

Set the caller address (msg.sender).

---

#### set_origin

```python
def set_origin(self, address: str | bytes) -> None
```

Set the transaction origin (tx.origin).

---

#### set_value

```python
def set_value(self, value: int | bytes) -> None
```

Set the call value in wei.

---

#### set_balance

```python
def set_balance(self, address: str | bytes, balance: int | bytes) -> None
```

Set an account's balance.

**Parameters**:
- `address`: Account address (hex string or bytes)
- `balance`: Balance in wei

---

#### set_code

```python
def set_code(self, address: str | bytes, code: bytes) -> None
```

Set an account's bytecode.

---

#### set_storage

```python
def set_storage(self, address: str | bytes, key: int | bytes, value: int | bytes) -> None
```

Set a storage slot value.

---

#### get_storage

```python
def get_storage(self, address: str | bytes, key: int | bytes) -> bytes
```

Get a storage slot value.

**Returns**: 32-byte value

---

#### execute

```python
def execute(self, code: bytes, calldata: bytes = b"") -> EVMResult
```

Execute EVM bytecode.

**Parameters**:
- `code`: EVM bytecode
- `calldata`: Optional input data

**Returns**: `EVMResult` with execution results

---

#### get_return_data

```python
def get_return_data(self) -> bytes
```

Get return data from last execution.

---

#### get_logs

```python
def get_logs(self) -> list[Log]
```

Get logs emitted during execution.

### Properties

#### gas_used

```python
@property
def gas_used(self) -> int
```

Gas used in last execution.

---

#### gas_remaining

```python
@property
def gas_remaining(self) -> int
```

Gas remaining after last execution.

---

#### stack_depth

```python
@property
def stack_depth(self) -> int
```

Current stack depth.

---

#### memory_size

```python
@property
def memory_size(self) -> int
```

Current memory size in bytes.

### Debugging Methods

#### stack_peek

```python
def stack_peek(self, index: int = 0) -> bytes | None
```

Peek at stack value without removing.

**Parameters**:
- `index`: Stack index (0 = top)

**Returns**: 32-byte value or `None`

---

#### memory_read

```python
def memory_read(self, offset: int, length: int) -> bytes
```

Read bytes from memory.

## EVMResult

```python
@dataclass
class EVMResult:
    success: bool
    error_code: int
    error_name: str
    gas_used: int
    gas_remaining: int
    return_data: bytes
    reverted: bool
```

| Field | Type | Description |
|-------|------|-------------|
| `success` | `bool` | Whether execution succeeded |
| `error_code` | `int` | Error code (0 = success) |
| `error_name` | `str` | Human-readable error name |
| `gas_used` | `int` | Gas consumed |
| `gas_remaining` | `int` | Gas remaining |
| `return_data` | `bytes` | Data from RETURN opcode |
| `reverted` | `bool` | Whether REVERT was called |

## Log

```python
@dataclass
class Log:
    address: bytes
    topics: list[bytes]
    data: bytes
```

| Field | Type | Description |
|-------|------|-------------|
| `address` | `bytes` | 20-byte contract address |
| `topics` | `list[bytes]` | 0-4 topics (32 bytes each) |
| `data` | `bytes` | Log data |

## BatchExecutor

For parallel transaction execution.

```python
from zigevm import BatchExecutor, BatchConfig, BatchTransaction
```

### BatchConfig

```python
@dataclass
class BatchConfig:
    max_threads: int = 8
    enable_parallel: bool = True
    enable_speculation: bool = False
    chain_id: int = 1
    block_number: int = 0
    block_timestamp: int = 0
    block_gas_limit: int = 30000000
    coinbase: str | bytes = None
```

### BatchTransaction

```python
@dataclass
class BatchTransaction:
    from_addr: str | bytes
    to_addr: str | bytes = None
    value: int | bytes = 0
    data: bytes = b""
    gas_limit: int = 21000
    gas_price: int | bytes = 0
    nonce: int = None
```

### BatchStats

```python
@dataclass
class BatchStats:
    total_transactions: int
    successful_transactions: int
    failed_transactions: int
    reverted_transactions: int
    total_gas_used: int
    execution_time_ns: int
    parallel_waves: int
    max_parallelism: int
```

### Methods

#### Constructor

```python
executor = BatchExecutor(config: BatchConfig)
```

---

#### set_account

```python
def set_account(self, address: str | bytes, balance: int = 0,
                nonce: int = 0, code: bytes = None) -> None
```

Set account state.

---

#### set_storage

```python
def set_storage(self, address: str | bytes,
                key: int | bytes, value: int | bytes) -> None
```

Set storage slot.

---

#### execute

```python
def execute(self, transactions: list[BatchTransaction]) -> BatchStats
```

Execute transactions in parallel.

---

#### get_results

```python
def get_results(self) -> list[BatchResult]
```

Get individual transaction results.

## Examples

### Basic Execution

```python
from zigevm import EVM

evm = EVM()
evm.set_gas_limit(100000)

# PUSH1 3, PUSH1 5, ADD, STOP
code = bytes([0x60, 0x03, 0x60, 0x05, 0x01, 0x00])

result = evm.execute(code)

print(f"Success: {result.success}")
print(f"Gas used: {result.gas_used}")

evm.destroy()
```

### Working with Storage

```python
from zigevm import EVM

evm = EVM()
evm.set_gas_limit(100000)

address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
evm.set_address(address)

# Set storage
evm.set_storage(address, 0, 42)

# SLOAD slot 0
code = bytes([0x60, 0x00, 0x54, 0x00])
result = evm.execute(code)

# Check stack
value = evm.stack_peek(0)
print(f"Value: {int.from_bytes(value, 'big')}")  # 42

evm.destroy()
```

### Reading Logs

```python
from zigevm import EVM

evm = EVM()
evm.set_gas_limit(100000)

# Execute code that emits logs
result = evm.execute(code)

for log in evm.get_logs():
    print(f"Address: 0x{log.address.hex()}")
    for i, topic in enumerate(log.topics):
        print(f"  Topic {i}: 0x{topic.hex()}")
    print(f"  Data: 0x{log.data.hex()}")

evm.destroy()
```

### Parallel Execution

```python
from zigevm import BatchExecutor, BatchConfig, BatchTransaction

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
    )

# Create transactions
transactions = [
    BatchTransaction(
        from_addr=f"0x{'%040x' % (i % 10)}",
        to_addr=f"0x{'%040x' % ((i + 1) % 10)}",
        value=1 * 10**18,
        gas_limit=21000,
    )
    for i in range(1000)
]

# Execute
stats = executor.execute(transactions)

print(f"Transactions: {stats.total_transactions}")
print(f"Parallel waves: {stats.parallel_waves}")
print(f"Speedup: {stats.max_parallelism}x")

# Check results
for result in executor.get_results():
    if not result.success:
        print(f"Tx {result.tx_index} failed: {result.error_code}")
```

## Error Handling

```python
from zigevm import EVM

evm = EVM()
evm.set_gas_limit(100)  # Very low gas

try:
    result = evm.execute(expensive_code)

    if not result.success:
        if result.error_code == 1:  # OutOfGas
            print("Increase gas limit")
        elif result.reverted:
            print(f"Reverted: {result.return_data}")
        else:
            print(f"Error: {result.error_name}")
except Exception as e:
    print(f"FFI error: {e}")
finally:
    evm.destroy()
```

## Address Formats

Addresses can be specified in multiple formats:

```python
# Hex string with 0x prefix
evm.set_address("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")

# Hex string without 0x
evm.set_address("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")

# bytes
evm.set_address(bytes.fromhex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
```

## Value Formats

Values can be specified as:

```python
# Integer
evm.set_balance(addr, 1000000)

# Hex integer
evm.set_balance(addr, 0x1000)

# 32-byte bytes (big-endian)
evm.set_balance(addr, b'\x00' * 31 + b'\x64')
```
