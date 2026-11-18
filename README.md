# Block Royale

A battle royale on a generated fantasy archipelago, built with Godot 4.7 (Forward+
renderer). Drop from the plane with up to 99 bots (64 players by default, set in Settings), loot,
and be the last one standing, alone or with friends on a game one of you hosts. A full match runs about 40-45 minutes.

Open the project in Godot 4.7 and press Play, or export with the presets in `export_presets.cfg`.

## Controls

| Key | Action |
| --- | --- |
| WASD | Move |
| Shift | Sprint (hold breath while scoped) |
| C / Ctrl | Crouch · dive while swimming |
| Space | Jump · vault/climb over low walls, fences and crates · dive in or out through a window · jump from plane · open parachute |
| Left mouse | Fire |
| Right mouse | Aim down sights |
| R | Reload |
| B | Fire mode (single / auto) |
| Page Up / Page Down | Zeroing distance |
| Q / E | Lean left / right |
| F | Pick up (ammo for your guns and fitting attachments are picked up automatically) · get in / out of a jeep · take a writ · open a Wayshrine |
| F (hold) | Dig up a relic · light a beacon |
| 1 / 2, mouse wheel, X | Switch weapon |
| H | Use the best healing item |
| 4 / 5 / 6 | Bandage / medkit / energy drink |
| G | Throw frag grenade |
| M | Full map (frees the mouse: left click marks a spot, e.g. where to land; right click removes it) |
| M then mouse wheel | Zoom the map on the cursor |
| Esc | Pause menu (sensitivity, volume) |

In deep water you swim (gun lowered): Shift swims faster, C dives (watch the air bar), Space climbs
out onto a bank or jetty. Shallow water slows you down the deeper it gets.

Healing puts the gun away and plays the item's animation; you can walk slowly but not sprint, and
firing cancels it. A bandage (2.2 s, heals to 75) is torn and wrapped round the forearm; a medkit
(4 s, +60) is unzipped and its syringe goes into your thigh; an energy drink (1.6 s, boost) is
cracked open, downed in three gulps and crushed. Other players and bots show the same item in their
hands, and you can hear someone healing nearby. You cannot heal while swimming.

## Writs, Embers and Wayshrines

The island is full of work for those brave enough to take it.

- **Writ boards** stand in every town and at the great landmarks: a roofed notice board with three
  sealed writs and a pennant in the writ's colour. Walk up and press **F** to take its writ. You
  carry one at a time; a board gets new writs a little after one is taken.
  - **Blood Writ** (red): a soldier is marked as a champion — heavy armour, a good gun, sharp aim.
    Their area shows on your map as a circle that follows them and shrinks. Get within 70 m and
    you see them exactly. Kill them yourself to fulfil it.
  - **Relic Writ** (gold): three search circles, each smaller, lead to a buried relic. Hold **F**
    at the glowing earth to dig up a cache: a high-tier gun, ammo, armour, a helmet and a scope.
  - **Beacon Writ** (blue): climb to a hilltop beacon, hold **F** to light it, then hold the hill for
    45 seconds while the soldiers nearby come for you. A supply drop lands beside it.
  - The writ shows top left (objective, distance, time left), on the map, the minimap, the compass
    and on screen. Run out of time, fall, or lose your mark to someone else and it is void.
- **Embers** ◆ are earned for kills (more for headshots and long shots) and for writs.
- **Wayshrines** (stone shrines with a fire bowl, marked ▲ on the map) sell for Embers: medkits,
  ammo, grenades, armour, helmets, **Raven's Eye** (every soldier within 250 m on your map) and
  **Kindling**. Press **F** at one, then **1–8** to buy; what you buy is laid on its offering stone.
- **Kindling** (solo games): fall while carrying it and you rise again at the nearest Wayshrine with
  a pistol and two bandages. Your kit and your Embers stay where you fell — the Embers glow there
  as a **Cinder** (on your map and screen). Walk over it to take them back. Fall again first and
  they are gone. Once the circle is small the fires go out and Kindling no longer works.
- Writs, Embers and Wayshrines work for every player in a LAN game; the host keeps the score.

- **Branded**: five kills inside 90 seconds and you are Branded. Every soldier within 500 m comes
  for you and the other players see you on their maps. Survive 90 seconds for 1,000 Embers; whoever
  kills a Branded player takes half of that.

## Revenants

Three **Revenants** hold the island's landmarks: named champions in black and crimson plate with
burning eyes ("MAELIS, THE ASH WARDEN OF KINGSBRIDGE"). Get close and their name and health bar
show at the top of the screen.

- They shrug off most of a bullet's damage. Bring friends, grenades and patience.
- Before a grenade volley, red rings mark where the grenades will land. Move.
- At half health they rage: faster, deadlier, and the armed soldiers nearby answer their call.
- They will not leave their ground: lure one far enough and it turns back home, healing as it goes.
- When one falls, a bell tolls across the island. It drops level 3 armour and helmet, medkits, an 8x
  scope and a grenade, and pays its killer 1,200 Embers on top of the kill.
- Revenants are not players: they do not count toward who is left alive.

## Vaults and Sigils

Five sealed **vaults** stand near the landmarks and old ruins: stone crypts with an iron door and a
gold sigil set in it (a padlock on the full map). A **Sigil** opens one: every Revenant carries one,
and Wayshrines sell them for 900 Embers. Press **F** at the door with a Sigil and it grinds down into
the floor. Inside: a top-tier rifle with ammo, level 3 armour and helmet, an 8x scope, medkits and a
grenade, and 600 Embers to whoever opened it. Anyone can walk in once it is open, so be quick.

## Shrines of the Old Gods

Six weathered stone idols stand alone out in the wilds, far from towns and roads, their eyes still
glowing green. Hold **F** to kneel before one and its god blesses you for the rest of the match
(shown top left). Each idol blesses only once, then its eyes go dark, so whoever gets there first
takes it.

| God | Blessing |
| --- | --- |
| Varra of the Swift Wind | Swiftness: you move 8% faster |
| Osk the Unshaken | Steady Aim: a quarter less recoil |
| Mirren of the Nimble Hands | Nimble Hands: reloads a quarter faster |
| The Green Mother | Vigour: 125 maximum health |
| Haldor the Shield | Warding: bullets and blasts hurt you 12% less |
| The Ember King | Ember-Touched: kills pay half again in Embers |

Blessings are lost if you fall (even if Kindling brings you back).

## Renown and Oaths

**Renown** is what you are known for, kept across every match you play. A match pays it for how long
you lasted, for winning, for kills, writs, Revenants felled, vaults opened and blessings taken; the
end screen shows the reckoning, and your rank shows under the title on the main menu:
Ashen, Wanderer, Sellsword, Hunter, Warden, Champion, Revenant-Slayer, and Legend of the Isle.

**Oaths** (main menu, OATHS) are vows you swear before a solo match. Each makes the match harder and
pays a quarter more Renown; they hold until you break them.

| Oath | You swear to... |
| --- | --- |
| Oath of Iron | Soldiers take a third less damage |
| Oath of Embers | Wayshrines charge double |
| Oath of the Hunted | You land Branded |
| Oath of Silence | No minimap |
| Oath of Ash | No Kindling |
| Oath of Glass | You have 75 health |

## Lookout towers

Climb to the upper floor of any watchtower or bell tower and press **F** to survey the land: every
soldier within 300 m shows on your map for a few seconds. Each tower once a match.

## The Codex

Twenty-four torn pages of the island's story lie where it happened: in the ruins, by the
landmarks, at the Old Gods' idols, beside the Wayshrines, even inside a sealed vault. They glow
faintly gold. Press **F** to read one. A page you have read is yours for good (and pays 30
Renown); read them again from the main menu under **CODEX**.

## The living island

Every match, the island throws things at you. A horn sounds and a banner names it.

- **A Reliquary falls** (mid-match): a golden supply crate lands in the next circle with two guns
  and twice the kit of a normal drop. The soldiers nearby head straight for it.
- **A fog bank rolls in**: thick fog for two minutes. Nobody sees far, you included.
- **The Hunt**: a Revenant leaves its ground and stalks the nearest player for two minutes, then
  goes home.
- **The storm surges** (some matches): halfway through a hold, the storm stops waiting and closes
  in seconds.
- **Blood Moon** (late game): the sky turns red and stays red. Soldiers hunt the nearest player in
  packs, and every kill pays double Embers.

The full plan, and what is left of it, is in [docs/PLAN.md](docs/PLAN.md).

## Gunplay

- Every bullet is a simulated projectile with muzzle velocity and gravity drop, flying up to 1.6 km
  (rifles and snipers) until it hits something; soldiers are drawn out to the same range, so long
  shots are real. Long shots need
  holdover and moving targets need lead. Tracers show the path.
- Each weapon has a learnable recoil pattern; part of the kick stays as muzzle climb you pull down.
- Spread grows with movement, jumping and sustained fire, and shrinks when aiming or crouching.
- Scopes (red dot, 2x, 4x, 8x) have holdover marks that follow your zeroing. Scoped aim sways;
  hold Shift to steady it until your breath runs out.
- Headshots hit hard, leg hits less. Helmets and vests (levels 1–3) absorb damage and wear out.
- Ammo comes in calibres: 9mm, 5.56, 7.62 and 12 gauge.

## Loadouts

The main menu's **Loadout** screen picks a primary, a secondary and an optic. With "drop in with
this loadout" on, you land with them and a few boxes of their ammo (bots land armed too); turn it
off to loot everything from scratch.

## Multiplayer

One player hosts from their own game; up to 8 players. It works on a local network and over the
internet. Everyone needs the same version (another build is refused with a message).

1. One player presses **HOST GAME** in the main menu. The lobby shows their address, with a
   button to copy it.
2. The others press **JOIN GAME**. (Or everyone presses **QUICK LAN**: it joins the first open game
   on your network, and hosts one if there is none yet.) Games on the same network appear in the server list; click
   one. For a game over the internet, type the host's address under Direct Connect (`address` or
   `address:port`), and the password if the host set one.
3. In the lobby:
   - Every player has a slot with their colour, ping and ready state. There is a chat (press
     Enter to type).
   - The host picks **Squad vs Bots** or **Free-for-all**, the number of bots, and whether
     everyone lands with their loadout.
4. Everyone presses **READY**. The host presses **START MATCH** (or **FORCE START**), and a
   5-second countdown drops the whole lobby into the same plane.

### Hosting over the internet

- Press **OPEN TO THE INTERNET** in the lobby. The game asks your router to pass the port through
  (UPnP) and then shows the address to share. If the router refuses, forward **UDP 24555** to your
  PC by hand, or use a virtual LAN (ZeroTier, Tailscale, Radmin VPN).
- Type a **PASSWORD** in the lobby to lock it. Joining players prove they know it against a
  one-time challenge; the password itself is never sent.
- **KICK** on a player's slot removes them; Shift + click bans their address (bans are kept in
  `bans.json` in the game's user folder). In a match the host can type these in chat:
  `/kick NAME`, `/ban NAME`, `/unban`, `/password [NEW]`, `/open`.
- If Windows asks whether to allow the game through the firewall, allow it. Ports: UDP 24555
  (game) and UDP 24556 (finding games on the local network).

### How it is kept fair

- The connection is encrypted (DTLS).
- Players talk to the host only. Whatever a player's game reports (movement, shots, hits, loot,
  jeeps, chat) goes through the host, which checks who sent it, how often, and whether it is
  possible, before anyone else hears of it. Nobody can speak as another player or as the host.
- The host runs the bots, the storm, loot and supply drops, and decides eliminations and the win.
- The anti-cheat watches every player from the host and each player's own game: speed and
  teleport hacks, impossible damage or range, shooting through solid ground, rapid fire, edited
  health, ammo or weapons. Flooding the host gets a player kicked.
- A player whose connection drops, or whose game crashes, gets their place and kit back when
  they rejoin within two minutes. That takes the session token their game was given, so nobody
  can take over another player's character by using their name.

In a match:

| Key | Action |
| --- | --- |
| Tab (hold) | Scoreboard: players, kills, damage, ping, bots left |
| Enter | Chat |
| Middle mouse | Place a marker where you look (again on the same spot removes it) |
| Map: left / right click | Place / remove a marker on the map |
| Left mouse (when out) | Spectate the next team mate |

- In squad mode, team mates appear on the squad panel (health and distance), with coloured
  name tags, on the compass and on the map. There is no friendly fire.
- **Down, not out** (squad games): drop to 0 health while a team mate is still standing and you go
  down instead of dying. You can only crawl, the screen reddens, and you bleed out in 30 seconds;
  every hit you take while down drains it faster. A team mate holds **F** beside you for 5 seconds to
  pick you up at 30 health. Downed mates show "DOWN" on the squad panel and over their heads. If the
  whole squad is down at once, it is over.
- When the match ends, Space or Esc returns everyone to the lobby to ready up again.

Joining players load the host's island automatically.

## Jeeps

Off-road jeeps are parked along the roads. Press **F** next to one to drive, or ride as a passenger
(four seats). W/S drive and brake, A/D steer, Space is the handbrake, and the mouse looks around.
Jeeps take bullet and crash damage and explode when wrecked. Running someone over at speed is
lethal. In multiplayer the driver's machine simulates the jeep and everyone sees the same thing.

## Graphics

The game starts fullscreen; **F11** or **Alt + Enter** switches to a window and back.

Settings, then **GRAPHICS**, cycles four presets:

- **LOW:** the fastest. Trees cast no shadows (they are the most expensive thing to shadow), two
  shadow cascades, the 3D view rendered at 77% and sharpened back up.
- **MEDIUM:** fast, with tree shadows, ambient occlusion and bloom.
- **HIGH:** screen-space indirect light and ambient occlusion, reflections, volumetric fog and eye
  adaptation.
- **ULTRA:** adds SDFGI global illumination (sunlight bounces into rooms), softer and longer
  shadows and further draw distance. Made for an RTX 3060 / RX 6600 class GPU.

Also in Settings:

- **UPSCALING:** native, or FSR 2 quality, balanced or performance. Renders the 3D scene at a lower
  resolution and rebuilds it sharply; the quickest way to more frames per second.
- **VSYNC:** on by default (adaptive: no tearing, and no stutter when a frame runs late).
- **SHOW FPS:** the counter in the top left corner (frames per second, frame time, and the
  slowest frame of the last half second).

Each match rolls its weather and time of day: clear noon, golden hour, misty morning, overcast or
a thunderstorm (multiplayer games share the host's). In the storm the rain stops at roofs and trees, so it
never rains indoors; the downpour goes muffled under a roof, and lightning flashes with the thunder
rolling in a few seconds later.

The game uses the Vulkan (Forward+) renderer and falls back to OpenGL automatically on machines
without Vulkan.

## Soundtrack

An original heavy metal soundtrack (five tracks, made for this game, generated by
`tools/metal_synth.py`) plays in the menu and during matches. Settings has separate **MENU MUSIC**
and **MATCH MUSIC** volumes (0 turns it off) and a NEXT button. Gunshots, echoes and other sounds
are synthesized too (`tools/gunshot_synth.py`). Distant shots arrive late at the speed of sound,
and the echo depends on where you are: open field, forest, town or indoors.

## The island

Two islands about 2.4 km across:

- The main island has the cliff-walled Highfalls plateau with a lake and a 75 m waterfall. Two
  ledge trails climb its walls.
- The waterfall's river cuts a gorge to Kestrel Bay. You can cross it at two shallow fords or on
  Kingsbridge.
- Skyreach Bridge, a 230 m stone span with a sky gate, links to the east isle and the Sunspire
  temple.
- Other landmarks: Stormkeep castle on its hill (walkable walls, a three-level keep and the best
  loot), the Old Henge stone circle, Gull Point lighthouse (climb the outside stair for a sniper
  perch) and the Elder Oak.
- Street towns, villages and farmsteads are linked by dirt roads. Lookout towers stand on high
  ground, and ruins and boulders give cover in the open.
- Every house can be entered through its door, and every two-storey house has a stair to its
  upper floor, where the better loot is. Village and town squares have a well and market stalls.
- Fantasy set pieces: the Arcane Spire (a mage tower with an outside spiral stair and a
  floating crystal over the best loot), two Crystal Hollows, Dragon's Rest (a giant skeleton to
  fight through) and the Faerie Grove, where giant mushroom caps form a staircase you vault up to
  a lookout.
- The Elder Oak is a giant tree with a treehouse deck, lanterns and a spiral stair round the trunk.
- Farms have wheat fields with scarecrows, hay-bale cover and paddock fences; houses have stone
  chimney stacks; meadows are covered in grass that sways in the wind (range set by the graphics
  setting).
- Hits match what you see: windows, doors, arches, tree trunks and rocks collide with their own
  meshes, so if you can see someone through an opening you can shoot them through it.
- Bots use doors and stairs too: they loot upper floors, and cautious ones sometimes hold an
  upstairs window and watch the street.

The storm closes in eight phases. It starts slow and weak, so there is time to land and loot,
then each circle gets tighter, faster and more painful. The next safe zone is shown on the map as
soon as it is chosen. Supply drops land during the match. The plane flies at 520 m. Pull the
chute early to glide over 1 km, or dive and pull late to land first.

The map (M) and the minimap show the island as it is: hills with height lines, every tree,
roads, and every building with its roof. The storm is the purple haze outside the current circle;
the white ring is the next safe zone. While you are outside it, the minimap draws the way there
and says how far it is. The minimap opens up when you drive or fall, squad mates and marks that
are off it show on its rim, and the full map has a key, a scale bar and grid references (A-H,
1-8, 300 m squares).

## Credits

Gun models: Ultimate Gun Pack by Quaternius (CC0), see `assets/guns/q/LICENSE.md`.

## Headless checks

```bash
godot --headless --fixed-fps 60 --path . -- --sim
```

Runs a scripted test of looting, healing, reloading, bullet drop, holdover hits and gun handling,
then fast-forwards a full match. `--smoke` is a shorter check, and `--shot --out=file.png` renders a
screenshot (needs a display, e.g. `xvfb-run`; `--lm=castle|bridge|falls|...` frames a landmark).
`--nethost` and `--netjoin` (run in two terminals, without `--fixed-fps`) test a LAN match on
this machine.

Building checks (add `--seed=N` to pick a map): `--houses` walks the player in through every
door and up every stair, `--stairs` climbs every house and tower, `--botstairs` sends a bot up
to loot every upper floor and back out, `--camp` checks bots holding windows, `--shootthru`
fires rays through every window and door opening on the map, `--fantasy` climbs the spire and
the mushroom caps, and `--drive` tests the jeep.

## Anti-cheat

Each machine watches its own player and the host watches everyone: speed hacks (game clock
against the system clock), time-scale changes, running faster than legs allow, teleporting,
flying, firing faster than the gun cycles, magazines that refill themselves, health/armour/items
above their limits, edited weapon stats, aim that snaps onto heads, hits through solid ground,
impossible damage or range, and impossible kill streaks. Blatant cheats are caught at once;
borderline signs have to repeat. A cheater is hunted by the Warden: the world darkens around them,
it closes in faster whenever they look away, and when it reaches them its face fills the screen and
they die. Everyone else sees it stalk them and is told why. Leaving and rejoining does not help.
`--cheattest` (with `CHEAT=speed|rapid|ammo|hp|time|fly|legit`) checks each detection end to end.
