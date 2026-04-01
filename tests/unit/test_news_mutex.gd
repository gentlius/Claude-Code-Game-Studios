extends GutTest
## Unit tests for NewsEventSystem — mutex_group filtering (GDD Rule 3-1).
## See: design/gdd/news-events.md §3-1


# ── Helpers ──

## Create a minimal template dictionary with optional mutex_group.
func _make_template(id: String, mutex: Variant = null) -> Dictionary:
	return {
		"template_id": id,
		"scope": "INDIVIDUAL",
		"event_tags": ["clinical_trial"],
		"event_type": "INSTANT_SHOCK",
		"impact_tier": "LARGE",
		"impact_min": 0.10,
		"impact_max": 0.15,
		"direction": 1,
		"decay_ticks": 0,
		"decay_curve": "LINEAR",
		"headline_template": "Test headline",
		"weight_base": 1.0,
		"cooldown_ticks": 0,
		"mutex_group": mutex,
	}


## Create a minimal StockData for testing.
func _make_stock(id: String) -> StockData:
	var stock := StockData.new()
	stock.stock_id = id
	stock.name_ko = "테스트종목"
	stock.sector = "바이오"
	stock.base_price = 100000
	stock.volatility_profile = StockData.VolatilityProfile.HIGH
	stock.sector_sensitivity = 1.0
	stock.macro_sensitivity = 1.0
	return stock


func before_each() -> void:
	NewsEventSystem._daily_mutex.clear()


# ── Tests: _is_mutex_blocked_for_stock ──

func test_mutex_null_does_not_block() -> void:
	# Arrange
	var template: Dictionary = _make_template("TPL_01", null)

	# Act
	var blocked: bool = NewsEventSystem._is_mutex_blocked_for_stock(template, "MG")

	# Assert
	assert_false(blocked, "null mutex_group should never block")


func test_mutex_empty_string_does_not_block() -> void:
	# Arrange
	var template: Dictionary = _make_template("TPL_02", "")

	# Act
	var blocked: bool = NewsEventSystem._is_mutex_blocked_for_stock(template, "MG")

	# Assert
	assert_false(blocked, "empty string mutex_group should never block")


func test_mutex_fixed_key_blocks_after_registration() -> void:
	# Arrange — register a fixed mutex key
	var template_a: Dictionary = _make_template("RATE_UP_01", "rate_direction")
	NewsEventSystem._register_mutex(template_a, null)

	# Act — check if another template with same mutex is blocked
	var template_b: Dictionary = _make_template("RATE_DOWN_01", "rate_direction")
	var blocked: bool = NewsEventSystem._is_mutex_blocked_for_stock(template_b, "KB")

	# Assert
	assert_true(blocked, "same fixed mutex_group should block on same day")


func test_mutex_fixed_key_different_group_not_blocked() -> void:
	# Arrange — register "rate_direction"
	var template_a: Dictionary = _make_template("RATE_UP_01", "rate_direction")
	NewsEventSystem._register_mutex(template_a, null)

	# Act — check "foreign_flow" (different group)
	var template_b: Dictionary = _make_template("FOREIGN_BUY_01", "foreign_flow")
	var blocked: bool = NewsEventSystem._is_mutex_blocked_for_stock(template_b, "KB")

	# Assert
	assert_false(blocked, "different mutex_group should not block")


func test_mutex_stock_placeholder_blocks_same_stock() -> void:
	# Arrange — register bio_clinical for stock MG
	var template_a: Dictionary = _make_template("BIO_SUCCESS_01", "bio_clinical_{stock_id}")
	var stock_mg: StockData = _make_stock("MG")
	NewsEventSystem._register_mutex(template_a, stock_mg)

	# Act — check if same mutex group blocks for MG
	var template_b: Dictionary = _make_template("BIO_FAIL_01", "bio_clinical_{stock_id}")
	var blocked: bool = NewsEventSystem._is_mutex_blocked_for_stock(template_b, "MG")

	# Assert
	assert_true(blocked, "{stock_id} mutex should block same stock on same day")


func test_mutex_stock_placeholder_allows_different_stock() -> void:
	# Arrange — register bio_clinical for stock MG
	var template_a: Dictionary = _make_template("BIO_SUCCESS_01", "bio_clinical_{stock_id}")
	var stock_mg: StockData = _make_stock("MG")
	NewsEventSystem._register_mutex(template_a, stock_mg)

	# Act — check if same mutex group blocks for BF (different stock)
	var template_b: Dictionary = _make_template("BIO_FAIL_01", "bio_clinical_{stock_id}")
	var blocked: bool = NewsEventSystem._is_mutex_blocked_for_stock(template_b, "BF")

	# Assert
	assert_false(blocked, "{stock_id} mutex should NOT block different stock")


func test_mutex_stock_placeholder_independent_per_stock() -> void:
	# Arrange — register earnings for stock SC, then also for KF
	var tpl_a: Dictionary = _make_template("EARN_GOOD_01", "earnings_{stock_id}")
	var stock_sc: StockData = _make_stock("SC")
	var stock_kf: StockData = _make_stock("KF")
	NewsEventSystem._register_mutex(tpl_a, stock_sc)
	NewsEventSystem._register_mutex(tpl_a, stock_kf)

	# Act — SC and KF should be blocked, but NE should not
	var tpl_b: Dictionary = _make_template("EARN_BAD_01", "earnings_{stock_id}")
	var sc_blocked: bool = NewsEventSystem._is_mutex_blocked_for_stock(tpl_b, "SC")
	var kf_blocked: bool = NewsEventSystem._is_mutex_blocked_for_stock(tpl_b, "KF")
	var ne_blocked: bool = NewsEventSystem._is_mutex_blocked_for_stock(tpl_b, "NE")

	# Assert
	assert_true(sc_blocked, "SC should be mutex-blocked")
	assert_true(kf_blocked, "KF should be mutex-blocked")
	assert_false(ne_blocked, "NE should NOT be mutex-blocked")


# ── Tests: _register_mutex ──

func test_register_mutex_stores_template_id() -> void:
	# Arrange
	var template: Dictionary = _make_template("FOREIGN_BUY_01", "foreign_flow")

	# Act
	NewsEventSystem._register_mutex(template, null)

	# Assert
	assert_eq(NewsEventSystem._daily_mutex.get("foreign_flow"), "FOREIGN_BUY_01",
		"mutex should store template_id as value")


func test_register_mutex_with_stock_resolves_placeholder() -> void:
	# Arrange
	var template: Dictionary = _make_template("BIO_SUCCESS_01", "bio_clinical_{stock_id}")
	var stock: StockData = _make_stock("BF")

	# Act
	NewsEventSystem._register_mutex(template, stock)

	# Assert
	assert_true(NewsEventSystem._daily_mutex.has("bio_clinical_BF"),
		"mutex key should resolve {stock_id} to actual stock ID")
	assert_false(NewsEventSystem._daily_mutex.has("bio_clinical_{stock_id}"),
		"unresolved placeholder should not be stored")


func test_register_mutex_null_group_no_op() -> void:
	# Arrange
	var template: Dictionary = _make_template("GENERIC_01", null)

	# Act
	NewsEventSystem._register_mutex(template, null)

	# Assert
	assert_eq(NewsEventSystem._daily_mutex.size(), 0,
		"null mutex_group should not register anything")


# ── Tests: Daily Reset ──

func test_mutex_clears_on_market_open() -> void:
	# Arrange — register some mutex keys
	var tpl: Dictionary = _make_template("RATE_UP_01", "rate_direction")
	NewsEventSystem._register_mutex(tpl, null)
	assert_eq(NewsEventSystem._daily_mutex.size(), 1, "precondition: mutex registered")

	# Act — simulate market open clearing mutex
	NewsEventSystem._daily_mutex.clear()

	# Assert
	assert_eq(NewsEventSystem._daily_mutex.size(), 0,
		"mutex dictionary should be empty after daily clear")


func test_mutex_blocked_then_cleared_then_unblocked() -> void:
	# Arrange — register rate_direction
	var tpl_a: Dictionary = _make_template("RATE_UP_01", "rate_direction")
	NewsEventSystem._register_mutex(tpl_a, null)

	var tpl_b: Dictionary = _make_template("RATE_DOWN_01", "rate_direction")
	var blocked_before: bool = NewsEventSystem._is_mutex_blocked_for_stock(tpl_b, "KB")
	assert_true(blocked_before, "precondition: should be blocked before clear")

	# Act — simulate new day (clear mutex)
	NewsEventSystem._daily_mutex.clear()

	# Assert — should no longer be blocked
	var blocked_after: bool = NewsEventSystem._is_mutex_blocked_for_stock(tpl_b, "KB")
	assert_false(blocked_after, "should not be blocked after daily mutex clear")
