## Autoload — Manages deposit (permanent) and sim seed (per-season) accounts.
## Foundation layer. See: design/gdd/currency-system.md
extends Node

# ── Signals ──

signal sim_cash_changed(new_amount: int, delta: int)
signal deposit_changed(new_amount: int, delta: int)
signal season_initialized(seed_amount: int)
signal season_settled()

# ── Constants ──

const INITIAL_DEPOSIT: int = 1_000_000
const DEFAULT_SEASON_SEED: int = 1_000_000

# ── State ──

var _deposit: int = INITIAL_DEPOSIT
var _sim_cash: int = 0
var _season_active: bool = false

# ── Public API: Queries ──

## Returns the current sim cash balance (모의투자 잔액).
func get_sim_cash() -> int:
	return _sim_cash


## Returns the permanent deposit balance (예수금).
func get_deposit() -> int:
	return _deposit


## Returns true if a season is currently active.
func is_season_active() -> bool:
	return _season_active

# ── Public API: Sim Cash Operations ──

## Deduct from sim cash. Returns true if successful, false if insufficient.
func sim_deduct(amount: int) -> bool:
	if amount <= 0:
		return false
	if _sim_cash < amount:
		return false
	_sim_cash -= amount
	sim_cash_changed.emit(_sim_cash, -amount)
	return true


## Add to sim cash (sell proceeds, order cancellation refund, etc).
func sim_add(amount: int) -> void:
	if amount <= 0:
		return
	_sim_cash += amount
	sim_cash_changed.emit(_sim_cash, amount)

# ── Public API: Season Lifecycle ──

## Initialize sim seed for the very first season only.
## Must not be called mid-game; use start_season() for subsequent seasons.
## Emits season_initialized and sim_cash_changed.
func init_first_season(amount: int = DEFAULT_SEASON_SEED) -> void:
	if _sim_cash > 0:
		push_warning("CurrencySystem.init_first_season called on non-zero balance (%d) — ignoring" % _sim_cash)
		return
	_sim_cash = amount
	_season_active = true
	season_initialized.emit(amount)
	sim_cash_changed.emit(_sim_cash, amount)


## Settle the season. Marks the season inactive without touching the balance.
## The settlement flow (cancel orders → liquidate → award prizes) uses
## sim_add/sim_deduct directly, so the balance is already correct by the time
## this is called. Wiping _sim_cash here would erase carry-over funds.
func settle_season() -> void:
	_season_active = false
	season_settled.emit()


## Award prize money to the permanent deposit.
func award_prize(amount: int) -> void:
	if amount <= 0:
		return
	_deposit += amount
	deposit_changed.emit(_deposit, amount)


## Resets volatile season state for unit tests. Call in before_each.
## Does NOT reset _deposit — tests that need a clean deposit must set it directly.
func reset_for_testing() -> void:
	_sim_cash = 0
	_season_active = false


# ── Serialization ──

## Returns serializable state for save system (GDD: save-load.md)
func get_save_data() -> Dictionary:
	return {
		"sim_cash": _sim_cash,
		"deposit": _deposit,
		"season_active": _season_active,
	}


## Restores state from save data. Skips init_first_season side-effects.
func load_save_data(data: Dictionary) -> void:
	_sim_cash = maxi(data.get("sim_cash", DEFAULT_SEASON_SEED), 0)
	_deposit = maxi(data.get("deposit", INITIAL_DEPOSIT), 0)
	_season_active = data.get("season_active", _sim_cash > 0)  # fallback for old saves
	sim_cash_changed.emit(_sim_cash, 0)
	deposit_changed.emit(_deposit, 0)
