# Block Royale

A battle royale on a generated fantasy archipelago, built with Godot 4.7 (GL Compatibility
renderer). Drop from the plane with up to 99 bots (64 players by default, set in Settings), loot,
and be the last one standing, alone or with friends over LAN. A full match runs about 40-45 minutes.

Open the project in Godot 4.7 and press Play, or export with the presets in `export_presets.cfg`.

## Controls

| Key | Action |
| --- | --- |
| WASD | Move |
| Shift | Sprint (hold breath while scoped) |
| C / Ctrl | Crouch |
| Space | Jump · jump from plane · open parachute |
| Left mouse | Fire |
| Right mouse | Aim down sights |
| R | Reload |
| B | Fire mode (single / auto) |
| Page Up / Page Down | Zeroing distance |
| Q / E | Lean left / right |
| F | Pick up (ammo for your guns and fitting attachments are picked up automatically) |
| 1 / 2, mouse wheel, X | Switch weapon |
| H | Use the best healing item |
| 4 / 5 / 6 | Bandage / medkit / energy drink |
| G | Throw frag grenade |
| M | Full map |
| M then mouse wheel | Zoom the map |
| Esc | Pause menu (sensitivity, volume) |

## Gunplay

- Every bullet is a simulated projectile with muzzle velocity and gravity drop, so long shots need
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

## LAN multiplayer

Everyone must be on the same network (same Wi-Fi or router).

1. One player presses **HOST LAN** in the main menu. The lobby shows the address to share.
2. The others press **JOIN LAN**. The host's game appears in the list; click it, or type the
   host's address and press **JOIN**.
3. The host picks **Squad vs Bots** (everyone on one team, no friendly fire, team mates shown
   on the map with name tags) or **Free-for-all**, then presses **START MATCH**.

Joining players load the host's island automatically. The host runs the bots, the storm, loot
and supply drops. If Windows asks whether to allow the game through the firewall, allow it on
private networks. The game uses UDP ports 24555 (game) and 24556 (LAN discovery).

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

The storm closes in eight phases. It starts slow and weak, so there is time to land and loot,
then each circle gets tighter, faster and more painful. The next safe zone is shown on the map as
soon as it is chosen. Supply drops land during the match. The plane flies at 520 m. Pull the
chute early to glide over 1 km, or dive and pull late to land first.

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
