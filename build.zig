const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Sibling module imports (The Complete 7-Library Zig Stack)
    const zcli_mod = b.createModule(.{
        .root_source_file = b.path("../zcli/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zserde_mod = b.createModule(.{
        .root_source_file = b.path("../zserde/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zmcp_mod = b.createModule(.{
        .root_source_file = b.path("../zmcp/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zbench_mod = b.createModule(.{
        .root_source_file = b.path("../zbench/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zfetch_mod = b.createModule(.{
        .root_source_file = b.path("../zfetch/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zenv_mod = b.createModule(.{
        .root_source_file = b.path("../zenv/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zlog_mod = b.createModule(.{
        .root_source_file = b.path("../zlog/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 1. Root library module
    const gateway_mod = b.addModule("zmcp-gateway", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    gateway_mod.addImport("zcli", zcli_mod);
    gateway_mod.addImport("zserde", zserde_mod);
    gateway_mod.addImport("zmcp", zmcp_mod);
    gateway_mod.addImport("zbench", zbench_mod);
    gateway_mod.addImport("zfetch", zfetch_mod);
    gateway_mod.addImport("zenv", zenv_mod);
    gateway_mod.addImport("zlog", zlog_mod);

    // 2. Main Gateway Binary
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("zcli", zcli_mod);
    exe_mod.addImport("zserde", zserde_mod);
    exe_mod.addImport("zmcp", zmcp_mod);
    exe_mod.addImport("zbench", zbench_mod);
    exe_mod.addImport("zfetch", zfetch_mod);
    exe_mod.addImport("zenv", zenv_mod);
    exe_mod.addImport("zlog", zlog_mod);
    exe_mod.addImport("gateway", gateway_mod);

    const exe = b.addExecutable(.{
        .name = "zmcp-gateway",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // 3. Run Step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run zmcp-gateway");
    run_step.dependOn(&run_cmd.step);

    // 4. Unit Tests
    const unit_tests = b.addTest(.{
        .root_module = gateway_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run zmcp-gateway tests");
    test_step.dependOn(&run_unit_tests.step);

    // 5. Benchmark Step
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("tests/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_mod.addImport("zcli", zcli_mod);
    bench_mod.addImport("zserde", zserde_mod);
    bench_mod.addImport("zmcp", zmcp_mod);
    bench_mod.addImport("zbench", zbench_mod);
    bench_mod.addImport("zfetch", zfetch_mod);
    bench_mod.addImport("zenv", zenv_mod);
    bench_mod.addImport("zlog", zlog_mod);
    bench_mod.addImport("gateway", gateway_mod);

    const bench_exe = b.addExecutable(.{
        .name = "gateway-bench",
        .root_module = bench_mod,
    });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run gateway routing benchmark");
    bench_step.dependOn(&run_bench.step);
}
