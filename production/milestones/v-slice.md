# Milestone: Vertical Slice

> **Status**: Closed
> **Started**: 2026-04-01
> **Closed**: 2026-04-06
> **Target**: 시즌 대회 + 성장 루프의 완전한 체험이 가능한 데모
> **Previous**: MVP (Pre-Production, 완료)

## Goal

MVP의 코어 루프(뉴스/차트 읽기 → 매매 판단 → 결과 확인)에 **경쟁과 성장**을
더해, "시즌 단위로 반복 플레이하고 싶은 게임"인지 검증한다.

## Success Criteria

- [x] AI 경쟁자와 수익률 경쟁하며 한 시즌을 플레이할 수 있다
- [x] 거래/분석으로 경험치를 얻고, 스킬(차트 지표 해금)로 성장을 체감할 수 있다
- [x] 시즌 종료 후 리더보드에서 순위를 확인할 수 있다
- [x] VI/서킷브레이커가 발동되어 시장 긴장감을 제공한다
- [x] 위 전체를 처음부터 끝까지 한 번에 플레이 가능하다 (end-to-end)

## V-Slice Systems (6)

| # | System | Est. Effort | Depends On | Sprint | Status |
|---|--------|-------------|------------|--------|--------|
| 9 | 경험치 시스템 | S (1.5 sessions) | MVP 완료 | Sprint 1 | ✅ Done (GDD+코드+테스트) |
| 8 | 스킬 트리 | M (2 sessions) | 경험치 | Sprint 1 | ✅ Done (GDD+코드+테스트) |
| 7 | AI 경쟁자 | M (2-3 sessions) | MVP 완료 | Sprint 2 | ✅ Done (GDD+코드+테스트) |
| 10 | 시즌/대회 관리 | M (2-3 sessions) | AI 경쟁자 | Sprint 2 | ✅ Done (GDD+코드+테스트) |
| 16 | 리더보드 UI | S (1 session) | 시즌/대회 | Sprint 3 | ✅ Done (GDD+코드+테스트) |
| 17 | 스킬 트리 UI | S (1 session) | 스킬 트리 | Sprint 4 | ✅ Done (GDD+코드+테스트) |

> **변경 사항 (2026-04-01)**: AI 경쟁자를 Sprint 2로 이동 (시즌/대회와 강결합).
> 스킬 트리 구현을 Sprint 1로 앞당김 (GDD 이미 Approved, 경험치와 연결하여 성장 루프 우선 검증).

## MVP 보강 항목 (V-Slice 진입 전 정리)

| Item | Description | Sprint | Status |
|------|-------------|--------|--------|
| VI/서킷브레이커 구현 | 설계 완료, 구현 완료 | Sprint 1 | ✅ Done |
| 시장 지수 HUD 표시 | `get_market_index()` API → 상단 상태바 연결 | Sprint 1 | ✅ Done |
| GUT 테스트 설치 | 유닛 테스트 자동 실행 환경 구축 | Sprint 1 | ✅ Done |
| 섹터/종목 확장 (46종목 11섹터) | V-Slice 데이터 기반. GDD+코드+테스트 | Sprint 1 | ✅ Done (unplanned) |
| 이벤트 시스템 mutex_group | 뉴스 모순 방지. GDD+코드+테스트 | Sprint 1 | ✅ Done (unplanned) |

## Sprint 4 추가 완료 항목 (클로즈 세션)

| Item | Description | Status |
|------|-------------|--------|
| trading_screen.gd God Object 분리 | 2020줄 → 551줄, 5개 서브컴포넌트 분리 | ✅ |
| 4x 배속 봉차트 점 버그 | 렌더 스킵 / 데이터 업데이트 분리 | ✅ |
| 일일 정산 XP UX | 알파(플레이어 수익 − 시장 평균) 기반 표시로 재설계 | ✅ |
| 레벨업 배너 스킬트리 버튼 | 시그널 연결 누락 수정 | ✅ |
| XP 시스템 알파 기반 재설계 | GDD 업데이트 → 코드 → 테스트 (GDD-first 워크플로) | ✅ |
| AI PRE_MARKET 수익률 노출 | _season_active 플래그 + 인트라데이 보간 | ✅ |
| 리더보드 성능 O(N log N) → O(K) | ADR-008 정렬 캐시. 매 4틱 전체 정렬 제거 | ✅ |
| 1분/5분/15분봉 시즌 전체 히스토리 | 일별 틱 버퍼 리셋 제거. GDD §5-1 복원 | ✅ |

## QA Sign-off

- 빌드: `build/windows/SeedMoney.exe` 109.5 MB — SCRIPT ERROR 0 (2026-04-06)
- 테스트: 192/192 pass
- 풀 시즌 플레이스루: 완료 (매매 도파민 확인)
- QA Lead 서명: ✅ Approved
