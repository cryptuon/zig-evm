/**
 * Zig EVM JavaScript Bindings
 *
 * High-performance EVM implementation for L2/Rollup execution.
 *
 * @example
 * const { EVM } = require('zigevm');
 *
 * const evm = new EVM();
 * evm.setGasLimit(1000000);
 *
 * const result = evm.execute(Buffer.from('6001600101', 'hex'));
 * console.log('Gas used:', result.gasUsed);
 */

const ffi = require('ffi-napi');
const ref = require('ref-napi');
const StructType = require('ref-struct-napi');
const path = require('path');
const os = require('os');

// ============================================================
// Type Definitions
// ============================================================

const voidPtr = ref.refType(ref.types.void);
const uint8Ptr = ref.refType(ref.types.uint8);

// EVMResult structure
const EVMResultStruct = StructType({
  success: ref.types.bool,
  error_code: ref.types.int32,
  gas_used: ref.types.uint64,
  gas_remaining: ref.types.uint64,
  return_data: uint8Ptr,
  return_data_len: ref.types.size_t,
  reverted: ref.types.bool,
});

// ============================================================
// Error Codes
// ============================================================

const EVMError = {
  OK: 0,
  OUT_OF_GAS: 1,
  STACK_UNDERFLOW: 2,
  STACK_OVERFLOW: 3,
  INVALID_OPCODE: 4,
  INVALID_JUMP: 5,
  REVERT: 6,
  STATIC_CALL_VIOLATION: 7,
  OUT_OF_MEMORY: 8,
  CALL_DEPTH_EXCEEDED: 9,
  INSUFFICIENT_BALANCE: 10,
  INVALID_ARGUMENT: 11,
  UNKNOWN_ERROR: 255,
};

const ErrorNames = {
  [EVMError.OK]: 'OK',
  [EVMError.OUT_OF_GAS]: 'OutOfGas',
  [EVMError.STACK_UNDERFLOW]: 'StackUnderflow',
  [EVMError.STACK_OVERFLOW]: 'StackOverflow',
  [EVMError.INVALID_OPCODE]: 'InvalidOpcode',
  [EVMError.INVALID_JUMP]: 'InvalidJump',
  [EVMError.REVERT]: 'Revert',
  [EVMError.STATIC_CALL_VIOLATION]: 'StaticCallViolation',
  [EVMError.OUT_OF_MEMORY]: 'OutOfMemory',
  [EVMError.CALL_DEPTH_EXCEEDED]: 'CallDepthExceeded',
  [EVMError.INSUFFICIENT_BALANCE]: 'InsufficientBalance',
  [EVMError.INVALID_ARGUMENT]: 'InvalidArgument',
  [EVMError.UNKNOWN_ERROR]: 'UnknownError',
};

// ============================================================
// Library Loading
// ============================================================

function findLibrary() {
  const platform = os.platform();
  let libName;

  switch (platform) {
    case 'darwin':
      libName = 'libzigevm.dylib';
      break;
    case 'win32':
      libName = 'zigevm.dll';
      break;
    default:
      libName = 'libzigevm.so';
  }

  // Try various paths
  const candidates = [
    path.join(__dirname, libName),
    path.join(__dirname, '..', libName),
    path.join(__dirname, '..', '..', 'zig-out', 'lib', libName),
    path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', libName),
    libName, // System path
  ];

  for (const candidate of candidates) {
    try {
      return ffi.Library(candidate, {});
    } catch (e) {
      // Continue trying
    }
  }

  throw new Error(`Could not find ${libName}. Build the library with 'zig build lib'`);
}

// Load library with function definitions
let lib;
function getLib() {
  if (!lib) {
    const libPath = findLibrary();
    lib = ffi.Library(typeof libPath === 'string' ? libPath : null, {
      // Lifecycle
      evm_create: [voidPtr, []],
      evm_destroy: ['void', [voidPtr]],
      evm_reset: ['void', [voidPtr]],

      // Configuration
      evm_set_gas_limit: ['void', [voidPtr, 'uint64']],
      evm_set_block_number: ['void', [voidPtr, 'uint64']],
      evm_set_timestamp: ['void', [voidPtr, 'uint64']],
      evm_set_chain_id: ['void', [voidPtr, 'uint64']],
      evm_set_coinbase: ['void', [voidPtr, uint8Ptr]],
      evm_set_address: ['void', [voidPtr, uint8Ptr]],
      evm_set_caller: ['void', [voidPtr, uint8Ptr]],
      evm_set_origin: ['void', [voidPtr, uint8Ptr]],
      evm_set_value: ['void', [voidPtr, uint8Ptr]],

      // Account management
      evm_set_balance: ['int32', [voidPtr, uint8Ptr, uint8Ptr]],
      evm_set_code: ['int32', [voidPtr, uint8Ptr, uint8Ptr, 'size_t']],
      evm_set_storage: ['int32', [voidPtr, uint8Ptr, uint8Ptr, uint8Ptr]],
      evm_get_storage: ['int32', [voidPtr, uint8Ptr, uint8Ptr, uint8Ptr]],

      // Execution
      evm_execute: [EVMResultStruct, [voidPtr, uint8Ptr, 'size_t', uint8Ptr, 'size_t']],

      // Results
      evm_gas_used: ['uint64', [voidPtr]],
      evm_gas_remaining: ['uint64', [voidPtr]],
      evm_return_data_len: ['size_t', [voidPtr]],
      evm_return_data_copy: ['size_t', [voidPtr, uint8Ptr, 'size_t']],

      // Logs
      evm_logs_count: ['size_t', [voidPtr]],
      evm_log_address: ['bool', [voidPtr, 'size_t', uint8Ptr]],
      evm_log_topics_count: ['size_t', [voidPtr, 'size_t']],
      evm_log_topic: ['bool', [voidPtr, 'size_t', 'size_t', uint8Ptr]],
      evm_log_data_len: ['size_t', [voidPtr, 'size_t']],
      evm_log_data_copy: ['size_t', [voidPtr, 'size_t', uint8Ptr, 'size_t']],

      // Debugging
      evm_stack_depth: ['size_t', [voidPtr]],
      evm_stack_peek: ['bool', [voidPtr, 'size_t', uint8Ptr]],
      evm_memory_size: ['size_t', [voidPtr]],
      evm_memory_copy: ['size_t', [voidPtr, 'size_t', uint8Ptr, 'size_t']],

      // Version
      evm_version: ['string', []],
    });
  }
  return lib;
}

// ============================================================
// Helper Functions
// ============================================================

function toAddress(value) {
  if (typeof value === 'string') {
    value = value.replace(/^0x/, '');
    return Buffer.from(value, 'hex');
  }
  if (Buffer.isBuffer(value)) {
    if (value.length !== 20) {
      throw new Error('Address must be 20 bytes');
    }
    return value;
  }
  throw new Error('Address must be a hex string or Buffer');
}

function toBytes32(value) {
  if (typeof value === 'bigint') {
    const hex = value.toString(16).padStart(64, '0');
    return Buffer.from(hex, 'hex');
  }
  if (typeof value === 'number') {
    return toBytes32(BigInt(value));
  }
  if (typeof value === 'string') {
    value = value.replace(/^0x/, '');
    const padded = value.padStart(64, '0');
    return Buffer.from(padded, 'hex');
  }
  if (Buffer.isBuffer(value)) {
    if (value.length > 32) {
      throw new Error('Value must be at most 32 bytes');
    }
    const buf = Buffer.alloc(32);
    value.copy(buf, 32 - value.length);
    return buf;
  }
  throw new Error('Value must be a number, bigint, hex string, or Buffer');
}

// ============================================================
// EVM Class
// ============================================================

class EVM {
  /**
   * Create a new EVM instance
   */
  constructor() {
    this._lib = getLib();
    this._handle = this._lib.evm_create();
    if (this._handle.isNull()) {
      throw new Error('Failed to create EVM instance');
    }
  }

  /**
   * Destroy the EVM instance
   */
  destroy() {
    if (this._handle && !this._handle.isNull()) {
      this._lib.evm_destroy(this._handle);
      this._handle = null;
    }
  }

  /**
   * Reset EVM state for new execution
   */
  reset() {
    this._lib.evm_reset(this._handle);
  }

  // Configuration

  /**
   * Set gas limit
   * @param {number|bigint} gasLimit
   */
  setGasLimit(gasLimit) {
    this._lib.evm_set_gas_limit(this._handle, BigInt(gasLimit));
  }

  /**
   * Set block number
   * @param {number|bigint} number
   */
  setBlockNumber(number) {
    this._lib.evm_set_block_number(this._handle, BigInt(number));
  }

  /**
   * Set timestamp
   * @param {number|bigint} timestamp
   */
  setTimestamp(timestamp) {
    this._lib.evm_set_timestamp(this._handle, BigInt(timestamp));
  }

  /**
   * Set chain ID
   * @param {number|bigint} chainId
   */
  setChainId(chainId) {
    this._lib.evm_set_chain_id(this._handle, BigInt(chainId));
  }

  /**
   * Set coinbase address
   * @param {string|Buffer} address
   */
  setCoinbase(address) {
    this._lib.evm_set_coinbase(this._handle, toAddress(address));
  }

  /**
   * Set current contract address
   * @param {string|Buffer} address
   */
  setAddress(address) {
    this._lib.evm_set_address(this._handle, toAddress(address));
  }

  /**
   * Set caller (msg.sender)
   * @param {string|Buffer} address
   */
  setCaller(address) {
    this._lib.evm_set_caller(this._handle, toAddress(address));
  }

  /**
   * Set origin (tx.origin)
   * @param {string|Buffer} address
   */
  setOrigin(address) {
    this._lib.evm_set_origin(this._handle, toAddress(address));
  }

  /**
   * Set call value (msg.value)
   * @param {number|bigint|string|Buffer} value
   */
  setValue(value) {
    this._lib.evm_set_value(this._handle, toBytes32(value));
  }

  // Account management

  /**
   * Set account balance
   * @param {string|Buffer} address
   * @param {number|bigint|string|Buffer} balance
   */
  setBalance(address, balance) {
    const err = this._lib.evm_set_balance(
      this._handle,
      toAddress(address),
      toBytes32(balance)
    );
    if (err !== 0) {
      throw new Error(`Failed to set balance: ${ErrorNames[err] || err}`);
    }
  }

  /**
   * Set account code
   * @param {string|Buffer} address
   * @param {Buffer} code
   */
  setCode(address, code) {
    if (!Buffer.isBuffer(code)) {
      code = Buffer.from(code.replace(/^0x/, ''), 'hex');
    }
    const err = this._lib.evm_set_code(
      this._handle,
      toAddress(address),
      code,
      code.length
    );
    if (err !== 0) {
      throw new Error(`Failed to set code: ${ErrorNames[err] || err}`);
    }
  }

  /**
   * Set storage value
   * @param {string|Buffer} address
   * @param {number|bigint|string|Buffer} key
   * @param {number|bigint|string|Buffer} value
   */
  setStorage(address, key, value) {
    const err = this._lib.evm_set_storage(
      this._handle,
      toAddress(address),
      toBytes32(key),
      toBytes32(value)
    );
    if (err !== 0) {
      throw new Error(`Failed to set storage: ${ErrorNames[err] || err}`);
    }
  }

  /**
   * Get storage value
   * @param {string|Buffer} address
   * @param {number|bigint|string|Buffer} key
   * @returns {Buffer}
   */
  getStorage(address, key) {
    const out = Buffer.alloc(32);
    const err = this._lib.evm_get_storage(
      this._handle,
      toAddress(address),
      toBytes32(key),
      out
    );
    if (err !== 0) {
      throw new Error(`Failed to get storage: ${ErrorNames[err] || err}`);
    }
    return out;
  }

  // Execution

  /**
   * Execute bytecode
   * @param {Buffer|string} code - Bytecode to execute
   * @param {Buffer|string} [calldata] - Optional calldata
   * @returns {Object} Execution result
   */
  execute(code, calldata = Buffer.alloc(0)) {
    if (!Buffer.isBuffer(code)) {
      code = Buffer.from(code.replace(/^0x/, ''), 'hex');
    }
    if (!Buffer.isBuffer(calldata)) {
      calldata = Buffer.from(calldata.replace(/^0x/, ''), 'hex');
    }

    const result = this._lib.evm_execute(
      this._handle,
      code,
      code.length,
      calldata,
      calldata.length
    );

    // Copy return data
    let returnData = Buffer.alloc(0);
    if (result.return_data_len > 0 && !result.return_data.isNull()) {
      returnData = Buffer.alloc(result.return_data_len);
      result.return_data.copy(returnData, 0, 0, result.return_data_len);
    }

    return {
      success: result.success,
      errorCode: result.error_code,
      errorName: ErrorNames[result.error_code] || 'Unknown',
      gasUsed: result.gas_used,
      gasRemaining: result.gas_remaining,
      returnData,
      reverted: result.reverted,
    };
  }

  // Results

  /**
   * Get gas used in last execution
   * @returns {bigint}
   */
  get gasUsed() {
    return this._lib.evm_gas_used(this._handle);
  }

  /**
   * Get remaining gas
   * @returns {bigint}
   */
  get gasRemaining() {
    return this._lib.evm_gas_remaining(this._handle);
  }

  /**
   * Get return data from last execution
   * @returns {Buffer}
   */
  getReturnData() {
    const len = this._lib.evm_return_data_len(this._handle);
    if (len === 0) return Buffer.alloc(0);
    const buf = Buffer.alloc(len);
    this._lib.evm_return_data_copy(this._handle, buf, len);
    return buf;
  }

  // Logs

  /**
   * Get logs emitted during execution
   * @returns {Array<Object>}
   */
  getLogs() {
    const count = this._lib.evm_logs_count(this._handle);
    const logs = [];

    for (let i = 0; i < count; i++) {
      // Get address
      const address = Buffer.alloc(20);
      this._lib.evm_log_address(this._handle, i, address);

      // Get topics
      const topicCount = this._lib.evm_log_topics_count(this._handle, i);
      const topics = [];
      for (let j = 0; j < topicCount; j++) {
        const topic = Buffer.alloc(32);
        this._lib.evm_log_topic(this._handle, i, j, topic);
        topics.push(topic);
      }

      // Get data
      const dataLen = this._lib.evm_log_data_len(this._handle, i);
      let data = Buffer.alloc(0);
      if (dataLen > 0) {
        data = Buffer.alloc(dataLen);
        this._lib.evm_log_data_copy(this._handle, i, data, dataLen);
      }

      logs.push({ address, topics, data });
    }

    return logs;
  }

  // Debugging

  /**
   * Get stack depth
   * @returns {number}
   */
  get stackDepth() {
    return Number(this._lib.evm_stack_depth(this._handle));
  }

  /**
   * Peek stack value at index (0 = top)
   * @param {number} index
   * @returns {Buffer|null}
   */
  stackPeek(index = 0) {
    const buf = Buffer.alloc(32);
    if (this._lib.evm_stack_peek(this._handle, index, buf)) {
      return buf;
    }
    return null;
  }

  /**
   * Get memory size
   * @returns {number}
   */
  get memorySize() {
    return Number(this._lib.evm_memory_size(this._handle));
  }

  /**
   * Read memory region
   * @param {number} offset
   * @param {number} length
   * @returns {Buffer}
   */
  memoryRead(offset, length) {
    const buf = Buffer.alloc(length);
    const copied = this._lib.evm_memory_copy(this._handle, offset, buf, length);
    return buf.slice(0, Number(copied));
  }
}

/**
 * Get library version
 * @returns {string}
 */
function version() {
  return getLib().evm_version();
}

module.exports = {
  EVM,
  EVMError,
  ErrorNames,
  version,
};
