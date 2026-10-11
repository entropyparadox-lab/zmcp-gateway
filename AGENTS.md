# AGENTS.md — zmcp-gateway Guidelines

## Invariants
1. **Dual-Doc Sync**: 게이트웨이 프로토콜/명령어 변경 시 `README.md` 및 `~/.hermes/skills/mcp/native-mcp/SKILL.md`를 함께 갱신한다.
2. **Binary Sync**: `zig build -Doptimize=ReleaseFast` 후 `install -m 755 zig-out/bin/zmcp-gateway ~/.local/bin/zmcp-gateway`에 원자적 배포한다.
3. **Zero-Overhead Protocol**: MCP stdio/SSE 프록시 라우팅 시 JSON-RPC 프레임 손상 없이 초저지연 중계를 보장한다.

## Mode A Performance & Quality Loop
* **Benchmark Harness**: `zig build bench` (zbench Criterion-grade 통계 벤치마크)
* **Unit Test Harness**: `zig build test`
* **Acceptance Rule**: 회귀 0건 (Exit code 0) + 처리량(Throughput) 유지/개선 또는 지연시간(p99) 단축 시 채택.
* **Rollback Protocol**: 퇴행 또는 빌드 에러 감지 시 즉각 `git checkout .`로 안전 롤백.
