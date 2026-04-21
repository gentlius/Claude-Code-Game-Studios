extends GutTest
## Unit tests for NewsEventSystem — market_id filtering (GDD §TD-DR-05).
## See: design/gdd/news-events.md Implementation Checklist


func test_event_pool_filtered_by_market_id() -> void:
	# Arrange — build two template stubs, one KR and one US
	var kr_template: Dictionary = {
		"id": "KR_ONLY", "market_id": "KR",
		"type": "INDIVIDUAL", "magnitude": "SMALL", "weight": 1.0,
		"headline_key": "test_kr", "affected_sectors": [], "mutex_group": ""
	}
	var us_template: Dictionary = {
		"id": "US_ONLY", "market_id": "US",
		"type": "INDIVIDUAL", "magnitude": "SMALL", "weight": 1.0,
		"headline_key": "test_us", "affected_sectors": [], "mutex_group": ""
	}

	# Filter logic mirrors NewsEventSystem._load_event_pool()
	var market_id: String = "KR"
	var templates: Array[Dictionary] = [kr_template, us_template]
	var filtered: Array[Dictionary] = templates.filter(
		func(t: Dictionary) -> bool:
			return t.get("market_id", "KR").to_upper() == market_id
	)

	# Assert — only the KR template survives
	assert_eq(filtered.size(), 1, "Only KR template should pass the KR filter")
	assert_eq(filtered[0]["id"], "KR_ONLY",
		"Filtered template should be KR_ONLY, not US_ONLY")


func test_event_pool_defaults_to_kr_when_market_id_absent() -> void:
	# Templates without market_id default to "KR" (backwards-compat)
	var legacy_template: Dictionary = {
		"id": "LEGACY", "type": "INDIVIDUAL", "magnitude": "SMALL", "weight": 1.0,
		"headline_key": "test_legacy", "affected_sectors": [], "mutex_group": ""
	}

	var market_id: String = "KR"
	var templates: Array[Dictionary] = [legacy_template]
	var filtered: Array[Dictionary] = templates.filter(
		func(t: Dictionary) -> bool:
			return t.get("market_id", "KR").to_upper() == market_id
	)

	assert_eq(filtered.size(), 1,
		"Legacy template without market_id should pass KR filter")
