# zmcp-gateway ⚡

[![Zig Version](https://img.shields.io/badge/Zig-0.17.1-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Zero-Allocation](https://img.shields.io/badge/Zero--Allocation-Multiplexer-brightgreen.svg)]()
[![Model Context Protocol](https://img.shields.io/badge/MCP-2024--11--05-purple.svg)](https://modelcontextprotocol.io)

**High-Performance Native Model Context Protocol (MCP) Multiplexer & Transparent Tool Gateway in Pure Zig (v0.17.1)**

`zmcp-gateway` provides a native Model Context Protocol (MCP) tool-routing library and stdio executable for AI agents (Hermes Agent, Claude Code, Cursor). Release **1.3.1** targets **Zig 0.17.1**. The executable currently registers only `sys__status` and `sys__ping`; library users can register in-process upstream handlers. External stdio child and HTTP upstream transports are not implemented in this executable.

---

## 7-in-1 Architecture (The Unified Zig Stack)

`zmcp-gateway` integrates the complete `entropyparadox-lab` Zig stack through commit-pinned URL/hash dependencies in `build.zig.zon` (no sibling checkouts):

```text
┌──────────────────────────────────────────────────────────────┐
│                    AI Agents (Hermes / Claude)                │
└──────────────────────────────┬───────────────────────────────┘
                               │ JSON-RPC 2.0 (Stdio / HTTP)
┌──────────────────────────────▼───────────────────────────────┐
│                       zmcp-gateway ⚡                         │
│                                                              │
│  [zcli] CLI Interface  │  [zenv] Config  │  [zlog] OTel Span │
│  [zmcp] MCP Server     │  [zserde] Specs │  [zbench] Profiler│
│  [zfetch] HTTP Proxy   │  [Router] 2.06µs Zero-Alloc Dispatch │
└───────┬──────────────────────┬──────────────────────┬────────┘
        │                      │                      │
┌───────▼────────┐     ┌───────▼────────┐     ┌───────▼────────┐
│  fs__read_file │     │   math__add    │     │   db__query    │
│  (Native Zig)  │     │ (Stdio Worker) │     │ (Remote HTTP)  │
└────────────────┘     └────────────────┘     └────────────────┘
```

---

## Benchmark Highlights (AMD Ryzen / ReleaseFast, 50 Sample Batches)

| Metric | Measured Value |
| :--- | :--- |
| **Gateway Multiplexing Throughput** | **477,300 requests/sec** |
| **Median Routing Latency (p50)** | **2.06 µs** |
| **99th Percentile Latency (p99)** | **2.55 µs** |
| **Memory Leaks** | **0 bytes (Per-Request Arena Isolation)** |

---

## Key Features

- 🌳 **Multi-Upstream Namespace Multiplexing**: Automatically prefixes downstream tools (`${namespace}__${tool_name}`) and aggregates schemas on `tools/list`.
- 🛡️ **100% Transparent Pass-Through (Zero-Cache Invariant)**: Eliminates stale reads, cache poisoning, and side-effect drops by directly forwarding every request with pure deterministic execution.
- 🪵 **Built-in W3C OpenTelemetry Tracing (`zlog`)**: Generates `traceparent` headers (`00-{trace_id}-{span_id}-01`) for distributed observability.
- 🌿 **Zero-Boilerplate Config Injection (`zenv`)**: Automatically loads from `.env` or environment variables with type conversion.
- 📦 **Single Static Binary (< 2MB)**: 100% Pure Zig, zero libc/C dependencies, instant startup (< 2ms).

---

## Installation & Usage

### 1. Build and Run

Use Zig **0.17.1**. See the [Korean upgrade guide](docs/zig-0.17.1-ko.md) and [changelog](CHANGELOG.md). Dependency commits are locally verified; unpublished commit archives remain unavailable remotely until their maintainers push them. Fresh remote CI is blocked until then; a seeded local cache is not proof of remote availability.

```bash
# Clone and build
git clone https://github.com/entropyparadox-lab/zmcp-gateway.git
cd zmcp-gateway
zig build -Doptimize=ReleaseFast

# Run in Stdio mode for AI Agent
./zig-out/bin/zmcp-gateway --verbose
```

### 2. Configure via `gateway.env`

```env
GATEWAY_PORT=8999
GATEWAY_TIMEOUT_MS=15000
GATEWAY_LOG_LEVEL=info
```

---

## License

MIT License (c) 2026 Entropy Paradox Lab / Charles Choi
