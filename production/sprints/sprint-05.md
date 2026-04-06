# Sprint 5 -- 2026-04-07 to 2026-04-20

## Sprint Goal

세이브/로드와 오디오 기반을 구축하여 Alpha 마일스톤을 달성하고,
V-Slice 기간 누적된 기술 부채를 해소한다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions reserved for unplanned work
- Available: 8 sessions
- Sprint 4 velocity: Must Have 2/2 ✅, Should Have 0/3 (미착수 — unplanned 버그픽스/리팩터로 buffer 소진)

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S5-01 | 세이브/로드 시스템 | gameplay-programmer | 3 | 전 시스템 `get_save_data()` / `load_save_data()` 구현 | `save-load.md` GDD Approved. `SaveSystem` autoload 구현. XpSystem·SkillTree·SeasonManager·PortfolioManager·CurrencySystem 5개 직렬화 연결. 세이브→종료→로드→재개 E2E 통과. `--export-release` 빌드 성공 |
| S5-02 | 오디오 시스템 기반 | audio-director + gameplay-programmer | 2 | 세이브/로드와 독립 | `audio.md` GDD Approved. `AudioManager` autoload. 주문 체결·레벨업·VI 발동·뉴스 알림 4개 SFX 이벤트 연결. 음소거/볼륨 설정 저장. 빌드 성공 |

### Should Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S5-03 | 차트 RSI/MACD 배열 재할당 제거 | lead-programmer | 1 | — | `_rebuild_indicator_caches()` per-frame 배열 할당 제거. Godot 프로파일러에서 `chart_renderer._draw()` 프레임당 할당 0. 기존 테스트 전부 통과 |
| S5-04 | 로컬라이제이션 기반 (tr() 래핑) | localization-lead | 1.5 | — | `project.godot` ko locale 등록. `locale/ko.po` 파일 생성. `src/ui/*.gd` 사용자 대면 한국어 문자열 전부 `tr("KEY")` 래핑. 키 누락 시 원본 한국어 fallback 확인 |

### Nice to Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S5-05 | 게임패드 입력 지원 | ui-programmer | 1 | — | `InputMap`에 게임패드 액션 등록 (매매/탭 전환/스킬트리/일시정지). `InputEventJoypadButton` 처리. ui-code.md Rule 3 통과 |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 8 |
| Must Have | 5 |
| Should Have | 2.5 |
| Nice to Have | 1.0 |
| **합계** | **8.5** |
| **여유** | **−0.5 → buffer 2 sessions이 흡수** |

## Critical Path

```
Day 1-3:  S5-01 세이브/로드 (GDD → 구현 → E2E 테스트)
Day 3-4:  S5-02 오디오 기반 (GDD → AudioManager → SFX 4개 연결)
          S5-03 RSI/MACD 캐싱 (S5-01과 병행 가능)
Day 5-6:  S5-04 로컬라이제이션 기반
Day 7+:   S5-05 게임패드 (여유 있을 때)
```

**S5-01 세이브/로드 구현 순서**:
1. `save-load.md` GDD 작성 (직렬화 포맷, 세이브 슬롯 정책, 에러 처리)
2. `SaveSystem` autoload 뼈대 + 파일 I/O
3. 각 시스템 `get_save_data()` / `load_save_data()` 연결 (이미 XpSystem 구현됨)
4. E2E 테스트 (세이브 → 재시작 → 로드 → 상태 일치 확인)

## Carryover from Sprint 4

| Task | Reason | Status |
|------|--------|--------|
| S4-03 성능 프로파일링 | unplanned 버그픽스로 buffer 소진 | S5-03으로 흡수 (프로파일링 없이 코드 직접 수정) |
| S4-04 RSI/MACD 캐싱 | S4-03 미완으로 연기 | S5-03으로 통합 |
| S4-05 스킬트리 JSON | **완료 확인** — skill_tree.gd가 이미 JSON 로드 중 | ✅ 캐리오버 없음 |
| S4-06 게임패드 | Nice-to-Have 미착수 | S5-05로 이관 |

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| 세이브 포맷이 시즌 진행 중 변경되어 하위 호환 깨짐 | Medium | High | 포맷 버전 필드 포함. `save_version: 1` → 로드 시 버전 체크 + 마이그레이션 훅 |
| 오디오 에셋 미확보 (SFX 파일 없음) | High | Low | 임시 beep/sine 프로그래매틱 생성. 에셋 플레이스홀더로 시스템 먼저 구축 |
| S5-01 세이브 E2E 세션 추정 초과 | Medium | Medium | GDD 범위를 "단일 슬롯, 자동 저장" 으로 제한. 멀티 슬롯은 Beta 이관 |
| 로컬라이제이션 래핑 중 UI 레이아웃 깨짐 | Low | Low | 문자열 길이 변동 없음 (한→한 fallback). 레이아웃 리스크 없음 |

## Dependencies on External Factors

- 오디오 SFX 에셋: 현재 미확보. 프로그래매틱 placeholder로 시작, 실 에셋은 Beta 이전 교체 예정

## Definition of Done for this Sprint

- [ ] S5-01~S5-02 Must Have 전부 완료
- [ ] `save-load.md` GDD Approved, `audio.md` GDD Approved
- [ ] 세이브 → 종료 → 로드 → 재개 E2E: XP/레벨/스킬포인트/시즌 상태 전부 복원
- [ ] 주문 체결·레벨업·VI·뉴스 SFX 4개 인게임 발동 확인
- [ ] 기존 테스트 전부 통과
- [ ] `--export-release` 빌드 성공 + SCRIPT ERROR 없음
- [ ] Alpha 마일스톤 파일 생성 (`production/milestones/alpha.md`)
- [ ] 코드 커밋 완료, main 브랜치 green
