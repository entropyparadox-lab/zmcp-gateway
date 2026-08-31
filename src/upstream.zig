const std = @import("std");
const Allocator = std.mem.Allocator;
const zmcp = @import("zmcp");

pub const UpstreamTool = struct {
    name: []const u8,
    description: []const u8,
    schema_json: []const u8,
};

pub const Upstream = struct {
    namespace: []const u8,
    tools: std.ArrayList(UpstreamTool),
    handler_fn: *const fn (ctx: *anyopaque, alloc: Allocator, tool_name: []const u8, args_json: []const u8) anyerror!zmcp.CallToolResult,
    ctx: *anyopaque,

    pub fn init(
        allocator: Allocator,
        namespace: []const u8,
        ctx: *anyopaque,
        handler_fn: *const fn (ctx: *anyopaque, alloc: Allocator, tool_name: []const u8, args_json: []const u8) anyerror!zmcp.CallToolResult,
    ) Upstream {
        return .{
            .namespace = namespace,
            .tools = std.ArrayList(UpstreamTool).initCapacity(allocator, 0) catch .empty,
            .handler_fn = handler_fn,
            .ctx = ctx,
        };
    }

    pub fn addTool(self: *Upstream, allocator: Allocator, tool: UpstreamTool) !void {
        try self.tools.append(allocator, tool);
    }

    pub fn deinit(self: *Upstream, allocator: Allocator) void {
        self.tools.deinit(allocator);
    }

    pub fn call(self: *Upstream, allocator: Allocator, tool_name: []const u8, args_json: []const u8) !zmcp.CallToolResult {
        return self.handler_fn(self.ctx, allocator, tool_name, args_json);
    }
};
