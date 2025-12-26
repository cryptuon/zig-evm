/**
 * @file zigevm.h
 * @brief Zig EVM - Embeddable Ethereum Virtual Machine
 *
 * A high-performance EVM implementation in Zig, designed for L2/Rollup execution.
 * This header provides the C ABI for embedding the EVM in Python, Rust, JavaScript,
 * and other languages via FFI.
 *
 * @version 0.1.0
 * @license MIT
 */

#ifndef ZIGEVM_H
#define ZIGEVM_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Error Codes
 * ============================================================ */

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

/* ============================================================
 * Result Structure
 * ============================================================ */

typedef struct {
    bool success;           /* True if execution succeeded without error or revert */
    EVMError error_code;    /* Error code if failed */
    uint64_t gas_used;      /* Gas consumed during execution */
    uint64_t gas_remaining; /* Gas remaining after execution */
    uint8_t* return_data;   /* Pointer to return data (owned by EVM) */
    size_t return_data_len; /* Length of return data */
    bool reverted;          /* True if execution reverted (REVERT opcode) */
} EVMResult;

/* ============================================================
 * Opaque EVM Handle
 * ============================================================ */

typedef void* EVMHandle;

/* ============================================================
 * EVM Lifecycle
 * ============================================================ */

/**
 * @brief Create a new EVM instance
 * @return Handle to the EVM, or NULL on failure
 * @note Must be freed with evm_destroy()
 */
EVMHandle evm_create(void);

/**
 * @brief Destroy an EVM instance and free all resources
 * @param handle EVM handle from evm_create()
 */
void evm_destroy(EVMHandle handle);

/**
 * @brief Reset EVM state for new execution
 * @param handle EVM handle
 * @note Preserves accounts and storage, clears stack/memory
 */
void evm_reset(EVMHandle handle);

/* ============================================================
 * Configuration
 * ============================================================ */

/**
 * @brief Set gas limit for execution
 * @param handle EVM handle
 * @param gas_limit Maximum gas allowed
 */
void evm_set_gas_limit(EVMHandle handle, uint64_t gas_limit);

/**
 * @brief Set block number
 * @param handle EVM handle
 * @param number Block number
 */
void evm_set_block_number(EVMHandle handle, uint64_t number);

/**
 * @brief Set block timestamp
 * @param handle EVM handle
 * @param timestamp Unix timestamp
 */
void evm_set_timestamp(EVMHandle handle, uint64_t timestamp);

/**
 * @brief Set chain ID
 * @param handle EVM handle
 * @param chain_id Chain ID (1 = mainnet, etc.)
 */
void evm_set_chain_id(EVMHandle handle, uint64_t chain_id);

/**
 * @brief Set coinbase (block producer) address
 * @param handle EVM handle
 * @param addr 20-byte address
 */
void evm_set_coinbase(EVMHandle handle, const uint8_t* addr);

/**
 * @brief Set current contract address
 * @param handle EVM handle
 * @param addr 20-byte address
 */
void evm_set_address(EVMHandle handle, const uint8_t* addr);

/**
 * @brief Set caller (msg.sender) address
 * @param handle EVM handle
 * @param addr 20-byte address
 */
void evm_set_caller(EVMHandle handle, const uint8_t* addr);

/**
 * @brief Set origin (tx.origin) address
 * @param handle EVM handle
 * @param addr 20-byte address
 */
void evm_set_origin(EVMHandle handle, const uint8_t* addr);

/**
 * @brief Set call value (msg.value)
 * @param handle EVM handle
 * @param value 32-byte big-endian value
 */
void evm_set_value(EVMHandle handle, const uint8_t* value);

/* ============================================================
 * Account Management
 * ============================================================ */

/**
 * @brief Set account balance
 * @param handle EVM handle
 * @param addr 20-byte address
 * @param balance 32-byte big-endian balance
 * @return EVM_OK on success, error code on failure
 */
EVMError evm_set_balance(EVMHandle handle, const uint8_t* addr, const uint8_t* balance);

/**
 * @brief Set account code (contract bytecode)
 * @param handle EVM handle
 * @param addr 20-byte address
 * @param code Pointer to bytecode
 * @param code_len Length of bytecode
 * @return EVM_OK on success, error code on failure
 */
EVMError evm_set_code(EVMHandle handle, const uint8_t* addr, const uint8_t* code, size_t code_len);

/**
 * @brief Set storage value
 * @param handle EVM handle
 * @param addr 20-byte address
 * @param key 32-byte storage key
 * @param value 32-byte storage value
 * @return EVM_OK on success, error code on failure
 */
EVMError evm_set_storage(EVMHandle handle, const uint8_t* addr, const uint8_t* key, const uint8_t* value);

/**
 * @brief Get storage value
 * @param handle EVM handle
 * @param addr 20-byte address
 * @param key 32-byte storage key
 * @param out 32-byte buffer to receive value
 * @return EVM_OK on success, error code on failure
 */
EVMError evm_get_storage(EVMHandle handle, const uint8_t* addr, const uint8_t* key, uint8_t* out);

/* ============================================================
 * Execution
 * ============================================================ */

/**
 * @brief Execute EVM bytecode
 * @param handle EVM handle
 * @param code Pointer to bytecode
 * @param code_len Length of bytecode
 * @param calldata Pointer to calldata (can be NULL if calldata_len is 0)
 * @param calldata_len Length of calldata
 * @return EVMResult containing execution outcome
 */
EVMResult evm_execute(EVMHandle handle, const uint8_t* code, size_t code_len,
                      const uint8_t* calldata, size_t calldata_len);

/* ============================================================
 * Result Access
 * ============================================================ */

/**
 * @brief Get gas used in last execution
 * @param handle EVM handle
 * @return Gas used
 */
uint64_t evm_gas_used(EVMHandle handle);

/**
 * @brief Get remaining gas after last execution
 * @param handle EVM handle
 * @return Remaining gas
 */
uint64_t evm_gas_remaining(EVMHandle handle);

/**
 * @brief Get return data length
 * @param handle EVM handle
 * @return Return data length in bytes
 */
size_t evm_return_data_len(EVMHandle handle);

/**
 * @brief Copy return data to buffer
 * @param handle EVM handle
 * @param out Buffer to receive data
 * @param max_len Maximum bytes to copy
 * @return Number of bytes copied
 */
size_t evm_return_data_copy(EVMHandle handle, uint8_t* out, size_t max_len);

/* ============================================================
 * Logs Access
 * ============================================================ */

/**
 * @brief Get number of logs emitted
 * @param handle EVM handle
 * @return Number of logs
 */
size_t evm_logs_count(EVMHandle handle);

/**
 * @brief Get log address at index
 * @param handle EVM handle
 * @param index Log index
 * @param out 20-byte buffer to receive address
 * @return true on success, false if index out of bounds
 */
bool evm_log_address(EVMHandle handle, size_t index, uint8_t* out);

/**
 * @brief Get log topics count at index
 * @param handle EVM handle
 * @param index Log index
 * @return Number of topics (0-4)
 */
size_t evm_log_topics_count(EVMHandle handle, size_t index);

/**
 * @brief Get log topic
 * @param handle EVM handle
 * @param log_index Log index
 * @param topic_index Topic index (0-3)
 * @param out 32-byte buffer to receive topic
 * @return true on success, false if index out of bounds
 */
bool evm_log_topic(EVMHandle handle, size_t log_index, size_t topic_index, uint8_t* out);

/**
 * @brief Get log data length
 * @param handle EVM handle
 * @param index Log index
 * @return Data length in bytes
 */
size_t evm_log_data_len(EVMHandle handle, size_t index);

/**
 * @brief Copy log data
 * @param handle EVM handle
 * @param index Log index
 * @param out Buffer to receive data
 * @param max_len Maximum bytes to copy
 * @return Number of bytes copied
 */
size_t evm_log_data_copy(EVMHandle handle, size_t index, uint8_t* out, size_t max_len);

/* ============================================================
 * Debugging
 * ============================================================ */

/**
 * @brief Get stack depth
 * @param handle EVM handle
 * @return Number of items on stack
 */
size_t evm_stack_depth(EVMHandle handle);

/**
 * @brief Peek stack value at index (0 = top)
 * @param handle EVM handle
 * @param index Stack index from top
 * @param out 32-byte buffer to receive value
 * @return true on success, false if index out of bounds
 */
bool evm_stack_peek(EVMHandle handle, size_t index, uint8_t* out);

/**
 * @brief Get memory size
 * @param handle EVM handle
 * @return Memory size in bytes
 */
size_t evm_memory_size(EVMHandle handle);

/**
 * @brief Copy memory region
 * @param handle EVM handle
 * @param offset Memory offset
 * @param out Buffer to receive data
 * @param len Number of bytes to copy
 * @return Number of bytes copied
 */
size_t evm_memory_copy(EVMHandle handle, size_t offset, uint8_t* out, size_t len);

/* ============================================================
 * Version
 * ============================================================ */

/**
 * @brief Get library version string
 * @return Null-terminated version string
 */
const char* evm_version(void);

/* ============================================================
 * Batch Execution (Parallel Processing)
 * ============================================================ */

/**
 * @brief Configuration for batch execution
 */
typedef struct {
    uint32_t max_threads;       /**< Maximum worker threads */
    bool enable_parallel;       /**< Enable parallel execution */
    bool enable_speculation;    /**< Enable speculative execution */
    uint64_t chain_id;          /**< Chain ID */
    uint64_t block_number;      /**< Block number */
    uint64_t block_timestamp;   /**< Block timestamp */
    uint64_t block_gas_limit;   /**< Block gas limit */
    uint8_t coinbase[20];       /**< Coinbase address */
} BatchConfig;

/**
 * @brief Transaction for batch execution
 */
typedef struct {
    uint8_t from[20];           /**< Sender address */
    uint8_t to[20];             /**< Recipient address */
    bool has_to;                /**< True if to address is set (false for contract creation) */
    uint8_t value[32];          /**< Value in wei (big-endian) */
    const uint8_t* data;        /**< Calldata */
    size_t data_len;            /**< Calldata length */
    uint64_t gas_limit;         /**< Gas limit */
    uint8_t gas_price[32];      /**< Gas price (big-endian) */
    uint64_t nonce;             /**< Nonce */
    bool has_nonce;             /**< True if nonce is explicitly set */
} BatchTransaction;

/**
 * @brief Result from batch execution
 */
typedef struct {
    uint32_t tx_index;          /**< Transaction index in batch */
    bool success;               /**< True if execution succeeded */
    bool reverted;              /**< True if execution reverted */
    uint64_t gas_used;          /**< Gas used */
    uint8_t* return_data;       /**< Return data pointer */
    size_t return_data_len;     /**< Return data length */
    EVMError error_code;        /**< Error code */
    size_t logs_count;          /**< Number of logs emitted */
    uint8_t created_address[20]; /**< Created contract address */
    bool has_created_address;   /**< True if contract was created */
} BatchResult;

/**
 * @brief Statistics from batch execution
 */
typedef struct {
    uint32_t total_transactions;      /**< Total transactions */
    uint32_t successful_transactions; /**< Successful transactions */
    uint32_t failed_transactions;     /**< Failed transactions */
    uint32_t reverted_transactions;   /**< Reverted transactions */
    uint64_t total_gas_used;          /**< Total gas used */
    uint64_t execution_time_ns;       /**< Execution time in nanoseconds */
    uint32_t parallel_waves;          /**< Number of parallel execution waves */
    uint32_t max_parallelism;         /**< Maximum transactions executed in parallel */
} BatchStats;

typedef void* BatchHandle;

/**
 * @brief Create a batch executor
 * @param config Configuration for batch execution
 * @return Handle to batch executor, or NULL on failure
 */
BatchHandle batch_create(const BatchConfig* config);

/**
 * @brief Destroy a batch executor
 * @param handle Batch executor handle
 */
void batch_destroy(BatchHandle handle);

/**
 * @brief Set account state in batch executor
 * @param handle Batch executor handle
 * @param addr 20-byte address
 * @param balance 32-byte balance (big-endian)
 * @param nonce Account nonce
 * @param code Contract bytecode
 * @param code_len Bytecode length
 * @return EVM_OK on success
 */
EVMError batch_set_account(BatchHandle handle, const uint8_t* addr,
                           const uint8_t* balance, uint64_t nonce,
                           const uint8_t* code, size_t code_len);

/**
 * @brief Set storage in batch executor
 * @param handle Batch executor handle
 * @param addr 20-byte address
 * @param key 32-byte storage key
 * @param value 32-byte storage value
 * @return EVM_OK on success
 */
EVMError batch_set_storage(BatchHandle handle, const uint8_t* addr,
                           const uint8_t* key, const uint8_t* value);

/**
 * @brief Execute a batch of transactions
 * @param handle Batch executor handle
 * @param transactions Array of transactions
 * @param tx_count Number of transactions
 * @param stats_out Output statistics
 * @return EVM_OK on success
 */
EVMError batch_execute(BatchHandle handle, const BatchTransaction* transactions,
                       size_t tx_count, BatchStats* stats_out);

/**
 * @brief Get number of results from last batch execution
 * @param handle Batch executor handle
 * @return Number of results
 */
size_t batch_results_count(BatchHandle handle);

/**
 * @brief Get a specific result from batch execution
 * @param handle Batch executor handle
 * @param index Result index
 * @param result_out Output result structure
 * @return true on success, false if index out of bounds
 */
bool batch_get_result(BatchHandle handle, size_t index, BatchResult* result_out);

/**
 * @brief Copy return data from a batch result
 * @param handle Batch executor handle
 * @param index Result index
 * @param out Output buffer
 * @param max_len Maximum bytes to copy
 * @return Number of bytes copied
 */
size_t batch_result_return_data(BatchHandle handle, size_t index,
                                uint8_t* out, size_t max_len);

#ifdef __cplusplus
}
#endif

#endif /* ZIGEVM_H */
