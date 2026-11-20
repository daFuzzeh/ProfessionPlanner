# Profession Planner for WoW Forever

Plans the cheapest way to level a profession: lowest net gold per expected skill point, priced from your own TradeSkillMaster data. It is a standalone addon and needs no website or other service.

## Install

1. Extract the ZIP so this file exists:
   `World of Warcraft\_forever_\Interface\AddOns\ProfessionPlanner\ProfessionPlanner.toc`
2. Keep the folder name `ProfessionPlanner`; do not nest a second copy inside it.
3. Restart WoW, or use `/reload` if the addon was installed while the game was open.
4. Type `/pp` (also `/profplan` or `/professionplanner`).

For auction prices, character stock, gold and known recipes, install **TradeSkillMaster 4** and run the TSM Desktop App so auction data is delivered. Without TSM the window still opens, says so at the top, and can only price vendor materials.

The first time, open each profession window once with TSM enabled so TSM records which recipes the character knows. Until then the planner says so and prices already-known recipes as purchases.

## What it does

- **Window:** pick a character and profession on the left, set the skill range at the top (or press **Next cap** / **To 300**), and read the totals in the cards. Settings are under **Options**. Hover an icon for the item's tooltip.
- **Recipes the route may buy:** the **Vendor recipes** and **AH recipes** switches next to the tabs. With both off, the route uses only trainer recipes and recipes you already know.
- **Show on map:** a step that needs a vendor recipe lists only the vendors your faction can use, with coordinates, and a button that places the game's own map pin on the nearest one and opens the map. Click again for the next vendor. No other addon is needed; TomTom gets the same waypoint if you have it. Positions are from the original game world, so a vendor WoW Forever has moved may be off.
- **Limited stock:** some vendors hold only one of a recipe and take hours to get another, so it is often sold out or camped. Those steps are marked, with the restock time and what the route would cost without that recipe. The **Limited stock** switch next to the tabs stops the route relying on them. The starting list describes the original game; whenever you open a vendor window the addon notes how many of each recipe were left, and what it has seen overrides the list.
- **Clear pin:** appears beside Show on map while the pin is up. The pin also clears by itself when you open that vendor's window.
- **Route:** crafts per step, materials, sell-back, net gold per expected skill point, trainer-cap reminders, and whether the character's gold covers it. Each step also names the next cheapest recipes, so there is a fallback when a material is bought out.
- **When a route stops short:** it says what is in the way at that skill: how many of the remaining recipes are out for each reason, which materials have no price, and the next recipe that can be learned.
- **Cheapest route:** compares strict cheapest-per-point selection with a low-swap route and keeps the cheaper one that reaches the target. Stock you already own counts as paid for.
- **Starting skill:** read from the character each time the window opens. Type a different From/To to look at another range.
- **Recipe purchases:** trainer and known recipes are always used. A recipe that trainers teach is learned from the trainer even where Forever also has a recipe item for it. **Buy vendor recipes** (on by default) adds recipes sold for gold by a vendor your faction can reach, at the vendor price. **Buy AH recipes** (off by default) adds recipes bought on the auction house. The purchase cost is spread over the skill points the recipe is useful for.
- **Locations:** where to learn or buy each recipe that is not already known.
- **Shopping:** what to buy, split into auction house and vendor. Materials with fewer auctions listed than the route needs are flagged, because the real cost will be higher than the estimate.
- **Recipes:** recipes useful in the chosen skill range with cost per point, why any are unavailable, and Avoid / Allow.
- **Profit:** crafts that sell for more than their materials, with regional sales per day.
- **All characters:** cost to the next trainer cap for every profession TSM knows on this realm and faction.
- Ticks, options and avoided recipes are saved in `ProfessionPlannerDB`.

## TSM Shopping

On the Shopping tab press **Select buy list**, then **Ctrl+C**, and paste into TSM's Shopping search. Each term is an exact-name search capped at the quantity to buy (for example `Silverleaf/exact/x40`), so TSM stops offering an item once enough is bought. With **Bad-luck spare** ticked the caps include the spare quantity. The addon does not change TSM settings or drive TSM's window; addons cannot write to the clipboard, which is why the copy is manual.

## Limits

- Craft counts are expected values. Skill-ups are random; the bad-luck spare is an estimate, not a guarantee.
- Prices are TSM's values at its last scan. A missing price is never treated as zero; the route stops and says why.
- Usable stock is bags, bank and mail. Items you have posted on the auction house are not counted.
- The listed-auction count comes from TSM's last scan and can be out of date.
- Character roster, gold, stock and known recipes are read (never written) from TSM's saved data. A TSM update that changes that layout would need an addon update.
- Recipe location text covers Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking and Tailoring. Cooking, First Aid and Mining show the basic learning text only.
- A few materials have no name in the bundled data. They show as `Item 12345` until the game has seen the item, and are searched in TSM by item ID.
- An enchant's target item is not costed. Cooldown recipes and special crafting stations are left out unless enabled.
- Disenchant uses up an item each time and those items are not costed, so a Disenchant step costs more than shown. The route warns when it uses one; press **Avoid** on the step to plan without it.
- Only crafting is planned. Mining is levelled mostly by mining nodes, so a Mining route covers smelting only and stops early.
- The last points of Blacksmithing, Engineering, Leatherworking and Tailoring come from recipes that drop, come from quests or are sold by vendors, not from trainers. The route stops where none of those is usable and says why (recipe not on the auction house, or a material with no price). **Buy AH recipes** lets it use recipes listed on the auction house.

## Data and sharing

Recipe and item data is generated from client build 1.60.1.70862. The addon contains no character, account or realm data of its author, no credentials and no paid guide content.

Recipe acquisition text is from **Classic WoW Forever** (`https://classicwowforever.com/`), licensed **Creative Commons Attribution 4.0 International**. See `LICENSE.txt`.

## How it is tested

Every release runs on Lua 5.1 (the game's interpreter) against a strict stand-in for the game client that rejects calls the real client would reject, with a TradeSkillMaster double and real TSM saved data. Routes are compared with an independent Python implementation of the same planner. That is not the same as the game itself: please report anything that behaves differently in-game.
