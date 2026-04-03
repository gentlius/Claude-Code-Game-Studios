# PROTOTYPE - NOT FOR PRODUCTION
# Question: Does the 3-layer price algorithm produce "readable but unpredictable" charts?
# Date: 2026-03-31

import random
import math
import json
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Optional

# ── Constants ──

class MarkovState(IntEnum):
    STRONG_UP = 0
    UPTREND = 1
    SIDEWAYS = 2
    DOWNTREND = 3
    STRONG_DOWN = 4
    BREAKOUT_UP = 5
    BREAKOUT_DOWN = 6

STATE_NAMES = [s.name for s in MarkovState]

class SeasonBias(IntEnum):
    BULL = 0
    NEUTRAL = 1
    BEAR = 2

class VolatilityProfile(IntEnum):
    LOW = 0
    MEDIUM = 1
    HIGH = 2
    EXTREME = 3

# ── State Parameters (from GDD Rule 1-1) ──

# (bias, mag_min, mag_max, noise_std, min_duration)
STATE_PARAMS = {
    MarkovState.STRONG_UP:     (+0.0012, +0.0003, +0.0020, 0.0008, 20),
    MarkovState.UPTREND:       (+0.0005, +0.0001, +0.0010, 0.0006, 30),
    MarkovState.SIDEWAYS:      ( 0.0000, -0.0005, +0.0005, 0.0004, 40),
    MarkovState.DOWNTREND:     (-0.0005, -0.0010, -0.0001, 0.0006, 30),
    MarkovState.STRONG_DOWN:   (-0.0012, -0.0020, -0.0003, 0.0008, 20),
    MarkovState.BREAKOUT_UP:   (+0.0030, +0.0010, +0.0050, 0.0015, 5),
    MarkovState.BREAKOUT_DOWN: (-0.0030, -0.0050, -0.0010, 0.0015, 5),
}

# ── Transition Matrix (MEDIUM baseline, GDD Rule 1-3) ──

TRANSITION_MATRIX_MEDIUM = [
    # SU    UT    SW    DT    SD    BU    BD
    [0.65, 0.20, 0.05, 0.02, 0.00, 0.08, 0.00],  # STRONG_UP
    [0.10, 0.60, 0.18, 0.05, 0.00, 0.05, 0.02],  # UPTREND
    [0.03, 0.15, 0.55, 0.15, 0.03, 0.05, 0.04],  # SIDEWAYS
    [0.00, 0.05, 0.18, 0.60, 0.10, 0.02, 0.05],  # DOWNTREND
    [0.00, 0.02, 0.05, 0.20, 0.65, 0.00, 0.08],  # STRONG_DOWN
    [0.15, 0.45, 0.15, 0.05, 0.00, 0.20, 0.00],  # BREAKOUT_UP
    [0.00, 0.05, 0.15, 0.45, 0.15, 0.00, 0.20],  # BREAKOUT_DOWN
]

# ── Volatility Profile Scaling (GDD Rule 1-5) ──

VOLATILITY_SCALING = {
    VolatilityProfile.LOW:     {"self_mult": 1.15, "breakout_mult": 0.30},
    VolatilityProfile.MEDIUM:  {"self_mult": 1.00, "breakout_mult": 1.00},
    VolatilityProfile.HIGH:    {"self_mult": 0.90, "breakout_mult": 2.00},
    VolatilityProfile.EXTREME: {"self_mult": 0.75, "breakout_mult": 4.00},
}

# ── Season Bias Adjustment (GDD Rule 1-6) ──

SEASON_BIAS_DELTA = {
    SeasonBias.BULL:    {"up_bonus": +0.01, "down_penalty": -0.01},
    SeasonBias.NEUTRAL: {"up_bonus":  0.00, "down_penalty":  0.00},
    SeasonBias.BEAR:    {"up_bonus": -0.01, "down_penalty": +0.01},
}

# ── Volume Parameters (GDD Rule 4) ──

BASE_VOLUME_RANGE = {
    VolatilityProfile.LOW:     (100, 300),
    VolatilityProfile.MEDIUM:  (200, 600),
    VolatilityProfile.HIGH:    (400, 1200),
    VolatilityProfile.EXTREME: (800, 3000),
}

STATE_VOLUME_MULT = {
    MarkovState.STRONG_UP: 1.5,
    MarkovState.UPTREND: 1.2,
    MarkovState.SIDEWAYS: 0.8,
    MarkovState.DOWNTREND: 1.2,
    MarkovState.STRONG_DOWN: 1.5,
    MarkovState.BREAKOUT_UP: None,    # 3.0~5.0 uniform
    MarkovState.BREAKOUT_DOWN: None,  # 3.0~5.0 uniform
}

# ── Event Impact (GDD Rule 3) ──

VOLATILITY_AMPLIFIER = {
    VolatilityProfile.LOW: 0.6,
    VolatilityProfile.MEDIUM: 1.0,
    VolatilityProfile.HIGH: 1.4,
    VolatilityProfile.EXTREME: 2.0,
}

VOL_PATTERN_SCALE = {
    VolatilityProfile.LOW: 0.6,
    VolatilityProfile.MEDIUM: 1.0,
    VolatilityProfile.HIGH: 1.3,
    VolatilityProfile.EXTREME: 1.8,
}

# ── Config ──

K_DRIFT = 0.001
THRESHOLD_SOFT = 0.20
THRESHOLD_HARD = 0.50
MAX_SINGLE_IMPACT = 0.25
TICKS_PER_DAY = 390
DAYS_PER_SEASON = 20

# ── Data Structures ──

@dataclass
class Event:
    event_type: str  # "INSTANT_SHOCK" or "GRADUAL_SHIFT"
    base_impact: float
    direction: int  # +1 or -1
    scope: str  # "MACRO", "SECTOR", "INDIVIDUAL"
    target_stock_ids: list
    decay_ticks: int = 0
    decay_curve: str = "LINEAR"  # "LINEAR" or "EXPONENTIAL"

@dataclass
class GradualEvent:
    """Tracks an in-progress GRADUAL_SHIFT event for a specific stock."""
    actual_impact: float
    remaining_ticks: int
    total_ticks: int
    decay_curve: str
    decay_rate: float = 0.0

    def get_tick_impact(self) -> float:
        if self.remaining_ticks <= 0:
            return 0.0
        elapsed = self.total_ticks - self.remaining_ticks
        if self.decay_curve == "LINEAR":
            return self.actual_impact / self.total_ticks
        else:  # EXPONENTIAL
            return self.actual_impact * (1 - self.decay_rate) ** elapsed * self.decay_rate

@dataclass
class StockConfig:
    stock_id: str
    name: str
    base_price: int
    volatility_profile: VolatilityProfile
    macro_sensitivity: float = 1.0
    sector_sensitivity: float = 1.0

@dataclass
class StockState:
    stock_id: str
    current_price: float
    base_price: int
    markov_state: MarkovState = MarkovState.SIDEWAYS
    state_duration: int = 0
    season_bias: SeasonBias = SeasonBias.NEUTRAL
    volatility_profile: VolatilityProfile = VolatilityProfile.MEDIUM
    macro_sensitivity: float = 1.0
    sector_sensitivity: float = 1.0
    gradual_events: list = field(default_factory=list)
    # History
    tick_prices: list = field(default_factory=list)
    tick_volumes: list = field(default_factory=list)
    state_history: list = field(default_factory=list)
    ohlcv_daily: list = field(default_factory=list)


# ── Core Engine ──

def get_adjusted_transition_matrix(vol_profile: VolatilityProfile,
                                    season_bias: SeasonBias) -> list:
    """Apply volatility scaling and season bias to base transition matrix."""
    scaling = VOLATILITY_SCALING[vol_profile]
    bias = SEASON_BIAS_DELTA[season_bias]
    matrix = []

    for i in range(7):
        row = list(TRANSITION_MATRIX_MEDIUM[i])

        # Step 1: Volatility profile scaling
        is_breakout = i in (5, 6)
        for j in range(7):
            if j == i:
                continue
            if j in (5, 6):  # transition TO breakout
                row[j] *= scaling["breakout_mult"]
            else:
                # Non-breakout, non-self: scale by self_mult (inverted logic)
                pass  # keep baseline for non-breakout transitions

        # Adjust self-transition to maintain row sum = 1
        # self_mult > 1 means MORE self-staying (LOW vol)
        # self_mult < 1 means LESS self-staying (HIGH/EXTREME vol)
        non_self_sum = sum(row[j] for j in range(7) if j != i and j not in (5, 6))
        breakout_sum = sum(row[j] for j in (5, 6) if j != i)
        row[i] = 1.0 - non_self_sum - breakout_sum

        # Step 2: Season bias
        up_states = {0, 1, 5}    # STRONG_UP, UPTREND, BREAKOUT_UP
        down_states = {3, 4, 6}  # DOWNTREND, STRONG_DOWN, BREAKOUT_DOWN

        for j in range(7):
            if j == i:
                continue
            if j in up_states:
                row[j] += bias["up_bonus"] / len(up_states)
            elif j in down_states:
                row[j] += bias["down_penalty"] / len(down_states)

        # Clamp negatives and renormalize
        row = [max(0.0, v) for v in row]
        total = sum(row)
        if total > 0:
            row = [v / total for v in row]

        matrix.append(row)

    return matrix


def drift_intensity(deviation_ratio: float) -> float:
    """Non-linear drift intensity (GDD Rule 2-2)."""
    r = abs(deviation_ratio)
    if r < THRESHOLD_SOFT:
        return 1.0
    elif r < THRESHOLD_HARD:
        return 1.0 + (r - THRESHOLD_SOFT) * 4.0
    else:
        return (1.0
                + (THRESHOLD_HARD - THRESHOLD_SOFT) * 4.0
                + (r - THRESHOLD_HARD) * 16.0)


def compute_pattern_delta(state: MarkovState,
                          vol_profile: VolatilityProfile) -> float:
    """Pattern layer: (bias + uniform magnitude + noise) * vol_pattern_scale."""
    bias, mag_min, mag_max, noise_std, _ = STATE_PARAMS[state]
    magnitude = random.uniform(mag_min, mag_max)
    noise = random.gauss(0, noise_std)
    raw = bias + magnitude + noise
    return raw * VOL_PATTERN_SCALE[vol_profile]


def compute_drift_delta(current_price: float, base_price: float) -> float:
    """Drift layer: mean reversion toward base_price."""
    deviation_ratio = (current_price - base_price) / base_price
    intensity = drift_intensity(deviation_ratio)
    return -K_DRIFT * deviation_ratio * intensity


def compute_event_delta(stock: StockState, tick_events: list) -> float:
    """Event layer: sum of all active event impacts this tick."""
    event_delta = 0.0
    forced_breakout = None

    # Process new instant shocks
    for evt in tick_events:
        if evt.event_type == "INSTANT_SHOCK":
            sensitivity = stock.macro_sensitivity if evt.scope == "MACRO" else (
                stock.sector_sensitivity if evt.scope == "SECTOR" else 1.0)
            vol_amp = VOLATILITY_AMPLIFIER[stock.volatility_profile]
            raw = evt.base_impact * evt.direction * sensitivity * vol_amp
            actual = max(-MAX_SINGLE_IMPACT, min(MAX_SINGLE_IMPACT, raw))
            event_delta += actual

            if abs(actual) >= 0.05:
                forced_breakout = MarkovState.BREAKOUT_UP if actual > 0 else MarkovState.BREAKOUT_DOWN

        elif evt.event_type == "GRADUAL_SHIFT":
            sensitivity = stock.macro_sensitivity if evt.scope == "MACRO" else (
                stock.sector_sensitivity if evt.scope == "SECTOR" else 1.0)
            vol_amp = VOLATILITY_AMPLIFIER[stock.volatility_profile]
            raw = evt.base_impact * evt.direction * sensitivity * vol_amp
            actual = max(-MAX_SINGLE_IMPACT, min(MAX_SINGLE_IMPACT, raw))

            if evt.decay_curve == "EXPONENTIAL":
                decay_rate = 1 - math.exp(math.log(0.01) / evt.decay_ticks) if evt.decay_ticks > 0 else 1.0
            else:
                decay_rate = 0.0

            ge = GradualEvent(
                actual_impact=actual,
                remaining_ticks=evt.decay_ticks,
                total_ticks=evt.decay_ticks,
                decay_curve=evt.decay_curve,
                decay_rate=decay_rate,
            )
            stock.gradual_events.append(ge)
            # First tick contribution
            event_delta += ge.get_tick_impact()
            ge.remaining_ticks -= 1

    # Process ongoing gradual events
    still_active = []
    for ge in stock.gradual_events:
        if ge.remaining_ticks > 0:
            event_delta += ge.get_tick_impact()
            ge.remaining_ticks -= 1
            if ge.remaining_ticks > 0:
                still_active.append(ge)
    stock.gradual_events = still_active

    return event_delta, forced_breakout


def compute_volume(stock: StockState, event_delta: float, tick_in_day: int) -> float:
    """Volume generation (GDD Rule 4)."""
    vol_min, vol_max = BASE_VOLUME_RANGE[stock.volatility_profile]
    base_vol = random.uniform(vol_min, vol_max)

    mult = STATE_VOLUME_MULT[stock.markov_state]
    if mult is None:  # BREAKOUT
        mult = random.uniform(3.0, 5.0)
    state_vol = base_vol * mult

    if abs(event_delta) > 0:
        spike_mult = max(1.0, min(10.0, abs(event_delta) * 30.0))
        event_spike = base_vol * spike_mult
    else:
        event_spike = 0.0

    # Time of day multiplier
    if tick_in_day < 10:
        tod_mult = 2.5
    elif tick_in_day >= 380:
        tod_mult = 2.0
    else:
        tod_mult = 1.0

    return (state_vol + event_spike) * tod_mult


def process_tick(stock: StockState, tick_in_day: int, tick_events: list,
                 transition_matrix: list):
    """Process one tick for one stock (GDD Rule 5)."""

    # Step 2: Pattern layer
    pattern_delta = compute_pattern_delta(stock.markov_state, stock.volatility_profile)

    # Step 3: Drift layer
    drift_delta = compute_drift_delta(stock.current_price, stock.base_price)

    # Step 4: Event layer
    event_delta, forced_breakout = compute_event_delta(stock, tick_events)

    # Step 5: Additive combination
    total_delta = pattern_delta + drift_delta + event_delta

    # Step 6: Price update
    raw_price = stock.current_price * (1 + total_delta)
    min_price = max(stock.base_price * 0.15, 1000)
    max_price = stock.base_price * 3.0
    clamped = max(min_price, min(max_price, raw_price))
    final_price = round(clamped / 100) * 100

    stock.current_price = final_price

    # Step 7: Markov state transition
    if forced_breakout is not None:
        stock.markov_state = forced_breakout
        stock.state_duration = 0
    else:
        _, _, _, _, min_dur = STATE_PARAMS[stock.markov_state]
        if stock.state_duration >= min_dur:
            roll = random.random()
            cumulative = 0.0
            for j in range(7):
                cumulative += transition_matrix[stock.markov_state][j]
                if roll <= cumulative:
                    new_state = MarkovState(j)
                    if new_state != stock.markov_state:
                        stock.markov_state = new_state
                        stock.state_duration = 0
                    else:
                        stock.state_duration += 1
                    break
        else:
            stock.state_duration += 1

    # Step 8: Volume
    volume = compute_volume(stock, event_delta, tick_in_day)

    # Step 9: Record
    stock.tick_prices.append(stock.current_price)
    stock.tick_volumes.append(volume)
    stock.state_history.append(stock.markov_state)


def summarize_day_ohlcv(stock: StockState, day_start_idx: int):
    """Create OHLCV summary for one trading day."""
    day_prices = stock.tick_prices[day_start_idx:day_start_idx + TICKS_PER_DAY]
    day_volumes = stock.tick_volumes[day_start_idx:day_start_idx + TICKS_PER_DAY]
    if not day_prices:
        return
    stock.ohlcv_daily.append({
        "open": day_prices[0],
        "high": max(day_prices),
        "low": min(day_prices),
        "close": day_prices[-1],
        "volume": sum(day_volumes),
    })


# ── Stock Definitions (from GDD / Stock DB) ──

STOCKS = [
    StockConfig("KSF", "코스모푸드", 65000, VolatilityProfile.MEDIUM, 0.8, 1.0),
    StockConfig("STC", "스타칩", 120000, VolatilityProfile.HIGH, 1.2, 1.5),
    StockConfig("KRB", "코리아뱅크", 52000, VolatilityProfile.LOW, 1.5, 0.5),
    StockConfig("NXE", "넥스트엔터", 42000, VolatilityProfile.HIGH, 0.6, 0.8),
    StockConfig("MDG", "메디진", 180000, VolatilityProfile.EXTREME, 1.0, 1.8),
    StockConfig("GRC", "그린케미", 38000, VolatilityProfile.MEDIUM, 1.0, 1.2),
    StockConfig("DHI", "대한중공업", 95000, VolatilityProfile.LOW, 1.3, 1.0),
    StockConfig("PLT", "피플텔레콤", 78000, VolatilityProfile.MEDIUM, 1.0, 1.0),
    StockConfig("SKL", "스카이로직", 210000, VolatilityProfile.HIGH, 0.9, 1.3),
    StockConfig("BPH", "블루팜", 320000, VolatilityProfile.EXTREME, 0.7, 2.0),
]

# ── Pre-defined Events for Testing ──

TEST_EVENTS = [
    # Day 3, tick 50: Macro bad news (rate hike)
    (3, 50, Event("INSTANT_SHOCK", 0.06, -1, "MACRO",
                  [s.stock_id for s in STOCKS])),
    # Day 7, tick 100: Sector good news (semiconductor boom) for SC, SK
    (7, 100, Event("INSTANT_SHOCK", 0.08, +1, "SECTOR",
                   ["STC", "SKL"])),
    # Day 10, tick 200: Individual mega event for MG (+15%)
    (10, 200, Event("INSTANT_SHOCK", 0.15, +1, "INDIVIDUAL", ["MDG"])),
    # Day 12, tick 0: Gradual sector decline for NE, MG (regulatory concern)
    (12, 0, Event("GRADUAL_SHIFT", 0.10, -1, "SECTOR", ["NXE", "MDG"],
                  decay_ticks=200, decay_curve="EXPONENTIAL")),
    # Day 16, tick 150: Macro good news (stimulus) - gradual
    (16, 150, Event("GRADUAL_SHIFT", 0.05, +1, "MACRO",
                    [s.stock_id for s in STOCKS], decay_ticks=300, decay_curve="LINEAR")),
]


def run_simulation(seed: int = 42) -> dict:
    """Run full season simulation for all 10 stocks."""
    random.seed(seed)

    # Initialize stock states
    states = {}
    transition_matrices = {}

    for cfg in STOCKS:
        # Random season bias assignment (BULL 40%, NEUTRAL 30%, BEAR 30%)
        r = random.random()
        if r < 0.4:
            bias = SeasonBias.BULL
        elif r < 0.7:
            bias = SeasonBias.NEUTRAL
        else:
            bias = SeasonBias.BEAR

        state = StockState(
            stock_id=cfg.stock_id,
            current_price=cfg.base_price,
            base_price=cfg.base_price,
            season_bias=bias,
            volatility_profile=cfg.volatility_profile,
            macro_sensitivity=cfg.macro_sensitivity,
            sector_sensitivity=cfg.sector_sensitivity,
        )
        states[cfg.stock_id] = state
        transition_matrices[cfg.stock_id] = get_adjusted_transition_matrix(
            cfg.volatility_profile, bias
        )

    # Build event schedule: {(day, tick_in_day): [events for that stock]}
    event_schedule = {}
    for day, tick, event in TEST_EVENTS:
        key = (day, tick)
        if key not in event_schedule:
            event_schedule[key] = []
        event_schedule[key].append(event)

    # Run simulation
    total_ticks = TICKS_PER_DAY * DAYS_PER_SEASON
    for day in range(DAYS_PER_SEASON):
        for tick in range(TICKS_PER_DAY):
            # Get events for this tick
            events_this_tick = event_schedule.get((day, tick), [])

            for stock_id, stock in states.items():
                # Filter events that apply to this stock
                stock_events = [
                    e for e in events_this_tick
                    if stock_id in e.target_stock_ids
                ]
                process_tick(
                    stock, tick, stock_events,
                    transition_matrices[stock_id]
                )

        # End of day OHLCV
        day_start = day * TICKS_PER_DAY
        for stock in states.values():
            summarize_day_ohlcv(stock, day_start)

    return states


def collect_metrics(states: dict) -> dict:
    """Collect metrics for the prototype report."""
    metrics = {}
    for stock_id, stock in states.items():
        cfg = next(s for s in STOCKS if s.stock_id == stock_id)
        prices = stock.tick_prices
        final = prices[-1]
        high = max(prices)
        low = min(prices)
        returns = [(prices[i] - prices[i-1]) / prices[i-1]
                   for i in range(1, len(prices)) if prices[i-1] > 0]

        # State distribution
        state_counts = {}
        for s in stock.state_history:
            name = STATE_NAMES[s]
            state_counts[name] = state_counts.get(name, 0) + 1

        # State transitions count
        transitions = sum(1 for i in range(1, len(stock.state_history))
                         if stock.state_history[i] != stock.state_history[i-1])

        # Daily returns from OHLCV
        daily_returns = []
        for i in range(1, len(stock.ohlcv_daily)):
            prev_close = stock.ohlcv_daily[i-1]["close"]
            curr_close = stock.ohlcv_daily[i]["close"]
            if prev_close > 0:
                daily_returns.append((curr_close - prev_close) / prev_close)

        # Max drawdown
        peak = prices[0]
        max_dd = 0
        for p in prices:
            if p > peak:
                peak = p
            dd = (peak - p) / peak if peak > 0 else 0
            if dd > max_dd:
                max_dd = dd

        metrics[stock_id] = {
            "name": cfg.name,
            "base_price": cfg.base_price,
            "volatility": cfg.volatility_profile.name,
            "season_bias": stock.season_bias.name,
            "final_price": final,
            "return_pct": round((final - cfg.base_price) / cfg.base_price * 100, 2),
            "high": high,
            "low": low,
            "price_range_pct": round((high - low) / cfg.base_price * 100, 2),
            "max_drawdown_pct": round(max_dd * 100, 2),
            "total_transitions": transitions,
            "state_distribution": {k: round(v / len(stock.state_history) * 100, 1)
                                   for k, v in sorted(state_counts.items())},
            "avg_daily_return_pct": round(sum(daily_returns) / len(daily_returns) * 100, 4) if daily_returns else 0,
            "daily_return_std_pct": round((sum((r - sum(daily_returns)/len(daily_returns))**2
                                              for r in daily_returns) / len(daily_returns))**0.5 * 100, 4) if daily_returns else 0,
        }

    return metrics


def check_acceptance_criteria(states: dict, metrics: dict) -> list:
    """Check acceptance criteria from GDD."""
    results = []

    # AC1: 10 stocks updated independently
    results.append(("10 stocks updated independently",
                    len(states) == 10,
                    f"{len(states)} stocks"))

    # AC2: Markov transitions follow matrix
    total_transitions = sum(m["total_transitions"] for m in metrics.values())
    results.append(("Markov transitions occurring",
                    total_transitions > 50,
                    f"{total_transitions} total transitions"))

    # AC3: Volatility profiles show different ranges
    low_range = [m["price_range_pct"] for m in metrics.values()
                 if m["volatility"] == "LOW"]
    high_range = [m["price_range_pct"] for m in metrics.values()
                  if m["volatility"] in ("HIGH", "EXTREME")]
    if low_range and high_range:
        avg_low = sum(low_range) / len(low_range)
        avg_high = sum(high_range) / len(high_range)
        results.append(("Volatility profiles show different ranges",
                        avg_high > avg_low * 1.3,
                        f"LOW avg={avg_low:.1f}%, HIGH/EXT avg={avg_high:.1f}%"))

    # AC4: Hard clamp respected
    clamp_ok = True
    for sid, stock in states.items():
        cfg = next(s for s in STOCKS if s.stock_id == sid)
        min_p = max(cfg.base_price * 0.15, 1000)
        max_p = cfg.base_price * 3.0
        for p in stock.tick_prices:
            if p < min_p - 100 or p > max_p + 100:  # 100원 반올림 여유
                clamp_ok = False
                break
    results.append(("Hard clamp respected", clamp_ok, "all prices within bounds"))

    # AC5: 100원 rounding
    rounding_ok = all(
        p % 100 == 0
        for stock in states.values()
        for p in stock.tick_prices
    )
    results.append(("100원 rounding applied", rounding_ok, "all prices multiple of 100"))

    # AC6: Event-free operation (check first 2 days have no events and still work)
    prices_day0 = list(states.values())[0].tick_prices[:TICKS_PER_DAY]
    has_movement = max(prices_day0) != min(prices_day0)
    results.append(("Pattern+drift alone produces movement",
                    has_movement,
                    f"Day 0 range: {min(prices_day0)}~{max(prices_day0)}"))

    return results


def generate_chart_data(states: dict) -> dict:
    """Generate chart data for visualization."""
    chart_data = {}
    for stock_id, stock in states.items():
        cfg = next(s for s in STOCKS if s.stock_id == stock_id)
        chart_data[stock_id] = {
            "name": cfg.name,
            "base_price": cfg.base_price,
            "volatility": cfg.volatility_profile.name,
            "season_bias": stock.season_bias.name,
            "tick_prices": stock.tick_prices,
            "ohlcv_daily": stock.ohlcv_daily,
            "state_history": [int(s) for s in stock.state_history],
        }
    return chart_data


if __name__ == "__main__":
    print("=" * 60)
    print("Price Engine Prototype — Season Simulation")
    print("=" * 60)
    print(f"Stocks: {len(STOCKS)}")
    print(f"Days: {DAYS_PER_SEASON}, Ticks/Day: {TICKS_PER_DAY}")
    print(f"Total ticks: {TICKS_PER_DAY * DAYS_PER_SEASON}")
    print(f"Events scheduled: {len(TEST_EVENTS)}")
    print()

    # Run simulation
    print("Running simulation...")
    states = run_simulation(seed=42)
    print("Simulation complete.")
    print()

    # Collect metrics
    metrics = collect_metrics(states)

    # Print per-stock summary
    print("=" * 60)
    print("Per-Stock Results")
    print("=" * 60)
    header = f"{'ID':>4} {'Name':<12} {'Vol':<8} {'Bias':<8} {'Base':>8} {'Final':>8} {'Ret%':>7} {'Range%':>7} {'MaxDD%':>7} {'Trans':>5}"
    print(header)
    print("-" * len(header))
    for sid in sorted(metrics.keys()):
        m = metrics[sid]
        print(f"{sid:>4} {m['name']:<12} {m['volatility']:<8} {m['season_bias']:<8} "
              f"{m['base_price']:>8,} {m['final_price']:>8,} {m['return_pct']:>7.1f} "
              f"{m['price_range_pct']:>7.1f} {m['max_drawdown_pct']:>7.1f} {m['total_transitions']:>5}")

    print()

    # State distribution
    print("=" * 60)
    print("State Distribution (%)")
    print("=" * 60)
    for sid in sorted(metrics.keys()):
        m = metrics[sid]
        dist = m["state_distribution"]
        dist_str = " | ".join(f"{k[:3]}:{v:.0f}" for k, v in dist.items())
        print(f"{sid}: {dist_str}")

    print()

    # Acceptance criteria
    print("=" * 60)
    print("Acceptance Criteria Check")
    print("=" * 60)
    criteria = check_acceptance_criteria(states, metrics)
    pass_count = 0
    for name, passed, detail in criteria:
        status = "PASS" if passed else "FAIL"
        if passed:
            pass_count += 1
        print(f"  [{status}] {name} — {detail}")
    print(f"\nResult: {pass_count}/{len(criteria)} passed")

    # Save chart data for visualization
    chart_data = generate_chart_data(states)
    with open("d:/Github/ta/prototypes/price-engine/chart_data.json", "w",
              encoding="utf-8") as f:
        json.dump(chart_data, f, ensure_ascii=False, indent=2)
    print("\nChart data saved to chart_data.json")

    # Save metrics
    with open("d:/Github/ta/prototypes/price-engine/metrics.json", "w",
              encoding="utf-8") as f:
        json.dump(metrics, f, ensure_ascii=False, indent=2)
    print("Metrics saved to metrics.json")

    # Run with different seeds to test consistency
    print()
    print("=" * 60)
    print("Multi-Seed Consistency Test (5 seeds)")
    print("=" * 60)
    seed_results = []
    for seed in [42, 123, 456, 789, 2026]:
        s = run_simulation(seed=seed)
        m = collect_metrics(s)

        avg_return = sum(v["return_pct"] for v in m.values()) / len(m)
        avg_range = sum(v["price_range_pct"] for v in m.values()) / len(m)
        avg_dd = sum(v["max_drawdown_pct"] for v in m.values()) / len(m)

        seed_results.append({
            "seed": seed,
            "avg_return": avg_return,
            "avg_range": avg_range,
            "avg_max_dd": avg_dd,
        })
        print(f"  Seed {seed:>4}: avg_return={avg_return:>+6.1f}% "
              f"avg_range={avg_range:>5.1f}% avg_maxDD={avg_dd:>5.1f}%")

    # Overall consistency check
    returns = [r["avg_return"] for r in seed_results]
    ranges = [r["avg_range"] for r in seed_results]
    print(f"\n  Return spread: {min(returns):>+.1f}% ~ {max(returns):>+.1f}%")
    print(f"  Range spread:  {min(ranges):>.1f}% ~ {max(ranges):>.1f}%")
