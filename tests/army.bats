#!/usr/bin/env bats

load setup.bash

setup() {
  setup_test_env
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
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
}

teardown() {
  teardown_test_env
}

# ============================================================
# peon army CLI
# ============================================================

@test "army shows empty army" {
  run bash "$PEON_SH" army
  [ "$status" -eq 0 ]
  [[ "$output" == *"Army"* ]]
  [[ "$output" == *"No units hired"* ]]
}

@test "army requires barracks" {
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
del s['buildings']['barracks']
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run bash "$PEON_SH" army
  [ "$status" -eq 1 ]
  [[ "$output" == *"Barracks"* ]]
}

# ============================================================
# peon hire CLI
# ============================================================

@test "hire grunt succeeds" {
  run bash "$PEON_SH" hire grunt
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hired"* ]]
  [[ "$output" == *"Grunt"* ]]
  local count
  count=$(python3 -c "import json; a=json.load(open('$TEST_DIR/.state.json')).get('army',{}); v=a.get('grunt',[]); print(len(v) if isinstance(v,list) else v)")
  [ "$count" -eq 1 ]
}

@test "hire deducts gold" {
  local gold_before
  gold_before=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['economy']['gold'])")
  bash "$PEON_SH" hire grunt
  local gold_after
  gold_after=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['economy']['gold'])")
  [ "$gold_after" -eq $((gold_before - 100)) ]
}

@test "hire deducts lumber for raider" {
  local lumber_before
  lumber_before=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['economy']['lumber'])")
  bash "$PEON_SH" hire raider
  local lumber_after
  lumber_after=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['economy']['lumber'])")
  [ "$lumber_after" -eq $((lumber_before - 500)) ]
}

@test "hire multiple units at once" {
  run bash "$PEON_SH" hire grunt 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"3x Grunt"* ]]
  local count
  count=$(python3 -c "import json; a=json.load(open('$TEST_DIR/.state.json')).get('army',{}); v=a.get('grunt',[]); print(len(v) if isinstance(v,list) else v)")
  [ "$count" -eq 3 ]
}

@test "hire unknown unit fails" {
  run bash "$PEON_SH" hire murloc
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown unit"* ]]
}

@test "hire requires barracks" {
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
del s['buildings']['barracks']
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run bash "$PEON_SH" hire grunt
  [ "$status" -eq 1 ]
  [[ "$output" == *"Barracks"* ]]
}

@test "hire fails with insufficient gold" {
  python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
s['economy']['gold'] = 5
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run bash "$PEON_SH" hire grunt
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not enough"* ]]
}

@test "hire respects food cap" {
  # food cap = 12 + 8 (fortress) + 10 (citadel) = 30
  # grunts cost 1 food each, 30 fills it exactly
  bash "$PEON_SH" hire grunt 30
  # 31st should fail (31 > 30)
  run bash "$PEON_SH" hire grunt
  [ "$status" -eq 1 ]
  [[ "$output" == *"food"* ]]
}

@test "hire tracks units_hired_total stat" {
  bash "$PEON_SH" hire grunt 5
  local total
  total=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json')).get('stats', {}).get('units_hired_total', 0))")
  [ "$total" -eq 5 ]
}

# ============================================================
# peon dismiss CLI
# ============================================================

@test "dismiss removes unit" {
  bash "$PEON_SH" hire grunt 3
  run bash "$PEON_SH" dismiss grunt
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dismissed"* ]]
  local count
  count=$(python3 -c "import json; a=json.load(open('$TEST_DIR/.state.json')).get('army',{}); v=a.get('grunt',[]); print(len(v) if isinstance(v,list) else v)")
  [ "$count" -eq 2 ]
}

@test "dismiss all units clears entry" {
  bash "$PEON_SH" hire grunt 2
  bash "$PEON_SH" dismiss grunt 2
  local has_grunt
  has_grunt=$(python3 -c "import json; print('grunt' in json.load(open('$TEST_DIR/.state.json')).get('army', {}))")
  [ "$has_grunt" = "False" ]
}

@test "dismiss nonexistent unit fails" {
  run bash "$PEON_SH" dismiss grunt
  [ "$status" -eq 1 ]
  [[ "$output" == *"No"* ]]
}

# ============================================================
# Army damage in boss combat
# ============================================================

@test "army deals extra damage to boss" {
  bash "$PEON_SH" hire grunt 5
  bash "$PEON_SH" raid kobold
  local hp_before
  hp_before=$(python3 -c "import json; print(json.load(open('$TEST_DIR/.state.json'))['active_boss']['hp'])")
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local hp_after
  hp_after=$(python3 -c "import json; s=json.load(open('$TEST_DIR/.state.json')); b=s.get('active_boss'); print(b['hp'] if b else 0)")
  # Base dmg 1 + army dmg 5 (5 grunts * 1) + blacksmith bonus = at least 6 total
  [ "$hp_after" -lt "$hp_before" ]
  local dmg=$((hp_before - hp_after))
  [ "$dmg" -ge 6 ]
}

@test "army damage shows in boss log" {
  bash "$PEON_SH" hire raider
  bash "$PEON_SH" raid kobold
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local has_army
  has_army=$(python3 -c "
import json
s = json.load(open('$TEST_DIR/.state.json'))
b = s.get('active_boss')
if b and b.get('log'):
    print('army' in b['log'][-1].get('bk', {}))
else:
    print(False)
")
  [ "$has_army" = "True" ]
}

# ============================================================
# Boss attacks army each turn
# ============================================================

@test "boss with atk_max kills units on task complete" {
  bash "$PEON_SH" hire grunt 10
  python3 -c "
import json, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
s['active_boss'] = {'id': 'archimonde', 'name': 'Archimonde', 'hp': 50000, 'max_hp': 100000, 'deadline': dl, 'loot_tier': 'epic', 'entry_fee': 0, 'gold_reward': 50000, 'lumber_reward': 15000, 'atk_min': 3, 'atk_max': 10}
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local count
  count=$(python3 -c "import json; a=json.load(open('$TEST_DIR/.state.json')).get('army',{}); v=a.get('grunt',[]); print(len(v) if isinstance(v,list) else v)")
  # archimonde deals 3-10 damage per turn to units with 30 HP each
  # some grunts should have taken damage (total HP < 300)
  total_hp=$(python3 -c "import json; a=json.load(open('$TEST_DIR/.state.json')).get('army',{}); v=a.get('grunt',[]); print(sum(v) if isinstance(v,list) else v*30)")
  [ "$total_hp" -lt 300 ]
}

@test "boss with atk_max 0 does not kill units" {
  bash "$PEON_SH" hire grunt 3
  bash "$PEON_SH" raid kobold
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local count
  count=$(python3 -c "import json; a=json.load(open('$TEST_DIR/.state.json')).get('army',{}); v=a.get('grunt',[]); print(len(v) if isinstance(v,list) else v)")
  [ "$count" -eq 3 ]
}

@test "shaman reduces boss attack casualties" {
  bash "$PEON_SH" hire grunt 5
  bash "$PEON_SH" hire shaman 2
  python3 -c "
import json, datetime
s = json.load(open('$TEST_DIR/.state.json'))
dl = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
s['active_boss'] = {'id': 'illidan', 'name': 'Illidan Stormrage', 'hp': 5000, 'max_hp': 6000, 'deadline': dl, 'loot_tier': 'epic', 'entry_fee': 0, 'gold_reward': 4000, 'lumber_reward': 1200, 'atk_min': 1, 'atk_max': 3}
json.dump(s, open('$TEST_DIR/.state.json', 'w'))
"
  # 2 shamans heal 1-3 HP each = 2-6 HP healed per turn
  # Boss atk 1-3 damage, units have 20-30 HP so no deaths in one turn
  run_peon '{"hook_event_name":"Stop","cwd":"/tmp/myproject","session_id":"s1","permission_mode":"default"}'
  local total
  total=$(python3 -c "import json; s=json.load(open('$TEST_DIR/.state.json')); a=s.get('army',{}); print(sum(len(v) if isinstance(v,list) else v for v in a.values()))")
  [ "$total" -eq 7 ]
}

# ============================================================
# army display shows units after hiring
# ============================================================

@test "army shows hired units" {
  bash "$PEON_SH" hire grunt 2
  bash "$PEON_SH" hire raider
  run bash "$PEON_SH" army
  [ "$status" -eq 0 ]
  [[ "$output" == *"2x Grunt"* ]]
  [[ "$output" == *"1x Raider"* ]]
  [[ "$output" == *"Units: 3"* ]]
}

@test "economy shows army upkeep" {
  bash "$PEON_SH" hire grunt 2
  run bash "$PEON_SH" economy
  [ "$status" -eq 0 ]
  [[ "$output" == *"Army"* ]]
  [[ "$output" == *"upkeep"* ]]
}
