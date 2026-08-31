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
    max_entries: usize = 512,

    pub fn init(allocator: Allocator) ToolCache {
        return .{
            .allocator = allocator,
            .entries = .empty,
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
        const hash = computeKey(tool_name, args_json);
        const now = getNowSec();

        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (std.mem.eql(u8, &self.entries.items[i].key_hash, &hash)) {
                if (self.entries.items[i].expires_at_sec >= now) {
                    return self.entries.items[i].response;
                } else {
                    // Lazy Eviction of expired entry
                    self.allocator.free(self.entries.items[i].response);
                    _ = self.entries.swapRemove(i);
                    return null;
                }
            }
            i += 1;
        }
        return null;
    }

    pub fn put(self: *ToolCache, tool_name: []const u8, args_json: []const u8, response: []const u8, ttl_sec: u32) !void {
        if (ttl_sec == 0) return;

        const hash = computeKey(tool_name, args_json);
        const now = getNowSec();
        const expires_at = now + ttl_sec;

        // 1. Update existing entry if present
        for (self.entries.items) |*e| {
            if (std.mem.eql(u8, &e.key_hash, &hash)) {
                self.allocator.free(e.response);
                e.response = try self.allocator.dupe(u8, response);
                e.expires_at_sec = expires_at;
                return;
            }
        }

        // 2. Enforce Max Capacity (Evict oldest if full)
        if (self.entries.items.len >= self.max_entries) {
            self.allocator.free(self.entries.items[0].response);
            _ = self.entries.swapRemove(0);
        }

        // 3. Insert new entry
        const resp_dupe = try self.allocator.dupe(u8, response);
        errdefer self.allocator.free(resp_dupe);

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

test "tool cache opt-in ttl and lazy eviction" {
    const allocator = std.testing.allocator;
    var cache = ToolCache.init(allocator);
    defer cache.deinit();

    // 1. TTL = 0 -> Must NOT be cached
    try cache.put("dynamic_poll", "{}", "{\"status\":\"pending\"}", 0);
    try std.testing.expect(cache.get("dynamic_poll", "{}") == null);

    // 2. TTL > 0 -> Cached
    try cache.put("static_country", "{\"code\":\"KR\"}", "{\"name\":\"South Korea\"}", 3600);
    const hit = cache.get("static_country", "{\"code\":\"KR\"}");
    try std.testing.expect(hit != null);
    try std.testing.expect(std.mem.indexOf(u8, hit.?, "South Korea") != null);
}
