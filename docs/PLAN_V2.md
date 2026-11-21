# Block Royale: The Isle of Embers — Plan v2

The goal: a game you can pick up in a minute and keep mastering for a hundred hours.
**Low complexity, high skill.** Every class has one attack, one alternate, one ability and one
passive. Nothing more to learn, everything to master: timing, spacing, reading the enemy.

This plan is ordered: each phase leaves the game better and shippable, and is checked with real
screenshots and the automated tests before the next begins.

---

## Phase 1 — Classes: choose who you are

Four classes, playable in **every mode** (Battle Royale, Souls, the Ordeal, the Hall of Echoes,
LAN). Each has a weapon nobody else has, plus room for the guns you find on the island
(Battle Royale) or not (Souls, where the class weapon is the build).

| Class | Weapon (slot 1) | Alt (right mouse) | Ability (Q, cooldown) | Passive |
|---|---|---|---|---|
| **THE KNIGHT** | Ashen greatsword: 3-hit combo, wide arcs, the third swing a heavy overhead | **Guard**: block from the front, takes 80% less; a guard raised *just* as a blow lands is a **parry**: no damage, the attacker staggers | **Shield Charge**: a short dash that bashes and staggers anything in the way | +25% max health, takes 10% less from the front |
| **THE HUNTER** | Longbow: hold to draw, release to loose; full draw flies flat and hits hard; arrows drop with distance | **Focus**: steady the draw, slow zoom | **Volley**: three arrows at once in a tight fan | Quieter steps, faster sprint, arrows recoverable from where they land |
| **THE PYROMANCER** | Ember staff: balls of fire that burst, burning the ground for a moment | **Flame wall** (hold): a short cone of fire, close range, eats Ember | **Blink**: step through space a few metres | Ember gauge refills on its own and from kills |
| **THE GUNSLINGER** | The guns you know: rifle and revolver (Battle Royale: any gun) | Aim down sights | **Quickdraw**: instant reload and the next 6 shots fire faster | Reloads 20% faster, more ammo from boxes |

Every class keeps **dodge roll** (with i-frames), **flask**, **slide** and **sprint**.

- Melee hits are real: a swept arc against the actual hitboxes, so a big boss is easy to hit
  and a small one is not. Hits stagger normal enemies; bosses stagger only at the end of a combo
  or from a parry.
- First-person view models for the sword, bow and staff, with animations: idle sway, swing
  arcs, bow draw and release, staff cast recoil, guard pose.
- Third person: the mannequin's own *Sword_Attack*, *Sword_Idle*, *Spell_Simple_Shoot* clips
  play for swords and spells.
- Class choice is saved, shown on the menu card, and sent over LAN so others see what you are.

**Done when:** each class can kill a boss in the Ordeal; tests cover melee hits, parry, bow drop,
fireball burst; screenshots of each view model look right.

## Phase 2 — The menu: everything explained

A full main menu with sections down the left and a **description panel**: moving the mouse over
(or focusing) *any* button tells you, in one or two plain lines, exactly what it does.

- **PLAY**: Battle Royale · Souls Mode · The Ordeal · Hall of Echoes · Host LAN · Join LAN
- **CHARACTER**: the four classes side by side, each with its weapon, alt, ability, passive and a
  difficulty mark; choose and it is yours everywhere
- **ARMOURY**: loadout (Battle Royale guns), talismans
- **CODEX**: the lore pages, the bosses you have met (with their portraits and how to beat them)
- **RECORDS**: renown and rank, oaths, Ordeal and Echoes best times
- **HOW TO PLAY**: every mode, every control, every system (writs, wayshrines, embers, gifts,
  talismans, flask, dodge, parry) — short pages, one idea each
- **SETTINGS**: Video · Audio · Controls · Gameplay (guidance on/off, hints on/off, crosshair,
  FOV, sensitivity)
- **QUIT**

Visual: dark glass panels, ember-gold accents, a slow camera over the island behind it, the
chosen class standing in the corner.

**Done when:** a screenshot of every section shows clear titles, every button has a description,
nothing overlaps at 1280×720 and 1920×1080.

## Phase 3 — Guidance: never lost, never dumped next to a boss

- Souls Mode starts on a **shore at the edge of the isle**, far from any keeper, with a short
  opening walk.
- A **guide wisp** (a small ember spirit) flies ahead of you to the next objective, waits when you
  stop, and fades once you are close.
- A clear **objective tracker** at the top left: the current step, the distance, and a marker on
  the compass and map. Steps at the start teach the game one thing at a time:
  1. *Walk to the wisp* (move, look)
  2. *Roll through the brambles* (dodge)
  3. *Strike the hollow* (your class attack) — a weak hollow on the path
  4. *Rest at the Wayshrine* (respawn point, flask refill, shop)
  5. *Follow the wisp to the first keeper* — the easiest boss first, then the tracker always
     points at the nearest keeper you have not felled.
- A hint line under the tracker shows the key for each new thing the first time it matters.
- **Settings → Gameplay → Guidance** turns the wisp and hints off (the tracker stays, it is just
  information). Battle Royale gets the same tracker for writs and bosses.

**Done when:** a new player reaches and fights the first keeper without opening the map;
screenshots of every tutorial step.

## Phase 4 — Battle Royale with classes

- Bots pick classes too: Knights rush and swing, Hunters keep their distance and loose arrows,
  Pyromancers burst fire at mid range, Gunslingers fight as now.
- Class weapons appear only on their class; guns stay loot for everyone (a Knight can carry a
  rifle as a second weapon).
- Balance targets: a skilled Knight wins up close, a skilled Hunter wins at range, the
  Pyromancer owns corners and groups, the Gunslinger is the steady all-rounder.

## Phase 5 — Hitboxes: every boss, its whole body

- An automated **coverage audit**: for each boss, rays are cast at a grid across the silhouette
  of its visible meshes; coverage must be at least 90%. Any shortfall gets shapes added
  (cloaks, horns, wings, bells, tails).
- Melee arcs use the same shapes, so what you see is what you hit.

## Phase 6 — Movement and feel

- **Slide**: sprint + crouch, keeps momentum, lowers your hitbox, can chain into a jump.
- Smoother camera on landing, sword hits with hit-stop (a 40 ms freeze) and screen kick, sparks on
  parry, embers on fire hits.
- Stagger and posture: normal enemies stagger on a heavy hit; bosses have a posture bar that a
  parry or a combo fills, and when it breaks they reel and take extra damage (riposte window).

## Phase 7 — Polish pass

- Screenshot every mode, every menu, every boss, every class; fix every flaw found.
- Performance check at high settings; nothing new costs more than a frame.
- Full regression and LAN tests; build both executables.

---

### Order of work

1 → 2 → 3 are the foundation (who you are, where you go, what everything does). 4–6 deepen
combat. 7 runs after every phase as well as at the end.
