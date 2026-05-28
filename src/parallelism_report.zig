// Demo: the C2 measurement instrument on a synthetic block.
//
// Builds a block of `n` transactions that all touch one account: `hot` of them
// read-modify-write a single shared "counter" slot (genuine contention), the
// rest each write their own private slot (independent). It then reports the
// achievable speedup (n / critical path) under the three conflict-detection
// granularities, and the re-execution count under worst-case (reverse) ordering.
//
// The point it illustrates: account-level analysis sees every transaction as
// conflicting (they share the account) and recovers ~no parallelism, while
// slot-level and dynamic analysis expose the true n/hot parallelism. On real
// blocks this gap is the headline empirical result; here it is synthetic and
// labelled as such.
//
//   Run: zig build parallel-report

const std = @import("std");
const BigInt = @import("bigint.zig").BigInt;
const sk = @import("state_key.zig");
const StateKey = sk.StateKey;
const mvcc = @import("mvcc.zig");
const as = @import("access_set.zig");
const bs = @import("block_stm.zig");

const addr: sk.Address = [_]u8{0x11} ** 20;
fn skey(s: u64) StateKey {
    return StateKey.storageOf(addr, BigInt.init(s));
}

const Tx = struct {
    hot: bool,
    slot: u64,
    fn run(ctx: *anyopaque, view: *bs.VmView) anyerror!void {
        const self: *const Tx = @ptrCast(@alignCast(ctx));
        if (self.hot) {
            // Read-modify-write the shared counter (slot 0): a serializing chain.
            const v = try view.read(skey(0));
            try view.write(skey(0), v.add(BigInt.one()));
        } else {
            // Independent write to a private slot.
            try view.write(skey(self.slot), BigInt.one());
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const n: usize = 64;
    std.debug.print(
        "Synthetic block: {d} transactions on one account. Achievable speedup = n / critical-path.\n\n",
        .{n},
    );
    std.debug.print(
        "{s:>4} | {s:>20} | {s:>20} | {s:>20} | {s:>7}\n",
        .{ "hot", "account-level", "slot-level", "dynamic (RAW)", "aborts" },
    );
    std.debug.print("{s:->4}-+-{s:->20}-+-{s:->20}-+-{s:->20}-+-{s:->7}\n", .{ "", "", "", "", "" });

    for ([_]usize{ 1, 2, 4, 8, 16, 32 }) |hot| {
        const txs = try alloc.alloc(bs.Transaction, n);
        defer alloc.free(txs);
        const objs = try alloc.alloc(Tx, n);
        defer alloc.free(objs);
        for (objs, 0..) |*o, i| {
            o.* = .{ .hot = i < hot, .slot = i + 1 };
            txs[i] = .{ .ctx = @ptrCast(o), .run = Tx.run };
        }

        var mv = mvcc.MvMemory.init(alloc);
        defer mv.deinit();
        const recs = try alloc.alloc(as.AccessRecorder, n);
        for (recs) |*r| r.* = as.AccessRecorder.init(alloc);
        defer {
            for (recs) |*r| r.deinit();
            alloc.free(recs);
        }

        // Reverse ordering stresses the optimistic path so aborts are visible;
        // the conflict graph (and thus the speedups) is order-independent.
        const stats = try bs.executeBlock(alloc, &mv, txs, recs, bs.zero_base, .reverse);
        const rep = try bs.analyzeModels(alloc, recs);

        std.debug.print(
            "{d:>4} | x{d:>5.1} (cp {d:>3}) | x{d:>6.1} (cp {d:>3}) | x{d:>6.1} (cp {d:>3}) | {d:>7}\n",
            .{
                hot,
                bs.ModelReport.speedup(n, rep.cp_account), rep.cp_account,
                bs.ModelReport.speedup(n, rep.cp_slot),    rep.cp_slot,
                bs.ModelReport.speedup(n, rep.cp_dynamic), rep.cp_dynamic,
                stats.aborts,
            },
        );
    }
}
