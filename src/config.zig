const std = @import("std");

pub const GatewayConfig = struct {
    name: []const u8 = "zmcp-gateway",
    version: []const u8 = "1.1.0",
    port: u16 = 8999,
    timeout_ms: u32 = 15000,
    log_level: []const u8 = "info",

    pub const zenv = .{
        .mapping = .{
            .name = "GATEWAY_NAME",
            .version = "GATEWAY_VERSION",
            .port = "GATEWAY_PORT",
            .timeout_ms = "GATEWAY_TIMEOUT_MS",
            .log_level = "GATEWAY_LOG_LEVEL",
        },
    };
};
