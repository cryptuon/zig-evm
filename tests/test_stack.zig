const std = @import("std");
const expect = std.testing.expect;
const Stack = @import("../src/stack.zig").Stack;
const BigInt = @import("../src/bigint.zig").BigInt;

test "Stack initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    try expect(stack.items.items.len == 0);
}

test "Stack push and pop" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    const value = BigInt.init(42);
    try stack.push(allocator, value);

    if (stack.pop()) |popped| {
        try expect(popped.data[0] == 42);
    } else {
        try expect(false); // Should not be empty
    }
}

test "Stack overflow protection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    const value = BigInt.init(1);

    // Fill stack to limit
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        try stack.push(allocator, value);
    }

    // This should fail with StackOverflow
    const result = stack.push(allocator, value);
    try expect(result == error.StackOverflow);
}

test "Stack underflow protection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    const result = stack.pop();
    try expect(result == null);
}

test "Stack LIFO behavior" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stack = Stack.init(allocator);
    defer stack.deinit(allocator);

    try stack.push(allocator, BigInt.init(1));
    try stack.push(allocator, BigInt.init(2));
    try stack.push(allocator, BigInt.init(3));

    if (stack.pop()) |val| try expect(val.data[0] == 3);
    if (stack.pop()) |val| try expect(val.data[0] == 2);
    if (stack.pop()) |val| try expect(val.data[0] == 1);
}