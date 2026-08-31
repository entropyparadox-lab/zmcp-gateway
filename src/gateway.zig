const std = @import("std");
const Allocator = std.mem.Allocator;
const zmcp = @import("zmcp");
const zlog = @import("zlog");
const config_mod = @import("config.zig");
const cache_mod = @import("cache.zig");
const upstream_mod = @import("upstream.zig");

pub const BufferWriter = struct {
    list: *std.ArrayList(u8),
    allocator: Allocator,

    pub fn writeByte(self: *BufferWriter, byte: u8) !void {
        try self.list.append(self.allocator, byte);
    }

    pub fn writeAll(self: *BufferWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }

    pub fn print(self: *BufferWriter, comptime fmt: []const u8, args: anytype) !void {
        var tmp_buf: [512]u8 = undefined;
        const formatted = try std.fmt.bufPrint(&tmp_buf, fmt, args);
        try self.writeAll(formatted);
    }
};

pub const Gateway = struct {
    allocator: Allocator,
    config: config_mod.GatewayConfig,
    cache: cache_mod.ToolCache,
    upstreams: std.ArrayList(upstream_mod.Upstream),

    pub fn init(allocator: Allocator, config: config_mod.GatewayConfig) Gateway {
        return .{
            .allocator = allocator,
            .config = config,
            .cache = cache_mod.ToolCache.init(allocator, config.cache_ttl_sec, config.cache_enabled),
            .upstreams = .empty,
        };
    }

    pub fn deinit(self: *Gateway) void {
        for (self.upstreams.items) |*up| {
            up.deinit(self.allocator);
        }
        self.upstreams.deinit(self.allocator);
        self.cache.deinit();
    }

    pub fn registerUpstream(self: *Gateway, upstream: upstream_mod.Upstream) !void {
        try self.upstreams.append(self.allocator, upstream);
    }

    /// Handles a single incoming MCP JSON-RPC message from an AI Agent client
    pub fn handleMessage(self: *Gateway, allocator: Allocator, raw_json: []const u8) !?[]u8 {
        var span = zlog.startSpan("mcp_gateway_dispatch", null);
        defer span.end();

        const traceparent = span.toTraceparent();

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const parsed_json = std.json.parseFromSlice(
            std.json.Value,
            arena_alloc,
            raw_json,
            .{},
        ) catch {
            return try self.formatErrorResponse(allocator, .null_id, .parse_error, "Parse error");
        };

        const root = parsed_json.value;
        if (root != .object) {
            return try self.formatErrorResponse(allocator, .null_id, .invalid_request, "Invalid JSON-RPC request");
        }

        const method_val = root.object.get("method") orelse {
            return try self.formatErrorResponse(allocator, .null_id, .invalid_request, "Missing method");
        };
        if (method_val != .string) {
            return try self.formatErrorResponse(allocator, .null_id, .invalid_request, "Method must be string");
        }
        const method = method_val.string;

        const id_val = root.object.get("id");
        const req_id: ?zmcp.RequestId = if (id_val) |id| switch (id) {
            .integer => |i| zmcp.RequestId{ .integer = i },
            .string => |s| zmcp.RequestId{ .string = s },
            .null => zmcp.RequestId.null_id,
            else => zmcp.RequestId.null_id,
        } else null;

        const params_val = root.object.get("params");

        // Dispatch
        const maybe_resp = blk: {
            if (std.mem.eql(u8, method, "initialize")) {
                if (req_id == null) break :blk null;
                break :blk try self.handleInitialize(arena_alloc, req_id.?);
            } else if (std.mem.eql(u8, method, "notifications/initialized") or std.mem.eql(u8, method, "initialized")) {
                break :blk null;
            } else if (std.mem.eql(u8, method, "ping")) {
                if (req_id == null) break :blk null;
                break :blk try self.formatSuccessResponse(arena_alloc, req_id.?, "{}");
            } else if (std.mem.eql(u8, method, "tools/list")) {
                if (req_id == null) break :blk null;
                break :blk try self.handleToolsList(arena_alloc, req_id.?);
            } else if (std.mem.eql(u8, method, "tools/call")) {
                if (req_id == null) break :blk null;
                break :blk try self.handleToolsCall(arena_alloc, req_id.?, params_val, &traceparent);
            } else {
                if (req_id) |rid| {
                    break :blk try self.formatErrorResponse(arena_alloc, rid, .method_not_found, "Method not found");
                }
                break :blk null;
            }
        };

        if (maybe_resp) |resp| {
            return try allocator.dupe(u8, resp);
        }
        return null;
    }

    fn handleInitialize(self: *Gateway, allocator: Allocator, id: zmcp.RequestId) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.print("{{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{{\"tools\":{{\"listChanged\":false}}}},\"serverInfo\":{{\"name\":\"{s}\",\"version\":\"{s}\"}}}}", .{
            self.config.name,
            self.config.version,
        });

        const res_json = try buf.toOwnedSlice(allocator);
        defer allocator.free(res_json);

        return self.formatSuccessResponse(allocator, id, res_json);
    }

    fn handleToolsList(self: *Gateway, allocator: Allocator, id: zmcp.RequestId) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"tools\":[");

        var total_tools: usize = 0;
        for (self.upstreams.items) |up| {
            for (up.tools.items) |tool| {
                if (total_tools > 0) try writer.writeByte(',');
                try writer.print("{{\"name\":\"{s}__{s}\",\"description\":\"{s}\",\"inputSchema\":{s}}}", .{
                    up.namespace,
                    tool.name,
                    tool.description,
                    tool.schema_json,
                });
                total_tools += 1;
            }
        }

        try writer.writeAll("]}");

        const res_json = try buf.toOwnedSlice(allocator);
        defer allocator.free(res_json);

        return self.formatSuccessResponse(allocator, id, res_json);
    }

    fn handleToolsCall(self: *Gateway, allocator: Allocator, id: zmcp.RequestId, params_val: ?std.json.Value, traceparent: []const u8) ![]u8 {
        if (params_val == null or params_val.? != .object) {
            return self.formatErrorResponse(allocator, id, .invalid_params, "Expected params object");
        }

        const name_val = params_val.?.object.get("name") orelse {
            return self.formatErrorResponse(allocator, id, .invalid_params, "Missing tool name");
        };
        if (name_val != .string) {
            return self.formatErrorResponse(allocator, id, .invalid_params, "Tool name must be string");
        }
        const full_name = name_val.string;

        const args_val = params_val.?.object.get("arguments");
        var args_json_slice: []const u8 = "{}";
        var allocated_args: ?[]u8 = null;
        defer if (allocated_args) |a| allocator.free(a);

        if (args_val) |av| {
            if (av == .object) {
                allocated_args = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(av, .{})});
                args_json_slice = allocated_args.?;
            }
        }

        // 1. Check in-memory cache
        if (self.cache.get(full_name, args_json_slice)) |cached_resp| {
            zlog.info("Tool Cache Hit", .{
                .tool = full_name,
                .traceparent = traceparent,
            });
            return self.formatSuccessResponse(allocator, id, cached_resp);
        }

        // 2. Parse namespace delimiter '__'
        const sep_idx = std.mem.indexOf(u8, full_name, "__") orelse {
            return self.formatErrorResponse(allocator, id, .tool_not_found, "Tool must be in format namespace__tool_name");
        };

        const namespace = full_name[0..sep_idx];
        const raw_tool_name = full_name[sep_idx + 2 ..];

        // 3. Dispatch to matching upstream
        for (self.upstreams.items) |*up| {
            if (std.mem.eql(u8, up.namespace, namespace)) {
                const res = up.call(allocator, raw_tool_name, args_json_slice) catch |err| {
                    var err_buf: [256]u8 = undefined;
                    const err_msg = try std.fmt.bufPrint(&err_buf, "Upstream error: {s}", .{@errorName(err)});
                    zlog.err("Upstream Execution Failed", .{
                        .namespace = namespace,
                        .tool = raw_tool_name,
                        .error_name = @errorName(err),
                        .traceparent = traceparent,
                    });
                    return self.formatErrorResponse(allocator, id, .internal_error, err_msg);
                };

                const tool_res_json = try self.formatToolCallResultJson(allocator, res);
                defer allocator.free(tool_res_json);

                // Save to cache
                try self.cache.put(full_name, args_json_slice, tool_res_json);

                zlog.info("Tool Executed Successfully", .{
                    .tool = full_name,
                    .is_error = res.isError,
                    .traceparent = traceparent,
                });

                return self.formatSuccessResponse(allocator, id, tool_res_json);
            }
        }

        return self.formatErrorResponse(allocator, id, .tool_not_found, "Upstream namespace not found");
    }

    fn formatToolCallResultJson(self: *Gateway, allocator: Allocator, result: zmcp.CallToolResult) ![]u8 {
        _ = self;
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"content\":[");

        if (result.text_content) |t| {
            try writer.writeAll("{\"type\":\"text\",\"text\":\"");
            try zmcp.protocol.writeJsonEscaped(&writer, t);
            try writer.writeAll("\"}");
        }

        try writer.print("],\"isError\":{s}}}", .{if (result.isError) "true" else "false"});
        return buf.toOwnedSlice(allocator);
    }

    pub fn formatSuccessResponse(self: *Gateway, allocator: Allocator, id: zmcp.RequestId, result_json: []const u8) ![]u8 {
        _ = self;
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try id.format(&writer);
        try writer.writeAll(",\"result\":");
        try writer.writeAll(result_json);
        try writer.writeByte('}');

        return buf.toOwnedSlice(allocator);
    }

    pub fn formatErrorResponse(self: *Gateway, allocator: Allocator, id: zmcp.RequestId, code: zmcp.ErrorCode, message: []const u8) ![]u8 {
        _ = self;
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try id.format(&writer);
        try writer.print(",\"error\":{{\"code\":{d},\"message\":\"", .{@intFromEnum(code)});
        try zmcp.protocol.writeJsonEscaped(&writer, message);
        try writer.writeAll("\"}}");

        return buf.toOwnedSlice(allocator);
    }
};
