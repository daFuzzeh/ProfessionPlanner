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
- **Where the sell-back comes from:** every step says what to do with what you craft. By default the plan counts only the vendor price, which is guaranteed; the Sell-back card names the outlet in use. Where the auction house clearly pays more and the item actually sells, the step says so. Options can switch the plan to count AH prices, or nothing. The Profit tab has a Sell at column: AH or Vendor.
- **Professions list:** shows only the professions TradeSkillMaster has recorded for the selected character. **Show all professions** underneath lists the rest, for planning one you have not learned yet.
- **The route stays put:** the route is chosen when you press **Plan**, or change the character, profession, target or an option, and is then kept. While the window is open it still follows what you do: gain a skill point, craft or buy materials, or learn a recipe, and about a second later the counts, costs and shopping list are brought up to date and finished steps drop off the top. The recipes and their order do not change, so buying the shopping list no longer reshuffles the route. The line at the bottom of the window says `kept until you press Plan`; press **Plan** to choose again from what you have now. A kept route is also there after `/reload` or a look at another profession, and is dropped after 12 hours. Skill levels are read from the game itself, so they are current even when TradeSkillMaster's copy lags.
- **Materials you can make yourself:** a material your profession makes (a bolt of cloth, leather, a cured hide, blasting powder, a grinding stone, a bronze tube) is made instead of bought when that is cheaper, and the skill points from making it count towards the route. The step lists the base materials and a **Make first** line with what to make from them. A material that costs a little more to make than to buy is still made when the skill points it gives come cheaper than the craft's own. Something an earlier step made is used by a later step before more is bought; that earlier step then says how many to keep instead of sell. Only recipes you know, or can learn from a trainer at that skill, are used for this. The **Make materials myself** option turns it off.
- **Recipes you already hold or have just learned:** a recipe item in your bags, bank or mail is not charged or listed to buy again; the step says to use it. A recipe you learn is counted as known at once, before TradeSkillMaster has seen it.
- **Shift-click to search:** on the Shopping tab, shift-click an item (name or icon) with TradeSkillMaster's Browse tab open at the auction house and TSM searches for exactly that item. It is the same as shift-clicking an item in your bags, so with a chat box open it links the item instead.
- **Click to open the recipe:** click a recipe's icon or name on the Route, Recipes or Profit tab (or its icon on the Stats tab) and the game's profession window opens at that recipe, ready to craft. The character you are playing must have that profession. If the window cannot be opened or does not turn to the recipe, a chat line says why. Shift-click still links the item. New in 1.12.0 and not yet confirmed in the game.
- **Which trainer:** when the route reaches a skill cap (75, 150, 225) it names the trainers who actually teach the next rank for your faction, with coordinates and a Show on map button. Not every trainer does: an "Expert Alchemist" in a capital teaches Journeyman only. The note disappears once you have trained the rank. Cooking and First Aid get their higher ranks from books and quests, which are not listed.
- **Learn ranks from your trainers:** the skill a trainer asks before teaching a recipe is set by the server, so the shipped ranks are second-hand. Whenever you open a profession trainer's window the addon reads the rank for every recipe listed and uses it from then on, for every character on the account; chat names the recipes whose rank turned out different. A route step that still rests on a second-hand rank says `not confirmed yet`. If the trainer does not offer such a recipe although your skill is at its rank, the recipe is taken out of your routes and chat says so; it returns when a trainer lists it. Only that stretch of a kept route is chosen again.
- **Stats:** the Stats tab shows what your crafting actually cost, per character and profession, for this session and all time: skill points, crafts, materials used, sell-back, cost per point, and how your skill-up luck compares with the average, overall and per recipe. Gold is the value of materials at the time of crafting (recipes bought and training fees are not counted). Tracking runs whenever the addon is loaded, window open or not.
- **Travel arrow:** press **Show on map**, place a map pin yourself, or type `/pp go wailing caverns` (a dungeon, flight point or zone) or `/pp go 45 62` (a spot in the zone you are in). A small movable box lists the trip one stop at a time: walk to this flight master, fly here, take this boat or zeppelin, walk to the spot. The arrow leads you along a trail of path points worked out from the game's terrain: around mountains and cliffs and along roads where there are any. The box says how far and which way to the next bend, what to do there ("then turn left"), the next named place on the way and how far is left. It uses only flight points this character has learned, which it reads when you open any flight map, and offers ones you have not learned when they are almost on your way. `>` skips a stop, `x` or `/pp stop` ends the trip. You do the travelling; the addon never moves the character.
- **Route:** crafts per step, materials, sell-back, net gold per expected skill point, trainer-cap reminders, and whether the character's gold covers it. Each step also names the next cheapest recipes, so there is a fallback when a material is bought out.
- **When a route stops short:** it says what is in the way at that skill: how many of the remaining recipes are out for each reason, which materials have no price, and the next recipe that can be learned.
- **Cheapest route:** builds two routes, cheapest per skill point and fewest recipe changes, and shows the one with fewer changes unless the other gets further or costs at least 5% less. Stock you already own counts as paid for, but a craft that pays for itself is ranked as free, no better, so a recipe that is turning green is not preferred for its sell-back. The route leaves a recipe only for one that is at least 10% cheaper per point, and one leftover material does not start a run. A recipe below a 25% skill-up chance is used only when it costs under a quarter of the best normal recipe per point, and never below 10%.
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
- Counts of materials to make are rounded up to whole crafts. Where a recipe makes several at once (five Silver Contacts), the ones left over are not counted for anything.
- With a kept route, buying a material the route planned to make changes the craft counts of that step (the skill points from making it are gone); the recipes and their order stay.
- Usable stock is bags, bank and mail. Items you have posted on the auction house are not counted.
- The listed-auction count comes from TSM's last scan and can be out of date.
- Character roster, gold, stock and known recipes are read (never written) from TSM's saved data. A TSM update that changes that layout would need an addon update.
- Learn ranks for trainer recipes are second-hand until you have opened that trainer's window. Blacksmithing, Leatherworking and Tailoring are the least certain: a route can name a recipe a few points before the trainer will teach it, or later than needed. Steps marked "not confirmed" rest on a rank reported by another site or taken from recipe text.
- Recipe location text covers Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking and Tailoring. Cooking, First Aid and Mining show the basic learning text only.
- A few materials have no name in the bundled data. They show as `Item 12345` until the game has seen the item, and are searched in TSM by item ID.
- An enchant's target item is not costed. Cooldown recipes and special crafting stations are left out unless enabled.
- Disenchant uses up an item each time and those items are not costed, so a Disenchant step costs more than shown. The route warns when it uses one; press **Avoid** on the step to plan without it.
- The trail comes from the shape of the ground only. Buildings, city walls, bridges, tunnels and lifts are separate models it cannot see, so there are no path points inside Undercity, Stormwind or Ironforge, and none through tunnels or across bridges. Where the path points stop, the box says so and the arrow points straight at the goal. A trail can also run into a wall or fence the ground data does not show.
- To fill those gaps the addon remembers where you walk (one point every 10 yards, on ground it has not recorded before; not on flights, boats or lifts, nor as a ghost) and uses those paths for later trips, on every character of the account. `/pp record` shows how much is recorded; `/pp record off` stops it. Nothing is sent anywhere: it stays in the saved settings on your PC.
- Travel times are estimates used to compare routes.
- Travel knows the original dungeons' entrances only. For a dungeon that is new in Forever, place a map pin on it instead.
- Travel does not use hearthstones, mage portals or the Deeprun Tram, and has no routes for Outland or other maps beyond Kalimdor, the Eastern Kingdoms and Zephras Isle. Inside a city, cave or instance the game may give no position; the arrow returns outside.
- Which faction may board each boat and zeppelin is a hand-kept list. If the box sends you to one you cannot board, press `>` and report it.
- Only crafting is planned. Mining is levelled mostly by mining nodes, so a Mining route covers smelting only and stops early.
- The last points of Blacksmithing, Engineering, Leatherworking and Tailoring come from recipes that drop, come from quests or are sold by vendors, not from trainers. The route stops where none of those is usable and says why (recipe not on the auction house, or a material with no price). **Buy AH recipes** lets it use recipes listed on the auction house.

## Data and sharing

Recipe and item data is generated from client build 1.60.1.71037. The addon contains no character, account or realm data of its author, no credentials and no paid guide content.

Flight points, flight paths and boat and zeppelin stops are generated from client build 1.60.1.70862, and the path points from its terrain tiles. Dungeon entrances are from the CMaNGOS Classic world database (GPL-3.0).

Recipe acquisition text is from **Classic WoW Forever** (`https://classicwowforever.com/`), licensed **Creative Commons Attribution 4.0 International**. See `LICENSE.txt`.

For 78 trainer recipes the learn rank is the one **ForeverWowCraft** (`https://foreverwowcraft.com/`) reports as seen at a trainer in the game. For 121 more Blacksmithing, Leatherworking and Tailoring recipes it is the trainer rank given in the Classic WoW Forever text, where that is the lower one. Both kinds are marked unconfirmed until your own trainer visits replace them. The ranks the addon reads are kept in its saved variables on your computer and are not sent anywhere.

## How it is tested

Every release runs on Lua 5.1 (the game's interpreter) against a strict stand-in for the game client that rejects calls the real client would reject, with a TradeSkillMaster double and real TSM saved data. Routes are compared with an independent Python implementation of the same planner. That is not the same as the game itself: please report anything that behaves differently in-game.
