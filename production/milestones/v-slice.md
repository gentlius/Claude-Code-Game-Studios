# Milestone: Vertical Slice

> **Status**: In Progress
> **Started**: 2026-04-01
> **Target**: 시즌 대회 + 성장 루프의 완전한 체험이 가능한 데모
> **Previous**: MVP (Pre-Production, 완료)

## Goal

MVP의 코어 루프(뉴스/차트 읽기 → 매매 판단 → 결과 확인)에 **경쟁과 성장**을
더해, "시즌 단위로 반복 플레이하고 싶은 게임"인지 검증한다.

## Success Criteria

- [ ] AI 경쟁자와 수익률 경쟁하며 한 시즌을 플레이할 수 있다
- [ ] 거래/분석으로 경험치를 얻고, 스킬(차트 지표 해금)로 성장을 체감할 수 있다
- [ ] 시즌 종료 후 리더보��에서 순위를 확인할 수 있다
- [ ] VI/서킷브레이커가 발동되어 시장 긴장감을 제공한다
- [ ] 위 전체를 처음부터 끝까지 한 번에 플레이 가능하다 (end-to-end)

## V-Slice Systems (6)

| # | System | Est. Effort | Depends On | Sprint |
|---|--------|-------------|------------|--------|
| 7 | AI 경쟁자 | M (2-3 sessions) | MVP 완료 | Sprint 1 |
| 9 | 경험치 시스템 | S (1 session) | MVP 완료 | Sprint 1 |
| 8 | 스킬 트리 | M (2-3 sessions) | 경험치 | Sprint 2 |
| 10 | 시즌/대회 관리 | M (2-3 sessions) | AI 경쟁자 | Sprint 2 |
| 16 | 리더보드 UI | S (1 session) | 시즌/대회 | Sprint 3 |
| 17 | 스킬 트리 UI | S (1 session) | 스킬 트리 | Sprint 3 |

## MVP 보강 항목 (V-Slice 진입 전 정리)

| Item | Description | Sprint |
|------|-------------|--------|
| VI/서킷브레이커 구현 | 설계 완료, 구현 대기. 시장 긴장감 핵심 | Sprint 1 |
| 시장 지수 HUD 표시 | `get_market_index()` API → 상단 상태바 연결 | Sprint 1 |
| GUT 테스트 설치 | 유닛 테스트 자동 실행 환경 구축 | Sprint 1 |
