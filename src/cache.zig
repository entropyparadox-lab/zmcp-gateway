const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CacheEntry = struct {
    namespace: []const u8,
    key_hash: [32]u8,
    response: []const u8,
    expires_at_sec: u64,
};

pub const ToolCache = struct {
    allocator: Allocator,
    entries: std.ArrayList(CacheEntry),
    ttl_sec: u32,
    enabled: bool,

    pub fn init(allocator: Allocator, ttl_sec: u32, enabled: bool) ToolCache {
        return .{
            .allocator = allocator,
            .entries = .empty,
            .ttl_sec = ttl_sec,
            .enabled = enabled,
        };
    }

    pub fn deinit(self: *ToolCache) void {
        for (self.entries.items) |e| {
            self.allocator.free(e.namespace);
            self.allocator.free(e.response);
        }
        self.entries.deinit(self.allocator);
    }

    /// Determines if a tool is an idempotent read-only query that is safe to cache.
    /// Mutation tools (create, update, delete, transfer, approve, submit, exec, etc.) are strictly rejected.
    pub fn isCacheableTool(tool_name: []const u8) bool {
        // 1. Explicit Mutation Blacklist (Never Cache)
        const mutation_keywords = [_][]const u8{
            "create", "update", "delete", "transfer", "approve",
            "reject", "apply",  "revoke", "submit",   "repay",
            "connect", "write", "exec",   "run",      "start",
            "stop",   "cancel", "kill",   "order",    "remove",
            "patch",  "mutate", "send",   "post",     "put",
        };

        for (mutation_keywords) |kw| {
            if (containsWord(tool_name, kw)) return false;
        }

        // 2. Read-Only Query Whitelist (Safe to Cache)
        const read_keywords = [_][]const u8{
            "get",      "list",     "search", "query",
            "read",     "describe", "fetch",  "view",
            "check",    "status",   "ping",   "info",
            "find",     "inspect",  "dump",   "context",
            "validate", "schema",
        };

        for (read_keywords) |kw| {
            if (containsWord(tool_name, kw)) return true;
        }

        return false;
    }

    fn containsWord(name: []const u8, word: []const u8) bool {
        var it = std.mem.splitAny(u8, name, "_-.:");
        while (it.next()) |token| {
            if (std.ascii.eqlIgnoreCase(token, word)) return true;
        }
        return false;
    }

    pub fn computeKey(tool_name: []const u8, args_json: []const u8) [32]u8 {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(tool_name);
        hasher.update(":");
        hasher.update(args_json);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        return hash;
    }

    pub fn get(self: *ToolCache, tool_name: []const u8, args_json: []const u8) ?[]const u8 {
        if (!self.enabled or !isCacheableTool(tool_name)) return null;

        const hash = computeKey(tool_name, args_json);
        const now = getNowSec();

        for (self.entries.items) |e| {
            if (std.mem.eql(u8, &e.key_hash, &hash)) {
                if (e.expires_at_sec >= now) {
                    return e.response;
                }
                break;
            }
        }
        return null;
    }

    pub fn put(self: *ToolCache, namespace: []const u8, tool_name: []const u8, args_json: []const u8, response: []const u8) !void {
        if (!self.enabled or !isCacheableTool(tool_name)) return;

        const hash = computeKey(tool_name, args_json);
        const now = getNowSec();
        const expires_at = now + self.ttl_sec;

        // Update if existing
        for (self.entries.items) |*e| {
            if (std.mem.eql(u8, &e.key_hash, &hash)) {
                self.allocator.free(e.response);
                e.response = try self.allocator.dupe(u8, response);
                e.expires_at_sec = expires_at;
                return;
            }
        }

        const ns_dupe = try self.allocator.dupe(u8, namespace);
        errdefer self.allocator.free(ns_dupe);
        const resp_dupe = try self.allocator.dupe(u8, response);
        errdefer self.allocator.free(resp_dupe);

        try self.entries.append(self.allocator, .{
            .namespace = ns_dupe,
            .key_hash = hash,
            .response = resp_dupe,
            .expires_at_sec = expires_at,
        });
    }

    /// Invalidates all cached queries for a given namespace after a mutation occurs.
    pub fn invalidateNamespace(self: *ToolCache, namespace: []const u8) void {
        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (std.mem.eql(u8, self.entries.items[i].namespace, namespace)) {
                self.allocator.free(self.entries.items[i].namespace);
                self.allocator.free(self.entries.items[i].response);
                _ = self.entries.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    fn getNowSec() u64 {
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.REALTIME, &ts);
        return @as(u64, @intCast(ts.sec));
    }
};

test "tool cache mutation bypass and invalidation" {
    const allocator = std.testing.allocator;
    var cache = ToolCache.init(allocator, 60, true);
    defer cache.deinit();

    // 1. Read-only tool -> Should Cache
    try std.testing.expect(ToolCache.isCacheableTool("classroom_get"));
    try std.testing.expect(ToolCache.isCacheableTool("mcp__earnlearning__wallet_get"));
    try std.testing.expect(ToolCache.isCacheableTool("lemmalog_query"));

    // 2. Mutation tool -> Must NOT Cache
    try std.testing.expect(!ToolCache.isCacheableTool("company_transfer"));
    try std.testing.expect(!ToolCache.isCacheableTool("admin_user_approve"));
    try std.testing.expect(!ToolCache.isCacheableTool("ouroboros_auto"));

    // 3. Put read-only query
    const read_tool = "wallet_get";
    const args = "{}";
    const resp = "{\"balance\":1000}";
    try cache.put("wallet", read_tool, args, resp);
    try std.testing.expect(cache.get(read_tool, args) != null);

    // 4. Put mutation tool -> must be ignored
    try cache.put("wallet", "wallet_transfer", "{\"amount\":500}", "{\"status\":\"ok\"}");
    try std.testing.expect(cache.get("wallet_transfer", "{\"amount\":500}") == null);

    // 5. Invalidate namespace
    cache.invalidateNamespace("wallet");
    try std.testing.expect(cache.get(read_tool, args) == null);
}
