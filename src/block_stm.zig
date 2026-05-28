// File: src/block_stm.zig
//
// A serializable optimistic block executor in the style of Block-STM
// (Gelashvili et al.), built on the multi-version store (src/mvcc.zig) and the
// read/write sets + validation predicate (src/access_set.zig).
//
// Transactions of a block carry a fixed order. They execute optimistically —
// each reads through `VmView` from the multi-version store (recording the
// version it observes) and writes back at its own (tx_index, incarnation).
// After an execution pass, every transaction is *validated* by re-resolving its
// recorded reads; any transaction whose reads no longer match is aborted (its
// incarnation bumped, its stale writes retracted) and re-executed. Iterating to
// a fixpoint yields a committed state identical to sequential execution — the
// schedule is serializable by the standard Block-STM argument.
//
// This implementation is a single-threaded, deterministic *simulation* of that
// scheme. It is the correctness reference and the measurement instrument: it
// produces, as a by-product, the exact read/write sets from which the block
// conflict graph and its critical path are computed (paper contribution C2).
// The genuinely multi-threaded scheduler that turns this into wall-clock
// speedup is future work; correctness and the conflict structure do not depend
// on it.
//
// To exercise the abort/re-execution path deterministically, `executeBlock`
// accepts an execution-order `Strategy`. The committed result is identical for
// every strategy (that is the serializability guarantee we test); `reverse`
// forces higher-indexed transactions to run before the lower ones they depend
// on, producing aborts that `forward` (which reads each lower write as soon as
// it lands) avoids.

const std = @import("std");
const Allocator = std.mem.Allocator;
const BigInt = @import("bigint.zig").BigInt;
const sk = @import("state_key.zig");
const StateKey = sk.StateKey;
const mvcc = @import("mvcc.zig");
const MvMemory = mvcc.MvMemory;
const Version = mvcc.Version;
const as = @import("access_set.zig");
const AccessRecorder = as.AccessRecorder;
const validateReadSet = as.validateReadSet;

/// Persistent base state seen when no transaction below the reader has written
/// a key. The EVM integration backs this with the pre-block world state; tests
/// use `zero_base`.
pub const BaseState = struct {
    ctx: *anyopaque,
    get: *const fn (ctx: *anyopaque, key: StateKey) BigInt,
};

var zero_base_dummy: u8 = 0;
fn zeroBaseGet(_: *anyopaque, _: StateKey) BigInt {
    return BigInt.zero();
}
/// A base state in which every absent key reads as zero.
pub const zero_base = BaseState{ .ctx = &zero_base_dummy, .get = zeroBaseGet };

/// The state interface an executing transaction uses. All reads and writes go
/// through here so they are versioned in the store and recorded in the
/// transaction's access set.
pub const VmView = struct {
    mv: *MvMemory,
    rec: *AccessRecorder,
    base: BaseState,
    /// This incarnation's own writes, so subsequent reads in the same
    /// transaction see them (read-your-own-writes). A read served from here is
    /// not a cross-transaction dependency and is therefore not recorded in the
    /// read set. Reset before every (re-)execution by the scheduler.
    local: *sk.StateKeyHashMap(BigInt),
    tx_index: usize,
    incarnation: usize,

    pub fn read(self: *VmView, key: StateKey) !BigInt {
        if (self.local.get(key)) |own| return own;
        switch (self.mv.read(key, self.tx_index)) {
            .value => |v| {
                try self.rec.read_set.record(self.rec.allocator, key, .{ .versioned = v.version });
                return v.value;
            },
            .not_found => {
                try self.rec.read_set.record(self.rec.allocator, key, .base);
                return self.base.get(self.base.ctx, key);
            },
            // The deterministic scheduler retracts a transaction's writes before
            // re-executing it, so a reader never observes an ESTIMATE here.
            .dependency => return error.UnexpectedEstimate,
        }
    }

    pub fn write(self: *VmView, key: StateKey, value: BigInt) !void {
        try self.local.put(key, value);
        try self.rec.write_set.record(self.rec.allocator, key);
        try self.mv.write(key, .{ .tx_index = self.tx_index, .incarnation = self.incarnation }, value);
    }

    /// Record a read of a key whose value is resolved outside the versioned
    /// word store (e.g. account code, which is not 256-bit-valued). It enters
    /// the read set as a base read so it still participates in the conflict
    /// graph; it is not version-validated.
    pub fn recordReadKey(self: *VmView, key: StateKey) !void {
        try self.rec.read_set.record(self.rec.allocator, key, .base);
    }

    /// Record a write of a key whose value is tracked elsewhere.
    pub fn recordWriteKey(self: *VmView, key: StateKey) !void {
        try self.rec.write_set.record(self.rec.allocator, key);
    }

    /// Read a key's current value without recording it (used to capture the
    /// pre-write value for the revert journal).
    pub fn peek(self: *VmView, key: StateKey) BigInt {
        if (self.local.get(key)) |own| return own;
        return switch (self.mv.read(key, self.tx_index)) {
            .value => |v| v.value,
            .not_found => self.base.get(self.base.ctx, key),
            .dependency => BigInt.zero(),
        };
    }
};

/// A block transaction: an opaque context plus the routine that runs it against
/// a `VmView`. (The EVM integration will supply a transaction whose routine
/// executes bytecode; tests supply small closures.)
pub const Transaction = struct {
    ctx: *anyopaque,
    run: *const fn (ctx: *anyopaque, view: *VmView) anyerror!void,
};

pub const Strategy = enum { forward, reverse };

pub const Stats = struct {
    /// Number of execute-then-validate passes to reach a fixpoint.
    rounds: usize = 0,
    /// Total transaction (re-)executions performed.
    executions: usize = 0,
    /// Re-executions beyond the first per transaction (i.e. aborts).
    aborts: usize = 0,
};

/// Execute a block to a serializable fixpoint. `recorders` (length == txs.len,
/// each `AccessRecorder.init`-ed by the caller) hold the per-transaction
/// read/write sets and remain valid after the call for `analyzeBlock`.
pub fn executeBlock(
    allocator: Allocator,
    mv: *MvMemory,
    txs: []const Transaction,
    recorders: []AccessRecorder,
    base: BaseState,
    strategy: Strategy,
) !Stats {
    const n = txs.len;
    std.debug.assert(recorders.len == n);

    const valid = try allocator.alloc(bool, n);
    defer allocator.free(valid);
    const executed_once = try allocator.alloc(bool, n);
    defer allocator.free(executed_once);
    const incarnation = try allocator.alloc(usize, n);
    defer allocator.free(incarnation);
    @memset(valid, false);
    @memset(executed_once, false);
    @memset(incarnation, 0);

    var stats = Stats{};

    while (true) {
        stats.rounds += 1;

        // --- execution phase: (re-)run every not-yet-valid transaction ---
        var step: usize = 0;
        while (step < n) : (step += 1) {
            const i = switch (strategy) {
                .forward => step,
                .reverse => n - 1 - step,
            };
            if (valid[i]) continue;

            // Retract this transaction's writes from a previous incarnation so a
            // shrinking write set leaves nothing stale behind.
            for (recorders[i].write_set.keys.items) |k| mv.remove(k, i);
            recorders[i].reset();

            // Fresh read-your-own-writes cache for this incarnation.
            var local = sk.StateKeyHashMap(BigInt).init(allocator);
            defer local.deinit();

            var view = VmView{ .mv = mv, .rec = &recorders[i], .base = base, .local = &local, .tx_index = i, .incarnation = incarnation[i] };
            try txs[i].run(txs[i].ctx, &view);

            stats.executions += 1;
            if (executed_once[i]) stats.aborts += 1 else executed_once[i] = true;
        }

        // --- validation phase: in index order ---
        var any_invalid = false;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (validateReadSet(&recorders[i].read_set, mv, i)) {
                valid[i] = true;
            } else {
                valid[i] = false;
                incarnation[i] += 1;
                any_invalid = true;
            }
        }

        if (!any_invalid) break;
        // tx k stabilizes by round k+1, so n+1 rounds always suffice; the slack
        // guards against a logic error rather than expected behaviour.
        if (stats.rounds > 2 * n + 2) return error.NoConvergence;
    }

    return stats;
}

/// The committed value of `key` after a block of `n` transactions: the write of
/// the highest-indexed transaction, or base state if none wrote it.
pub fn finalValue(mv: *MvMemory, key: StateKey, n: usize) BigInt {
    return switch (mv.read(key, n + 1)) {
        .value => |v| v.value,
        else => BigInt.zero(),
    };
}

pub const BlockMetrics = struct {
    num_txs: usize,
    /// Read-after-write edges i->j (i<j) where j reads a key i wrote.
    raw_edges: usize,
    /// Longest chain of RAW dependencies, in number of transactions. This is
    /// the minimum number of sequential execution rounds, hence a lower bound
    /// on parallel makespan; achievable speedup is num_txs / critical_path.
    critical_path: usize,
};

/// Build the read-after-write conflict graph from executed read/write sets and
/// compute its critical path. Edges only run from lower to higher index, so the
/// graph is a DAG topologically ordered by index and the longest path is a
/// simple O(n^2) dynamic program.
pub fn analyzeBlock(allocator: Allocator, recorders: []const AccessRecorder) !BlockMetrics {
    const n = recorders.len;
    var edges: usize = 0;

    // depth[j] = longest RAW chain ending at j, counting nodes.
    const depth = try allocator.alloc(usize, n);
    defer allocator.free(depth);

    var crit: usize = 0;
    var j: usize = 0;
    while (j < n) : (j += 1) {
        depth[j] = 1;
        var i: usize = 0;
        while (i < j) : (i += 1) {
            if (as.readsConflict(&recorders[j].read_set, &recorders[i].write_set)) {
                edges += 1;
                if (depth[i] + 1 > depth[j]) depth[j] = depth[i] + 1;
            }
        }
        if (depth[j] > crit) crit = depth[j];
    }

    return .{ .num_txs = n, .raw_edges = edges, .critical_path = crit };
}

/// Critical-path / achievable-parallelism under three conflict-detection
/// granularities, computed from the same observed read/write sets. This is the
/// instrument behind paper contribution C2: comparing these three shows how
/// much available concurrency the cheap account-level approximation forgoes
/// relative to slot-level and to the precise dynamic (RAW) dependencies.
///
///   * account: two transactions conflict if they touch any common account
///     (the coarse model keyed on addresses, e.g. tx from/to fields).
///   * slot:    conflict if they touch any common (address, slot) or balance
///     key — still static (read+write, undirected).
///   * dynamic: a read-after-write edge — tx j reads a key tx i wrote. These
///     are the dependencies that actually force serialization under Block-STM.
pub const ModelReport = struct {
    num_txs: usize,
    cp_account: usize,
    cp_slot: usize,
    cp_dynamic: usize,

    /// Achievable speedup under uniform per-transaction cost: n / critical path.
    pub fn speedup(num_txs: usize, critical_path: usize) f64 {
        if (critical_path == 0) return 0;
        return @as(f64, @floatFromInt(num_txs)) / @as(f64, @floatFromInt(critical_path));
    }
};

fn addrSetsIntersect(x: *std.AutoHashMap([20]u8, void), y: *std.AutoHashMap([20]u8, void)) bool {
    var it = x.keyIterator();
    while (it.next()) |k| if (y.contains(k.*)) return true;
    return false;
}

fn keySetsIntersect(x: *sk.StateKeyHashMap(void), y: *sk.StateKeyHashMap(void)) bool {
    var it = x.keyIterator();
    while (it.next()) |k| if (y.contains(k.*)) return true;
    return false;
}

pub fn analyzeModels(allocator: Allocator, recorders: []const AccessRecorder) !ModelReport {
    const n = recorders.len;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Per-transaction sets of touched keys and touched addresses (read ∪ write).
    const key_sets = try aa.alloc(sk.StateKeyHashMap(void), n);
    const addr_sets = try aa.alloc(std.AutoHashMap([20]u8, void), n);
    for (recorders, 0..) |*r, i| {
        key_sets[i] = sk.StateKeyHashMap(void).init(aa);
        addr_sets[i] = std.AutoHashMap([20]u8, void).init(aa);
        for (r.read_set.entries.items) |rd| {
            try key_sets[i].put(rd.key, {});
            try addr_sets[i].put(rd.key.address, {});
        }
        for (r.write_set.keys.items) |k| {
            try key_sets[i].put(k, {});
            try addr_sets[i].put(k.address, {});
        }
    }

    const depth = try aa.alloc(usize, n);

    const Model = enum { account, slot, dynamic };
    const crit = struct {
        fn run(
            m: Model,
            nn: usize,
            d: []usize,
            ks: []sk.StateKeyHashMap(void),
            as_: []std.AutoHashMap([20]u8, void),
            recs: []const AccessRecorder,
        ) usize {
            var c: usize = 0;
            var j: usize = 0;
            while (j < nn) : (j += 1) {
                d[j] = 1;
                var i: usize = 0;
                while (i < j) : (i += 1) {
                    const conflict = switch (m) {
                        .account => addrSetsIntersect(&as_[i], &as_[j]),
                        .slot => keySetsIntersect(&ks[i], &ks[j]),
                        .dynamic => as.readsConflict(&recs[j].read_set, &recs[i].write_set),
                    };
                    if (conflict and d[i] + 1 > d[j]) d[j] = d[i] + 1;
                }
                if (d[j] > c) c = d[j];
            }
            return c;
        }
    }.run;

    return .{
        .num_txs = n,
        .cp_account = crit(.account, n, depth, key_sets, addr_sets, recorders),
        .cp_slot = crit(.slot, n, depth, key_sets, addr_sets, recorders),
        .cp_dynamic = crit(.dynamic, n, depth, key_sets, addr_sets, recorders),
    };
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

const addr: sk.Address = [_]u8{0xEE} ** 20;
fn skey(slot: u64) StateKey {
    return StateKey.storageOf(addr, BigInt.init(slot));
}

/// Writes a constant to a slot.
const SetTx = struct {
    slot: u64,
    value: u64,
    fn run(ctx: *anyopaque, view: *VmView) anyerror!void {
        const self: *SetTx = @ptrCast(@alignCast(ctx));
        try view.write(skey(self.slot), BigInt.init(self.value));
    }
    fn tx(self: *SetTx) Transaction {
        return .{ .ctx = self, .run = SetTx.run };
    }
};

/// Reads `src`, writes `src + delta` to `dst` (a RAW dependency on the writer of `src`).
const AddTx = struct {
    src: u64,
    dst: u64,
    delta: u64,
    fn run(ctx: *anyopaque, view: *VmView) anyerror!void {
        const self: *AddTx = @ptrCast(@alignCast(ctx));
        const v = try view.read(skey(self.src));
        try view.write(skey(self.dst), v.add(BigInt.init(self.delta)));
    }
    fn tx(self: *AddTx) Transaction {
        return .{ .ctx = self, .run = AddTx.run };
    }
};

fn initRecorders(allocator: Allocator, n: usize) ![]AccessRecorder {
    const recs = try allocator.alloc(AccessRecorder, n);
    for (recs) |*r| r.* = AccessRecorder.init(allocator);
    return recs;
}
fn deinitRecorders(allocator: Allocator, recs: []AccessRecorder) void {
    for (recs) |*r| r.deinit();
    allocator.free(recs);
}

test "independent transactions: no conflicts, single round, no aborts" {
    const a = testing.allocator;
    var s0 = SetTx{ .slot = 0, .value = 10 };
    var s1 = SetTx{ .slot = 1, .value = 20 };
    var s2 = SetTx{ .slot = 2, .value = 30 };
    const txs = [_]Transaction{ s0.tx(), s1.tx(), s2.tx() };

    inline for (.{ Strategy.forward, Strategy.reverse }) |strat| {
        var mv = MvMemory.init(a);
        defer mv.deinit();
        const recs = try initRecorders(a, txs.len);
        defer deinitRecorders(a, recs);

        const stats = try executeBlock(a, &mv, &txs, recs, zero_base, strat);
        try testing.expectEqual(@as(usize, 0), stats.aborts);
        try testing.expect(finalValue(&mv, skey(0), txs.len).eq(BigInt.init(10)));
        try testing.expect(finalValue(&mv, skey(1), txs.len).eq(BigInt.init(20)));
        try testing.expect(finalValue(&mv, skey(2), txs.len).eq(BigInt.init(30)));

        const m = try analyzeBlock(a, recs);
        try testing.expectEqual(@as(usize, 0), m.raw_edges);
        try testing.expectEqual(@as(usize, 1), m.critical_path);
    }
}

test "dependency chain: serializable result under any order; reverse forces aborts" {
    const a = testing.allocator;
    // slot0 = 1; slot1 = slot0 + 1; slot2 = slot1 + 1  => 1, 2, 3
    var s0 = SetTx{ .slot = 0, .value = 1 };
    var a1 = AddTx{ .src = 0, .dst = 1, .delta = 1 };
    var a2 = AddTx{ .src = 1, .dst = 2, .delta = 1 };
    const txs = [_]Transaction{ s0.tx(), a1.tx(), a2.tx() };

    // Forward: each reads the lower write as soon as it lands -> no aborts.
    {
        var mv = MvMemory.init(a);
        defer mv.deinit();
        const recs = try initRecorders(a, txs.len);
        defer deinitRecorders(a, recs);
        const stats = try executeBlock(a, &mv, &txs, recs, zero_base, .forward);
        try testing.expectEqual(@as(usize, 0), stats.aborts);
        try testing.expect(finalValue(&mv, skey(2), txs.len).eq(BigInt.init(3)));

        const m = try analyzeBlock(a, recs);
        try testing.expectEqual(@as(usize, 2), m.raw_edges); // 0->1, 1->2
        try testing.expectEqual(@as(usize, 3), m.critical_path);
    }

    // Reverse: higher txs run before their dependencies -> aborts, same result.
    {
        var mv = MvMemory.init(a);
        defer mv.deinit();
        const recs = try initRecorders(a, txs.len);
        defer deinitRecorders(a, recs);
        const stats = try executeBlock(a, &mv, &txs, recs, zero_base, .reverse);
        try testing.expect(stats.aborts > 0);
        try testing.expect(finalValue(&mv, skey(0), txs.len).eq(BigInt.init(1)));
        try testing.expect(finalValue(&mv, skey(1), txs.len).eq(BigInt.init(2)));
        try testing.expect(finalValue(&mv, skey(2), txs.len).eq(BigInt.init(3)));
    }
}

test "write-write on one slot: last writer in index order wins" {
    const a = testing.allocator;
    var s0 = SetTx{ .slot = 7, .value = 5 };
    var s1 = SetTx{ .slot = 7, .value = 9 };
    const txs = [_]Transaction{ s0.tx(), s1.tx() };

    inline for (.{ Strategy.forward, Strategy.reverse }) |strat| {
        var mv = MvMemory.init(a);
        defer mv.deinit();
        const recs = try initRecorders(a, txs.len);
        defer deinitRecorders(a, recs);

        _ = try executeBlock(a, &mv, &txs, recs, zero_base, strat);
        // No reads => no RAW edges => fully parallel, and tx1 (higher index) wins.
        try testing.expect(finalValue(&mv, skey(7), txs.len).eq(BigInt.init(9)));
        const m = try analyzeBlock(a, recs);
        try testing.expectEqual(@as(usize, 0), m.raw_edges);
        try testing.expectEqual(@as(usize, 1), m.critical_path);
    }
}

test "conflict models: account-level over-counts vs slot-level and dynamic" {
    const a = testing.allocator;
    // Two txs writing *different slots of the same account*. Account-level
    // analysis sees a conflict (they share the account); slot-level and dynamic
    // see none — they are independent.
    var s0 = SetTx{ .slot = 0, .value = 1 };
    var s1 = SetTx{ .slot = 1, .value = 2 };
    const txs = [_]Transaction{ s0.tx(), s1.tx() };

    var mv = MvMemory.init(a);
    defer mv.deinit();
    const recs = try initRecorders(a, txs.len);
    defer deinitRecorders(a, recs);
    _ = try executeBlock(a, &mv, &txs, recs, zero_base, .forward);

    const rep = try analyzeModels(a, recs);
    try testing.expectEqual(@as(usize, 2), rep.cp_account); // false serialization
    try testing.expectEqual(@as(usize, 1), rep.cp_slot); // fully parallel
    try testing.expectEqual(@as(usize, 1), rep.cp_dynamic); // fully parallel
}

test "conflict models: a true RAW chain serializes under all three models" {
    const a = testing.allocator;
    var s0 = SetTx{ .slot = 0, .value = 1 };
    var a1 = AddTx{ .src = 0, .dst = 1, .delta = 1 };
    var a2 = AddTx{ .src = 1, .dst = 2, .delta = 1 };
    const txs = [_]Transaction{ s0.tx(), a1.tx(), a2.tx() };

    var mv = MvMemory.init(a);
    defer mv.deinit();
    const recs = try initRecorders(a, txs.len);
    defer deinitRecorders(a, recs);
    _ = try executeBlock(a, &mv, &txs, recs, zero_base, .forward);

    const rep = try analyzeModels(a, recs);
    try testing.expectEqual(@as(usize, 3), rep.cp_account);
    try testing.expectEqual(@as(usize, 3), rep.cp_slot);
    try testing.expectEqual(@as(usize, 3), rep.cp_dynamic);
}

test "diamond dependency: critical path is three despite four transactions" {
    const a = testing.allocator;
    // t0: slot0=1 ; t1: slot1=slot0+1 ; t2: slot2=slot0+1 ; t3: slot3=slot1+1
    // RAW edges: 0->1, 0->2, 1->3.  Longest chain 0->1->3 = 3 nodes.
    var s0 = SetTx{ .slot = 0, .value = 1 };
    var a1 = AddTx{ .src = 0, .dst = 1, .delta = 1 };
    var a2 = AddTx{ .src = 0, .dst = 2, .delta = 1 };
    var a3 = AddTx{ .src = 1, .dst = 3, .delta = 1 };
    const txs = [_]Transaction{ s0.tx(), a1.tx(), a2.tx(), a3.tx() };

    var mv = MvMemory.init(a);
    defer mv.deinit();
    const recs = try initRecorders(a, txs.len);
    defer deinitRecorders(a, recs);

    _ = try executeBlock(a, &mv, &txs, recs, zero_base, .reverse);
    try testing.expect(finalValue(&mv, skey(3), txs.len).eq(BigInt.init(3))); // 1 ->2 ->3
    const m = try analyzeBlock(a, recs);
    try testing.expectEqual(@as(usize, 3), m.raw_edges);
    try testing.expectEqual(@as(usize, 3), m.critical_path);
}
