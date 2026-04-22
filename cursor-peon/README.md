# Peon Mascot

A tiny WC3 peon lives in your Cursor status bar — and slowly takes over the rest of your IDE.

## Status bar mascot

- Sits as `🧌 Lv.X` until something interesting happens.
- Flashes for: level up, boss kill, achievement, item drop (Uncommon+), combo milestone.
- Hover for live stats. Click to poke.

## Secret legendary themes (7)

Each legendary item unlocks a hidden Cursor color theme:

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

## Theme outfits

Each Peon theme also swaps your **font, cursor style, and cursor blink** for a complete vibe change:

| Theme | Font | Cursor |
|---|---|---|
| Frostmourne | Menlo | block + phase |
| Wirt's Leg | Courier New | line + blink |
| Thunderfury | Menlo | underline + expand |
| Unstoppable Force | Menlo bold | block + solid (no blink) |
| Warglaives of Azzinoth | Monaco | line-thin + smooth |
| Ashbringer | Georgia serif | line + smooth |
| Cheese | Comic Sans MS | underline + expand |

Disable: `peonMascot.outfits.enabled: false`. Reset everything: `Peon: Reset all customizations`.

## Live window title

Your title bar becomes:
```
🧌 Lv.8 ⚡18/30 💰3,540 — myproject — Cursor
```

Disable: `peonMascot.windowTitle.enabled: false`.

## Editor decorations

Comment tags get WC3 gutter icons:
- `TODO` / `XXX` → 🪓 *Quest awaits, peon.*
- `FIXME` → 🔥 *Cursed bug. Cleanse it.*
- `HACK` → 👹 *Forbidden magic at work.*
- `NOTE` → 📜 *Ancient scroll.*

Lint errors get a 💀 in the gutter beside the red squiggle. Save events briefly flash the file in parchment yellow.

Disable: `peonMascot.decorations.enabled: false`.

## WC3 file icon theme

Activate: `Cmd+Shift+P` → **Preferences: File Icon Theme** → **Peon: WC3 Icons**.

- Folders → 🏰 Town Halls
- `node_modules` → 🐲 Murloc Lair
- `.git` → 📜 Ancient Scrolls
- `package.json` → 🍞 Rations
- `.env` → 🗝️ Key of Power
- `tests/` → ⚔️ Trial of Combat
- `*.sh` → 🪓 Battle Axe
- `*.md` → 📜 Tome
- `Dockerfile` → 🛡️ Bunker
- `*.py` → 🐍, `*.ts`/`*.js` → 💎, `*.json` → 📜

## Install

```bash
./install.sh
```

Then `Cmd+Shift+P` → **Developer: Reload Window**.

## Commands

`Cmd+Shift+P` →
- **Peon: Show unlocked themes** — pick a theme to apply
- **Peon: Toggle mascot** — show/hide
- **Peon: Poke the peon** — random voice line
- **Peon: Reset all customizations** — restore your original font/cursor/title
