# Cairn Mock Data

`cairn-mock-data.json` is a complete Cairn backup file (schema version 3) that
can be imported directly via **Settings → Import Backup**. Importing will
**replace** all existing data, so back up your current data from Settings first.

## Contents

- **3 members**: Alice Chen / Bob Martin / Lily Tanaka
- **9 accounts** covering every `AccountKind`:
  - cash (USD / EUR / CNY / JPY)
  - stock (USD / HKD)
  - realEstate (CNY)
  - device (JPY)
- **13 holdings** across the currencies `USD / EUR / HKD / CNY / JPY`
- **6 months** of monthly snapshots per holding (2025-11 to 2026-04), totaling
  78 `Snapshot` records
- **6 `PortfolioSnapshot` records** (aggregated monthly, home currency = USD)
- **24 FX cache entries** covering EUR/HKD/CNY/JPY × 6 months
- **6 physical assets (`Asset`)**: real estate, vehicles, electronics, bicycles,
  watches, etc., covering all of `realEstate / vehicle / electronics / other`

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
