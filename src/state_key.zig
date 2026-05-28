// File: src/state_key.zig
//
// Addressable units of EVM world state, used by the serializable parallel
// execution engine (see src/mvcc.zig and src/access_set.zig).
//
// A `StateKey` identifies exactly one mutable location in the world state:
// an account's balance, its nonce, its code, or a single storage slot. This
// is the granularity at which the engine detects conflicts between
// transactions. Storage-slot granularity (rather than whole-account) is what
// lets the empirical study (paper contribution C2) quantify how much
// parallelism cheap account-level analysis leaves on the table.

const std = @import("std");
const BigInt = @import("bigint.zig").BigInt;

pub const Address = [20]u8;

pub const StateKeyTag = enum(u8) {
    balance,
    nonce,
    code,
    storage,
};

/// A single addressable location in the world state.
///
/// `slot` is only meaningful when `tag == .storage`; for the other tags it is
/// fixed to zero so that equality and hashing stay well defined.
pub const StateKey = struct {
    tag: StateKeyTag,
    address: Address,
    slot: BigInt = BigInt.zero(),

    pub fn balanceOf(address: Address) StateKey {
        return .{ .tag = .balance, .address = address };
    }

    pub fn nonceOf(address: Address) StateKey {
        return .{ .tag = .nonce, .address = address };
    }

    pub fn codeOf(address: Address) StateKey {
        return .{ .tag = .code, .address = address };
    }

    pub fn storageOf(address: Address, slot: BigInt) StateKey {
        return .{ .tag = .storage, .address = address, .slot = slot };
    }

    pub fn eql(a: StateKey, b: StateKey) bool {
        if (a.tag != b.tag) return false;
        if (!std.mem.eql(u8, &a.address, &b.address)) return false;
        if (a.tag == .storage) return a.slot.eq(b.slot);
        return true;
    }

    pub fn hash(self: StateKey) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(&[_]u8{@intFromEnum(self.tag)});
        h.update(&self.address);
        if (self.tag == .storage) {
            const slot_bytes = self.slot.toBytes();
            h.update(&slot_bytes);
        }
        return h.final();
    }
};

/// Hash-map context so `StateKey` can key a `std.HashMap` directly.
pub const StateKeyContext = struct {
    pub fn hash(_: StateKeyContext, key: StateKey) u64 {
        return key.hash();
    }
    pub fn eql(_: StateKeyContext, a: StateKey, b: StateKey) bool {
        return StateKey.eql(a, b);
    }
};

/// Convenience: a managed hash map keyed by `StateKey`.
pub fn StateKeyHashMap(comptime V: type) type {
    return std.HashMap(StateKey, V, StateKeyContext, std.hash_map.default_max_load_percentage);
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

const addr_a: Address = [_]u8{0xAA} ** 20;
const addr_b: Address = [_]u8{0xBB} ** 20;

test "distinct tags on the same address are distinct keys" {
    try testing.expect(!StateKey.balanceOf(addr_a).eql(StateKey.nonceOf(addr_a)));
    try testing.expect(!StateKey.balanceOf(addr_a).eql(StateKey.codeOf(addr_a)));
}

test "balance keys differ by address but match themselves" {
    try testing.expect(StateKey.balanceOf(addr_a).eql(StateKey.balanceOf(addr_a)));
    try testing.expect(!StateKey.balanceOf(addr_a).eql(StateKey.balanceOf(addr_b)));
}

test "storage keys distinguish slots within an account" {
    const k0 = StateKey.storageOf(addr_a, BigInt.init(0));
    const k0b = StateKey.storageOf(addr_a, BigInt.init(0));
    const k1 = StateKey.storageOf(addr_a, BigInt.init(1));
    try testing.expect(k0.eql(k0b));
    try testing.expect(!k0.eql(k1));
}

test "equal keys hash equal; storage slots hash distinctly" {
    const k0 = StateKey.storageOf(addr_a, BigInt.init(7));
    const k0b = StateKey.storageOf(addr_a, BigInt.init(7));
    const k1 = StateKey.storageOf(addr_a, BigInt.init(8));
    try testing.expectEqual(k0.hash(), k0b.hash());
    try testing.expect(k0.hash() != k1.hash());
}

test "StateKey can key a hash map at slot granularity" {
    var map = StateKeyHashMap(u64).init(testing.allocator);
    defer map.deinit();

    try map.put(StateKey.storageOf(addr_a, BigInt.init(0)), 100);
    try map.put(StateKey.storageOf(addr_a, BigInt.init(1)), 200);
    try map.put(StateKey.balanceOf(addr_a), 999);

    try testing.expectEqual(@as(?u64, 100), map.get(StateKey.storageOf(addr_a, BigInt.init(0))));
    try testing.expectEqual(@as(?u64, 200), map.get(StateKey.storageOf(addr_a, BigInt.init(1))));
    try testing.expectEqual(@as(?u64, 999), map.get(StateKey.balanceOf(addr_a)));
    try testing.expectEqual(@as(?u64, null), map.get(StateKey.storageOf(addr_b, BigInt.init(0))));
}
