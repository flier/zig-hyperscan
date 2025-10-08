const std = @import("std");

pub fn build(b: *std.Build) void {
    const with_examples = b.option(bool, "with-examples", "Build examples") orelse false;
    const with_tests = b.option(bool, "with-tests", "Build tests") orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    if (with_examples) {
        const simplegrep = b.addExecutable(.{
            .name = "simplegrep",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/simplegrep.zig"),
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

    if (with_tests) {
        const unit_tests = b.addModule("unit_tests", .{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hyperscan", .module = hyperscan_mod },
            },
        });

        const run_mod_tests = b.addRunArtifact(b.addTest(.{
            .root_module = hyperscan_mod,
        }));

        const run_unit_tests = b.addRunArtifact(b.addTest(.{
            .root_module = unit_tests,
        }));

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_unit_tests.step);
    }
}
