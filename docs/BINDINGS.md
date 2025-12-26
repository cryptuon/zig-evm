# Zig EVM Language Bindings

This guide covers using Zig EVM from Python, Rust, and JavaScript/Node.js.

## Python Bindings

### Installation

```bash
cd bindings/python
pip install -e .
```

Or build the library first:

```bash
zig build lib
pip install ./bindings/python
```

### Quick Start

```python
from zigevm import EVM

# Create EVM instance
evm = EVM()

# Configure
evm.set_gas_limit(1000000)
evm.set_chain_id(1)

# Set up account
address = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
evm.set_balance(address, 1000000)
evm.set_address(address)

# Execute bytecode (PUSH1 3, PUSH1 5, ADD)
code = bytes([0x60, 0x03, 0x60, 0x05, 0x01])
result = evm.execute(code)

print(f"Success: {result.success}")
print(f"Gas used: {result.gas_used}")
print(f"Return data: {result.return_data.hex()}")

# Cleanup
evm.destroy()
```

### API Reference

#### EVM Class

```python
class EVM:
    def __init__(self) -> None:
        """Create a new EVM instance."""

    def destroy(self) -> None:
        """Destroy EVM and free resources."""

    def reset(self) -> None:
        """Reset execution state (keeps accounts)."""

    # Configuration
    def set_gas_limit(self, gas: int) -> None: ...
    def set_block_number(self, number: int) -> None: ...
    def set_timestamp(self, timestamp: int) -> None: ...
    def set_chain_id(self, chain_id: int) -> None: ...
    def set_coinbase(self, address: str | bytes) -> None: ...
    def set_address(self, address: str | bytes) -> None: ...
    def set_caller(self, address: str | bytes) -> None: ...
    def set_origin(self, address: str | bytes) -> None: ...
    def set_value(self, value: int | bytes) -> None: ...

    # Account management
    def set_balance(self, address: str | bytes, balance: int | bytes) -> None: ...
    def set_code(self, address: str | bytes, code: bytes) -> None: ...
    def set_storage(self, address: str | bytes, key: int | bytes, value: int | bytes) -> None: ...
    def get_storage(self, address: str | bytes, key: int | bytes) -> bytes: ...

    # Execution
    def execute(self, code: bytes, calldata: bytes = b"") -> EVMResult: ...

    # Results
    @property
    def gas_used(self) -> int: ...
    @property
    def gas_remaining(self) -> int: ...
    def get_return_data(self) -> bytes: ...
    def get_logs(self) -> list[Log]: ...

    # Debugging
    @property
    def stack_depth(self) -> int: ...
    def stack_peek(self, index: int = 0) -> bytes | None: ...
    @property
    def memory_size(self) -> int: ...
    def memory_read(self, offset: int, length: int) -> bytes: ...
```

#### EVMResult

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

#### Log

```python
@dataclass
class Log:
    address: bytes
    topics: list[bytes]
    data: bytes
```

### Advanced Usage

#### Contract Deployment

```python
from zigevm import EVM

evm = EVM()
evm.set_gas_limit(3000000)

# Deploy bytecode (simplified example)
# Constructor code that returns runtime code
deploy_code = bytes.fromhex("6080604052...")

result = evm.execute(deploy_code)
if result.success:
    runtime_code = result.return_data
    contract_address = "0x1234..."
    evm.set_code(contract_address, runtime_code)
```

#### Storage Operations

```python
# Set storage
evm.set_storage(
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    0,  # slot 0
    42  # value
)

# Get storage
value = evm.get_storage(
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    0
)
print(int.from_bytes(value, "big"))  # 42
```

#### Reading Logs

```python
# Execute code that emits logs
code = bytes.fromhex("...")  # LOG1 opcode etc.
result = evm.execute(code)

for log in evm.get_logs():
    print(f"Address: {log.address.hex()}")
    print(f"Topics: {[t.hex() for t in log.topics]}")
    print(f"Data: {log.data.hex()}")
```

---

## Rust Bindings

### Installation

Add to `Cargo.toml`:

```toml
[dependencies]
zigevm = { path = "path/to/bindings/rust/zigevm" }
```

Or build from source:

```bash
cd bindings/rust/zigevm
cargo build --release
```

### Quick Start

```rust
use zigevm::{Evm, EvmError};

fn main() -> Result<(), EvmError> {
    // Create EVM
    let mut evm = Evm::new()?;

    // Configure
    evm.set_gas_limit(1_000_000);
    evm.set_chain_id(1);

    // Set up account
    let address = [0xaa; 20];
    evm.set_balance(&address, 1_000_000u64)?;
    evm.set_address(&address);

    // Execute (PUSH1 3, PUSH1 5, ADD)
    let code = vec![0x60, 0x03, 0x60, 0x05, 0x01];
    let result = evm.execute(&code, &[])?;

    println!("Success: {}", result.success);
    println!("Gas used: {}", result.gas_used);
    println!("Return data: {:?}", result.return_data);

    Ok(())
}
```

### API Reference

#### Evm

```rust
pub struct Evm { /* private */ }

impl Evm {
    /// Create a new EVM instance
    pub fn new() -> Result<Self, EvmError>;

    /// Reset execution state
    pub fn reset(&mut self);

    // Configuration
    pub fn set_gas_limit(&mut self, gas: u64);
    pub fn set_block_number(&mut self, number: u64);
    pub fn set_timestamp(&mut self, timestamp: u64);
    pub fn set_chain_id(&mut self, chain_id: u64);
    pub fn set_coinbase(&mut self, addr: &[u8; 20]);
    pub fn set_address(&mut self, addr: &[u8; 20]);
    pub fn set_caller(&mut self, addr: &[u8; 20]);
    pub fn set_origin(&mut self, addr: &[u8; 20]);
    pub fn set_value(&mut self, value: &[u8; 32]);

    // Account management
    pub fn set_balance(&mut self, addr: &[u8; 20], balance: impl Into<U256>)
        -> Result<(), EvmError>;
    pub fn set_code(&mut self, addr: &[u8; 20], code: &[u8])
        -> Result<(), EvmError>;
    pub fn set_storage(&mut self, addr: &[u8; 20], key: &[u8; 32], value: &[u8; 32])
        -> Result<(), EvmError>;
    pub fn get_storage(&self, addr: &[u8; 20], key: &[u8; 32])
        -> Result<[u8; 32], EvmError>;

    // Execution
    pub fn execute(&mut self, code: &[u8], calldata: &[u8])
        -> Result<EvmResult, EvmError>;

    // Results
    pub fn gas_used(&self) -> u64;
    pub fn gas_remaining(&self) -> u64;
    pub fn return_data(&self) -> Vec<u8>;
    pub fn logs(&self) -> Vec<Log>;

    // Debugging
    pub fn stack_depth(&self) -> usize;
    pub fn stack_peek(&self, index: usize) -> Option<[u8; 32]>;
    pub fn memory_size(&self) -> usize;
    pub fn memory_read(&self, offset: usize, length: usize) -> Vec<u8>;
}
```

#### EvmResult

```rust
pub struct EvmResult {
    pub success: bool,
    pub error_code: EvmError,
    pub gas_used: u64,
    pub gas_remaining: u64,
    pub return_data: Vec<u8>,
    pub reverted: bool,
}
```

#### EvmError

```rust
#[repr(u8)]
pub enum EvmError {
    Ok = 0,
    OutOfGas = 1,
    StackUnderflow = 2,
    StackOverflow = 3,
    InvalidOpcode = 4,
    InvalidJump = 5,
    Revert = 6,
    StaticCallViolation = 7,
    OutOfMemory = 8,
    CallDepthExceeded = 9,
    InsufficientBalance = 10,
    InvalidArgument = 11,
    UnknownError = 255,
}
```

### Advanced Usage

#### Using with ethers-rs

```rust
use ethers::types::{Address, U256, Bytes};
use zigevm::Evm;

fn execute_call(
    evm: &mut Evm,
    to: Address,
    calldata: Bytes,
) -> Result<Bytes, Box<dyn std::error::Error>> {
    // Get contract code
    let code = get_contract_code(to)?;

    // Set context
    evm.set_address(&to.0);

    // Execute
    let result = evm.execute(&code, &calldata)?;

    if result.success {
        Ok(Bytes::from(result.return_data))
    } else {
        Err("Execution failed".into())
    }
}
```

---

## JavaScript/Node.js Bindings

### Installation

```bash
cd bindings/js
npm install
npm run build
```

Or from npm (when published):

```bash
npm install zigevm
```

### Quick Start

```javascript
const { EVM } = require('zigevm');

// Create EVM
const evm = new EVM();

// Configure
evm.setGasLimit(1000000n);
evm.setChainId(1n);

// Set up account
const address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
evm.setBalance(address, 1000000n);
evm.setAddress(address);

// Execute (PUSH1 3, PUSH1 5, ADD)
const code = Buffer.from([0x60, 0x03, 0x60, 0x05, 0x01]);
const result = evm.execute(code);

console.log('Success:', result.success);
console.log('Gas used:', result.gasUsed);
console.log('Return data:', result.returnData.toString('hex'));

// Cleanup
evm.destroy();
```

### TypeScript Support

TypeScript definitions are included:

```typescript
import { EVM, EVMResult, Log, EVMError } from 'zigevm';

const evm = new EVM();

// Full type support
const result: EVMResult = evm.execute(code, calldata);
const logs: Log[] = evm.getLogs();
```

### API Reference

#### EVM Class

```typescript
class EVM {
    constructor();
    destroy(): void;
    reset(): void;

    // Configuration
    setGasLimit(gasLimit: number | bigint): void;
    setBlockNumber(number: number | bigint): void;
    setTimestamp(timestamp: number | bigint): void;
    setChainId(chainId: number | bigint): void;
    setCoinbase(address: string | Buffer): void;
    setAddress(address: string | Buffer): void;
    setCaller(address: string | Buffer): void;
    setOrigin(address: string | Buffer): void;
    setValue(value: number | bigint | string | Buffer): void;

    // Account management
    setBalance(address: string | Buffer, balance: number | bigint | string | Buffer): void;
    setCode(address: string | Buffer, code: Buffer | string): void;
    setStorage(address: string | Buffer, key: number | bigint | string | Buffer,
               value: number | bigint | string | Buffer): void;
    getStorage(address: string | Buffer, key: number | bigint | string | Buffer): Buffer;

    // Execution
    execute(code: Buffer | string, calldata?: Buffer | string): EVMResult;

    // Results
    readonly gasUsed: bigint;
    readonly gasRemaining: bigint;
    getReturnData(): Buffer;
    getLogs(): Log[];

    // Debugging
    readonly stackDepth: number;
    stackPeek(index?: number): Buffer | null;
    readonly memorySize: number;
    memoryRead(offset: number, length: number): Buffer;
}
```

#### EVMResult

```typescript
interface EVMResult {
    success: boolean;
    errorCode: number;
    errorName: string;
    gasUsed: bigint;
    gasRemaining: bigint;
    returnData: Buffer;
    reverted: boolean;
}
```

#### Log

```typescript
interface Log {
    address: Buffer;
    topics: Buffer[];
    data: Buffer;
}
```

### Advanced Usage

#### With ethers.js

```javascript
const { ethers } = require('ethers');
const { EVM } = require('zigevm');

async function simulateCall(contractAddress, calldata) {
    const evm = new EVM();
    evm.setGasLimit(3000000n);

    // Set up the contract
    const code = await provider.getCode(contractAddress);
    evm.setCode(contractAddress, code);
    evm.setAddress(contractAddress);

    // Execute
    const result = evm.execute(
        Buffer.from(code.slice(2), 'hex'),
        Buffer.from(calldata.slice(2), 'hex')
    );

    evm.destroy();
    return result;
}
```

#### Async Execution (Future)

```javascript
const { EVM } = require('zigevm');

// Batch execution (parallel)
async function executeBatch(transactions) {
    const evm = new EVM();

    const results = await Promise.all(
        transactions.map(tx => evm.executeAsync(tx.code, tx.calldata))
    );

    evm.destroy();
    return results;
}
```

---

## Common Patterns

### Address Formats

All bindings accept addresses in multiple formats:

```python
# Python
evm.set_address("0xaaaa...")           # Hex string with 0x
evm.set_address("aaaa...")             # Hex string without 0x
evm.set_address(bytes.fromhex("aa..")) # bytes
```

```rust
// Rust
evm.set_address(&[0xaa; 20]);          // [u8; 20] array
```

```javascript
// JavaScript
evm.setAddress('0xaaaa...');           // Hex string
evm.setAddress(Buffer.from([0xaa...])); // Buffer
```

### Value Formats

Values (balance, storage) can be specified as:

```python
# Python
evm.set_balance(addr, 1000000)         # int
evm.set_balance(addr, 0x1000)          # hex int
evm.set_balance(addr, b'\x00...')      # 32-byte bytes
```

```rust
// Rust
evm.set_balance(&addr, 1_000_000u64)?; // Into<U256>
evm.set_balance(&addr, [0u8; 32])?;    // [u8; 32]
```

```javascript
// JavaScript
evm.setBalance(addr, 1000000);         // number
evm.setBalance(addr, 1000000n);        // bigint
evm.setBalance(addr, '0x1000');        // hex string
evm.setBalance(addr, Buffer.alloc(32)); // Buffer
```

### Error Handling

```python
# Python
try:
    result = evm.execute(code)
    if not result.success:
        print(f"EVM error: {result.error_name}")
except Exception as e:
    print(f"FFI error: {e}")
```

```rust
// Rust
match evm.execute(&code, &[]) {
    Ok(result) => {
        if !result.success {
            eprintln!("EVM error: {:?}", result.error_code);
        }
    }
    Err(e) => eprintln!("FFI error: {:?}", e),
}
```

```javascript
// JavaScript
try {
    const result = evm.execute(code);
    if (!result.success) {
        console.error(`EVM error: ${result.errorName}`);
    }
} catch (e) {
    console.error(`FFI error: ${e.message}`);
}
```
