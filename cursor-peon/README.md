# Peon Mascot

A tiny WC3 peon lives in your Cursor status bar.

## What it does

- Sits quietly as `🧌 Lv.X` most of the time.
- Flashes for important peon-ping events:
  - **Level up** — `⭐ LEVEL UP! Lv.9 Illidan`
  - **Boss killed** — `💀 SLAIN: Pit Lord Mannoroth (+10000g)`
  - **Achievement** — `🏆 ACHIEVEMENT: Boss Slayer`
  - **Item drop (Uncommon+)** — `🟢 DROP: Serrated Blade (Uncommon)`
  - **Combo milestone** — `🔥 COMBO x100!`
- Hover for live stats (level, gold, lumber, fatigue, combo, active boss, themes unlocked).
- Click to poke.

## Secret themes

Each of the 7 legendary items unlocks a hidden Cursor color theme:

| Legendary | Theme | Vibe |
|---|---|---|
| Frostmourne | `Peon: Frostmourne` | Icy Lich King blue |
| Wirt's Leg | `Peon: Wirt's Leg` | Brown wooden, intentionally bad |
| Thunderfury | `Peon: Thunderfury` | Electric purple + lightning yellow |
| The Unstoppable Force | `Peon: The Unstoppable Force` | Aggressive blood red |
| Warglaives of Azzinoth | `Peon: Warglaives of Azzinoth` | Demon hunter green |
| Ashbringer | `Peon: Ashbringer` | Holy light parchment (light theme) |
| Cheese | `Peon: Cheese (Mmm)` | Yellow everything (light theme) |

When a legendary drops, you get a notification with **Apply Theme**. Already-owned legendaries unlock silently on first launch — run **Peon: Show unlocked themes** to apply.

## Install

```bash
./install.sh
```

Reload your Cursor window after install (`Cmd+Shift+P` → "Developer: Reload Window").

## Commands

`Cmd+Shift+P` →
- **Peon: Show unlocked themes** — pick a theme to apply
- **Peon: Toggle mascot** — show/hide
- **Peon: Poke the peon** — random voice line
