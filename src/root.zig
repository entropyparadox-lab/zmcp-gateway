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

test "gateway explicit opt-in caching vs zero-cache default" {
    const allocator = std.testing.allocator;
    @import("zlog").setMinLevel(.silent);

    var gw = Gateway.init(allocator, .{
        .name = "test-gateway",
        .version = "1.2.0",
    });
    defer gw.deinit();

    var dynamic_calls: u32 = 0;
    var static_calls: u32 = 0;

    const TestHandler = struct {
        dyn_ptr: *u32,
        stat_ptr: *u32,

        fn handle(ctx: *anyopaque, alloc: std.mem.Allocator, tool_name: []const u8, args_json: []const u8) anyerror!@import("zmcp").CallToolResult {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            _ = args_json;

            if (std.mem.eql(u8, tool_name, "poll_status")) {
                self.dyn_ptr.* += 1;
                const out = try std.fmt.allocPrint(alloc, "{{\"status\":\"pending\",\"seq\":{d}}}", .{self.dyn_ptr.*});
                return @import("zmcp").CallToolResult.text(out);
            } else if (std.mem.eql(u8, tool_name, "get_country_code")) {
                self.stat_ptr.* += 1;
                return @import("zmcp").CallToolResult.text("{\"code\":\"KR\",\"name\":\"Korea\"}");
            }
            return @import("zmcp").CallToolResult.err("Tool not found");
        }
    };

    var handler_ctx = TestHandler{ .dyn_ptr = &dynamic_calls, .stat_ptr = &static_calls };
    var up = Upstream.init(allocator, "sys", &handler_ctx, TestHandler.handle);

    // Tool 1: Default cache_ttl_sec = 0 (Pure Pass-Through, Safe for Polling)
    try up.addTool(allocator, .{
        .name = "poll_status",
        .description = "Poll dynamic task status",
        .schema_json = "{}",
        .cache_ttl_sec = 0,
    });

    // Tool 2: Explicit Opt-In cache_ttl_sec = 3600 (Safe for Immutable Metadata)
    try up.addTool(allocator, .{
        .name = "get_country_code",
        .description = "Get static country metadata",
        .schema_json = "{}",
        .cache_ttl_sec = 3600,
    });
    try gw.registerUpstream(up);

    // --- Dynamic Tool Test (Default: cache_ttl_sec = 0) ---
    const poll_req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"sys__poll_status\",\"arguments\":{}}}";
    if (try gw.handleMessage(allocator, poll_req)) |resp| allocator.free(resp);
    if (try gw.handleMessage(allocator, poll_req)) |resp| allocator.free(resp);
    if (try gw.handleMessage(allocator, poll_req)) |resp| allocator.free(resp);
    // Must have executed 3 times without caching
    try std.testing.expectEqual(@as(u32, 3), dynamic_calls);

    // --- Static Opt-In Tool Test (cache_ttl_sec = 3600) ---
    const static_req = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"sys__get_country_code\",\"arguments\":{}}}";
    if (try gw.handleMessage(allocator, static_req)) |resp| allocator.free(resp);
    if (try gw.handleMessage(allocator, static_req)) |resp| allocator.free(resp);
    if (try gw.handleMessage(allocator, static_req)) |resp| allocator.free(resp);
    // Must have executed only ONCE, subsequent calls served from cache!
    try std.testing.expectEqual(@as(u32, 1), static_calls);
}

test {
    _ = config;
    _ = cache;
    _ = upstream;
    _ = gateway;
}
