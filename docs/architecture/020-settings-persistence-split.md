# ADR-020: Settings Persistence Split (AudioManager cfg + SettingsScreen cfg)

**Status**: Accepted
**Date**: 2026-04-17
**Sprint**: S9-05

## Context

S9-05 요구: 볼륨/음소거 설정과 뉴스 자동 감속 설정을 영구 저장해야 한다.
기존에 `AudioManager`는 이미 `user://audio_settings.cfg`에 볼륨/음소거를 저장하고 있다.

선택지:
1. **통합 cfg**: `UserSettings` autoload를 신설해 모든 설정을 `user://settings.cfg` 하나로 통합 (Sprint 8 GDD 초안 방식)
2. **분할 cfg**: AudioManager가 `user://audio_settings.cfg`를 그대로 유지하고, SettingsScreen이 게임 설정(`auto_slow_on_news`)을 `user://game_settings.cfg`에 별도 저장

## Decision

**분할 cfg (선택지 2)** 를 선택한다.

이유:
- `AudioManager`는 이미 안정적으로 동작하는 자체 저장 로직이 있다. 마이그레이션은 버그 유입 위험.
- S9-05 범위 내에서 구현해야 하는 추가 게임 설정이 `auto_slow_on_news` 하나뿐이다 (색각 모드, 키 리맵은 와이어프레임).
- `UserSettings` autoload 신설은 scope 확장이며 S9-05 capacity 2.5 session을 초과한다.
- Full Release 시 `UserSettings` 통합을 다시 검토할 수 있다.

## Consequences

- `user://audio_settings.cfg` — AudioManager 전용 (볼륨, 음소거)
- `user://game_settings.cfg` — SettingsScreen 전용 (gameplay 설정)
- SettingsScreen은 UI 초기화 시 두 곳 모두에서 상태를 읽는다
  (AudioManager에서 볼륨/음소거, game_settings.cfg에서 auto_slow)
- 향후 통합 시: `UserSettings` autoload에서 두 cfg를 흡수하고 마이그레이션 로직 추가
- `GameClock.AUTO_SLOW_ON_EVENT` const가 제거되고 `_auto_slow_on_event` var로 교체됨
