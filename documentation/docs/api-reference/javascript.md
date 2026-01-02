# JavaScript API Reference

Complete API reference for the Node.js bindings.

## Installation

```bash
cd bindings/js
npm install
npm run build
```

Or when published to npm:

```bash
npm install zigevm
```

## EVM Class

```javascript
const { EVM } = require('zigevm');
```

### Constructor

```javascript
const evm = new EVM();
```

Create a new EVM instance.

### Methods

#### destroy

```typescript
destroy(): void
```

Destroy EVM and free resources.

!!! warning
    Always call `destroy()` when done to prevent memory leaks.

---

#### reset

```typescript
reset(): void
```

Reset execution state (keeps accounts).

---

#### setGasLimit

```typescript
setGasLimit(gasLimit: number | bigint): void
```

Set maximum gas for execution.

---

#### setBlockNumber

```typescript
setBlockNumber(number: number | bigint): void
```

Set current block number.

---

#### setTimestamp

```typescript
setTimestamp(timestamp: number | bigint): void
```

Set block timestamp.

---

#### setChainId

```typescript
setChainId(chainId: number | bigint): void
```

Set chain ID.

---

#### setCoinbase

```typescript
setCoinbase(address: string | Buffer): void
```

Set coinbase address.

---

#### setAddress

```typescript
setAddress(address: string | Buffer): void
```

Set current contract address.

---

#### setCaller

```typescript
setCaller(address: string | Buffer): void
```

Set caller address (msg.sender).

---

#### setOrigin

```typescript
setOrigin(address: string | Buffer): void
```

Set transaction origin (tx.origin).

---

#### setValue

```typescript
setValue(value: number | bigint | string | Buffer): void
```

Set call value in wei.

---

#### setBalance

```typescript
setBalance(address: string | Buffer,
           balance: number | bigint | string | Buffer): void
```

Set account balance.

---

#### setCode

```typescript
setCode(address: string | Buffer, code: Buffer | string): void
```

Set account bytecode.

---

#### setStorage

```typescript
setStorage(address: string | Buffer,
           key: number | bigint | string | Buffer,
           value: number | bigint | string | Buffer): void
```

Set storage slot.

---

#### getStorage

```typescript
getStorage(address: string | Buffer,
           key: number | bigint | string | Buffer): Buffer
```

Get storage slot value.

**Returns**: 32-byte Buffer

---

#### execute

```typescript
execute(code: Buffer | string, calldata?: Buffer | string): EVMResult
```

Execute bytecode.

**Parameters**:
- `code`: EVM bytecode
- `calldata`: Optional input data

**Returns**: `EVMResult`

---

#### getReturnData

```typescript
getReturnData(): Buffer
```

Get return data from last execution.

---

#### getLogs

```typescript
getLogs(): Log[]
```

Get logs emitted during execution.

### Properties

#### gasUsed

```typescript
readonly gasUsed: bigint
```

Gas used in last execution.

---

#### gasRemaining

```typescript
readonly gasRemaining: bigint
```

Gas remaining after execution.

---

#### stackDepth

```typescript
readonly stackDepth: number
```

Current stack depth.

---

#### memorySize

```typescript
readonly memorySize: number
```

Current memory size in bytes.

### Debugging Methods

#### stackPeek

```typescript
stackPeek(index?: number): Buffer | null
```

Peek at stack value.

**Parameters**:
- `index`: Stack index (0 = top, default)

**Returns**: 32-byte Buffer or `null`

---

#### memoryRead

```typescript
memoryRead(offset: number, length: number): Buffer
```

Read memory region.

## EVMResult

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

| Field | Type | Description |
|-------|------|-------------|
| `success` | `boolean` | Whether execution succeeded |
| `errorCode` | `number` | Error code (0 = success) |
| `errorName` | `string` | Human-readable error name |
| `gasUsed` | `bigint` | Gas consumed |
| `gasRemaining` | `bigint` | Gas remaining |
| `returnData` | `Buffer` | Data from RETURN opcode |
| `reverted` | `boolean` | Whether REVERT was called |

## Log

```typescript
interface Log {
    address: Buffer;
    topics: Buffer[];
    data: Buffer;
}
```

| Field | Type | Description |
|-------|------|-------------|
| `address` | `Buffer` | 20-byte contract address |
| `topics` | `Buffer[]` | 0-4 topics (32 bytes each) |
| `data` | `Buffer` | Log data |

## BatchExecutor

For parallel transaction execution.

```javascript
const { BatchExecutor } = require('zigevm');
```

### Constructor

```typescript
interface BatchExecutorConfig {
    maxThreads?: number;
    enableParallel?: boolean;
    enableSpeculation?: boolean;
    chainId?: bigint;
    blockNumber?: bigint;
    blockTimestamp?: bigint;
    blockGasLimit?: bigint;
    coinbase?: string | Buffer;
}

const executor = new BatchExecutor(config: BatchExecutorConfig);
```

### Methods

#### setAccount

```typescript
setAccount(options: {
    address: string | Buffer;
    balance?: bigint;
    nonce?: number;
    code?: Buffer;
}): void
```

Set account state.

---

#### setStorage

```typescript
setStorage(address: string | Buffer,
           key: number | bigint | string | Buffer,
           value: number | bigint | string | Buffer): void
```

Set storage slot.

---

#### execute

```typescript
execute(transactions: BatchTransaction[]): Promise<BatchStats>
```

Execute transactions in parallel.

---

#### getResults

```typescript
getResults(): BatchResult[]
```

Get individual transaction results.

### BatchTransaction

```typescript
interface BatchTransaction {
    from: string | Buffer;
    to?: string | Buffer;
    value?: bigint;
    data?: Buffer;
    gasLimit?: bigint;
    gasPrice?: bigint;
    nonce?: number;
}
```

### BatchStats

```typescript
interface BatchStats {
    totalTransactions: number;
    successfulTransactions: number;
    failedTransactions: number;
    revertedTransactions: number;
    totalGasUsed: bigint;
    executionTimeNs: bigint;
    parallelWaves: number;
    maxParallelism: number;
}
```

### BatchResult

```typescript
interface BatchResult {
    txIndex: number;
    success: boolean;
    reverted: boolean;
    gasUsed: bigint;
    returnData: Buffer;
    errorCode: number;
    logsCount: number;
    createdAddress?: Buffer;
}
```

## Examples

### Basic Execution

```javascript
const { EVM } = require('zigevm');

const evm = new EVM();
evm.setGasLimit(100000n);

// PUSH1 3, PUSH1 5, ADD, STOP
const code = Buffer.from([0x60, 0x03, 0x60, 0x05, 0x01, 0x00]);
const result = evm.execute(code);

console.log(`Success: ${result.success}`);
console.log(`Gas used: ${result.gasUsed}`);

evm.destroy();
```

### Working with Storage

```javascript
const { EVM } = require('zigevm');

const evm = new EVM();
evm.setGasLimit(100000n);

const address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
evm.setAddress(address);

// Set storage
evm.setStorage(address, 0, 42);

// SLOAD slot 0
const code = Buffer.from([0x60, 0x00, 0x54, 0x00]);
const result = evm.execute(code);

// Check stack
const value = evm.stackPeek(0);
console.log(`Value: ${value.readBigUInt64BE(24)}`);  // 42

evm.destroy();
```

### Reading Logs

```javascript
const { EVM } = require('zigevm');

const evm = new EVM();
evm.setGasLimit(100000n);

const result = evm.execute(code);

for (const log of evm.getLogs()) {
    console.log(`Address: 0x${log.address.toString('hex')}`);
    log.topics.forEach((topic, i) => {
        console.log(`  Topic ${i}: 0x${topic.toString('hex')}`);
    });
    console.log(`  Data: 0x${log.data.toString('hex')}`);
}

evm.destroy();
```

### Parallel Execution

```javascript
const { BatchExecutor } = require('zigevm');

const executor = new BatchExecutor({
    maxThreads: 8,
    enableParallel: true,
    chainId: 1n,
    blockNumber: 12345678n,
});

// Set up accounts
for (let i = 0; i < 10; i++) {
    executor.setAccount({
        address: `0x${'00'.repeat(19)}${i.toString(16).padStart(2, '0')}`,
        balance: 100n * 10n**18n,
    });
}

// Create transactions
const transactions = Array(1000).fill(null).map((_, i) => ({
    from: `0x${'00'.repeat(19)}${(i % 10).toString(16).padStart(2, '0')}`,
    to: `0x${'00'.repeat(19)}${((i + 1) % 10).toString(16).padStart(2, '0')}`,
    value: 1n * 10n**18n,
    gasLimit: 21000n,
}));

// Execute
const stats = await executor.execute(transactions);

console.log(`Transactions: ${stats.totalTransactions}`);
console.log(`Parallel waves: ${stats.parallelWaves}`);
console.log(`Speedup: ${stats.maxParallelism}x`);

// Check results
for (const result of executor.getResults()) {
    if (!result.success) {
        console.log(`Tx ${result.txIndex} failed: ${result.errorCode}`);
    }
}
```

### With ethers.js

```javascript
const { ethers } = require('ethers');
const { EVM } = require('zigevm');

async function simulateCall(contractAddress, calldata) {
    const evm = new EVM();
    evm.setGasLimit(3000000n);

    // Get contract code
    const code = await provider.getCode(contractAddress);
    evm.setCode(contractAddress, Buffer.from(code.slice(2), 'hex'));
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

### TypeScript

```typescript
import { EVM, EVMResult, Log, EVMError } from 'zigevm';

const evm = new EVM();

// Full type support
const result: EVMResult = evm.execute(code, calldata);
const logs: Log[] = evm.getLogs();
const gasUsed: bigint = evm.gasUsed;

evm.destroy();
```

## Error Handling

```javascript
const { EVM } = require('zigevm');

const evm = new EVM();
evm.setGasLimit(100n);  // Very low

try {
    const result = evm.execute(expensiveCode);

    if (!result.success) {
        if (result.errorCode === 1) {  // OutOfGas
            console.log('Increase gas limit');
        } else if (result.reverted) {
            console.log(`Reverted: ${result.returnData.toString('hex')}`);
        } else {
            console.log(`Error: ${result.errorName}`);
        }
    }
} catch (e) {
    console.log(`FFI error: ${e.message}`);
} finally {
    evm.destroy();
}
```

## Value Formats

```javascript
// Numbers
evm.setBalance(address, 1000000);

// BigInts (recommended for large values)
evm.setBalance(address, 1000000000000000000n);

// Hex strings
evm.setBalance(address, '0x1000');

// Buffers (32 bytes, big-endian)
evm.setBalance(address, Buffer.alloc(32));
```

## Address Formats

```javascript
// Hex string with 0x
evm.setAddress('0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');

// Buffer
evm.setAddress(Buffer.from('aa'.repeat(20), 'hex'));
```
