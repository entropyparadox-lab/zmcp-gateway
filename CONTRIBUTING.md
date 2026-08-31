# Contributing to zmcp-gateway ⚡

Thank you for contributing to `zmcp-gateway`! To maintain high throughput, low latency, and zero memory leaks in the Zig ecosystem, we follow strict quality guidelines.

---

## 1. Compiler Versioning & Branch Strategy

* **`main` (Protected)**: Targets **Official Stable Zig (`0.16.x`)**. All production releases (`vX.Y.Z`) are cut exclusively from `main`.
* **`zig-master`**: Tracks upstream `ziglang/zig` nightly builds.
* **`feat/<name>` / `fix/<name>`**: Branch off `main` for stable changes.

---

## 2. Strict Quality & Verification Gate

1. **100% Tested & Verified**: Every PR must include reproducible test coverage (`zig build test`).
2. **Zero-Allocation Invariant**: Gateway dispatching and routing must **NEVER** leak memory.
3. **No Regressions**: Benchmark throughput (`zig build bench`) must sustain >400k req/sec.

---

## 3. Fast Local Development & Git Hooks

Install local pre-commit hooks:
```bash
./scripts/setup-hooks.sh
```

Before opening a PR, run full local verification:
```bash
# 1. Format code
zig fmt src/ build.zig

# 2. Run unit tests
zig build test

# 3. Run benchmarks
zig build bench
```
