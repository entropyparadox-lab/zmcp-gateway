# zmcp-gateway ⚡

[![Zig Version](https://img.shields.io/badge/Zig-0.16.0%2B-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Zero-Allocation](https://img.shields.io/badge/Zero--Allocation-Multiplexer-brightgreen.svg)]()
[![Model Context Protocol](https://img.shields.io/badge/MCP-2024--11--05-purple.svg)](https://modelcontextprotocol.io)

**High-Performance Native Model Context Protocol (MCP) Multiplexer, Tool Hub & Caching Gateway in Pure Zig (v0.16.0+)**

`zmcp-gateway` consolidates multiple downstream Model Context Protocol (MCP) tool servers into a **single, unified virtual MCP endpoint** for AI agents (Hermes Agent, Claude Code, Cursor). Built as a pure Zig 0.16.0+ static binary, it routes tool calls with sub-3µs latency, provides SHA256 deterministic in-memory result caching, and correlates all events with **W3C OpenTelemetry distributed tracing**.

---

## 7-in-1 Architecture (The Unified Zig Stack)

`zmcp-gateway` is built by integrating the complete `entropyparadox-lab` Zig 0.16.0+ stack:

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
│  [zfetch] HTTP Proxy   │  [Cache] SHA256 In-Memory Cache     │
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
| **Gateway Multiplex & Cache Throughput** | **445,000 requests/sec** |
| **Median Routing Latency (p50)** | **2.15 µs** |
| **99th Percentile Latency (p99)** | **2.91 µs** |
| **Memory Leaks** | **0 bytes (Per-Request Arena Isolation)** |

---

## Key Features

- 🌳 **Multi-Upstream Namespace Multiplexing**: Automatically prefixes downstream tools (`${namespace}__${tool_name}`) and aggregates schemas on `tools/list`.
- ⚡ **Sub-3µs Deterministic Tool Cache**: SHA256-hashed in-memory cache for idempotent tool calls (`cache_ttl_sec`).
- 🪵 **Built-in W3C OpenTelemetry Tracing (`zlog`)**: Generates `traceparent` headers (`00-{trace_id}-{span_id}-01`) for distributed observability.
- 🌿 **Zero-Boilerplate Config Injection (`zenv`)**: Automatically loads from `.env` or environment variables with type conversion.
- 📦 **Single Static Binary (< 2MB)**: 100% Pure Zig, zero libc/C dependencies, instant startup (< 2ms).

---

## Installation & Usage

### 1. Build and Run

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
GATEWAY_CACHE_ENABLED=true
GATEWAY_CACHE_TTL_SEC=60
GATEWAY_LOG_LEVEL=info
```

---

## License

MIT License (c) 2026 Entropy Paradox Lab / Charles Choi
