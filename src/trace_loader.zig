// File: src/trace_loader.zig
//
// Ingests a block access-trace into the engine's read/write-set form so the
// conflict-granularity analysis (block_stm.analyzeModels, paper contribution
// C2) can run on real workloads. The trace is the only input the parallelism
// and contention measurements need — the engine does not have to re-execute the
// bytecode, which is why E2/E3 are unblocked by data alone.
//
// Intermediate format (one JSON document; produced from geth's `prestateTracer`
// or Erigon `trace_replayBlockTransactions` stateDiff by a small normalizer):
//
//   {
//     "blocks": [
//       { "number": 21000000,
//         "txs": [
//           { "reads":  [ {"addr":"0x..", "slot":"0x.."}, {"addr":"0x.."} ],
//             "writes": [ {"addr":"0x..", "slot":"0x.."} ] },
//           ...
//         ] }
//     ]
//   }
//
// A key with a `slot` is a storage slot; without one it is an account balance.
// Hex is parsed leniently (any length, optional 0x), so minimal-form values
// from a tracer are accepted.

const std = @import("std");
const Allocator = std.mem.Allocator;
const BigInt = @import("bigint.zig").BigInt;
const sk = @import("state_key.zig");
const StateKey = sk.StateKey;
const as = @import("access_set.zig");
const AccessRecorder = as.AccessRecorder;

pub const KeyJson = struct {
    addr: []const u8,
    slot: ?[]const u8 = null,
};
pub const TxJson = struct {
    reads: []const KeyJson = &.{},
    writes: []const KeyJson = &.{},
};
pub const BlockJson = struct {
    number: u64 = 0,
    txs: []const TxJson = &.{},
};
pub const TraceJson = struct {
    blocks: []const BlockJson = &.{},
};

fn stripHexPrefix(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) return s[2..];
    return s;
}

fn parseAddr(hex: []const u8) ![20]u8 {
    const v = try std.fmt.parseInt(u160, stripHexPrefix(hex), 16);
    var out: [20]u8 = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) out[19 - i] = @truncate(v >> @intCast(8 * i)); // big-endian
    return out;
}

fn parseSlot(hex: []const u8) !BigInt {
    const v = try std.fmt.parseInt(u256, stripHexPrefix(hex), 16);
    return BigInt{ .data = .{
        @truncate(v),
        @truncate(v >> 64),
        @truncate(v >> 128),
        @truncate(v >> 192),
    } };
}

fn keyOf(k: KeyJson) !StateKey {
    const addr = try parseAddr(k.addr);
    if (k.slot) |slot_hex| return StateKey.storageOf(addr, try parseSlot(slot_hex));
    return StateKey.balanceOf(addr);
}

/// Parse the trace document. Caller owns the returned `Parsed` (`.deinit()`).
pub fn parse(allocator: Allocator, json_bytes: []const u8) !std.json.Parsed(TraceJson) {
    return std.json.parseFromSlice(TraceJson, allocator, json_bytes, .{ .ignore_unknown_fields = true });
}

/// Build per-transaction access recorders for one block. Caller frees with
/// `freeRecorders`. The recorders carry the read/write sets that
/// `block_stm.analyzeModels` consumes.
pub fn buildRecorders(allocator: Allocator, block: BlockJson) ![]AccessRecorder {
    const recs = try allocator.alloc(AccessRecorder, block.txs.len);
    errdefer allocator.free(recs);
    for (block.txs, 0..) |tx, i| {
        recs[i] = AccessRecorder.init(allocator);
        errdefer recs[i].deinit();
        for (tx.reads) |k| try recs[i].recordRead(try keyOf(k));
        for (tx.writes) |k| try recs[i].recordWrite(try keyOf(k));
    }
    return recs;
}

pub fn freeRecorders(allocator: Allocator, recs: []AccessRecorder) void {
    for (recs) |*r| r.deinit();
    allocator.free(recs);
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;
const bs = @import("block_stm.zig");

// One block, four ERC-20-style read-modify-write transactions, all on the same
// token contract (0x22..22) but mostly distinct holder-balance slots. tx3 also
// touches slot 2, which tx0 wrote — a genuine dependency. This is the canonical
// case where account-level analysis over-counts conflicts.
const erc20_fixture =
    \\{
    \\  "blocks": [
    \\    { "number": 21000000,
    \\      "txs": [
    \\        { "reads":  [ {"addr":"0x2222222222222222222222222222222222222222","slot":"0x1"},
    \\                      {"addr":"0x2222222222222222222222222222222222222222","slot":"0x2"} ],
    \\          "writes": [ {"addr":"0x2222222222222222222222222222222222222222","slot":"0x1"},
    \\                      {"addr":"0x2222222222222222222222222222222222222222","slot":"0x2"} ] },
    \\        { "reads":  [ {"addr":"0x2222222222222222222222222222222222222222","slot":"0x3"},
    \\                      {"addr":"0x2222222222222222222222222222222222222222","slot":"0x4"} ],
    \\          "writes": [ {"addr":"0x2222222222222222222222222222222222222222","slot":"0x3"},
    \\                      {"addr":"0x2222222222222222222222222222222222222222","slot":"0x4"} ] },
    \\        { "reads":  [ {"addr":"0x2222222222222222222222222222222222222222","slot":"0x5"},
    \\                      {"addr":"0x2222222222222222222222222222222222222222","slot":"0x6"} ],
    \\          "writes": [ {"addr":"0x2222222222222222222222222222222222222222","slot":"0x5"},
    \\                      {"addr":"0x2222222222222222222222222222222222222222","slot":"0x6"} ] },
    \\        { "reads":  [ {"addr":"0x2222222222222222222222222222222222222222","slot":"0x2"},
    \\                      {"addr":"0x2222222222222222222222222222222222222222","slot":"0x7"} ],
    \\          "writes": [ {"addr":"0x2222222222222222222222222222222222222222","slot":"0x2"},
    \\                      {"addr":"0x2222222222222222222222222222222222222222","slot":"0x7"} ] }
    \\      ] }
    \\  ]
    \\}
;

test "trace_loader: parses keys at slot granularity" {
    const a = testing.allocator;
    var parsed = try parse(a, erc20_fixture);
    defer parsed.deinit();
    try testing.expectEqual(@as(usize, 1), parsed.value.blocks.len);
    try testing.expectEqual(@as(usize, 4), parsed.value.blocks[0].txs.len);

    const recs = try buildRecorders(a, parsed.value.blocks[0]);
    defer freeRecorders(a, recs);
    // tx0 read slots 1 and 2 of the token.
    const token: sk.Address = [_]u8{0x22} ** 20;
    try testing.expect(recs[0].readKey(StateKey.storageOf(token, BigInt.init(1))));
    try testing.expect(recs[0].write_set.contains(StateKey.storageOf(token, BigInt.init(2))));
}

test "trace_loader: ERC-20 block — account-level over-counts vs slot/dynamic" {
    const a = testing.allocator;
    var parsed = try parse(a, erc20_fixture);
    defer parsed.deinit();
    const recs = try buildRecorders(a, parsed.value.blocks[0]);
    defer freeRecorders(a, recs);

    const rep = try bs.analyzeModels(a, recs);
    // All four txs touch the token account -> account-level serializes them all.
    try testing.expectEqual(@as(usize, 4), rep.cp_account);
    // Only tx0 and tx3 share a slot (slot 2) -> slot- and dynamic-level see a
    // 2-long critical path; the rest are independent.
    try testing.expectEqual(@as(usize, 2), rep.cp_slot);
    try testing.expectEqual(@as(usize, 2), rep.cp_dynamic);
}
