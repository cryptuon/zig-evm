// File: src/state_test.zig
//
// Offline replay/conformance harness. Given a JSON state test
//
//   { "pre":  { "<addr>": {balance,nonce,code,storage}, ... },
//     "txs":  [ {from,to,value,data,gas}, ... ],
//     "post": { "<addr>": {balance?,nonce?,storage?}, ... } }
//
// it loads the pre-state, runs each transaction through EVM.executeTransaction,
// and checks the resulting accounts against the (partial) expected post-state.
// This is the structure of `geth evm t8n` input/output (alloc + txs -> alloc),
// so expected post-states can be produced by a reference client and replayed
// here with no archive node — the path to real E1 conformance numbers.
//
// Simplifications: the sender is given explicitly as `from` (no secp256k1
// signature recovery), and post checks are partial (only the fields present).

const std = @import("std");
const Allocator = std.mem.Allocator;
const main = @import("main.zig");
const EVM = main.EVM;
const BigInt = main.BigInt;
const Transaction = main.Transaction;

fn strip0x(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) return s[2..];
    return s;
}

fn bigFromHex(s: []const u8) !BigInt {
    const h = strip0x(s);
    if (h.len == 0) return BigInt.zero();
    const v = try std.fmt.parseInt(u256, h, 16);
    return BigInt{ .data = .{
        @truncate(v),
        @truncate(v >> 64),
        @truncate(v >> 128),
        @truncate(v >> 192),
    } };
}

fn addrFromHex(s: []const u8) ![20]u8 {
    const v = try std.fmt.parseInt(u160, strip0x(s), 16);
    var out: [20]u8 = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) out[19 - i] = @truncate(v >> @intCast(8 * i));
    return out;
}

fn bytesFromHex(allocator: Allocator, s: []const u8) ![]u8 {
    const h = strip0x(s);
    const out = try allocator.alloc(u8, h.len / 2);
    errdefer allocator.free(out);
    _ = try std.fmt.hexToBytes(out, h);
    return out;
}

fn getStr(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

pub const Result = struct {
    checks: usize = 0,
    mismatches: usize = 0,
};

/// Run a state test against a fresh EVM and check the post-state. Mismatch
/// diagnostics are printed via std.debug.print.
pub fn run(allocator: Allocator, json_bytes: []const u8) !Result {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    const root = parsed.value.object;

    var evm = try EVM.init(allocator);
    defer evm.deinit();

    // --- load pre-state ---
    if (root.get("pre")) |pre_v| {
        var it = pre_v.object.iterator();
        while (it.next()) |entry| {
            const addr = try addrFromHex(entry.key_ptr.*);
            const acct = entry.value_ptr.*.object;
            var storage = std.AutoHashMap(BigInt, BigInt).init(allocator);
            if (acct.get("storage")) |st_v| {
                var sit = st_v.object.iterator();
                while (sit.next()) |se| {
                    try storage.put(try bigFromHex(se.key_ptr.*), try bigFromHex(se.value_ptr.*.string));
                }
            }
            const code: []const u8 = if (getStr(acct, "code")) |c| try bytesFromHex(allocator, c) else &[_]u8{};
            try evm.accounts.put(addr, .{
                .balance = if (getStr(acct, "balance")) |b| try bigFromHex(b) else BigInt.zero(),
                .nonce = if (getStr(acct, "nonce")) |n| @intCast((try bigFromHex(n)).data[0]) else 0,
                .code = code,
                .storage = storage,
            });
        }
    }

    // --- run transactions ---
    if (root.get("txs")) |txs_v| {
        for (txs_v.array.items) |tx_v| {
            const t = tx_v.object;
            const from = try addrFromHex(getStr(t, "from").?);
            const to: ?[20]u8 = if (getStr(t, "to")) |s|
                (if (strip0x(s).len == 0) null else try addrFromHex(s))
            else
                null;
            const data: []const u8 = if (getStr(t, "data")) |d| try bytesFromHex(allocator, d) else &[_]u8{};
            defer if (data.len > 0) allocator.free(data);
            const gas: u64 = if (getStr(t, "gas")) |g| @intCast((try bigFromHex(g)).data[0]) else 1_000_000;
            const tx = Transaction{
                .from = from,
                .to = to,
                .value = if (getStr(t, "value")) |v| try bigFromHex(v) else BigInt.zero(),
                .data = data,
                .gas_limit = gas,
                .gas_price = BigInt.init(1),
            };
            _ = evm.executeTransaction(tx) catch {}; // a failed/reverted tx still leaves committed state
        }
    }

    // --- check post-state ---
    var result = Result{};
    if (root.get("post")) |post_v| {
        var it = post_v.object.iterator();
        while (it.next()) |entry| {
            const addr = try addrFromHex(entry.key_ptr.*);
            const want = entry.value_ptr.*.object;
            const got = evm.accounts.getPtr(addr);

            if (getStr(want, "balance")) |b| {
                result.checks += 1;
                const expected = try bigFromHex(b);
                const actual = if (got) |g| g.balance else BigInt.zero();
                if (!actual.eq(expected)) {
                    result.mismatches += 1;
                    std.debug.print("  balance mismatch @ {s}\n", .{entry.key_ptr.*});
                }
            }
            if (getStr(want, "nonce")) |n| {
                result.checks += 1;
                const expected: u64 = @intCast((try bigFromHex(n)).data[0]);
                const actual: u64 = if (got) |g| g.nonce else 0;
                if (actual != expected) {
                    result.mismatches += 1;
                    std.debug.print("  nonce mismatch @ {s}: want {d} got {d}\n", .{ entry.key_ptr.*, expected, actual });
                }
            }
            if (want.get("storage")) |st_v| {
                var sit = st_v.object.iterator();
                while (sit.next()) |se| {
                    result.checks += 1;
                    const slot = try bigFromHex(se.key_ptr.*);
                    const expected = try bigFromHex(se.value_ptr.*.string);
                    const actual = if (got) |g| (g.storage.get(slot) orelse BigInt.zero()) else BigInt.zero();
                    if (!actual.eq(expected)) {
                        result.mismatches += 1;
                        std.debug.print("  storage[{s}] mismatch @ {s}\n", .{ se.key_ptr.*, entry.key_ptr.* });
                    }
                }
            }
        }
    }
    return result;
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

// A counter contract (storage[0] += 1 per call) at 0xC0..C0, called once by
// Alice after she sends 1000 wei to Bob.
const fixture =
    \\{
    \\  "pre": {
    \\    "0xa1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1": {"balance":"0xf4240","nonce":"0x0"},
    \\    "0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0": {"balance":"0x0","code":"0x6000546001016000556000"}
    \\  },
    \\  "txs": [
    \\    {"from":"0xa1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1","to":"0xb0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0","value":"0x3e8","gas":"0x186a0"},
    \\    {"from":"0xa1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1","to":"0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0","gas":"0x30d40"}
    \\  ],
    \\  "post": {
    \\    "0xb0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0": {"balance":"0x3e8"},
    \\    "0xa1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1": {"nonce":"0x2"},
    \\    "0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0": {"storage":{"0x0":"0x1"}}
    \\  }
    \\}
;

test "state_test: fixture replays with no mismatches" {
    const res = try run(testing.allocator, fixture);
    try testing.expect(res.checks >= 3);
    try testing.expectEqual(@as(usize, 0), res.mismatches);
}

const fixture_bad =
    \\{
    \\  "pre": { "0xa1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1": {"balance":"0xf4240"} },
    \\  "txs": [ {"from":"0xa1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1","to":"0xb0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0","value":"0x3e8","gas":"0x186a0"} ],
    \\  "post": { "0xb0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0": {"balance":"0x999"} }
    \\}
;

test "state_test: a wrong expectation is reported as a mismatch" {
    const res = try run(testing.allocator, fixture_bad);
    try testing.expectEqual(@as(usize, 1), res.mismatches);
}
