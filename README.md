# DisenchantValue

WoW Forever (interface 16001). Prices come from EverlookDB Auctions or Auctionator (either one; both are optional).

- Item tooltips show the estimated auction value of disenchanting the item, from Classic disenchant odds and your auction prices. Hold Shift for the breakdown. Works alongside EverlookDB Auctions: only one "Disenchant" line is shown.
- Logs every disenchant on all your characters and shows your own results on tooltips, per item and per item-level bracket.
- `/dv` opens the window (overview, recent disenchants, options; also under Settings > AddOns). Its chat commands follow the same pattern as every EverlookDB addon: `/dv status` (version, totals, where prices come from), `/dv recent` (last 10), `/dv breakdown always` or `/dv set breakdown always` (change a setting; `/dv get` lists them), `/dv announce off` (no chat line after each disenchant), `/dv search <words>` (the window with its search box filled), `/dv help` (or `?`) lists everything. A mistyped command suggests the nearest one. The old `/dv summary` and `/dv quiet` still work.

## Credits

Disenchant odds: [classic-db](https://github.com/cmangos/classic-db) (CMaNGOS, GPL-3.0). WoW Forever can differ; your own logged disenchants show next to the estimate.

## License

GPL-3.0-or-later (see LICENSE). Not affiliated with Blizzard Entertainment.
