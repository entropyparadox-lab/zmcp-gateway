const std = @import("std");
const zmcp = @import("zmcp");
const zlog = @import("zlog");
const gateway_mod = @import("root.zig");
const Gateway = gateway_mod.Gateway;
const Upstream = gateway_mod.Upstream;
const testing = std.testing;

// ============================================================================
// Multi-Upstream Multiplexer Test
// ============================================================================

test "zmcp-gateway: multi-upstream tools/list aggregation and tool routing" {
    const allocator = testing.allocator;
    zlog.setMinLevel(.silent);

    var gw = Gateway.init(allocator, .{
        .name = "enterprise-mcp-hub",
        .version = "1.0.0",
    });
    defer gw.deinit();

    // Upstream 1: Database tools
    const DbHandler = struct {
        fn handle(_: *anyopaque, alloc: std.mem.Allocator, tool_name: []const u8, _: []const u8) anyerror!zmcp.CallToolResult {
            _ = alloc;
            if (std.mem.eql(u8, tool_name, "query")) {
                return zmcp.CallToolResult.text("db: rows [1, 2, 3]");
            }
            return zmcp.CallToolResult.err("DB tool not found");
        }
    };
    var db_ctx: u8 = 0;
    var up_db = Upstream.init(allocator, "db", &db_ctx, DbHandler.handle);
    try up_db.addTool(allocator, .{
        .name = "query",
        .description = "Execute SQL query",
        .schema_json = "{}",
    });
    try gw.registerUpstream(up_db);

    // Upstream 2: Network tools
    const NetHandler = struct {
        fn handle(_: *anyopaque, alloc: std.mem.Allocator, tool_name: []const u8, _: []const u8) anyerror!zmcp.CallToolResult {
            _ = alloc;
            if (std.mem.eql(u8, tool_name, "ping")) {
                return zmcp.CallToolResult.text("net: pong 12ms");
            }
            return zmcp.CallToolResult.err("Net tool not found");
        }
    };
    var net_ctx: u8 = 0;
    var up_net = Upstream.init(allocator, "net", &net_ctx, NetHandler.handle);
    try up_net.addTool(allocator, .{
        .name = "ping",
        .description = "Network ICMP ping",
        .schema_json = "{}",
    });
    try gw.registerUpstream(up_net);

    // 1. tools/list must aggregate both upstreams with namespace prefix
    const list_req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}";
    const list_resp = (try gw.handleMessage(allocator, list_req)).?;
    defer allocator.free(list_resp);

    try testing.expect(std.mem.indexOf(u8, list_resp, "db__query") != null);
    try testing.expect(std.mem.indexOf(u8, list_resp, "net__ping") != null);

    // 2. Call tool on upstream 1 (db__query)
    const call_db_req = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"db__query\",\"arguments\":{}}}";
    const call_db_resp = (try gw.handleMessage(allocator, call_db_req)).?;
    defer allocator.free(call_db_resp);
    try testing.expect(std.mem.indexOf(u8, call_db_resp, "rows [1, 2, 3]") != null);

    // 3. Call tool on upstream 2 (net__ping)
    const call_net_req = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"net__ping\",\"arguments\":{}}}";
    const call_net_resp = (try gw.handleMessage(allocator, call_net_req)).?;
    defer allocator.free(call_net_resp);
    try testing.expect(std.mem.indexOf(u8, call_net_resp, "pong 12ms") != null);

    // 4. Call unknown tool on unknown upstream
    const call_bad_req = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"unknown__tool\",\"arguments\":{}}}";
    const call_bad_resp = (try gw.handleMessage(allocator, call_bad_req)).?;
    defer allocator.free(call_bad_resp);
    try testing.expect(std.mem.indexOf(u8, call_bad_resp, "\"code\":-32001") != null);
}

// ============================================================================
// Protocol Error Tests
// ============================================================================

test "zmcp-gateway: protocol error code responses" {
    const allocator = testing.allocator;
    zlog.setMinLevel(.silent);

    var gw = Gateway.init(allocator, .{
        .name = "test-hub",
        .version = "1.0.0",
    });
    defer gw.deinit();

    // 1. Parse error
    const r1 = (try gw.handleMessage(allocator, "{bad_json")).?;
    defer allocator.free(r1);
    try testing.expect(std.mem.indexOf(u8, r1, "\"code\":-32700") != null);

    // 2. Invalid request (missing method)
    const r2 = (try gw.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":1}")).?;
    defer allocator.free(r2);
    try testing.expect(std.mem.indexOf(u8, r2, "\"code\":-32600") != null);

    // 3. Method not found
    const r3 = (try gw.handleMessage(allocator, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"invalid/route\"}")).?;
    defer allocator.free(r3);
    try testing.expect(std.mem.indexOf(u8, r3, "\"code\":-32601") != null);
}
