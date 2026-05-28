// File: src/mvcc.zig
//
// Multi-version memory (MVMemory) for the serializable parallel EVM engine.
//
// This is the shared, versioned state store at the heart of a Block-STM-style
// optimistic concurrency-control scheme (Gelashvili et al., "Block-STM"). It
// replaces the previous engine's *isolated* per-transaction state — which
// produced non-serializable results — with a single store in which every
// write is tagged with the writing transaction's index and incarnation.
//
// Invariant of optimistic block execution: a transaction at index `i` reads
// the value written by the *highest-indexed transaction below i* that wrote
// the same key. If that writer's value is still an ESTIMATE (the writer was
// aborted and is being re-executed), the reader has a dependency and must
// wait / abort. Validating that each recorded read still resolves to the same
// version is what makes the parallel schedule equivalent to the sequential
// one (serializability).
//
// This module implements the versioned store and its read/write/validate
// primitives. The collaborative scheduler (execution + validation tasks with
// re-execution on abort) is a separate milestone (src/block_stm.zig, planned).

const std = @import("std");
const Allocator = std.mem.Allocator;
const BigInt = @import("bigint.zig").BigInt;
const sk = @import("state_key.zig");
const StateKey = sk.StateKey;

/// Identifies a particular write: which transaction produced it, and on which
/// re-execution (incarnation) of that transaction.
pub const Version = struct {
    tx_index: usize,
    incarnation: usize,

    pub fn eql(a: Version, b: Version) bool {
        return a.tx_index == b.tx_index and a.incarnation == b.incarnation;
    }
};

/// One versioned write of a single key. All EVM values (balances, nonces,
/// storage words) are represented as a 256-bit `BigInt`; code versioning is
/// out of scope for now (handled at commit time on CREATE).
const VersionEntry = struct {
    version: Version,
    value: BigInt,
    /// When true, the writing transaction was aborted and is being
    /// re-executed; the value is stale and readers must treat it as a
    /// dependency rather than a concrete value.
    is_estimate: bool,
};

/// Outcome of reading a key from the perspective of some transaction index.
pub const ReadResult = union(enum) {
    /// No transaction below the reader has written this key; the reader should
    /// fall back to the persistent base state.
    not_found,
    /// A concrete value written by `version`.
    value: struct { value: BigInt, version: Version },
    /// Blocked: the highest writer below the reader is an ESTIMATE. The payload
    /// is that writer's transaction index (the dependency to wait on).
    dependency: usize,
};

pub const MvMemory = struct {
    allocator: Allocator,
    map: sk.StateKeyHashMap(std.ArrayListUnmanaged(VersionEntry)),

    pub fn init(allocator: Allocator) MvMemory {
        return .{
            .allocator = allocator,
            .map = sk.StateKeyHashMap(std.ArrayListUnmanaged(VersionEntry)).init(allocator),
        };
    }

    pub fn deinit(self: *MvMemory) void {
        var it = self.map.valueIterator();
        while (it.next()) |list| list.deinit(self.allocator);
        self.map.deinit();
    }

    /// Record that transaction `version.tx_index` wrote `value` to `key`.
    /// Re-writing the same transaction's entry (a later incarnation, or a
    /// second write within one execution) overwrites in place; entries stay
    /// sorted ascending by `tx_index`.
    pub fn write(self: *MvMemory, key: StateKey, version: Version, value: BigInt) !void {
        const gop = try self.map.getOrPut(key);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        const list = gop.value_ptr;

        // Find insertion point / existing entry for this tx_index.
        var i: usize = 0;
        while (i < list.items.len and list.items[i].version.tx_index < version.tx_index) : (i += 1) {}

        if (i < list.items.len and list.items[i].version.tx_index == version.tx_index) {
            list.items[i] = .{ .version = version, .value = value, .is_estimate = false };
        } else {
            try list.insert(self.allocator, i, .{ .version = version, .value = value, .is_estimate = false });
        }
    }

    /// Read `key` as seen by transaction `tx_index`: returns the value written
    /// by the highest-indexed transaction strictly below `tx_index`.
    pub fn read(self: *MvMemory, key: StateKey, tx_index: usize) ReadResult {
        const list = self.map.getPtr(key) orelse return .not_found;
        // Entries are ascending by tx_index; scan from the top for the highest
        // writer below `tx_index`.
        var i: usize = list.items.len;
        while (i > 0) {
            i -= 1;
            const entry = list.items[i];
            if (entry.version.tx_index < tx_index) {
                if (entry.is_estimate) return .{ .dependency = entry.version.tx_index };
                return .{ .value = .{ .value = entry.value, .version = entry.version } };
            }
        }
        return .not_found;
    }

    /// Mark transaction `tx_index`'s write to `key` as an ESTIMATE. Called when
    /// a transaction is aborted, so that dependents observe a dependency rather
    /// than a stale value while it re-executes.
    pub fn markEstimate(self: *MvMemory, key: StateKey, tx_index: usize) void {
        const list = self.map.getPtr(key) orelse return;
        for (list.items) |*entry| {
            if (entry.version.tx_index == tx_index) {
                entry.is_estimate = true;
                return;
            }
        }
    }

    /// Remove transaction `tx_index`'s write to `key` entirely. Used to retract
    /// writes from a previous incarnation that the latest one no longer makes.
    pub fn remove(self: *MvMemory, key: StateKey, tx_index: usize) void {
        const list = self.map.getPtr(key) orelse return;
        for (list.items, 0..) |entry, i| {
            if (entry.version.tx_index == tx_index) {
                _ = list.orderedRemove(i);
                return;
            }
        }
    }
};

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

const addr: sk.Address = [_]u8{0xCC} ** 20;

fn slotKey(n: u64) StateKey {
    return StateKey.storageOf(addr, BigInt.init(n));
}

test "read with no prior writer is not_found" {
    var mv = MvMemory.init(testing.allocator);
    defer mv.deinit();
    try testing.expect(mv.read(slotKey(0), 5) == .not_found);
}

test "reader sees the highest writer strictly below its index" {
    var mv = MvMemory.init(testing.allocator);
    defer mv.deinit();

    try mv.write(slotKey(0), .{ .tx_index = 1, .incarnation = 0 }, BigInt.init(11));
    try mv.write(slotKey(0), .{ .tx_index = 3, .incarnation = 0 }, BigInt.init(33));

    // tx 4 sees tx 3's write.
    switch (mv.read(slotKey(0), 4)) {
        .value => |v| {
            try testing.expectEqual(@as(usize, 3), v.version.tx_index);
            try testing.expect(v.value.eq(BigInt.init(33)));
        },
        else => return error.TestUnexpectedResult,
    }

    // tx 2 sees tx 1's write (3 is not strictly below 2).
    switch (mv.read(slotKey(0), 2)) {
        .value => |v| {
            try testing.expectEqual(@as(usize, 1), v.version.tx_index);
            try testing.expect(v.value.eq(BigInt.init(11)));
        },
        else => return error.TestUnexpectedResult,
    }

    // A transaction never reads its own write here.
    try testing.expect(mv.read(slotKey(0), 1) == .not_found);
}

test "rewriting a transaction's entry overwrites in place and keeps order" {
    var mv = MvMemory.init(testing.allocator);
    defer mv.deinit();

    try mv.write(slotKey(0), .{ .tx_index = 2, .incarnation = 0 }, BigInt.init(20));
    try mv.write(slotKey(0), .{ .tx_index = 5, .incarnation = 0 }, BigInt.init(50));
    // Re-execution of tx 2 (incarnation 1) writes a new value.
    try mv.write(slotKey(0), .{ .tx_index = 2, .incarnation = 1 }, BigInt.init(22));

    switch (mv.read(slotKey(0), 3)) {
        .value => |v| {
            try testing.expectEqual(@as(usize, 2), v.version.tx_index);
            try testing.expectEqual(@as(usize, 1), v.version.incarnation);
            try testing.expect(v.value.eq(BigInt.init(22)));
        },
        else => return error.TestUnexpectedResult,
    }
    // tx 6 still sees tx 5, ordering intact.
    switch (mv.read(slotKey(0), 6)) {
        .value => |v| try testing.expectEqual(@as(usize, 5), v.version.tx_index),
        else => return error.TestUnexpectedResult,
    }
}

test "an ESTIMATE write surfaces as a dependency on its writer" {
    var mv = MvMemory.init(testing.allocator);
    defer mv.deinit();

    try mv.write(slotKey(0), .{ .tx_index = 2, .incarnation = 0 }, BigInt.init(20));
    mv.markEstimate(slotKey(0), 2);

    switch (mv.read(slotKey(0), 7)) {
        .dependency => |dep| try testing.expectEqual(@as(usize, 2), dep),
        else => return error.TestUnexpectedResult,
    }
}

test "removing a write retracts it for readers" {
    var mv = MvMemory.init(testing.allocator);
    defer mv.deinit();

    try mv.write(slotKey(0), .{ .tx_index = 1, .incarnation = 0 }, BigInt.init(11));
    try mv.write(slotKey(0), .{ .tx_index = 3, .incarnation = 0 }, BigInt.init(33));
    mv.remove(slotKey(0), 3);

    switch (mv.read(slotKey(0), 4)) {
        .value => |v| try testing.expectEqual(@as(usize, 1), v.version.tx_index),
        else => return error.TestUnexpectedResult,
    }
}

test "writes to different slots do not interfere" {
    var mv = MvMemory.init(testing.allocator);
    defer mv.deinit();

    try mv.write(slotKey(0), .{ .tx_index = 1, .incarnation = 0 }, BigInt.init(111));
    try mv.write(slotKey(1), .{ .tx_index = 1, .incarnation = 0 }, BigInt.init(222));

    switch (mv.read(slotKey(0), 2)) {
        .value => |v| try testing.expect(v.value.eq(BigInt.init(111))),
        else => return error.TestUnexpectedResult,
    }
    switch (mv.read(slotKey(1), 2)) {
        .value => |v| try testing.expect(v.value.eq(BigInt.init(222))),
        else => return error.TestUnexpectedResult,
    }
}
