# Active Hooks

## Git Hooks (누가 커밋해도 실행 — 터미널, IDE, Claude 모두 적용)

설치: `bash tools/hooks/install.sh`
소스: `tools/hooks/` (버전 관리됨)

| Hook | 트리거 | 검증 내용 |
| ---- | ------ | --------- |
| `tools/hooks/pre-commit` | `git commit` | GDD 9섹션, JSON 유효성, [A] API contracts, [B] 클래스 캐시, [C] 유령 메서드 |
| `tools/hooks/pre-push` | `git push` (main만) | GUT 유닛 테스트 전체 실행 |

## Claude Code Hooks (Claude가 도구를 사용할 때 실행)

`.claude/settings.json`에 설정됨.

| Hook | Event | Trigger | Action |
| ---- | ----- | ------- | ------ |
| `validate-commit.sh` | PreToolUse (Bash) | `git commit` | GDD 9섹션, JSON, 하드코딩 경고, [A][B][C] 품질 게이트 |
| `validate-push.sh` | PreToolUse (Bash) | `git push` | 보호 브랜치 경고 |
| `validate-assets.sh` | PostToolUse (Write/Edit) | Asset 파일 변경 | 명명 규칙, JSON 유효성 |
| `session-start.sh` | SessionStart | 세션 시작 | 스프린트/마일스톤 컨텍스트 로드, active.md 복구 |
| `detect-gaps.sh` | SessionStart | 세션 시작 | 문서 갭 탐지 |
| `pre-compact.sh` | PreCompact | 컨텍스트 압축 | 세션 상태 덤프 |
| `session-stop.sh` | Stop | 세션 종료 | 세션 로그 업데이트 |
| `log-agent.sh` | SubagentStart | Agent 생성 | 감사 추적 |

Hook reference documentation: `.claude/docs/hooks-reference/`
Hook input schema documentation: `.claude/docs/hooks-reference/hook-input-schemas.md`
