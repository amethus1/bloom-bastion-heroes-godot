# Bloom Bastion Heroes: Godot 4 version

A rewrite of the browser game (`../bloom-bastion-heroes`) in **Godot 4.7**: a native app with the same heroes, pests, maps, towers and waves, and all three modes (Adventure, Endless and the three-lane **Garden Clash**), plus a six-wave **Short Adventure** and a 12–15 minute **⚡ Quick Clash** made for this version. Up to 4 players can play together over LAN with no browser and no Node server.

## Run it

```bash
godot --path .                 # title screen
godot --path . -- --solo       # jump straight into a solo game with your saved settings
godot -e --path .              # open the project in the Godot editor
```

If the scripts show "unknown class" errors after you pull new files, run `godot --headless --path . --import` once.

New players: press **🌱 Practice Garden** on the title screen. It is a short, easy game with a step-by-step checklist (walk, grab Sun, leap, build, start a wave, pick an evolution, special, upgrade). Winning it offers **▶ Play Sunny Meadow**: a whole game on the same map, with a Bot Buddy. **⏱️ Short Adventure** (Mode on the title screen) is the next step up: six waves in about 8 minutes on any Adventure map. A crowd comes first, then fast Zoom Wasps, Camo pests, armored beetles and a mix of all of them, and the Thornback Toad is the finale. You start with 150 acorns, enough to try a tower's special power. The **📖** button opens the Garden Guide: every hero, tower and reaction, plus a pest book that fills in as you meet pests.

## Builds for other computers

```bash
tools/export_all.sh     # Mac (.zip with the .app), Windows (one .exe) and Linux, into build/
```

It needs Godot 4.7.2's export templates (in Godot: Editor > Manage Export Templates > Download). The builds are not signed by Apple or Microsoft, so the first time:

* **Mac:** unzip, then right-click **Bloom Bastion Heroes.app** and choose **Open** (double-clicking says it can't check the developer).
* **Windows:** if SmartScreen warns, click **More info**, then **Run anyway**.

On Windows and Linux the game uses the bundled Nunito font (`fonts/`, SIL Open Font License). Macs use their built-in Arial Rounded.

## Controls

| Key | What it does |
|---|---|
| WASD / arrows, or click | Walk; clicking finds a way around water and rocks |
| Shift | Leaf Leap (dash) |
| Q / E | Hero special |
| Click ⭐ Evolve (left side bar) | Pick your hero's path upgrade (A or B). With **Level-ups: automatic** (the default) that's all you pick: on hero levels 2, 4, 6, 8, 11 and 14 the hero waits for you, and every other level picks a stat card by itself |
| 1 2 3 | Pick a level-up card (only with **Level-ups: pick every card**) |
| R (cards showing) | New cards: one free at the start and one more per boss chest, then 30 acorns |
| 1 – 9 (no cards waiting), or G | Pick a tower or trap. Its outline shows where it will go |
| F, or click | Build the picked tower. Move the mouse after picking and the outline follows it (up to a short walk from your hero), so a click builds right there; F without moving the mouse builds where you stand. Right-click cancels |
| Right-click a pest | Mark it: every hero and tower in range shoots it first for 6 seconds |
| U / Y | Upgrade the tower you stand next to; at level 2, U or Y picks its special version. Its cost and sell price float above it |
| X | Sell the tower you stand next to |
| Your towers (left side bar) | Every tower you built, with its level and a ⬆ upgrade button. Click one (or click it in the garden) to ring it and see its range, its two special powers at level 2, Sell, and 🚶 Go there. Upgrading and selling still need your hero next to the tower |
| Ctrl + / Ctrl − | Make the HUD bigger or smaller |
| T | Targeting: First, Strongest, Closest or Last pest |
| Space | Start the next wave. The panel above it shows what's coming, plus one tip: what to do about the next wave, or which trail pests got through last wave |
| H | Teleport home |
| P | Pause |
| Esc | Menu: keep playing, restart, sound, or leave to the title screen |
| Tab (hold) | Team stats, your hero's numbers, and which reactions your team can make |
| M | Sound on/off |
| V, then 1–5 | Emotes: Hi!, ❤️, Help!, Nice!, Follow me! |
| Middle-click (or Alt+click) | Ping the map ("Look here!", "Chest!", "Pests here!"…) for everyone |
| N | Hide/show the minimap (click the minimap to walk there) |
| F11 | Fullscreen |
| Z, mouse wheel, + and − | Overview and zoom |

Hover over any tower to see its range. Arrows at the screen edge point to chests, power-ups, pings, bosses and pests near the tree.

### Controllers and couch co-op

Up to 4 players on one computer: press **Start** (or A) on a controller during a game, pick a hero with the D-pad, and press **A**. If the team is full, a Bot Buddy steps aside. The camera zooms out to keep everyone on screen. Couch players work in solo games and on a LAN host.

| Button (Xbox / PlayStation) | What it does |
|---|---|
| Left stick | Walk |
| A / Cross | Leaf Leap |
| X / Square | Special |
| Y / Triangle | Build the picked tower (Garden Clash: Berry Juice) |
| B / Circle | Upgrade the tower you stand next to (Garden Clash: go home) |
| LB / RB | Pick a tower (Garden Clash: LB juice, RB buy the pinned item or the shop's first pick at the tree) |
| D-pad ◀ ▲ ▶ | Pick level-up card 1 / 2 / 3 |
| D-pad ▼ | Home |
| Back / Share | Sell the tower you stand next to |
| R3 | Targeting |
| Start | Start the next wave when the green button shows; otherwise the menu |

On the title screen, **Controllers: Controller 1 = me** lets one kid play solo on a controller.

### Maps, combos and rewards

* **Map gimmicks:** Sunny Meadow sunflowers bloom bonus Sun when you walk past. Lilypad Crossing lily pads give a speed boost. The Starlight Crossroads obelisk charges as pests pop nearby; stand on it when it's full for a Starlight Blast. Maple Hollow leaf piles slow pests when you walk through them. Frosty Glade geysers chill pests by themselves.
* **Team combo invites:** when a friend uses their special near you and yours is ready, your Q button pulses, a line above it says "⚡ Press Q now: ⛈️ STORM SURGE with Lily! 3s", and a circle on the ground (its edge runs down like a timer) shows where to stand. Bot Buddies answer your special the same way, so kids find combos just by playing next to one. Couch players see "⚡ X now: Team Combo!".
* **The build preview tells the truth:** before you spend anything it says what F or a click will really do: "Build Sprout Sentry · 60🌰", "⬆ Upgrade this Sentry to level 2 · 60🌰" (building on top of your own tower of the same kind upgrades it), "Tower limit reached · 5/5" or "Sprout Sentry needs 60🌰 (you have 10)".
* **Auto Wave** waits (up to 12 seconds) while someone picks an evolution, and the Bloom Tree panel shows "⭐ wait".
* **Named team combos:** two heroes using Q close together always make a Team Combo, and these pairs get a signature move on top: Frost Lotus + Boom Shroom 💎 Cryo Nuke, Bubble Lily + Volt Cactus ⛈️ Storm Surge, Snapdragon + Sun Blossom ☀️ Solar Flare, Pea Blaster + Frost Lotus 🌨️ Hailstorm, Boom Shroom + Volt Cactus 💥 Thunderboom, Bubble Lily + Frost Lotus 🧊 Glacier Tide, Boom Shroom + Snapdragon 🎆 Firecracker, Pea Blaster + Sun Blossom 🌻 Sunny Volley.
* **Chests:** boss chests give everyone 2 bonus cards. Golden Beetle chests give a card for the first 5, then XP and acorns, so late games don't snowball.
* **Medals:** winning an Adventure map earns a medal on its card on the title screen (🥉 Easy, 🥈 Normal, 🥇 Hard, 💎 Nightmare).

* **Perfect waves:** clear a wave without losing a life for bonus acorns and XP that grow with your streak.
* **Leaf Leap perks:** Frost Lotus leaves a chilly trail, Snapdragon an ember puff, Bubble Lily a soaking splash, Volt Cactus zaps, Boom Shroom booms, Pea Blaster fires a ring of peas, Sun Blossom drops a little Sun.
* **Endless acorn shop** (wave 5+, above the build bar): 🌳 +1 Tree life (once every 5 waves), ⚡ Overclock (towers 25% faster for a minute), 🎁 Mystery power-up.
* **Level-ups:** on **Automatic** the hero picks its own stat cards and only stops for path upgrades, which wait in the ⭐ Evolve box on the left (hover one for the exact change, e.g. "Damage 39 → 51"). On **Pick every card** small cards pop up over the hero panel with path progress (●●○○); C tucks them away during a busy fight.
* **Kid assist** (⚙ Settings): the Bloom Tree regrows 2 lives after every wave and Sun is easier to grab.
* **Rare cards** from hero level 12 (gold edge): ⚗️ Catalyst Mastery (your reactions +30%), 🔁 Echo Shot (15% of hits echo onto a nearby pest), 🌰 Acorn Magnet (+50% acorns from pops), 🌳 Guardian Roots (your towers near you fire 15% faster).
* **More towers:** 🪴 Bloom Pot (helper: grows acorns and Sun during waves, nearby towers fire 15% faster), 🍯 Sap Pitcher (trap: slows, washes off Camo, fire and blast hit 20% harder), 🌬️ Gust Blossom (blows pests back along the trail every 4 seconds). Each has two level-3 paths like the others.
* **Thornback Toad:** a wave-13 mini-boss, between the first Spore Zeppelin and the double one (in Endless also every 10 waves after). Pests near it take 40% less damage, and its stomp puts towers to sleep: walk past them to wake them.
* **Gifts:** the 🎁 25 button next to a friend's name in the team list sends them 25 acorns.
* **Save and Continue:** solo Adventure and Endless games save after every cleared wave. The title screen shows **⏯ Continue (wave N)**; right-click it to forget the save.
* **🎲 Garden Rules** (title screen, Adventure and Endless): 🌀 Oops! All Twists, 🦸 Hero Mode (no towers but stronger heroes), ⚗️ Reaction Chaos (reactions +50%), ⏩ Turbo Garden. Their icons show next to the Bloom Tree panel during the game.

### Settings and unlocks

The ⚙ button on the title screen (or Esc in a game) has screen shake, damage numbers, graphics, fullscreen, UI size, level-ups, messages and sound. **UI size** (60% to 130%, normally 80%; Ctrl + and Ctrl − in a game) scales every panel and button. **Messages: Fewer** (normal) hides small news like "Sentry built!" and the wave banners; **Only important ones** also hides tips. **Hero chatter** sets how much the announcer and heroes talk: Lots, Some (at most one everyday line every 9 seconds), Big moments only (bosses, the Bloom Tree in danger, combos, the end) or Off. Pop-up messages sit in the bottom-left corner, out of the middle of the screen. **Graphics: Fancy** adds drifting cloud shadows, shimmering ponds and rivers, and glowing shots, sparks and fireflies; **Simple** turns those off for an older computer (`--simple` does the same from the command line). Hats and pets unlock by playing (the title screen shows how to earn each 🔒 one). Everyone in a game earns them on their own computer. **Hats & pets: Unlock everything** is there for little kids.

In Garden Clash:

| Key | What it does |
|---|---|
| B or H | Go home: stand still for 3 seconds. It also asks a teammate to cover your lane while you shop |
| G | "Cover me": ask a teammate to hold your lane. When a friend asks, G says yes |
| 1 / 2 (at a claimed Garden Plot) | Grow a 🫐 Berry Bush or a 🌱 Spring Vine |
| R | Drink a Berry Juice |
| Click the shop | Buy an item at the Bloom Tree. Buying it again makes it Golden |
| 📌 in the shop | Pin an item to buy later. The hero panel counts down to it ("120 more acorns", then "ready! B: go home") |
| F | Buy the pinned item at the tree (RB on a controller buys the pinned item, or else the shop's first pick) |
| Click an item slot | Sell it (only at the tree) |

Stand right next to a knocked-out friend to revive them.

The shop stays small so the minimap stays in view: it shows one thing worth doing next, read from the battle ("⚔️ Stop the raid on the Top Lane!", "⚡ Push the Middle Lane: their gate grows back in 1:20", "🚩 Walk with Captain Clover up the Top Lane"…), the two items that suit your hero best, Berry Juice, and **Browse all items ▸**. Hover an item for its whole description.

**⚡ Quick Clash** (Mode on the title screen or in the LAN lobby) is the whole three-lane battle in about 12–15 minutes: one Thorn Tower before each gate (on both sides), everyone starts with a free item picked for their hero, Pumpkin Cannons march from the first wave, heroes level a little faster, gates grow back more slowly, and raids, Captains and the Elder Toad come sooner. When either Clash mode is picked, the title screen shows Three-Lane Valley instead of the Adventure maps (your Adventure map is kept for when you switch back).

After a Clash, the end screen tells the match in its three biggest moments, in order, e.g. "Beat the Rumble Toad → Broke the Middle Lane gate (Pumpkin Cannon, with Lily & Pea) → Smashed the Thorn Heart". When a Sproutling lands the last hit on a gate, it gets the banner, along with the heroes who walked it there.

The battlefield is a living garden:

* **Garden Plots:** a patch of soil beside each lane. Stand on an empty one for 3 seconds (with no pests close by) to claim it, then grow a **🫐 Berry Bush** (heals heroes and Sproutlings near it) or a **🌱 Spring Vine** (step on it and it flings you about 460 px down the lane toward the pests; marching Sproutlings get a bounce in their step). Pests standing on a plot with no hero near it trample it back to soil in 4 seconds.
* **Cover me:** going home asks a teammate to hold your lane. A Bot Buddy says yes at once and walks to that lane; a friend gets "G: I'll cover the Middle Lane". The top-left corner shows who is holding which lane until you're back out of base.
* **Rival Raids:** after about 2½ minutes, and every couple of minutes after that, two rival champions announce which of your towers they're coming for, 9 seconds before they attack it. The tower pulses red, an arrow points to it, and the minimap shows it. Stop them for 60 acorns and XP each, or push another lane while they're busy. Bot Buddies go to meet a raid.
* **Sproutling Captains:** every 4th wave (from the 2nd) a named Bud Buddy (Captain Clover, Basil…) with a banner and 3½ times the health leads the lane with the most heroes in it. Walk with it: if it gets close to a Thorn Tower it plants a **rally flag**, and for 20 seconds Sproutlings near the flag hit 50% harder and take 30% less damage. A Bot Buddy walks with the Captain too.
* **Tower lock-on:** a red dashed line runs from a Thorn Tower to the hero it's shooting, with 1, 2, then 3 warning thorns over that hero's head (each shot in a row hurts more). At three: "Step back!"

## Playing together on the LAN

1. One computer presses **Host LAN Game**. The lobby shows its address (with a Copy button), for example `192.168.1.20`. The host can still change the map, difficulty, mode and bots there, and everyone can switch hero, hat and pet before the game starts. Friends press **I'm ready!** (the host's Start button counts them; the host can start any time).
2. The other computers press **Join LAN Game**. Games on the same Wi-Fi appear in the list automatically (UDP beacon on port 24681). You can also type the address.
3. The host presses **Start Game**. Friends can still join a game that has already started.

If a friend's Wi-Fi drops, their game keeps trying to reconnect for a minute or so ("📶 Lost the host. Reconnecting…"). Meanwhile their hero stays in the game with 📶 by their name, and a Bot Buddy walks it and fights but leaves their cards and acorns alone. When they get back (or join again later from the same computer with the same name) they get the same hero back: level, cards, acorns and towers. In the lobby, a ✨ **Great Team Combo!** line shows when the heroes picked can make reactions together.

The game uses UDP ports **24680** (ENet game traffic) and **24681** (discovery). The first time you host, macOS may ask whether Godot can accept incoming connections. Say Allow.

## How it is built

| Folder | What is in it |
|---|---|
| `data/` | JSON exported from `shared/constants.js` by `npm run export-data` in the Node project, so balance numbers stay in one place |
| `autoload/game_data.gd` | Loads the JSON. Map walking, A* paths, hero and tower stats, wave plans (`GameData`) |
| `autoload/sprites.gd` | Sprite sheets plus `atlas.json` (`Sprites`) |
| `sim/sim_world.gd` | The whole Adventure/Endless game as a fixed 30 Hz simulation: heroes, pests, elements and reactions, specials, combos, towers, Sun, chests, power-ups, Endless twists and Bot Buddies. It draws nothing, so it runs headless |
| `sim/clash_world.gd` | Garden Clash (extends SimWorld): lanes, Sproutling waves, Bloom and Thorn buildings with shields and regrowing gates, rivals and their abilities, jungle camps and Toad Power, hero health, knock-outs and revives, recall, the shop, and the Clash Bot Buddies |
| `net/game_host.gd` | Steps the sim and applies player actions (solo, or on the LAN host) |
| `net/net_host.gd`, `net_client.gd` | ENet LAN play. Channel 0 is reliable (lobby, actions); channel 1 is unreliable-ordered (walking, snapshots at 20 Hz, zstd-compressed, about 5 KB in a big wave) |
| `net/lan_finder.gd` | Listens for host beacons |
| `render/world_view.gd` | Draws a snapshot: map, depth-sorted sprites, hats and pets, effects, damage numbers, camera with smoothing and shake. Glows and sparks go on a separate additive-blended layer (`LightLayer`); `render/ground.gdshader` adds cloud shadows and finds water by colour to make it shimmer. Dots, shadows, rings, bars and trails all come from one small generated texture, and pests draw in layers (ground, bodies, overlay), so a 260-pest fight stays near 100 fps. Things off screen are skipped. A LAN friend sees everyone ~2 snapshots in the past, glided between time-stamped snapshots, so uneven Wi-Fi doesn't stutter |
| `sim/save_game.gd` | Save and Continue for solo games (`user://autosave.save`) |
| `sim/map_features.gd` | One gimmick per Adventure map |
| `ui/` | HUD, menus (title, Garden Rules, Garden Guide, settings) and lobby, save profile (`user://profile.cfg`), shared theme |
| `main.gd` | Game flow and local input. Your walking is predicted locally so it feels instant |
| `art/` | Every sprite drawn by the real browser renderer and exported as PNG strips. The Bloom Pot, Sap Pitcher and Gust Blossom pictures and the app icon are drawn by `tools/gen_gadget_art.py` and `tools/gen_icon.py` |
| `fonts/` | Nunito (SIL Open Font License), used on Windows and Linux |
| `tools/` | `run_tests.sh`, `export_all.sh`, and the art/audio generators |
| `.github/workflows/tests.yml` | GitHub runs every test suite on each push |

### Re-exporting the art or data after changing the browser game

```bash
cd ../bloom-bastion-heroes && npm run export-data && cp export/data/*.json ../bloom-bastion-heroes-godot/data/
cd ../bloom-bastion-heroes && node tools/sprite-server.js   # then open http://localhost:3011 and press "Export all"
```

Careful: some things exist only in this Godot version and are not in the browser game's export: the Thornback Toad (`thorntoad` in `data/enemies.json`), the Bloom Pot, Sap Pitcher and Gust Blossom (`pot`, `sap`, `gust` in `data/gadgets.json`, including `order` and `costs`), and their `atlas.json` entries (run `python3 tools/gen_gadget_art.py` again). Copy those back in after re-exporting.

## Tests (all headless)

```bash
tools/run_tests.sh            # every suite below, one line each (about 4 minutes); "quick" skips the whole-game ones
```

Or one at a time:

```bash
godot --headless --path . -s tests/test_data.gd    # hero stats, XP curve and waves match the JS game exactly
godot --headless --path . -s tests/test_sim.gd -- meadow normal adventure frostlotus,snapdragon   # bots play a whole game
godot --headless --path . -s tests/test_rules.gd   # 2x speed = 1x per game-second, frostbite vs burn, wisps, targeting
godot --headless --path . -s tests/test_play.gd    # real key presses: walk, leap, build, cards... plus Clash shop, juice, recall, revive, win
godot --headless --path . -s tests/test_clash.gd -- hard boomshroom,bubblelily 3 idle   # bots play whole Garden Clash games
godot --headless --path . -s tests/test_clash.gd -- normal boomshroom,bubblelily 1 quick  # ...or Quick Clash (prints the match story too)
godot --headless --path . -s tests/test_net.gd     # snapshot packets round-trip and stay small
godot --headless --path . -s tests/test_smooth.gd  # LAN friends see even motion through Wi-Fi jitter; pause holds; dash slides; facing doesn't flicker
godot --headless --path . -s tests/test_soak.gd    # 8 games across every map and mode: no script errors, memory flat (add `-- soak repeat` for 8x the same game)
godot --headless --path . -s tests/test_save.gd    # save after a wave, Continue on the title screen, everything put back
godot --headless --path . -s tests/test_rejoin.gd  # a dropped LAN friend's hero is kept and handed back
godot --headless --path . -s tests/test_features.gd # aiming, marks, rerolls, rare cards, new towers, Thornback Toad, Garden Rules, gifts, Practice, Guide, UI size, messages, Your towers, automatic level-ups
```

LAN test: run a host and a client on one computer.

```bash
godot --headless --path . -- --host --bind=127.0.0.1 --autostart=1 --netcheck=11 &
godot --headless --path . -- --join=127.0.0.1 --hero=sunblossom --netcheck=8
```

Each prints a `NETCHECK {...}` line: players, wave, how far the client's hero walked on the host, and packets received. Add `--dropat=7` to the client to pretend its Wi-Fi drops 7 seconds in: its line then has `drop` with the hero's level before and after reconnecting. Add `--mode=clash` to the host to test Garden Clash, where the client also buys an item. Run the client in a window with `--max-fps 60` and its line also has `smooth`: how evenly pests move from frame to frame (`avg_off_pct` about 7 now; add `--nointerp` to see the old blending, about 70).

### Garden Clash balance check

`test_clash.gd ... idle` adds a player who stands at the tree, the same setup as the Node balance oracle (`node tools/sim.js clash hard 2 valley boomshroom,bubblelily`). Recent runs:

| Difficulty (2 bots + idle) | Godot | Node |
|---|---|---|
| Easy | 18–31 min, avg 24 | 22–27 min, avg 25 |
| Normal | 20–27 min | 17–29 min |
| Hard | 48–68 min, bots win about 3 in 8 | 47–63 min, bots win about 2 in 13 |

Other test flags: `--demo` (you are a bot too), `--warp=SECONDS` (fast-forward), `--shot=file.png --shot-after=3 --quit` (screenshot), `--perflog` (every second: fps, worst frame, draw calls, memory, and milliseconds per frame for the sim, world drawing, HUD drawing and rendering). A big late-game check: `--demo --map=courtyard --mode=endless --bots=3 --wave=40 --warp=8 --perflog`.

## Not ported yet

- Touch controls.
- Shaders and lights.
