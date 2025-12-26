//! # Zig EVM Rust Bindings
//!
//! High-performance EVM implementation for L2/Rollup execution.
//!
//! ## Example
//!
//! ```no_run
//! use zigevm::{Evm, Address};
//!
//! let mut evm = Evm::new().expect("Failed to create EVM");
//! evm.set_gas_limit(1_000_000);
//!
//! // Set up an account
//! let address = Address::from_hex("1234567890123456789012345678901234567890").unwrap();
//! evm.set_balance(&address, 1_000_000_000_000_000_000u128).unwrap(); // 1 ETH
//!
//! // Execute bytecode
//! let bytecode = hex::decode("6001600101").unwrap(); // PUSH1 1, PUSH1 1, ADD
//! let result = evm.execute(&bytecode, &[]).unwrap();
//!
//! println!("Success: {}", result.success);
//! println!("Gas used: {}", result.gas_used);
//! ```

use std::ffi::c_void;
use std::ptr;
use thiserror::Error;

// ============================================================
// Error Types
// ============================================================

/// Error codes from EVM execution
#[derive(Debug, Clone, Copy, PartialEq, Eq, Error)]
#[repr(i32)]
pub enum EvmError {
    #[error("Success")]
    Ok = 0,
    #[error("Out of gas")]
    OutOfGas = 1,
    #[error("Stack underflow")]
    StackUnderflow = 2,
    #[error("Stack overflow")]
    StackOverflow = 3,
    #[error("Invalid opcode")]
    InvalidOpcode = 4,
    #[error("Invalid jump destination")]
    InvalidJump = 5,
    #[error("Execution reverted")]
    Revert = 6,
    #[error("Static call violation")]
    StaticCallViolation = 7,
    #[error("Out of memory")]
    OutOfMemory = 8,
    #[error("Call depth exceeded")]
    CallDepthExceeded = 9,
    #[error("Insufficient balance")]
    InsufficientBalance = 10,
    #[error("Invalid argument")]
    InvalidArgument = 11,
    #[error("Unknown error")]
    UnknownError = 255,
}

impl From<i32> for EvmError {
    fn from(code: i32) -> Self {
        match code {
            0 => EvmError::Ok,
            1 => EvmError::OutOfGas,
            2 => EvmError::StackUnderflow,
            3 => EvmError::StackOverflow,
            4 => EvmError::InvalidOpcode,
            5 => EvmError::InvalidJump,
            6 => EvmError::Revert,
            7 => EvmError::StaticCallViolation,
            8 => EvmError::OutOfMemory,
            9 => EvmError::CallDepthExceeded,
            10 => EvmError::InsufficientBalance,
            11 => EvmError::InvalidArgument,
            _ => EvmError::UnknownError,
        }
    }
}

// ============================================================
// FFI Declarations
// ============================================================

#[repr(C)]
struct EvmResultFfi {
    success: bool,
    error_code: i32,
    gas_used: u64,
    gas_remaining: u64,
    return_data: *mut u8,
    return_data_len: usize,
    reverted: bool,
}

#[link(name = "zigevm")]
extern "C" {
    fn evm_create() -> *mut c_void;
    fn evm_destroy(handle: *mut c_void);
    fn evm_reset(handle: *mut c_void);

    fn evm_set_gas_limit(handle: *mut c_void, gas_limit: u64);
    fn evm_set_block_number(handle: *mut c_void, number: u64);
    fn evm_set_timestamp(handle: *mut c_void, timestamp: u64);
    fn evm_set_chain_id(handle: *mut c_void, chain_id: u64);
    fn evm_set_coinbase(handle: *mut c_void, addr: *const u8);
    fn evm_set_address(handle: *mut c_void, addr: *const u8);
    fn evm_set_caller(handle: *mut c_void, addr: *const u8);
    fn evm_set_origin(handle: *mut c_void, addr: *const u8);
    fn evm_set_value(handle: *mut c_void, value: *const u8);

    fn evm_set_balance(handle: *mut c_void, addr: *const u8, balance: *const u8) -> i32;
    fn evm_set_code(handle: *mut c_void, addr: *const u8, code: *const u8, len: usize) -> i32;
    fn evm_set_storage(handle: *mut c_void, addr: *const u8, key: *const u8, value: *const u8) -> i32;
    fn evm_get_storage(handle: *mut c_void, addr: *const u8, key: *const u8, out: *mut u8) -> i32;

    fn evm_execute(
        handle: *mut c_void,
        code: *const u8,
        code_len: usize,
        calldata: *const u8,
        calldata_len: usize,
    ) -> EvmResultFfi;

    fn evm_gas_used(handle: *mut c_void) -> u64;
    fn evm_gas_remaining(handle: *mut c_void) -> u64;
    fn evm_return_data_len(handle: *mut c_void) -> usize;
    fn evm_return_data_copy(handle: *mut c_void, out: *mut u8, max_len: usize) -> usize;

    fn evm_logs_count(handle: *mut c_void) -> usize;
    fn evm_log_address(handle: *mut c_void, index: usize, out: *mut u8) -> bool;
    fn evm_log_topics_count(handle: *mut c_void, index: usize) -> usize;
    fn evm_log_topic(handle: *mut c_void, log_index: usize, topic_index: usize, out: *mut u8) -> bool;
    fn evm_log_data_len(handle: *mut c_void, index: usize) -> usize;
    fn evm_log_data_copy(handle: *mut c_void, index: usize, out: *mut u8, max_len: usize) -> usize;

    fn evm_stack_depth(handle: *mut c_void) -> usize;
    fn evm_stack_peek(handle: *mut c_void, index: usize, out: *mut u8) -> bool;
    fn evm_memory_size(handle: *mut c_void) -> usize;
    fn evm_memory_copy(handle: *mut c_void, offset: usize, out: *mut u8, len: usize) -> usize;

    fn evm_version() -> *const i8;
}

// ============================================================
// Type Aliases
// ============================================================

/// 20-byte Ethereum address
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct Address(pub [u8; 20]);

impl Address {
    /// Create address from hex string (with or without 0x prefix)
    pub fn from_hex(s: &str) -> Result<Self, &'static str> {
        let s = s.strip_prefix("0x").unwrap_or(s);
        if s.len() != 40 {
            return Err("Address must be 40 hex characters");
        }
        let mut bytes = [0u8; 20];
        for (i, chunk) in s.as_bytes().chunks(2).enumerate() {
            let hex_str = std::str::from_utf8(chunk).map_err(|_| "Invalid UTF-8")?;
            bytes[i] = u8::from_str_radix(hex_str, 16).map_err(|_| "Invalid hex")?;
        }
        Ok(Address(bytes))
    }

    /// Convert to hex string with 0x prefix
    pub fn to_hex(&self) -> String {
        format!("0x{}", hex::encode(self.0))
    }
}

impl AsRef<[u8; 20]> for Address {
    fn as_ref(&self) -> &[u8; 20] {
        &self.0
    }
}

/// 32-byte value (hash, storage key, etc.)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct Bytes32(pub [u8; 32]);

impl Bytes32 {
    /// Create from hex string
    pub fn from_hex(s: &str) -> Result<Self, &'static str> {
        let s = s.strip_prefix("0x").unwrap_or(s);
        if s.len() != 64 {
            return Err("Bytes32 must be 64 hex characters");
        }
        let mut bytes = [0u8; 32];
        for (i, chunk) in s.as_bytes().chunks(2).enumerate() {
            let hex_str = std::str::from_utf8(chunk).map_err(|_| "Invalid UTF-8")?;
            bytes[i] = u8::from_str_radix(hex_str, 16).map_err(|_| "Invalid hex")?;
        }
        Ok(Bytes32(bytes))
    }

    /// Create from u128 (for balance, etc.)
    pub fn from_u128(value: u128) -> Self {
        let mut bytes = [0u8; 32];
        bytes[16..].copy_from_slice(&value.to_be_bytes());
        Bytes32(bytes)
    }

    /// Create from U256-like value as big-endian bytes
    pub fn from_be_bytes(bytes: [u8; 32]) -> Self {
        Bytes32(bytes)
    }

    /// Convert to U256 value (returns u128 for simplicity)
    pub fn to_u128(&self) -> u128 {
        let mut bytes = [0u8; 16];
        bytes.copy_from_slice(&self.0[16..]);
        u128::from_be_bytes(bytes)
    }
}

// ============================================================
// Result Types
// ============================================================

/// Result of EVM execution
#[derive(Debug, Clone)]
pub struct EvmResult {
    /// True if execution succeeded
    pub success: bool,
    /// Error code if failed
    pub error: EvmError,
    /// Gas consumed
    pub gas_used: u64,
    /// Gas remaining
    pub gas_remaining: u64,
    /// Return data
    pub return_data: Vec<u8>,
    /// True if execution reverted (REVERT opcode)
    pub reverted: bool,
}

/// Log entry (event)
#[derive(Debug, Clone)]
pub struct Log {
    /// Contract address that emitted the log
    pub address: Address,
    /// Log topics (0-4)
    pub topics: Vec<Bytes32>,
    /// Log data
    pub data: Vec<u8>,
}

// ============================================================
// EVM Implementation
// ============================================================

/// Ethereum Virtual Machine instance
pub struct Evm {
    handle: *mut c_void,
}

// Safety: The EVM handle is thread-safe for single-threaded access
unsafe impl Send for Evm {}

impl Evm {
    /// Create a new EVM instance
    pub fn new() -> Result<Self, EvmError> {
        let handle = unsafe { evm_create() };
        if handle.is_null() {
            return Err(EvmError::OutOfMemory);
        }
        Ok(Evm { handle })
    }

    /// Reset EVM state for new execution
    pub fn reset(&mut self) {
        unsafe { evm_reset(self.handle) }
    }

    // Configuration

    /// Set gas limit for execution
    pub fn set_gas_limit(&mut self, gas_limit: u64) {
        unsafe { evm_set_gas_limit(self.handle, gas_limit) }
    }

    /// Set block number
    pub fn set_block_number(&mut self, number: u64) {
        unsafe { evm_set_block_number(self.handle, number) }
    }

    /// Set block timestamp
    pub fn set_timestamp(&mut self, timestamp: u64) {
        unsafe { evm_set_timestamp(self.handle, timestamp) }
    }

    /// Set chain ID
    pub fn set_chain_id(&mut self, chain_id: u64) {
        unsafe { evm_set_chain_id(self.handle, chain_id) }
    }

    /// Set coinbase address
    pub fn set_coinbase(&mut self, address: &Address) {
        unsafe { evm_set_coinbase(self.handle, address.0.as_ptr()) }
    }

    /// Set current contract address
    pub fn set_address(&mut self, address: &Address) {
        unsafe { evm_set_address(self.handle, address.0.as_ptr()) }
    }

    /// Set caller (msg.sender)
    pub fn set_caller(&mut self, address: &Address) {
        unsafe { evm_set_caller(self.handle, address.0.as_ptr()) }
    }

    /// Set origin (tx.origin)
    pub fn set_origin(&mut self, address: &Address) {
        unsafe { evm_set_origin(self.handle, address.0.as_ptr()) }
    }

    /// Set call value (msg.value)
    pub fn set_value(&mut self, value: u128) {
        let bytes = Bytes32::from_u128(value);
        unsafe { evm_set_value(self.handle, bytes.0.as_ptr()) }
    }

    // Account management

    /// Set account balance
    pub fn set_balance(&mut self, address: &Address, balance: u128) -> Result<(), EvmError> {
        let balance_bytes = Bytes32::from_u128(balance);
        let err = unsafe {
            evm_set_balance(self.handle, address.0.as_ptr(), balance_bytes.0.as_ptr())
        };
        if err != 0 {
            return Err(EvmError::from(err));
        }
        Ok(())
    }

    /// Set account code
    pub fn set_code(&mut self, address: &Address, code: &[u8]) -> Result<(), EvmError> {
        let err = unsafe {
            evm_set_code(self.handle, address.0.as_ptr(), code.as_ptr(), code.len())
        };
        if err != 0 {
            return Err(EvmError::from(err));
        }
        Ok(())
    }

    /// Set storage value
    pub fn set_storage(&mut self, address: &Address, key: &Bytes32, value: &Bytes32) -> Result<(), EvmError> {
        let err = unsafe {
            evm_set_storage(self.handle, address.0.as_ptr(), key.0.as_ptr(), value.0.as_ptr())
        };
        if err != 0 {
            return Err(EvmError::from(err));
        }
        Ok(())
    }

    /// Get storage value
    pub fn get_storage(&self, address: &Address, key: &Bytes32) -> Result<Bytes32, EvmError> {
        let mut out = [0u8; 32];
        let err = unsafe {
            evm_get_storage(self.handle, address.0.as_ptr(), key.0.as_ptr(), out.as_mut_ptr())
        };
        if err != 0 {
            return Err(EvmError::from(err));
        }
        Ok(Bytes32(out))
    }

    // Execution

    /// Execute bytecode with optional calldata
    pub fn execute(&mut self, code: &[u8], calldata: &[u8]) -> Result<EvmResult, EvmError> {
        let result = unsafe {
            evm_execute(
                self.handle,
                code.as_ptr(),
                code.len(),
                if calldata.is_empty() { ptr::null() } else { calldata.as_ptr() },
                calldata.len(),
            )
        };

        // Copy return data
        let return_data = if result.return_data_len > 0 && !result.return_data.is_null() {
            let mut data = vec![0u8; result.return_data_len];
            unsafe {
                ptr::copy_nonoverlapping(result.return_data, data.as_mut_ptr(), result.return_data_len);
            }
            data
        } else {
            Vec::new()
        };

        Ok(EvmResult {
            success: result.success,
            error: EvmError::from(result.error_code),
            gas_used: result.gas_used,
            gas_remaining: result.gas_remaining,
            return_data,
            reverted: result.reverted,
        })
    }

    // Results

    /// Get gas used in last execution
    pub fn gas_used(&self) -> u64 {
        unsafe { evm_gas_used(self.handle) }
    }

    /// Get remaining gas
    pub fn gas_remaining(&self) -> u64 {
        unsafe { evm_gas_remaining(self.handle) }
    }

    /// Get return data from last execution
    pub fn return_data(&self) -> Vec<u8> {
        let len = unsafe { evm_return_data_len(self.handle) };
        if len == 0 {
            return Vec::new();
        }
        let mut data = vec![0u8; len];
        unsafe { evm_return_data_copy(self.handle, data.as_mut_ptr(), len) };
        data
    }

    // Logs

    /// Get logs emitted during execution
    pub fn logs(&self) -> Vec<Log> {
        let count = unsafe { evm_logs_count(self.handle) };
        let mut logs = Vec::with_capacity(count);

        for i in 0..count {
            // Get address
            let mut address = [0u8; 20];
            unsafe { evm_log_address(self.handle, i, address.as_mut_ptr()) };

            // Get topics
            let topic_count = unsafe { evm_log_topics_count(self.handle, i) };
            let mut topics = Vec::with_capacity(topic_count);
            for j in 0..topic_count {
                let mut topic = [0u8; 32];
                unsafe { evm_log_topic(self.handle, i, j, topic.as_mut_ptr()) };
                topics.push(Bytes32(topic));
            }

            // Get data
            let data_len = unsafe { evm_log_data_len(self.handle, i) };
            let data = if data_len > 0 {
                let mut data = vec![0u8; data_len];
                unsafe { evm_log_data_copy(self.handle, i, data.as_mut_ptr(), data_len) };
                data
            } else {
                Vec::new()
            };

            logs.push(Log {
                address: Address(address),
                topics,
                data,
            });
        }

        logs
    }

    // Debugging

    /// Get stack depth
    pub fn stack_depth(&self) -> usize {
        unsafe { evm_stack_depth(self.handle) }
    }

    /// Peek stack value at index (0 = top)
    pub fn stack_peek(&self, index: usize) -> Option<Bytes32> {
        let mut out = [0u8; 32];
        if unsafe { evm_stack_peek(self.handle, index, out.as_mut_ptr()) } {
            Some(Bytes32(out))
        } else {
            None
        }
    }

    /// Get memory size
    pub fn memory_size(&self) -> usize {
        unsafe { evm_memory_size(self.handle) }
    }

    /// Read memory region
    pub fn memory_read(&self, offset: usize, len: usize) -> Vec<u8> {
        let mut data = vec![0u8; len];
        let copied = unsafe { evm_memory_copy(self.handle, offset, data.as_mut_ptr(), len) };
        data.truncate(copied);
        data
    }
}

impl Drop for Evm {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe { evm_destroy(self.handle) }
        }
    }
}

/// Get library version
pub fn version() -> &'static str {
    unsafe {
        let ptr = evm_version();
        std::ffi::CStr::from_ptr(ptr).to_str().unwrap_or("unknown")
    }
}

// Hex encoding helper (minimal implementation)
mod hex {
    pub fn encode(data: impl AsRef<[u8]>) -> String {
        data.as_ref().iter().map(|b| format!("{:02x}", b)).collect()
    }

    pub fn decode(s: &str) -> Result<Vec<u8>, &'static str> {
        let s = s.strip_prefix("0x").unwrap_or(s);
        if s.len() % 2 != 0 {
            return Err("Odd length hex string");
        }
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(|_| "Invalid hex"))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_address_from_hex() {
        let addr = Address::from_hex("0x1234567890123456789012345678901234567890").unwrap();
        assert_eq!(addr.0[0], 0x12);
        assert_eq!(addr.0[19], 0x90);
    }

    #[test]
    fn test_bytes32_from_u128() {
        let b = Bytes32::from_u128(256);
        assert_eq!(b.0[31], 0);
        assert_eq!(b.0[30], 1);
    }
}
