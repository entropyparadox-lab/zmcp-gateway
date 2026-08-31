const std = @import("std");

pub const config = @import("config.zig");
pub const cache = @import("cache.zig");
pub const upstream = @import("upstream.zig");
pub const gateway = @import("gateway.zig");

pub const Gateway = gateway.Gateway;
pub const GatewayConfig = config.GatewayConfig;
pub const Upstream = upstream.Upstream;
pub const UpstreamTool = upstream.UpstreamTool;
pub const ToolCache = cache.ToolCache;

test "gateway multi-upstream routing, namespacing and caching" {
    const allocator = std.testing.allocator;
    @import("zlog").setMinLevel(.silent);

    var gw = Gateway.init(allocator, .{
        .name = "test-gateway",
        .version = "1.0.0",
        .cache_enabled = true,
        .cache_ttl_sec = 60,
    });
    defer gw.deinit();

    // 1. Math Upstream
    const MathHandler = struct {
        fn handle(ctx: *anyopaque, alloc: std.mem.Allocator, tool_name: []const u8, args_json: []const u8) anyerror!@import("zmcp").CallToolResult {
            _ = ctx;
            if (std.mem.eql(u8, tool_name, "add")) {
                const ParsedArgs = struct { a: f64, b: f64 };
                var parsed = try std.json.parseFromSlice(ParsedArgs, alloc, args_json, .{ .ignore_unknown_fields = true });
                defer parsed.deinit();
                const sum = parsed.value.a + parsed.value.b;
                const out = try std.fmt.allocPrint(alloc, "Sum: {d}", .{sum});
                return @import("zmcp").CallToolResult.text(out);
            }
            return @import("zmcp").CallToolResult.err("Tool not found in math");
        }
    };

    var math_up = Upstream.init(allocator, "math", undefined, MathHandler.handle);
    try math_up.addTool(allocator, .{
        .name = "add",
        .description = "Add two numbers",
        .schema_json = "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"number\"},\"b\":{\"type\":\"number\"}},\"required\":[\"a\",\"b\"]}",
    });
    try gw.registerUpstream(math_up);

    // 2. FS Upstream
    const FsHandler = struct {
        fn handle(ctx: *anyopaque, alloc: std.mem.Allocator, tool_name: []const u8, args_json: []const u8) anyerror!@import("zmcp").CallToolResult {
            _ = ctx;
            _ = alloc;
            _ = args_json;
            if (std.mem.eql(u8, tool_name, "read_file")) {
                return @import("zmcp").CallToolResult.text("file-content-sample");
            }
            return @import("zmcp").CallToolResult.err("Tool not found in fs");
        }
    };

    var fs_up = Upstream.init(allocator, "fs", undefined, FsHandler.handle);
    try fs_up.addTool(allocator, .{
        .name = "read_file",
        .description = "Read a file from disk",
        .schema_json = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}",
    });
    try gw.registerUpstream(fs_up);

    // 3. Test `tools/list`
    const list_req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}";
    const list_resp = (try gw.handleMessage(allocator, list_req)).?;
    defer allocator.free(list_resp);

    try std.testing.expect(std.mem.indexOf(u8, list_resp, "math__add") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_resp, "fs__read_file") != null);

    // 4. Test `tools/call` for `math__add`
    const call_req = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"math__add\",\"arguments\":{\"a\":10,\"b\":32}}}";
    const call_resp = (try gw.handleMessage(allocator, call_req)).?;
    defer allocator.free(call_resp);

    try std.testing.expect(std.mem.indexOf(u8, call_resp, "Sum: 42") != null);

    // 5. Test Cache Hit on second call
    const call_resp2 = (try gw.handleMessage(allocator, call_req)).?;
    defer allocator.free(call_resp2);
    try std.testing.expect(std.mem.indexOf(u8, call_resp2, "Sum: 42") != null);
}

test {
    _ = config;
    _ = cache;
    _ = upstream;
    _ = gateway;
}
