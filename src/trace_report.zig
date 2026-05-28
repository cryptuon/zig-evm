// CLI: read a block access-trace JSON and report achievable parallelism under
// the account / slot / dynamic conflict models for each block plus an aggregate.
// This is the tool that turns real traced workloads into the C2 numbers.
//
//   zig build trace-report -- testdata/sample_trace.json

const std = @import("std");
const tl = @import("trace_loader.zig");
const bs = @import("block_stm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len < 2) {
        std.debug.print("usage: trace-report <trace.json>\n", .{});
        return;
    }

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(alloc, 512 * 1024 * 1024);
    defer alloc.free(bytes);

    var parsed = try tl.parse(alloc, bytes);
    defer parsed.deinit();
    const trace = parsed.value;

    std.debug.print(
        "Conflict-granularity report over {d} block(s). Speedup = txs / critical-path.\n\n",
        .{trace.blocks.len},
    );
    std.debug.print("{s:>12} | {s:>4} | {s:>16} | {s:>16} | {s:>16}\n", .{ "block", "txs", "account-level", "slot-level", "dynamic (RAW)" });
    std.debug.print("{s:->12}-+-{s:->4}-+-{s:->16}-+-{s:->16}-+-{s:->16}\n", .{ "", "", "", "", "" });

    var sum_acc: f64 = 0;
    var sum_slot: f64 = 0;
    var sum_dyn: f64 = 0;
    var counted: usize = 0;

    for (trace.blocks) |block| {
        if (block.txs.len == 0) continue;
        const recs = try tl.buildRecorders(alloc, block);
        defer tl.freeRecorders(alloc, recs);
        const rep = try bs.analyzeModels(alloc, recs);
        const sa = bs.ModelReport.speedup(rep.num_txs, rep.cp_account);
        const ss = bs.ModelReport.speedup(rep.num_txs, rep.cp_slot);
        const sd = bs.ModelReport.speedup(rep.num_txs, rep.cp_dynamic);
        std.debug.print("{d:>12} | {d:>4} | x{d:>5.1} (cp{d:>3}) | x{d:>5.1} (cp{d:>3}) | x{d:>5.1} (cp{d:>3})\n", .{
            block.number, rep.num_txs,
            sa, rep.cp_account,
            ss, rep.cp_slot,
            sd, rep.cp_dynamic,
        });
        sum_acc += sa;
        sum_slot += ss;
        sum_dyn += sd;
        counted += 1;
    }

    if (counted > 0) {
        const c: f64 = @floatFromInt(counted);
        std.debug.print(
            "\nmean speedup over {d} block(s):  account x{d:.2}   slot x{d:.2}   dynamic x{d:.2}\n",
            .{ counted, sum_acc / c, sum_slot / c, sum_dyn / c },
        );
    }
}
