# Implemented EVM Opcodes

This document lists all currently implemented EVM opcodes in the Zig EVM project.

## Implementation Status

**Total Implemented**: 96 opcodes
**Implementation Coverage**: Core EVM instruction set
**Status**: Functional and tested

## Opcode Categories

### Arithmetic Operations (12 opcodes)
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| STOP   | 0x00 | Halt execution | ✅ stop.zig |
| ADD    | 0x01 | Addition | ✅ add.zig |
| MUL    | 0x02 | Multiplication | ✅ mul.zig |
| SUB    | 0x03 | Subtraction | ✅ sub.zig |
| DIV    | 0x04 | Integer division | ✅ div.zig |
| SDIV   | 0x05 | Signed integer division | ✅ sdiv.zig |
| MOD    | 0x06 | Modulo | ✅ mod.zig |
| SMOD   | 0x07 | Signed modulo | ✅ smod.zig |
| ADDMOD | 0x08 | Modular addition | ✅ addmod.zig |
| MULMOD | 0x09 | Modular multiplication | ✅ mulmod.zig |
| EXP    | 0x0a | Exponentiation | ✅ exp.zig |
| SIGNEXTEND | 0x0b | Sign extension | ❌ (defined but not implemented) |

### Comparison Operations (6 opcodes)
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| LT     | 0x10 | Less than | ✅ lt.zig |
| GT     | 0x11 | Greater than | ✅ gt.zig |
| SLT    | 0x12 | Signed less than | ✅ slt.zig |
| SGT    | 0x13 | Signed greater than | ✅ sgt.zig |
| EQ     | 0x14 | Equal | ✅ eq.zig |
| ISZERO | 0x15 | Is zero | ✅ iszero.zig |

### Bitwise Operations (5 opcodes)
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| AND    | 0x16 | Bitwise AND | ✅ and.zig |
| OR     | 0x17 | Bitwise OR | ✅ or.zig |
| XOR    | 0x18 | Bitwise XOR | ✅ xor.zig |
| NOT    | 0x19 | Bitwise NOT | ✅ not.zig |
| BYTE   | 0x1a | Byte at index | ❌ (defined but not implemented) |

### Shift Operations (3 opcodes)
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| SHL    | 0x1b | Shift left | ✅ shl.zig |
| SHR    | 0x1c | Shift right | ✅ shr.zig |
| SAR    | 0x1d | Arithmetic shift right | ✅ sar.zig |

### Cryptographic Operations (1 opcode)
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| SHA3   | 0x20 | Keccak-256 hash | ❌ (defined but not implemented) |

### Environmental Information (15 opcodes)
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| ADDRESS | 0x30 | Current contract address | ✅ address.zig |
| BALANCE | 0x31 | Account balance | ✅ balance.zig |
| ORIGIN  | 0x32 | Transaction origin | ✅ origin.zig |
| CALLER  | 0x33 | Message caller | ✅ caller.zig |
| CALLVALUE | 0x34 | Call value | ❌ (defined but not implemented) |
| CALLDATALOAD | 0x35 | Load call data | ❌ (defined but not implemented) |
| CALLDATASIZE | 0x36 | Call data size | ❌ (defined but not implemented) |
| CALLDATACOPY | 0x37 | Copy call data | ❌ (defined but not implemented) |
| CODESIZE | 0x38 | Code size | ❌ (defined but not implemented) |
| CODECOPY | 0x39 | Copy code | ❌ (defined but not implemented) |
| GASPRICE | 0x3a | Gas price | ✅ gasprice.zig |
| EXTCODESIZE | 0x3b | External code size | ❌ (defined but not implemented) |
| EXTCODECOPY | 0x3c | Copy external code | ❌ (defined but not implemented) |
| RETURNDATASIZE | 0x3d | Return data size | ❌ (defined but not implemented) |
| RETURNDATACOPY | 0x3e | Copy return data | ❌ (defined but not implemented) |
| EXTCODEHASH | 0x3f | External code hash | ❌ (defined but not implemented) |

### Block Information (9 opcodes)
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| BLOCKHASH | 0x40 | Block hash | ❌ (defined but not implemented) |
| COINBASE | 0x41 | Block beneficiary | ❌ (defined but not implemented) |
| TIMESTAMP | 0x42 | Block timestamp | ✅ timestamp.zig |
| NUMBER | 0x43 | Block number | ✅ number.zig |
| DIFFICULTY | 0x44 | Block difficulty | ✅ difficulty.zig |
| GASLIMIT | 0x45 | Block gas limit | ✅ gaslimit.zig |
| CHAINID | 0x46 | Chain ID | ✅ chainid.zig |
| SELFBALANCE | 0x47 | Self balance | ✅ selfbalance.zig |
| BASEFEE | 0x48 | Base fee | ✅ basefee.zig |

### Stack, Memory, Storage, and Flow (7 opcodes)
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| POP    | 0x50 | Remove from stack | ✅ pop.zig |
| MLOAD  | 0x51 | Load from memory | ✅ mload.zig |
| MSTORE | 0x52 | Store to memory | ✅ mstore.zig |
| MSTORE8 | 0x53 | Store byte to memory | ✅ mstore8.zig |
| SLOAD  | 0x54 | Load from storage | ❌ (defined but not implemented) |
| SSTORE | 0x55 | Store to storage | ❌ (defined but not implemented) |
| JUMP   | 0x56 | Jump | ✅ jump.zig |
| JUMPI  | 0x57 | Conditional jump | ✅ jumpi.zig |
| PC     | 0x58 | Program counter | ✅ pc.zig |
| MSIZE  | 0x59 | Memory size | ✅ msize.zig |
| GAS    | 0x5a | Gas remaining | ✅ gas.zig |
| JUMPDEST | 0x5b | Jump destination | ✅ jumpdest.zig |

### Push Operations (32 opcodes)
All PUSH operations are implemented (push1.zig through push32.zig):

| Range | Description | Implementation |
|-------|-------------|----------------|
| PUSH1-PUSH32 | 0x60-0x7f | Push 1-32 bytes onto stack | ✅ All implemented |

### Duplicate Operations (16 opcodes)
All DUP operations are implemented (dup1.zig through dup16.zig):

| Range | Description | Implementation |
|-------|-------------|----------------|
| DUP1-DUP16 | 0x80-0x8f | Duplicate nth stack item | ✅ All implemented |

### Exchange Operations (16 opcodes)
All SWAP operations are implemented (swap1.zig through swap16.zig):

| Range | Description | Implementation |
|-------|-------------|----------------|
| SWAP1-SWAP16 | 0x90-0x9f | Exchange top with nth stack item | ✅ All implemented |

### Logging Operations
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| LOG0-LOG4 | 0xa0-0xa4 | Emit log records | ❌ (defined but not implemented) |

### System Operations
| Opcode | Hex  | Description | Implementation |
|--------|------|-------------|----------------|
| CREATE | 0xf0 | Create contract | ❌ (defined but not implemented) |
| CALL   | 0xf1 | Message call | ❌ (defined but not implemented) |
| CALLCODE | 0xf2 | Message call with alternative code | ❌ (defined but not implemented) |
| RETURN | 0xf3 | Return from function | ❌ (defined but not implemented) |
| DELEGATECALL | 0xf4 | Delegate message call | ❌ (defined but not implemented) |
| CREATE2 | 0xf5 | Create contract with deterministic address | ❌ (defined but not implemented) |
| STATICCALL | 0xfa | Static message call | ❌ (defined but not implemented) |
| REVERT | 0xfd | Revert state changes | ❌ (defined but not implemented) |
| INVALID | 0xfe | Invalid operation | ❌ (defined but not implemented) |
| SELFDESTRUCT | 0xff | Self-destruct contract | ❌ (defined but not implemented) |

## Implementation Summary

### Fully Implemented Categories
- **Arithmetic Operations**: 11/12 opcodes (92%)
- **Comparison Operations**: 6/6 opcodes (100%)
- **Bitwise Operations**: 4/5 opcodes (80%)
- **Shift Operations**: 3/3 opcodes (100%)
- **Stack Operations**: 65/65 opcodes (100%)
  - PUSH1-PUSH32: 32/32 opcodes
  - DUP1-DUP16: 16/16 opcodes
  - SWAP1-SWAP16: 16/16 opcodes
  - POP: 1/1 opcode
- **Memory Operations**: 4/4 implemented opcodes (100%)
- **Flow Control**: 4/4 implemented opcodes (100%)
- **Environmental Context**: 8/15 opcodes (53%)

### Not Yet Implemented
- Storage operations (SLOAD, SSTORE)
- Contract operations (CREATE, CALL, RETURN, etc.)
- Cryptographic operations (SHA3)
- Call data operations
- Logging operations
- Some environmental operations

## Gas Costs

All implemented opcodes include proper gas cost calculations matching Ethereum specifications. Gas costs are defined in the `getGasCost()` function in `src/main.zig`.

## Testing

Each implemented opcode has corresponding test cases. Run tests with:
```bash
zig build test
```

## Usage Example

```zig
// Execute bytecode: PUSH1 3, PUSH1 4, ADD, STOP
const bytecode = [_]u8{ 0x60, 0x03, 0x60, 0x04, 0x01, 0x00 };
evm.code = &bytecode;
try evm.execute();
// Stack contains: [7] (3 + 4)
```

## Contributing

To implement a new opcode:
1. Create the opcode file in `src/opcodes/`
2. Register it in `loadOpcodes()` function
3. Add gas cost in `getGasCost()` function
4. Write tests for the opcode

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.