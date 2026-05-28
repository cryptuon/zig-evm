// CLI: replay a JSON state test and report post-state mismatches.
//   zig build state-test -- testdata/sample_state_test.json
// Exit code is nonzero if any post-state check fails, so it can gate CI.

const std = @import("std");
const state_test = @import("state_test.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len < 2) {
        std.debug.print("usage: state-test <state_test.json>\n", .{});
        return;
    }

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(alloc, 256 * 1024 * 1024);
    defer alloc.free(bytes);

    const res = try state_test.run(alloc, bytes);
    std.debug.print("{s}: {d} checks, {d} mismatches\n", .{ args[1], res.checks, res.mismatches });
    if (res.mismatches > 0) std.process.exit(1);
}
