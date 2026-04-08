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
complete -c peon -n __peon_no_subcommand -a bunker -d "Suppress roasts for 1 hour"
complete -c peon -n __peon_no_subcommand -a resurrect -d "Restore combo streak"
complete -c peon -n __peon_no_subcommand -a taunt -d "Play a random roast"
complete -c peon -n __peon_no_subcommand -a inventory -d "View items and equipment"
complete -c peon -n __peon_no_subcommand -a equip -d "Equip an item"
complete -c peon -n __peon_no_subcommand -a unequip -d "Unequip an item"
complete -c peon -n __peon_no_subcommand -a use -d "Use a consumable item"
complete -c peon -n __peon_no_subcommand -a sell -d "Sell an item for gold"
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
complete -c peon -n "__peon_using_subcommand build" -a burrow -d "Roast suppression (100g/50l)"
complete -c peon -n "__peon_using_subcommand build" -a war_mill -d "Unlock combos (200g/100l)"
complete -c peon -n "__peon_using_subcommand build" -a watch_tower -d "Early context warning (150g/75l)"
complete -c peon -n "__peon_using_subcommand build" -a altar -d "Combo resurrect (300g/150l)"
complete -c peon -n "__peon_using_subcommand build" -a spirit_lodge -d "Idle thoughts (500g/200l)"
complete -c peon -n "__peon_using_subcommand build" -a tavern -d "On-demand taunts (400g/200l)"

# rotation subcommands
complete -c peon -n "__peon_using_subcommand rotation" -a random -d "Pick a random pack each session (default)"
complete -c peon -n "__peon_using_subcommand rotation" -a round-robin -d "Cycle through packs in order"
complete -c peon -n "__peon_using_subcommand rotation" -a agentskill -d "Assign pack per session via /peon-ping-use"

# notifications subcommands
complete -c peon -n "__peon_using_subcommand notifications" -a on -d "Enable desktop notifications"
complete -c peon -n "__peon_using_subcommand notifications" -a off -d "Disable desktop notifications"
