# EVM Implementation Plan

This document outlines a comprehensive plan for implementing the Ethereum Virtual Machine (EVM) in Zig, covering all major components of the specification.

## 1. Core Data Structures

### 1.1 BigInt (256-bit Integer)
- [x] Basic implementation with addition and subtraction
- [x] Implement multiplication
- [ ] Implement division
- [ ] Implement modulo operations
- [ ] Implement bitwise operations (AND, OR, XOR, NOT)
- [ ] Implement shift operations (SHL, SHR, SAR)
- [ ] Implement comparison operations
- [ ] Implement conversion functions (to/from bytes, to/from u64, etc.)

### 1.2 Memory
- [x] Basic structure with store/load functions
- [ ] Implement proper memory expansion
- [ ] Implement memory gas cost calculation
- [ ] Implement MLOAD opcode
- [ ] Implement MSTORE opcode
- [ ] Implement MSTORE8 opcode
- [ ] Implement MSIZE opcode

### 1.3 Stack
- [x] Basic structure with push/pop functions
- [x] Implement full stack operations (1024 item limit)
- [x] Implement stack underflow/overflow checks
- [ ] Implement DUP opcodes (DUP1-DUP16)
- [ ] Implement SWAP opcodes (SWAP1-SWAP16)

### 1.4 Account
- [x] Basic structure with balance, nonce, code, storage
- [ ] Implement proper account state management
- [ ] Implement account creation logic
- [ ] Implement account deletion (SELFDESTRUCT)

### 1.5 Transaction
- [x] Basic structure with from, to, value, data, gas_limit, gas_price
- [ ] Implement transaction validation
- [ ] Implement transaction signing/verification
- [ ] Implement transaction receipt generation

### 1.6 EVM Context
- [x] Basic structure with stack, memory, pc, gas, code, accounts
- [ ] Implement proper execution context management
- [ ] Implement call stack for nested calls
- [ ] Implement block context (blockhash, timestamp, etc.)

## 2. Opcode Implementation

### 2.1 Arithmetic Operations
- [x] ADD - Addition operation
- [x] MUL - Multiplication operation
- [ ] SUB - Subtraction operation
- [ ] DIV - Division operation
- [ ] SDIV - Signed division operation
- [ ] MOD - Modulo operation
- [ ] SMOD - Signed modulo operation
- [ ] ADDMOD - Addition modulo operation
- [ ] MULMOD - Multiplication modulo operation
- [ ] EXP - Exponential operation
- [ ] SIGNEXTEND - Sign extension operation

### 2.2 Bitwise Operations
- [ ] LT - Less-than comparison
- [ ] GT - Greater-than comparison
- [ ] SLT - Signed less-than comparison
- [ ] SGT - Signed greater-than comparison
- [ ] EQ - Equality comparison
- [ ] ISZERO - Simple not operation
- [ ] AND - Bitwise AND operation
- [ ] OR - Bitwise OR operation
- [ ] XOR - Bitwise XOR operation
- [ ] NOT - Bitwise NOT operation
- [ ] BYTE - Retrieve single byte from word
- [ ] SHL - Logical left shift
- [ ] SHR - Logical right shift
- [ ] SAR - Arithmetic right shift

### 2.3 Cryptographic Operations
- [ ] SHA3 - Compute Keccak-256 hash
- [ ] ADDRESS - Get address of currently executing account
- [ ] BALANCE - Get balance of the given account
- [ ] ORIGIN - Get execution origination address
- [ ] CALLER - Get caller address
- [ ] CALLVALUE - Get deposited value by the instruction/transaction responsible for this execution
- [ ] CALLDATALOAD - Get input data of current environment
- [ ] CALLDATASIZE - Get size of input data in current environment
- [ ] CALLDATACOPY - Copy input data in current environment to memory
- [ ] CODESIZE - Get size of code running in current environment
- [ ] CODECOPY - Copy code running in current environment to memory
- [ ] GASPRICE - Get price of gas in current environment
- [ ] EXTCODESIZE - Get size of an account's code
- [ ] EXTCODECOPY - Copy an account's code to memory
- [ ] RETURNDATASIZE - Get size of output data from the previous call in the current environment
- [ ] RETURNDATACOPY - Copy output data from the previous call to memory
- [ ] EXTCODEHASH - Get hash of an account's code

### 2.4 Environmental Operations
- [ ] BLOCKHASH - Get hash of most recent complete block
- [ ] COINBASE - Get the block's beneficiary address
- [ ] TIMESTAMP - Get the block's timestamp
- [ ] NUMBER - Get the block's number
- [ ] DIFFICULTY - Get the block's difficulty
- [ ] GASLIMIT - Get the block's gas limit
- [ ] CHAINID - Get the current chain ID
- [ ] SELFBALANCE - Get balance of currently executing account
- [ ] BASEFEE - Get the block's base fee

### 2.5 Stack Operations
- [x] POP - Remove item from stack
- [ ] MLOAD - Load word from memory
- [ ] MSTORE - Save word to memory
- [ ] MSTORE8 - Save byte to memory
- [ ] SLOAD - Load word from storage
- [ ] SSTORE - Save word to storage
- [ ] JUMP - Alter the program counter
- [ ] JUMPI - Conditionally alter the program counter
- [ ] PC - Get the value of the program counter prior to the increment
- [ ] MSIZE - Get the size of active memory in bytes
- [ ] GAS - Get the amount of available gas, including the corresponding reduction
- [ ] JUMPDEST - Mark a valid destination for jumps

### 2.6 Push Operations
- [x] PUSH1 - Place 1 byte item on stack
- [ ] PUSH2 - Place 2 byte item on stack
- [ ] ...
- [ ] PUSH32 - Place 32 byte item on stack

### 2.7 Duplication Operations
- [ ] DUP1 - Duplicate 1st stack item
- [ ] DUP2 - Duplicate 2nd stack item
- [ ] ...
- [ ] DUP16 - Duplicate 16th stack item

### 2.8 Exchange Operations
- [ ] SWAP1 - Exchange 1st and 2nd stack items
- [ ] SWAP2 - Exchange 1st and 3rd stack items
- [ ] ...
- [ ] SWAP16 - Exchange 1st and 17th stack items

### 2.9 Logging Operations
- [ ] LOG0 - Append log record with no topics
- [ ] LOG1 - Append log record with one topic
- [ ] LOG2 - Append log record with two topics
- [ ] LOG3 - Append log record with three topics
- [ ] LOG4 - Append log record with four topics

### 2.10 System Operations
- [x] STOP - Halt execution
- [ ] CREATE - Create a new account with associated code
- [ ] CALL - Message-call into an account
- [ ] CALLCODE - Message-call into this account with an alternative account's code
- [ ] RETURN - Halt execution returning output data
- [ ] DELEGATECALL - Message-call into this account with an alternative account's code, but persisting the current values for sender and value
- [ ] CREATE2 - Create a new account with associated code at a predictable address
- [ ] STATICCALL - Static message-call into an account
- [ ] REVERT - Halt execution reverting state changes but returning data
- [ ] INVALID - Designated invalid instruction
- [ ] SELFDESTRUCT - Halt execution and register account for deletion

## 3. Gas Calculation

### 3.1 Static Gas Costs
- [ ] Implement fixed gas costs for all opcodes
- [ ] Implement gas consumption for arithmetic operations
- [ ] Implement gas consumption for bitwise operations
- [ ] Implement gas consumption for cryptographic operations
- [ ] Implement gas consumption for environmental operations
- [ ] Implement gas consumption for stack operations
- [ ] Implement gas consumption for flow control operations

### 3.2 Dynamic Gas Costs
- [ ] Implement memory expansion gas cost calculation
- [ ] Implement storage operation gas costs (SLOAD, SSTORE)
- [ ] Implement data copying gas costs (CALLDATACOPY, CODECOPY, etc.)
- [ ] Implement contract creation gas costs
- [ ] Implement message call gas costs
- [ ] Implement log operation gas costs

### 3.3 Gas Refunds
- [ ] Implement gas refunds for clearing storage
- [ ] Implement gas refunds for SELFDESTRUCT operations

## 4. Memory Management

### 4.1 Memory Model
- [x] Implement linear, expandable memory
- [ ] Implement byte-addressable memory with word alignment
- [ ] Implement memory expansion on access
- [ ] Implement memory size tracking

### 4.2 Memory Operations
- [ ] Implement MLOAD to load words from memory
- [ ] Implement MSTORE to save words to memory
- [ ] Implement MSTORE8 to save bytes to memory
- [ ] Implement MSIZE to get active memory size

## 5. Storage Management

### 5.1 Storage Model
- [ ] Implement persistent key-value storage
- [ ] Implement storage trie structure
- [ ] Implement storage access patterns

### 5.2 Storage Operations
- [ ] Implement SLOAD to load words from storage
- [ ] Implement SSTORE to save words to storage
- [ ] Implement storage gas costs
- [ ] Implement storage refunds

## 6. Execution Context

### 6.1 Program Counter
- [x] Implement PC tracking
- [x] Implement PC updates for normal execution
- [ ] Implement PC jumps (JUMP, JUMPI)

### 6.2 Call Stack
- [ ] Implement nested call tracking
- [ ] Implement call frame management
- [ ] Implement return data handling

### 6.3 Exception Handling
- [x] Implement stack underflow/overflow handling
- [ ] Implement invalid opcode handling
- [ ] Implement insufficient gas handling
- [ ] Implement invalid jump handling
- [ ] Implement out of bounds memory access handling

## 7. State Transitions

### 7.1 Transaction Processing
- [x] Implement intrinsic validation
- [ ] Implement nonce verification
- [ ] Implement gas validation
- [ ] Implement account creation
- [ ] Implement value transfer
- [ ] Implement contract execution
- [ ] Implement state updates

### 7.2 Message Calls
- [ ] Implement value transfer between accounts
- [ ] Implement contract code execution
- [ ] Implement return data handling
- [ ] Implement exception handling

### 7.3 Contract Creation
- [ ] Implement new contract code deployment
- [ ] Implement contract storage initialization
- [ ] Implement contract address calculation
- [ ] Implement contract creation gas costs

## 8. Precompiled Contracts

### 8.1 Standard Precompiled Contracts
- [ ] Implement ECDSA recovery (0x01)
- [ ] Implement SHA2-256 hash (0x02)
- [ ] Implement RIPEMD-160 hash (0x03)
- [ ] Implement identity function (0x04)
- [ ] Implement modular exponentiation (0x05)
- [ ] Implement elliptic curve addition (0x06)
- [ ] Implement elliptic curve scalar multiplication (0x07)
- [ ] Implement elliptic curve pairing check (0x08)

## 9. Additional Features

### 9.1 Logs and Events
- [ ] Implement log record generation
- [ ] Implement log topic indexing
- [ ] Implement transaction receipt generation
- [ ] Implement bloom filter generation

### 9.2 Block Context
- [ ] Implement block header information access
- [ ] Implement blockhash calculation
- [ ] Implement block validation

### 9.3 Testing Framework
- [x] Implement simple test to verify EVM functionality
- [ ] Implement unit tests for each opcode
- [ ] Implement integration tests for complex contracts
- [ ] Implement Ethereum test suite compatibility

## 10. Performance Optimizations

### 10.1 Memory Management
- [ ] Implement memory pooling
- [ ] Implement efficient memory copying
- [ ] Implement optimized data structures

### 10.2 Execution Optimizations
- [ ] Implement bytecode analysis
- [ ] Implement jump destination analysis
- [ ] Implement common subexpression elimination

### 10.3 Gas Calculation Optimizations
- [ ] Implement gas tracking optimizations
- [ ] Implement batch gas calculations

## Implementation Priority

1. Core data structures (BigInt, Memory, Stack)
2. Basic arithmetic opcodes (ADD, MUL, SUB, DIV)
3. Memory operations (MLOAD, MSTORE, MSTORE8)
4. Stack operations (POP, DUP, SWAP)
5. Flow control (JUMP, JUMPI)
6. Storage operations (SLOAD, SSTORE)
7. Environmental operations
8. System operations (CREATE, CALL, RETURN, REVERT, SELFDESTRUCT)
9. Gas calculation and management
10. Precompiled contracts
11. Advanced features and optimizations

This plan will be updated as implementation progresses and new requirements are identified.

## Current Progress

We have successfully implemented:
- Core data structures: BigInt (add, mul), Memory, Stack
- Basic opcodes: ADD, MUL, PUSH1, POP, STOP
- Basic EVM execution framework
- Simple test demonstrating correct execution of bytecode

The EVM can now execute simple arithmetic operations correctly, as demonstrated by our test that computes (3 + 4) * 2 = 14.

### Next Steps

1. Implement more arithmetic operations (SUB, DIV)
2. Implement more stack operations (DUP, SWAP)
3. Implement memory operations (MLOAD, MSTORE, MSTORE8)
4. Implement flow control operations (JUMP, JUMPI)
5. Add more comprehensive testing