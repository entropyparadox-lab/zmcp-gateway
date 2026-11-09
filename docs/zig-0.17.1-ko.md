# Zig 0.17.1 전환 가이드

## 적용 범위

- 패키지: zmcp-gateway 1.3.1, 최소 컴파일러: Zig 0.17.1.
- 기존 Zig 0.17.0에서 테스트·빌드·벤치마크를 실행한 뒤 0.17.1로 검증한다.
- 이 환경의 두 컴파일러 모두 `.ReleaseFast`와 `-Doptimize=ReleaseFast`를 허용한다. 실제 오류가 없으므로 추측에 따른 `.fast` 변경은 하지 않았다.
- 배포된 게이트웨이, 전역 실행 파일, 서비스 설정은 변경하지 않는다.

## 빌드와 검증

Zig 0.17.1 실행 파일을 명시적으로 선택하고 다음을 실행한다.

```sh
zig version
zig fmt --check src/ tests/ build.zig build.zig.zon
zig build test --summary all
zig build -Doptimize=ReleaseFast
zig build bench
python3 tests/stdio_smoke.py zig-out/bin/zmcp-gateway
```

stdio 스모크는 별도 임시 디렉터리와 빈 환경의 자식 게이트웨이에서 5초 제한으로 initialize → initialized 알림 → tools/list → sys__ping → sys__status를 검증한다. 프로토콜은 2024-11-05 NDJSON이며 알림 응답이 없어야 한다.

현재 실행 파일은 내장 sys 도구만 등록한다. 라이브러리의 Upstream은 함수 포인터 기반이다. 외부 stdio 서버를 실행하거나 HTTP 서버에 연결하는 전송 구현은 없으므로 HTTP/외부 자식 upstream 스모크를 통과했다고 주장하지 않는다. `port` 설정도 HTTP 리스너가 구현되었다는 뜻이 아니다.

## 재현 가능한 의존성

`build.zig`는 모든 라이브러리를 `b.dependency(...).module(...)`로 가져온다. `build.zig.zon`의 URL은 변경 불가능한 전체 커밋 ID이며 Zig 패키지 해시를 함께 고정했다. 형제 디렉터리의 작업 중 파일이나 이후 커밋은 읽지 않는다.

**2026-11-09 검증 시 7개 고정 URL 모두 HTTP 404였다.** 아직 원격에 공개되지 않은 커밋은 push 전까지 새 머신/CI에서 다운로드할 수 없다. 로컬 검증 성공과 원격 배포 가능성은 구분한다. 이 작업에서는 push하지 않는다.

로컬 재현은 manifest의 정확한 커밋으로 `git archive`를 생성한 뒤 **격리한** 캐시로 `zig fetch`한다. fetch 출력 해시가 manifest와 일치하는지 확인한다. 변경 중인 작업 트리를 직접 fetch하지 않는다.

```sh
# scratch는 사용자가 선택한 전용 작업 디렉터리
export ZIG_GLOBAL_CACHE_DIR="$scratch/global-cache"
# 각 라이브러리의 manifest URL에 있는 전체 커밋 ID를 사용한다.
git -C /path/to/library archive --format=tar --output="$scratch/library.tar" EXACT_COMMIT
zig fetch "$scratch/library.tar"
```

Zig fetch는 `.paths`에 포함된 내용만 패키지 해시에 반영한다. 게이트웨이 패키지에는 `tests`와 `docs`, changelog도 포함된다. 게이트웨이 자체도 아카이브를 fetch하여 캐시의 패키지 디렉터리에서 테스트·빌드·벤치마크를 실행하고, 별도 소비자 프로젝트에서 공개 `zmcp-gateway` 모듈을 가져와 검증한다. 전역 사용자 캐시는 사용하지 않는다.

CI는 Zig 0.17.1로 Linux/macOS 테스트, ReleaseFast 빌드, stdio 스모크, 독립 아카이브 빌드를 실행한다. 형제 저장소 clone 단계는 제거했다. 공개되지 않은 의존성 URL의 404는 CI를 막는 외부 조건으로 남는다.
