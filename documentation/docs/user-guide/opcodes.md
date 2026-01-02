# Opcodes

Complete reference for EVM opcodes implemented in Zig EVM.

## Implementation Status

| Metric | Value |
|--------|-------|
| **Total Implemented** | 141 opcodes |
| **Coverage** | Full EVM instruction set |
| **Status** | Production-ready |

## Opcode Categories

### Stop and Arithmetic (0x00 - 0x0b)

| Opcode | Hex | Description | Gas | Stack |
|--------|-----|-------------|-----|-------|
| STOP | 0x00 | Halt execution | 0 | 0 -> 0 |
| ADD | 0x01 | Addition | 3 | 2 -> 1 |
| MUL | 0x02 | Multiplication | 5 | 2 -> 1 |
| SUB | 0x03 | Subtraction | 3 | 2 -> 1 |
| DIV | 0x04 | Integer division | 5 | 2 -> 1 |
| SDIV | 0x05 | Signed division | 5 | 2 -> 1 |
| MOD | 0x06 | Modulo | 5 | 2 -> 1 |
| SMOD | 0x07 | Signed modulo | 5 | 2 -> 1 |
| ADDMOD | 0x08 | Modular addition | 8 | 3 -> 1 |
| MULMOD | 0x09 | Modular multiplication | 8 | 3 -> 1 |
| EXP | 0x0a | Exponentiation | 10+ | 2 -> 1 |
| SIGNEXTEND | 0x0b | Sign extension | 5 | 2 -> 1 |

### Comparison & Bitwise (0x10 - 0x1d)

| Opcode | Hex | Description | Gas | Stack |
|--------|-----|-------------|-----|-------|
| LT | 0x10 | Less than | 3 | 2 -> 1 |
| GT | 0x11 | Greater than | 3 | 2 -> 1 |
| SLT | 0x12 | Signed less than | 3 | 2 -> 1 |
| SGT | 0x13 | Signed greater than | 3 | 2 -> 1 |
| EQ | 0x14 | Equal | 3 | 2 -> 1 |
| ISZERO | 0x15 | Is zero | 3 | 1 -> 1 |
| AND | 0x16 | Bitwise AND | 3 | 2 -> 1 |
| OR | 0x17 | Bitwise OR | 3 | 2 -> 1 |
| XOR | 0x18 | Bitwise XOR | 3 | 2 -> 1 |
| NOT | 0x19 | Bitwise NOT | 3 | 1 -> 1 |
| BYTE | 0x1a | Extract byte | 3 | 2 -> 1 |
| SHL | 0x1b | Shift left | 3 | 2 -> 1 |
| SHR | 0x1c | Logical shift right | 3 | 2 -> 1 |
| SAR | 0x1d | Arithmetic shift right | 3 | 2 -> 1 |

### Keccak256 (0x20)

| Opcode | Hex | Description | Gas | Stack |
|--------|-----|-------------|-----|-------|
| SHA3 | 0x20 | Keccak-256 hash | 30+ | 2 -> 1 |

### Environmental Information (0x30 - 0x3f)

| Opcode | Hex | Description | Gas | Stack |
|--------|-----|-------------|-----|-------|
| ADDRESS | 0x30 | Current contract address | 2 | 0 -> 1 |
| BALANCE | 0x31 | Account balance | 100-2600 | 1 -> 1 |
| ORIGIN | 0x32 | Transaction origin | 2 | 0 -> 1 |
| CALLER | 0x33 | Message caller | 2 | 0 -> 1 |
| CALLVALUE | 0x34 | Call value | 2 | 0 -> 1 |
| CALLDATALOAD | 0x35 | Load call data | 3 | 1 -> 1 |
| CALLDATASIZE | 0x36 | Call data size | 2 | 0 -> 1 |
| CALLDATACOPY | 0x37 | Copy call data | 3+ | 3 -> 0 |
| CODESIZE | 0x38 | Code size | 2 | 0 -> 1 |
| CODECOPY | 0x39 | Copy code | 3+ | 3 -> 0 |
| GASPRICE | 0x3a | Gas price | 2 | 0 -> 1 |
| EXTCODESIZE | 0x3b | External code size | 100-2600 | 1 -> 1 |
| EXTCODECOPY | 0x3c | Copy external code | 100+ | 4 -> 0 |
| RETURNDATASIZE | 0x3d | Return data size | 2 | 0 -> 1 |
| RETURNDATACOPY | 0x3e | Copy return data | 3+ | 3 -> 0 |
| EXTCODEHASH | 0x3f | External code hash | 100-2600 | 1 -> 1 |

### Block Information (0x40 - 0x48)

| Opcode | Hex | Description | Gas | Stack |
|--------|-----|-------------|-----|-------|
| BLOCKHASH | 0x40 | Block hash | 20 | 1 -> 1 |
| COINBASE | 0x41 | Block beneficiary | 2 | 0 -> 1 |
| TIMESTAMP | 0x42 | Block timestamp | 2 | 0 -> 1 |
| NUMBER | 0x43 | Block number | 2 | 0 -> 1 |
| DIFFICULTY | 0x44 | Block difficulty | 2 | 0 -> 1 |
| GASLIMIT | 0x45 | Block gas limit | 2 | 0 -> 1 |
| CHAINID | 0x46 | Chain ID | 2 | 0 -> 1 |
| SELFBALANCE | 0x47 | Self balance | 5 | 0 -> 1 |
| BASEFEE | 0x48 | Base fee | 2 | 0 -> 1 |

### Stack, Memory, Storage, Flow (0x50 - 0x5b)

| Opcode | Hex | Description | Gas | Stack |
|--------|-----|-------------|-----|-------|
| POP | 0x50 | Remove from stack | 2 | 1 -> 0 |
| MLOAD | 0x51 | Load from memory | 3+ | 1 -> 1 |
| MSTORE | 0x52 | Store to memory | 3+ | 2 -> 0 |
| MSTORE8 | 0x53 | Store byte to memory | 3+ | 2 -> 0 |
| SLOAD | 0x54 | Load from storage | 100-2100 | 1 -> 1 |
| SSTORE | 0x55 | Store to storage | 100-20000 | 2 -> 0 |
| JUMP | 0x56 | Jump | 8 | 1 -> 0 |
| JUMPI | 0x57 | Conditional jump | 10 | 2 -> 0 |
| PC | 0x58 | Program counter | 2 | 0 -> 1 |
| MSIZE | 0x59 | Memory size | 2 | 0 -> 1 |
| GAS | 0x5a | Gas remaining | 2 | 0 -> 1 |
| JUMPDEST | 0x5b | Jump destination | 1 | 0 -> 0 |

### Push Operations (0x60 - 0x7f)

All 32 PUSH opcodes push 1-32 bytes onto the stack.

| Opcode | Hex | Description | Gas |
|--------|-----|-------------|-----|
| PUSH1 | 0x60 | Push 1 byte | 3 |
| PUSH2 | 0x61 | Push 2 bytes | 3 |
| ... | ... | ... | 3 |
| PUSH32 | 0x7f | Push 32 bytes | 3 |

### Duplication Operations (0x80 - 0x8f)

All 16 DUP opcodes duplicate a stack item.

| Opcode | Hex | Description | Gas |
|--------|-----|-------------|-----|
| DUP1 | 0x80 | Duplicate 1st stack item | 3 |
| DUP2 | 0x81 | Duplicate 2nd stack item | 3 |
| ... | ... | ... | 3 |
| DUP16 | 0x8f | Duplicate 16th stack item | 3 |

### Exchange Operations (0x90 - 0x9f)

All 16 SWAP opcodes exchange stack items.

| Opcode | Hex | Description | Gas |
|--------|-----|-------------|-----|
| SWAP1 | 0x90 | Exchange 1st and 2nd | 3 |
| SWAP2 | 0x91 | Exchange 1st and 3rd | 3 |
| ... | ... | ... | 3 |
| SWAP16 | 0x9f | Exchange 1st and 17th | 3 |

### Logging Operations (0xa0 - 0xa4)

| Opcode | Hex | Description | Gas | Stack |
|--------|-----|-------------|-----|-------|
| LOG0 | 0xa0 | Log with 0 topics | 375+ | 2 -> 0 |
| LOG1 | 0xa1 | Log with 1 topic | 750+ | 3 -> 0 |
| LOG2 | 0xa2 | Log with 2 topics | 1125+ | 4 -> 0 |
| LOG3 | 0xa3 | Log with 3 topics | 1500+ | 5 -> 0 |
| LOG4 | 0xa4 | Log with 4 topics | 1875+ | 6 -> 0 |

### System Operations (0xf0 - 0xff)

| Opcode | Hex | Description | Gas | Stack |
|--------|-----|-------------|-----|-------|
| CREATE | 0xf0 | Create contract | 32000 | 3 -> 1 |
| CALL | 0xf1 | Message call | 100+ | 7 -> 1 |
| CALLCODE | 0xf2 | Call with alt code | 100+ | 7 -> 1 |
| RETURN | 0xf3 | Return from call | 0 | 2 -> 0 |
| DELEGATECALL | 0xf4 | Delegate call | 100+ | 6 -> 1 |
| CREATE2 | 0xf5 | Create2 | 32000 | 4 -> 1 |
| STATICCALL | 0xfa | Static call | 100+ | 6 -> 1 |
| REVERT | 0xfd | Revert execution | 0 | 2 -> 0 |
| INVALID | 0xfe | Invalid instruction | - | - |
| SELFDESTRUCT | 0xff | Self-destruct | 5000+ | 1 -> 0 |

## Example Usage

### Arithmetic

```
# Calculate (3 + 5) * 2 = 16
PUSH1 0x03    # Stack: [3]
PUSH1 0x05    # Stack: [5, 3]
ADD           # Stack: [8]
PUSH1 0x02    # Stack: [2, 8]
MUL           # Stack: [16]
```

### Memory Operations

```
# Store 42 at offset 0
PUSH1 0x2a    # Stack: [42]
PUSH1 0x00    # Stack: [0, 42]
MSTORE        # Memory[0:32] = 42

# Load from offset 0
PUSH1 0x00    # Stack: [0]
MLOAD         # Stack: [42]
```

### Control Flow

```
# Conditional jump
PUSH1 0x01    # Stack: [1] (true)
PUSH1 0x10    # Stack: [16, 1] (destination)
JUMPI         # Jump to offset 16 if true

# At offset 16:
JUMPDEST      # Valid jump destination
```

### Storage

```
# Store value at slot 0
PUSH1 0x64    # Stack: [100]
PUSH1 0x00    # Stack: [0, 100]
SSTORE        # Storage[0] = 100

# Load from slot 0
PUSH1 0x00    # Stack: [0]
SLOAD         # Stack: [100]
```

## Adding Custom Opcodes

To implement a new opcode:

1. Create the implementation file:

```zig
// src/opcodes/newop.zig
const std = @import("std");
const EVM = @import("../main.zig").EVM;
const OpcodeImpl = @import("../main.zig").OpcodeImpl;
const Opcode = @import("../main.zig").Opcode;

pub fn getImpl() struct { code: u8, impl: OpcodeImpl } {
    return .{
        .code = @intFromEnum(Opcode.NEWOP),
        .impl = OpcodeImpl{ .execute = execute },
    };
}

fn execute(evm: *EVM) !void {
    // Implementation here
}
```

2. Register in `src/main.zig`:

```zig
fn loadOpcodes(self: *EVM) !void {
    // ... existing opcodes ...
    try self.registerOpcode(@import("opcodes/newop.zig").getImpl());
}
```

3. Add gas cost:

```zig
.NEWOP => 3, // gas cost
```

4. Add tests in `tests/test_*.zig`

## References

- [EVM Opcodes Reference](https://www.evm.codes/)
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)
- [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) - Base fee
- [EIP-3198](https://eips.ethereum.org/EIPS/eip-3198) - BASEFEE opcode
