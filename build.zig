const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("chappie_metrics", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "chappie_metrics",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run metrics library tests");
    test_step.dependOn(&run_tests.step);

    const labels_module = b.createModule(.{
        .root_source_file = b.path("src/labels.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const benchmark_module = b.createModule(.{
        .root_source_file = b.path("bench/atomic_counter.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    benchmark_module.addImport("labels", labels_module);
    const benchmark = b.addExecutable(.{
        .name = "atomic_counter_bench",
        .root_module = benchmark_module,
    });
    const run_benchmark = b.addRunArtifact(benchmark);
    const benchmark_step = b.step("bench", "Run ReleaseFast atomic counter contention benchmark");
    benchmark_step.dependOn(&run_benchmark.step);

    _ = module;
}
