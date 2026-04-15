---
paths:
  - "src/ui/**"
---

# UI Code Rules

- UI must NEVER own or directly modify game state — display only, use commands/events to request changes
- All UI text must go through the localization system — no hardcoded user-facing strings
- Support both keyboard/mouse AND gamepad input for all interactive elements
- All animations must be skippable and respect user motion/accessibility preferences
- UI sounds trigger through the audio event system, not directly
- UI must never block the game thread
- Scalable text and colorblind modes are mandatory, not optional
- Test all screens at minimum and maximum supported resolutions

## 표시 포맷 단일 소유 (Display Format Ownership)

플레이어에게 노출되는 표시 포맷(종목명, 날짜, 금액 등)은 반드시 단일 메서드/상수에서 생성한다. 동일한 포맷 문자열을 여러 파일에 복사하지 않는다. 포맷 변경 시 한 곳만 수정하면 모든 UI에 반영되어야 한다.

```gdscript
# 올바름 — 단일 소스에서 읽기
label.text = stock_data.get_display_name()
# 틀림 — 포맷 문자열 직접 조합
label.text = "%s(%s)" % [stock_data.name, stock_data.code]
```

## 상수 기반 동적 문자열 (Constant-Driven Strings)

튜닝 상수값이 포함된 플레이어 노출 문자열은 상수를 직접 참조하여 런타임에 생성한다. 상수를 리터럴로 박으면 상수 변경 시 문자열이 자동으로 틀려진다.

## UI는 상태를 소유하지 않는다

UI 클래스는 autoload에서 읽기만 한다. 게임 상태를 멤버 변수로 보관하면 세이브/로드 시 해당 상태가 유실된다. 주간 XP, 누적 수익 등 모든 수치는 해당 시스템(XpSystem, PortfolioManager 등)에서 읽어야 한다.
