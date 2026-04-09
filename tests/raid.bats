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
  run bash "$PEON_SH" raid murloc
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
