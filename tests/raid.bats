#!/usr/bin/env bats

load setup.bash

setup() {
  setup_test_env
  # Give player enough resources and buildings for raids
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['economy'] = {'gold': 50000, 'lumber': 20000}
s['buildings'] = {
  'burrow': {'built_at': 1}, 'watch_tower': {'built_at': 1}, 'war_mill': {'built_at': 1},
  'altar': {'built_at': 1}, 'lumber_mill': {'built_at': 1}, 'tavern': {'built_at': 1},
  'stronghold': {'built_at': 1}, 'spirit_lodge': {'built_at': 1}, 'barracks': {'built_at': 1},
  'blacksmith': {'built_at': 1}, 'arcane_sanctum': {'built_at': 1}, 'fortress': {'built_at': 1},
  'dark_portal': {'built_at': 1}, 'citadel': {'built_at': 1}
}
s['stats'] = {'level': 9, 'tasks_completed': 10000}
s['boss_kills_total'] = 30
s['boss_kills'] = {'kobold': 10, 'troll': 5, 'ogre': 5, 'infernal': 5, 'mannoroth': 3, 'archimonde': 2}
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
}

teardown() {
  teardown_test_env
}

# ============================================================
# peon raid CLI
# ============================================================

@test "raid status with no active boss shows available bosses" {
  run bash "$PEON_SH" raid
  [ "$status" -eq 0 ]
  [[ "$output" == *"No active raid"* ]]
  [[ "$output" == *"Kobold Taskmaster"* ]]
}

@test "raid requires dark_portal" {
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
del s['buildings']['dark_portal']
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run bash "$PEON_SH" raid
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dark Portal"* ]]
}

@test "raid kobold starts a raid" {
  run bash "$PEON_SH" raid kobold
  [ "$status" -eq 0 ]
  [[ "$output" == *"RAID STARTED"* ]]
  [[ "$output" == *"Kobold Taskmaster"* ]]
  # State should have active_boss
  local hp
  hp=$(python3 -c "import json; s=json.load(open('$TEST_DIR/.state.json')); print(s['active_boss']['id'])")
  [ "$hp" = "kobold" ]
}

@test "raid refuses if already in a raid" {
  bash "$PEON_SH" raid kobold
  run bash "$PEON_SH" raid troll
  [ "$status" -eq 1 ]
  [[ "$output" == *"Already fighting"* ]]
}

@test "raid unknown boss fails" {
  run bash "$PEON_SH" raid dragon
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown boss"* ]]
}

@test "raid status shows active boss" {
  bash "$PEON_SH" raid kobold
  run bash "$PEON_SH" raid
  [ "$status" -eq 0 ]
  [[ "$output" == *"Kobold Taskmaster"* ]]
  [[ "$output" == *"HP"* ]]
}

@test "raid entry fee is deducted" {
  local gold_before
  gold_before=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['economy']['gold'])")
  bash "$PEON_SH" raid troll
  local gold_after
  gold_after=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['economy']['gold'])")
  [ "$gold_after" -eq $((gold_before - 50)) ]
}

@test "raid locked boss shows requirements" {
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['boss_kills_total'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run bash "$PEON_SH" raid
  [ "$status" -eq 0 ]
  [[ "$output" == *"LOCKED"* ]]
}

# ============================================================
# Boss combat via hook events
# ============================================================

@test "task.complete deals damage to active boss" {
  bash "$PEON_SH" raid kobold
  local hp_before
  hp_before=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local hp_after
  hp_after=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  [ "$hp_after" -lt "$hp_before" ]
}

@test "frostmourne doubles raid damage via boss_dmg_mult" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['atk_min'] = 0
s['active_boss']['atk_max'] = 0
s['active_boss']['hp'] = 100000
s['active_boss']['max_hp'] = 100000
s['army'] = {}
s['equipped'] = ['war_axe']
s['inventory'] = []
s['fatigue'] = 0
s['combo_count'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  local hp_before hp_after dmg_no_mult
  hp_before=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  hp_after=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  dmg_no_mult=$((hp_before - hp_after))
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['hp'] = 100000
s['equipped'] = ['war_axe', 'frostmourne']
s['combo_count'] = 0
s['last_stop_time'] = 0
s['fatigue'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  hp_before=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  hp_after=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  local dmg_with_mult=$((hp_before - hp_after))
  [ "$dmg_with_mult" = "$((dmg_no_mult * 2))" ]
}

@test "boss_armor reduces incoming counter-attack damage" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['atk_min'] = 100
s['active_boss']['atk_max'] = 100
s['active_boss']['hp'] = 100000
s['army'] = {'tauren': [80] * 5}
s['equipped'] = ['iron_shield', 'infernal_core']
s['item_durability'] = {'iron_shield': 50, 'infernal_core': 100}
s['inventory'] = []
s['fatigue'] = 0
s['combo_count'] = 0
s['last_stop_time'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local armor logged_dmg
  armor=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('armor',0))")
  logged_dmg=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('boss_dmg',-1))")
  [ "$armor" = "75" ]
  [ "$logged_dmg" = "25" ]
}

@test "depletion_ext extends gold mine threshold" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
del s['active_boss']
s['equipped'] = ['skull_shield', 'periapt_of_vitality']
s['item_durability'] = {'skull_shield': 50, 'periapt_of_vitality': 75}
s['economy']['daily_tasks'] = 60
s['economy']['gold'] = 0
s['fatigue'] = 0
s['last_stop_time'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local gold
  gold=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['economy']['gold'])")
  [ "$gold" -ge 10 ]
}

@test "boss_double_loot stacks across items" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['atk_min'] = 0
s['active_boss']['atk_max'] = 0
s['active_boss']['hp'] = 1
s['active_boss']['loot_tier'] = ['common']
s['army'] = {}
s['equipped'] = ['crown_of_eredar', 'helm_of_domination']
s['item_durability'] = {'crown_of_eredar': 200, 'helm_of_domination': 200}
s['inventory'] = []
s['fatigue'] = 0
s['combo_count'] = 0
s['last_stop_time'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local n_items
  n_items=$(python3 -c "import json; print(len(json.load(open('$TEST_DIR/.state.json'))['inventory']))")
  [ "$n_items" -ge 4 ]
}

@test "boss defeat gives gold reward" {
  # Set boss to 1 HP so next task kills it
  python3 -c "
import json, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
s['active_boss'] = {'id': 'kobold', 'name': 'Kobold Taskmaster', 'hp': 1, 'max_hp': 30, 'deadline': dl, 'loot_tier': 'common', 'entry_fee': 0, 'gold_reward': 50, 'lumber_reward': 25, 'atk_min': 0, 'atk_max': 0}
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  local gold_before
  gold_before=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['economy']['gold'])")
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local gold_after
  gold_after=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['economy']['gold'])")
  [ "$gold_after" -gt "$gold_before" ]
  # Boss should be cleared
  local boss
  boss=$(python3 -c "import json; s=json.load(open('$TEST_DIR/.state.json')); print(s.get('active_boss') or 'None')")
  [ "$boss" = "None" ]
  # Boss kills should be tracked (was 30 from setup, now 31)
  local kills
  kills=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json')).get('boss_kills_total', 0))")
  [ "$kills" -eq 31 ]
}

@test "boss defeat adds history entry" {
  python3 -c "
import json, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
s['active_boss'] = {'id': 'kobold', 'name': 'Kobold Taskmaster', 'hp': 1, 'max_hp': 30, 'deadline': dl, 'loot_tier': 'common', 'entry_fee': 0, 'gold_reward': 50, 'lumber_reward': 25, 'atk_min': 0, 'atk_max': 0}
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local result
  result=$(python3 -c "import json; s=json.load(open('$TEST_DIR/.state.json')); print(s.get('boss_history', [{}])[-1].get('result', ''))")
  [ "$result" = "victory" ]
}

@test "boss defeat drops an item" {
  python3 -c "
import json, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
s['active_boss'] = {'id': 'kobold', 'name': 'Kobold Taskmaster', 'hp': 1, 'max_hp': 30, 'deadline': dl, 'loot_tier': 'common', 'entry_fee': 0, 'gold_reward': 50, 'lumber_reward': 25, 'atk_min': 0, 'atk_max': 0}
s['inventory'] = []
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local inv_len
  inv_len=$(python3 -c "import json; print(len(json.load(open('$TEST_DIR/.state.json')).get('inventory', [])))")
  [ "$inv_len" -ge 1 ]
}

@test "task.complete with army_heal item equipped does not crash" {
  # Regression test for silent NameError at line 4760 (`army`/`UNITS` instead of `_army`/`_UHP`)
  # that aborted every Stop event and blocked boss damage for users with army_heal items equipped.
  python3 -c "
import json, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
s['active_boss'] = {'id': 'kobold', 'name': 'Kobold Taskmaster', 'hp': 100, 'max_hp': 100, 'deadline': dl, 'loot_tier': 'common', 'entry_fee': 0, 'gold_reward': 50, 'lumber_reward': 25, 'atk_min': 0, 'atk_max': 0}
s['equipped'] = ['amulet_of_spell']
s['item_durability'] = {'amulet_of_spell': 150}
s['army'] = {'grunt': [30, 30], 'tauren': [40]}
s['tauren_brave_migrated'] = True
s['brave_refunded'] = True
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  [ "$PEON_EXIT" -eq 0 ]
  [ -z "$PEON_STDERR" ] || ! grep -q "NameError\|Traceback" <<< "$PEON_STDERR"
  local hp_after
  hp_after=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  [ "$hp_after" -lt 100 ]
  local tauren_hp
  tauren_hp=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['army']['tauren'][0])")
  [ "$tauren_hp" -gt 40 ]
}

@test "task.complete with army_heal but no army does not crash" {
  python3 -c "
import json, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
s['active_boss'] = {'id': 'kobold', 'name': 'Kobold Taskmaster', 'hp': 100, 'max_hp': 100, 'deadline': dl, 'loot_tier': 'common', 'entry_fee': 0, 'gold_reward': 50, 'lumber_reward': 25, 'atk_min': 0, 'atk_max': 0}
s['equipped'] = ['amulet_of_spell']
s['item_durability'] = {'amulet_of_spell': 150}
s['army'] = {}
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  [ "$PEON_EXIT" -eq 0 ]
  [ -z "$PEON_STDERR" ] || ! grep -q "NameError\|Traceback" <<< "$PEON_STDERR"
  local hp_after
  hp_after=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  [ "$hp_after" -lt 100 ]
}

@test "amulet_of_spell heals at most v HP total per task (not per unit)" {
  # Regression: previously army_heal applied v HP to EVERY unit, so an army of N units gained
  # v*N HP per task and bosses could not damage the army. Should now heal v HP TOTAL.
  python3 -c "
import json, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
s['active_boss'] = {'id': 'kobold', 'name': 'Kobold Taskmaster', 'hp': 100, 'max_hp': 100, 'deadline': dl, 'loot_tier': 'common', 'entry_fee': 0, 'gold_reward': 50, 'lumber_reward': 25, 'atk_min': 0, 'atk_max': 0}
s['equipped'] = ['amulet_of_spell']
s['item_durability'] = {'amulet_of_spell': 150}
s['army'] = {'grunt': [10, 10, 10, 10, 10], 'tauren': [40, 40, 40]}
s['tauren_brave_migrated'] = True
s['brave_refunded'] = True
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  [ "$PEON_EXIT" -eq 0 ]
  local total_hp before_hp delta
  before_hp=$((10*5 + 40*3))
  total_hp=$(python3 -c "import json; a=json.load(open('$TEST_DIR/.state.json'))['army']; print(sum(h for hps in a.values() for h in hps))")
  delta=$((total_hp - before_hp))
  # Amulet v=3, kobold atk_max=0 → exactly 3 HP total restored
  [ "$delta" -eq 3 ]
}

@test "amulet_of_spell heal targets most-wounded by percentage" {
  # With a tauren at 197/200 (1.5% deficit) and a grunt at 28/30 (6.7% deficit),
  # the 3-HP heal pool should go to the grunt first.
  python3 -c "
import json, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
s['active_boss'] = {'id': 'kobold', 'name': 'Kobold Taskmaster', 'hp': 100, 'max_hp': 100, 'deadline': dl, 'loot_tier': 'common', 'entry_fee': 0, 'gold_reward': 50, 'lumber_reward': 25, 'atk_min': 0, 'atk_max': 0}
s['equipped'] = ['amulet_of_spell']
s['item_durability'] = {'amulet_of_spell': 150}
s['army'] = {'tauren': [197], 'grunt': [28]}
s['tauren_brave_migrated'] = True
s['brave_refunded'] = True
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  [ "$PEON_EXIT" -eq 0 ]
  local grunt tauren
  grunt=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['army']['grunt'][0])")
  tauren=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['army']['tauren'][0])")
  # Grunt should be fully healed first (deficit 2 HP, 6.7%), then tauren gets the remaining 1 HP.
  [ "$grunt" -eq 30 ]
  [ "$tauren" -eq 198 ]
}

@test "scroll_of_heal consumable heals 15 HP TOTAL across army" {
  bash "$PEON_SH" hire grunt 5
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['inventory'] = ['scroll_of_heal']
s['army'] = {'grunt': [5, 5, 5, 5, 5]}
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run bash "$PEON_SH" use scroll_of_heal
  [ "$status" -eq 0 ]
  local total
  total=$(python3 -c "import json; print(sum(json.load(open('$TEST_DIR/.state.json'))['army']['grunt']))")
  # Started at 25, +15 = 40
  [ "$total" -eq 40 ]
}

@test "healing_ward consumable still fully heals every unit" {
  bash "$PEON_SH" hire grunt 5
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['inventory'] = ['healing_ward']
s['army'] = {'grunt': [1, 1, 1, 1, 1]}
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run bash "$PEON_SH" use healing_ward
  [ "$status" -eq 0 ]
  local total
  total=$(python3 -c "import json; print(sum(json.load(open('$TEST_DIR/.state.json'))['army']['grunt']))")
  # 5 grunts at full = 150
  [ "$total" -eq 150 ]
}

@test "python stderr is captured to .error.log, not discarded" {
  # Regression: previously 2>/dev/null swallowed silent NameError crashes.
  # Ensure errors are now written to $PEON_DIR/.error.log.
  rm -f "$TEST_DIR/.error.log"
  # Force a python crash by feeding malformed JSON
  run bash -c "printf 'not json' | bash '$PEON_SH'"
  [ -f "$TEST_DIR/.error.log" ]
  grep -q "Traceback\|Error" "$TEST_DIR/.error.log"
}

@test "build dark_portal command works" {
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
del s['buildings']['dark_portal']
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run bash "$PEON_SH" build dark_portal
  [ "$status" -eq 0 ]
  [[ "$output" == *"Built dark_portal"* ]]
}

# ============================================================
# Poison (real-time DoT)
# ============================================================
# Setup helper: stand up a 4-day Mannoroth-shaped boss with poison_last_tick
# exactly 1h ago. Equips the requested items.
# Rates: venom_orb 0.05%/hr, black_arrow 0.1%/hr, thunderfury 0.2%/hr.
# vs 40000 HP → 20, 40, 80 dmg/hr respectively.
_poison_setup() {
  local equip_json="$1"
  python3 -c "
import json, time, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=3)).isoformat()
s['active_boss'] = {
    'id':'mannoroth','name':'Pit Lord Mannoroth',
    'hp':40000,'max_hp':40000,'deadline':dl,'spawned_at':int(time.time()) - 86400,
    'loot_tier':'common','entry_fee':0,'gold_reward':50,'lumber_reward':25,
    'atk_min':0,'atk_max':0,
    'poison_last_tick': int(time.time()) - 3600,
}
s['equipped'] = $equip_json
s['item_durability'] = {e: 200 for e in $equip_json}
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
}

@test "poison ticks on a non-task event (PreCompact)" {
  _poison_setup "['thunderfury']"
  # Thunderfury 0.2%/hr × 40000 = 80 dmg/hr. ~80 over 1 hour.
  run_peon '{"hook_event_name":"PreCompact","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  [ "$PEON_EXIT" -eq 0 ]
  local hp poison
  hp=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  poison=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('bk',{}).get('poison',0))")
  [ "$poison" -ge 75 ]
  [ "$poison" -le 85 ]
  [ "$hp" -eq $((40000 - poison)) ]
}

@test "poison rate is additive across stacked items" {
  _poison_setup "['venom_orb','black_arrow','thunderfury']"
  # 0.05+0.1+0.2 = 0.35%/hr × 40000 = 140 dmg/hr.
  run_peon '{"hook_event_name":"PreCompact","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local poison
  poison=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('bk',{}).get('poison',0))")
  [ "$poison" -ge 135 ]
  [ "$poison" -le 145 ]
}

@test "poison ticks during task.complete in addition to attack damage" {
  _poison_setup "['thunderfury']"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local base poison
  base=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('bk',{}).get('base',0))")
  poison=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('bk',{}).get('poison',0))")
  [ "$base" -eq 1 ]
  [ "$poison" -ge 75 ]
}

@test "poison bypasses fatigue exhaustion" {
  _poison_setup "['thunderfury']"
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['fatigue'] = 999  # well past _fatigue_exhaust threshold
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local poison
  poison=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('bk',{}).get('poison',0))")
  # Even with EXHAUSTED zeroing the attack, poison still lands.
  [ "$poison" -ge 75 ]
}

@test "poison is uncapped over a long AFK gap" {
  _poison_setup "['thunderfury']"
  # Simulate 100 hours since last tick. 80 dmg/hr × 100h = 8000 dmg.
  python3 -c "
import json, time
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['poison_last_tick'] = int(time.time()) - (100 * 3600)
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"PreCompact","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local poison
  poison=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('bk',{}).get('poison',0))")
  [ "$poison" -ge 7900 ]
  [ "$poison" -le 8100 ]
}

@test "poison-only kill is tagged 'poisoned' in history" {
  _poison_setup "['thunderfury']"
  python3 -c "
import json, time
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['hp'] = 50  # 80 dmg/hr × 1h overkills
s['active_boss']['poison_last_tick'] = int(time.time()) - 3600
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"PreCompact","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local poisoned
  poisoned=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json')).get('boss_history',[{}])[-1].get('poisoned'))")
  [ "$poisoned" = "True" ]
}

@test "no poison equipped means no tick" {
  _poison_setup "[]"
  run_peon '{"hook_event_name":"PreCompact","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local hp poison
  hp=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  poison=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('bk',{}).get('poison',0))")
  [ "$poison" -eq 0 ]
  [ "$hp" -eq 40000 ]
}

@test "PermissionRequest does not engage the boss" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['atk_min'] = 100
s['active_boss']['atk_max'] = 100
s['active_boss']['hp'] = 100
s['active_boss']['log'] = []
s['army'] = {'tauren': [80] * 5}
s['equipped'] = []
s['fatigue'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local hp army_total log_len
  hp=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  army_total=$(python3 -c "import json; a=json.load(open('$TEST_DIR/.state.json'))['army']; print(sum(h for hps in a.values() for h in hps))")
  log_len=$(python3 -c "import json; print(len(json.load(open('$TEST_DIR/.state.json'))['active_boss'].get('log', [])))")
  [ "$hp" -eq 100 ]
  [ "$army_total" -eq 400 ]
  [ "$log_len" -eq 0 ]
}

@test "resource.limit (PreCompact) tags battle log with reason" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['atk_min'] = 0
s['active_boss']['atk_max'] = 0
s['active_boss']['hp'] = 100
s['active_boss']['log'] = []
s['army'] = {}
s['equipped'] = []
s['fatigue'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"PreCompact","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local counter
  counter=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('counter',''))")
  [[ "$counter" == *"Compacting"* ]]
}

@test "user.spam tags battle log with reason" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['atk_min'] = 0
s['active_boss']['atk_max'] = 0
s['active_boss']['hp'] = 100
s['active_boss']['log'] = []
s['army'] = {}
s['equipped'] = []
s['fatigue'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  for i in 1 2 3; do
    run_peon '{"hook_event_name":"UserPromptSubmit","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  done
  local counter
  counter=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1].get('counter',''))")
  [[ "$counter" == *"poking"* ]]
}

@test "combo raid damage scales with player level" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json, time
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['atk_min'] = 0
s['active_boss']['atk_max'] = 0
s['active_boss']['hp'] = 100000
s['active_boss']['max_hp'] = 100000
s['army'] = {}
s['equipped'] = []
s['inventory'] = []
s['fatigue'] = 0
s['combo_count'] = 100
s['combo_ts'] = time.time()
s['stats']['tasks_completed'] = 500
s['last_stop_time'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local combo_dmg
  combo_dmg=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1]['bk'].get('combo', 0))")
  [ "$combo_dmg" = "50" ]
}

@test "combo raid damage at level 1 keeps original 1-per-10 rate" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json, time
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['atk_min'] = 0
s['active_boss']['atk_max'] = 0
s['active_boss']['hp'] = 100000
s['active_boss']['max_hp'] = 100000
s['army'] = {}
s['equipped'] = []
s['inventory'] = []
s['fatigue'] = 0
s['combo_count'] = 100
s['combo_ts'] = time.time()
s['stats']['tasks_completed'] = 0
s['last_stop_time'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local combo_dmg
  combo_dmg=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1]['bk'].get('combo', 0))")
  [ "$combo_dmg" = "10" ]
}

@test "bloodstone raid damage scales with player level" {
  bash "$PEON_SH" raid kobold
  python3 -c "
import json, time
s = json.load(open('$TEST_DIR/.state.json'))
s['active_boss']['atk_min'] = 0
s['active_boss']['atk_max'] = 0
s['active_boss']['hp'] = 100000
s['active_boss']['max_hp'] = 100000
s['army'] = {}
s['equipped'] = ['bloodstone']
s['item_durability'] = {'bloodstone': 100}
s['inventory'] = []
s['fatigue'] = 0
s['combo_count'] = 100
s['combo_ts'] = time.time()
s['stats']['tasks_completed'] = 10000
s['last_stop_time'] = 0
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local bloodstone_dmg
  bloodstone_dmg=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['log'][-1]['bk'].get('bloodstone', 0))")
  [ "$bloodstone_dmg" = "90" ]
}
