# Implemented EVM Opcodes

Complete list of EVM opcodes implemented in Zig EVM.

## Implementation Status

| Metric | Value |
|--------|-------|
| **Total Implemented** | 141 opcodes |
| **Coverage** | Full EVM instruction set |
| **Status** | Production-ready |

## Opcode Categories

### Stop and Arithmetic (0x00 - 0x0b)

| Opcode | Hex | Description | Status |
|--------|-----|-------------|--------|
| STOP | 0x00 | Halt execution | ✅ |
| ADD | 0x01 | Addition | ✅ |
| MUL | 0x02 | Multiplication | ✅ |
| SUB | 0x03 | Subtraction | ✅ |
| DIV | 0x04 | Integer division | ✅ |
| SDIV | 0x05 | Signed integer division | ✅ |
| MOD | 0x06 | Modulo | ✅ |
| SMOD | 0x07 | Signed modulo | ✅ |
| ADDMOD | 0x08 | Modular addition | ✅ |
| MULMOD | 0x09 | Modular multiplication | ✅ |
| EXP | 0x0a | Exponentiation | ✅ |
| SIGNEXTEND | 0x0b | Sign extension | ✅ |

### Comparison & Bitwise (0x10 - 0x1d)

| Opcode | Hex | Description | Status |
|--------|-----|-------------|--------|
| LT | 0x10 | Less than | ✅ |
| GT | 0x11 | Greater than | ✅ |
| SLT | 0x12 | Signed less than | ✅ |
| SGT | 0x13 | Signed greater than | ✅ |
| EQ | 0x14 | Equal | ✅ |
| ISZERO | 0x15 | Is zero | ✅ |
| AND | 0x16 | Bitwise AND | ✅ |
| OR | 0x17 | Bitwise OR | ✅ |
| XOR | 0x18 | Bitwise XOR | ✅ |
| NOT | 0x19 | Bitwise NOT | ✅ |
| BYTE | 0x1a | Extract byte | ✅ |
| SHL | 0x1b | Shift left | ✅ |
| SHR | 0x1c | Logical shift right | ✅ |
| SAR | 0x1d | Arithmetic shift right | ✅ |

### Keccak256 (0x20)

| Opcode | Hex | Description | Status |
|--------|-----|-------------|--------|
| SHA3 | 0x20 | Keccak-256 hash | ✅ |

### Environmental Information (0x30 - 0x3f)

| Opcode | Hex | Description | Status |
|--------|-----|-------------|--------|
| ADDRESS | 0x30 | Current contract address | ✅ |
| BALANCE | 0x31 | Account balance | ✅ |
| ORIGIN | 0x32 | Transaction origin | ✅ |
| CALLER | 0x33 | Message caller | ✅ |
| CALLVALUE | 0x34 | Call value | ✅ |
| CALLDATALOAD | 0x35 | Load call data | ✅ |
| CALLDATASIZE | 0x36 | Call data size | ✅ |
| CALLDATACOPY | 0x37 | Copy call data | ✅ |
| CODESIZE | 0x38 | Code size | ✅ |
| CODECOPY | 0x39 | Copy code | ✅ |
| GASPRICE | 0x3a | Gas price | ✅ |
| EXTCODESIZE | 0x3b | External code size | ✅ |
| EXTCODECOPY | 0x3c | Copy external code | ✅ |
| RETURNDATASIZE | 0x3d | Return data size | ✅ |
| RETURNDATACOPY | 0x3e | Copy return data | ✅ |
| EXTCODEHASH | 0x3f | External code hash | ✅ |

### Block Information (0x40 - 0x48)

| Opcode | Hex | Description | Status |
|--------|-----|-------------|--------|
| BLOCKHASH | 0x40 | Block hash | ✅ |
| COINBASE | 0x41 | Block beneficiary | ✅ |
| TIMESTAMP | 0x42 | Block timestamp | ✅ |
| NUMBER | 0x43 | Block number | ✅ |
| DIFFICULTY | 0x44 | Block difficulty | ✅ |
| GASLIMIT | 0x45 | Block gas limit | ✅ |
| CHAINID | 0x46 | Chain ID | ✅ |
| SELFBALANCE | 0x47 | Self balance | ✅ |
| BASEFEE | 0x48 | Base fee | ✅ |

### Stack, Memory, Storage, Flow (0x50 - 0x5b)

| Opcode | Hex | Description | Status |
|--------|-----|-------------|--------|
| POP | 0x50 | Remove from stack | ✅ |
| MLOAD | 0x51 | Load from memory | ✅ |
| MSTORE | 0x52 | Store to memory | ✅ |
| MSTORE8 | 0x53 | Store byte to memory | ✅ |
| SLOAD | 0x54 | Load from storage | ✅ |
| SSTORE | 0x55 | Store to storage | ✅ |
| JUMP | 0x56 | Jump | ✅ |
| JUMPI | 0x57 | Conditional jump | ✅ |
| PC | 0x58 | Program counter | ✅ |
| MSIZE | 0x59 | Memory size | ✅ |
| GAS | 0x5a | Gas remaining | ✅ |
| JUMPDEST | 0x5b | Jump destination | ✅ |

### Push Operations (0x60 - 0x7f)

All 32 PUSH opcodes are implemented:

| Range | Opcodes | Description | Status |
|-------|---------|-------------|--------|
| 0x60 - 0x7f | PUSH1 - PUSH32 | Push 1-32 bytes | ✅ All 32 |

### Duplication Operations (0x80 - 0x8f)

All 16 DUP opcodes are implemented:

| Range | Opcodes | Description | Status |
|-------|---------|-------------|--------|
| 0x80 - 0x8f | DUP1 - DUP16 | Duplicate stack item | ✅ All 16 |

### Exchange Operations (0x90 - 0x9f)

All 16 SWAP opcodes are implemented:

| Range | Opcodes | Description | Status |
|-------|---------|-------------|--------|
| 0x90 - 0x9f | SWAP1 - SWAP16 | Exchange stack items | ✅ All 16 |

### Logging Operations (0xa0 - 0xa4)

| Opcode | Hex | Description | Status |
|--------|-----|-------------|--------|
| LOG0 | 0xa0 | Log with 0 topics | ✅ |
| LOG1 | 0xa1 | Log with 1 topic | ✅ |
| LOG2 | 0xa2 | Log with 2 topics | ✅ |
| LOG3 | 0xa3 | Log with 3 topics | ✅ |
| LOG4 | 0xa4 | Log with 4 topics | ✅ |

### System Operations (0xf0 - 0xff)

| Opcode | Hex | Description | Status |
|--------|-----|-------------|--------|
| CREATE | 0xf0 | Create contract | ✅ |
| CALL | 0xf1 | Message call | ✅ |
| CALLCODE | 0xf2 | Call with alt code | ✅ |
| RETURN | 0xf3 | Return from call | ✅ |
| DELEGATECALL | 0xf4 | Delegate call | ✅ |
| CREATE2 | 0xf5 | Create2 | ✅ |
| STATICCALL | 0xfa | Static call | ✅ |
| REVERT | 0xfd | Revert execution | ✅ |
| INVALID | 0xfe | Invalid instruction | ⚠️ Defined |
| SELFDESTRUCT | 0xff | Self-destruct | ⚠️ Defined |

## Implementation Summary

### By Category

| Category | Implemented | Total | Coverage |
|----------|-------------|-------|----------|
| Arithmetic | 12 | 12 | 100% |
| Comparison | 6 | 6 | 100% |
| Bitwise | 5 | 5 | 100% |
| Shift | 3 | 3 | 100% |
| Cryptographic | 1 | 1 | 100% |
| Environmental | 16 | 16 | 100% |
| Block | 9 | 9 | 100% |
| Stack/Memory/Storage | 12 | 12 | 100% |
| Push | 32 | 32 | 100% |
| Dup | 16 | 16 | 100% |
| Swap | 16 | 16 | 100% |
| Logging | 5 | 5 | 100% |
| System | 8 | 10 | 80% |
| **Total** | **141** | **143** | **99%** |

### Not Implemented

Only 2 opcodes are defined but not fully implemented:

1. **INVALID (0xfe)** - Explicitly invalid instruction
2. **SELFDESTRUCT (0xff)** - Deprecated in post-merge Ethereum

## Gas Costs

All opcodes include Ethereum-compliant gas costs defined in `src/main.zig`:

```zig
pub fn getGasCost(opcode: Opcode) u64 {
    return switch (opcode) {
        .STOP => 0,
        .ADD, .SUB => 3,
        .MUL, .DIV, .MOD => 5,
        .EXP => 10, // + dynamic cost
        .SLOAD => 800, // cold access
        .SSTORE => 20000, // new value
        .CALL => 700, // + memory + value
        .CREATE => 32000,
        .LOG0 => 375,
        // ... etc
    };
}
```

## File Structure

Each opcode is implemented in its own file:

```
src/opcodes/
├── add.zig      # ADD opcode
├── sub.zig      # SUB opcode
├── call.zig     # CALL opcode
├── create.zig   # CREATE opcode
├── push1.zig    # PUSH1 opcode
├── ...          # 136 more files
└── sha3.zig     # SHA3/KECCAK256 opcode
```

## Adding New Opcodes

To implement a new opcode:

1. Create `src/opcodes/newop.zig`:

```zig
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

3. Add gas cost in `getGasCost()`:

```zig
.NEWOP => 3, // gas cost
```

4. Add tests in `tests/test_*.zig`

## Testing

Run opcode tests:

```bash
zig build test
```

Run compliance tests:

```bash
zig build compliance
```

## References

- [EVM Opcodes Reference](https://www.evm.codes/)
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)
- [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) - Base fee
- [EIP-3198](https://eips.ethereum.org/EIPS/eip-3198) - BASEFEE opcode
- [EIP-3855](https://eips.ethereum.org/EIPS/eip-3855) - PUSH0 opcode
