# QA Test Fixtures

Save file fixtures for efficient QA testing without grinding through early gameplay.

## superaccount.json

Pre-built save state with all features unlocked and substantial capital.

### Contents

- **Cash Balance**: 500M KRW (500,000,000) total assets
  - sim_cash: 100M (trading account)
  - cash_assets: 100M (personal funds)
- **All Skills Unlocked**: A1-A4 (Analysis), S1-S3 (Sense), TR1-TR4 (Trading), P1-P3 (Portfolio)
- **Season State**: Season 5, Day 1, Week 1 (fresh market close)
- **Tier**: Platinum (tier 3) — entry capital ≥30M
- **Holdings**: Empty (fresh start for testing order placement)
- **XP**: Level 20, 99 available skill points (no re-grinding)

### How to Use

#### Option 1: Command Line (Recommended for Automation)

```bash
# Copy fixture to save slot 0 (first slot)
cp tests/fixtures/superaccount.json ~/.var/app/Godot/data/Seed\ Money/save_slot_0.json

# For Windows
copy tests\fixtures\superaccount.json "%APPDATA%\Godot\app_userdata\Seed Money\save_slot_0.json"
```

#### Option 2: Manual Steps (for Manual QA)

1. **Locate Save Directory**:
   - Windows: `%APPDATA%\Godot\app_userdata\Seed Money\`
   - Linux: `~/.var/app/com.godotengine.Godot/data/Godot/app_userdata/Seed Money/`
   - macOS: `~/Library/Application Support/Godot/app_userdata/Seed Money/`

2. **Copy Fixture**:
   ```
   tests/fixtures/superaccount.json → [Save Dir]/save_slot_0.json
   ```

3. **Launch Game** → Main Screen → Load Slot 1 (ID 0)

### Save File Format (SAVE_VERSION: 4)

The fixture contains all required save sections:

| Section | Purpose | State |
|---------|---------|-------|
| `xp` | Player level and skill points | Level 20, 99 points available |
| `skill_tree` | Unlocked skills | All 14 skills unlocked |
| `season` | Tier, season number, free-market flag | Platinum, Season 5, competitive |
| `currency` | sim_cash, cash_assets, reserved_cash | 100M each + 0 reserved |
| `portfolio` | Holdings, transaction history | Empty (for clean order testing) |
| `clock` | Day/week/tick, season_active flag | Day 1, Week 1, Tick 0 |
| `prices` | Stock price snapshots (per-tick state) | Empty (will initialize at load) |
| `ai` | AI competitor state | Empty (will initialize at load) |
| `news` | News event buffer | Empty (will initialize at load) |
| `stop_take` | Stop-loss/take-profit orders | Empty (no active orders) |
| `lifestyle` | Lifestyle state (housing, jobs, status) | Empty (defaults) |
| `short_positions` | TR3 short positions | Empty |
| `borrow_pool` | TR3 borrowed stock ledger | Empty |
| `leverage_positions` | TR4 leveraged positions | Empty |
| `ohlcv_history` | OHLCV price history (S9-07) | Empty (will build during season) |
| `etf` | ETF prices and flows (P3 feature) | Empty |
| `financial_report` | Quarterly earnings schedule (S10-05) | Empty |

### Customizing Fixtures

To create a variant (e.g., testing short selling):

1. **Edit locally** (values are JSON-validated at save load):
   ```json
   {
     "short_positions": [
       {
         "stock_id": "SKL",
         "quantity": 100,
         "entry_price": 210000,
         "borrowed_amount": 21000000
       }
     ]
   }
   ```

2. **Validate**: Try loading in-game — SaveSystem logs any version mismatches
   ```
   EC-04: save_version mismatch — only known fields loaded
   ```

3. **Save as new fixture**: After editing in-game, export to a new .json:
   ```bash
   cp ~/.var/app/Godot/data/Seed\ Money/save_slot_1.json tests/fixtures/superaccount_with_shorts.json
   ```

### Load Flow (SaveSystem.load_slot)

When you load a fixture:

1. **SaveSystem** reads `save_slot_N.json`
2. **Core systems** restore in order:
   - XpSystem.load_save_data()
   - SkillTree.load_save_data() — validates prerequisite chains
   - SeasonManager.load_save_data()
   - CurrencySystem.load_save_data()
   - PortfolioManager.load_save_data()
   - LifestyleManager.load_save_data()
3. **Clock** restores and determines if season is active
4. **In-season systems** initialize (only if season_active=true):
   - PriceEngine.initialize_for_load() — seeds RNG, sets base prices
   - AiCompetitor.load_save_data()
   - NewsEventSystem.load_save_data()
   - StopTakeSystem.load_save_data()
   - ShortSellingSystem.load_save_data()
   - LeverageManager.load_save_data()
   - OhlcvHistory.load_save_data()
   - EtfManager.load_save_data()
   - FinancialReportSystem.load_save_data()

**Note**: If a section is empty `{}` or `[]`, the system initializes with defaults.

### Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Slot loads as empty/blank | Wrong save directory | Verify `%APPDATA%/Godot/app_userdata/Seed Money/` path |
| "Slot is corrupted" | JSON syntax error | Validate JSON with `jq tests/fixtures/superaccount.json` |
| Skills don't appear unlocked | Version mismatch (EC-04) | Check `save_version: 4` field matches build |
| Cash shows 0 | clock.season_active=false | Ensure `"season_active": true` in both sections |
| Markets won't open | current_day or current_week out of range | Ensure `0 ≤ current_day < 20` and `0 ≤ current_week < 4` |

### Related Documentation

- **Game Design**: `design/gdd/save-load.md` — save system spec and tier thresholds
- **Season System**: `design/gdd/season-manager.md` — tier requirements and reset logic
- **XP/Skills**: `design/gdd/skill-tree.md` — skill prerequisites and unlock order
- **Save Code**: `src/core/save_system.gd` — load/save implementation
- **Version History**: Check `production/sprints/sprint-10.md` for fixture creation history

### Test Cases Using This Fixture

- **TD-QA-02**: Order placement (all order types)
- **TD-QA-03**: Position management (open/close trades)
- **TD-QA-04**: Stop-loss and take-profit triggers
- **TD-QA-05**: Short selling mechanics (TR3)
- **TD-QA-06**: Leverage trading (TR4)
- **TD-QA-07**: Portfolio ETF trading (P3)
- **TD-QA-08**: Season settlement and tier transitions
- **TD-QA-09**: News events and reaction timing
