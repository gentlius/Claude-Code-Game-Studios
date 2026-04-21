## MarketProfile — Autoload. 시장별 규칙 전체를 JSON에서 읽어 단일 API로 제공.
## DLC 시장 추가 시 새 JSON 파일 추가만으로 확장 가능.
## 코드 내 `if market == "KR"` 분기 금지 — 모든 시장별 값은 이 autoload를 통한다.
##
## GDD: design/gdd/financial-report-system.md §7 (calendar params)
## ADR: docs/architecture/ADR-021 — MarketProfile 데이터 기반 시장 규칙 분리
## 진입점: 시즌 시작 시 SeasonManager → MarketProfile.load_market("KR") (S10-07)
extends Node

# ── Constants ──

const PROFILE_DIR: String = "res://assets/data/market_profiles/"
const DEFAULT_MARKET_ID: String = "KR"

# ── State ──

var _active_profile: Dictionary = {}
var _active_market_id: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ── Lifecycle ──

func _ready() -> void:
	load_market(DEFAULT_MARKET_ID)


# ── Public API: Load ──

## Load the market profile for [param market_id] (e.g. "KR", "US").
## Falls back to DEFAULT_MARKET_ID if not found. Safe to call multiple times.
func load_market(market_id: String) -> bool:
	var path: String = "%smarket_%s.json" % [PROFILE_DIR, market_id.to_lower()]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("MarketProfile: cannot open '%s' — market '%s' unavailable" % [path, market_id])
		return false
	var result: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if result == null or not result is Dictionary:
		push_warning("MarketProfile: JSON parse failed for '%s'" % path)
		return false
	_active_profile = result as Dictionary
	_active_market_id = market_id.to_upper()
	_validate_rivalry_weights()
	return true


## Returns the market_id of the currently loaded profile (e.g. "KR").
func get_active_market_id() -> String:
	return _active_market_id


## Returns the full active profile dictionary. Prefer specific getters.
func get_active() -> Dictionary:
	return _active_profile.duplicate(true)


# ── Public API: Sector / ETF ──

## Returns the ordered list of sector names for the active market.
## AC S10-07: MarketProfile is authoritative sector source.
func get_sectors() -> Array[String]:
	var result: Array[String] = []
	for s: Variant in _active_profile.get("sectors", []):
		result.append(str(s))
	return result


## Returns all ETF definitions as a dict of etf_id → {sector, base_price, name_ko}.
func get_etfs() -> Dictionary:
	return _active_profile.get("etfs", {}).duplicate(true)


## Returns the archetype name for [param sector] (e.g. "반도체" → "TECH").
## Returns "" if unknown.
func get_archetype(sector: String) -> String:
	var archetypes: Dictionary = _active_profile.get("sector_archetypes", {})
	return str(archetypes.get(sector, ""))


## Returns all sectors belonging to [param archetype] (e.g. "TECH" → ["반도체", "2차전지", "게임"]).
func get_sectors_in_archetype(archetype: String) -> Array[String]:
	var result: Array[String] = []
	var archetypes: Dictionary = _active_profile.get("sector_archetypes", {})
	for sector: String in archetypes.keys():
		if str(archetypes[sector]) == archetype:
			result.append(sector)
	return result


## Returns the rivalry weight dict for [param archetype] (e.g. {INDUSTRIAL: 0.4, ...}).
## Weights sum to 1.0 (validated on load).
func get_rivalry_weights(archetype: String) -> Dictionary:
	var weights: Dictionary = _active_profile.get("rivalry_weights", {})
	return weights.get(archetype, {}).duplicate(true)


# ── Public API: Rotation ──

## Returns the full rotation params dict for the active market.
func get_rotation_params() -> Dictionary:
	return _active_profile.get("rotation_params", {}).duplicate(true)


## Returns a random rotation headline key for [param direction] ("inflow" or "outflow").
## Caller uses `tr(key).format({sector: name})` to get localized text.
func get_rotation_headline(direction: String) -> String:
	var headline_keys: Dictionary = _active_profile.get("rotation_headline_keys", {})
	var keys: Array = headline_keys.get(direction, [])
	if keys.is_empty():
		return ""
	return str(keys[_rng.randi() % keys.size()])


# ── Public API: Trading ──

## Returns a trading parameter by key (e.g. "commission", "sell_tax", "margin_rate_min").
## Returns null if key not found. Caller casts to appropriate type.
func get_trading_param(key: String) -> Variant:
	return _active_profile.get("trading", {}).get(key, null)


# ── Public API: Calendar / Reporting ──

## Returns a calendar parameter by key (e.g. "report_cycle_seasons", "report_type_sequence").
## Returns null if key not found.
func get_calendar_param(key: String) -> Variant:
	return _active_profile.get("calendar", {}).get(key, null)


# ── Public API: Endings ──

## Returns a field from the endings block for [param ending_id].
## Example: get_ending_param("bankruptcy", "visual") → "res://assets/endings/kr_hangang.png"
## Returns null if ending_id or field not found.
func get_ending_param(ending_id: String, field: String) -> Variant:
	var endings: Dictionary = _active_profile.get("endings", {})
	var entry: Dictionary = endings.get(ending_id, {})
	return entry.get(field, null)


## Returns all ending IDs defined for the active market.
func get_ending_ids() -> Array[String]:
	var result: Array[String] = []
	var endings: Dictionary = _active_profile.get("endings", {})
	for k: String in endings.keys():
		result.append(k)
	return result


# ── Public API: Achievements (DLC) ──

## Returns the DLC achievements array for the active market. Empty for KR base game.
func get_dlc_achievements() -> Array:
	return _active_profile.get("achievements", [])


# ── Public API: Macro Context (future) ──

## Apply a macro context modifier (e.g. "CRISIS", "BULL_RUN").
## Placeholder — actual implementation in Polish sprint.
func apply_macro_context(_context_id: String) -> void:
	pass


## Reset macro context to baseline rivalry_weights.
func reset_macro_context() -> void:
	pass


# ── Validation ──

## Validates that each rivalry_weight row sums to 1.0 (±0.01 tolerance).
## Logs a warning if any row is malformed. AC S10-07.
func _validate_rivalry_weights() -> void:
	var weights: Dictionary = _active_profile.get("rivalry_weights", {})
	for archetype: String in weights.keys():
		var row: Dictionary = weights[archetype]
		var total: float = 0.0
		for v: Variant in row.values():
			total += float(v)
		if absf(total - 1.0) > 0.011:
			push_warning(
				"MarketProfile [%s]: rivalry_weights[%s] sums to %.3f (expected 1.0)" \
				% [_active_market_id, archetype, total]
			)
