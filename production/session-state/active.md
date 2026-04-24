## TASK: ADR-027 Phase B — EventEngine C++ 구현 + macro_state 소유권 수정
## STATUS: IN PROGRESS
## COMPLETED:
- ✅ Phase B EventEngine: price_kernel.cpp (set_config, start_season, start_day, _ee_* 메서드, process_all_ticks)
- ✅ Phase B: price_engine.gd (on_kernel_news 시그널, event_pool cfg 로드, event_tags, season theme, ui_events emit)
- ✅ Phase B: news_event_system.gd 클린업
  - _on_kernel_news() + _queue_kernel_event() 핸들러 추가
  - 인트라데이 스케줄링 제거 (_generate_daily_schedule, _check_scheduled_slots, _fire_event_from_slot 등 C++로 이전)
  - _is_mutex_blocked_for_stock() + _register_mutex() 고아 메서드 제거
  - stale doc comment 3건 수정
- ✅ macro_state 이중 소유권 수정 (state ownership 규칙 준수)
  - C++ get_macro_states() 추가 (price_kernel.h + price_kernel.cpp + _bind_methods)
  - _roll_macro_states() GDScript 롤 제거 — C++ 커널이 단독 소유
  - _end_trading_day(): kernel.start_day() 후 get_macro_states()로 GDScript 동기화
- ✅ 테스트 수정: _compute_volume() 호출 인자 4→5개 (rumor_delta 0.0 추가)
- ✅ API contracts 업데이트: get_macro_states() 추가
- ✅ DLL 컴파일 성공 (Phase B + get_macro_states stock_id 오타 수정 확인)
  - 단, DLL 재링크는 Godot가 DLL을 잠금 중이므로 대기

## REMAINING:
- [ ] Godot 종료 후 DLL 재빌드 (get_macro_states 포함) — 최우선
- [ ] Phase B + macro_state fix 커밋
- [ ] Phase C: EtfEngine C++ 구현 (process_all_ticks ETF 경로)
- [ ] Phase D: ReportEngine C++ 구현
- [ ] Phase E: run_historical_simulation() C++ 구현 + CACHE_VERSION 6→7

## NEXT: Godot 종료 → cmd /c build.bat → git commit → Phase C

<!-- STATUS -->
Epic: ADR-027 Price Kernel
Feature: Phase B EventEngine
Task: DLL rebuild pending (Godot lock)
<!-- /STATUS -->
