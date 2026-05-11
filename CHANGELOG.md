# Changelog

## Unreleased

## v3.8.0 (2026-05-11)

### Added
- **Brew damage consumables at the Arcane Sanctum**: New `peon brew <item>` CLI command (and matching dashboard "Brew" panel on the Raid view) lets you spend gold + lumber to craft damage consumables instead of grinding boss RNG for them. Recipes scale with player stage — Chain Lightning and Death Coil are instant brews (200g/50l and 500g/150l), Finger of Death and Doom queue for 1 and 3 task completions (1500g/500l and 4000g/1500l), and the new legendary tier (Soul Reaver at 12000g/4000l, Twin Eclipse at 30000g/10000l) additionally costs 1 and 3 KJ shards respectively. The brew queue ticks down 1 per `task.complete`; completed brews drop straight into your inventory and surface in the game subtitle. Re-purposes the Arcane Sanctum, which previously only granted "peon prophecies on session start."
- **Two new legendary consumables for the LK-tier endgame**: **Soul Reaver** (200,000 dmg — 20% of Kil'jaeden HP, 4% of Lich King HP) and **Twin Eclipse** (500,000 dmg — Kil'jaeden's signature spell, 50% of KJ HP / 10% of LK HP). Both are brew-only (no boss drop tables), so they can't randomly fail to roll, and they're the answer to "how do I survive a 14-day Lich King fight?" — preload your inventory before pulling the boss.
- **KJ shard drop on Kil'jaeden victory**: Each Kil'jaeden kill grants 1 `kj_shards` (tracked in `.state.json`, displayed on the dashboard raid view). Soul Reaver costs 1 shard, Twin Eclipse costs 3, so the path to a Twin-Eclipse-fueled LK pull is 3 KJ kills + ~30k gold — predictable and grindable, not RNG-gated.

### Changed
- **Epic damage consumables bumped to keep pace with the buffed Lich King (5M HP)**: Chain Lightning 2,000 → 2,500, Death Coil 5,000 → 7,500, Finger of Death 10,000 → 15,000, Doom 40,000 → 75,000. Doom still doesn't one-shot Archimonde (75% of 100k HP) and is now ~7.5% of KJ rather than 4%. Common/uncommon/rare consumables (Firebolt through Thunder Clap) are unchanged — they're correctly tuned for early bosses and a flat 5x bump would have one-shot Kobolds.
- **Arcane Sanctum description** updated to mention the brewing role: `peon prophecies + brewing damage consumables (peon brew)`.

## v3.7.0 (2026-04-29)

### Added
- **New endgame boss: Kil'jaeden the Deceiver** (1,000,000 HP / 10d / 7,500g entry / atk 4-15) slots between Archimonde and the Lich King in the raid progression — fitting both the lore (Kil'jaeden is the eredar lord who ordered Archimonde's invasion of Azeroth and forged Ner'zhul into the Lich King) and the difficulty curve, which previously had a 10x HP jump (100k Archimonde → 1M LK). Drops 5 items including the **first reliable legendary roll** in the game (`['legendary','epic','epic','rare','rare']`) and rewards +25,000g +8,000l on victory. Unlocks at 25 boss kills + lvl 9 + citadel.
- **New legendary trophy: Soul Cage** (`army_heal` v=8, "Heal army 8 HP per task. Imprisoned the soul of Ner'zhul.") drops at 30% on Kil'jaeden victory. Strong sustain item that fills a real gap — Amulet of Spell Shield (epic) heals only 3 HP/task, leaving long fights against the buffed Lich King unsurvivable without it. Lore-themed: Kil'jaeden literally caged Ner'zhul's soul to create the Lich King.

### Changed
- **The Lich King promoted to true endgame**: HP 1,000,000 → **5,000,000** (5x), counter-attack 5-20 → **10-25**. The previous LK was killable in ~13 active hours by a mid-tier player using just Thunderfury poison; at 5M HP the deadline math now actually requires 14 days of sustained engagement, real army sustain (hence Soul Cage), and most/all four meta legendaries equipped (Frostmourne + Sulfuras + Thunderfury + Ashbringer). The Lich King Any% achievement (`fastest_lich_king_pct ≤ 0.5`, i.e. 7 days) becomes a meaningful speedrun target rather than an inevitability.
- **Crit multiplier nerfed from x3 to x2**: With seven items granting `boss_crit` (`tome_of_agility` +3% through `ashbringer` +30%) all stacking additively with no cap, a realistic 6-slot build hit 84% crit and a triple multiplier pushed average DPS to ~2.5x baseline — better per slot than stacking flat damage even from epics. Worse, crit applies *after* `boss_dmg_mult` (Frostmourne x2) and `boss_execute` (Executioner's Blade x3), so an execute-phase crit on a Mannoroth-tier boss was an x18 single-task burst. Dropping the multiplier to x2 keeps crit attractive (50% crit = 1.5x avg DPS, in line with Frostmourne) but ends the "crit is mandatory" math without touching item values, removing items, or capping stacks. BATS coverage in `tests/raid.bats`.

### Fixed
- **Stale boss completions**: `completions.bash` and `completions.fish` were referencing five bosses that no longer exist in the BOSSES dict (`mud_golem`, `infernal`, `brewmaster`, `blademaster`) and had wrong HP/days for the bosses that do (e.g. listing Archimonde as 14 days when it's been 7 for several releases). Both completion files now match the canonical BOSSES dict in `peon.sh`, including the new Kil'jaeden boss.

## v3.6.0 (2026-04-28)

### Added
- **5 new Warcraft character levels between Brewmaster (10k) and Murloc (1m)**: The 100x leap from level 9 to "level 10" was an obvious end-game cliff. Filled it with iconic Warcraft III hero archetypes — **Archmage** (Human, 25k tasks), **Cairne Bloodhoof** (Tauren, 75k), **Blademaster** (Orc, 150k), **Thrall** (Orc, 250k), and **Kel'Thuzad** (Undead, 500k). Murloc moves from level 10 to level 15 (still the secret final tier). Cairne also introduces a brand-new Tauren faction, and the 15-tile grid now fits cleanly as 3 rows of 5 in the dashboard.
- **Voice packs wired to all 5 new levels**: `dota2_invoker` for Archmage (both are master mages of many spells — `Quas Wex Exort`), `wow-tauren` for Cairne (126 Tauren WoW lines), `dota2_phantom_lancer` for Blademaster (Phantom Lancer's mirror images = Blademaster's signature Mirror Image ability — `I am one. We are many.`), `zugzug` for Thrall (community Orc-inspired pack), and `wc3_lich` for Kel'Thuzad (44 Lich + Kel'Thuzad lines). The Dota 2 borrowing follows the precedent already in place at level 7, where the Witch Doctor uses `dota2_witch_doctor`. All 5 packs are added to `DEFAULT_PACKS` in `install.sh` so users have them on disk the moment they hit each tier.
- **Legendary item overlay theming**: When one of the five named legendaries is equipped, the macOS overlay banner (and the WSL Forms popup background) recolors to match the item's lore — Frostmourne paints icy cyan with pale-blue edges, Ashbringer turns holy gold, Thunderfury goes electric purple with lightning-yellow edges, The Unstoppable Force burns fiery red, and Wirt's Leg picks bone-grey. The matching emoji glyph is also prepended to the tab title `MARKER` (so it appears in the terminal tab title, the toast title, and the overlay text). Wearing several named legendaries at once stacks all their glyphs (e.g. `✨❄`) while the highest-priority item drives the colors (Ashbringer > Frostmourne > Unstoppable Force > Thunderfury > Wirt's Leg). `mac-overlay.js` gained three optional positional args (`accent_rgb`, `edge_rgb`, `text_rgb`) and is fully backward-compatible. BATS coverage in `tests/peon.bats`.

### Changed
- `peon.sh` `_LEVELS` / `_LEVEL_FLAVORS` / `_LVL_PACKS`, `dashboard/index.html` LEVELS array + `tierClass` (`>= 15` is now the murloc tier) + secret-tile detection (now uses `L.secret` flag instead of hardcoded `lvl === 10`), `site/index.html` and `zugzug-landing.html` level grids + "14 Levels. Every Faction. One Secret." headlines, README + Chinese README tables, `docs/public/llms.txt`, and `install.sh` icon downloads (`lvl-10` through `lvl-15`, all wowpedia BTN icons).
- **Tauren Totem building + true Tauren Warrior unit + Troll Headhunter**: New endgame building **Tauren Totem** (20000g/8000l, between Goblin Lab and World Tree) gates the new **Tauren Warrior** (3000g/1200l, 6 food, 200 HP, +15 dmg) — the first unit with a building gate via the new `unlock_bld` field on units (mirroring the boss gating pattern). The previous "Tauren Warrior" (1000g/400l, 80 HP, +10 dmg) is replaced by a brand-new **Troll Headhunter** (200g/100l, 3 food, 35 HP, +3 dmg) — first non-Orc, non-Tauren Horde unit and a cheap ranged option that fills a real role gap (everything else is melee). Two-step auto-migration in `_load_state` handles upgrades cleanly: pre-v3.6.0 `army.tauren` (always 80 HP, since the totem didn't exist) is normalised first, then any 80-HP units are **refunded** at original cost (1000g/400l each) to the player's economy so investment is never lost. Both steps are flag-gated (`tauren_brave_migrated`, `brave_refunded`) so they run at most once per state. Also fixed the `citadel` building icon, which was incorrectly using the Tauren Totem image (`orc/taurentotem.png`) — now uses `human/castle.png`.
- **World Tree perk reworked**: The endgame building (25k gold / 10k lumber) previously extended the daily gold-mine depletion thresholds from 50/80 to 80/120 — useless by the time you could afford it, since once you've banked 25k gold you don't need *more* gold income. World Tree now grants **+1 equipment slot** (7 total instead of 6), giving real endgame value: another legendary, another stat-stick, or another consumable in your loadout. Affects CLI (`peon inventory`, `peon equip`) and the dashboard inventory page; the mine-status badge always shows the unmodified 50/80 thresholds. BATS tests updated.
- **Combo raid damage scales with player level**: Combo damage (`combo // 10`) was a flat 10 dmg cap regardless of progression — fine vs the 40 HP Kobold but useless against Lich King at 1M HP. Combo dmg now multiplies by player level, so a maxed combo deals 10 dmg at lvl 1 (unchanged), 50 dmg at lvl 5 (Far Seer), 90 dmg at lvl 9 (Brewmaster), and 150 dmg at lvl 15 (Murloc). **Bloodstone** scales the same way (now `+1 dmg per 10 combo per level`) so the rare-tier item stays relevant in late-game raids. BATS coverage in `tests/raid.bats`.
- **Battle log only logs meaningful raid events**: The boss raid block was previously firing on every event with a category (including `task.acknowledge`, `input.required`, `task.error`), which produced noisy `0 dmg` battle log entries every time the user submitted a prompt, the agent asked for permission, or a Bash command failed. The boss now only engages on `task.complete`, `resource.limit`, `user.spam`, and `session.start`. Poison still ticks correctly on the next eligible event (the elapsed time across skipped events accumulates into the next tick).
- **Battle log tags non-attack engagements**: When the boss engages on `resource.limit` (PreCompact) the entry now shows `Compacting context`, and on `user.spam` it shows `Stop poking peon!`, so the `0 dmg` lines have a clear reason rather than looking like a random whiff.
- **Doom is now epic everywhere**: v3.5.2 fixed a CLI/dashboard mismatch by promoting Doom's display rarity from `epic` to `legendary` to match the runtime drop tier in `_ITEMS`. We're going the other direction instead — Doom is conceptually a top-end *consumable*, not a true legendary loot piece, so the runtime drop tier (`_ITEMS['doom']['r']`) and the rarity lookup table (`ITEMS_R`) now align with the long-standing display rarity of `epic`. Effective change: Doom now drops from epic-tier loot rolls (more common) rather than legendary-tier rolls. Display in `peon inventory`, `dashboard/index.html`, and `dashboard/raid.html` all match.
- **Raid consumables in main dashboard, `raid.html` retired**: The raid view in `dashboard/index.html` gained a "Use Items" section that lets you fire damage consumables (Firebolt, Goblin Sapper, Storm Bolt, Demolisher Shot, Thunder Clap, Chain Lightning, Death Coil, Finger of Death, Doom) directly at the active boss with one click — same buttons the standalone `dashboard/raid.html` used to surface. Battle log entries now also render the item icon and name when a consumable is the source of damage. Standalone `dashboard/raid.html` deleted; `install.sh` cleans the file up on update and the `/raid` route is removed from the local dashboard server.

## v3.5.4 (2026-04-20)

### Fixed
- **Army-heal items trivialised raid combat**: Items with the `army_heal` effect (Amulet of Spell Shield) and the heal consumables (Scroll of Healing, Ensnare) all healed `v` HP **per unit** instead of `v` HP **total** across the army, contradicting their "Heal army X HP" descriptions. With even a single Amulet equipped, every non-shaman unit was fully restored every task because per-unit heal (3 × N units = 21 HP/turn for a typical army) outpaced every boss in the game (Lich King caps at 20 HP/turn). Shamans died first because their 20-HP cap couldn't soak the random 1-HP-per-attack damage before they got fully picked, masking the bug as a shaman-only issue. All four heal sites — passive `army_heal` (`peon.sh`), CLI `peon use` (`peon.sh`), and both copies of dashboard `_dash_heal` — now distribute a total HP pool to the most-wounded unit by **percentage** deficit, so low-HP units like shamans aren't perma-starved of healing. `healing_ward` retains "fully heal every unit" since its description is explicit.
- **Stale `scroll_of_heal` description**: Catalog said "Heal all army units 15 HP" (ambiguous, suggested per-unit). Aligned with the dashboard's "Heal army 15 HP" wording.

### Added
- BATS regression tests covering: amulet heal pool ≤ v HP per task, percentage-based heal targeting prioritising low-HP units, scroll_of_heal total-pool behavior, and healing_ward still fully healing.

## v3.5.3 (2026-04-16)

### Fixed
- **Stale boss attack stats on main dashboard**: `dashboard/index.html`'s `RAID_BOSSES` table missed the `3c92a11` "bosses higher attack" rebalance and was showing outdated attack ranges for the four endgame bosses — Illidan `2–6` (should be `3–7`), Mannoroth `2–9` (`4–10`), Archimonde `3–7` (`4–15`), Lich King `4–10` (`5–20`). `raid.html` and the backend already had the correct numbers; only the main dashboard was drifting. All three sources now agree.

## v3.5.2 (2026-04-16)

### Fixed
- **Doom consumable damage mismatch**: `dashboard/raid.html` showed Doom dealing 20000 HP while the backend actually dealt 40000. Frontend now shows the correct 40000.
- **Stale item descriptions in `_ITEMS`**: All 9 boss-consumable items in the `_ITEMS` catalog (firebolt through doom) carried pre-v3.5.0 damage values in their `desc` and `v` fields (e.g. "Deal 5 damage" for firebolt, "Deal 4000 damage" for doom). These are used for tooltips, overlays, and `peon inspect`. Aligned to the real damage numbers (50 / 100 / 250 / 500 / 750 / 2000 / 5000 / 10000 / 40000).
- **Rarity drift between CLI and dashboard**: `ITEMS` (CLI / `peon inventory`) and `BOSS_ITEMS` (dashboard) listed boss-consumable rarities lower than their actual drop-tier (`_ITEMS['r']`), which governs what boss loot rolls them. For example, Doom was shown as `epic` everywhere but dropped as `legendary`. CLI + dashboard rarities now match the runtime drop table.
- **Damage breakdown missing entries**: When the boss log contained `bk` keys outside the hardcoded known set (e.g. the `compensation` key added in v3.5.1 post-mortems, or future fields like `exhausted`), the dashboard's "Damage Breakdown" row silently dropped them — making the sum diverge from the "Damage Dealt" headline. Added an "Other: +N" bucket on both dashboards so every numeric `bk` value contributes.

## v3.5.1 (2026-04-16)

### Fixed
- **Silent boss damage regression**: `task.complete` / `Stop` events silently crashed with `NameError: name 'army' is not defined` when any item granting the `army_heal` effect (e.g. Amulet of Spell Shield) was equipped. The crash aborted the Python hook block mid-run, so `last_stop_time`, `active_boss.hp`, `active_boss.log`, and `activity_log` stopped updating while `last_active` (earlier in the pipeline) kept advancing — making it look like state was fine. Regression from v3.5.0's items balance pass. The buggy block now uses `_army` / `_UHP` (the correctly-scoped names).

### Changed
- **Hook errors are no longer swallowed**: The Python block in `peon.sh` now appends stderr to `$PEON_DIR/.error.log` instead of redirecting to `/dev/null`. Silent crashes like the one above are now debuggable via `tail -f ~/.claude/hooks/peon-ping/.error.log`.

### Added
- BATS regression tests covering `task.complete` with `army_heal` items equipped (with and without an army), and a test asserting that Python stderr lands in `.error.log`.

## v3.5.0 (2026-03-04)

### Added
- **Fatigue system**: Peon accumulates fatigue (+1 per task). Tired at 20 (half gold), exhausted at 30 (no gold, combos break). `peon rest` costs 20 lumber to reset. Tavern building raises thresholds by 10. Replaces the error-based penalty system which only worked in Claude Code.
- **Item durability**: Equipped items lose 1 durability per task. Broken items (0 durability) lose their effect until repaired. `peon repair` costs gold by rarity. Blacksmith building halves durability loss rate.
- **5 new buildings**: Lumber Mill (2x lumber), Barracks (agent sessions count toward stats), Blacksmith (+50% item effects, halves durability loss), Arcane Sanctum (peon prophecies on session start), Citadel (2x item drop rate).
- **15 new items**: 10 commons (Belt of Giant Strength, Gloves of Haste, Robe of the Magi, Pendant of Mana, Hood of Cunning, Medallion of Courage, Tome of Power, Skull Shield, Kelen's Dagger, Void Stone) and 5 rares (Talisman of Evasion, Ring of Regeneration, Scourge Bone Chimes, Shadow Orb, Lion Horn of Stormwind).
- **3 secret achievements**: Stop Clicking Me! (500 prompts), Peon Union Rep (fatigue 50 in session), Touch Grass (code past 3 AM on weekend).
- **Achievement progress tracking**: Dashboard now shows real progress bars for all achievements instead of 0/N.
- **Resource node spawning**: Lumber and gold nodes appear on the base map (15%/6% chance per task) and can be harvested by clicking.
- **Sass from productivity**: New roast triggers for overwork (30+ daily tasks), gold hoarding (5000g), and marathon sessions (15+ tasks). New grumpy-but-funny roast lines.
- **Dashboard fatigue bar**: Resource bar shows fatigue level with color-coded progress (green/yellow/red).
- **Dashboard rest/repair buttons**: One-click rest and repair actions in the base view.
- **Dashboard durability display**: Inventory page shows durability bars on equipped items with broken state.

### Changed
- **Building costs 5x**: All existing buildings now cost 5x their previous price.
- **Architect achievement**: Threshold raised from 7 to 10 buildings.
- **4 error items remapped**: Helm of Valor (fatigue resist), Orb of Fire (half gold when tired), Talisman of Evasion (fatigue resist), Mask of Death (50% repair discount).
- **4 error achievements remapped**: First Blood (20 fatigue), Rage Quit (fatigue 40), Oops (25 repairs), Peon Union Rep (fatigue 50).
- **Dashboard How It Works**: Updated all sections to reflect current mechanics.
- **Tavern perk expanded**: Now also provides +10 fatigue threshold.
- **Blacksmith perk expanded**: Now also halves item durability loss.

### Fixed
- **Achievement progress bug**: Dashboard showed 0/N for all unfinished achievements because `achievements_progress` was never written to state.
- **Item drop rarity collapse**: When all items of a rarity were collected, drops fell back to uniform distribution across all remaining items. Now redistributes weights among remaining rarities.
- **Resource node harvesting**: Dashboard harvest UI existed but no nodes were ever spawned. Added spawn logic to event loop.
- **Dashboard building icons**: Fixed broken icon paths for Lumber Mill, Blacksmith, Arcane Sanctum, and Citadel.

## v3.4.1 (2026-02-19)

### Fixed
- **Dashboard opening on every hook**: Replaced stale PID file check with a live curl probe of the port. The old approach failed when the server crashed and left a stale PID, causing every subsequent hook to open a new browser tab.

## v3.4.0 (2026-02-19)

### Added
- **`notify_always` config option**: Overlay notifications now show on every response by default, even when the terminal is focused. Set `"notify_always": false` in `config.json` to restore the old focus-aware behavior.

## v3.3.0 (2026-02-20)

### Added
- **Character page**: New dashboard tab with large portrait, XP progress bar, faction badge, and 10-level progression ladder showing completed/current/locked states
- **Level-driven sounds**: Your level now determines which sound pack plays for ALL events (Level 4 Knight hears peasant voices, Level 8 Arthas hears death knight lines, etc.)
- **Level-driven overlay portraits**: macOS overlay notifications show your level's character portrait instead of the default peon icon
- **Level portrait icons**: 10 WC3 character portraits downloaded at install time into `icons/` for overlay use
- **Level-up celebrations**: Level-up notification text in overlay, activity log, and dashboard toast with star icon
- 8 new BATS tests for level system (level calculation, level-up detection, pack override, fallback)

### Changed
- **Default installed packs** expanded from 5 to 9: added `wc3_jaina`, `dota2_witch_doctor`, `wc3_corrupted_arthas`, and more to support level-based sound progression
- Dashboard default tab changed from Base to Character
- Base page portrait is now dynamic (updates with level) and clickable (switches to Character tab)

## v3.2.0 (2026-02-19)

### Added
- **Level system**: Cross-faction progression through 10 levels based on lifetime tasks completed, with level-up notifications and sounds from matching packs
- **Dashboard API endpoints**: `/api/harvest`, `/api/equip`, `/api/unequip`, `/api/use` — inventory and harvest node interactions now work from the dashboard UI
- **Dashboard auto-open**: Auto-spawn server now opens the browser on first launch (previously only via `peon dashboard` CLI)

### Changed
- **Mac overlay redesign**: WC3-themed Cocoa overlay with category-aware styling
- **Dashboard restructured**: Moved from `dashboard.html` to `dashboard/index.html`
- Removed upkeep mechanic references from docs; simplified economy description

### Fixed
- Dashboard equip/unequip/use/harvest buttons now work (were returning 404)

## v3.1.0 (2026-02-19)

### Added
- **Item system**: 31 items across 5 rarity tiers (Common/Uncommon/Rare/Epic/Legendary) with drop rates from 5% down to 0.01%
  - Items drop on task completions, achievement unlocks, and combo milestones
  - 6 equipment slots with equip/unequip management
  - Equipped items modify game behavior: gold/lumber bonuses, roast immunity, combo persistence, error shields, crit strikes, lifesteal, debt immunity
  - Consumable items: potions, scrolls, tomes, the legendary Cheese (+1000g/+500l)
  - Named legendaries: Frostmourne (roasts become compliments), Thunderfury (+15g/task), The Unstoppable Force (combos never break), Ashbringer (purge all debt), Wirt's Leg (does nothing)
- **New CLI commands**: `peon inventory`, `peon equip <item>`, `peon unequip <item>`, `peon use <item>`
- Tab completions updated for all new commands
- 7 new BATS tests for item system

## v3.0.0 (2026-02-19)

### Added
- **WC3 Metagame**: Full Warcraft III base-building metagame layered on coding sessions
  - **Economy**: Earn gold (task completions) and lumber (prompts). Gold mine depletion, debt with interest, upkeep based on concurrent sessions, base raids on error streaks
  - **Buildings**: 8 structures buildable via `peon build` — each unlocks a real perk (combos, roast suppression, combo resurrect, on-demand taunts, random events, idle thoughts)
  - **Achievements**: 14 achievements with WC3-themed flavor text (First Blood, Night Elf, Iron Peon, Architect, Mogul, etc.)
  - **Roasts**: Escalating sass levels 0-5 based on errors, context limits, late-night coding. Suppressible via Burrow building
  - **Combos**: Multi-kill tracking (Double/Triple/Mega/UNSTOPPABLE/GODLIKE) gated behind War Mill building
  - **Time awareness**: Day/night cycle affects notification text. Special events for Monday morning, Friday evening, lunch hour
  - **Random events**: Treasure finds, gold veins, goblin merchant discounts (gated behind Stronghold)
- **Dashboard**: WC3-themed local web dashboard at `localhost:19997` with resource bar, base view, achievements, activity feed. Auto-spawns on first hook event
- **New CLI commands**: `peon economy`, `peon achievements`, `peon build`, `peon bunker`, `peon resurrect`, `peon taunt`, `peon dashboard`
- Tab completions for all new commands (bash + fish)
- 13 new BATS tests for game features

## v2.4.1 (2026-02-18)

### Fixed
- Pack rotation: `session_packs` entries in dict format (after cleanup upgrade) were not recognized by the `in pack_rotation` check, causing a new random pack to be picked on every non-SessionStart event — same session could play sounds from different characters each turn
- `SubagentStart` now exits silently after saving state — previously could play `task.acknowledge` sound on the parent session
- Task-spawned subagent sessions now inherit the parent session's voice pack via `pending_subagent_pack` state, ensuring a single conversation always uses one character

## v2.4.0 (2026-02-18)

### Added
- Project-local config override: place a `config.json` at `.claude/hooks/peon-ping/config.json` in any project to override the global config for that project only

### Fixed
- `hook-handle-use.sh`: macOS BSD sed does not support `\s`/`\S` — replaced with POSIX `[[:space:]]`/`[^[:space:]]` classes (closes #212)
- OpenCode plugin: `desktop_notifications: false` in config was ignored — AppleScript notifications now respect the setting (closes #207)
- OpenCode plugin: Linux audio backend chain now matches `peon.sh` priority order (`pw-play` → `paplay` → `aplay`) with correct per-backend volume scaling

## v2.3.0 (2026-02-18)

### Added
- `peon volume [0.0-1.0]` CLI command — get or set volume from the terminal
- `peon rotation [random|round-robin|agentskill]` CLI command — get or set pack rotation mode from the terminal

### Fixed
- macOS overlay (`mac-overlay.js`) is now correctly copied during install — previously only `.sh`/`.ps1`/`.swift` scripts were copied, so the visual overlay banner never appeared
- Resume sessions (`source: "resume"`) preserve the active voice pack instead of picking a new random one

### Changed
- Default pack set reduced to 5 curated WC/SC/Portal packs: `peon`, `peasant`, `sc_kerrigan`, `sc_battlecruiser`, `glados`

## v2.2.3 (2026-02-18)

### Changed
- `UserPromptSubmit` removed from default registered hooks — peon no longer fires on every user message. The `/peon-ping-use` skill hook remains registered under `UserPromptSubmit`. Re-add manually to `~/.claude/settings.json` if you want the annoyed easter egg or `task.acknowledge`.
- `task.acknowledge` default changed to `false` in `config.json` template (was `true`, which caused a sound on every message even without the hook firing explicitly)

This also mitigates the Windows console raw mode issue (#205) where spawning `powershell.exe` on every `UserPromptSubmit` corrupted Claude Code's keyboard input.

## v2.2.2 (2026-02-18)

### Fixed
- `peon-play` and `mac-overlay.js` now resolve correctly on Homebrew/adapter installs where `$PEON_DIR` is remapped (same root cause as the `pack-download.sh` issue fixed in v2.2.1)
- Overlay notifications fall through to standard notifications when `mac-overlay.js` is not found rather than silently failing
- `USE_SOUND_EFFECTS_DEVICE` unbound variable crash in `play_sound` when called from preview context

## v2.2.1 (2026-02-18)

### Fixed
- `peon packs install`, `peon packs use --install`, and `peon packs list --registry` now correctly locate `pack-download.sh` on Homebrew and adapter installs where `$PEON_DIR` is remapped away from the script directory ([#204](https://github.com/PeonPing/peon-ping/pull/204))
- Test isolation: `PEON_TEST=1` now exported globally in test setup so all `run bash peon.sh` calls correctly skip the Homebrew path probe

## v2.2.0 (2026-02-17)

### Added
- MCP server (`mcp/`) for agent-driven sound playback via Model Context Protocol
- OpenClaw adapter documented in README and llms.txt
- `SubagentStart` and `PostToolUseFailure` now registered in installer hook list
- `task.error` and `task.acknowledge` added to "What you'll hear" README table
- `/peon-ping-use` and `/peon-ping-log` skills documented in CLAUDE.md and llms.txt

### Fixed
- MCP server: `pw-play` volume now uses correct 0.0–1.0 float scale (was 0–65536)
- MCP server: reads volume from `config.json` instead of requiring `PEON_VOLUME` env var
- `openclaw.sh`: error events now map to `PostToolUseFailure` (task.error) not `Stop`
- `peon help`: added missing `mobile on/pushover/telegram` and `relay --bind` entries
- Windows installer: `PostToolUseFailure` and `SubagentStart` now registered and handled

### Changed
- Pack count updated to 75+ across all docs
- Hero copy updated to "any AI agent" framing with MCP server mention

## v2.1.1 (2026-02-17)

### Security
- Pass WSL Windows Forms notification message via temp file to prevent PowerShell script injection ([#187](https://github.com/PeonPing/peon-ping/pull/187))

### Added
- macOS JXA Cocoa overlay notifications with configurable `overlay`/`standard` styles and `peon notifications` CLI ([#185](https://github.com/PeonPing/peon-ping/pull/185))
- CESP §5.5 icon resolution chain for pack-aware notifications (sound → category → pack → icon.png → default) with path traversal protection ([#189](https://github.com/PeonPing/peon-ping/pull/189))

### Fixed
- Background relay health check on SessionStart to avoid blocking greeting sound for SSH/devcontainer users ([#190](https://github.com/PeonPing/peon-ping/pull/190))
- OpenCode adapter `task.complete` debounce increased to 5s to prevent repeated notifications in plan mode ([#188](https://github.com/PeonPing/peon-ping/pull/188))

## v2.1.0 (2026-02-17)

### Added
- `peon packs install <pack1,pack2>` and `peon packs install --all` for post-install pack management ([#179](https://github.com/PeonPing/peon-ping/pull/179))
- `peon packs list --registry` to browse all available packs from the registry ([#179](https://github.com/PeonPing/peon-ping/pull/179))
- Bash and fish shell completions for new packs commands ([#179](https://github.com/PeonPing/peon-ping/pull/179))
- Shared `scripts/pack-download.sh` engine extracted from installer ([#179](https://github.com/PeonPing/peon-ping/pull/179))

### Fixed
- Local installs (`--local`) now use correct `INSTALL_DIR` for skill hook paths instead of hardcoded global path ([#180](https://github.com/PeonPing/peon-ping/pull/180))
- Cursor IDE hooks registration now handles flat-array `hooks.json` format

## v2.0.0 (2026-02-16)

### Added
- **Peon Trainer**: Pavel-style daily exercise mode — 300 pushups and 300 squats per day, tracked through your coding sessions
- Trainer CLI: `peon trainer on/off/status/log/goal/help` subcommands
- Trainer reminders piggyback on IDE hook events every ~20 minutes with orc peon voice lines
- Session-start encouragement: peon immediately greets you with a workout prompt when you start a new coding session
- 24 ElevenLabs orc voice lines across 5 categories: session_start, remind, log, complete, slacking
- Pace-based slacking detection: past noon with less than 25% progress triggers slacking voice lines
- Daily auto-reset at midnight
- Configurable goals (`peon trainer goal 200`) and per-exercise goals (`peon trainer goal pushups 100`)
- Trainer section in README with quick start guide

## v1.8.2 (2026-02-15)

### Fixed
- SHA256 checksum-based caching for sound downloads: re-runs skip files that are already downloaded and intact, corrupted files are auto-detected and re-downloaded ([#164](https://github.com/PeonPing/peon-ping/pull/164))
- URL-encode special characters (`?`, `!`, `#`) in filenames when downloading from GitHub, fixing packs with filenames like `New_construction?.mp3` ([#164](https://github.com/PeonPing/peon-ping/pull/164))
- Allow `?` and `!` in sound filenames (`is_safe_filename`) ([#164](https://github.com/PeonPing/peon-ping/pull/164))
- Remove destructive `rm -rf` that wiped all sounds before re-downloading on updates ([#164](https://github.com/PeonPing/peon-ping/pull/164))

## v1.8.1 (2026-02-13)

### Fixed
- Eliminate test race conditions: `peon.sh` runs afplay synchronously in test mode instead of relying on sleep ([#134](https://github.com/PeonPing/peon-ping/pull/134))
- Local uninstall now cleans hooks from global `settings.json` ([#134](https://github.com/PeonPing/peon-ping/pull/134))
- Background sound playback and notifications on WSL/Linux to avoid blocking the IDE ([#132](https://github.com/PeonPing/peon-ping/pull/132))

## v1.8.0 (2026-02-13)

### Added
- **Native Windows support**: PowerShell installer (`install.ps1`), hook script (`peon.ps1`), and uninstaller with two-tier audio fallback (WPF MediaPlayer + SoundPlayer) ([#105](https://github.com/PeonPing/peon-ping/pull/105))
- **Windsurf adapter**: Full CESP adapter for Windsurf Cascade hooks with session tracking ([#130](https://github.com/PeonPing/peon-ping/pull/130))
- **Kilo CLI adapter**: Native TypeScript plugin for Kilo CLI (OpenCode fork) ([#129](https://github.com/PeonPing/peon-ping/pull/129))
- **Install progress bar**: Live-updating per-pack progress bar in TTY mode, dot-based fallback for non-TTY ([#121](https://github.com/PeonPing/peon-ping/pull/121))
- **OpenCode adapter tests**: 21 BATS tests covering install, uninstall, idempotency, XDG support, and icon replacement ([#131](https://github.com/PeonPing/peon-ping/pull/131))

### Fixed
- Fix code injection vulnerability in `peon packs use/remove` — pack args now passed via env vars ([#127](https://github.com/PeonPing/peon-ping/pull/127))
- Fix `pw-play` silent on non-English locales by setting `LC_ALL=C` ([#124](https://github.com/PeonPing/peon-ping/pull/124))
- Fix Telegram API call to use POST body instead of URL params ([#128](https://github.com/PeonPing/peon-ping/pull/128))
- Replace bare `except:` clauses with `except Exception:` across all embedded Python ([#126](https://github.com/PeonPing/peon-ping/pull/126))
- Remove broken symlink before curl download in OpenCode adapter ([#125](https://github.com/PeonPing/peon-ping/pull/125))
- Remove Claude Code paths from OpenCode icon resolution ([#123](https://github.com/PeonPing/peon-ping/pull/123))
- Fix race condition in peon.bats (background afplay timing)
- Fix install.bats `--local` tests to check correct settings.json path

## v1.7.1 (2026-02-13)

### Fixed
- `peon packs list` and other CLI commands now work correctly for Homebrew installs ([#101](https://github.com/PeonPing/peon-ping/issues/101))

## v1.7.0 (2026-02-12)

### Added
- **SSH remote audio support**: Auto-detects SSH sessions and routes audio through a relay server running on your local machine (`peon relay`)
- **Relay daemon mode**: `peon relay --daemon`, `--stop`, `--status` for persistent background relay
- **Devcontainer / Codespaces support**: Auto-detects container environments and routes audio to `host.docker.internal`
- **Mobile push notifications**: `peon mobile ntfy|pushover|telegram` — get phone notifications via ntfy.sh, Pushover, or Telegram
- **Enhanced `peon status`**: Shows active pack, installed pack count, and detected IDE ([#91](https://github.com/PeonPing/peon-ping/pull/91))
- **Relay test suite**: 20 tests covering health, playback, path traversal protection, notifications, and daemon mode
- **Automated Homebrew tap updates**: Release workflow now auto-updates `PeonPing/homebrew-tap`

### Fixed
- Prevent duplicate hooks when both global and local installs exist
- Correct Ghostty process name casing in focus detection ([#92](https://github.com/PeonPing/peon-ping/pull/92))
- Suppress replay sounds during session continue ([#19](https://github.com/PeonPing/peon-ping/issues/19))
- Harden installer reliability ([#93](https://github.com/PeonPing/peon-ping/pull/93))

## v1.6.0 (2026-02-12)

### Breaking
- **Subcommand CLI**: All `--flag` commands replaced with subcommands. `peon --pause` is now `peon pause`, `peon --packs` is now `peon packs list`, etc. ([#90](https://github.com/PeonPing/peon-ping/pull/90))

### Added
- **Homebrew install**: `brew install PeonPing/tap/peon-ping` as primary install method
- **Multi-IDE messaging**: Updated all docs and landing page to highlight Claude Code, Codex, Cursor, and OpenCode support
- **`peon packs remove`**: Uninstall specific packs without removing everything ([#89](https://github.com/PeonPing/peon-ping/pull/89))
- **`peonping.com/install` redirect**: Clean install URL via Vercel redirect
- **Dynamic pack counts**: peonping.com fetches live pack count from registry at runtime
- **Session replay suppression**: Sounds no longer fire 3x when continuing a session with `claude -c` ([#19](https://github.com/PeonPing/peon-ping/issues/19))

### Fixed
- Handle read-only shell rc files during install ([#86](https://github.com/PeonPing/peon-ping/issues/86))
- Fix raw escape codes in OpenCode adapter output ([#88](https://github.com/PeonPing/peon-ping/pull/88))
- Fix OpenCode adapter registry lookup and add missing plugin file

## v1.5.14 (2026-02-12)

### Added
- **Registry-based pack discovery**: install.sh fetches packs from the [OpenPeon registry](https://github.com/PeonPing/registry) instead of bundling sounds in the repo
- **CESP standard**: Migrated to the [Coding Event Sound Pack Specification](https://github.com/PeonPing/openpeon) with `openpeon.json` manifests
- **Multi-IDE adapters**: Cursor (`adapters/cursor.sh`), Codex (`adapters/codex.sh`), OpenCode (`adapters/opencode.sh`)
- **`--packs` flag**: Install specific packs by name (`--packs=peon,glados,peasant`)
- **Interactive pack picker**: peonping.com lets you select packs and generates a custom install command
- **`silent_window_seconds`**: Suppress sounds for tasks shorter than N seconds ([#82](https://github.com/PeonPing/peon-ping/pull/82))
- **Help on bare invocation**: Running `peon` with no args on a TTY shows usage ([#83](https://github.com/PeonPing/peon-ping/pull/83))
- **Desktop notification toggle**: Independent `desktop_notifications` config option ([#47](https://github.com/PeonPing/peon-ping/issues/47))
- **Duke Nukem** sound pack
- **Red Alert Soviet Soldier** sound pack

### Fixed
- Missing sound file references in several packs
- zsh completions `bashcompinit` ordering

## v1.4.0 (2026-02-12)

### Added
- **Stop debouncing**: Prevents sound spam from rapid background task completions
- **Pack rotation**: Configure multiple packs in `pack_rotation`, each session picks one randomly
- **CLAUDE_CONFIG_DIR** support for non-standard Claude installs ([#61](https://github.com/PeonPing/peon-ping/pull/61))
- **13 community sound packs**: Czech (peon_cz, peasant_cz), Spanish (peon_es, peasant_es), RA2 Kirov, WC2 Peasant, AoE2, Russian Brewmaster, Elder Scrolls (Molag Bal, Sheogorath), Dota 2 Axe, Helldivers 2, Sopranos, Rick Sanchez

## v1.2.0 (2026-02-11)

### Added
- **WSL2 (Windows) support**: PowerShell `MediaPlayer` audio backend with visual popup notifications
- **PermissionRequest hook**: Sound alert when IDE needs permission approval
- **`peon --pack` command**: Switch packs from CLI with tab completion and cycling
- **Performance**: Consolidated 5 Python invocations into 1 per hook event
- **Polish Orc Peon** sound pack ([#9](https://github.com/PeonPing/peon-ping/pull/9))
- **French packs**: Human Peasant (FR) and Orc Peon (FR) ([#7](https://github.com/PeonPing/peon-ping/pull/7))

### Fixed
- Prevent install.sh from hanging when run via `curl | bash` ([#8](https://github.com/PeonPing/peon-ping/pull/8))

## v1.1.0 (2026-02-11)

### Added
- **Pause/mute toggle**: `peon --toggle` CLI and `/peon-ping-toggle` slash command ([#6](https://github.com/PeonPing/peon-ping/pull/6))
- **Battlecruiser + Kerrigan** sound packs
- **RA2 Soviet Engineer** sound pack
- **Self-update check**: Checks for new versions once per day
- **BATS test suite**: 30+ automated tests with CI ([#5](https://github.com/PeonPing/peon-ping/pull/5))
- **Terminal-agnostic tab titles**: ANSI escape sequences instead of AppleScript ([#3](https://github.com/PeonPing/peon-ping/pull/3))

### Fixed
- Hook runner compatibility ([#5](https://github.com/PeonPing/peon-ping/pull/5))

## v1.0.0 (2026-02-10)

### Added
- Initial release
- Warcraft III Orc Peon and GLaDOS sound packs
- Claude Code hook for `SessionStart`, `UserPromptSubmit`, `Stop`, `Notification`
- Desktop notifications (macOS)
- Terminal tab title updates
- Agent session detection (suppress sounds in delegate mode)
- macOS + Linux audio support
