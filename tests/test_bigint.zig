const std = @import("std");
const expect = std.testing.expect;
const BigInt = @import("../src/bigint.zig").BigInt;

test "BigInt initialization" {
    const a = BigInt.init(42);
    try expect(a.data[0] == 42);
    try expect(a.data[1] == 0);
    try expect(a.data[2] == 0);
    try expect(a.data[3] == 0);
}

test "BigInt addition" {
    const a = BigInt.init(10);
    const b = BigInt.init(20);
    const result = a.add(b);
    try expect(result.data[0] == 30);
}

test "BigInt addition with carry" {
    const a = BigInt{ .data = .{ 0xFFFFFFFFFFFFFFFF, 0, 0, 0 } };
    const b = BigInt.init(1);
    const result = a.add(b);
    try expect(result.data[0] == 0);
    try expect(result.data[1] == 1);
}

test "BigInt subtraction" {
    const a = BigInt.init(30);
    const b = BigInt.init(10);
    const result = a.sub(b);
    try expect(result.data[0] == 20);
}

test "BigInt multiplication" {
    const a = BigInt.init(5);
    const b = BigInt.init(7);
    const result = a.mul(b);
    try expect(result.data[0] == 35);
}

test "BigInt comparison" {
    const a = BigInt.init(10);
    const b = BigInt.init(20);
    const c = BigInt.init(10);

    try expect(a.lt(b));
    try expect(!b.lt(a));
    try expect(!a.lt(c));
}

test "BigInt large number comparison" {
    const a = BigInt{ .data = .{ 0, 0, 0, 1 } };
    const b = BigInt{ .data = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0 } };

    try expect(b.lt(a));
    try expect(!a.lt(b));
}