const std = @import("std");
const zbench = @import("zbench");
const zmcp = @import("zmcp");
const gateway_lib = @import("gateway");

var bench_gw: gateway_lib.Gateway = undefined;
var bench_alloc: std.mem.Allocator = undefined;

const sample_req = "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"calc__add\",\"arguments\":{\"a\":15,\"b\":27}}}";

fn benchRouting() void {
    var req_arena = std.heap.ArenaAllocator.init(bench_alloc);
    defer req_arena.deinit();
    const resp = bench_gw.handleMessage(req_arena.allocator(), sample_req) catch unreachable;
    _ = zbench.blackBox(resp);
}

pub fn main(init: std.process.Init) !void {
    bench_alloc = init.arena.allocator();

    bench_gw = gateway_lib.Gateway.init(bench_alloc, .{
        .name = "bench-gw",
        .version = "1.1.0",
    });
    defer bench_gw.deinit();

    const CalcHandler = struct {
        fn handle(ctx: *anyopaque, alloc: std.mem.Allocator, tool_name: []const u8, args_json: []const u8) anyerror!zmcp.CallToolResult {
            _ = ctx;
            _ = alloc;
            _ = tool_name;
            _ = args_json;
            return zmcp.CallToolResult.text("Result: 42");
        }
    };

    var calc_up = gateway_lib.Upstream.init(bench_alloc, "calc", undefined, CalcHandler.handle);
    try calc_up.addTool(bench_alloc, .{
        .name = "add",
        .description = "Add two numbers",
        .schema_json = "{}",
    });
    try bench_gw.registerUpstream(calc_up);

    var suite = zbench.BenchmarkSuite.init(bench_alloc);
    defer suite.deinit();

    try suite.add("Gateway Direct Multiplexing", benchRouting, .{
        .warmup_ms = 100,
        .sample_count = 50,
    });

    try suite.run();
}
