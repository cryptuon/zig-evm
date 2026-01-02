# Contributing

Guidelines for contributing to Zig EVM.

## Getting Started

### Prerequisites

- Zig 0.13.0 or later
- Git
- Basic understanding of EVM

### Setup

```bash
# Fork and clone the repository
git clone https://github.com/YOUR_USERNAME/zig-evm.git
cd zig-evm

# Build and test
zig build test
zig build run
```

## Development Workflow

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/issue-description
```

### 2. Make Changes

- Follow the coding style
- Add tests for new functionality
- Update documentation as needed

### 3. Run Tests

```bash
# Run all tests
zig build test

# Run specific test file
zig test tests/test_opcodes.zig

# Run with optimization
zig build test -Doptimize=ReleaseFast
```

### 4. Submit Pull Request

- Write a clear PR description
- Reference any related issues
- Ensure CI passes

## Code Style

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Functions | camelCase | `executeOpcode` |
| Types | PascalCase | `BigInt` |
| Constants | SCREAMING_SNAKE | `MAX_STACK_SIZE` |
| Variables | snake_case | `gas_used` |

### Formatting

Use `zig fmt` to format code:

```bash
zig fmt src/main.zig
zig fmt src/**/*.zig
```

### Documentation

Add doc comments for public APIs:

```zig
/// Executes a single opcode at the current program counter.
///
/// Returns an error if the opcode fails or gas is exhausted.
pub fn executeOpcode(self: *EVM) !void {
    // ...
}
```

## Adding Opcodes

### 1. Create Implementation File

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
    // Get operands from stack
    const a = evm.stack.pop() orelse return error.StackUnderflow;
    const b = evm.stack.pop() orelse return error.StackUnderflow;

    // Perform operation
    const result = a.someOperation(b);

    // Push result
    try evm.stack.push(result);
}
```

### 2. Register Opcode

In `src/main.zig`:

```zig
fn loadOpcodes(self: *EVM) !void {
    // ... existing opcodes ...
    try self.registerOpcode(@import("opcodes/newop.zig").getImpl());
}
```

### 3. Add Gas Cost

In `getGasCost()` function:

```zig
.NEWOP => 3, // or appropriate gas cost
```

### 4. Add Tests

```zig
// tests/test_newop.zig
test "NEWOP basic" {
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // PUSH1 5, PUSH1 3, NEWOP
    evm.code = &[_]u8{ 0x60, 0x05, 0x60, 0x03, 0xXX };
    evm.setGasLimit(100000);

    try evm.execute();

    const result = evm.stack.pop().?;
    try testing.expectEqual(@as(u64, expected_value), result.data[0]);
}
```

## Testing

### Test Structure

```
tests/
├── test_bigint.zig       # BigInt arithmetic
├── test_opcodes.zig      # Basic opcode tests
├── test_arithmetic.zig   # Arithmetic operations
├── test_stack_ops.zig    # Stack manipulation
├── test_memory.zig       # Memory operations
├── test_storage.zig      # Storage operations
├── test_call.zig         # Call operations
└── test_parallel.zig     # Parallel execution
```

### Writing Tests

```zig
const testing = std.testing;

test "opcode does expected thing" {
    // Setup
    var evm = try EVM.init(testing.allocator);
    defer evm.deinit();

    // Configure
    evm.code = &[_]u8{ /* bytecode */ };
    evm.setGasLimit(100000);

    // Execute
    try evm.execute();

    // Verify
    const result = evm.stack.pop().?;
    try testing.expectEqual(expected, result);
}
```

### Running Specific Tests

```bash
# Run a specific test
zig build test --test-filter "NEWOP basic"

# Run tests in a specific file
zig test tests/test_opcodes.zig
```

## Documentation

### Adding Documentation

1. Update relevant `.md` files in `documentation/docs/`
2. Add examples for new features
3. Update API reference if needed

### Building Documentation

```bash
cd documentation
pip install mkdocs-material
mkdocs serve  # Preview at localhost:8000
mkdocs build  # Build static site
```

## Pull Request Guidelines

### PR Checklist

- [ ] Code follows style guidelines
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] CI passes
- [ ] No merge conflicts

### PR Template

```markdown
## Description
Brief description of changes.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
How was this tested?

## Related Issues
Fixes #123
```

### Review Process

1. Automated CI checks
2. Code review by maintainers
3. Address feedback
4. Merge when approved

## Reporting Issues

### Bug Reports

Include:

1. Zig version
2. OS and version
3. Steps to reproduce
4. Expected vs actual behavior
5. Minimal reproducing code

### Feature Requests

Include:

1. Use case description
2. Proposed solution
3. Alternative approaches considered

## Community

### Communication

- GitHub Issues: Bug reports and features
- GitHub Discussions: Questions and ideas
- Pull Requests: Code contributions

### Code of Conduct

- Be respectful
- Be constructive
- Help others learn

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Recognition

Contributors are recognized in:

- CONTRIBUTORS.md file
- Release notes
- GitHub contributors page
