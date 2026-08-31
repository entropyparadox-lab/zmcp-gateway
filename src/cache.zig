const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CacheEntry = struct {
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
            self.allocator.free(e.response);
        }
        self.entries.deinit(self.allocator);
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
        if (!self.enabled) return null;

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

    pub fn put(self: *ToolCache, tool_name: []const u8, args_json: []const u8, response: []const u8) !void {
        if (!self.enabled) return;

        const hash = computeKey(tool_name, args_json);
        const now = getNowSec();
        const expires_at = now + self.ttl_sec;

        // Check if existing
        for (self.entries.items) |*e| {
            if (std.mem.eql(u8, &e.key_hash, &hash)) {
                self.allocator.free(e.response);
                e.response = try self.allocator.dupe(u8, response);
                e.expires_at_sec = expires_at;
                return;
            }
        }

        const resp_dupe = try self.allocator.dupe(u8, response);
        try self.entries.append(self.allocator, .{
            .key_hash = hash,
            .response = resp_dupe,
            .expires_at_sec = expires_at,
        });
    }

    fn getNowSec() u64 {
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.REALTIME, &ts);
        return @as(u64, @intCast(ts.sec));
    }
};

test "tool cache put and get" {
    const allocator = std.testing.allocator;
    var cache = ToolCache.init(allocator, 60, true);
    defer cache.deinit();

    const tool = "fs_read";
    const args = "{\"path\":\"/etc/hosts\"}";
    const resp = "{\"content\":[{\"type\":\"text\",\"text\":\"127.0.0.1 localhost\"}]}";

    try cache.put(tool, args, resp);

    const cached = cache.get(tool, args);
    try std.testing.expect(cached != null);
    try std.testing.expectEqualStrings(resp, cached.?);
}
