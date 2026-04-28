# Studio Memory — [PROJECT NAME]

<!-- This file is the memory index for Claude Code. Each line is a pointer to a memory file. -->
<!-- Copied from .claude/memory-template/ at project start. Update as the project grows. -->
<!-- Lines after 200 will be truncated — keep entries concise (~150 chars max per line). -->

## Studio-Wide Feedback (inherited from framework)

- [GDD-first workflow](feedback_gdd_first.md) — 기획 변경 시 GDD 먼저, 코드는 그 다음
- [TD 아키텍처 감사 선행](feedback_td_audit_first.md) — 새 시스템/소유권 변경 전 TD 감사 필수
- [테스트 수정 방향](feedback_test_fix_direction.md) — 실패 시 GDD→코드→테스트 순서, 절대 역방향 금지
- [완료 선언 전 실제 검증](feedback_verify_before_done.md) — 소스 읽고 테스트 작성, API contracts 즉시 등록
- [코드 작업 완료 시 반드시 커밋](feedback_commit_on_complete.md) — 작업 단위 완결 즉시 커밋
- [작업 범위 흘려듣지 않기](feedback_scope_confirmation.md) — 명시된 요구사항 전체 구현, 불확실하면 확인
- [프레임워크 의도 먼저 확인](feedback_framework_first.md) — 프레임워크 파일 수정 전 패턴 파악
- [유저 제안 반박 시 확인 먼저](feedback_confirm_before_change.md) — 근거 제시 후 확인받고 진행
- [근본 원인 우선](feedback_rootcause_first.md) — 증상 억제 패치 2건 이상 → 근본 원인 탐색
- [외부 리소스 URL 규칙](feedback_external_resources.md) — 검증된 URL만, 모르면 "검색 필요"
- [임시 파일 즉시 정리](feedback_cleanup_temp.md) — 생성한 임시 파일/폴더는 작업 후 즉시 삭제

## Project-Specific (add as you go)

<!-- Add project memories below as you learn user preferences for this project -->
<!-- Format: - [Title](file.md) — one-line hook -->
