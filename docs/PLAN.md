# Block Royale: the plan to make it bigger

Block Royale is becoming a **souls-like battle royale**. You can play it alone against bots or with
friends over LAN. The match is still the backbone: drop, loot, outlast the storm, be the last one
standing. But the island fills up with jobs worth taking, places worth finding and enemies worth
fearing. Death costs something, and coming back from it means something.

This document is the order we build things in. Each phase is playable on its own and ships in a
build.

---

## Pillars

1. **Every minute has a goal.** You never just wander between loot. There is always a writ to
   take, a vault to open, a revenant to avoid or hunt.
2. **Risk you choose.** The best rewards sit behind fights you could walk away from: a marked
   champion, a guarded vault, an oath that makes the match harder.
3. **Hard, but fair and readable.** Elite enemies telegraph their moves. You lose because you
   were greedy or careless, not because the game cheated.
4. **Earned, never bought.** Embers come from playing well. They are spent inside the match, and
   Renown carries across matches.
5. **The island is a place.** It has lore, secrets and landmarks you learn. Matches play out
   differently on the same island.
6. **Friends make it better.** Everything works in LAN co-op: shared writs, revives, pings and
   shared Embers.

---

## Names (our own words, nothing borrowed)

| Thing | Our name | What it is |
| --- | --- | --- |
| Contracts / bounties | **Writs** | Sealed jobs nailed to **Writ Boards** in towns and at landmarks. Take one with F. |
| Cash | **Embers** | Earned from kills, writs, vaults and finds. Spent at Wayshrines. |
| Buy station | **Wayshrine** | A stone shrine with a brazier. Buy armour, ammo, kit and a second chance. |
| Second chance | **Kindling** | Carry one and you rise again at the nearest lit Wayshrine when you die. |
| Dropped Embers on death | **Cinder** | Your unspent Embers stay where you fell, glowing. Get back to them to recover them. |
| Most-wanted status | **Branded** | Kill too many too fast and everyone sees you on the map. Survive it for a big payout. |
| Elite boss enemies | **Revenants** | Named, armoured champions with their own moves. Each guards a vault. |
| Hidden treasure rooms | **Vaults** | Sealed rooms under ruins, castles and landmarks. Open them with Sigils. |
| Keys | **Sigils** | Dropped by Revenants, found in secrets, or bought. |
| Difficulty modifiers | **Oaths** | Chosen before the drop. Each makes the match harder and pays more Renown. |
| Account progression | **Renown** | Ranks earned across matches. Unlocks loadouts, cosmetics, Oaths and codex pages. |
| Lore collectibles | **Codex pages** | Scrolls, carvings and notes that tell the island's story. |
| Scan / UAV | **Raven's Eye** | Shows enemies near you on the map for a few seconds. |

---

## Phase 1: Writs, Embers and Wayshrines (the core loop) — DONE

**Writ Boards** stand in every town square and at the big landmarks: a timber frame with parchment
notices and a lantern. Walk up and press F to see the board's writs (one to three). Take one. You
can hold one writ at a time. A writ runs on a timer, between 3 and 6 minutes.

### Writ types

| Writ | Job | Reward |
| --- | --- | --- |
| **Blood Writ** | Hunt a marked target: a bot, or another player in free-for-all. Their area shows on the map as a circle that shrinks and moves every 20 s. They are told they are hunted. | Embers, a loot cache, and a short reveal of nearby enemies |
| **Relic Writ** | Recover a buried relic. Three search circles in turn, each smaller. Dig it up (hold F) and carry it back to any Writ Board. | Embers and a high-tier gun |
| **Beacon Writ** | Light a signal beacon on a hilltop. Hold the area for 45 s while bots converge on it. | Embers, a supply drop at the beacon, and armour |
| **Courier Writ** | Carry a satchel to a far town. You run slower while you carry it. If you drop it, anyone can take it. | Big Embers |
| **Purge Writ** | Clear a bandit camp: 4 to 6 armed bots holding a ruin. | Embers and the camp's chest |
| **Seeker Writ** | Find a hidden Codex page or shrine using a riddle and a rough map circle. | Embers and Renown |

### HUD and feel

- A writ tracker panel shows the title, the objective, a timer and the distance. It sits on the
  map, the minimap and the compass.
- There is a stinger when you take a writ, when the target is found and when it is done.
- Big gold text announces a finished writ, with the reward rolling up.

### Embers

- You earn Embers from:
  - kills (more for headshots and long range);
  - finished writs;
  - opened vaults;
  - the last circles you survive.
- They show on the HUD next to your armour.

### Wayshrines

There are 8 to 12 Wayshrines on the island. Walk up to one and press F to buy:

| Item | Cost |
| --- | --- |
| Armour repair | 300 |
| Ammo crate | 150 |
| Medkit | 200 |
| Grenades | 150 |
| Raven's Eye | 400 |
| Kindling (one carried at a time) | 1200 |
| A Sigil | 900 |

Buying at a Wayshrine lights it, and a lit Wayshrine is where Kindling brings you back.

### Branded

Five kills inside 90 seconds makes you Branded:

- Everyone (bots included) sees your position on the map, refreshed every 15 s.
- Survive 90 s to get 1000 Embers.
- Whoever kills you takes half of that.

**LAN:** writ state lives on the host. Squads share one writ, and everyone in the squad earns
from it.

---

## Phase 2: Revenants and Vaults (souls-like danger) — DONE

**Revenants** are named elite enemies, 3 to 5 per match. Each one guards a vault at a landmark
(Stormkeep, Old Henge, Sunspire, Dragon's Rest, Crystal Hollows and the others).

- Each has a name and a title ("Maelis, the Ash Warden of Stormkeep"), a health bar across the top
  of the screen while you fight them, and heavy armour.
- Their moves are telegraphed:
  - a charge with a wind-up shout;
  - a grenade volley that marks the landing spots on the ground first;
  - a suppressing burst that sweeps;
  - a "call the pack" that summons 2 to 3 bots.
- Phase 2 starts at half health. The Revenant gets faster and the arena changes: fire on the
  ground, or the lights going out.
- They leash to their arena, so you can retreat, heal and come back. They regenerate slowly while
  no one is fighting them.
- When one dies, a bell tolls across the island and every player sees "REVENANT FELLED" in the
  feed.
- The drop is a **Sigil**, a **named legendary weapon** (unique stats, a gold finish and a name
  such as "Widowmaker"), and a pile of Embers.

**Vaults** are sealed doors with a carved sigil slot.

- Use a Sigil to open one. Inside are three tiered chests, a Codex page and sometimes a Kindling.
- Some vaults have a simple puzzle instead: light three braziers in order, step on pressure plates,
  or shoot hidden targets.

---

## Phase 3: Death that matters — DONE (Kindling, Cinders, downed and revive)

**Cinders.** When you die, your unspent Embers drop as a glowing Cinder. If you come back through
Kindling or a squad revive, you can recover it. Anyone else who reaches it first takes half.

**Kindling.** Rise at the nearest lit Wayshrine with a pistol and one bandage, 10 s after death.
This works once per Kindling. After the 5th circle no Kindling works ("the fires have gone out").

**Hollowing (optional solo Oath).** Each time you rise you come back weaker (-10 max health), but
your kills pay more.

**Downed and revive (LAN squads).**

- At 0 HP you go down and crawl. A team mate can hold F for 5 s to revive you.
- You bleed out in 30 s. If the whole squad is down, the squad is out.
- A team mate who carries Kindling can revive you instantly.

---

## Phase 4: More to explore and find — Shrines of the Old Gods, lookout towers and the Codex DONE (caves, shipwreck, treasure maps, secret rooms still to do)

- **Codex pages:** 40 pieces of lore across the island, in ruins, on a skeleton's hand, under a
  jetty, at the top of the giant tree. Collected pages persist and read in a Codex screen on the
  menu. Finding a new page pays Renown.
- **Secret rooms:**
  - false walls in castles that a shot reveals;
  - cellars under some houses, reached through a trapdoor;
  - a smugglers' cave behind the waterfall at Highfalls.
- **Shipwreck** on a reef, with loot in a half-flooded hull (diving uses the air bar).
- **Caves:** two cave systems through the hills, dark, with lanterns, crystal light and good loot.
- **Shrines of the Old Gods:** small one-time shrines. Kneel (hold F) for a random blessing for the
  rest of the match:
  - faster reloads;
  - quieter footsteps;
  - +25 max HP;
  - more Embers from kills.
- **Treasure maps:** found rarely. They mark a dig spot with a rich cache.
- **Lookout towers:** climb to the top and press F to reveal the nearby writs, vaults and loot
  tiers on the map.

---

## Phase 5: Living island events — Reliquary, Fog Bank, The Hunt, Storm Surge, Bounty Hunters and Blood Moon DONE (Caravan still to do)

These are announced with a horn and a banner, and appear on the map.

- **Blood Moon** (late game): the sky turns red, bots become aggressive and hunt in packs, and
  kills pay double Embers.
- **Reliquary Drop:** a golden supply crate guarded by a Revenant's pack. The best loot in the
  match.
- **Storm Surge:** the storm briefly jumps forward a phase. Run.
- **Caravan:** a convoy of jeeps drives a road with armed escorts. Ambush it for its strongbox.
- **Fog Bank:** thick fog rolls over one region for 2 minutes. Close-range chaos.
- **The Hunt:** a Revenant leaves its arena and roams toward the nearest player.

---

## Phase 6: Oaths, Renown and the long game — Oaths and Renown ranks DONE (daily trials, cosmetics still to do)

**Oaths** are picked in the lobby before the drop (the host picks them in LAN). Each adds Renown
on a win or a top-10 finish.

| Oath | Effect |
| --- | --- |
| Oath of Iron | Bots have +50% health |
| Oath of Embers | Wayshrines cost double |
| Oath of the Hunted | You start Branded |
| Oath of Silence | No minimap |
| Oath of Ash | No Kindling |
| Oath of the Pack | Revenants call twice the pack |
| Oath of Glass | You have 75 max health |

**Renown ranks** unlock:

- starting loadout slots and more optics;
- weapon finishes (bronze, silver, gold, "ember" glow);
- character camos;
- banners on the scoreboard;
- new Oaths;
- titles ("Revenant Slayer", "Untouched", "Codex Keeper").

**Match summary screen:** writs completed, Revenants felled, Embers earned, Codex pages found,
Renown gained, and a progress bar to the next rank.

**Daily trials** (offline, seeded by date): "Finish 3 Blood Writs", "Win with only a pistol", and
so on.

---

## Phase 7: Co-op and LAN polish — downed/revive and Quick LAN DONE (ping wheel, squad Embers still to do)

- **Ping wheel:** enemy here, loot here, going here, need help. It works with the existing markers.
- **Squad Embers:** hold E at a Wayshrine to buy for a team mate.
- **Shared writ tracker** on everyone's HUD.
- **Downed and revive** (Phase 3), spectating that hands over cleanly, and squad wipe detection.
- **LAN discovery** is already in. Add a "QUICK LAN" button that hosts or joins the first game
  found, with no typing.

---

## Engineering notes

- New systems live in their own scripts:
  - `writs.gd`: boards, writ state, the HUD tracker data;
  - `embers.gd`: wallet, Cinders;
  - `wayshrines.gd`;
  - `revenant.gd`: extends the bot brain;
  - `vaults.gd`;
  - `codex.gd`;
  - `events.gd`.
- `game.gd` only wires them in.
- The host owns all the state. Clients send requests ("take writ 2 at board 5", "buy Kindling")
  and the host checks them the same way it already checks shots and pickups.
- Placement reuses the village and landmark data (town squares, POI pads, `_free_spot`), so
  nothing lands in a road or a doorway.
- Every system gets a headless test mode (`--writs`, `--revenant`, `--vault`), like the existing
  `--houses` and `--botfight`.
- Performance budget: no new per-frame scans over all bots or loot. Writ targets and Revenants
  tick on timers; boards and shrines are batched meshes.

## Performance (ongoing)

- **Draw calls:**
  - Cars, the drop plane, clouds and weapon optics are now one mesh per material instead of dozens
    of boxes. In a town on LOW: 4387 → about 2000 draws, and shadow draws 1217 → about 300.
- **Shadows:** LOW and MEDIUM render two cascades instead of four.
- **Next:**
  - bake whole houses per village cell;
  - impostors for far trees;
  - cheaper grass on LOW;
  - animation rate for far bots tied to screen size;
  - occlusion culling inside towns.
