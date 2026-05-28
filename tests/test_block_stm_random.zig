// Randomized differential test of the serializable executor.
//
// Generates random read-dependent transaction programs and checks that the
// committed state agrees across three independent computations:
//   * forward optimistic execution (reads each lower write as it lands),
//   * reverse optimistic execution (forces aborts + re-execution), and
//   * a direct sequential applier (the ground-truth oracle).
//
// Agreement over many seeds is strong evidence that the executor is serializable
// for arbitrary conflict structures, not just the hand-crafted cases.

const std = @import("std");
const testing = std.testing;
const BigInt = @import("../src/bigint.zig").BigInt;
const sk = @import("../src/state_key.zig");
const StateKey = sk.StateKey;
const mvcc = @import("../src/mvcc.zig");
const as = @import("../src/access_set.zig");
const bs = @import("../src/block_stm.zig");

const addr: sk.Address = [_]u8{0x5A} ** 20;
fn skey(slot: u32) StateKey {
    return StateKey.storageOf(addr, BigInt.init(slot));
}

const Op = union(enum) {
    write_const: struct { slot: u32, value: u64 },
    // dst = addend + read(src_a) + read(src_b): a read-after-write dependency.
    write_sum: struct { dst: u32, src_a: u32, src_b: u32, addend: u64 },
};

const ProgramTx = struct {
    ops: []const Op,

    fn run(ctx: *anyopaque, view: *bs.VmView) anyerror!void {
        const self: *const ProgramTx = @ptrCast(@alignCast(ctx));
        for (self.ops) |o| switch (o) {
            .write_const => |w| try view.write(skey(w.slot), BigInt.init(w.value)),
            .write_sum => |w| {
                const a = try view.read(skey(w.src_a));
                const b = try view.read(skey(w.src_b));
                try view.write(skey(w.dst), a.add(b).add(BigInt.init(w.addend)));
            },
        };
    }
};

/// Ground-truth: apply the programs in index order to a single mutable map.
fn applySequential(map: *sk.StateKeyHashMap(BigInt), programs: []const ProgramTx) !void {
    for (programs) |p| {
        for (p.ops) |o| switch (o) {
            .write_const => |w| try map.put(skey(w.slot), BigInt.init(w.value)),
            .write_sum => |w| {
                const a = map.get(skey(w.src_a)) orelse BigInt.zero();
                const b = map.get(skey(w.src_b)) orelse BigInt.zero();
                try map.put(skey(w.dst), a.add(b).add(BigInt.init(w.addend)));
            },
        };
    }
}

test "block_stm: randomized serializability — forward == reverse == sequential" {
    const gpa = testing.allocator;
    const num_slots: u32 = 8;

    var seed: u64 = 0;
    while (seed < 50) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        const rnd = prng.random();
        const n = 4 + rnd.uintLessThan(usize, 28); // 4..31 transactions

        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const aa = arena.allocator();

        // Build random programs (1..3 ops each).
        const programs = try aa.alloc(ProgramTx, n);
        const txs = try gpa.alloc(bs.Transaction, n);
        defer gpa.free(txs);
        for (programs, 0..) |*p, i| {
            const num_ops = 1 + rnd.uintLessThan(usize, 3);
            const ops = try aa.alloc(Op, num_ops);
            for (ops) |*o| {
                if (rnd.boolean()) {
                    o.* = .{ .write_const = .{
                        .slot = rnd.uintLessThan(u32, num_slots),
                        .value = rnd.uintLessThan(u64, 1000),
                    } };
                } else {
                    o.* = .{ .write_sum = .{
                        .dst = rnd.uintLessThan(u32, num_slots),
                        .src_a = rnd.uintLessThan(u32, num_slots),
                        .src_b = rnd.uintLessThan(u32, num_slots),
                        .addend = rnd.uintLessThan(u64, 100),
                    } };
                }
            }
            p.* = .{ .ops = ops };
            txs[i] = .{ .ctx = @ptrCast(p), .run = ProgramTx.run };
        }

        // Oracle.
        var oracle = sk.StateKeyHashMap(BigInt).init(gpa);
        defer oracle.deinit();
        try applySequential(&oracle, programs);

        // Both execution orders must reproduce the oracle exactly.
        inline for (.{ bs.Strategy.forward, bs.Strategy.reverse }) |strat| {
            var mv = mvcc.MvMemory.init(gpa);
            defer mv.deinit();
            const recs = try gpa.alloc(as.AccessRecorder, n);
            for (recs) |*r| r.* = as.AccessRecorder.init(gpa);
            defer {
                for (recs) |*r| r.deinit();
                gpa.free(recs);
            }

            _ = try bs.executeBlock(gpa, &mv, txs, recs, bs.zero_base, strat);

            var s: u32 = 0;
            while (s < num_slots) : (s += 1) {
                const got = bs.finalValue(&mv, skey(s), n);
                const want = oracle.get(skey(s)) orelse BigInt.zero();
                try testing.expect(got.eq(want));
            }
        }
    }
}
