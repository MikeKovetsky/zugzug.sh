# Peon Mascot

A tiny WC3 peon lives in your Cursor status bar.

- Walks back and forth saying `wrk wrk!`, `zug zug`, etc.
- Reacts to peon-ping events:
  - **task.complete** → chops a tree, drops a log
  - **task.error** → falls over, "ouch!"
  - **combo ≥ 3** → "GODLIKE!" / "RAMPAGE!" / "UNSTOPPABLE!"
  - **fatigue ≥ 30** → falls asleep on the job
  - **level up** → ⭐ LV UP! ⭐
  - **user.spam (sass)** → "stop click!"
- Hover for live stats (level, gold, lumber, fatigue, combo, active boss).
- Click to poke.

## Install

```bash
./install.sh
```

Reload your Cursor window after install (`Cmd+Shift+P` → "Reload Window").

## Toggle

`Cmd+Shift+P` → "Peon: Toggle mascot"
