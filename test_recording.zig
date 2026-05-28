// Root for the `recording-test` build target. Kept at the repository root (like
// test_engine.zig) so that the test file's `@import("../src/main.zig")` resolves
// within the module root. Run with: zig build recording-test
comptime {
    _ = @import("tests/test_access_recording.zig");
    _ = @import("tests/test_block_evm.zig");
    _ = @import("tests/test_gas_eip2929.zig");
    _ = @import("tests/test_replay.zig");
    _ = @import("src/state_test.zig");
}
