# Bloom Bastion Heroes: Godot 4 version

A rewrite of the browser game (`../bloom-bastion-heroes`) in **Godot 4.7**: a native app with the same heroes, pests, maps, towers and waves, and all three modes (Adventure, Endless and the three-lane **Garden Clash**). Up to 4 players can play together over LAN with no browser and no Node server.

## Run it

```bash
godot --path .                 # title screen
godot --path . -- --solo       # jump straight into a solo game with your saved settings
godot -e --path .              # open the project in the Godot editor
```

If the scripts show "unknown class" errors after you pull new files, run `godot --headless --path . --import` once.

## Controls

| Key | What it does |
|---|---|
| WASD / arrows, or click | Walk; clicking finds a way around water and rocks |
| Shift | Leaf Leap (dash) |
| Q / E | Hero special |
| 1 2 3 | Pick a level-up card |
| 1 – 6 (no cards waiting), or G | Pick a tower or trap. Its outline shows where it will go |
| F | Build the picked tower where you stand |
| U / Y | Upgrade the tower you stand next to; at level 2, U or Y picks its special version. Its cost and sell price float above it |
| X | Sell the tower you stand next to |
| T | Targeting: First, Strongest, Closest or Last pest |
| Space | Start the next wave (the panel above it shows what's coming) |
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
| LB / RB | Pick a tower (Garden Clash: LB juice, RB buy the next item at the tree) |
| D-pad ◀ ▲ ▶ | Pick level-up card 1 / 2 / 3 |
| D-pad ▼ | Home |
| Back / Share | Sell the tower you stand next to |
| R3 | Targeting |
| Start | Menu |

On the title screen, **Controllers: Controller 1 = me** lets one kid play solo on a controller.

### Maps, combos and rewards

* **Map gimmicks:** Sunny Meadow sunflowers bloom bonus Sun when you walk past. Lilypad Crossing lily pads give a speed boost. The Starlight Crossroads obelisk charges as pests pop nearby; stand on it when it's full for a Starlight Blast. Maple Hollow leaf piles slow pests when you walk through them. Frosty Glade geysers chill pests by themselves.
* **Named team combos:** two heroes using Q close together always make a Team Combo, and these pairs get a signature move on top: Frost Lotus + Boom Shroom 💎 Cryo Nuke, Bubble Lily + Volt Cactus ⛈️ Storm Surge, Snapdragon + Sun Blossom ☀️ Solar Flare, Pea Blaster + Frost Lotus 🌨️ Hailstorm, Boom Shroom + Volt Cactus 💥 Thunderboom, Bubble Lily + Frost Lotus 🧊 Glacier Tide, Boom Shroom + Snapdragon 🎆 Firecracker, Pea Blaster + Sun Blossom 🌻 Sunny Volley.
* **Chests:** boss chests give everyone 2 bonus cards. Golden Beetle chests give a card for the first 5, then XP and acorns, so late games don't snowball.
* **Medals:** winning an Adventure map earns a medal on its card on the title screen (🥉 Easy, 🥈 Normal, 🥇 Hard, 💎 Nightmare).

* **Perfect waves:** clear a wave without losing a life for bonus acorns and XP that grow with your streak.
* **Leaf Leap perks:** Frost Lotus leaves a chilly trail, Snapdragon an ember puff, Bubble Lily a soaking splash, Volt Cactus zaps, Boom Shroom booms, Pea Blaster fires a ring of peas, Sun Blossom drops a little Sun.
* **Endless acorn shop** (wave 5+, above the build bar): 🌳 +1 Tree life (once every 5 waves), ⚡ Overclock (towers 25% faster for a minute), 🎁 Mystery power-up.
* **Level-up cards** show path progress (●●○○) and the exact change ("Damage 39 → 51"). C tucks them away during a busy fight.
* **Kid assist** (⚙ Settings): the Bloom Tree regrows 2 lives after every wave and Sun is easier to grab.

### Settings and unlocks

The ⚙ button on the title screen (or Esc in a game) has screen shake, damage numbers, fullscreen and sound. Hats and pets unlock by playing (the title screen shows how to earn each 🔒 one). Everyone in a game earns them on their own computer. **Hats & pets: Unlock everything** is there for little kids.

In Garden Clash:

| Key | What it does |
|---|---|
| B or H | Go home: stand still for 3 seconds |
| R | Drink a Berry Juice |
| Click the shop | Buy an item at the Bloom Tree. Buying it again makes it Golden |
| Click an item slot | Sell it (only at the tree) |

Stand right next to a knocked-out friend to revive them.

## Playing together on the LAN

1. One computer presses **Host LAN Game**. The lobby shows its address (with a Copy button), for example `192.168.1.20`. The host can still change the map, difficulty, mode and bots there, and everyone can switch hero, hat and pet before the game starts. Friends press **I'm ready!** (the host's Start button counts them; the host can start any time).
2. The other computers press **Join LAN Game**. Games on the same Wi-Fi appear in the list automatically (UDP beacon on port 24681). You can also type the address.
3. The host presses **Start Game**. Friends can still join a game that has already started.

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
| `render/world_view.gd` | Draws a snapshot: map, depth-sorted sprites, hats and pets, effects, damage numbers, camera with smoothing and shake. Dots, shadows, rings, bars and trails all come from one small generated texture, and pests draw in layers (ground, bodies, overlay), so a 260-pest fight stays near 100 fps. Things off screen are skipped. A LAN friend sees everyone ~2 snapshots in the past, glided between time-stamped snapshots, so uneven Wi-Fi doesn't stutter |
| `ui/` | HUD, menus and lobby, save profile (`user://profile.cfg`), shared theme |
| `main.gd` | Game flow and local input. Your walking is predicted locally so it feels instant |
| `art/` | Every sprite drawn by the real browser renderer and exported as PNG strips |

### Re-exporting the art or data after changing the browser game

```bash
cd ../bloom-bastion-heroes && npm run export-data && cp export/data/*.json ../bloom-bastion-heroes-godot/data/
cd ../bloom-bastion-heroes && node tools/sprite-server.js   # then open http://localhost:3011 and press "Export all"
```

## Tests (all headless)

```bash
godot --headless --path . -s tests/test_data.gd    # hero stats, XP curve and waves match the JS game exactly
godot --headless --path . -s tests/test_sim.gd -- meadow normal adventure frostlotus,snapdragon   # bots play a whole game
godot --headless --path . -s tests/test_rules.gd   # 2x speed = 1x per game-second, frostbite vs burn, wisps, targeting
godot --headless --path . -s tests/test_play.gd    # real key presses: walk, leap, build, cards... plus Clash shop, juice, recall, revive, win
godot --headless --path . -s tests/test_clash.gd -- hard boomshroom,bubblelily 3 idle   # bots play whole Garden Clash games
godot --headless --path . -s tests/test_net.gd     # snapshot packets round-trip and stay small
godot --headless --path . -s tests/test_smooth.gd  # LAN friends see even motion through Wi-Fi jitter; pause holds; dash slides; facing doesn't flicker
godot --headless --path . -s tests/test_soak.gd    # 8 games across every map and mode: no script errors, memory flat (add `-- soak repeat` for 8x the same game)
```

LAN test: run a host and a client on one computer.

```bash
godot --headless --path . -- --host --bind=127.0.0.1 --autostart=1 --netcheck=11 &
godot --headless --path . -- --join=127.0.0.1 --hero=sunblossom --netcheck=8
```

Each prints a `NETCHECK {...}` line: players, wave, how far the client's hero walked on the host, and packets received. Add `--mode=clash` to the host to test Garden Clash, where the client also buys an item. Run the client in a window with `--max-fps 60` and its line also has `smooth`: how evenly pests move from frame to frame (`avg_off_pct` about 7 now; add `--nointerp` to see the old blending, about 70).

### Garden Clash balance check

`test_clash.gd ... idle` adds a player who stands at the tree, the same setup as the Node balance oracle (`node tools/sim.js clash hard 2 valley boomshroom,bubblelily`). Recent runs:

| Difficulty (2 bots + idle) | Godot | Node |
|---|---|---|
| Easy | 18–31 min, avg 24 | 22–27 min, avg 25 |
| Normal | 20–27 min | 17–29 min |
| Hard | 48–68 min, bots win about 3 in 8 | 47–63 min, bots win about 2 in 13 |

Other test flags: `--demo` (you are a bot too), `--warp=SECONDS` (fast-forward), `--shot=file.png --shot-after=3 --quit` (screenshot), `--perflog` (every second: fps, worst frame, draw calls, memory, and milliseconds per frame for the sim, world drawing, HUD drawing and rendering). A big late-game check: `--demo --map=courtyard --mode=endless --bots=3 --wave=40 --warp=8 --perflog`.

## Not ported yet

- Touch controls and the pet unlock rules.
- Shaders and lights, and exported macOS/Windows app builds (an export preset plus export templates).
