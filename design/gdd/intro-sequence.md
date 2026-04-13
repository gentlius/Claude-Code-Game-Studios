# Intro Sequence (도입부 서사)

*Created: 2026-04-06*
*Status: Approved*
*Sprint: S5 (Alpha)*

---

## 1. Overview

게임 최초 실행 시 전체화면 슬라이드 카드 5장으로 플레이어의 배경과 세계관을 전달한다.
카드는 클릭/스페이스/엔터로 넘기며, 스킵 버튼(ESC 포함)으로 즉시 종료한다.
최초 1회만 표시되며, 설정 메뉴에서 다시 볼 수 있다.

---

## 2. Player Fantasy

시장이 열리기 전, 플레이어는 "이게 내 전부다"는 무게를 느낀다.
100만원, 쪽방, 20,000명 경쟁 — 숫자가 상황을 설명한다.
설명하지 않는다. 느끼게 한다.

---

## 3. Detailed Design

### 3-1. 트리거 조건

인트로는 **새 게임 시작 시 항상** 재생된다. `StartScreen`이 직접 `IntroSequence.play()`를 호출한다.  
기존 슬롯 로드 시에는 재생하지 않는다.

| 조건 | 동작 |
|------|------|
| 새 게임 시작 | `StartScreen` → `IntroSequence.play()` → 재생 → `intro_finished` → MainScreen |
| 기존 슬롯 로드 | 인트로 없음, MainScreen 직행 |
| 설정 메뉴 "인트로 다시 보기" | `IntroSequence.play()` 직접 호출 (Beta 이후) |

### 3-2. 카드 텍스트

| # | 텍스트 | 감정 |
|---|--------|------|
| 1 | 오늘, 퇴소했다. / 보육원 문이 닫혔다. 뒤돌아보지 않았다. / 손에 쥔 건 전부다. / 정착지원금 1,000,000원. / 이게 시작이다. | 외로움 + 결의 |
| 2 | 같은 날, 공고 하나가 올라왔다. / 제1회 시드머니 투자 대회 / 기간: 20거래일 / 참가자: 20,000명 / 무기: 당신의 판단 / 19,999명이 이미 접속 중이다. 모두 같은 돈으로 시작한다. 모두 같은 시장을 본다. / 결과는 다를 것이다. | 냉정한 현실 |
| 3 | 오늘 밤은 쪽방이다. / 벽이 얇다. 창이 없다. 괜찮다. 여기가 출발선이다. / 자산이 오르면, 거처가 바뀐다. 고층이 보이고, 나중엔 수평선이 보인다. 개인 섬을 가진 사람들이 있다. 당신도 갈 수 있다. / 반대 방향도 있다. 자산이 10,000원 아래로 떨어지면 — 끝이다. / 그러니까, 오르는 방향으로만 간다. | 긴장감 |
| 4 | 무기가 없다고 생각하지 마라. / 거래할수록 배운다. 차트를 읽는 눈이 열리고, 뉴스보다 빨리 움직이는 법을 익힌다. / 판단이 무기다. 분석이 수익이다. 시즌 수익은 다음 시드머니가 된다. / 복리는 당신 편이다 — 방향이 맞다면. | 유능감 |
| 5 | 브론즈에서 거장까지. / 1,000,000원에서 1,000억까지. / 쪽방에서 수평선까지. / 시장이 열린다. | 각오 |

### 3-3. 인터랙션

| 입력 | 타이프라이터 진행 중 | 타이프라이터 완료 후 |
|------|---------------------|---------------------|
| 마우스 클릭 (좌) | 텍스트 즉시 완성 | 다음 카드 (마지막이면 종료) |
| Space / Enter | 텍스트 즉시 완성 | 다음 카드 (마지막이면 종료) |
| ESC | 즉시 인트로 종료 | 즉시 인트로 종료 |
| 스킵 버튼 클릭 | 즉시 인트로 종료 | 즉시 인트로 종료 |

### 3-4. 시각 디자인

- 배경: `#0a0a0a` (거의 검정)
- 텍스트: `#ebebeb` (거의 흰색), 폰트 22px
- 카드 번호: `#595959`, 12px, 우하단
- 스킵 버튼: `#666666`, 13px, 우상단, flat 스타일
- 클릭 안내("클릭하여 계속"): `#808080`, 13px, 텍스트 완성 후 페이드인
- 카드 전환: 페이드아웃(0.2s) → 텍스트 교체 → 페이드인(0.2s)
- 종료 전환: 페이드아웃(1.2s) → `intro_finished` 시그널

---

## 4. Formulas

```
카드 표시 순서: 1 → 2 → 3 → 4 → 5 → intro_finished 시그널
타이프라이터 지속 시간 = 텍스트_길이(chars) / TYPEWRITER_SPEED
카드 전환 시간 = CARD_FADE_DURATION × 2 (페이드아웃 + 페이드인)
```

변수 정의:
- `TYPEWRITER_SPEED` = 28.0 chars/sec (기본값)
- `CARD_FADE_DURATION` = 0.4s (기본값, 페이드 양방향 합산)
- `FINISH_FADE_DURATION` = 1.2s (마지막 페이드아웃)

예시) 카드 1 텍스트 약 55자 → 지속 시간 ≈ 2.0초

---

## 5. Edge Cases

| 상황 | 처리 |
|------|------|
| EC-01: 카드 5 이후 클릭 중복 입력 | `_finishing` 플래그로 이중 종료 방지 |
| EC-02: 스킵 직후 `intro_finished` 중복 emit | `_finishing` 플래그 체크 후 1회만 emit |
| EC-03: `TYPEWRITER_SPEED = 0` | 0 나눗셈 방지: speed = max(speed, 1.0) |

---

## 6. Dependencies

| 의존 방향 | 시스템 | 설명 |
|----------|--------|------|
| IntroSequence ← | `StartScreen` | 새 게임 시 `IntroSequence.play()` 호출 (`start-screen.md`) |
| IntroSequence → | `StartScreen` / `MainScreen` | `intro_finished` 시그널 수신 후 MainScreen 진입 |
| IntroSequence ← | 설정 메뉴 (미구현) | `IntroSequence.play()` 직접 호출로 다시 보기 (Beta 이후) |
| IntroSequence ← | S5-02 AudioManager (미구현) | 인트로 중 ambient BGM 재생 (Beta 이후) |

역방향: `start-screen.md`는 `IntroSequence.play()` 호출자임을 명시.

---

## 7. Tuning Knobs

| 파라미터 | 기본값 | 안전 범위 | 영향 |
|---------|--------|---------|------|
| `TYPEWRITER_SPEED` | 28.0 chars/sec | 10 ~ 60 | 낮을수록 긴장감↑, 높을수록 답답함↓ |
| `CARD_FADE_DURATION` | 0.4s | 0.1 ~ 1.0 | 카드 전환 속도 |
| `FINISH_FADE_DURATION` | 1.2s | 0.5 ~ 2.5 | 마지막 카드 후 무게감 |

---

## 8. Acceptance Criteria

| AC | 조건 | 검증 방법 |
|----|------|----------|
| AC-01 | 새 게임 시작 시 인트로가 MainScreen보다 먼저 표시된다 | 수동: 새 게임 버튼 클릭 |
| AC-02 | 기존 슬롯 로드 시 인트로 없이 MainScreen 직행 | 수동: 슬롯 선택 후 진입 |
| AC-03 | 스킵 버튼/ESC 누르면 즉시 MainScreen으로 이동 | 수동: 카드 1에서 스킵 |
| AC-04 | 5장 카드가 정확한 텍스트로 순서대로 표시된다 | 수동: 전 카드 확인 |
| AC-05 | 카드 5 완료 후 MainScreen이 정상 로드된다 | 수동 + 빌드 검증 |
| AC-06 | 타이프라이터 진행 중 클릭 시 텍스트 즉시 완성 | 수동 |
| AC-07 | 인트로 표시 중 MainScreen이 메모리에 로드되지 않는다 | 수동: Godot 디버거 씬 트리 확인 |
| AC-08 | 새 게임 여러 번 시작해도 인트로 매번 재생 | 수동: 슬롯 삭제 후 새 게임 반복 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- `StartScreen.new_game_confirmed(name)` → `IntroSequence.play()` → `intro_finished` → MainScreen

### 호출 경로
- [x] `IntroSequence.play()` — 씬 인스턴스화 → `add_child()` → 재생 → `intro_finished` emit → `queue_free()`
- [x] `intro_finished` 시그널 — `StartScreen._on_intro_finished()` → MainScreen 전환
- [x] 스킵(ESC·스킵 버튼) → `_finishing` 플래그 체크 → `intro_finished` emit

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-06 | `tests/unit/test_intro_sequence.gd` | `test_typewriter_completes_on_click()` |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
