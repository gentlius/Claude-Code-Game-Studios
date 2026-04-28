---
name: GDD-first workflow
description: Always update GDD documents before implementing code changes when design changes or additions occur
type: feedback
---

기획 변경/추가 시 반드시 GDD 먼저 업데이트 → 검증 → 코딩 순서로 진행할 것.

**Why:** 코드를 먼저 작성하고 GDD를 나중에 업데이트하면 문서와 구현이 어긋나고, 설계 검증 없이 구현에 들어가게 됨. "구현에 집중하다 GDD는 나중에"라는 사고방식 자체가 이 규칙의 위반이다.

**How to apply:**
1. 새 시스템/기능 구현 요청 → **Edit/Write 툴 사용 전에** GDD 섹션 초안 작성
2. 유저에게 설계 검토 요청 ("이 설계로 진행할까요?")
3. 승인 후 코드 구현
4. 테스트 갱신

**절대 안 되는 것:** 코드 먼저 짜고 GDD는 커밋 직전에 추가하는 것. GDD가 코드를 추적하는 게 아니라 코드가 GDD를 구현하는 것이다.
