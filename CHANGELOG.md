# Changes

## 1.12.1
- The route stays put. It is chosen when you press **Plan** or change the character, profession, skill range or an option, and is then kept: crafting, buying and skill gains update the counts, costs and shopping list, not the recipes or their order. The line at the bottom says `kept until you press Plan`. A kept route survives `/reload` and a look at another profession, and is dropped after 12 hours.
- Fixed: a route could bounce between two recipes that share a skill range, because a craft that pays for itself made the worse skill-up chance look better.
- The route leaves a recipe only for one that is at least 10% cheaper per skill point, and one leftover material no longer starts a run.
- A recipe with a low skill-up chance is used only when it costs under a quarter of the best normal recipe per point.
- If a trainer does not offer a recipe whose learn rank is not confirmed, the recipe leaves your routes and chat says so. It returns when a trainer lists it.
- A recipe item you already hold is not charged or listed to buy again, and a recipe you learn counts as known at once.
- Recipe data rebuilt from client build 1.60.1.71037: 27 recipes changed, mostly the skill at which they turn grey.
- Fixed: the skill at which a recipe turns green is shown as the game shows it.

## 1.12.0
- Click a recipe's icon or name on the Route, Recipes or Profit tab and the game's profession window opens at that recipe. Shift-click still links the item.

## 1.11.1
- Learn ranks for 121 more Blacksmithing, Leatherworking and Tailoring trainer recipes lowered to the rank given in the Classic WoW Forever text. These are estimates and are marked "not confirmed".

## 1.11.0
- Learn ranks from your trainers: opening a profession trainer's window reads the skill each listed recipe needs, and the addon uses it from then on for every character on the account.
- 78 trainer learn ranks replaced by the ranks ForeverWowCraft reports as seen at a trainer in the game, marked "not confirmed" until your own trainer visit replaces them.

## 1.10.0
- Travel remembers where you walk (not on flights, boats or lifts) and uses those paths for later trips, to cover cities, bridges and tunnels the terrain data does not show. `/pp record` shows how much is recorded, `/pp record off` stops it. It stays in the saved settings on your PC.

## 1.9.1
- Trails for Kalimdor and Zephras Isle.

## 1.9.0
- The travel arrow follows a trail worked out from the game's terrain and roads instead of pointing straight at the goal, and the box says how far and which way to the next bend and what to do there.
- No trail inside Undercity, Stormwind or Ironforge, nor across bridges or through tunnels: there the box says so and the arrow points straight.

## 1.8.1
- Fixed: travel sent you to a flight master in the city you were already standing in.

## 1.8.0
- Travel arrow: **Show on map**, a map pin of your own, or `/pp go <place>` plans the way from where you stand: walk, flight paths you have learned, boats and zeppelins. A small movable box shows the steps and an arrow. You do all the moving.

## 1.7.0
- Stats tab: crafts, skill points, cost and luck per character and profession, for the session and all time.

## 1.6.0
- At a skill cap the route names the trainers who teach the next rank for your faction, with a map button.

## 1.5.1
- Shopping tab: shift-click an item with TradeSkillMaster's Browse tab open at the auction house to search for it.

## 1.5.0
- The open window follows what you do: skill gains, crafting, buying and learning recipes re-plan the route about a second later.
- Profession levels are read from the game itself, so they are current and include professions TradeSkillMaster has not recorded yet.

## 1.4.2
- The professions list shows only the selected character's professions, with a "Show all professions" button underneath.

## 1.4.1
- Every route step says where its sell-back comes from (vendor or auction house) and for how much, and points out when the auction house clearly pays more.
- The Sell-back card names the outlet in use; the Profit tab has a "Sell at" column.

## 1.4.0
- Vendor recipes sold in limited numbers are marked, with the restock time and what the route costs without them.
- "Limited stock" switch next to the tabs, to stop the route relying on those recipes.
- The addon notes how many recipes a vendor had left whenever you open a vendor window; that overrides the built-in list.
- "Clear pin" button; the map pin also clears when you open the pinned vendor's window.

## 1.3.0
- "Show on map" button for recipes sold by vendors, with coordinates in the step text.
- Vendor recipes / AH recipes switches next to the tabs.

## 1.2.2
- Recipe sources list only the vendors your faction can use.

## 1.2.1
- Fixed: the logged-in character was not found in TradeSkillMaster's data on WoW Forever.

## 1.2.0
- Redesigned window: profession sidebar, summary cards, item icons and tooltips, options panel.

## 1.1.0
- First version that loads in the game client. Trainer recipes are no longer priced as purchases; routes that stop early say why.
