# PROTOTYPE - NOT FOR PRODUCTION
# Question: Does the 3-layer price algorithm produce "readable but unpredictable" charts?
# Date: 2026-03-31

"""
Generates chart images from simulation data.
Requires: matplotlib, numpy (pip install matplotlib numpy)
"""

import json
import sys

try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    import matplotlib.pyplot as plt
    import matplotlib.gridspec as gridspec
    import numpy as np
except ImportError:
    print("matplotlib/numpy not found. Install with: pip install matplotlib numpy")
    sys.exit(1)


def load_data():
    with open("d:/Github/ta/prototypes/price-engine/chart_data.json", "r",
              encoding="utf-8") as f:
        return json.load(f)

with open("d:/Github/ta/prototypes/price-engine/metrics.json", "r",
          encoding="utf-8") as f:
    METRICS = json.load(f)


STATE_COLORS = {
    0: '#2ECC71',  # STRONG_UP - green
    1: '#82E0AA',  # UPTREND - light green
    2: '#BDC3C7',  # SIDEWAYS - gray
    3: '#F1948A',  # DOWNTREND - light red
    4: '#E74C3C',  # STRONG_DOWN - red
    5: '#F39C12',  # BREAKOUT_UP - orange
    6: '#8E44AD',  # BREAKOUT_DOWN - purple
}

STATE_NAMES = [
    'STRONG_UP', 'UPTREND', 'SIDEWAYS', 'DOWNTREND',
    'STRONG_DOWN', 'BREAKOUT_UP', 'BREAKOUT_DOWN'
]

TICKS_PER_DAY = 390


def plot_stock_detail(stock_id: str, data: dict, save_path: str):
    """Generate detailed chart for a single stock."""
    stock = data[stock_id]
    prices = stock["tick_prices"]
    states = stock["state_history"]
    ohlcv = stock["ohlcv_daily"]

    fig = plt.figure(figsize=(16, 10))
    gs = gridspec.GridSpec(3, 1, height_ratios=[3, 1, 1], hspace=0.3)

    # --- Panel 1: Price chart with state coloring ---
    ax1 = fig.add_subplot(gs[0])

    # Color background by state
    for i in range(len(prices) - 1):
        ax1.axvspan(i, i + 1, alpha=0.15, color=STATE_COLORS[states[i]],
                    linewidth=0)

    # Price line
    ax1.plot(prices, color='#2C3E50', linewidth=0.5, alpha=0.9)

    # Base price reference
    ax1.axhline(y=stock["base_price"], color='#E67E22', linestyle='--',
                alpha=0.5, label=f'Base: {stock["base_price"]:,}')

    # Day boundaries
    for d in range(1, 20):
        ax1.axvline(x=d * TICKS_PER_DAY, color='#BDC3C7', linestyle=':',
                    alpha=0.3)

    m = METRICS[stock_id]
    ax1.set_title(
        f'{stock["name"]} ({stock_id}) — {stock["volatility"]} / {stock["season_bias"]}\n'
        f'Return: {m["return_pct"]:+.1f}% | Range: {m["price_range_pct"]:.1f}% | '
        f'MaxDD: {m["max_drawdown_pct"]:.1f}% | Transitions: {m["total_transitions"]}',
        fontsize=12, fontweight='bold'
    )
    ax1.set_ylabel('Price (KRW)')
    ax1.legend(loc='upper left')
    ax1.grid(True, alpha=0.2)

    # --- Panel 2: State timeline ---
    ax2 = fig.add_subplot(gs[1])
    state_arr = np.array(states)
    for s_val in range(7):
        mask = state_arr == s_val
        if mask.any():
            ax2.fill_between(range(len(states)), 0, 1, where=mask,
                            color=STATE_COLORS[s_val], alpha=0.7,
                            label=STATE_NAMES[s_val])
    ax2.set_ylabel('State')
    ax2.set_yticks([])
    ax2.legend(loc='upper right', ncol=7, fontsize=6)

    # --- Panel 3: Daily OHLCV bars ---
    ax3 = fig.add_subplot(gs[2])
    if ohlcv:
        days = range(len(ohlcv))
        closes = [d["close"] for d in ohlcv]
        opens = [d["open"] for d in ohlcv]
        colors = ['#2ECC71' if c >= o else '#E74C3C'
                  for c, o in zip(closes, opens)]
        volumes = [d["volume"] for d in ohlcv]
        ax3.bar(days, volumes, color=colors, alpha=0.7)
        ax3.set_ylabel('Volume')
        ax3.set_xlabel('Trading Day')

    plt.savefig(save_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {save_path}")


def plot_overview(data: dict, save_path: str):
    """Generate overview chart comparing all 10 stocks."""
    fig, axes = plt.subplots(5, 2, figsize=(20, 20))
    fig.suptitle('Price Engine Prototype — All 10 Stocks (1 Season = 20 Days)',
                 fontsize=16, fontweight='bold')

    stock_ids = sorted(data.keys())
    for idx, stock_id in enumerate(stock_ids):
        ax = axes[idx // 2][idx % 2]
        stock = data[stock_id]
        prices = stock["tick_prices"]
        base = stock["base_price"]
        m = METRICS[stock_id]

        # Normalize to percentage change from base
        pct_changes = [(p - base) / base * 100 for p in prices]

        ax.plot(pct_changes, linewidth=0.5, color='#2C3E50')
        ax.axhline(y=0, color='#E67E22', linestyle='--', alpha=0.5)
        ax.fill_between(range(len(pct_changes)), pct_changes, 0,
                        where=[p >= 0 for p in pct_changes],
                        color='#2ECC71', alpha=0.2)
        ax.fill_between(range(len(pct_changes)), pct_changes, 0,
                        where=[p < 0 for p in pct_changes],
                        color='#E74C3C', alpha=0.2)

        ax.set_title(
            f'{stock["name"]} ({stock_id}) — {stock["volatility"]} / {stock["season_bias"]} '
            f'| Ret: {m["return_pct"]:+.1f}%',
            fontsize=9
        )
        ax.set_ylabel('% from Base')
        ax.grid(True, alpha=0.2)

        # Day boundaries
        for d in range(1, 20):
            ax.axvline(x=d * TICKS_PER_DAY, color='#BDC3C7', linestyle=':',
                       alpha=0.2)

    plt.tight_layout()
    plt.savefig(save_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {save_path}")


def plot_drift_test(save_path: str):
    """Visualize drift layer effectiveness across deviation ratios."""
    from price_engine_prototype import drift_intensity, K_DRIFT

    ratios = np.linspace(-1.0, 1.0, 500)
    intensities = [drift_intensity(r) for r in ratios]
    drift_forces = [-K_DRIFT * r * drift_intensity(r) for r in ratios]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
    fig.suptitle('Drift Layer Analysis', fontsize=14, fontweight='bold')

    ax1.plot(ratios * 100, intensities, color='#2C3E50', linewidth=2)
    ax1.axvline(x=30, color='#F39C12', linestyle='--', label='Soft threshold (30%)')
    ax1.axvline(x=-30, color='#F39C12', linestyle='--')
    ax1.axvline(x=60, color='#E74C3C', linestyle='--', label='Hard threshold (60%)')
    ax1.axvline(x=-60, color='#E74C3C', linestyle='--')
    ax1.set_xlabel('Deviation from Base Price (%)')
    ax1.set_ylabel('Drift Intensity Multiplier')
    ax1.set_title('Non-linear Drift Intensity')
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    ax2.plot(ratios * 100, [f * 10000 for f in drift_forces],
             color='#2C3E50', linewidth=2)
    ax2.axhline(y=0, color='#BDC3C7', linestyle='-')
    ax2.set_xlabel('Deviation from Base Price (%)')
    ax2.set_ylabel('Drift Force (bps per tick)')
    ax2.set_title('Drift Force vs Deviation')
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(save_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {save_path}")


if __name__ == "__main__":
    data = load_data()

    print("Generating charts...")

    # Overview
    plot_overview(data, "d:/Github/ta/prototypes/price-engine/overview.png")

    # Drift analysis
    plot_drift_test("d:/Github/ta/prototypes/price-engine/drift_analysis.png")

    # Individual stock details (pick representative ones)
    for sid in ["KF", "SC", "MG", "KB"]:
        plot_stock_detail(
            sid, data,
            f"d:/Github/ta/prototypes/price-engine/detail_{sid}.png"
        )

    print("\nAll charts generated.")
