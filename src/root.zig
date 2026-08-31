const std = @import("std");

pub const config = @import("config.zig");
pub const upstream = @import("upstream.zig");
pub const gateway = @import("gateway.zig");

pub const Gateway = gateway.Gateway;
pub const GatewayConfig = config.GatewayConfig;
pub const Upstream = upstream.Upstream;
pub const UpstreamTool = upstream.UpstreamTool;

test "gateway 100% transparent routing, zero-cache, flexible naming" {
    const allocator = std.testing.allocator;
    @import("zlog").setMinLevel(.silent);

    var gw = Gateway.init(allocator, .{
        .name = "test-gateway",
        .version = "1.1.0",
    });
    defer gw.deinit();

    // 1. Register EarnLearning Upstream with dynamic state
    var call_count: u32 = 0;

    const ELHandler = struct {
        count_ptr: *u32,

        fn handle(ctx: *anyopaque, alloc: std.mem.Allocator, tool_name: []const u8, args_json: []const u8) anyerror!@import("zmcp").CallToolResult {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            _ = args_json;

            if (std.mem.eql(u8, tool_name, "wallet_get")) {
                self.count_ptr.* += 1;
                const out = try std.fmt.allocPrint(alloc, "{{\"balance\":1000,\"call_count\":{d}}}", .{self.count_ptr.*});
                return @import("zmcp").CallToolResult.text(out);
            }
            return @import("zmcp").CallToolResult.err("Tool not found");
        }
    };

    var el_ctx = ELHandler{ .count_ptr = &call_count };
    var el_up = Upstream.init(allocator, "earnlearning", &el_ctx, ELHandler.handle);
    try el_up.addTool(allocator, .{
        .name = "wallet_get",
        .description = "Get current wallet balance",
        .schema_json = "{}",
    });
    try gw.registerUpstream(el_up);

    // 2. Read query via Hermes-style naming (`mcp__earnlearning__wallet_get`)
    const read_req1 = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"mcp__earnlearning__wallet_get\",\"arguments\":{}}}";
    const read_resp1 = (try gw.handleMessage(allocator, read_req1)).?;
    defer allocator.free(read_resp1);
    try std.testing.expect(std.mem.indexOf(u8, read_resp1, "call_count") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_resp1, ":1") != null);

    // 3. Second read -> ZERO CACHE: Must directly hit upstream and increment call_count to 2!
    const read_resp2 = (try gw.handleMessage(allocator, read_req1)).?;
    defer allocator.free(read_resp2);
    try std.testing.expect(std.mem.indexOf(u8, read_resp2, "call_count") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_resp2, ":2") != null);

    // 4. Dot notation routing (`earnlearning.wallet_get`)
    const dot_req = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"earnlearning.wallet_get\",\"arguments\":{}}}";
    const dot_resp = (try gw.handleMessage(allocator, dot_req)).?;
    defer allocator.free(dot_resp);
    try std.testing.expect(std.mem.indexOf(u8, dot_resp, "call_count") != null);
    try std.testing.expect(std.mem.indexOf(u8, dot_resp, ":3") != null);
}

test {
    _ = config;
    _ = upstream;
    _ = gateway;
}
