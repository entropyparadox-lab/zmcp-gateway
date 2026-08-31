const std = @import("std");
const Allocator = std.mem.Allocator;
const zmcp = @import("zmcp");

pub const UpstreamTool = struct {
    name: []const u8,
    description: []const u8,
    schema_json: []const u8,
    cache_ttl_sec: u32 = 0, // 0 = Pure Pass-Through (Default / Safe), >0 = Explicit Opt-In Cache
};

pub const UpstreamHandler = *const fn (ctx: *anyopaque, allocator: Allocator, tool_name: []const u8, args_json: []const u8) anyerror!zmcp.CallToolResult;

pub const Upstream = struct {
    namespace: []const u8,
    ctx: *anyopaque,
    handler_fn: UpstreamHandler,
    tools: std.ArrayList(UpstreamTool),

    pub fn init(allocator: Allocator, namespace: []const u8, ctx: *anyopaque, handler: UpstreamHandler) Upstream {
        _ = allocator;
        return .{
            .namespace = namespace,
            .ctx = ctx,
            .handler_fn = handler,
            .tools = .empty,
        };
    }

    pub fn deinit(self: *Upstream, allocator: Allocator) void {
        self.tools.deinit(allocator);
    }

    pub fn addTool(self: *Upstream, allocator: Allocator, tool: UpstreamTool) !void {
        try self.tools.append(allocator, tool);
    }

    pub fn call(self: *Upstream, allocator: Allocator, tool_name: []const u8, args_json: []const u8) !zmcp.CallToolResult {
        return self.handler_fn(self.ctx, allocator, tool_name, args_json);
    }
};
