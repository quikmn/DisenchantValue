# Changelog

## Unreleased
- Tooltip: the same tidy look as the other EverlookDB addons: brighter labels, prices on the right with their coins lined up; the material breakdown says "each" beside the name, not after the price.
- New setting "Solid tooltip background" (on by default), shared by every EverlookDB addon.

## v0.2.1 (2026-11-21)
- Your disenchant log names the character's realm again after today's WoW Forever client update, which stopped telling addons the realm's name (entries read "Name-" since then). Those entries are kept as they are, and /dv status counts them.

## v0.2.0 (2026-11-20)
- Settings window: switches, buttons and sliders use a softer shade of the accent colour, an on switch has a dark knob so it stands out, and boxes have cleaner rounded edges.

- Only one "Disenchant" line on tooltips: when EverlookDB Auctions shows its own, DisenchantValue no longer adds a second one with a different price. The breakdown (Shift) and your own results still show, right under it.
- Auctionator is no longer required. Prices come from EverlookDB Auctions' scans first, then Auctionator's; either one is enough.
- The chat line after each disenchant is now off by default (and switched off once for everyone who had it from v0.1.0). Turn it back on with `/dv announce on` or in the window.
- The chat line after a disenchant now names every material ("2x Strange Dust") instead of "item 10940" when the game hadn't loaded it yet.
- Disenchanting an item the game hadn't loaded yet now logs its type and quality too, so it counts for its item-level bracket on tooltips.
- Fixed: opening a crate or bag right after a disenchant could log it as a disenchant. Such entries are removed from your log.
- Without any auction prices, the "no prices, scan the auction house" hint now shows on one item per session instead of on every green item.
- Item tooltips do less work: your own results are added up once per item instead of on every tooltip refresh.

## v0.1.0 (2026-11-19)

- New disenchant odds from classic-db, the open CMaNGOS Classic database. Shields and off-hand items now count as weapons (more essences, less dust), uncommon weapons of item level 21-30 give Lesser Astral and Greater Astral Essence, rares from item level 5 (WoW Forever's new low-level rares) give Small Glimmering Shards, and the price cap for lesser essences (a third of the greater one) now works for every Classic essence. Odds for Outland-level items are gone.
- Settings: an AI help button copies a description of every setting for an AI assistant, and `/dv apply` runs the commands it gives back.
- Chat commands now follow one pattern across all EverlookDB addons: `/dv help` (or `?`) lists them; `/dv status` shows the version, totals and Auctionator; `get` and `set <setting> <value>`; `/dv announce off` or `/dv off announce`; `search <words>`; `version`; a mistyped command suggests the nearest one. `/dv summary` and `/dv quiet` still work.
- Tooltip lines now share one tidy layout with the other EverlookDB addons: labels left, values right, in a fixed order (after EverlookDB Auctions' prices; your own results after every value line). "Disenchant  Auctionator · scanned today" on the left, "~1g 20s" on the right; "Your disenchants  this item · 3 disenchants" likewise; the breakdown is indented under its line. Money rounds the same way as in the other addons.
- The settings window has a search box at the top: type to find any setting.
- `/dv` opens a window: totals and whether Auctionator is loaded, your last 100 disenchants (hover one for the item), and options. New options: the value on tooltips on or off, the per-material breakdown with Shift (as before), always or never, your own results on tooltips, the lesser-essence price cap, how many disenchants the log keeps (10,000 as before), and a button to forget every disenchant. Also under Settings > AddOns. `/dv summary` prints what a bare `/dv` used to; `/dv recent` and `/dv quiet` work as before; any setting works from chat (`/dv breakdown always`, `/dv settings`, `/dv help`).
- The tooltip value says how old its prices are ("scanned 3 days ago"), from the oldest Auctionator scan it used.
- "Your DEs" on tooltips is now "Your disenchants", and "ilvl" is "item level".
- Lowering "Disenchants kept in the log" trims the log when you close the window, so dragging the slider down and back up loses nothing; trimming a big log no longer stalls the game.
- Settings window: Escape closes an open dropdown list first, then the window; Escape in a text box puts the old text back; a number typed next to a slider snaps to the slider's steps; a Delete or Reset that asks for a second click no longer forgets it early.
