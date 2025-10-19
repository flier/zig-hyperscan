const std = @import("std");

pub fn build(b: *std.Build) void {
    const with_zlinter = b.option(bool, "with-zlinter", "Run zlinter") orelse false;
    const with_examples = b.option(bool, "with-examples", "Build examples") orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    addHyperscanToSearchPrefixes(b, target);

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

    addlintCmd(b, with_zlinter);

    addExamples(b, target, optimize, hyperscan_mod, with_examples);

    addTests(b, target, optimize, hyperscan_mod);
}

fn addHyperscanToSearchPrefixes(b: *std.Build, target: std.Build.ResolvedTarget) void {
    // Add search prefix for HYPERSCAN_ROOT
    if (std.posix.getenv("HYPERSCAN_ROOT")) |p| {
        b.addSearchPrefix(p);
    }

    // Add search prefix for Homebrew
    switch (target.result.os.tag) {
        .macos => switch (target.result.cpu.arch.family()) {
            .aarch64 => addSearchPrefix(b, "/opt/homebrew/"),
            .x86 => addSearchPrefix(b, "/usr/local/"),
            else => {},
        },
        .linux => addSearchPrefix(b, "/home/linuxbrew/.linuxbrew"),
        else => {},
    }
}

fn addSearchPrefix(b: *std.Build, prefix: []const u8) void {
    var dir = (std.fs.openDirAbsolute(prefix, .{})) catch return;
    defer dir.close();

    b.addSearchPrefix(prefix);
}

fn addlintCmd(b: *std.Build, with_zlinter: bool) void {
    const lint_cmd = b.step("lint", "Lint source code.");

    if (with_zlinter) {
        if (b.lazyImport(@This(), "zlinter")) |zlinter| {
            lint_cmd.dependOn(step: {
                var builder = zlinter.builder(b, .{});

                inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |f| {
                    const rule: zlinter.BuiltinLintRule = @enumFromInt(f.value);

                    const config = switch (rule) {
                        .declaration_naming => .{
                            .decl_name_min_len = .{
                                .len = 2,
                                .severity = .warning,
                            },
                        },
                        .field_naming => .{
                            .struct_field_min_len = .{
                                .len = 2,
                                .severity = .warning,
                            },
                        },
                        .max_positional_args => .{
                            .max = 7,
                        },
                        .no_inferred_error_unions => {
                            continue;
                        },
                        else => .{},
                    };

                    builder.addRule(.{ .builtin = rule }, config);
                }

                break :step builder.build();
            });
        }
    } else {
        lint_cmd.dependOn(&b.addFail("lint command needs zlinter dependency with `-Dwith-zlinter` option").step);
    }
}

fn addExamples(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, hyperscan_mod: *std.Build.Module, with_examples: bool) void {
    const simplegrep_step = b.step("simplegrep", "Run the simplegrep example");

    if (with_examples) {
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

        if (b.lazyDependency("clap", .{})) |clap| {
            simplegrep.root_module.addImport("clap", clap.module("clap"));
        }

        simplegrep.root_module.linkSystemLibrary("hs", .{});
        simplegrep.root_module.link_libc = true;

        b.installArtifact(simplegrep);

        const simplegrep_cmd = b.addRunArtifact(simplegrep);
        simplegrep_cmd.step.dependOn(b.getInstallStep());

        simplegrep_step.dependOn(&simplegrep_cmd.step);

        if (b.args) |args| {
            simplegrep_cmd.addArgs(args);
        }
    } else {
        simplegrep_step.dependOn(&b.addFail("simplegrep example needs `-Dwith-examples` option to be enabled").step);
    }
}

fn addTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, hyperscan_mod: *std.Build.Module) void {
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

    mod_tests.root_module.linkSystemLibrary("hs", .{});
    mod_tests.root_module.link_libc = true;

    b.installArtifact(mod_tests);

    const unit_tests = b.addTest(.{
        .root_module = unit_tests_mod,
    });

    unit_tests.root_module.linkSystemLibrary("hs", .{});
    unit_tests.root_module.link_libc = true;

    b.installArtifact(unit_tests);

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_unit_tests.step);
}
