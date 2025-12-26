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

    // Quick benchmark
    const benchmark_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/quick_benchmark.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(benchmark_exe);

    const run_benchmark_cmd = b.addRunArtifact(benchmark_exe);
    run_benchmark_cmd.step.dependOn(b.getInstallStep());

    const run_benchmark_step = b.step("benchmark", "Run quick optimization benchmarks");
    run_benchmark_step.dependOn(&run_benchmark_cmd.step);

    // Simple benchmark
    const simple_benchmark_exe = b.addExecutable(.{
        .name = "simple-benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/simple_benchmark.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(simple_benchmark_exe);

    const run_simple_benchmark_cmd = b.addRunArtifact(simple_benchmark_exe);
    run_simple_benchmark_cmd.step.dependOn(b.getInstallStep());

    const run_simple_benchmark_step = b.step("bench", "Run simple optimization benchmark");
    run_simple_benchmark_step.dependOn(&run_simple_benchmark_cmd.step);

    // Standalone benchmark demo
    const benchmark_demo_exe = b.addExecutable(.{
        .name = "benchmark-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(benchmark_demo_exe);

    const run_benchmark_demo_cmd = b.addRunArtifact(benchmark_demo_exe);
    run_benchmark_demo_cmd.step.dependOn(b.getInstallStep());

    const run_benchmark_demo_step = b.step("demo", "Run optimization results demo");
    run_benchmark_demo_step.dependOn(&run_benchmark_demo_cmd.step);

    // Comprehensive benchmark suite
    const full_benchmark_exe = b.addExecutable(.{
        .name = "full-benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(full_benchmark_exe);

    const run_full_benchmark_cmd = b.addRunArtifact(full_benchmark_exe);
    run_full_benchmark_cmd.step.dependOn(b.getInstallStep());

    const run_full_benchmark_step = b.step("bench-full", "Run comprehensive benchmark suite");
    run_full_benchmark_step.dependOn(&run_full_benchmark_cmd.step);

    // Ethereum Compliance Test Runner
    const compliance_exe = b.addExecutable(.{
        .name = "compliance-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/run_compliance.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(compliance_exe);

    const run_compliance_cmd = b.addRunArtifact(compliance_exe);
    run_compliance_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_compliance_cmd.addArgs(args);
    }

    const run_compliance_step = b.step("compliance", "Run Ethereum compliance tests");
    run_compliance_step.dependOn(&run_compliance_cmd.step);

    // Shared library for FFI
    const lib = b.addSharedLibrary(.{
        .name = "zigevm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ffi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.linkLibC();

    b.installArtifact(lib);

    // Also create static library
    const static_lib = b.addStaticLibrary(.{
        .name = "zigevm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ffi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    static_lib.linkLibC();

    b.installArtifact(static_lib);

    // Install the header file
    b.installFile("include/zigevm.h", "include/zigevm.h");

    // Add lib step
    const lib_step = b.step("lib", "Build shared and static libraries");
    lib_step.dependOn(&lib.step);
    lib_step.dependOn(&static_lib.step);

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