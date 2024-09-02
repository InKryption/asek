const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const unit_test_step = b.step("unit-test", "Run unit tests.");

    {
        const test_step = b.step("test", "Run all tests.");
        test_step.dependOn(unit_test_step);
    }

    const asek_mod = b.addModule("asek", .{
        .root_source_file = b.path("src/asek.zig"),
    });
    _ = asek_mod;

    const unit_test_exe = b.addTest(.{
        .name = "unit-test",
        .root_source_file = b.path("src/asek.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_test_install = b.addInstallArtifact(unit_test_exe, .{});
    b.getInstallStep().dependOn(&unit_test_install.step);

    const unit_test_run = b.addRunArtifact(unit_test_exe);
    unit_test_run.step.dependOn(&unit_test_install.step);
    unit_test_step.dependOn(&unit_test_run.step);
}
