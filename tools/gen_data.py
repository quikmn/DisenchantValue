"""Generate Data/*.lua (disenchant odds, materials, names, lesser->greater essences) from classic-db.

    python tools/gen_data.py [classicdb.sqlite]

Source: classic-db, the CMaNGOS community's Classic 1.12 world database, https://github.com/cmangos/classic-db
Licence: GNU General Public License v3.0 (same as this addon). Version used: db_version
'Classic DB version 1.12.1 "Melting Pot v2". For Classic core z2815.' (printed into each generated file).
The SQLite file is classic-db imported without MySQL by EverlookDB's tools/classicdb/import.py
(default path below); only two tables are read: disenchant_loot_template and item_template.

How the odds are built (the CMaNGOS loot rules):
- Each item's DisenchantID picks a loot table; its item level range is the lowest..highest item level of the
  items that use it, per quality, made contiguous (a gap between two tables goes to the higher one); the first
  table of each kind reaches down to item level 5, the lowest classic-db disenchants.
- Rows in group 1 are one roll: a row with a chance gets it, the rows with chance 0 share what is left equally.
  Rows in group 0 roll on their own. The count is uniform between mincount and maxcount, so a 1-2 row becomes
  two lines (1x and 2x) with half the chance each, which is the layout the addon reads.
- classic-db gives weapons, shields and held-in-off-hand items the essence-heavy uncommon tables (21-31) and
  other armor the dust-heavy ones (1-11). The addon keeps them under class 2 (weapon table) and 4 (armor table)
  and looks shields and off-hand items up in the class 2 table.
Item IDs and names of the materials are game facts; the names here are only fallbacks before the client has
the item cached.
"""
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = sys.argv[1] if len(sys.argv) > 1 else r"D:\Dev\Quarry\state\classicdb.sqlite"

# Corrections to classic-db, each with its reason. Keep this short and explain every line.
#   Table 50 (rare items of item level 71-74, e.g. Zul'Gurub rings and cloaks) has only its 0.5% Nexus Crystal
#   row; the 99.5% Large Brilliant Shard row that table 49 (item level 66-70) has is missing, so without it these
#   items would disenchant into nothing 99.5% of the time.
ADD_ROWS = {50: [(14344, 99.5, 1, 1, 1)]}  # entry: [(item, chance, group, min, max)]


def table_class(cls, subclass, inv):
    """2 for the weapon (essence) tables: weapons, shields (armor subclass 6), held in off-hand (InventoryType 23)."""
    return 2 if cls == 2 or (cls == 4 and (subclass == 6 or inv == 23)) else 4


def lua_num(x):
    return ("%.4f" % x).rstrip("0").rstrip(".")


def main():
    c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    version = c.execute("select version from db_version").fetchone()[0]

    loot = defaultdict(list)
    for e, item, ch, grp, mn, mx in c.execute(
            "select entry, item, ChanceOrQuestChance, groupid, mincountOrRef, maxcount from disenchant_loot_template"
            " where condition_id = 0"):
        loot[e].append((item, ch, grp, mn, mx))
    for e, rows in ADD_ROWS.items():
        have = {r[0] for r in loot[e]}
        loot[e] += [r for r in rows if r[0] not in have]

    # expected outcome lines of each table: [(chance %, count, item)]
    lines = {}
    for e, rows in loot.items():
        out = []
        groups = defaultdict(list)
        for r in rows:
            groups[r[2]].append(r)
        for grp, rs in groups.items():
            if grp == 0:
                chances = [(r, r[1]) for r in rs]
            else:
                fixed = sum(r[1] for r in rs if r[1] > 0)
                equal = [r for r in rs if r[1] == 0]
                share = max(0.0, 100 - fixed) / len(equal) if equal else 0
                chances = [(r, r[1] if r[1] > 0 else share) for r in rs]
            for (item, _, _, mn, mx), ch in chances:
                for n in range(mn, mx + 1):
                    out.append((ch / (mx - mn + 1), n, item))
        lines[e] = sorted(out, key=lambda t: (t[2], t[1]))

    # item level range of each (table class, quality, table)
    ranges = {}
    for cls, sub, inv, q, il, e in c.execute(
            "select class, subclass, InventoryType, Quality, ItemLevel, DisenchantID from item_template"
            " where DisenchantID > 0 and class in (2, 4) and Quality between 2 and 4"):
        k = (table_class(cls, sub, inv), q, e)
        lo, hi = ranges.get(k, (il, il))
        ranges[k] = (min(lo, il), max(hi, il))
    # rare and epic tables are shared: both classes get every range
    for (tc, q, e), r in list(ranges.items()):
        if q >= 3:
            other = (6 - tc, q, e)
            lo, hi = ranges.get(other, r)
            ranges[other] = ranges[(tc, q, e)] = (min(lo, r[0]), max(hi, r[1]))

    # The first table of each class and quality also covers the item levels below it, down to the lowest item level
    # classic-db disenchants at all (5): WoW Forever has rares at item level 15-19 (classic-db's start at 20) and
    # uncommon weapons below 10, and those disenchant like the lowest table of their kind.
    lowest = min(lo for lo, _ in ranges.values())
    prob = defaultdict(lambda: defaultdict(list))
    for (tc, q, e), (lo, hi) in ranges.items():
        prob[tc][q].append([lo, hi, e])
    for tc in prob:
        for q in prob[tc]:
            rows = sorted(prob[tc][q])
            for a, b in zip(rows, rows[1:]):
                if b[0] <= a[1]:
                    sys.exit(f"overlapping item levels: class {tc} quality {q}: {a} {b}")
                b[0] = a[1] + 1  # close gaps
            rows[0][0] = min(rows[0][0], lowest)  # see "lowest" above
            prob[tc][q] = rows

    mats = sorted({i for e in lines.values() for _, _, i in e})
    names = {i: n for i, n in c.execute(
        f"select entry, name from item_template where entry in ({','.join(map(str, mats))})")}

    head = (f"-- Generated by tools/gen_data.py from classic-db (CMaNGOS, GPL-3.0, https://github.com/cmangos/classic-db),\n"
            f"-- {version.rstrip('.')}. Do not edit by hand; run the script again.\n")

    out = [head, "DisenchantValueData.DisenchantingProbabilityKeys = { LOW = 1, HIGH = 2, PROBABILITIES = 3 }\n\n",
           "-- [item class: 2 weapon tables (also shields, off-hand), 4 armor][quality] =\n",
           "--   { { low item level, high item level, chance %, count, item ID, chance %, count, item ID, ... }, ... }\n",
           "DisenchantValueData.DisenchantingProbability = {\n"]
    for tc in (4, 2):
        out.append(f"  [{tc}] = {{\n")
        for q in sorted(prob[tc]):
            out.append(f"    [{q}] = {{\n")
            for lo, hi, e in prob[tc][q]:
                cells = [str(lo), str(hi)] + [f"{lua_num(ch)},{n},{i}" for ch, n, i in lines[e] if ch > 0]
                out.append(f"      {{{','.join(cells)}}}, -- table {e}\n")
            out.append("    },\n")
        out.append("  },\n")
    out.append("}\n")
    (ROOT / "Data/DisenchantingProbabilities.lua").write_text("".join(out), encoding="utf-8", newline="\n")

    def const(n):
        return "".join(ch if ch.isalnum() else "_" for ch in n.upper())

    (ROOT / "Data/DisenchantingMaterials.lua").write_text(
        head + "DisenchantValueData.DisenchantMats = {\n"
        + "".join(f"  {const(names[i])} = {i},\n" for i in mats) + "}\n", encoding="utf-8", newline="\n")
    (ROOT / "Data/DisenchantingItemNames.lua").write_text(
        head + "-- Fallback names until the client has the item cached\nDisenchantValueData.DisenchantingItemName = {\n"
        + "".join(f"  [{i}] = {names[i]!r},\n".replace("'", '"') for i in mats) + "}\n",
        encoding="utf-8", newline="\n")

    # three lesser essences combine into one greater (and back), so a lesser is worth at most a third of a greater
    by_name = {n: i for i, n in names.items()}
    pairs = [(i, by_name[n.replace("Lesser ", "Greater ", 1)]) for i, n in names.items()
             if n.startswith("Lesser ") and n.replace("Lesser ", "Greater ", 1) in by_name]
    (ROOT / "Data/DisenchantingMaterialMapping.lua").write_text(
        head + "-- lesser essence -> greater essence (3 lesser = 1 greater)\nDisenchantValueData.DisenchantingMatMapping = {\n"
        + "".join(f"  [{a}] = {b}, -- {names[a]} -> {names[b]}\n" for a, b in sorted(pairs)) + "}\n",
        encoding="utf-8", newline="\n")
    print(f"{len(lines)} tables, {len(mats)} materials, {len(pairs)} essence pairs; {version}")


if __name__ == "__main__":
    main()
