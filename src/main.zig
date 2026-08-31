const std = @import("std");
const zcli = @import("zcli");
const zenv = @import("zenv");
const zlog = @import("zlog");
const zmcp = @import("zmcp");
const gateway_lib = @import("gateway");

const CliOptions = struct {
    config_file: []const u8 = "gateway.env",
    port: u16 = 8999,
    verbose: bool = false,
    format: enum { ansi, ndjson, compact } = .ansi,

    pub const zcli = .{
        .name = "zmcp-gateway",
        .version = "1.0.0",
        .description = "Zero-Allocation Native MCP Multiplexer & Tool Hub",
        .short = .{
            .config_file = 'c',
            .port = 'p',
            .verbose = 'v',
        },
        .env = .{
            .port = "GATEWAY_PORT",
        },
        .help = .{
            .config_file = "Path to .env configuration file",
            .port = "Listening port for remote MCP connections",
            .verbose = "Enable debug logging verbosity",
            .format = "Log output format (ansi, ndjson, compact)",
        },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    // 1. Parse CLI arguments via zcli
    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(allocator);

    var it = init.minimal.args.iterate();
    while (it.next()) |arg| {
        try args_list.append(allocator, std.mem.sliceTo(arg, 0));
    }

    const cli = zcli.parse(CliOptions, args_list.items) catch {
        std.process.exit(1);
    };

    // 2. Configure zlog
    zlog.setFormat(switch (cli.format) {
        .ansi => .ansi,
        .ndjson => .ndjson,
        .compact => .compact,
    });
    zlog.setMinLevel(if (cli.verbose) .debug else .info);

    // 3. Load configuration via zenv
    const config = zenv.loadOrEmpty(gateway_lib.GatewayConfig, allocator, cli.config_file) catch gateway_lib.GatewayConfig{};

    zlog.info("Starting zmcp-gateway", .{
        .name = config.name,
        .version = config.version,
        .cache_enabled = config.cache_enabled,
        .cache_ttl = config.cache_ttl_sec,
    });

    var gw = gateway_lib.Gateway.init(allocator, config);
    defer gw.deinit();

    // Register built-in system tools upstream
    const SysHandler = struct {
        fn handle(ctx: *anyopaque, alloc: std.mem.Allocator, tool_name: []const u8, args_json: []const u8) anyerror!zmcp.CallToolResult {
            _ = ctx;
            _ = alloc;
            _ = args_json;
            if (std.mem.eql(u8, tool_name, "status")) {
                return zmcp.CallToolResult.text("zmcp-gateway OK (Pure Zig 0.16.0+, Zero-Alloc Multiplexer)");
            } else if (std.mem.eql(u8, tool_name, "ping")) {
                return zmcp.CallToolResult.text("pong");
            }
            return zmcp.CallToolResult.err("Unknown system tool");
        }
    };

    var sys_up = gateway_lib.Upstream.init(allocator, "sys", undefined, SysHandler.handle);
    try sys_up.addTool(allocator, .{
        .name = "status",
        .description = "Get gateway health and runtime telemetry",
        .schema_json = "{\"type\":\"object\",\"properties\":{}}",
    });
    try sys_up.addTool(allocator, .{
        .name = "ping",
        .description = "Ping the gateway",
        .schema_json = "{\"type\":\"object\",\"properties\":{}}",
    });
    try gw.registerUpstream(sys_up);

    // 4. Run Stdio loop
    const stdin_fd = std.posix.STDIN_FILENO;
    const stdout_fd = std.posix.STDOUT_FILENO;

    var read_buf: [65536]u8 = undefined;
    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(allocator);

    while (true) {
        const bytes_read = std.posix.read(stdin_fd, &read_buf) catch |err| {
            if (err == error.WouldBlock) continue;
            break;
        };
        if (bytes_read == 0) break; // EOF

        for (read_buf[0..bytes_read]) |byte| {
            if (byte == '\n') {
                const line = std.mem.trim(u8, line_buf.items, " \r\t");
                if (line.len > 0) {
                    var req_arena = std.heap.ArenaAllocator.init(allocator);
                    defer req_arena.deinit();
                    const req_alloc = req_arena.allocator();

                    if (try gw.handleMessage(req_alloc, line)) |resp| {
                        _ = std.posix.system.write(stdout_fd, resp.ptr, resp.len);
                        _ = std.posix.system.write(stdout_fd, "\n", 1);
                    }
                }
                line_buf.clearRetainingCapacity();
            } else {
                try line_buf.append(allocator, byte);
            }
        }
    }
}
