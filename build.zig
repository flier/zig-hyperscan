const std = @import("std");

pub fn build(b: *std.Build) void {
    const skip_examples = b.option(bool, "skip-examples", "Don't build examples") orelse false;
    const skip_tests = b.option(bool, "skip-tests", "Don't build tests") orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add search prefix for HYPERSCAN_ROOT
    if (std.posix.getenv("HYPERSCAN_ROOT")) |p| {
        b.addSearchPrefix(p);
    }

    // Add search prefix for Homebrew
    switch (target.result.os.tag) {
        .macos => switch (target.result.cpu.arch.family()) {
            .aarch64 => b.addSearchPrefix("/opt/homebrew/"),
            .x86 => b.addSearchPrefix("/usr/local/"),
            else => {},
        },
        .linux => b.addSearchPrefix("/home/linuxbrew/.linuxbrew"),
        else => {},
    }

    const hyperscan_mod = b.addModule("hyperscan", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const hyperscan_lib = b.addLibrary(.{
        .name = "hyperscan",
        .linkage = .static,
        .root_module = hyperscan_mod,
    });

    b.installArtifact(hyperscan_lib);

    const hyperscan_dylib = b.addLibrary(.{
        .name = "hyperscan",
        .linkage = .dynamic,
        .root_module = hyperscan_mod,
    });

    b.installArtifact(hyperscan_dylib);

    // Build examples
    if (!skip_examples) {
        const simplegrep = b.addExecutable(.{
            .name = "simplegrep",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/simplegrep.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "hyperscan", .module = hyperscan_mod },
                },
            }),
        });

        simplegrep.linkSystemLibrary("hs");

        b.installArtifact(simplegrep);

        const simplegrep_cmd = b.addRunArtifact(simplegrep);
        simplegrep_cmd.step.dependOn(b.getInstallStep());

        const simplegrep_step = b.step("simplegrep", "Run the simplegrep");
        simplegrep_step.dependOn(&simplegrep_cmd.step);

        if (b.args) |args| {
            simplegrep_cmd.addArgs(args);
        }
    }

    // Build tests
    if (!skip_tests) {
        const unit_tests_mod = b.addModule("unit_tests", .{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hyperscan", .module = hyperscan_mod },
            },
        });

        const mod_tests = b.addTest(.{
            .root_module = hyperscan_mod,
        });

        mod_tests.linkSystemLibrary("hs");

        b.installArtifact(mod_tests);

        const unit_tests = b.addTest(.{
            .root_module = unit_tests_mod,
        });

        unit_tests.linkSystemLibrary("hs");

        b.installArtifact(unit_tests);

        const run_mod_tests = b.addRunArtifact(mod_tests);
        const run_unit_tests = b.addRunArtifact(unit_tests);

        const test_step = b.step("test", "Run unit tests");

        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_unit_tests.step);
    }
}
