const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-evm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Parallel execution demo
    const parallel_exe = b.addExecutable(.{
        .name = "parallel-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parallel_example.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(parallel_exe);

    const run_parallel_cmd = b.addRunArtifact(parallel_exe);
    run_parallel_cmd.step.dependOn(b.getInstallStep());

    const run_parallel_step = b.step("parallel", "Run parallel execution demo");
    run_parallel_step.dependOn(&run_parallel_cmd.step);

    // Optimized parallel execution demo
    const parallel_opt_exe = b.addExecutable(.{
        .name = "parallel-optimized",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parallel_optimized_example.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(parallel_opt_exe);

    const run_parallel_opt_cmd = b.addRunArtifact(parallel_opt_exe);
    run_parallel_opt_cmd.step.dependOn(b.getInstallStep());

    const run_parallel_opt_step = b.step("parallel-opt", "Run optimized parallel execution demo");
    run_parallel_opt_step.dependOn(&run_parallel_opt_cmd.step);

    // Tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}