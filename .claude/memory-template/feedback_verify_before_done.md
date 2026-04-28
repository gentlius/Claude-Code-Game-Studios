---
name: 완료 선언 전 실제 검증 필수
description: 코드/테스트 작성 후 완료 선언 전 실제 실행 결과를 확인한다
type: feedback
---

작업 완료를 선언하기 전에 실제로 동작하는지 확인한다. 테스트 통과 보고 전에 빌드/실행 오류가 없는지 확인한다.

**Why:** 세 가지 실수가 반복됐다:
1. 소스 코드를 읽지 않고 테스트를 작성 → 존재하지 않는 함수 사용
2. API contracts 누락을 두 번 반복 — 규칙이 있었는데도
3. 컴파일 에러가 있는 상태에서 "테스트 통과" 보고

**How to apply:**
- 소스 파일 편집 전: 해당 파일을 읽고 public 메서드 목록을 파악한다
- 테스트 작성 전: `tests/unit/test_api_contracts.gd`를 읽어 이미 등록된 메서드를 확인한다
- public 메서드 추가 즉시: `test_api_contracts.gd` 업데이트 — 커밋 전이 아니라 코드 수정 직후
- 완료 보고 전: 실행 로그에 SCRIPT ERROR 없는지 확인
- **GDD Status 변경 전**: Implementation Checklist의 `- [ ]` 항목 수를 확인한다. 0개일 때만 Approved 변경 가능
