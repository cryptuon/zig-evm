# Rust API Reference

Complete API reference for the Rust bindings.

## Installation

Add to `Cargo.toml`:

```toml
[dependencies]
zigevm = { path = "path/to/zig-evm/bindings/rust/zigevm" }
```

Or build from source:

```bash
cd bindings/rust/zigevm
cargo build --release
```

## Evm Struct

```rust
use zigevm::{Evm, EvmError, EvmResult};
```

### Constructor

```rust
impl Evm {
    pub fn new() -> Result<Self, EvmError>
}
```

Create a new EVM instance.

**Returns**: `Result<Evm, EvmError>`

### Methods

#### reset

```rust
pub fn reset(&mut self)
```

Reset execution state (keeps accounts).

---

#### set_gas_limit

```rust
pub fn set_gas_limit(&mut self, gas: u64)
```

Set maximum gas for execution.

---

#### set_block_number

```rust
pub fn set_block_number(&mut self, number: u64)
```

Set current block number.

---

#### set_timestamp

```rust
pub fn set_timestamp(&mut self, timestamp: u64)
```

Set block timestamp.

---

#### set_chain_id

```rust
pub fn set_chain_id(&mut self, chain_id: u64)
```

Set chain ID.

---

#### set_coinbase

```rust
pub fn set_coinbase(&mut self, addr: &[u8; 20])
```

Set coinbase address.

---

#### set_address

```rust
pub fn set_address(&mut self, addr: &[u8; 20])
```

Set current contract address.

---

#### set_caller

```rust
pub fn set_caller(&mut self, addr: &[u8; 20])
```

Set caller address (msg.sender).

---

#### set_origin

```rust
pub fn set_origin(&mut self, addr: &[u8; 20])
```

Set transaction origin (tx.origin).

---

#### set_value

```rust
pub fn set_value(&mut self, value: &[u8; 32])
```

Set call value (big-endian).

---

#### set_balance

```rust
pub fn set_balance(&mut self, addr: &[u8; 20], balance: impl Into<U256>)
    -> Result<(), EvmError>
```

Set account balance.

---

#### set_code

```rust
pub fn set_code(&mut self, addr: &[u8; 20], code: &[u8])
    -> Result<(), EvmError>
```

Set account bytecode.

---

#### set_storage

```rust
pub fn set_storage(&mut self, addr: &[u8; 20], key: &[u8; 32], value: &[u8; 32])
    -> Result<(), EvmError>
```

Set storage slot.

---

#### get_storage

```rust
pub fn get_storage(&self, addr: &[u8; 20], key: &[u8; 32])
    -> Result<[u8; 32], EvmError>
```

Get storage slot value.

---

#### execute

```rust
pub fn execute(&mut self, code: &[u8], calldata: &[u8])
    -> Result<EvmResult, EvmError>
```

Execute bytecode.

---

#### gas_used

```rust
pub fn gas_used(&self) -> u64
```

Get gas used in last execution.

---

#### gas_remaining

```rust
pub fn gas_remaining(&self) -> u64
```

Get remaining gas.

---

#### return_data

```rust
pub fn return_data(&self) -> Vec<u8>
```

Get return data.

---

#### logs

```rust
pub fn logs(&self) -> Vec<Log>
```

Get emitted logs.

---

#### stack_depth

```rust
pub fn stack_depth(&self) -> usize
```

Get stack depth.

---

#### stack_peek

```rust
pub fn stack_peek(&self, index: usize) -> Option<[u8; 32]>
```

Peek at stack value.

---

#### memory_size

```rust
pub fn memory_size(&self) -> usize
```

Get memory size.

---

#### memory_read

```rust
pub fn memory_read(&self, offset: usize, length: usize) -> Vec<u8>
```

Read memory region.

## EvmResult

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

## EvmError

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

## Log

```rust
pub struct Log {
    pub address: [u8; 20],
    pub topics: Vec<[u8; 32]>,
    pub data: Vec<u8>,
}
```

## Examples

### Basic Execution

```rust
use zigevm::{Evm, EvmError};

fn main() -> Result<(), EvmError> {
    let mut evm = Evm::new()?;

    evm.set_gas_limit(100_000);

    // PUSH1 3, PUSH1 5, ADD, STOP
    let code = vec![0x60, 0x03, 0x60, 0x05, 0x01, 0x00];
    let result = evm.execute(&code, &[])?;

    println!("Success: {}", result.success);
    println!("Gas used: {}", result.gas_used);

    Ok(())
}
```

### Working with Accounts

```rust
use zigevm::Evm;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut evm = Evm::new()?;

    // Set up account
    let address = [0xaa; 20];
    evm.set_balance(&address, 1_000_000_000_000_000_000u64)?;  // 1 ETH
    evm.set_address(&address);

    // Set storage
    let key = [0u8; 32];
    let mut value = [0u8; 32];
    value[31] = 42;  // Store 42
    evm.set_storage(&address, &key, &value)?;

    // SLOAD slot 0
    let code = vec![0x60, 0x00, 0x54, 0x00];
    let result = evm.execute(&code, &[])?;

    // Peek at stack
    if let Some(stack_value) = evm.stack_peek(0) {
        println!("Value: {}", stack_value[31]);  // 42
    }

    Ok(())
}
```

### With ethers-rs

```rust
use ethers::types::{Address, U256, Bytes};
use zigevm::Evm;

async fn simulate_call(
    evm: &mut Evm,
    to: Address,
    calldata: Bytes,
) -> Result<Bytes, Box<dyn std::error::Error>> {
    // Get contract code
    let code = get_contract_code(to).await?;

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

### Error Handling

```rust
use zigevm::{Evm, EvmError};

fn main() {
    let mut evm = match Evm::new() {
        Ok(evm) => evm,
        Err(e) => {
            eprintln!("Failed to create EVM: {:?}", e);
            return;
        }
    };

    evm.set_gas_limit(100);  // Very low

    let code = vec![/* expensive operations */];

    match evm.execute(&code, &[]) {
        Ok(result) => {
            if result.success {
                println!("Success!");
            } else if result.reverted {
                println!("Reverted: {:?}", result.return_data);
            } else {
                match result.error_code {
                    EvmError::OutOfGas => println!("Out of gas"),
                    EvmError::StackUnderflow => println!("Stack underflow"),
                    _ => println!("Error: {:?}", result.error_code),
                }
            }
        }
        Err(e) => eprintln!("FFI error: {:?}", e),
    }
}
```

### Reading Logs

```rust
use zigevm::Evm;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut evm = Evm::new()?;
    evm.set_gas_limit(1_000_000);

    let code = vec![/* code that emits logs */];
    let result = evm.execute(&code, &[])?;

    for log in evm.logs() {
        println!("Address: 0x{}", hex::encode(log.address));
        for (i, topic) in log.topics.iter().enumerate() {
            println!("  Topic {}: 0x{}", i, hex::encode(topic));
        }
        println!("  Data: 0x{}", hex::encode(&log.data));
    }

    Ok(())
}
```

## Type Conversions

### Address

```rust
// From [u8; 20]
let addr: [u8; 20] = [0xaa; 20];
evm.set_address(&addr);

// From ethers Address
let addr: ethers::types::Address = "0xaaaa...".parse()?;
evm.set_address(&addr.0);
```

### Values

```rust
// From u64
evm.set_balance(&addr, 1_000_000u64)?;

// From [u8; 32] (big-endian)
let mut balance = [0u8; 32];
balance[31] = 100;
evm.set_balance(&addr, balance)?;

// From ethers U256
let balance: U256 = U256::from(1_000_000);
let mut bytes = [0u8; 32];
balance.to_big_endian(&mut bytes);
evm.set_balance(&addr, bytes)?;
```

## Cargo Features

```toml
[dependencies]
zigevm = { path = "...", features = ["ethers"] }
```

| Feature | Description |
|---------|-------------|
| `default` | Base functionality |
| `ethers` | ethers-rs type conversions |
| `serde` | Serialization support |
