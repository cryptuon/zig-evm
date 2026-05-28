// File: src/access_set.zig
//
// Per-transaction dynamic read/write sets and the Block-STM validation check.
//
// During optimistic execution, every state access a transaction makes is
// recorded here: each read remembers *which version* it observed, and each
// write remembers *which key* it touched. Two things are built from these:
//
//   1. Validation (this file): re-resolve every recorded read against the
//      current multi-version store. If any read would now return a different
//      version, the transaction's execution was based on stale data and must
//      be re-executed. Passing validation for every transaction in index order
//      is exactly the condition that makes the parallel schedule serializable.
//
//   2. The conflict graph (paper contribution C2/C3): a write by transaction i
//      to a key later read by transaction j (j > i) is a real, dynamically
//      observed dependency. Aggregated over a block, these sets yield the
//      achievable-parallelism and contention measurements the paper reports —
//      and crucially let us compare slot-level conflicts against the cheap
//      account-level (from/to) approximation used by the prior engine.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sk = @import("state_key.zig");
const StateKey = sk.StateKey;
const mvcc = @import("mvcc.zig");
const MvMemory = mvcc.MvMemory;
const Version = mvcc.Version;

/// The provenance of a value a transaction read.
pub const ReadVersion = union(enum) {
    /// Read fell through to the persistent base state (no prior writer).
    base,
    /// Read observed a specific version produced by an earlier transaction.
    versioned: Version,
};

pub const ReadDescriptor = struct {
    key: StateKey,
    version: ReadVersion,
};

/// Ordered log of the reads a single transaction incarnation performed.
pub const ReadSet = struct {
    entries: std.ArrayListUnmanaged(ReadDescriptor) = .{},

    pub fn deinit(self: *ReadSet, allocator: Allocator) void {
        self.entries.deinit(allocator);
    }

    pub fn clear(self: *ReadSet) void {
        self.entries.clearRetainingCapacity();
    }

    pub fn record(self: *ReadSet, allocator: Allocator, key: StateKey, version: ReadVersion) !void {
        try self.entries.append(allocator, .{ .key = key, .version = version });
    }
};

/// Set of keys a single transaction incarnation wrote.
pub const WriteSet = struct {
    keys: std.ArrayListUnmanaged(StateKey) = .{},

    pub fn deinit(self: *WriteSet, allocator: Allocator) void {
        self.keys.deinit(allocator);
    }

    pub fn clear(self: *WriteSet) void {
        self.keys.clearRetainingCapacity();
    }

    pub fn record(self: *WriteSet, allocator: Allocator, key: StateKey) !void {
        for (self.keys.items) |k| {
            if (StateKey.eql(k, key)) return; // dedupe
        }
        try self.keys.append(allocator, key);
    }

    pub fn contains(self: *const WriteSet, key: StateKey) bool {
        for (self.keys.items) |k| {
            if (StateKey.eql(k, key)) return true;
        }
        return false;
    }
};

/// Bundles a transaction's read and write sets and is attached to an executing
/// EVM so that state-touching opcodes record what they touch. With the
/// sequential (single-version) backend there are no versions to observe yet, so
/// reads are recorded as `.base`; once execution runs against the multi-version
/// store (\Cref engine milestone M3) the recorder will capture the observed
/// `Version` instead. Either way the recorded *keys* are what the conflict graph
/// and the contention measurements are built from.
pub const AccessRecorder = struct {
    allocator: Allocator,
    read_set: ReadSet = .{},
    write_set: WriteSet = .{},

    pub fn init(allocator: Allocator) AccessRecorder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AccessRecorder) void {
        self.read_set.deinit(self.allocator);
        self.write_set.deinit(self.allocator);
    }

    /// Clear both sets so the recorder can be reused for the next transaction
    /// (or the next incarnation of the same transaction) without reallocating.
    pub fn reset(self: *AccessRecorder) void {
        self.read_set.clear();
        self.write_set.clear();
    }

    pub fn recordRead(self: *AccessRecorder, key: StateKey) !void {
        try self.read_set.record(self.allocator, key, .base);
    }

    pub fn recordWrite(self: *AccessRecorder, key: StateKey) !void {
        try self.write_set.record(self.allocator, key);
    }

    /// Did this transaction read the given key?
    pub fn readKey(self: *const AccessRecorder, key: StateKey) bool {
        for (self.read_set.entries.items) |rd| {
            if (StateKey.eql(rd.key, key)) return true;
        }
        return false;
    }
};

/// Re-resolve every recorded read against the current store. Returns true iff
/// every read still observes the same version it did during execution.
///
/// This is the core Block-STM validation step. A read recorded as `.base` is
/// still valid only if no earlier transaction now writes the key; a read
/// recorded as `.versioned` is valid only if the highest writer below the
/// transaction is still that same (tx_index, incarnation). Any ESTIMATE
/// encountered invalidates the read (the dependency must be re-run first).
pub fn validateReadSet(read_set: *const ReadSet, mv: *MvMemory, tx_index: usize) bool {
    for (read_set.entries.items) |rd| {
        switch (mv.read(rd.key, tx_index)) {
            .not_found => if (rd.version != .base) return false,
            .dependency => return false,
            .value => |v| switch (rd.version) {
                .base => return false,
                .versioned => |seen| if (!Version.eql(v.version, seen)) return false,
            },
        }
    }
    return true;
}

/// Does any key written by `writer` appear in `reader`'s read set? Used to
/// build the dynamically observed conflict graph for the empirical study.
pub fn readsConflict(reader: *const ReadSet, writer: *const WriteSet) bool {
    for (reader.entries.items) |rd| {
        if (writer.contains(rd.key)) return true;
    }
    return false;
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;
const BigInt = @import("bigint.zig").BigInt;
const addr: sk.Address = [_]u8{0xDD} ** 20;

fn slotKey(n: u64) StateKey {
    return StateKey.storageOf(addr, BigInt.init(n));
}

test "write set dedupes and reports membership" {
    var ws = WriteSet{};
    defer ws.deinit(testing.allocator);
    try ws.record(testing.allocator, slotKey(0));
    try ws.record(testing.allocator, slotKey(0));
    try ws.record(testing.allocator, slotKey(1));
    try testing.expectEqual(@as(usize, 2), ws.keys.items.len);
    try testing.expect(ws.contains(slotKey(1)));
    try testing.expect(!ws.contains(slotKey(2)));
}

test "a base read stays valid until an earlier write appears" {
    var mv = MvMemory.init(testing.allocator);
    defer mv.deinit();
    var rs = ReadSet{};
    defer rs.deinit(testing.allocator);

    // tx 5 read slot 0 from base state (nobody had written it).
    try rs.record(testing.allocator, slotKey(0), .base);
    try testing.expect(validateReadSet(&rs, &mv, 5));

    // Now an earlier tx 2 writes slot 0; tx 5's base read is stale.
    try mv.write(slotKey(0), .{ .tx_index = 2, .incarnation = 0 }, BigInt.init(99));
    try testing.expect(!validateReadSet(&rs, &mv, 5));
}

test "a versioned read stays valid only against the same version" {
    var mv = MvMemory.init(testing.allocator);
    defer mv.deinit();
    var rs = ReadSet{};
    defer rs.deinit(testing.allocator);

    try mv.write(slotKey(0), .{ .tx_index = 2, .incarnation = 0 }, BigInt.init(20));
    // tx 5 read the value tx 2 (incarnation 0) wrote.
    try rs.record(testing.allocator, slotKey(0), .{ .versioned = .{ .tx_index = 2, .incarnation = 0 } });
    try testing.expect(validateReadSet(&rs, &mv, 5));

    // tx 2 re-executes (incarnation 1) -> tx 5's read is now stale.
    try mv.write(slotKey(0), .{ .tx_index = 2, .incarnation = 1 }, BigInt.init(21));
    try testing.expect(!validateReadSet(&rs, &mv, 5));
}

test "an estimate dependency invalidates a read" {
    var mv = MvMemory.init(testing.allocator);
    defer mv.deinit();
    var rs = ReadSet{};
    defer rs.deinit(testing.allocator);

    try mv.write(slotKey(0), .{ .tx_index = 2, .incarnation = 0 }, BigInt.init(20));
    try rs.record(testing.allocator, slotKey(0), .{ .versioned = .{ .tx_index = 2, .incarnation = 0 } });
    mv.markEstimate(slotKey(0), 2);
    try testing.expect(!validateReadSet(&rs, &mv, 5));
}

test "conflict detection between a writer and a later reader" {
    var rs = ReadSet{};
    defer rs.deinit(testing.allocator);
    var ws = WriteSet{};
    defer ws.deinit(testing.allocator);

    try rs.record(testing.allocator, slotKey(3), .base);
    try ws.record(testing.allocator, slotKey(7));
    try testing.expect(!readsConflict(&rs, &ws)); // disjoint

    try ws.record(testing.allocator, slotKey(3));
    try testing.expect(readsConflict(&rs, &ws)); // now they share slot 3
}
