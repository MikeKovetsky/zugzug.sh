# Changelog

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
