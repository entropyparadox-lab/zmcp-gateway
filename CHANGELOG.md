# Changelog

## 1.3.1 — 2026-11-09

- Target Zig 0.17.1 and synchronize package, CLI and MCP server versions.
- Replace all seven sibling-directory imports with commit-pinned URL/hash packages and `b.dependency` modules.
- Include tests, docs and release notes in package `.paths` so archive builds retain benchmark sources.
- Pin CI to Zig 0.17.1, remove moving sibling clones and add bounded stdio MCP and standalone archive checks.
- Add a Korean upgrade/reproduction guide documenting implemented transport limits.
- Retain `.ReleaseFast`: both available 0.17.0/0.17.1 compilers accept it; no compiler-confirmed migration is needed.
- Release blocker: all seven commit archive URLs returned HTTP 404 during validation. Exact local committed archives seeded an isolated cache for verification; fresh remote builds require publishing those dependency commits first. No push or deployment was performed.
