# peon-ping tab completion for fish shell

# Helper: true when no subcommand has been given yet
function __peon_no_subcommand
  set -l cmd (commandline -opc)
  test (count $cmd) -eq 1
end

# Helper: true when the given subcommand is active
function __peon_using_subcommand
  set -l cmd (commandline -opc)
  test (count $cmd) -ge 2; and test $cmd[2] = $argv[1]
end

# Helper: true when packs subcommand is active and second arg matches
function __peon_packs_subcommand
  set -l cmd (commandline -opc)
  test (count $cmd) -ge 3; and test $cmd[2] = packs; and test $cmd[3] = $argv[1]
end

# Disable file completions
complete -c peon -f

# Top-level commands (only when no subcommand given)
complete -c peon -n __peon_no_subcommand -a pause -d "Mute sounds"
complete -c peon -n __peon_no_subcommand -a resume -d "Unmute sounds"
complete -c peon -n __peon_no_subcommand -a toggle -d "Toggle mute on/off"
complete -c peon -n __peon_no_subcommand -a status -d "Show current status"
complete -c peon -n __peon_no_subcommand -a volume -d "Get or set volume level"
complete -c peon -n __peon_no_subcommand -a rotation -d "Get or set pack rotation mode"
complete -c peon -n __peon_no_subcommand -a packs -d "Manage sound packs"
complete -c peon -n __peon_no_subcommand -a notifications -d "Control desktop notifications"
complete -c peon -n __peon_no_subcommand -a mobile -d "Configure mobile push notifications"
complete -c peon -n __peon_no_subcommand -a relay -d "Start audio relay for devcontainers"
complete -c peon -n __peon_no_subcommand -a economy -d "Show gold and lumber"
complete -c peon -n __peon_no_subcommand -a achievements -d "Show unlocked achievements"
complete -c peon -n __peon_no_subcommand -a build -d "Build WC3 structures"
complete -c peon -n __peon_no_subcommand -a bunker -d "Pause fatigue for 1 hour"
complete -c peon -n __peon_no_subcommand -a resurrect -d "Restore combo streak"
complete -c peon -n __peon_no_subcommand -a taunt -d "Play a random taunt"
complete -c peon -n __peon_no_subcommand -a inventory -d "View items and equipment"
complete -c peon -n __peon_no_subcommand -a equip -d "Equip an item"
complete -c peon -n __peon_no_subcommand -a unequip -d "Unequip an item"
complete -c peon -n __peon_no_subcommand -a use -d "Use a consumable item"
complete -c peon -n __peon_no_subcommand -a sell -d "Sell an item for gold"
complete -c peon -n __peon_no_subcommand -a raid -d "Start or check boss raids"
complete -c peon -n __peon_no_subcommand -a dashboard -d "Open WC3 base dashboard"
complete -c peon -n __peon_no_subcommand -a help -d "Show help message"

# packs subcommands
complete -c peon -n "__peon_using_subcommand packs" -a list -d "List installed sound packs"
complete -c peon -n "__peon_using_subcommand packs" -a use -d "Switch to a specific pack"
complete -c peon -n "__peon_using_subcommand packs" -a next -d "Cycle to the next pack"
complete -c peon -n "__peon_using_subcommand packs" -a install -d "Download and install new packs"
complete -c peon -n "__peon_using_subcommand packs" -a remove -d "Remove specific packs"

# packs install options
complete -c peon -n "__peon_packs_subcommand install" -a "--all" -d "Install all packs from registry"

# packs list options
complete -c peon -n "__peon_packs_subcommand list" -a "--registry" -d "List all available packs from registry"

# Pack name completions for 'packs use' and 'packs remove'
complete -c peon -n "__peon_packs_subcommand use" -a "(
  set -l packs_dir (set -q CLAUDE_PEON_DIR; and echo \$CLAUDE_PEON_DIR; or echo \$HOME/.claude/hooks/peon-ping)/packs
  if not test -d \$packs_dir; and test -d \$HOME/.openpeon/packs
    set packs_dir \$HOME/.openpeon/packs
  end
  if test -d \$packs_dir
    for manifest in \$packs_dir/*/manifest.json \$packs_dir/*/openpeon.json
      basename (dirname \$manifest)
    end
  end
)"
complete -c peon -n "__peon_packs_subcommand remove" -a "(
  set -l packs_dir (set -q CLAUDE_PEON_DIR; and echo \$CLAUDE_PEON_DIR; or echo \$HOME/.claude/hooks/peon-ping)/packs
  if not test -d \$packs_dir; and test -d \$HOME/.openpeon/packs
    set packs_dir \$HOME/.openpeon/packs
  end
  if test -d \$packs_dir
    for manifest in \$packs_dir/*/manifest.json \$packs_dir/*/openpeon.json
      basename (dirname \$manifest)
    end
  end
)"

# mobile subcommands
complete -c peon -n "__peon_using_subcommand mobile" -a ntfy -d "Set up ntfy.sh notifications"
complete -c peon -n "__peon_using_subcommand mobile" -a pushover -d "Set up Pushover notifications"
complete -c peon -n "__peon_using_subcommand mobile" -a telegram -d "Set up Telegram notifications"
complete -c peon -n "__peon_using_subcommand mobile" -a on -d "Enable mobile notifications"
complete -c peon -n "__peon_using_subcommand mobile" -a off -d "Disable mobile notifications"
complete -c peon -n "__peon_using_subcommand mobile" -a status -d "Show mobile config"
complete -c peon -n "__peon_using_subcommand mobile" -a test -d "Send test notification"

# build subcommands
complete -c peon -n "__peon_using_subcommand build" -a list -d "List available buildings"
complete -c peon -n "__peon_using_subcommand build" -a stronghold -d "Rank upgrade (500g/200l)"
complete -c peon -n "__peon_using_subcommand build" -a fortress -d "Max rank (2000g/800l)"
complete -c peon -n "__peon_using_subcommand build" -a burrow -d "Fatigue pause (100g/50l)"
complete -c peon -n "__peon_using_subcommand build" -a war_mill -d "Unlock combos (200g/100l)"
complete -c peon -n "__peon_using_subcommand build" -a watch_tower -d "Early context warning (150g/75l)"
complete -c peon -n "__peon_using_subcommand build" -a altar -d "Combo resurrect (300g/150l)"
complete -c peon -n "__peon_using_subcommand build" -a spirit_lodge -d "Idle thoughts (500g/200l)"
complete -c peon -n "__peon_using_subcommand build" -a tavern -d "On-demand taunt (400g/200l)"
complete -c peon -n "__peon_using_subcommand build" -a dark_portal -d "Boss raids (12000g/5000l)"
complete -c peon -n "__peon_using_subcommand build" -a blacksmith -d "Item effects +50% (4000g/1500l)"
complete -c peon -n "__peon_using_subcommand build" -a arcane_sanctum -d "Peon prophecies (7500g/3000l)"
complete -c peon -n "__peon_using_subcommand build" -a lumber_mill -d "2x lumber (1500g/500l)"
complete -c peon -n "__peon_using_subcommand build" -a barracks -d "Subagent stats (3000g/1200l)"
complete -c peon -n "__peon_using_subcommand build" -a citadel -d "2x item drops (15000g/6000l)"

# raid subcommands
complete -c peon -n "__peon_using_subcommand raid" -a status -d "Show active raid status"
complete -c peon -n "__peon_using_subcommand raid" -a kobold -d "Kobold Taskmaster (30 HP, 1 day)"
complete -c peon -n "__peon_using_subcommand raid" -a mud_golem -d "Mud Golem (100 HP, 1 day)"
complete -c peon -n "__peon_using_subcommand raid" -a troll -d "Forest Troll Warlord (200 HP, 2 days)"
complete -c peon -n "__peon_using_subcommand raid" -a ogre -d "Ogre Magi (600 HP, 3 days)"
complete -c peon -n "__peon_using_subcommand raid" -a naga -d "Naga Sea Witch (1200 HP, 3 days)"
complete -c peon -n "__peon_using_subcommand raid" -a infernal -d "Infernal (2000 HP, 4 days)"
complete -c peon -n "__peon_using_subcommand raid" -a brewmaster -d "Pandaren Brewmaster (3500 HP, 4 days)"
complete -c peon -n "__peon_using_subcommand raid" -a mannoroth -d "Pit Lord Mannoroth (5000 HP, 5 days)"
complete -c peon -n "__peon_using_subcommand raid" -a blademaster -d "Blademaster (8000 HP, 6 days)"
complete -c peon -n "__peon_using_subcommand raid" -a archimonde -d "Archimonde (12000 HP, 7 days)"

# rotation subcommands
complete -c peon -n "__peon_using_subcommand rotation" -a random -d "Pick a random pack each session (default)"
complete -c peon -n "__peon_using_subcommand rotation" -a round-robin -d "Cycle through packs in order"
complete -c peon -n "__peon_using_subcommand rotation" -a agentskill -d "Assign pack per session via /peon-ping-use"

# notifications subcommands
complete -c peon -n "__peon_using_subcommand notifications" -a on -d "Enable desktop notifications"
complete -c peon -n "__peon_using_subcommand notifications" -a off -d "Disable desktop notifications"
