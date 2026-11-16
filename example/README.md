# Cairn Mock Data

`cairn-mock-data.json` is a complete Cairn backup file (backup format version 5) that
can be imported directly via **Settings → Import Backup**. Importing will
**replace** all existing data, so back up your current data from Settings first.

## Contents

- **3 members**: Alice Chen / Bob Wang / Lily Wang
- **7 accounts** across cash and stock (homes, cars and devices are
  possessions instead, so they are counted once)
- **10 holdings** across the currencies `USD / EUR / HKD / CNY / JPY`
- **12 months** of month-end snapshots per holding (2025-11 to 2026-10)
- **12 `PortfolioSnapshot` records** (home currency = USD)
- **4 FX cache entries** (EUR/HKD/CNY/JPY), one per pair at the latest month, as the app stores them
- **6 possessions** with photo cutouts or icons, including one sold item

## How to Import

1. Open Cairn → Settings → Backup & Restore
2. Choose "Import Backup"
3. Select `cairn-mock-data.json` from this directory
4. Confirm the replacement and wait for the import to finish

## Regenerating

After editing `generate_mock.py`, run:

```bash
python3 example/generate_mock.py
```

The script uses deterministic UUIDs (`uuid5`), so each run produces stable
output that diffs cleanly.
