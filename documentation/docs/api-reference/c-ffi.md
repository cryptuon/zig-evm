# C FFI Reference

Complete C ABI reference for embedding Zig EVM in C/C++ and other languages.

## Building the Library

```bash
# Build shared and static libraries
zig build lib

# Output:
# - zig-out/lib/libzigevm.so (Linux)
# - zig-out/lib/libzigevm.dylib (macOS)
# - zig-out/lib/libzigevm.dll (Windows)
# - zig-out/lib/libzigevm.a (static)
# - zig-out/include/zigevm.h (header)
```

## Header

```c
#include "zigevm.h"
```

## Error Codes

```c
typedef enum {
    EVM_OK = 0,
    EVM_OUT_OF_GAS = 1,
    EVM_STACK_UNDERFLOW = 2,
    EVM_STACK_OVERFLOW = 3,
    EVM_INVALID_OPCODE = 4,
    EVM_INVALID_JUMP = 5,
    EVM_REVERT = 6,
    EVM_STATIC_CALL_VIOLATION = 7,
    EVM_OUT_OF_MEMORY = 8,
    EVM_CALL_DEPTH_EXCEEDED = 9,
    EVM_INSUFFICIENT_BALANCE = 10,
    EVM_INVALID_ARGUMENT = 11,
    EVM_UNKNOWN_ERROR = 255,
} EVMError;
```

## Single Execution API

### Lifecycle

#### evm_create

```c
EVMHandle evm_create(void);
```

Create a new EVM instance.

**Returns**: Handle to the EVM, or `NULL` on failure.

---

#### evm_destroy

```c
void evm_destroy(EVMHandle handle);
```

Destroy an EVM instance and free all resources.

---

#### evm_reset

```c
void evm_reset(EVMHandle handle);
```

Reset EVM state for new execution. Preserves accounts and storage.

### Configuration

#### evm_set_gas_limit

```c
void evm_set_gas_limit(EVMHandle handle, uint64_t gas_limit);
```

Set the maximum gas allowed for execution.

---

#### evm_set_block_number

```c
void evm_set_block_number(EVMHandle handle, uint64_t number);
```

Set the current block number.

---

#### evm_set_timestamp

```c
void evm_set_timestamp(EVMHandle handle, uint64_t timestamp);
```

Set the block timestamp.

---

#### evm_set_chain_id

```c
void evm_set_chain_id(EVMHandle handle, uint64_t chain_id);
```

Set the chain ID (1 = mainnet).

---

#### evm_set_coinbase

```c
void evm_set_coinbase(EVMHandle handle, const uint8_t* addr);
```

Set the coinbase (block producer) address.

**Parameters**:
- `addr`: 20-byte address

---

#### evm_set_address

```c
void evm_set_address(EVMHandle handle, const uint8_t* addr);
```

Set the current contract address.

---

#### evm_set_caller

```c
void evm_set_caller(EVMHandle handle, const uint8_t* addr);
```

Set the caller address (msg.sender).

---

#### evm_set_origin

```c
void evm_set_origin(EVMHandle handle, const uint8_t* addr);
```

Set the transaction origin (tx.origin).

---

#### evm_set_value

```c
void evm_set_value(EVMHandle handle, const uint8_t* value);
```

Set the call value.

**Parameters**:
- `value`: 32-byte big-endian value

### Account Management

#### evm_set_balance

```c
EVMError evm_set_balance(EVMHandle handle, const uint8_t* addr,
                          const uint8_t* balance);
```

Set an account's balance.

**Parameters**:
- `addr`: 20-byte address
- `balance`: 32-byte big-endian balance

---

#### evm_set_code

```c
EVMError evm_set_code(EVMHandle handle, const uint8_t* addr,
                       const uint8_t* code, size_t code_len);
```

Set an account's bytecode.

---

#### evm_set_storage

```c
EVMError evm_set_storage(EVMHandle handle, const uint8_t* addr,
                          const uint8_t* key, const uint8_t* value);
```

Set a storage slot value.

**Parameters**:
- `addr`: 20-byte address
- `key`: 32-byte storage key
- `value`: 32-byte storage value

---

#### evm_get_storage

```c
EVMError evm_get_storage(EVMHandle handle, const uint8_t* addr,
                          const uint8_t* key, uint8_t* out);
```

Get a storage slot value.

**Parameters**:
- `out`: 32-byte buffer to receive value

### Execution

#### evm_execute

```c
EVMResult evm_execute(EVMHandle handle, const uint8_t* code, size_t code_len,
                       const uint8_t* calldata, size_t calldata_len);
```

Execute EVM bytecode.

**Returns**: `EVMResult` structure:

```c
typedef struct {
    bool success;           // True if execution succeeded
    EVMError error_code;    // Error code if failed
    uint64_t gas_used;      // Gas consumed
    uint64_t gas_remaining; // Gas remaining
    uint8_t* return_data;   // Return data (owned by EVM)
    size_t return_data_len; // Return data length
    bool reverted;          // True if REVERT was called
} EVMResult;
```

### Result Access

#### evm_gas_used

```c
uint64_t evm_gas_used(EVMHandle handle);
```

Get gas used in last execution.

---

#### evm_gas_remaining

```c
uint64_t evm_gas_remaining(EVMHandle handle);
```

Get remaining gas after last execution.

---

#### evm_return_data_len

```c
size_t evm_return_data_len(EVMHandle handle);
```

Get return data length.

---

#### evm_return_data_copy

```c
size_t evm_return_data_copy(EVMHandle handle, uint8_t* out, size_t max_len);
```

Copy return data to buffer.

**Returns**: Number of bytes copied.

### Logs Access

#### evm_logs_count

```c
size_t evm_logs_count(EVMHandle handle);
```

Get number of logs emitted.

---

#### evm_log_address

```c
bool evm_log_address(EVMHandle handle, size_t index, uint8_t* out);
```

Get log address at index.

---

#### evm_log_topics_count

```c
size_t evm_log_topics_count(EVMHandle handle, size_t index);
```

Get number of topics (0-4) for a log.

---

#### evm_log_topic

```c
bool evm_log_topic(EVMHandle handle, size_t log_index,
                    size_t topic_index, uint8_t* out);
```

Get a specific topic from a log.

---

#### evm_log_data_len

```c
size_t evm_log_data_len(EVMHandle handle, size_t index);
```

Get log data length.

---

#### evm_log_data_copy

```c
size_t evm_log_data_copy(EVMHandle handle, size_t index,
                          uint8_t* out, size_t max_len);
```

Copy log data to buffer.

### Debugging

#### evm_stack_depth

```c
size_t evm_stack_depth(EVMHandle handle);
```

Get number of items on stack.

---

#### evm_stack_peek

```c
bool evm_stack_peek(EVMHandle handle, size_t index, uint8_t* out);
```

Peek stack value at index (0 = top).

---

#### evm_memory_size

```c
size_t evm_memory_size(EVMHandle handle);
```

Get memory size in bytes.

---

#### evm_memory_copy

```c
size_t evm_memory_copy(EVMHandle handle, size_t offset,
                        uint8_t* out, size_t len);
```

Copy memory region to buffer.

### Version

#### evm_version

```c
const char* evm_version(void);
```

Get library version string.

## Batch Execution API

### Structures

#### BatchConfig

```c
typedef struct {
    uint32_t max_threads;       // Maximum worker threads
    bool enable_parallel;       // Enable parallel execution
    bool enable_speculation;    // Enable speculative execution
    uint64_t chain_id;          // Chain ID
    uint64_t block_number;      // Block number
    uint64_t block_timestamp;   // Block timestamp
    uint64_t block_gas_limit;   // Block gas limit
    uint8_t coinbase[20];       // Coinbase address
} BatchConfig;
```

#### BatchTransaction

```c
typedef struct {
    uint8_t from[20];           // Sender address
    uint8_t to[20];             // Recipient address
    bool has_to;                // True if to address is set
    uint8_t value[32];          // Value in wei (big-endian)
    const uint8_t* data;        // Calldata
    size_t data_len;            // Calldata length
    uint64_t gas_limit;         // Gas limit
    uint8_t gas_price[32];      // Gas price (big-endian)
    uint64_t nonce;             // Nonce
    bool has_nonce;             // True if nonce is set
} BatchTransaction;
```

#### BatchResult

```c
typedef struct {
    uint32_t tx_index;          // Transaction index
    bool success;               // True if succeeded
    bool reverted;              // True if reverted
    uint64_t gas_used;          // Gas used
    uint8_t* return_data;       // Return data pointer
    size_t return_data_len;     // Return data length
    EVMError error_code;        // Error code
    size_t logs_count;          // Number of logs
    uint8_t created_address[20]; // Created contract address
    bool has_created_address;   // True if contract created
} BatchResult;
```

#### BatchStats

```c
typedef struct {
    uint32_t total_transactions;      // Total transactions
    uint32_t successful_transactions; // Successful count
    uint32_t failed_transactions;     // Failed count
    uint32_t reverted_transactions;   // Reverted count
    uint64_t total_gas_used;          // Total gas used
    uint64_t execution_time_ns;       // Execution time
    uint32_t parallel_waves;          // Parallel waves
    uint32_t max_parallelism;         // Max parallelism
} BatchStats;
```

### Functions

#### batch_create

```c
BatchHandle batch_create(const BatchConfig* config);
```

Create a batch executor.

---

#### batch_destroy

```c
void batch_destroy(BatchHandle handle);
```

Destroy a batch executor.

---

#### batch_set_account

```c
EVMError batch_set_account(BatchHandle handle, const uint8_t* addr,
                            const uint8_t* balance, uint64_t nonce,
                            const uint8_t* code, size_t code_len);
```

Set account state in batch executor.

---

#### batch_set_storage

```c
EVMError batch_set_storage(BatchHandle handle, const uint8_t* addr,
                            const uint8_t* key, const uint8_t* value);
```

Set storage in batch executor.

---

#### batch_execute

```c
EVMError batch_execute(BatchHandle handle,
                        const BatchTransaction* transactions,
                        size_t tx_count, BatchStats* stats_out);
```

Execute a batch of transactions.

---

#### batch_results_count

```c
size_t batch_results_count(BatchHandle handle);
```

Get number of results from last execution.

---

#### batch_get_result

```c
bool batch_get_result(BatchHandle handle, size_t index, BatchResult* result_out);
```

Get a specific result.

---

#### batch_result_return_data

```c
size_t batch_result_return_data(BatchHandle handle, size_t index,
                                 uint8_t* out, size_t max_len);
```

Copy return data from a result.

## Complete Example

```c
#include <stdio.h>
#include <string.h>
#include "zigevm.h"

int main() {
    // Create EVM
    EVMHandle evm = evm_create();
    if (!evm) {
        fprintf(stderr, "Failed to create EVM\n");
        return 1;
    }

    // Configure
    evm_set_gas_limit(evm, 1000000);
    evm_set_chain_id(evm, 1);

    // Set up account
    uint8_t addr[20] = {0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
                        0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
                        0xaa, 0xaa, 0xaa, 0xaa, 0xaa,
                        0xaa, 0xaa, 0xaa, 0xaa, 0xaa};
    uint8_t balance[32] = {0};
    balance[31] = 100;
    evm_set_balance(evm, addr, balance);
    evm_set_address(evm, addr);

    // Bytecode: PUSH1 42, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
    uint8_t code[] = {
        0x60, 0x2a,  // PUSH1 42
        0x60, 0x00,  // PUSH1 0
        0x52,        // MSTORE
        0x60, 0x20,  // PUSH1 32
        0x60, 0x00,  // PUSH1 0
        0xf3         // RETURN
    };

    // Execute
    EVMResult result = evm_execute(evm, code, sizeof(code), NULL, 0);

    if (result.success) {
        printf("Execution successful!\n");
        printf("Gas used: %lu\n", result.gas_used);
        printf("Return data length: %zu\n", result.return_data_len);

        if (result.return_data_len > 0) {
            printf("Return data: ");
            for (size_t i = 0; i < result.return_data_len; i++) {
                printf("%02x", result.return_data[i]);
            }
            printf("\n");
        }
    } else {
        printf("Execution failed with error: %d\n", result.error_code);
        if (result.reverted) {
            printf("Transaction reverted\n");
        }
    }

    // Cleanup
    evm_destroy(evm);
    return 0;
}
```

## Linking

### Linux/macOS

```bash
gcc -o myapp myapp.c -L/path/to/lib -lzigevm -Wl,-rpath,/path/to/lib
```

### Windows

```bash
cl myapp.c /I path\to\include /link path\to\lib\zigevm.lib
```

## Thread Safety

- Each EVM instance is **NOT** thread-safe
- Create separate instances for concurrent use
- BatchExecutor handles internal threading
- FFI functions are safe to call from any thread
