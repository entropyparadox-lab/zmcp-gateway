const std = @import("std");

pub const GatewayConfig = struct {
    name: []const u8 = "zmcp-gateway",
    version: []const u8 = "1.0.0",
    port: u16 = 8999,
    timeout_ms: u32 = 15000,
    cache_enabled: bool = true,
    cache_ttl_sec: u32 = 60,
    log_level: enum { debug, info, warn, err } = .info,

    pub const zenv = .{
        .mapping = .{
            .timeout_ms = "GATEWAY_TIMEOUT_MS",
            .cache_enabled = "GATEWAY_CACHE_ENABLED",
            .cache_ttl_sec = "GATEWAY_CACHE_TTL_SEC",
            .log_level = "GATEWAY_LOG_LEVEL",
        },
    };
};
