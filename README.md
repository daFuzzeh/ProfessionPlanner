# Profession Planner for WoW Forever

An addon that plans the cheapest way to level a profession: lowest net gold per expected skill point, priced from your own TradeSkillMaster data. Guides send everyone to the same recipes, so those materials get camped and overpriced; this works the route out from current prices instead.

**Status: early test build.** It has had very little time in the real game client. Expect rough edges and please report them.

## Download and install

1. Get the latest `ProfessionPlanner-x.y.z.zip` from the [Releases](../../releases/latest) page. Do not use the green "Code" button; that download has the wrong folder layout.
2. Extract it into `World of Warcraft\_forever_\Interface\AddOns` so that `AddOns\ProfessionPlanner\ProfessionPlanner.toc` exists.
3. Restart WoW and type `/pp`.

For auction prices, stock, gold and known recipes you need **TradeSkillMaster 4** and its desktop app. Open each profession window once so TSM records what the character knows.

## What it does

- Cheapest route between any two skill levels, with crafts, materials, sell-back and gold per skill point for every step.
- Uses what is already in your bags, bank and mail, and optionally your alts'.
- Shopping list with a search string to paste into TSM Shopping.
- Recipes to buy are optional: switch vendor and auction-house recipes on or off and watch the cost change.
- "Show on map" places the game's own map pin on the vendor that sells a recipe, for your faction.
- Marks vendor recipes that are sold one at a time and are often sold out or camped, and can plan around them.
- The route is chosen when you press Plan and then stays put: crafting and buying update the counts and the shopping list, not the recipes or their order.
- Click a recipe to open the game's profession window at it. Shift-click a material to search TSM for it.
- Reads the skill a trainer asks for each recipe when you open the trainer's window, and uses it from then on. Shipped trainer ranks that are second-hand are marked "not confirmed".
- Names the next cheapest recipes for each step, for when a material is bought out.
- A Profit tab for recipes that sell for more than their materials.
- Names the trainers who teach the next profession rank, and keeps a Stats tab of crafts, skill points and cost.
- Travel arrow: `/pp go <place>`, a map pin or "Show on map" plans the way from where you stand over flight paths you know, boats and zeppelins, and leads you along a trail around mountains and along roads. You do all the moving. This part is new and has had almost no time in the game.

More detail is in [ProfessionPlanner/README.md](ProfessionPlanner/README.md).

## Reporting a problem

Open an [issue](../../issues) and include: the addon version (shown next to the title), your faction, the profession and skill range, what you expected and what you saw. A screenshot helps. If the game shows a Lua error, paste its text.

## Credits and licence

MIT licence. Recipe acquisition text is from [Classic WoW Forever](https://classicwowforever.com/) (CC BY 4.0). Some trainer learn ranks are the ones [ForeverWowCraft](https://foreverwowcraft.com/) reports as seen at a trainer. Vendor map positions are from the [pfQuest](https://github.com/shagu/pfQuest) database by Shagu (MIT). Vendor stock limits, rank trainers and dungeon entrances are from the [CMaNGOS Classic database](https://github.com/cmangos/classic-db) (GPL-3.0); those tables are offered under GPL-3.0. See [LICENSE](LICENSE). Not affiliated with Blizzard Entertainment or TradeSkillMaster.
