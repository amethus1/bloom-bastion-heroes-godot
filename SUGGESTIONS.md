# Bloom Bastion Heroes (Godot 4) — Comprehensive Analysis & Improvement Roadmap

This document compiles a deep technical, UX, balance, and feature audit of **Bloom Bastion Heroes** (`bloom-bastion-heroes-godot`), along with prioritized recommendations to take the game from a solid playable port to a standout co-op experience.

---

## Progress (Nov 16)

**Done**
* 1.1 Burn at 2x speed: 2x now runs two normal-size ticks, so every per-tick rule (burn rounding included) matches 1x per game-second. 1x balance unchanged. (`tests/test_rules.gd`)
* 1.2 Frostbite has its own `frost_*` fields: it no longer replaces a burn, OVERLOAD works again, and frostbitten pests drip ice instead of fire.
* 1.3 Build preview: picking a tower (G, 1–6 or the build bar) shows its outline for 3 s; F shows it again briefly. 1.4 Ranges are true circles.
* 1.5 Targeting: T key, a `🎯 Target` pill above the hero bar, and a `target` action over LAN.
* 1.6 Snapdragon wisps use the hero's current stats.
* 1.7 Game-changing events go over the reliable LAN channel. A friend joining a full game replaces a Bot Buddy.
* 1.8 `test_play.gd` waits for sim ticks; `test_data.gd` no longer leaks.
* 2.2 Keys 1–6 pick towers when no cards are waiting.
* 3.1 Boss health bar (with Dread Monarch's 50% notch), enraged glow and banner.
* 3.2 Golden ring, range and `U upgrade · X sell` prompt on your nearest tower; range on hover for any tower.
* 3.3 Next-wave preview (pests, counts, resists, twist, hover for details) and a "New pest!" card on intro waves and boss waves.
* 3.4 Hold Tab: team scoreboard, hero stats, reaction guide.
* 3.5 Esc pause menu (Resume / Restart / Sound / Leave). Host-only buttons are hidden on LAN clients. Active buff timers.
* 3.6 Resist badges show their element icon.
* 3.8 Difficulty and mode descriptions on the title screen.
* 3.9 Build bar tooltip follows the hovered tower; `Build n/5`; pests-left counter; auto-wave countdown; no cut-off hero text; twist box fits its text; tier-3 cards warn they lock the other path.
* 4.1 Sound effects and voice lines (done in another session).
* 2.3 / 2.5 Controllers and couch co-op: drop-in local players (Start, pick a hero, A), full controller mapping, camera framing, mini HUD panels, "Controller 1 = me" option. (No rebinding screen yet.)
* 2.4 / 3.8 Settings: screen shake, damage numbers, fullscreen (F11), "unlock everything"; ⚙ on the title screen and in the Esc menu.
* 3.5 / 4.3 Adventure minimap (click to walk, N hides it) and edge arrows for chests, power-ups, pings, bosses, pests near the tree.
* 3.7 Evolution fanfare at tier 3/4, team awards on the end screen, "Next challenge →" after a win.
* 3.10 / 9.1 LAN: switch hero/hat/pet in the lobby, host changes map/difficulty/mode/bots live, Copy-address button, richer game list (difficulty, mode, wave), Refresh + firewall tip. 9.2 shots extrapolate by the real snapshot gap; a small "LAN: N updates a second" note on clients.
* 7.1 Emotes (V, 1–5) and map pings (middle-click / Alt+click), sent reliably.
* 1.6 / 5.4 Sun Blossom Golden Harvest: shares 50% base, +30%/+40% at tier 3/4 (removing the floor outright would have left her sharing nothing before tier 3); Solar Beam = 6x her damage and heals (every 3rd beam +1 Bloom Tree life; heroes in Clash).
* 6.1 Balance: 4-trail maps ramp team toughness more gently and top out 20% lower; Golden Beetle chests give cards for the first 5 then XP + acorns (boss chests keep 2 cards). Tapering boss chests too made Hard Meadow unwinnable for a duo, so that part was dropped.
* 5.1 Eight named team combos on top of the Team Combo blast (tested in `tests/test_rules.gd`).
* 5.2 One light gimmick per Adventure map (`sim/map_features.gd`).
* 3.8 Title screen: live animated hero + hat + pet preview, map thumbnail cards with medals; Controllers option moved to Settings.
* 3.10 / 9.1 Lobby Ready toggle (✅/⏳, host's Start shows "n/m ready").
* 4.3 Ambient particles per map (pollen, sparkles, fireflies, maple leaves, snow, petals) and a soft vignette; drawn acorn/tree/pause icons for the always-visible HUD (other icons are still emoji).
* 6.3 Perfect-wave streak bonus; Kid assist option (tree regrows 2 lives a wave, 1.5x Sun grab range).
* 6.2 Smarter Bot Buddies: wake sleeping towers, target the strongest pest while bosses are out, Seed Bomb pests close to the tree. (Hard Maple Hollow went from mostly losing around wave 15 to reaching waves 25-30.)
* 5.7 Telegraphs: Healer Moth tethers, Snoozy Moth sleep-dust range, mole dirt; 3.6 ice-crystal frozen look and status pips (soaked, sunlit, frostbite, poisoned, trapped); 4.3 the Bloom Tree drops petals when hurt and blossoms when it gains lives.
* 3.9 Level-up cards: path pips, exact stat changes, tuck away with C.
* 5.4 Leaf Leap perks for every hero.
* 5.5 Endless acorn shop (life / overclock / mystery power-up).
* 8.3 First-time tips (each shows once per computer).
* 8.1 Hats & pets unlock by playing (per computer, everyone in the game earns them), 🔒 items show how to earn them, new unlocks are listed on the end screen.
* 10 Garden Clash is ported.
* 11.4 Rendering speed: a 260-pest Endless wave-40 fight went from ~50 to ~95–100 fps (draw calls 1,900 → 800). All dots, shadows, rings, bars and trails come from one generated texture; pests draw in ground/body/overlay layers; off-screen things are skipped; particles and damage numbers are capped. Pest and tower sheets preload in the background at the title screen so new pests don't hitch. `--perflog` prints the per-frame breakdown.
* 9.2 LAN smoothness: friends see everyone ~2 snapshots in the past, glided between time-stamped snapshots. In a real 2-process LAN game, frame-to-frame pest motion went from ~73% to ~7% off even (`tests/test_smooth.gd`, and the `smooth` field of `--netcheck`).
* Smooth animation: your own dash zips over 0.14 s instead of blinking; pests fade and grow in, pop with a bright flash of their picture when defeated, and no longer flicker left/right when walking up or down; towers spring up when built and bounce when upgraded.
* Stability: 8-game soak test (`tests/test_soak.gd`) with flat memory; closing the window or Quit stops every sound first, so exit is leak-free (10 of 10 windowed runs clean); removed the 2D MSAA setting the Compatibility renderer ignores (its startup warning is gone).
* 9.2 Graceful rejoin: a dropped friend's client reconnects on its own for about a minute; the host keeps their hero (a Bot Buddy walks and fights, but leaves cards and acorns alone) and hands it back, matched by a per-computer key + name. Tested in a real 2-process LAN game (`--dropat`) and `tests/test_rejoin.gd`.
* 6.3 Save & resume: solo Adventure/Endless games save after every cleared wave; ⏯ Continue on the title screen (`tests/test_save.gd`). Garden Rules: Oops! All Twists, Hero Mode, Reaction Chaos, Turbo Garden.
* 5.8 Towers follow the mouse after picking (within 170 px of the hero) and a click builds there; right-click a pest to mark it for every hero and tower for 6 s.
* 5.6 Card rerolls (1 free, +1 per boss chest, then 30 acorns; R) and four rare capstone cards from level 12.
* 5.7 Bloom Pot, Sap Pitcher and Gust Blossom (with art in the same style, `tools/gen_gadget_art.py`); the Thornback Toad mini-boss on wave 13 (wave 15 already has two Spore Zeppelins).
* 7.2 Gift 25 acorns from the team list; "Great Team Combo!" line in the LAN lobby.
* 8.3 Practice Garden (guided checklist game); 8.2 Garden Guide (heroes, towers, reactions, and a pest book that fills in as you meet pests).
* 4.7 Graphics & smoothness: cloud shadows drift over every map and ponds/rivers shimmer (one shader, water found by colour); shots, sparks, explosions, level-up columns, Sun orbs, fireflies and burning pests glow (additive light layer); pests squash when hit and pop in a puff of smoke with twinkles; towers bounce and flash as they fire and sway a little; health bars slide down leaving a pale "just lost" strip; pop-up numbers rise, drift apart and slow; heroes' name tags stack instead of overlapping; river sparkles sit on the water. HUD: level-up cards slide in one by one, XP / tree / boss bars and the acorn counter glide, the end screen and pause menu pop in, toasts slide up, banners pop, confetti on a win, a fade from dark when a game or the title starts, and the camera starts on your hero. A hero's next evolution sheets load in the background. **Graphics: Fancy / Simple** setting. (Heaviest wave-30 fight: about 105 fps Fancy, 108 Simple.)
* 4.8 Less in the way: **UI size** setting (60–130%, normally 80% of the old size; Ctrl + / Ctrl −), with the hero panel moving on top of the build bar when a big size leaves no room beside it. Pop-up messages moved to a small stack in the bottom-left (wrapped, at most 3, repeats count up "×2"); smaller banners under the boss bars; the announcer line sits under them too. **Messages: All / Fewer / Only important ones** and a 4-step **Hero chatter** (Lots / Some / Big moments only / Off; "Some" allows one everyday line every 9 s). **Your towers** side bar: every tower with its level and a ⬆ upgrade button, click (or click it in the garden) to ring it, show its range, pick its level-3 special power, sell it or walk there; upgrading and selling still need your hero next to it, now also checked by the host. **Level-ups: Automatic** (default): stat cards pick themselves; on hero levels 2, 4, 6, 8, 11, 14 the path upgrade waits in a small ⭐ Evolve box in the side bar. "Pick every card" keeps the cards, now about half the size.
* 4.9 From the design review: number keys pick towers while the cards are tucked away (C); a controller's Start starts the wave when the green button shows; Practice graduates to "▶ Play Sunny Meadow" with a Bot Buddy; end-screen awards put Lifesaver / Combo Buddy / Reaction Master first and give everyone one before anyone gets two; the Thornback Toad's card leads with "Walk by sleeping towers to wake them!"; new Garden Guide pages share one counting line; Auto Wave waits for evolution picks. **Build preview shows the real outcome** (build / upgrade this one / max level / tower limit / not enough acorns), checked in the same order as the game. **Team combo invites**: a friend's special opens a 3-second window that the HUD (pulsing Q, "Press Q now: STORM SURGE with Lily!"), the ground (timer circle) and couch panels show, and Bot Buddies answer it. **Between-wave tip** in the next-wave panel: which trail pests got through ("2 Zoom Wasps got through on the trail from the top-left"), or what to do about a boss, Camo, armor or a resist. **⏱️ Short Adventure**: 6 hand-made waves (crowd, wasps, Camo, armor, everything, Thornback Toad finale) with 150 starting acorns. Bot duos win it in about 2.5 game-minutes of fighting; human playtests should judge the difficulty.
* 4.10 Garden Clash as a living garden (the top five from the Clash ideas list): **Thorn Tower lock-on** (dashed line + 1/2/3 warning thorns + "Step back!"), **Cover me** handoffs (recalling or G asks; Bot Buddies accept and switch lanes; friends accept with G; status chips top-left), **Rival Raids** (two rivals, 9 s warning, path-finding to the target tower, +60 acorns when stopped, bots defend), **Garden Plots** (claim, then Berry Bush or Spring Vine; pests trample unguarded plots; bots tend their lane's plot), **Sproutling Captains** (named, bannered, a bot escorts, a rally flag near Thorn Towers). In a 25-minute bot game: about 7 plots claimed, 16 cover handoffs, 6 raids, and Captains every 4th wave.
* 4.11 Garden Clash, next round (from the design review and the Clash ideas list): the title screen shows **Three-Lane Valley** (picture, goal, expected length) instead of Adventure maps when a Clash mode is picked, and the LAN lobby hides its map list. **Smaller shop** that keeps the minimap in view: one lane goal read from the battle (raid, a building in trouble, the Thorn Heart open, a gate about to regrow, the Captain, the weakest pest building), two items picked for your hero, Berry Juice, "Browse all items". **📌 Pin an item** (#39): the hero panel counts down to it, "ready! B: go home", then F (or RB) buys it at the tree. **⚡ Quick Clash** (#44): one tower before each gate, a free first item, siege from wave 1; bot duos win it in 11–17 minutes (full Clash: about 23). **Match story** on the end screen (#43) and a banner for the Sproutling that breaks a gate, with the heroes who walked it there (#18).
* Painted art: all seven heroes and their upgrade forms, then the whole garden (maps, pests, towers, Clash buildings, pets, hats, pickups, shots, menus) were redrawn in one painted style. Big things (the Bloom Tree, Garden Clash towers and Thorn buildings) fade see-through while a hero stands behind them.
* 11.3 Mac/Windows/Linux export presets (`tools/export_all.sh`), app icon, bundled Nunito font for Windows/Linux. 11.2 `tools/run_tests.sh` and a GitHub Actions workflow that runs every suite.

**Left alone on purpose:** the 1.6 Sun Blossom share/Solar Beam and Mega-Pea knockback items are the browser original's own behavior and tuning, so changing them is a design choice. The same goes for the §6 balance items (Courtyard, chests).

---

## Table of Contents
1. [Critical Bugs & Simulation Fixes](#1-critical-bugs--simulation-fixes)
2. [Controls, Input & Accessibility](#2-controls-input--accessibility)
3. [HUD, Combat Readability & UI/UX](#3-hud-combat-readability--uiux)
4. [Audio, Juice & Visual Polish](#4-audio-juice--visual-polish)
5. [Gameplay Depth, Heroes & Towers](#5-gameplay-depth-heroes--towers)
6. [Balance, Maps & Bot AI](#6-balance-maps--bot-ai)
7. [Co-op & Social Features](#7-co-op--social-features)
8. [Meta-Progression, Unlocks & Onboarding](#8-meta-progression-unlocks--onboarding)
9. [LAN Networking & Lobby Experience](#9-lan-networking--lobby-experience)
10. [Porting Garden Clash](#10-porting-garden-clash)
11. [Engineering, Testing & Distribution](#11-engineering-testing--distribution)
12. [Recommended Roadmap](#12-recommended-roadmap)

---

## 1. Critical Bugs & Simulation Fixes

These are real bugs directly observed in the simulation, rendering, input, and test suite.

### 1.1 Burn DoT Rounding & `2x` Speed Bug
* **Where:** `sim/sim_world.gd` → `update_enemies()` (around `burn_t` / `burn_dps`), `apply_damage()` (`maxf(1.0, round(dmg))`).
* **Problem:** Poison correctly accumulates fractional damage in `poison_acc` until `>= 3`, whereas Burn calls `apply_damage(e, e.burn_dps * dt, ...)` every 30 Hz tick. Because `apply_damage` clamps `maxf(1.0, round(dmg))`, **any** `burn_dps < 45` deals a flat `1` damage per tick = **30 DPS minimum** at `1x` speed. At `2x` speed (`dt = 1/15`), base burn (`9 DPS`) still rounds to `1` per tick = **15 DPS** — cutting burn damage in half on `2x` speed.
* **Fix:** Add `burn_acc` using the exact same accumulator pattern as `poison_acc`.

### 1.2 Frostbite Overwrites Burn & Breaks `OVERLOAD`
* **Where:** `sim/sim_world.gd` → `apply_frost()` and `reaction_mult()`, `render/world_view.gd` → `draw_enemy()`.
* **Problem:** Frost Lotus's `frostDot` writes into `e.burn_dps`, `e.burn_t`, and `e.burn_tower`. If Frost Lotus and Snapdragon attack the same enemy:
  * `e.burn_tower` becomes Frost Lotus (`"ice"`), which silently prevents Volt Cactus from triggering `OVERLOAD` (`element_of(e.burn_tower) != "ice"`).
  * `snapshot()` reports `"burning": e.burn_t > 0`, causing `WorldView` to emit orange fire particles on frostbitten enemies.
* **Fix:** Give `frost_dot` / `frost_t` its own fields (accumulated separately, blocking `regen` cleanly, and rendering icy mist particles instead of fire).

### 1.3 `G` Key Cycles Towers *While* Being Held for Placement Preview
* **Where:** `main.gd` → `_process()` (`world.ghost`) and `_unhandled_input()` (`KEY_G`).
* **Problem:** Pressing `G` immediately cycles `selected_gadget` to the next tower, while `world.ghost` only appears while holding `G`. You cannot preview where your currently selected tower will be placed without switching away from it.
* **Fix:** Separate selection from preview:
  * Option A: Show a subtle placement ghost whenever a tower is selected, or toggle build-preview mode with `B` / `G` vs cycling with `Tab`/`MouseWheel`/`1–6` when not picking cards.
  * Option B: `G` cycles towers, and **holding `F`** previews the placement ghost (building on release, or right-click to cancel).

### 1.4 Tower Range Rings Lie Vertically (`* 0.62`)
* **Where:** `render/world_view.gd` → `_draw()` (ghost preview) and `draw_gadget()` (Frost Fern pulse).
* **Problem:** `SimWorld` checks circular Euclidean distance for all towers (`dist(e.x, e.y, g.x, g.y) <= range`), and hero range rings draw true circles. However, the tower ghost and Frost Fern draw `ellipse(..., def.range, def.range * 0.62, ...)`, visually under-reporting vertical range by 38%.
* **Fix:** Draw true circles (`ry = range`) so visual range matches gameplay hitboxes 1:1.

### 1.5 Targeting Mode (`first` / `strong` / `close` / `last`) Is Unreachable
* **Where:** `sim/sim_world.gd` → `pick_target()` & `snapshot()` (`targetMode`); missing in `net/game_host.gd`, `main.gd`, and `ui/hud.gd`.
* **Problem:** The sim already implements 4 targeting priorities, and snapshots already transmit `targetMode`, yet there is no keybind, action, or HUD button to change it. Boss-killer builds (e.g., Pea Blaster Solar Railgun or Boom Shroom Titan Buster) are permanently stuck on `"first"`.
* **Fix:** Add `"target"` action in `GameHost.apply()`, bind `T` (or `R`) in `main.gd`, and add a clickable pill on the HUD hero bar (`Target: First / Strong / Close / Last`).

### 1.6 Hero Ability Bugs
* **Sun Blossom `shareRatio` clamping** (`sim/sim_world.gd` → `sunblossom_extras()`): `maxf(0.5, D.gnum(st, "shareRatio"))` forces 50% share from Level 1, making Path A3 (`0.3`) and A4 (`0.4`) share values dead numbers.
* **Sun Blossom `solarBeam`** (`sunblossom_extras()`): Deals `110 * (1 + 0.05 * (t.level - 1))` unscaled by `st.damage`, Power Bloom cards, or difficulty, and performs **no healing** despite `data/heroes.json` promising `"healing Sunbeams!"`. Make it scale with `st.damage` (e.g., `st.damage * 6`) and restore a small Bloom Tree shield or heal nearby heroes/progress toward a life heal.
* **Pea Blaster Mega-Pea Knockback** (`update_projectiles()`): Subtracts fixed `0.14` from normalized segment `t` (pushing 84 px on long segments and 8 px on short corners) instead of calling `push_back(e, p.knockback)`.
* **Snapdragon Wisps Static Stats** (`sync_wisps()`): Only called inside `pick_card()`, so wisp damage and range do not update on level-ups or temporary buffs (e.g., Giant Mode) until the next card is picked. Recompute or sync wisps whenever `h._st` is invalidated.

### 1.7 Unreliable Delivery of Critical LAN Events & Late-Join Overflow
* **Where:** `net/net_host.gd` → `_process()`, `_on_packet()`.
* **Problem:**
  * Snapshots and `s.events` are sent via `TRANSFER_MODE_UNRELIABLE_ORDERED` (channel 1). A dropped UDP packet on Wi-Fi silently loses `level_up`, `chest_open`, `gadget_choose`, `wave_start`, and even `victory`/`game_over` (because `GameHost` stops stepping once `phase != "playing"`).
  * Joining a live game with Bot Buddies adds a new hero without replacing a bot, allowing 5+ heroes in a 4-player game.
* **Fix:** Send critical one-shot events (or phase changes) over reliable channel 0, and replace a Bot Buddy when a human joins mid-game if `players.size() >= 4`.

### 1.8 Flaky `test_play.gd` & Resource Leak Warning
* **Where:** `tests/test_play.gd`, `tests/test_data.gd`.
* **Problem:** `test_play.gd` failed 2–3 checks (`level up gives cards`, `1 picks a card`, intermittently `losing all lives ends the game`) because `await frames(3)` in headless mode runs faster than `GameHost`'s `33.3 ms` tick accumulator. `test_data.gd` leaks `GameData` on exit (`3 ObjectDB instances were leaked`).
* **Fix:** Await `main.host.snapshot_ready` (or `secs(0.06)`) in `test_play.gd`, and call `D.free()` at the end of `test_data.gd`.

---

## 2. Controls, Input & Accessibility

### 2.1 Click-and-Play Parity for Towers & Cards
* Kids and mouse-focused players using click-to-walk still have to reach for `F`, `U`, `Y`, `X` to build, upgrade, branch, and sell.
* **Recommendation:**
  * Clicking on an existing **owned tower** selects it and opens a small contextual radial/floating action card right next to it: **Upgrade (cost)**, **Branch A / B (at Lv 2)**, **Sell (+refund)**, and **Targeting info**.
  * Clicking the **Ghost Preview** or pressing a **"Build Here"** button on the HUD plants the tower without requiring `F`.

### 2.2 Direct Build Hotkeys & Better Card Overlap Handling
* When `pending == 0`, keys `1–6` are unused. Let `1–6` (or `Shift+1–6` when cards are open) select/build gadgets directly instead of tapping `G` up to 5 times.
* Allow collapsing/minimizing the Level-Up Card tray (e.g., `Tab` or a small `Hide` button) if cards pop up during an intense boss wave so players don't misclick a card while trying to walk.

### 2.3 Godot `InputMap` + Gamepad / Controller Support
* **Where:** `project.godot`, `main.gd`.
* **Problem:** Movement and actions hardcode physical keycodes (`KEY_W`, `KEY_Q`, etc.), with zero `InputMap` actions and zero controller support.
* **Recommendation:**
  * Define semantic `InputMap` actions (`move_up/down/left/right`, `dash`, `special`, `build`, `upgrade`, `branch_b`, `sell`, `target_mode`, `start_wave`, `pause`).
  * Add full **gamepad support** (Left Stick walk, A/Cross dash, X/Square special, Y/Triangle build/upgrade, LB/RB cycle gadget, D-Pad pick cards 1–3). Co-op games with kids shine on controllers and Steam Deck.
  * Add a **Controls / Rebind** modal accessible from Title and Pause screens.

### 2.4 Accessibility & Readability Options
* Add settings in `Profile`:
  * **Screen Shake toggle / slider** (0%, 50%, 100%) for sensitive players.
  * **Damage Numbers toggle** (`All`, `Crits & Reactions Only`, `Off`) to reduce late-game clutter.
  * **Colorblind-friendly indicators:** Add distinct shapes/icons alongside player slot colors (`Coral`, `Sky`, `Amber`, `Violet`) and pest resistance rings.
  * **Auto-Dash / Hold-to-Walk:** Allowing players to hold left-click to steer continuously (in addition to click-to-pathfind) feels much smoother than re-clicking constantly.

### 2.5 Local Couch Co-op (Shared Screen on One Computer)
* **Why:** The game is in `Kids Games/Coop/` — siblings, parents, and friends sitting on one couch shouldn't *need* 2–4 separate laptops on Wi-Fi to play together!
* **How to support 2–4 local players:**
  * Add a **"Couch Co-op"** mode alongside Solo and Host LAN: P1 on Keyboard/Mouse (or Controller 1), P2–P4 on Gamepads (or optional shared-keyboard WASD vs Arrow Keys for 2-player quick play).
  * **Dynamic Framing Camera:** Automatically smoothly zoom `WorldView.camera` between `0.6x` and `1.0x` so all local heroes stay inside the viewport (or lean into `overview` mode if players spread far apart), and give each player a non-intrusive mini corner card for picking upgrades (e.g., `1/2/3` for P1, D-Pad `Left/Up/Right` for P2–P4).
  * **Mixed Couch + LAN:** Allow 2 players on one laptop to join/host a LAN game with 2 players on another laptop!

---

## 3. HUD, Combat Readability & UI/UX

### 3.1 Boss Health Bar & Enrage Telegraph
* **Where:** `render/world_view.gd` (`draw_enemy`), `ui/hud.gd`.
* **Problem:** `if e.hp < e.maxHp and not e.boss:` hides boss HP bars completely. During Spore Zeppelin (Wave 10+) and Dread Monarch (Wave 20+) fights, players have zero visibility into remaining HP or Dread Monarch's 50% enrage threshold.
* **Recommendation:** Add a prominent top-center **Boss Health Bar** when any boss is alive (showing boss name, resist icon if any, HP number, and a 50% notch on Dread Monarch), plus a clean world-space bar above the boss sprite.

### 3.2 World-Space Tower Upgrade / Sell Prompts & Range on Hover
* **Where:** `render/world_view.gd`, `ui/hud.gd`.
* **Recommendation:**
  * Highlight the nearest owned tower within `110 px` with a soft golden ring, its actual circular attack range, its current Level (`Lv 1 / Lv 2 / Lv 3A / Lv 3B`), and a compact prompt: `[U] Upgrade 60 🌰 · [X] Sell +36 🌰` (or `[U] Branch A / [Y] Branch B` at Lv 2).
  * Show the **tower range circle** when hovering over any placed tower with the mouse, including teammates' towers (helpful for coordinating Frost Fern + Puffball Mortar overlap!).

### 3.3 Wave Preview & New-Pest Spotlight Cards
* **Where:** `data/enemies.json` (`newPestIntro`, `enemies[id].desc`), `autoload/game_data.gd`, `ui/hud.gd`.
* **Problem:** `enemies.json` already defines `newPestIntro` (`slug: 7, puffcap: 8, mothmedic: 9, mole: 11, snoozemoth: 12`) and kid-friendly pest descriptions, and `group_resist` was specifically hashed to match wave previews — yet **none of it is shown in the HUD**.
* **Recommendation:**
  * Between waves, show a compact **"Next Wave Preview"** strip above the Start Wave button: pest icons, counts, elite resistances (e.g. `❄️ Ice-proof`), and Endless Twist preview.
  * On intro waves (Wave 5 Camo, Wave 6 Shielded, Wave 7 Splitter Slug, Wave 8 Puffcap, Wave 9 Moth Medic, Wave 10 Boss, Wave 11 Mole, Wave 12 Snoozy Moth), display a brief **Pest Warning Card** with a 1-line counter tip (e.g. *"Digger Mole tunnels underground — spread towers along the trail or use explosions!"*).

### 3.4 `Tab` Scoreboard, Hero Inspector & Elemental Reaction Guide
* **Where:** `main.gd` (`KEY_TAB: pass`), `data/elements.json`, `ui/hud.gd`.
* **Recommendation:** Holding `Tab` (or clicking a top-right `?` / `Stats` button) opens a translucent overlay with three clean panels:
  1. **Team Scoreboard:** Each player's Pops, Total Damage, Reactions Triggered, Combos, Towers Built, and Current Build (`Tier A/B` + Card icons).
  2. **My Hero Stats:** Live computed Damage, Attack Speed, Range, Crit %, Move Speed, Camo Detection, Armor Pierce, and Special Cooldown.
  3. **Elemental Reaction Cheat Sheet:** Visual cards from `data/elements.json` (`SHATTER`, `MELT`, `OVERLOAD`, `KNOCKOUT`, `SUNLIT`, `ELECTROCUTE`, `FLASH FREEZE`) highlighting which reactions your current team composition can trigger!

### 3.5 Pause Menu & End-of-Game Polish
* **Pause Menu (`Esc` / `P`):** Replace the bare `"Paused"` text with real buttons: **Resume**, **Controls / Reaction Guide**, **Restart Match** (host/solo), and **Leave to Menu** (currently impossible mid-game without closing the app!). Note: in LAN co-op, let clients leave to menu anytime while only the host pauses/restarts.
* **Clean Client Controls:** Hide or grey-out host-only buttons (`Pause`, `1x/2x`, `Auto`) on LAN clients instead of letting clients click dead buttons. Center the `Menu (Esc)` button on the end screen when `not is_host`.
* **Active Buff Bar:** Display active powerup timers (`🍄 Giant 8s`, `👟 Zoom 11s`, `🔥 Frenzy 6s`, `🌞 Rally 4s`) above the hero bar so players know when their burst window is ending.
* **Mini-Map:** Add a small (`~180x110 px`) translucent minimap in the top-left or bottom-right showing paths, the Bloom Tree, teammates, treasure chests, powerups, and flashing red pings when pests approach the Tree.

### 3.6 Visual Clarity Upgrades in `WorldView`
* **Resist Badges:** Draw the actual element glyph/letter inside the elite resist circle (`❄️`, `🔥`, `⚡`, `💥`, `🍃`) instead of an empty colored ring.
* **Frozen Visual:** Replace the plain blue `draw_rect` over frozen enemies with a faceted ice-crystal polygon or frost outline.
* **Status Stacking Clarity:** Show subtle icons for `Brittle (+% dmg)`, `Soaked`, `Trapped`, and `Sunlit` so players *see* their co-op setups landing.
* **Tower Ghost Upgrade:** Render the actual translucent tower sprite (plus an `OK` / `Blocked` label with `spot.reason` if invalid) instead of just a colored circle.

### 3.7 Evolution Fanfare, Post-Game Awards & UI Polish
* **Hero Evolution Celebration:** `Sprites` has 21 unique evolution sprite sheets per hero (`00` through `42`/`24`), yet evolving only pops small white text. When hitting Tier 3 or Tier 4, trigger a golden ring burst, evolution sound, and a brief toast/badge (`"✨ Evolved into Solar Railgun!"`).
* **Co-op MVP & Role Awards on End Screen:** Right now `_draw_end` only shows `Pops`, `Damage`, `Specials`, and `Built`, which makes support heroes (`Sun Blossom`, `Frost Lotus`, `Bubble Lily`) look weaker than DPS heroes. Add fun **Team Award Badges** at the bottom of the Victory/Game Over card:
  * 🌞 **Sun Gatherer** (most Sun/XP generated)
  * ⚡ **Reaction Master** (most elemental reactions triggered)
  * ❄️ **Crowd Controller** (most chills/stuns/traps/pushbacks)
  * 🏗️ **Master Builder** (most tower damage / upgrades)
* **Custom Vector/Sprite UI Icons:** Replace OS-dependent Unicode emojis (`🌰`, `🌳`, `⏸`, `🅰️`, `🅱️`) with crisp custom PNG/SVG icons so the HUD looks identical and razor-sharp on macOS, Windows, and Linux.
* **Title Screen Attract Mode Polish:** Make `start_attract()` pan smoothly between active fights or cycle camera focus across heroes, and add a **"Hide Menu / Watch Demo"** button so players can preview heroes in action.
* **Map & Difficulty Cards on Title Screen:** Replace plain `OptionButton` dropdowns for Map and Hero info with visual **Map Thumbnail Previews** (showing path count, length/speed rating, and earned difficulty medals).

### 3.8 Title Screen & Menu Redesign (`ui/menu.gd`, `ui/ui_kit.gd`)
* **Live Animated Hero + Hat + Pet Showcase:** Right now Hat and Pet are plain text dropdowns (`🌼 Flower Crown`, `🐞 Ladybug`)—you can't see how they look until launching a match! Add a live animated preview box on the Title Screen rendering your chosen hero's idle animation wearing the selected Hat with the Pet trotting beside them.
* **Hero Card Stat Bars & Path A/B Evolution Preview:** On the hero picker, show each hero's **Element badge** (`🍃`, `☀️`, `❄️`, `💥`, `⚡`, `🔥`, `💧`), simple visual stat bars (*Damage, Speed, Range, Control, Support*), and an expandable **"View Paths"** preview showing Tier 1–4 upgrades for Path A and Path B before locking in.
* **Surface Difficulty & Mode Descriptions:** `data/difficulties.json` already has clear descriptions (*"80 Team Lives. 20 waves. Great for learning!"* vs *"just 10 Team Lives. 30 waves."*), yet `menu.gd` never displays them! Show a crisp summary pill underneath Difficulty and Mode so kids and new players understand what they're choosing.
* **Responsive Layout & Small-Screen Safety:** `Menu._frame()` hardcodes `custom_minimum_size = Vector2(1080, 0)` without a `ScrollContainer`. On smaller windows or high-DPI displays, wrap menu content in a responsive `ScrollContainer` with scaled margins so buttons never clip off-screen.
* **Dedicated Settings Modal:** Add a `⚙️ Settings` button on the Title and Pause screens for **Master/SFX/Music volumes**, **HUD Scale** (`Small / Normal / Large`), **Screen Shake**, **Damage Numbers**, **Controls/Rebinds**, and a **Kid-Friendly "Unlock All Cosmetics"** toggle.

### 3.9 In-Game HUD Bug Fixes & Micro-Interactions (`ui/hud.gd`)
* **Fix Build Bar Hover Tooltip Bug:** In `Hud._draw_build_bar()`, hovering over *any* tower button displays the description for `selected_gadget` instead of the tower under your mouse cursor! Show the hovered tower's name, cost, element, and stats (`Range`, `DPS`) dynamically.
* **Fix Truncated Text & Tight Spacing:**
  * `_draw_hero_bar()` cuts hero style text mid-word at 40 characters (`.substr(0, 40)`), and places `Path A · Path B` at `x0 + 150` right next to longer names like `"Bubble Lily"`. Wrap or give the style subtitle proper width, and push the path indicator right or make it `A2 · B4` pills.
  * The Endless Twist banner (`tl` panel below top-left) uses a fixed `330×30` box that overflows on longer descriptions like *Sneaky Wave*. Auto-size width or wrap cleanly to 2 lines.
* **Essential Missing Counters:**
  * **Wave Pest Counter / Progress Bar:** Show remaining pests (`14 / 42 left`) in the top-left panel so players know whether to burn a Special or save it for the next wave.
  * **Tower Cap Indicator:** Show `Built: 2 / 5` directly on the Build Bar header so hitting `limitPerPlayer` (5) never surprises players.
  * **Auto-Wave Countdown Ring:** When `Auto` is enabled between waves, show a clear `"Next wave in 2.1s"` pill instead of starting abruptly.
* **Ability & Team Panel Polish:**
  * Show rich **hover tooltips** on the `Q` Special, `Shift` Leaf Leap, and `H` Home buttons explaining exact effect and cooldown.
  * Upgrade the **top-right Team List** with mini hero portraits, a glowing purple **Special Ready** indicator (for easy Team Combos), a bobbing **Card Pending** star, and click-to-spectate or gift acorns.
  * Add **Quick HUD Buttons** in the bottom-right next to Pause/Speed/Auto for **Overview Map (`Z`)**, **Reaction Guide (`?`)**, and **Audio Mute (`🔊`)**.
* **Level-Up Card Tray Polish (`_draw_cards`):**
  * Increase card height slightly so 3-line descriptions never crowd the bottom edge, add **Path Progress Pips** (`● ● ○ ○`), show **exact stat deltas** (`Fire Rate: 1.25 → 1.69`), and animate cards sliding in smoothly.
  * Add a small **"Minimize / Peek"** button on the card header so players can temporarily tuck cards away if they spawn mid-boss fight.
  * Switch mouse cursor to `CURSOR_POINTING_HAND` when hovering clickable HUD buttons/cards, and highlight affordances on hover/press.

### 3.10 LAN Browser & Lobby Interface (`ui/menu.gd`, `net/`)
* **Richer LAN Game List (`show_join`):** Include **Difficulty, Mode (`Adventure`/`Endless`), and Current Wave** in the UDP beacon so players know what they're joining before clicking. Add an explicit **Refresh** button and a subtle troubleshooting hint (*"Don't see a game? Check macOS/Windows firewall or type the host IP below"*) after 5 seconds.
* **Copy-Pasteable Host Address:** In `show_lobby()`, display the host's LAN IP prominently with a one-click **Copy IP** button instead of burying it in a status sentence.
* **Interactive Lobby Room:** Let every player change **Hero, Hat, and Pet** live in the lobby, toggle a **Ready** checkmark, see a **Team Element Synergy** strip (*"Frost Lotus + Boom Shroom = 💎 SHATTER!"*), and let the host adjust Map/Difficulty/Mode/Bots without recreating the lobby.

---

## 4. Audio, Voice, Music & Visual Polish

The base audio system is now wired via `autoload/audio.gd` (`Audio`), `tools/gen_audio.py` (41 procedural SFX + 34 hero/boss/announcer voice lines), HUD subtitles, and hero speech bubbles. Below are the best next upgrades to take sound and voice from good to unforgettable.

### 4.1 Event-Sound Separation & Missing Signature SFX
* **Separate `"nova"` by Source (`render/world_view.gd`):** Currently all `"nova"` events play `"shoot_frost"`, so **Sun Blossom's light pulse** (`#FDE047`) and **Volt Cactus's overload** (`#C084FC`) both sound like ice. Map them by color/kind to a warm solar chime and an electric crackle.
* **Missing Adventure SFX:**
  * **Digger Mole (`mole_down` / `mole_up`):** Muffled dirt-digging thud vs earth-burst pop.
  * **Seed Bomb (`gadget_boom`) & Bubble Trap (`bubble_trap`):** Heavy mine boom and a bouncy soap-bubble *"bloop-lock!"*.
  * **Spring of Life (`spring_life`):** Gentle healing harp/water sparkle.
  * **Sniper Sunflower (`snipe`) vs Solar Railgun (`beam`) vs Solar Beam (`solar_beam`):** Distinct crisp sniper crack, sci-fi railgun zap, and warm sun-beam hum.
  * **Subtle Movement/Pet Feedback:** Soft leafy rustle on footsteps/dashes and tiny celebratory pet chirps on level-up.
* **Garden Clash Specific SFX:** Dedicated sounds for **Thorn Tower firing**, **Sir Shellbash's ground slam** (`slam_warn` wind-up + heavy impact), **structure collapse** (`struct_down`), **hero knocked out**, **teammate revive jingle**, **Golden item forge clang**, and **Berry Juice gulp** (`potion`).

### 4.2 Spatial Audio, Stereo Panning & Priority Mixing
* **Camera-Relative Attenuation & Panning:** Right now `Audio.play_sfx()` uses non-positional `AudioStreamPlayer`s, so a Bot Buddy fighting across a `2160×1320` arena sounds as loud as your own hero. Pass world `(x, y)` into `Audio.play_sfx(id, pos)` to pan left/right and roll off distant off-screen combat by `-10` to `-14 dB`, keeping global alerts (`boss_warn`, `tree_hurt`, `team_combo`, `level_up`, `chest_open`) centered at full volume.
* **Local Player Priority Boost:** Play the local player's own shots and pops `+2 to +3 dB` louder than teammates/bots so personal actions stay crisp in 4-player chaos.

### 4.3 Godot Audio Buses, DSP Effects & Voice Ducking
* **4-Bus Routing (`Master → Music / SFX / Voice / UI`):** Splitting buses in Godot enables clean mixing and per-category sliders.
* **Voice Ducking:** Smoothly dip `Music` and `SFX` by `~4 dB` whenever a hero, boss, or announcer speaks so dialog cuts cleanly through wave explosions.
* **Master Limiter / Compressor:** Prevent clipping when 4 heroes + 16 towers fire simultaneously in late Endless waves.
* **Character Voice DSP Flavor (`tools/gen_audio.py`):** Give **Dread Monarch** & **Spore Zeppelin** deeper formant/reverb tails, **Garden Announcer** crisp studio warmth, **Bubble Lily** a light watery shimmer, and **Snapdragon** warm saturation.

### 4.4 Richer, Non-Repetitive Dialog & Garden Clash Cast
* **3–4 Randomized Variants per Trigger:** Repeating `"Growing stronger!"` on every level-up fatigues fast. Generate 3–4 short variations per hero for `level`, `special`, and `evolve` (`pea_level_0..2`) and rotate randomly without immediate repeats.
* **New Situational Dialog Triggers:**
  * **Tier 3 / Tier 4 Evolutions (`hero_upgraded`):** Celebratory line when transforming (`"Solar railgun online!"`, `"Absolute zero!"`).
  * **Co-op Reactions & Combos:** Quick banter when players trigger `TEAM COMBO` or big reactions (`"Shattered 'em!"`, `"Lightning and water — zap!"`).
  * **Bloom Tree Danger (`lives <= 25%`):** Urgent hero callout (`"Protect the Bloom Tree!"`).
  * **Tower Wake-Up (`gadget_wake`):** Playful quip when waking a sleeping tower (`"Wakey wakey, tower!"`).
* **Garden Clash Voices:**
  * Distinct voice personalities for the **4 Rival Champions** (`Sir Shellbash`, `Queen Stinger`, `Digger Duke`, `Spore Witch`) on spawn and signature ability casts.
  * **Clash Hero Lines:** Downed (`"Need a revive!"`), Revived (`"Thanks, friend!"`), Golden item bought (`"Golden power!"`), Berry Juice (`"Mmm, refreshing!"`).
  * **Clash Announcer:** `"Rumble Toad has awakened!"`, `"Toad Power activated!"`, `"Gate shattered — Super Sprouts marching!"`, `"Thorn Heart exposed!"`.
* **Upgrading to Neural AI Voices (`--gemini`):** Adding expressive voice direction cues (*"[excited]"*, *"[menacing villain]"*) to `DIALOG_LINES` lets `python3 tools/gen_audio.py --gemini` upgrade the entire cast to studio-grade AI acting with one command whenever an API key is configured.

### 4.5 Adaptive Background Music & Map Ambience
* **3-Layer Adaptive Loop:**
  * *Calm Prep:* Gentle, cozy acoustic/marimba garden theme between waves.
  * *Wave Action:* Crossfades in upbeat bass and light percussion while `waveActive` is true.
  * *Boss / Clash Climax:* Layers in energetic brass/synth urgency during Spore Zeppelin, Dread Monarch, or when Thorn Heart shields drop.
* **Subtle Map Ambient Beds:** Soft birdsong/breeze (*Sunny Meadow*), gentle brook (*Lilypad Crossing*), night crickets/chimes (*Starlight Crossroads*), crisp wind (*Frosty Glade*).

### 4.6 Audio Settings & Subtitle Polish
* **Volume & Chatter Controls:** Expose **Music / SFX / Voice** sliders and a **Dialog Frequency** toggle (`All`, `Key Events Only`, `Off`) in a Settings panel, plus subtitle on/off toggle.
* **Boss World-Space Bubbles & Speaker Accents:** Attach boss dialog lines (`boss_zep`, `boss_monarch`, `boss_enrage`, Rival spawns) to their entity ID so bosses get world-space speech bubbles too, and add speaker portraits + color-coded borders to the top HUD subtitle bar.

### 4.7 Visual Polish & Shaders (Step 7)
* **Bloom Tree Vitality:** Have the Bloom Tree visibly shed petals or dim as lives drop, and burst with golden blossoms when healed by `Tree Hug` or `Spring of Life`.
* **Map Atmosphere:** Add subtle ambient particles per map (drifting pollen on `Sunny Meadow`, water sparkles on `Lilypad Crossing`, falling maple leaves on `Maple Hollow`, gentle snow on `Frosty Glade`, floating fireflies on `Starlight Crossroads`).
* **Off-Screen Indicators:** When a **Treasure Chest**, **Power-up**, **Dread Monarch**, or **leaking pest** is off-screen, draw a small edge-of-screen pointer arrow so players notice and dash toward it!
* **Hit-Stop / Juice:** Subtle scale squash-and-stretch on hero attacks, pest pops, and tower firing; glowing trail on `Leaf Leap` dash; crisp impact rings on `Shatter` and `Knockout`.
* **Custom Font Bundling:** Bundle an actual `.ttf`/`.otf` rounded display font + emoji/icon sprites instead of relying on `SystemFont` (`Arial Rounded MT Bold`), ensuring identical, crisp rendering across macOS, Windows, and Linux builds.

---

## 5. Gameplay Depth, Heroes & Towers

### 5.1 Deepen Co-op Team Combos
* **Current:** `check_combo()` triggers a generic `"TEAM COMBO!"` AoE blast whenever any 2 players use specials within 3 seconds and `450 px`.
* **Suggestions:**
  * **Combo Window Indicator:** When Player A uses a special, show a 3-second glowing ring/timer around them (`"Combo Ready! Press Q!"`) and a HUD pulse for teammates within `450 px` so combos feel **intentional**, not accidental.
  * **Unique Named Pair Combos:** Give specific hero pairings signature combo effects! Examples:
    * *Frost Lotus + Boom Shroom* → **Cryo Nuke** (massive shatter blast + brittle).
    * *Bubble Lily + Volt Cactus* → **Storm Surge** (map-wide chain lightning across all soaked pests).
    * *Snapdragon + Sun Blossom* → **Solar Flare** (burns + drops bonus Sun orbs).
    * *Pea Blaster + Frost Lotus* → **Hailstorm Barrage** (piercing frost-pea volley).

### 5.2 Interactive Map Features
* Right now maps only differ in paths, `pestSpeed`, water, and rocks. Give each Adventure map 1 light signature gimmick (with an optional toggle):
  * **Sunny Meadow:** Sunflowers near paths occasionally bloom bonus Sun orbs when walked past.
  * **Lilypad Crossing:** Stepping onto lilypads grants brief Water-Soak aura or a speed boost across the river bend.
  * **Starlight Crossroads:** Central Starlight Obelisk charges up as pests die nearby, letting any hero trigger a mini-pulse when full.
  * **Maple Hollow:** Leaf piles slow pests slightly when heroes dash through them.
  * **Frosty Glade:** Frozen geysers periodically chill nearby pests (setting up `SHATTER`/`MELT` even without Frost Lotus).

### 5.3 Tower & Trap Improvements
* **Seed Bomb (`bomb`) Value:** Currently a 25-acorn one-shot trap that bots never build and players forget mid-wave. Give it a **1-time micro-stun / mole-unburrow bonus** and allow **quick-planting near your cursor or directly under your feet** cleanly, or give it 2 charges / an upgradeable "Re-Seeding Bomb" option that regrows once per wave.
* **Tower Synergy & Positioning:**
  * Add a **Tower Status Tooltip** showing total damage dealt (`pops`) by each placed tower so players feel rewarded for smart placements!
  * Let **Sun Blossom** boost nearby **gadgets** too (+15% fire rate when standing next to a tower, encouraging active support positioning!).
* **Wake-Up Mechanic Polish:** Snoozy Moth puts towers to sleep, and walking within `75 px` wakes them up — awesome co-op interaction! Add a clearer **"Zzz — Walk near to wake!"** badge + off-screen indicator so players rush over to wake sleeping towers.

### 5.4 Hero Kit Polish
* **Active Dash Synergy (`Leaf Leap`):** Give `Leaf Leap` a subtle hero-flavored perk (e.g., Frost Lotus leaves a brief chill trail, Snapdragon leaves an ember puff, Bubble Lily splashes soak, Volt Cactus zaps nearby on landing) — makes movement feel heroic rather than purely positional.
* **Pea Blaster:** Already strong; ensure Path A4's knockback uses `push_back` so it feels punchy on every map segment.
* **Sun Blossom:** Make Path A (`Golden Harvest`) meaningfully distinct and viable solo (fix `shareRatio`, scale `solarBeam` + add a Bloom Tree shield/heal or burst of Sun).

### 5.5 Endless Mode Depth
* Currently Endless scales HP/speed/count after Wave 25 and picks 1 of 6 twists.
* **Suggestions:**
  * **Double-Twist Milestone Waves** (Wave 40, 50, 60+) and a **Boss Rush Wave** every 15 waves.
  * **Endless Shop / Acorn Sink:** Once all 5 towers are Lv 3, acorns become useless! Add late-game acorn sinks: **Overclock a Tower (+25% speed for 1 wave, 100 🌰)**, **Repair 1 Tree Life (250 🌰, limit once per 5 waves)**, or **Buy a Mystery Power-Up (120 🌰)**.

### 5.6 Deeper Level-Up Cards & Build Decisions
* **Tier-3 Path Lock Warning:** In `GameData.path_card_options()`, picking Tier 3 of Path A permanently caps Path B at Tier 2 (`max_allowed = 2 if other >= 3 else 4`), and vice versa. Display a clear warning pill on Tier 3 cards (`"🔒 Locks other path at Tier 2"`) so players don't accidentally lock themselves out of a build they wanted.
* **Card Reroll Mechanic:** Give players **1 free Card Reroll** per boss chest (or spend `30 acorns`) to redraw their 3-card offer if they really need `Keen Eyes` (Camo) or `Armor Breaker` before Wave 5/6.
* **Post-Level-11 Capstone Synergy Cards:** After Level 11, heroes finish their A4/B2 or A2/B4 paths and spend Levels 12–30+ picking generic stat cards (`+15% dmg`, `+12% speed`). Add **Rare Capstone Cards** that only appear at Level 12+:
  * *Catalyst Mastery:* Elemental reactions you trigger deal +30% bonus damage.
  * *Quick Wisp / Echo Shot:* 15% chance for hero attacks to fire a bonus projectile.
  * *Acorn Magnet:* Defeated pests drop +25% more acorns.
  * *Guardian Roots:* Nearby towers within your hero range gain +15% attack speed.

### 5.7 Bosses, Enemies & New Gadgets
* **Dread Monarch Enrage Visuals & Sound:** `SimWorld` already sets `e.enraged = true` at <50% HP and emits `boss_enrage`, yet `WorldView` renders nothing for it! Add a pulsing crimson/violet aura, smoke trail, and a `"👑 Dread Monarch is ENRAGED!"` screen banner.
* **Wave 15 Mini-Boss:** Bridge the 10-wave gap between Wave 10 (Spore Zeppelin) and Wave 20 (Dread Monarch) with a **Wave 15 Mini-Boss** (e.g., *Bramble Colossus* — slow armored ground juggernaut that shields nearby pests or shakes towers).
* **Cleaner Enemy Ability Telegraphs:**
  * Draw a soft green tether line when **Healer Moth (`mothmedic`)** heals nearby pests so players immediately spot why pests aren't dying.
  * Give **Snoozy Moth (`snoozemoth`)** a visible violet ring pulse 0.5s before putting towers to sleep.
  * Animate **Digger Mole (`mole`)** dirt mounds with kicked-up earth particles instead of static colored ovals.
* **New Gadgets for Strategic Variety:**
  * **Acorn Harvester / Bloom Pot** (`support`, 75 🌰): Generates small bursts of acorns + Sun orbs during waves and boosts nearby tower fire rate by 10–20%.
  * **Sap Pitcher / Honey Trap** (`onPath` trap, 55 🌰): Coats pests in sticky sap that strips Camo and increases Fire/Blast damage taken by +20%.
  * **Gust Blossom** (`tower`, 95 🌰): Periodically pushes pests back along the trail—great emergency anchor near the Bloom Tree!

### 5.8 Mouse-Aimed Tower Placement & Priority Target Marking
* **Cursor-Assisted Placement:** Allow planting towers at the **mouse cursor** (clamped within `160 px` of your hero) when using the mouse, while keeping hero-feet placement when using keyboard `F`. Placing Frost Ferns and Thorn Patches at tight corners becomes much less finicky.
* **Priority Target Mark (`Right-Click` on an Enemy):** Let players right-click a dangerous enemy (like a Healer Moth, Snoozy Moth, or Golden Beetle) to paint a glowing crosshair over it for 5 seconds so your hero (and nearby towers/bots) prioritize popping it first!

---

## 6. Balance, Maps & Bot AI

Running `tests/test_sim.gd` revealed a huge gap between maps and difficulties:
* `Easy/Normal/Hard Meadow` and `Normal River` all ended in **Victory with 100% starting lives (0 leaks)**.
* `Normal Courtyard` lost at **Wave 20**, `Hard Courtyard` lost at **Wave 11**, and `Nightmare Courtyard` lost at **Wave 6–7**.

### 6.1 Why `Starlight Crossroads (courtyard)` & `Maple Hollow (hollow)` Spike So Hard
Checking `data/maps.json` path geometry explains why:
* `river`: 1 path, `4,620 px` (`pestSpeed: 1.45` → `3,186` effective px).
* `meadow`: 2 paths, `3,540 px` (`pestSpeed: 1.2` → `2,950` effective px).
* `frosty`: 2 paths, `3,540 / 3,480 px` (`pestSpeed: 1.15` → `3,026–3,078` effective px).
* `hollow`: 3 paths, middle path is only `2,640 px` (`pestSpeed: 1.15` → `2,295` effective px).
* `courtyard`: **4 paths**, each only **`2,040 px`** (`pestSpeed: 1.0` → **`2,040` effective px**).

On top of paths being **30% shorter**, `courtyard` splits waves across 4 opposite corners while `teamHp` + `teamHpBig` scales enemy HP up to `4x+` for 4 players — meaning each hero effectively solos a 4-player-HP enemy on a shorter lane.

**Recommendations:**
1. **Factor path count / path length into `teamHp` or `pestSpeed`:** On 3–4 path maps (`hollow`, `courtyard`), reduce `pestSpeed` slightly (`0.85` on Courtyard) or scale `teamHp` down when threats are split across 3+ lanes.
2. **Smooth the Early-Wave Difficulty Cliff on Hard/Nightmare:** Ease `teamHp` ramp on waves 1–8 (`team_ramp` starting at `0.15` instead of `0.25`) while keeping waves 12–30 intense.
3. **Fix Late-Game Chest Snowballing:** In our `Hard Meadow` sim run, **33 chests** spawned across 30 waves, giving every player 33+ free bonus cards on top of ~28 level-ups.
   * Cap Golden Beetle spawn chance or make Golden Beetle chests award **+Acorns & +XP** with a **chance** (or every Nth chest) for a Bonus Card, reserving guaranteed Bonus Cards for **Boss Chests** and **Endless Milestones**.
4. **Prevent Acorn Starvation vs Overflow:** Early game players often starve for acorns on 4-path maps; late game players float 1,000+ unused acorns once capped at 5 Lv 3 towers. Add acorn sinks (see §5.5) and slightly higher early-wave clear acorn rewards on multi-path maps.

### 6.2 Smarter Bot Buddies (`sim_world.gd` → `update_bots`)
* **Current issues:** Bots chase the furthest enemy across the map, build only near wherever they happen to stand (`near_path.d < 100`), ignore `bomb`, never prioritize `mothmedic` or `snoozemoth`, and don't prioritize waking sleeping towers.
* **Improvements:**
  1. **Wake Sleeping Towers First:** If any tower is sleeping (`g.sleep_t > 0`), nearest bot runs over to wake it.
  2. **Smart Chokepoint Building:** Build towers near path intersections / central defense radius (`200–550 px` from Sanctuary) rather than isolated far corners.
  3. **Priority Target Switching:** Briefly switch bot hero `target_mode` to `"strong"` on boss waves or when Acorn Knights/Iron Tankbugs appear.
  4. **Use Seed Bombs on Leak Emergencies:** If an enemy gets within `350 px` of the Bloom Tree and the bot has 25+ acorns, drop a Seed Bomb ahead of it.
  5. **Allow Players to Ping Bots:** Let players signal bots to *"Follow me"* or *"Guard this lane"* via the Emote/Ping wheel!

### 6.3 Modes, Modifiers & Family-Friendly Replayability
* **Zero-Leak "Perfect Wave" Streak Bonus:** Award a small escalating bonus (`+5 🌰` / `+10% wave-clear XP`) whenever a wave clears with zero lives lost. It creates exciting tension even on Easy/Normal!
* **Fun Mutators ("Garden Rules"):** Optional pre-game toggles for replayability:
  * *Oops! All Twists* (every wave has an Endless Twist from Wave 3).
  * *Hero Mode* (no towers allowed, +60% hero XP and shorter special cooldowns).
  * *Reaction Chaos* (elemental reaction multipliers increased by 1.5×).
  * *Turbo Garden* (1.4× move & projectile speed, faster waves).
* **Cozy Kid Assist Toggle:** Optional setting for younger kids (gentle Bloom Tree life regen between waves + wider Sun magnet pickup) so families with mixed skill levels can have fun together without frustration.
* **Practice / Sandbox Mode:** Unlimited acorns, wave selector, spawn-any-pest buttons, and instant level-up testing so players can experiment with Tier 4 evolutions and combos.
* **Save & Resume Solo Runs:** Auto-save state between waves to `user://autosave.cfg` so players can resume a long Endless or Adventure run later.
* **One-Click "Next Map" / "Step Up Difficulty" on Victory:** Add a **"Next Challenge →"** button on the Victory popup to flow seamlessly through all 5 maps.

---

## 7. Co-op & Social Features

### 7.1 Implement Emotes & Map Pings (`data/cosmetics.json`)
* `cosmetics.json` already defines 5 emotes (`Hi!`, `Love`, `Help!`, `Nice!`, `Follow me!`).
* **Add:**
  * Quick emote wheel (`V` or `C`, or `1–5` while wheel is open) displaying a floating speech bubble above your hero + subtle chime.
  * **World Ping (`Middle Click` or `Alt+Click`):** Drop a 4-second pulsing beacon (`"Look here!"` / `"Chest!"` / `"Leaking!"`) visible on everyone's screen and minimap.

### 7.2 Co-op Support Mechanics
* **Sun Share Ping / Gift Acorn:** Let teammates send `25 acorns` to a teammate (e.g., clicking their name in the top-right team panel) so a player saving for a Lv 3 Branch Upgrade (`220 🌰`) can be boosted by allies!
* **Hero Synergy Highlights in Lobby:** In the Title / Lobby screen, when 2+ players pick heroes whose elements react (`Frost Lotus + Boom Shroom = SHATTER`, `Bubble Lily + Volt Cactus = ELECTROCUTE`), show a **"Great Team Combo!"** badge so kids discover synergistic teams naturally!

---

## 8. Meta-Progression, Unlocks & Onboarding

### 8.1 Enforce & Celebrate Hat/Pet Unlocks (`data/cosmetics.json`)
* **Current:** All 12 hats and 9 pets are unlocked immediately, and `Profile` (`ui/profile.gd`) doesn't track unlocks or show the `how` requirements already written in `cosmetics.json`.
* **Recommendation:**
  * Track unlocked `hats` and `pets` in `user://profile.cfg` (keeping the `free: true` starter ones unlocked, plus checking conditions like `"Pop 250 pests in one game"`, `"Pop a boss"`, `"Reach hero level 20"`, `"Make 30 team reactions in one game"`, `"Win on Hard"`).
  * Show locked items in the Title menu with a 🔒 icon and tooltip showing their unlock requirement (`cosmetics.json` → `how`).
  * Display a celebratory **"NEW UNLOCK!"** banner on the Victory/GameOver screen when you earn a hat or pet!
  * *(Optional kid-friendly toggle: "Unlock Everything" sandbox/family switch in Settings for younger kids who just want to wear the Dragon pet right away.)*

### 8.2 Garden Almanac (Bestiary & Tower Guide)
* Add a **"Garden Guide"** button on the Title Screen with tabs for:
  * **Heroes:** Stats, both Upgrade Paths (A1–A4, B1–B4), Special, and Elemental Reactions.
  * **Towers & Traps:** Costs, Level 3 Branch options, and tips.
  * **Pest Bestiary:** All 13 Adventure pests (unlocking entries as you encounter/pop them!) showing HP, Speed, Armor/Camo/Burrow traits, and counter tips.

### 8.3 Interactive First-Time Onboarding ("Practice Garden")
* A 60-second optional guided Wave 0 or checklist toast sequence for new players (`games == 0`):
  1. Walk to the glowing Sun orb (`WASD` or Click).
  2. Press `Shift` to Leaf Leap across the garden.
  3. Press `Space` to start Wave 1, pick a Level-Up Card (`1/2/3`), and press `Q` for your Special.
  4. Build a Sprout Sentry (`F`) and upgrade it (`U`).

### 8.4 Daily / Weekly Challenge Seeds & Medals
* Track **Map × Difficulty Medals** in `Profile` (e.g., Bronze/Silver/Gold/Nightmare stars on each map card in the menu).
* Add a **"Seeded Challenge"** option (deterministic RNG seed + fixed hero/twist rule, e.g., *"No Towers, Heroes Only"* or *"Double Bosses"*).

---

## 9. LAN Networking & Lobby Experience

### 9.1 In-Lobby Customization & Host Controls
* Currently once you enter the LAN lobby (`Menu.show_lobby`), players cannot change their **Hero, Hat, Pet**, or **Map/Difficulty/Bots** without backing out.
* Let clients switch Hero/Hat/Pet inside the lobby (broadcast via `"pick"`), show each player's **Ready** checkmark, and let the host tweak Map/Difficulty/Mode/Bots live in the lobby.

### 9.2 Network Smoothness & Reconnects
* **Client Projectile Extrapolation** (`world_view.gd` line 435): Scale projectile velocity extrapolation by `snap_gap` (`0.05s` on 20 Hz clients) instead of hardcoding `/ 30.0`.
* **Graceful Rejoin / Keep-Alive:** If a client briefly drops Wi-Fi and reconnects with the same name, optionally restore their hero level/cards/acorns instead of spawning a fresh player or losing their towers.
* **Network Quality Indicator:** Show a tiny ping/packet-rate pill in the corner (`LAN: 18 ms · 20 Hz`) when `net != null`.

---

## 10. Porting Garden Clash

As noted in `README.md`, **Garden Clash** (`data/clash.json`, `valley` map, rival champions, jungle camps, shop items, potions, minion waves, respawn/recall) already has:
* All balance JSON in `data/clash.json`, `data/enemies.json`, and `data/maps.json` (`valley`, 3 lanes: `2520 / 1773 / 2520 px`).
* All sprites exported in `art/pests/` (`rival_*`, `rubybeetle`, `sapphiresnail`, `rumbletoad`, `grunt`, `stinger`, `shellcart`, plus allied minions `budling`, `peapod`, `pumpkin`).
* Item & Clash buff hooks already wired in `GameData.compute_hero_stats()` (`items`, `maxHp`, `lifeSteal`, `regen`, `ember`/`dew`/`toad`/`elder` buffs) and `Bubble Lily` (`healAura`).

**Concrete implementation roadmap for Garden Clash:**
1. **Shared Simulation Layer (`sim/clash_world.gd`):** Reuse `GameData` damage/reaction math and emit the same `snapshot()` + `events` format plus Clash state (`heroHp`, `maxHp`, `deadT`, `recallT`, `potions`, `items`, `camps`, `structures`, `minions`).
2. **Allied & Enemy Wave Spawner:** Spawn 3-lane waves of **Bud Buddy (`budling`)**, **Pea Pod (`peapod`)**, and **Pumpkin Cannon (`pumpkin`)** vs **Grub Grunt**, **Stinger Wasp**, and **Siege Tankbug** every `waveEvery: 30s` (`firstWave: 8s`).
3. **Structures & Mirroring:** Implement `allyTowers`, `gates` (with `gateRegrow: 300`), `guardians`, and `core` (`Thorn Heart`, `14,000 HP`), mirrored for the pest side (`foeBuildingsAreMirrored`).
4. **Rival Champions & Jungle Camps:** Implement the 4 AI Rival Champions (`Sir Shellbash` slam, `Queen Stinger` stinger volley, `Digger Duke` burrow, `Spore Witch` spore clouds) plus neutral jungle objectives (`Ruby Beetle` → Ember buff, `Sapphire Snail` → Dewdrop buff, `Nest Grubs`, and `Rumble Toad` → teamwide Toad / Elder Toad buff).
5. **Item Shop, Golden Upgrades & Teammate Revives:** Wire the 8 Clash items (`Thorn Sword` through `Giant's Acorn`), `goldenItem` upgrades (`1.5×` cost for `1.8×` stats), `Berry Juice` (`R` hotkey, 3 charges), fountain Recall (`3s`), and `reviveRadius: 85` co-op teammate revival (`2.5s`) — plus unlock hooks for the Clash hats/pets (`Knight Helmet`, `Thorn Crown`, `Froggy`, `Hedgehog`).

---

## 11. Engineering, Testing & Distribution

### 11.1 Code Quality & Architecture Cleanups
* **Split `sim/sim_world.gd` (~2,000 lines):** Extract cohesive helpers/modules such as `sim/sim_combat.gd` (reactions, damage, projectiles), `sim/sim_bots.gd` (bot AI), and `sim/sim_gadgets.gd` (towers/traps) so future modes (like Garden Clash) can reuse them cleanly without growing one file past 3,000+ lines.
* **Use Typed Structs / Constants for Event Names & Card IDs:** Avoid string-typo bugs across `sim_world.gd`, `world_view.gd`, `hud.gd`, and `main.gd`.
* **Fix Static Resource Caches on Exit:** Clean up or avoid leaked `RefCounted`/resources in headless test scripts.

### 11.2 Automated Balance & Regression CI
* Fix `tests/test_play.gd` timing flakiness (wait on `snapshot_ready` rather than fixed frames).
* Add a **Headless LAN Loopback Test** (`test_lan.gd`) that launches host + client logic in-tree or via subprocess `--netcheck` and asserts `moved > 50` and `packets > 0`.
* Expand `tests/test_sim.gd` into a **Balance Matrix Script** that runs all 5 maps × 4 difficulties and logs win rate, leak count, and average clear time so tuning changes can be verified objectively in seconds.

### 11.3 Packaging & Distribution Polish
* Add `export_presets.cfg` for **macOS (Universal `.app` / `.dmg`)**, **Windows (`.exe`)**, and **Linux** builds.
* **Add `Title Screen` Fullscreen / Windowed Toggle (`F11` / `Alt+Enter`) & Resolution Scaling:** Helpful on Retina/4K Macs and TVs when playing couch/LAN co-op.

### 11.4 Simulation & Rendering Performance
* **Replace `sqrt()` in Inner Loops with `dist_sq()`:** `SimWorld.dist()` calls `sqrt()` on every enemy-to-hero, enemy-to-tower, enemy-to-projectile, chain-lightning, and healer-moth check. Switching range checks to squared distance (`dx*dx + dy*dy <= r*r`) removes thousands of `sqrt()` calls per second in 300-pest waves.
* **Lightweight Spatial Grid (`36×22` tiles):** `GameData` already defines a `36×22` (`60 px`) tile grid. Bucketing enemies by tile once per tick turns `O(projectiles × enemies)` and `O(enemies²)` healer/explosion checks into `O(1)` local neighborhood lookups — keeping Endless Wave 50+ silky smooth on older laptops and speeding up headless balance tests dramatically.
* **Quantized / Delta Snapshots:** Quantize positions to `int` and send static/rarely-changing player metadata (names, hats, pets) only when changed instead of inside every 20 Hz snapshot.

---

## 12. Recommended Roadmap

| Phase | Focus | Key Deliverables |
|---|---|---|
| **Phase 1: Rock-Solid Core** | Fix bugs & test reliability | Burn accumulator, separate `frostDot`, fix `G` key & circular ranges, targeting mode (`T`), Pause/Quit menu, Boss HP bars, reliable LAN events, fix `test_play.gd` & `test_data.gd` leak |
| **Phase 2: Clarity & Feel** | Make every mechanic obvious & juicy | Audio/SFX + adaptive music, world-space tower upgrade/sell prompts, Next Wave & New Pest previews, `Tab` scoreboard + Reaction Guide, minimap, off-screen pointers, resist icons, evolution & enrage FX |
| **Phase 3: Balance & Co-op Magic** | Tune fun & replayability | Fix Courtyard/4-player scaling & chest snowballing, Sun Blossom A-path fixes, smarter Bot Buddies, Emotes & Pings, named Team Combos, Map gimmicks, Hat/Pet unlocks + Almanac, Perfect Wave & Mutators |
| **Phase 4: Expansion & Release** | Full feature parity & polish | Port Garden Clash (`valley`), Couch Co-op + gamepad & rebindable controls, lobby hero/cosmetic switching, spatial-grid sim optimization, ambient map particles & shaders, macOS/Windows export presets |
