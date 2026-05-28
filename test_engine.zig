// Test entrypoint for the serializable parallel-execution engine.
//
// Kept separate from test.zig because the legacy compliance test files
// (tests/eth_compliance.zig, tests/eth_test_loader.zig) and src/call_frame.zig
// have not yet been migrated to the Zig 0.15.x standard-library API, so the
// full `zig build test` target does not currently compile. Run these with:
//
//     zig build engine-test
//
comptime {
    _ = @import("src/state_key.zig");
    _ = @import("src/mvcc.zig");
    _ = @import("src/access_set.zig");
    _ = @import("src/block_stm.zig");
    _ = @import("src/trace_loader.zig");
    _ = @import("src/precompiles.zig");
    _ = @import("tests/test_block_stm_random.zig");
}
