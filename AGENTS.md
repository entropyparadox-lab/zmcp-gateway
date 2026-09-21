# AGENTS.md — zmcp-gateway Guidelines

## Invariants
1. **Dual-Doc Sync**: 게이트웨이 프로토콜/명령어 변경 시 `README.md` 및 `~/.hermes/skills/mcp/native-mcp/SKILL.md`를 함께 갱신한다.
2. **Binary Sync**: `zig build -Doptimize=ReleaseFast` 후 `~/.local/bin/zmcp-gateway`에 배포한다.
3. **Zero-Overhead Protocol**: MCP stdio/SSE 프록시 라우팅 시 JSON-RPC 프레임 손상 없이 초저지연 중계를 보장한다.
