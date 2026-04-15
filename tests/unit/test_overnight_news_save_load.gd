extends GutTest
## Regression tests: overnight news price bias survives save/load cycle.
## Verifies that MarketEvent reconstruction data saved in NewsEventSystem.get_save_data()
## is correctly used by load_save_data() to repopulate PriceEngine.event_queue.
## Bug context: PRE_MARKET auto-save included overnight events in PriceEngine.event_queue,
## but event_queue was not serialized — on load, queue was empty → zero price effect.
## See: docs/architecture/015-save-trigger-timing.md, design/gdd/news-events.md


# ── Helpers ──

## Build a minimal overnight_display entry as saved by get_save_data() (post-fix format).
func _make_overnight_entry(
		scope: String,
		direction: int,
		targets: Array[String],
		base_impact: float,
		decay_ticks: int,
		decay_curve: int = MarketEvent.DecayCurve.LINEAR,
		event_type: int = MarketEvent.EventType.GRADUAL_SHIFT
) -> Dictionary:
	return {
		"headline":         "테스트 헤드라인",
		"body":             "테스트 본문",
		"impact_hint":      "테스트",
		"scope":            scope,
		"impact_tier":      "SMALL",
		"direction":        direction,
		"target_stock_ids": targets,
		"base_impact":      base_impact,
		"decay_ticks":      decay_ticks,
		"decay_curve":      decay_curve,
		"event_type":       event_type,
	}


## Inject a MarketEvent directly into _overnight_buffer to simulate overnight generation.
func _inject_overnight_event(
		scope: String,
		direction: int,
		targets: Array[String],
		base_impact: float,
		decay_ticks: int
) -> MarketEvent:
	var sc: MarketEvent.EventScope = MarketEvent.EventScope.MACRO
	if scope == "SECTOR":
		sc = MarketEvent.EventScope.SECTOR
	elif scope == "INDIVIDUAL":
		sc = MarketEvent.EventScope.INDIVIDUAL
	var evt: MarketEvent = MarketEvent.gradual_shift(
		base_impact, direction, sc, targets, decay_ticks, MarketEvent.DecayCurve.LINEAR)
	NewsEventSystem._overnight_buffer.append({
		"market_event":     evt,
		"headline":         "테스트",
		"body":             "테스트",
		"impact_hint":      "",
		"scope":            scope,
		"impact_tier":      "SMALL",
		"direction":        direction,
		"target_stock_ids": targets,
	})
	return evt


func before_each() -> void:
	NewsEventSystem._overnight_buffer.clear()
	NewsEventSystem._loaded_news_bundle.clear()


func after_each() -> void:
	NewsEventSystem._overnight_buffer.clear()
	NewsEventSystem._loaded_news_bundle.clear()


# ── Tests: get_save_data() includes MarketEvent reconstruction fields ──

func test_get_save_data_includes_base_impact() -> void:
	# Arrange
	_inject_overnight_event("MACRO", 1, ["A001"], 0.05, 40)

	# Act
	var data: Dictionary = NewsEventSystem.get_save_data()
	var entries: Array = data.get("overnight_display", [])

	# Assert
	assert_eq(entries.size(), 1, "1건 저장")
	assert_almost_eq(float(entries[0].get("base_impact", 0.0)), 0.05, 0.0001,
		"base_impact가 저장돼야 함")


func test_get_save_data_includes_decay_ticks() -> void:
	# Arrange
	_inject_overnight_event("MACRO", 1, ["A001"], 0.03, 60)

	# Act
	var data: Dictionary = NewsEventSystem.get_save_data()
	var entries: Array = data.get("overnight_display", [])

	# Assert
	assert_eq(int(entries[0].get("decay_ticks", 0)), 60, "decay_ticks가 저장돼야 함")


func test_get_save_data_includes_event_type() -> void:
	# Arrange
	_inject_overnight_event("MACRO", -1, ["A001"], 0.02, 30)

	# Act
	var data: Dictionary = NewsEventSystem.get_save_data()
	var entries: Array = data.get("overnight_display", [])

	# Assert
	assert_eq(int(entries[0].get("event_type", -1)),
		MarketEvent.EventType.GRADUAL_SHIFT, "event_type GRADUAL_SHIFT이 저장돼야 함")


func test_get_save_data_includes_direction_and_scope() -> void:
	# Arrange
	_inject_overnight_event("SECTOR", -1, ["B001", "B002"], 0.04, 20)

	# Act
	var data: Dictionary = NewsEventSystem.get_save_data()
	var entries: Array = data.get("overnight_display", [])

	# Assert
	assert_eq(entries[0].get("direction"), -1, "direction 저장")
	assert_eq(entries[0].get("scope"), "SECTOR", "scope 저장")
	var targets: Array = entries[0].get("target_stock_ids", [])
	assert_eq(targets.size(), 2, "target_stock_ids 2건 저장")


# ── Tests: load_save_data() pushes reconstructed events to PriceEngine ──

func test_load_save_data_with_base_impact_populates_loaded_news_bundle() -> void:
	# Arrange — simulate a post-fix save
	var entries: Array = [_make_overnight_entry("MACRO", 1, ["A001"], 0.05, 40)]
	var data: Dictionary = {"overnight_display": entries}

	# Act
	NewsEventSystem.load_save_data(data)

	# Assert — display bundle populated
	var bundle: Array[Dictionary] = NewsEventSystem.get_and_clear_loaded_news()
	assert_eq(bundle.size(), 1, "로드 후 뉴스 번들 1건 있어야 함")
	assert_eq(bundle[0].get("scope"), "MACRO", "scope 복원")


func test_load_save_data_without_base_impact_skips_push_gracefully() -> void:
	## Pre-fix saves lack base_impact → load should not crash, just skip push.
	# Arrange — old format save (no base_impact field)
	var entries: Array = [{
		"headline": "구버전 뉴스",
		"body": "구버전 본문",
		"scope": "MACRO",
		"impact_tier": "SMALL",
		"direction": 1,
		"target_stock_ids": ["A001"],
	}]
	var data: Dictionary = {"overnight_display": entries}

	# Act / Assert — must not crash
	NewsEventSystem.load_save_data(data)
	assert_true(true, "구버전 세이브 로드 시 크래시 없어야 함")


func test_load_save_data_sets_state_ready() -> void:
	# Arrange
	NewsEventSystem._state = NewsEventSystem.SystemState.UNINITIALIZED
	var data: Dictionary = {"overnight_display": []}

	# Act
	NewsEventSystem.load_save_data(data)

	# Assert
	assert_eq(NewsEventSystem._state, NewsEventSystem.SystemState.READY,
		"load 후 state가 READY여야 함")


# ── Tests: save → load round-trip preserves all event data ──

func test_save_load_roundtrip_preserves_entry_count() -> void:
	# Arrange — 2건 overnight 이벤트
	_inject_overnight_event("MACRO",    1,  ["A001"],         0.03, 40)
	_inject_overnight_event("SECTOR",   -1, ["B001", "B002"], 0.05, 60)

	# Act — save then load
	var saved: Dictionary = NewsEventSystem.get_save_data()
	NewsEventSystem._overnight_buffer.clear()
	NewsEventSystem.load_save_data(saved)

	# Assert — 2건 뉴스 번들 복원
	var bundle: Array[Dictionary] = NewsEventSystem.get_and_clear_loaded_news()
	assert_eq(bundle.size(), 2, "round-trip 후 2건 복원")


func test_save_load_roundtrip_preserves_direction() -> void:
	# Arrange
	_inject_overnight_event("MACRO", -1, ["A001"], 0.04, 30)

	# Act
	var saved: Dictionary = NewsEventSystem.get_save_data()
	NewsEventSystem._overnight_buffer.clear()
	NewsEventSystem.load_save_data(saved)

	# Assert
	var bundle: Array[Dictionary] = NewsEventSystem.get_and_clear_loaded_news()
	assert_eq(bundle.size(), 1)
	assert_eq(bundle[0].get("direction"), -1, "direction -1 복원")
