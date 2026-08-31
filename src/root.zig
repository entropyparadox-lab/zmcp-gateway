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

test "gateway routing, flexible naming, mutation cache invalidation" {
    const allocator = std.testing.allocator;
    @import("zlog").setMinLevel(.silent);

    var gw = Gateway.init(allocator, .{
        .name = "test-gateway",
        .version = "1.0.0",
        .cache_enabled = true,
        .cache_ttl_sec = 60,
    });
    defer gw.deinit();

    // 1. Register EarnLearning Upstream
    var wallet_balance: i64 = 1000;

    const ELHandler = struct {
        balance_ptr: *i64,

        fn handle(ctx: *anyopaque, alloc: std.mem.Allocator, tool_name: []const u8, args_json: []const u8) anyerror!@import("zmcp").CallToolResult {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            _ = args_json;

            if (std.mem.eql(u8, tool_name, "wallet_get")) {
                const out = try std.fmt.allocPrint(alloc, "{{\"balance\":{d}}}", .{self.balance_ptr.*});
                return @import("zmcp").CallToolResult.text(out);
            } else if (std.mem.eql(u8, tool_name, "company_transfer")) {
                self.balance_ptr.* -= 200;
                return @import("zmcp").CallToolResult.text("{\"status\":\"transfer_success\"}");
            }
            return @import("zmcp").CallToolResult.err("Tool not found");
        }
    };

    var el_ctx = ELHandler{ .balance_ptr = &wallet_balance };
    var el_up = Upstream.init(allocator, "earnlearning", &el_ctx, ELHandler.handle);
    try el_up.addTool(allocator, .{
        .name = "wallet_get",
        .description = "Get current wallet balance",
        .schema_json = "{}",
    });
    try el_up.addTool(allocator, .{
        .name = "company_transfer",
        .description = "Transfer funds to another company",
        .schema_json = "{}",
    });
    try gw.registerUpstream(el_up);

    // 2. Read query via Hermes-style naming (`mcp__earnlearning__wallet_get`)
    const read_req1 = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"mcp__earnlearning__wallet_get\",\"arguments\":{}}}";
    const read_resp1 = (try gw.handleMessage(allocator, read_req1)).?;
    defer allocator.free(read_resp1);
    try std.testing.expect(std.mem.indexOf(u8, read_resp1, "1000") != null);

    // 3. Second read -> Must Hit Cache (returns 1000)
    const read_resp2 = (try gw.handleMessage(allocator, read_req1)).?;
    defer allocator.free(read_resp2);
    try std.testing.expect(std.mem.indexOf(u8, read_resp2, "1000") != null);

    // 4. Mutation: Transfer funds (`earnlearning__company_transfer`)
    const mut_req = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"earnlearning__company_transfer\",\"arguments\":{}}}";
    const mut_resp = (try gw.handleMessage(allocator, mut_req)).?;
    defer allocator.free(mut_resp);
    try std.testing.expect(std.mem.indexOf(u8, mut_resp, "transfer_success") != null);
    try std.testing.expectEqual(@as(i64, 800), wallet_balance);

    // 5. Read query again -> Cache MUST have been invalidated by mutation! Must return 800!
    const read_resp3 = (try gw.handleMessage(allocator, read_req1)).?;
    defer allocator.free(read_resp3);
    try std.testing.expect(std.mem.indexOf(u8, read_resp3, "800") != null);

    // 6. Dot-delimited naming test (`earnlearning.wallet_get`)
    const dot_req = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"earnlearning.wallet_get\",\"arguments\":{}}}";
    const dot_resp = (try gw.handleMessage(allocator, dot_req)).?;
    defer allocator.free(dot_resp);
    try std.testing.expect(std.mem.indexOf(u8, dot_resp, "800") != null);
}

test {
    _ = config;
    _ = cache;
    _ = upstream;
    _ = gateway;
}
