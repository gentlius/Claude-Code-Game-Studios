extends GutTest
## Unit tests for NewsEventSystem — mutex_group filtering (GDD Rule 3-1).
## ADR-027: daily mutex moved to C++ EventEngine — all tests marked pending.
## See: design/gdd/news-events.md §3-1


func before_each() -> void:
	pass


# ── Tests: _is_mutex_blocked_for_stock ──

func test_mutex_null_does_not_block() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


func test_mutex_empty_string_does_not_block() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


func test_mutex_fixed_key_blocks_after_registration() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


func test_mutex_fixed_key_different_group_not_blocked() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


func test_mutex_stock_placeholder_blocks_same_stock() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


func test_mutex_stock_placeholder_allows_different_stock() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


func test_mutex_stock_placeholder_independent_per_stock() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


# ── Tests: _register_mutex ──

func test_register_mutex_stores_template_id() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


func test_register_mutex_with_stock_resolves_placeholder() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


func test_register_mutex_null_group_no_op() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


# ── Tests: Daily Reset ──

func test_mutex_clears_on_market_open() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")


func test_mutex_blocked_then_cleared_then_unblocked() -> void:
	pending("daily mutex moved to C++ EventEngine (ADR-027)")
