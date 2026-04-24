## Autoload — Manages lifestyle spending: residence, luxury goods, alternative investments.
## Tracks tangible assets (real estate, luxury) for total_assets calculation (F3).
## Auto-settlement runs on every market close via process_market_close(day, week).
## Season-end items (rental income, recurring costs) self-detect the last season day.
## See: design/gdd/lifestyle-spending.md §3-1
extends Node

# ── Signals ──

## Emitted when tangible asset value changes (purchase, sale, depreciation, exit).
signal tangible_value_changed(new_value: int)

## Emitted when the player's current residence tier changes (upgrade).
signal residence_changed(tier: int, residence_name: String)

## Emitted when a title is earned (social contribution, luxury purchase milestone).
signal title_earned(title_id: String)

## Path to the external config file (assets/data/lifestyle_config.json).
const CONFIG_PATH: String = "res://assets/data/lifestyle_config.json"

# ── Config (Tuning Knobs) ──
## All values loaded from lifestyle_config.json in _ready(). Hardcoded values are fallback defaults.

## Residence names indexed by SeasonManager tier constant.
## Index -1 (TIER_FREE_MARKET) maps to "쪽방/고시원" (BRONZE default).
var RESIDENCE_NAMES: Array[String] = [
	"쪽방/고시원",             ## TIER_BRONZE (0) — 기본 제공
	"변두리 원룸",             ## TIER_SILVER (1)
	"도심 오피스텔",           ## TIER_GOLD (2)
	"강남 아파트 (중형)",      ## TIER_PLATINUM (3)
	"도심 대형 아파트",        ## TIER_EMERALD (4)
	"초고층 펜트하우스",       ## TIER_DIAMOND (5)
	"교외 대저택",             ## TIER_MASTER (6)
	"개인 섬/별장",            ## TIER_GRANDMASTER (7)
	"스카이 레지던스",         ## TIER_CHALLENGER (8)
	"영빈관급 저택",           ## TIER_LEGEND (9)
	"(엔딩)",                  ## TIER_MASTER_OF_INVESTMENT (10)
]

## Residence purchase costs indexed by tier (0 = bronze default, no cost).
var RESIDENCE_COSTS: Array[int] = [
	0,              ## TIER_BRONZE — 기본 제공
	500_000,        ## TIER_SILVER
	2_000_000,      ## TIER_GOLD
	10_000_000,     ## TIER_PLATINUM
	30_000_000,     ## TIER_EMERALD
	100_000_000,    ## TIER_DIAMOND
	300_000_000,    ## TIER_MASTER
	1_000_000_000,  ## TIER_GRANDMASTER
	3_000_000_000,  ## TIER_CHALLENGER
	10_000_000_000, ## TIER_LEGEND
	0,              ## TIER_MASTER_OF_INVESTMENT — 자동 전환 (구매 불가)
]

## Property rental rates (annual yield per season).
var RENTAL_RATE_OFFICETEL: float = 0.025  ## 소형 오피스텔 2.5%/시즌
var RENTAL_RATE_SANGGA: float    = 0.030  ## 강남 상가 3.0%/시즌
var RENTAL_RATE_BUILDING: float  = 0.040  ## 빌딩 4.0%/시즌

## Title eligibility definitions loaded from lifestyle_config.json.
## Each entry: { titleId: String, condition: String, itemId?: String }
## condition "has_property" triggers on any tangible asset; "has_luxury" checks itemId.
## Fallback defaults mirror the JSON titles array so titles work even if the file is missing.
var _title_definitions: Array[Dictionary] = [
	{"titleId": "건물주",      "condition": "has_property"},
	{"titleId": "수입차 애호가", "condition": "has_luxury", "itemId": "luxury_car"},
	{"titleId": "컬렉터",      "condition": "has_luxury", "itemId": "luxury_watch"},
	{"titleId": "멤버스 온리", "condition": "has_luxury", "itemId": "golf_club"},
	{"titleId": "요트클럽",    "condition": "has_luxury", "itemId": "yacht_berth"},
]

## Startup exit probabilities — B-grade (GDD §F5).
var STARTUP_IPO_CHANCE: float    = 0.20
var STARTUP_MA_CHANCE: float     = 0.70   ## cumulative: 0.20 + 0.50
var STARTUP_IPO_MIN: float       = 2.0
var STARTUP_IPO_MAX: float       = 5.0
var STARTUP_MA_MIN: float        = 1.0
var STARTUP_MA_MAX: float        = 1.5

## Startup exit probabilities — C-grade (GDD §F5, rebalanced 2026-04-20).
var STARTUP_C_IPO_CHANCE: float  = 0.15
var STARTUP_C_MA_CHANCE: float   = 0.30  ## cumulative: 0.15 + 0.15

## Real estate maintenance cost deducted each season (GDD §F3, lifestyle-spending §3-2).
const REAL_ESTATE_MAINTENANCE_RATE: float = 0.005

## Scholarship buff: news delay reduction in ticks, valid for first trading day of next season.
## Set by purchase_network_item("scholarship"). See: design/gdd/lifestyle-spending.md §3-2.
const SCHOLARSHIP_NEWS_DELAY_REDUCTION: int = 5

## Donation amount limits (GDD §3-2). Overridden by lifestyle_config.json.
var DONATION_MIN: int = 1_000_000
var DONATION_MAX: int = 50_000_000

# ── State ──

## Current residence tier (index into RESIDENCE_NAMES / RESIDENCE_COSTS).
var _residence_tier: int = 0

## Tangible asset portfolio: Array of {type, purchase_price, seasons_held, ...}
var _tangible_assets: Array[Dictionary] = []

## Purchased luxury item IDs (Set semantics — key = item_id, value = true).
var _owned_luxury: Dictionary = {}

## Earned title IDs.
var _titles: Array[String] = []

## Pending startup investments: Array of {amount, seasons_remaining, rng_seed}
var _startups: Array[Dictionary] = []

## Recurring cost items: Array of {item_id, cost_per_season}
var _recurring_costs: Array[Dictionary] = []

## Cached sum of all tangible asset purchase prices.
var _tangible_value_cache: int = 0

## True after scholarship purchased — activates at start of the NEXT season (day 0 only).
## Cleared when the next season starts (transitions to _scholarship_buff_day0_active).
var _scholarship_buff_pending: bool = false
## True on day 0 of the season immediately following scholarship purchase.
## Cleared at end of day 0 market close. Used by get_news_delay_buff_ticks().
var _scholarship_buff_day0_active: bool = false


# ── Lifecycle ──

func _ready() -> void:
	_load_config()
	# Auto-settlement: runs on every market close, self-detects season-end day.
	# SeasonManager dependency removed — GameClock is the sole timer source.
	# GDD: lifestyle-spending.md §3-1
	GameClock.on_market_close.connect(_on_market_close)
	GameClock.on_season_start.connect(_on_season_start_scholarship)


# ── Config Loading ──

## Load tuning values from assets/data/lifestyle_config.json.
## Falls back to hardcoded defaults on any read or parse error (design/gdd/lifestyle-spending.md §7).
func _load_config() -> void:
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("LifestyleManager._load_config: cannot open %s — using defaults" % CONFIG_PATH)
		return
	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		push_warning("LifestyleManager._load_config: JSON parse error in %s — using defaults" % CONFIG_PATH)
		return
	var cfg: Dictionary = parsed as Dictionary

	# Residence names
	if cfg.has("residenceNames") and cfg["residenceNames"] is Array:
		var arr: Array = cfg["residenceNames"]
		var loaded: Array[String] = []
		for v: Variant in arr:
			loaded.append(str(v))
		if not loaded.is_empty():
			RESIDENCE_NAMES = loaded

	# Residence costs
	if cfg.has("residenceCosts") and cfg["residenceCosts"] is Array:
		var arr: Array = cfg["residenceCosts"]
		var loaded: Array[int] = []
		for v: Variant in arr:
			loaded.append(int(v))
		if not loaded.is_empty():
			RESIDENCE_COSTS = loaded

	# Rental rates (nested dictionary)
	if cfg.has("rentalRates") and cfg["rentalRates"] is Dictionary:
		var rates: Dictionary = cfg["rentalRates"]
		if rates.has("officetel"): RENTAL_RATE_OFFICETEL = float(rates["officetel"])
		if rates.has("sangga"):    RENTAL_RATE_SANGGA    = float(rates["sangga"])
		if rates.has("building"):  RENTAL_RATE_BUILDING  = float(rates["building"])

	# Startup probabilities
	if cfg.has("startupIpoChance"):  STARTUP_IPO_CHANCE = float(cfg["startupIpoChance"])
	if cfg.has("startupMaChance"):   STARTUP_MA_CHANCE  = float(cfg["startupMaChance"])
	if cfg.has("startupIpoMin"):     STARTUP_IPO_MIN    = float(cfg["startupIpoMin"])
	if cfg.has("startupIpoMax"):     STARTUP_IPO_MAX    = float(cfg["startupIpoMax"])
	if cfg.has("startupMaMin"):      STARTUP_MA_MIN     = float(cfg["startupMaMin"])
	if cfg.has("startupMaMax"):      STARTUP_MA_MAX     = float(cfg["startupMaMax"])

	# Donation limits
	if cfg.has("donationMin"): DONATION_MIN = int(cfg["donationMin"])
	if cfg.has("donationMax"): DONATION_MAX = int(cfg["donationMax"])

	# Title definitions — replaces hardcoded TITLE_ITEM_ID_* consts.
	if cfg.has("titles") and cfg["titles"] is Array:
		_title_definitions.clear()
		for entry: Variant in cfg["titles"]:
			if entry is Dictionary:
				_title_definitions.append(entry as Dictionary)


# ── Public API: Queries ──

## Returns the total tangible asset value for total_assets calculation (F3).
## GDD §F2: tangible_asset_value = purchase_price (depreciation_rate = 0 currently).
func get_tangible_value() -> int:
	return _tangible_value_cache


## Returns the current residence tier index.
func get_residence_tier() -> int:
	return _residence_tier


## Returns the display name of the current residence.
func get_residence_name() -> String:
	if _residence_tier < 0 or _residence_tier >= RESIDENCE_NAMES.size():
		return RESIDENCE_NAMES[0]
	return RESIDENCE_NAMES[_residence_tier]


## Returns all earned title IDs.
func get_titles() -> Array[String]:
	return _titles.duplicate()


## Returns true if the player owns a specific luxury item.
func has_luxury(item_id: String) -> bool:
	return _owned_luxury.has(item_id)


# ── Public API: Purchases ──

## Attempt to upgrade residence to the next tier.
## GDD §3-2: Only sequential upgrade (no skipping). Returns false if upgrade is not possible.
func upgrade_residence() -> bool:
	var next_tier: int = _residence_tier + 1
	if next_tier >= RESIDENCE_NAMES.size():
		return false  ## Already at max tier
	if next_tier >= RESIDENCE_COSTS.size():
		return false
	if RESIDENCE_COSTS[next_tier] == 0 and next_tier == RESIDENCE_COSTS.size() - 1:
		return false  ## Master of Investment tier — auto unlock only

	var cost: int = RESIDENCE_COSTS[next_tier]
	if cost > 0 and not CurrencySystem.cash_deduct(cost):
		return false  ## Insufficient cash_assets (GDD §5 EC-1)

	_residence_tier = next_tier
	residence_changed.emit(_residence_tier, get_residence_name())
	return true


## Purchase a luxury item by item_id.
## Caller is responsible for resolving the item's cost before calling this.
## Returns false if already owned or insufficient cash.
func purchase_luxury(item_id: String, cost: int) -> bool:
	if _owned_luxury.has(item_id):
		return false
	if not CurrencySystem.cash_deduct(cost):
		return false
	_owned_luxury[item_id] = true
	_check_and_grant_titles()
	return true


## Record purchase of a tangible real-estate asset (부동산 매입).
## GDD §3-2 카테고리 5: 매입가 = tangible_asset_value (no depreciation currently).
## Returns false if insufficient cash_assets.
func purchase_property(property_type: String, purchase_price: int) -> bool:
	if not CurrencySystem.cash_deduct(purchase_price):
		return false
	var entry: Dictionary = {
		"type": property_type,
		"purchase_price": purchase_price,
		"seasons_held": 0,
	}
	_tangible_assets.append(entry)
	_tangible_value_cache += purchase_price
	tangible_value_changed.emit(_tangible_value_cache)
	_check_and_grant_titles()
	return true


## Register a recurring cost item (연회비 등). Called after purchase_luxury or network buy.
## item_id: unique identifier matching purchased item. cost_per_season: amount deducted each offseason.
## No-op if already registered (idempotent).
func add_recurring_cost(item_id: String, cost_per_season: int) -> void:
	for item: Dictionary in _recurring_costs:
		if item.get("item_id", "") == item_id:
			return  ## Already registered
	_recurring_costs.append({"item_id": item_id, "cost_per_season": cost_per_season})


## Mark an item as owned in the luxury registry without deducting cash.
## Used for network/social items where cash deduction is handled by the caller (LifestyleScreen).
## Also triggers title check.
func mark_luxury_owned(item_id: String) -> void:
	if _owned_luxury.has(item_id):
		return
	_owned_luxury[item_id] = true
	_check_and_grant_titles()


## Purchase a network or social contribution item: deducts cash, marks owned, grants XP.
## GDD §3-2: 네트워크/사회공헌 구매 통합 API.
## Special case: "scholarship" grants no XP; instead sets scholarship news delay buff
## (active for first trading day of next season). See: SCHOLARSHIP_NEWS_DELAY_REDUCTION.
## Returns false if already owned or insufficient cash.
func purchase_network_item(item_id: String, cost: int, xp_bonus: int, is_recurring: bool) -> bool:
	if _owned_luxury.has(item_id):
		return false
	if not CurrencySystem.cash_deduct(cost):
		return false
	_owned_luxury[item_id] = true
	if is_recurring:
		add_recurring_cost(item_id, cost)
	if item_id == "scholarship":
		# GDD lifestyle-spending.md §3-2: 장학재단 → 다음 시즌 첫 거래일 뉴스 딜레이 −5틱
		# Buff is pending until the NEXT season starts (not immediate).
		_scholarship_buff_pending = true
	elif xp_bonus > 0:
		XpSystem.grant_lifestyle_xp(xp_bonus)
	_check_and_grant_titles()
	return true


## Returns the active scholarship news delay reduction in ticks (0 if no buff).
## Only non-zero on day 0 of the season immediately after scholarship purchase.
## Called by NewsEventSystem.get_news_delay(). GDD lifestyle-spending.md §3-2.
func get_news_delay_buff_ticks() -> int:
	return SCHOLARSHIP_NEWS_DELAY_REDUCTION if _scholarship_buff_day0_active else 0


## Purchase a social contribution item: deducts cash, marks owned, grants XP.
## GDD §3-2: 사회공헌 구매 통합 API. Returns false if already owned or insufficient cash.
func purchase_social_item(item_id: String, cost: int, xp_bonus: int, is_recurring: bool) -> bool:
	return purchase_network_item(item_id, cost, xp_bonus, is_recurring)


## Donate to public campaign (공익 캠페인 기부). GDD §3-2: XP = ₩10M당 +1, 최대 +5/회.
## Returns false if amount out of range or insufficient cash.
func donate(amount: int) -> bool:
	if amount < DONATION_MIN or amount > DONATION_MAX:
		return false
	if not CurrencySystem.cash_deduct(amount):
		return false
	var xp_bonus: int = mini(amount / 10_000_000, 5)
	if xp_bonus > 0:
		XpSystem.grant_weekly_prize_xp(xp_bonus)
	return true


## Record a startup angel investment (대안 투자 — 스타트업 엔젤).
## GDD §3-2: seasons_to_exit is 3~6 (random at investment time).
## grade: "B" (standard) or "C" (lower-quality, riskier). Defaults to "B".
## Returns false if insufficient cash_assets.
func invest_startup(amount: int, seasons_to_exit: int, rng_seed: int, grade: String = "B") -> bool:
	if not CurrencySystem.cash_deduct(amount):
		return false
	var entry: Dictionary = {
		"amount": amount,
		"seasons_remaining": seasons_to_exit,
		"rng_seed": rng_seed,
		"grade": grade,
	}
	_startups.append(entry)
	return true


# ── Daily Auto-Settlement ──

## Called every market close. Processes items on their natural schedule:
##   - Startup exits: checked every day (when seasons_remaining reaches 0).
##   - Rental income / Recurring costs / seasons_held++: season-final day only.
## GDD: lifestyle-spending.md §3-1
func process_market_close(_current_day: int = 0, _current_week: int = 0) -> void:
	var is_season_final: bool = GameClock.is_season_final_day()
	# Startup exits: decrement counter on season-final day, resolve when it hits 0.
	_process_startup_exits(is_season_final)
	if is_season_final:
		_process_rental_income()
		_process_recurring_costs()
		_tick_seasons_held()


func _process_rental_income() -> void:
	for asset: Dictionary in _tangible_assets:
		var purchase_price: int = asset.get("purchase_price", 0)
		var rate: float = _get_rental_rate(asset.get("type", ""))
		# Rental income (GDD §F3)
		if rate > 0.0:
			var income: int = int(float(purchase_price) * rate)
			if income > 0:
				CurrencySystem.cash_add(income)
		# Maintenance cost deducted each season (GDD §F3, REAL_ESTATE_MAINTENANCE_RATE = 0.5%/시즌)
		var maintenance: int = int(float(purchase_price) * REAL_ESTATE_MAINTENANCE_RATE)
		if maintenance > 0:
			CurrencySystem.cash_deduct(maintenance)


func _get_rental_rate(property_type: String) -> float:
	match property_type:
		"officetel": return RENTAL_RATE_OFFICETEL
		"sangga":    return RENTAL_RATE_SANGGA
		"building":  return RENTAL_RATE_BUILDING
		_:           return 0.0


## Processes startup investments. tick_season=true decrements the season counter (season-final day only).
func _process_startup_exits(tick_season: bool) -> void:
	var remaining: Array[Dictionary] = []
	for startup: Dictionary in _startups:
		var seasons_left: int = startup.get("seasons_remaining", 1)
		if tick_season:
			seasons_left -= 1
		if seasons_left <= 0:
			_resolve_startup_exit(startup)
		else:
			startup["seasons_remaining"] = seasons_left
			remaining.append(startup)
	_startups = remaining


func _resolve_startup_exit(startup: Dictionary) -> void:
	var amount: int = startup.get("amount", 0)
	var grade: String = startup.get("grade", "B")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = startup.get("rng_seed", 0)
	var roll: float = rng.randf()
	var multiplier: float = 0.0
	# Grade-specific cumulative probability thresholds (GDD §F5).
	var ipo_threshold: float = STARTUP_C_IPO_CHANCE if grade == "C" else STARTUP_IPO_CHANCE
	var ma_threshold: float  = STARTUP_C_MA_CHANCE  if grade == "C" else STARTUP_MA_CHANCE
	if roll < ipo_threshold:
		multiplier = rng.randf_range(STARTUP_IPO_MIN, STARTUP_IPO_MAX)
	elif roll < ma_threshold:
		multiplier = rng.randf_range(STARTUP_MA_MIN, STARTUP_MA_MAX)
	# 폐업: multiplier stays 0.0
	var proceeds: int = int(float(amount) * multiplier)
	if proceeds > 0:
		CurrencySystem.cash_add(proceeds)


func _process_recurring_costs() -> void:
	## GDD §5 EC-5: Insufficient cash → 강제 해지 (환불 없음, 칭호 유지).
	var still_active: Array[Dictionary] = []
	for item: Dictionary in _recurring_costs:
		var cost: int = item.get("cost_per_season", 0)
		if CurrencySystem.cash_deduct(cost):
			still_active.append(item)
		## else: 잔액 부족 → 해지. item이 still_active에 포함되지 않음.
	_recurring_costs = still_active


func _tick_seasons_held() -> void:
	for asset: Dictionary in _tangible_assets:
		asset["seasons_held"] = asset.get("seasons_held", 0) + 1


# ── Title System ──

func _check_and_grant_titles() -> void:
	## Driven by _title_definitions loaded from lifestyle_config.json (§titles array).
	## Each definition has: titleId (String), condition (String), optional itemId (String).
	## condition "has_property" — granted when at least one tangible asset is owned.
	## condition "has_luxury"   — granted when _owned_luxury contains the given itemId.
	for def: Dictionary in _title_definitions:
		var title_id: String = def.get("titleId", "")
		if title_id.is_empty() or _titles.has(title_id):
			continue
		var condition: String = def.get("condition", "")
		match condition:
			"has_property":
				if not _tangible_assets.is_empty():
					_grant_title(title_id)
			"has_luxury":
				var item_id: String = def.get("itemId", "")
				if not item_id.is_empty() and _owned_luxury.has(item_id):
					_grant_title(title_id)


func _grant_title(title_id: String) -> void:
	_titles.append(title_id)
	title_earned.emit(title_id)


# ── Signal Handlers ──

func _on_market_close() -> void:
	process_market_close(GameClock.get_current_day(), GameClock.get_current_week())
	_tick_scholarship_buff()  # explicit ordering: settlement first, then buff expiry


## Activates scholarship buff at the start of the next season (pending → active).
func _on_season_start_scholarship() -> void:
	if _scholarship_buff_pending:
		_scholarship_buff_pending = false
		_scholarship_buff_day0_active = true


## Clears the scholarship day-0 buff at end of the first trading day.
## Day 0 is the first trading day; buff expires after market close.
func _tick_scholarship_buff() -> void:
	if _scholarship_buff_day0_active and GameClock.get_current_day() == 0:
		_scholarship_buff_day0_active = false


# ── Serialization ──

## Returns serializable state for SaveSystem.
func get_save_data() -> Dictionary:
	return {
		"residence_tier": _residence_tier,
		"tangible_assets": _tangible_assets.duplicate(true),
		"owned_luxury": _owned_luxury.duplicate(),
		"titles": _titles.duplicate(),
		"startups": _startups.duplicate(true),
		"recurring_costs": _recurring_costs.duplicate(true),
		"tangible_value_cache": _tangible_value_cache,
		"scholarship_buff_pending": _scholarship_buff_pending,
		"scholarship_buff_day0_active": _scholarship_buff_day0_active,
	}


## Restores state from save data.
## Backward-compatible: lifestyle key absent in v1-v3 saves → defaults (Beta+).
func load_save_data(data: Dictionary) -> void:
	_residence_tier = data.get("residence_tier", 0)
	_owned_luxury = data.get("owned_luxury", {})
	_titles = []
	for t: Variant in data.get("titles", []):
		if t is String:
			_titles.append(t as String)
	_tangible_assets = []
	for a: Variant in data.get("tangible_assets", []):
		if a is Dictionary:
			_tangible_assets.append(a as Dictionary)
	_startups = []
	for s: Variant in data.get("startups", []):
		if s is Dictionary:
			_startups.append(s as Dictionary)
	_recurring_costs = []
	for r: Variant in data.get("recurring_costs", []):
		if r is Dictionary:
			_recurring_costs.append(r as Dictionary)
	_tangible_value_cache = data.get("tangible_value_cache", 0)
	_scholarship_buff_pending = data.get("scholarship_buff_pending", false)
	_scholarship_buff_day0_active = data.get("scholarship_buff_day0_active", false)
	tangible_value_changed.emit(_tangible_value_cache)


## Resets all lifestyle state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_residence_tier = 0
	_tangible_assets.clear()
	_owned_luxury.clear()
	_titles.clear()
	_startups.clear()
	_recurring_costs.clear()
	_tangible_value_cache = 0
	_scholarship_buff_pending = false
	_scholarship_buff_day0_active = false
