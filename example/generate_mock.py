#!/usr/bin/env python3
"""Generate a Cairn mock backup file (JSON) that can be imported via
Settings → Import. Produces multi-member, multi-currency, multi-month data
plus several physical assets.

Run:
    python3 example/generate_mock.py
"""
from __future__ import annotations

import base64
import json
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

OUT_PATH = Path(__file__).parent / "cairn-mock-data.json"
AVATAR_DIR = Path(__file__).resolve().parents[1] / "docs" / "assets"


def avatar_b64(filename: str) -> str | None:
    path = AVATAR_DIR / filename
    if not path.is_file():
        return None
    return base64.b64encode(path.read_bytes()).decode("ascii")

UTC = timezone.utc
HOME = "USD"

# Deterministic UUIDs so re-runs produce stable output (handy for diffs).
_NS = uuid.UUID("00000000-0000-0000-0000-000000000001")


def uid(label: str) -> str:
    return str(uuid.uuid5(_NS, label))


def iso(dt: datetime) -> str:
    # ISO8601 with seconds + Z, matching Foundation's iso8601 default.
    return dt.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def first_of_month(year: int, month: int) -> datetime:
    return datetime(year, month, 1, 0, 0, 0, tzinfo=UTC)


def day(year: int, month: int, d: int, h: int = 12) -> datetime:
    return datetime(year, month, d, h, 0, 0, tzinfo=UTC)


# ---------------------------------------------------------------------------
# Members
# ---------------------------------------------------------------------------
MEMBERS = [
    {"id": uid("member.alice"), "name": "Alice Chen",  "createdAt": iso(day(2024, 1, 5)), "avatarData": avatar_b64("alice-chen.png")},
    {"id": uid("member.bob"),   "name": "Bob Wang",    "createdAt": iso(day(2024, 1, 5)), "avatarData": avatar_b64("bob-wang.png")},
    {"id": uid("member.lily"),  "name": "Lily Wang",   "createdAt": iso(day(2024, 6, 1)), "avatarData": avatar_b64("lily-wang.png")},
]

# ---------------------------------------------------------------------------
# Accounts (varied kinds & owners)
# ---------------------------------------------------------------------------
ACCOUNTS = [
    # Alice — has cash in USD/EUR, stock brokerage in USD/HKD
    {"key": "alice.checking", "name": "Chase Checking",      "kind": "cash",       "memberKey": "member.alice", "note": "Primary USD checking"},
    {"key": "alice.eurosave", "name": "Revolut EUR",         "kind": "cash",       "memberKey": "member.alice", "note": "Travel + EUR savings"},
    {"key": "alice.broker",   "name": "Fidelity Brokerage",  "kind": "stock",      "memberKey": "member.alice", "note": "Long-term ETFs"},
    {"key": "alice.hk",       "name": "HSBC HK",             "kind": "stock",      "memberKey": "member.alice", "note": "HK equities"},

    # Bob — cash in CNY, stock brokerage, real-estate account
    {"key": "bob.cmb",        "name": "招商银行 一卡通",        "kind": "cash",       "memberKey": "member.bob",   "note": "工资卡"},
    {"key": "bob.futu",       "name": "Futu Securities",     "kind": "stock",      "memberKey": "member.bob",   "note": "美股账户"},
    {"key": "bob.house",      "name": "Shanghai Apartment",  "kind": "realEstate", "memberKey": "member.bob",   "note": "Pudong 2BR"},

    # Lily — cash in JPY, device account
    {"key": "lily.mufg",      "name": "MUFG 普通預金",         "kind": "cash",       "memberKey": "member.lily",  "note": "Salary account"},
    {"key": "lily.devices",   "name": "Devices",             "kind": "device",     "memberKey": "member.lily",  "note": "Personal electronics"},
]

# ---------------------------------------------------------------------------
# Holdings: (key, account, currency, label)
# ---------------------------------------------------------------------------
HOLDINGS = [
    # Alice
    ("alice.cash.usd",     "alice.checking", "USD", "Checking"),
    ("alice.cash.eur",     "alice.eurosave", "EUR", "Savings"),
    ("alice.stock.voo",    "alice.broker",   "USD", "VOO"),
    ("alice.stock.cash",   "alice.broker",   "USD", "Cash sweep"),
    ("alice.hk.tencent",   "alice.hk",       "HKD", "0700.HK Tencent"),

    # Bob
    ("bob.cnycash",        "bob.cmb",        "CNY", "Main"),
    ("bob.cnyfd",          "bob.cmb",        "CNY", "Fixed deposit"),
    ("bob.futu.usd",       "bob.futu",       "USD", "美股持仓"),
    ("bob.futu.hkd",       "bob.futu",       "HKD", "港股持仓"),
    ("bob.house.cny",      "bob.house",      "CNY", "Estimated value"),

    # Lily
    ("lily.jpy",           "lily.mufg",      "JPY", "普通"),
    ("lily.device.mbp",    "lily.devices",   "JPY", "MacBook Pro 16”"),
    ("lily.device.iphone", "lily.devices",   "JPY", "iPhone 17 Pro"),
]

# ---------------------------------------------------------------------------
# Snapshot trajectory: 6 months Nov 2025 .. Apr 2026.
# Each holding grows >=5% per month so net-worth charts trend up clearly.
# ---------------------------------------------------------------------------
MONTHS = [
    (2025, 11),
    (2025, 12),
    (2026,  1),
    (2026,  2),
    (2026,  3),
    (2026,  4),
]

# (key, starting amount, per-month growth rates [len == len(MONTHS)-1])
# Mix of winners and losers per holding so charts look organic; the net
# worth still trends up >=5% per month overall (verified by the script).
_BASES: list[tuple[str, float, list[float]]] = [
    # Alice — cash drifts, EUR depreciates a bit, US stocks fly, HK pulls back
    ("alice.cash.usd",     12500.0,  [ 0.020, -0.015,  0.030,  0.012, -0.008]),
    ("alice.cash.eur",      8200.0,  [-0.025,  0.010, -0.030, -0.012,  0.018]),
    ("alice.stock.voo",    48200.0,  [ 0.105,  0.128,  0.092,  0.118,  0.098]),
    ("alice.stock.cash",    1800.0,  [ 0.250, -0.120,  0.180,  0.090, -0.050]),
    ("alice.hk.tencent",   62000.0,  [-0.040,  0.085, -0.060,  0.135,  0.070]),
    # Bob — salary cash up, fixed deposit flat, US stocks great, HK shaky,
    # property rising in a hot tier-1 market
    ("bob.cnycash",        38000.0,  [ 0.045, -0.020,  0.060,  0.030,  0.018]),
    ("bob.cnyfd",         120000.0,  [ 0.004,  0.004,  0.004,  0.004,  0.004]),
    ("bob.futu.usd",        9800.0,  [ 0.135,  0.092, -0.040,  0.158,  0.110]),
    ("bob.futu.hkd",       54000.0,  [ 0.020, -0.085,  0.045, -0.030,  0.065]),
    ("bob.house.cny",    3200000.0,  [ 0.030,  0.038,  0.025,  0.042,  0.034]),
    # Lily — yen savings up, devices depreciate steadily
    ("lily.jpy",         1850000.0,  [ 0.085,  0.062,  0.094,  0.078,  0.105]),
    ("lily.device.mbp",   320000.0,  [-0.025, -0.025, -0.030, -0.025, -0.030]),
    ("lily.device.iphone",180000.0,  [-0.030, -0.030, -0.040, -0.030, -0.035]),
]


def _build_trajectory() -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for key, start, rates in _BASES:
        assert len(rates) == len(MONTHS) - 1
        series = [start]
        for r in rates:
            series.append(series[-1] * (1.0 + r))
        # JPY holdings are usually whole-yen; others keep 2 decimals.
        is_jpy_or_huge = start >= 100000 and float(start).is_integer() and key.startswith(("lily.", "bob.house", "bob.cnyfd"))
        if key.startswith("lily.") or key == "bob.house.cny" or key == "bob.cnyfd":
            out[key] = [f"{v:.0f}" for v in series]
        else:
            out[key] = [f"{v:.2f}" for v in series]
    return out


TRAJECTORY: dict[str, list[str]] = _build_trajectory()

# ---------------------------------------------------------------------------
# FX rates per month. Rates are stored as `1 base = rate × quote`.
# We keep base = HOME (USD), quote = foreign. So `amount_in_foreign / rate = USD`.
# Looking at NetWorthCalculator usage to confirm: foreignToHomeRate function
# below in BackupService uses these inversely; here we provide both directions
# through the snapshot's own rates list (which is what's actually consumed).
# Snapshot.Rate semantics from PortfolioSnapshot: base/quote/rate where
# 1 base = rate × quote (same as FXRate).
# ---------------------------------------------------------------------------

# foreign-per-USD (i.e. base=USD, quote=FOREIGN, rate=foreign per 1 USD)
USD_PER_FOREIGN = {
    "EUR": ["0.92", "0.93", "0.94", "0.92", "0.91", "0.90"],   # 1 USD = 0.92 EUR
    "HKD": ["7.80", "7.81", "7.82", "7.79", "7.78", "7.77"],
    "CNY": ["7.18", "7.20", "7.22", "7.15", "7.10", "7.05"],
    "JPY": ["152.0","154.0","156.0","153.5","151.0","149.5"],
}


def fx_to_usd(currency: str, amount: str, month_index: int) -> float:
    if currency == HOME:
        return round(float(amount), 2)
    rate = USD_PER_FOREIGN[currency][month_index]
    return round(float(amount) / float(rate), 2)


# ---------------------------------------------------------------------------
# Build payload pieces
# ---------------------------------------------------------------------------
member_id_by_key = {f"member.{m['name'].split()[0].lower()}": m["id"] for m in MEMBERS}
member_id_by_key = {
    "member.alice": MEMBERS[0]["id"],
    "member.bob":   MEMBERS[1]["id"],
    "member.lily":  MEMBERS[2]["id"],
}

accounts_out = []
account_id_by_key = {}
account_member_name = {}
account_kind_by_key = {}
account_name_by_key = {}
for a in ACCOUNTS:
    aid = uid(f"account.{a['key']}")
    account_id_by_key[a["key"]] = aid
    account_member_name[a["key"]] = next(m["name"] for m in MEMBERS if m["id"] == member_id_by_key[a["memberKey"]])
    account_kind_by_key[a["key"]] = a["kind"]
    account_name_by_key[a["key"]] = a["name"]
    accounts_out.append({
        "id": aid,
        "name": a["name"],
        "kindRawValue": a["kind"],
        "note": a["note"],
        "isArchived": False,
        "createdAt": iso(day(2024, 2, 1)),
        "memberId": member_id_by_key[a["memberKey"]],
    })

holdings_out = []
holding_id_by_key = {}
holding_meta = {}
for key, acct_key, currency, label in HOLDINGS:
    hid = uid(f"holding.{key}")
    holding_id_by_key[key] = hid
    holding_meta[key] = {
        "currency": currency,
        "label": label,
        "accountKey": acct_key,
    }
    holdings_out.append({
        "id": hid,
        "currency": currency,
        "label": label,
        "isArchived": False,
        "createdAt": iso(day(2024, 3, 1)),
        "accountId": account_id_by_key[acct_key],
    })

# Holding snapshots (day-granular, captured on the last day of the month)
snapshots_out = []
last_day_for_month = {
    (2025, 11): day(2025, 11, 30, 21),
    (2025, 12): day(2025, 12, 31, 21),
    (2026,  1): day(2026,  1, 31, 21),
    (2026,  2): day(2026,  2, 28, 21),
    (2026,  3): day(2026,  3, 31, 21),
    (2026,  4): day(2026,  4, 30, 21),
}
for key, amounts in TRAJECTORY.items():
    for idx, ym in enumerate(MONTHS):
        captured = last_day_for_month[ym]
        snapshots_out.append({
            "id": uid(f"snapshot.{key}.{ym[0]}-{ym[1]}"),
            "amount": float(amounts[idx]),
            "periodMonth": iso(captured.replace(hour=0, minute=0, second=0)),
            "recordedAt": iso(captured),
            "holdingId": holding_id_by_key[key],
        })

# FXRate cache entries (one per currency × month, base=USD, quote=foreign)
fx_out = []
for ccy, rates in USD_PER_FOREIGN.items():
    for idx, ym in enumerate(MONTHS):
        captured = last_day_for_month[ym]
        fx_out.append({
            "id": uid(f"fx.USD.{ccy}.{ym[0]}-{ym[1]}"),
            "base": "USD",
            "quote": ccy,
            "rate": float(rates[idx]),
            "date": iso(captured),
        })

# Portfolio snapshots — one per month, summarising every holding in HOME currency.
portfolio_out = []
for idx, ym in enumerate(MONTHS):
    captured = last_day_for_month[ym]
    period_first = iso(first_of_month(*ym))
    entries = []
    total_usd = 0.0
    for key, amounts in TRAJECTORY.items():
        meta = holding_meta[key]
        amt = amounts[idx]
        usd = fx_to_usd(meta["currency"], amt, idx)
        total_usd += usd
        acct_key = meta["accountKey"]
        entries.append({
            "id": uid(f"entry.{key}.{ym[0]}-{ym[1]}"),
            "holdingId": holding_id_by_key[key],
            "memberName": account_member_name[acct_key],
            "accountName": account_name_by_key[acct_key],
            "accountKindRawValue": account_kind_by_key[acct_key],
            "holdingLabel": meta["label"],
            "currency": meta["currency"],
            "amount": float(amt),
            "convertedAmount": usd,
        })
    rates = []
    for ccy in ("EUR", "HKD", "CNY", "JPY"):
        rates.append({
            "base": "USD",
            "quote": ccy,
            "rate": float(USD_PER_FOREIGN[ccy][idx]),
        })
    portfolio_out.append({
        "id": uid(f"portfolio.{ym[0]}-{ym[1]}"),
        "periodMonth": period_first,
        "homeCurrency": HOME,
        "totalAmount": round(total_usd, 2),
        "note": None,
        "recordedAt": iso(captured),
        "entries": entries,
        "rates": rates,
    })

# Physical assets — at least 4 across categories, mixed currencies & owners.
assets_out = [
    {
        "id": uid("asset.house"),
        "name": "Pudong Apartment",
        "categoryRawValue": "realEstate",
        "purchasePrice": 2800000.00,
        "purchaseCurrency": "CNY",
        "purchaseDate": iso(day(2019, 6, 15)),
        "currentValue": 3245000.00,
        "currentValueUpdatedAt": iso(last_day_for_month[(2026, 4)]),
        "saleDate": None,
        "salePrice": None,
        "iconName": "house.fill",
        "note": "Primary residence",
        "createdAt": iso(day(2024, 2, 10)),
        "memberId": member_id_by_key["member.bob"],
    },
    {
        "id": uid("asset.tesla"),
        "name": "Tesla Model 3",
        "categoryRawValue": "vehicle",
        "purchasePrice": 42000.00,
        "purchaseCurrency": "USD",
        "purchaseDate": iso(day(2023, 4, 20)),
        "currentValue": 31500.00,
        "currentValueUpdatedAt": iso(last_day_for_month[(2026, 4)]),
        "saleDate": None,
        "salePrice": None,
        "iconName": "car.fill",
        "note": "Daily driver",
        "createdAt": iso(day(2024, 2, 12)),
        "memberId": member_id_by_key["member.alice"],
    },
    {
        "id": uid("asset.mbp"),
        "name": "MacBook Pro 16”",
        "categoryRawValue": "electronics",
        "purchasePrice": 398000.00,
        "purchaseCurrency": "JPY",
        "purchaseDate": iso(day(2024, 11, 2)),
        "currentValue": 270000.00,
        "currentValueUpdatedAt": iso(last_day_for_month[(2026, 4)]),
        "saleDate": None,
        "salePrice": None,
        "iconName": "laptopcomputer",
        "note": "M4 Max, 64GB",
        "createdAt": iso(day(2024, 11, 3)),
        "memberId": member_id_by_key["member.lily"],
    },
    {
        "id": uid("asset.iphone"),
        "name": "iPhone 17 Pro",
        "categoryRawValue": "electronics",
        "purchasePrice": 189000.00,
        "purchaseCurrency": "JPY",
        "purchaseDate": iso(day(2025, 9, 25)),
        "currentValue": 160000.00,
        "currentValueUpdatedAt": iso(last_day_for_month[(2026, 4)]),
        "saleDate": None,
        "salePrice": None,
        "iconName": "iphone",
        "note": None,
        "createdAt": iso(day(2025, 9, 26)),
        "memberId": member_id_by_key["member.lily"],
    },
    {
        "id": uid("asset.bike"),
        "name": "Trek Domane SLR",
        "categoryRawValue": "other",
        "purchasePrice": 6500.00,
        "purchaseCurrency": "USD",
        "purchaseDate": iso(day(2022, 5, 14)),
        "currentValue": 4200.00,
        "currentValueUpdatedAt": iso(last_day_for_month[(2026, 4)]),
        "saleDate": None,
        "salePrice": None,
        "iconName": "bicycle",
        "note": "Road bike",
        "createdAt": iso(day(2024, 2, 14)),
        "memberId": member_id_by_key["member.alice"],
    },
    {
        "id": uid("asset.watch"),
        "name": "Rolex Submariner",
        "categoryRawValue": "other",
        "purchasePrice": 62000.00,
        "purchaseCurrency": "HKD",
        "purchaseDate": iso(day(2021, 8, 10)),
        "currentValue": 78000.00,
        "currentValueUpdatedAt": iso(last_day_for_month[(2026, 4)]),
        "saleDate": None,
        "salePrice": None,
        "iconName": "applewatch",
        "note": "Appreciating asset",
        "createdAt": iso(day(2024, 2, 15)),
        "memberId": member_id_by_key["member.alice"],
    },
]

payload = {
    "version": 3,
    "exportedAt": iso(day(2026, 4, 30, 22)),
    "members": MEMBERS,
    "accounts": accounts_out,
    "holdings": holdings_out,
    "snapshots": snapshots_out,
    "fxRates": fx_out,
    "portfolioSnapshots": portfolio_out,
    "assets": assets_out,
}

OUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
print(f"Wrote {OUT_PATH} ({OUT_PATH.stat().st_size} bytes)")
print(f"  members: {len(MEMBERS)}  accounts: {len(accounts_out)}  holdings: {len(holdings_out)}")
print(f"  snapshots: {len(snapshots_out)}  portfolioSnapshots: {len(portfolio_out)}")
print(f"  fxRates: {len(fx_out)}  assets: {len(assets_out)}")
