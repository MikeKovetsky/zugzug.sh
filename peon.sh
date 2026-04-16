#!/bin/bash
# peon-ping: Warcraft III Peon voice lines for Claude Code hooks
# Replaces notify.sh — handles sounds, tab titles, and notifications
set -uo pipefail

# --- Platform detection ---
detect_platform() {
  case "$(uname -s)" in
    Darwin)
      if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ]; then
        echo "ssh"
      else
        echo "mac"
      fi ;;
    Linux)
      # Check for devcontainer/Docker BEFORE checking for WSL
      # (devcontainers on WSL2 have both indicators)
      if [ "${REMOTE_CONTAINERS:-}" = "true" ] || [ "${CODESPACES:-}" = "true" ] || [ -f /.dockerenv ]; then
        echo "devcontainer"
      elif grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      elif [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ]; then
        echo "ssh"
      else
        echo "linux"
      fi ;;
    *) echo "unknown" ;;
  esac
}
PLATFORM=${PLATFORM:-$(detect_platform)}

PEON_DIR="${CLAUDE_PEON_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# Homebrew/adapter installs: script lives in Cellar but packs/config are elsewhere
if [ ! -d "$PEON_DIR/packs" ]; then
  # Check CESP shared path (used by peon-ping-setup and standalone adapters)
  if [ -d "$HOME/.openpeon/packs" ]; then
    PEON_DIR="$HOME/.openpeon"
  else
    # Fall back to Claude Code hooks dir
    _hooks_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/peon-ping"
    [ -d "$_hooks_dir/packs" ] && PEON_DIR="$_hooks_dir"
    unset _hooks_dir
  fi
fi
# Local project config overrides global config
_local_config="${PWD}/.claude/hooks/peon-ping/config.json"
if [ -f "$_local_config" ]; then
  CONFIG="$_local_config"
else
  CONFIG="$PEON_DIR/config.json"
fi
unset _local_config
STATE="$PEON_DIR/.state.json"

# Atomic state I/O helpers (Python). Prevents corruption from concurrent hook events.
# - _load_state: tries main file, falls back to .bak
# - _save_state: backs up, writes to temp, then atomic os.replace
_PY_STATE_IO="
import tempfile as _tf, shutil as _sh
def _load_state(p):
    for _f in (p, p + '.bak'):
        try:
            _d = json.load(open(_f))
            if isinstance(_d, dict): return _d
        except Exception: pass
    return {}
def _save_state(p, d, indent=None):
    _dn = os.path.dirname(p) or '.'
    os.makedirs(_dn, exist_ok=True)
    if os.path.isfile(p):
        try: _sh.copy2(p, p + '.bak')
        except Exception: pass
    _fd, _t = _tf.mkstemp(dir=_dn, suffix='.tmp')
    try:
        with os.fdopen(_fd, 'w') as _fh:
            json.dump(d, _fh, indent=indent)
            _fh.flush()
            os.fsync(_fh.fileno())
        os.replace(_t, p)
    except Exception:
        try: os.unlink(_t)
        except Exception: pass
        raise
"

# --- Resolve a bundled script from scripts/ (handles local + Homebrew/Cellar installs) ---
# Prints the resolved path on success, prints nothing on failure.
# Skips the BASH_SOURCE fallback in test mode to preserve "missing script" test cases.
find_bundled_script() {
  local name="$1" path
  # Standard local install: $PEON_DIR is the install root
  path="$PEON_DIR/scripts/$name"
  [ -f "$path" ] && { printf '%s\n' "$path"; return 0; }
  # Homebrew/adapter install: peon.sh lives in the Cellar, scripts/ is a sibling
  if [ "${PEON_TEST:-0}" != "1" ]; then
    path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/$name"
    [ -f "$path" ] && { printf '%s\n' "$path"; return 0; }
  fi
  return 1
}

resolve_pack_download() {
  local pack_dl
  pack_dl="$(find_bundled_script "pack-download.sh")" && { printf '%s\n' "$pack_dl"; return 0; }
  echo "Error: pack-download.sh not found. Run 'peon update' or reinstall peon-ping to fix." >&2
  return 1
}

# --- Linux audio backend detection ---
detect_linux_player() {
  local override="${1:-}"
  # Helper to check if a player is available (respects test-mode disable markers)
  player_available() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null || return 1
    # In test mode, check for disable marker
    [ "${PEON_TEST:-0}" = "1" ] && [ -f "${CLAUDE_PEON_DIR}/.disabled_${cmd}" ] && return 1
    return 0
  }

  # If user configured a preferred player, try it first
  if [ -n "$override" ] && player_available "$override"; then
    echo "$override"
    return 0
  fi

  if player_available pw-play; then
    echo "pw-play"
  elif player_available paplay; then
    echo "paplay"
  elif player_available ffplay; then
    echo "ffplay"
  elif player_available mpv; then
    echo "mpv"
  elif player_available play; then
    echo "play"
  elif player_available aplay; then
    echo "aplay"
  else
    # Warn only once per process to avoid spam
    if [ -z "${WARNED_NO_LINUX_AUDIO_BACKEND:-}" ]; then
      echo "WARNING: No audio backend found. Please install one of: pw-play, paplay, ffplay, mpv, play (SoX), or aplay" >&2
      WARNED_NO_LINUX_AUDIO_BACKEND=1
    fi
    return 1
  fi
}

# --- Linux audio playback with backend-specific volume handling ---
play_linux_sound() {
  local file="$1" vol="$2" player="$3"

  # Skip playback if no backend available
  [ -z "$player" ] && return 0

  # Background mode: use nohup & for async playback (default)
  # Synchronous mode: no nohup/& for tests (when PEON_TEST=1)
  local use_bg=true
  [ "${PEON_TEST:-0}" = "1" ] && use_bg=false

  case "$player" in
    pw-play)
      # pw-play (PipeWire) expects volume as float 0.0-1.0 (unlike paplay 0-65536, ffplay/mpv 0-100)
      if [ "$use_bg" = true ]; then
        nohup env LC_ALL=C pw-play --volume "$vol" "$file" >/dev/null 2>&1 &
      else
        LC_ALL=C pw-play --volume "$vol" "$file" >/dev/null 2>&1
      fi
      ;;
    paplay)
      local pa_vol
      pa_vol=$(python3 -c "print(max(0, min(65536, int($vol * 65536))))")
      if [ "$use_bg" = true ]; then
        nohup paplay --volume="$pa_vol" "$file" >/dev/null 2>&1 &
      else
        paplay --volume="$pa_vol" "$file" >/dev/null 2>&1
      fi
      ;;
    ffplay)
      local ff_vol
      ff_vol=$(python3 -c "print(max(0, min(100, int($vol * 100))))")
      if [ "$use_bg" = true ]; then
        nohup ffplay -nodisp -autoexit -volume "$ff_vol" "$file" >/dev/null 2>&1 &
      else
        ffplay -nodisp -autoexit -volume "$ff_vol" "$file" >/dev/null 2>&1
      fi
      ;;
    mpv)
      local mpv_vol
      mpv_vol=$(python3 -c "print(max(0, min(100, int($vol * 100))))")
      if [ "$use_bg" = true ]; then
        nohup mpv --no-video --volume="$mpv_vol" "$file" >/dev/null 2>&1 &
      else
        mpv --no-video --volume="$mpv_vol" "$file" >/dev/null 2>&1
      fi
      ;;
    play)
      if [ "$use_bg" = true ]; then
        nohup play -v "$vol" "$file" >/dev/null 2>&1 &
      else
        play -v "$vol" "$file" >/dev/null 2>&1
      fi
      ;;
    aplay)
      if [ "$use_bg" = true ]; then
        nohup aplay -q "$file" >/dev/null 2>&1 &
      else
        aplay -q "$file" >/dev/null 2>&1
      fi
      ;;
  esac
}

# --- Kill any previously playing peon-ping sound ---
kill_previous_sound() {
  local pidfile="$PEON_DIR/.sound.pid"
  if [ -f "$pidfile" ]; then
    local old_pid
    old_pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null
    fi
    rm -f "$pidfile"
  fi
}

save_sound_pid() {
  echo "$1" > "$PEON_DIR/.sound.pid"
}

# --- Platform-aware audio playback ---
play_sound() {
  local file="$1" vol="$2"
  kill_previous_sound
  case "$PLATFORM" in
    mac)
      local player="afplay"
      if [ "${USE_SOUND_EFFECTS_DEVICE:-true}" != "false" ]; then
        local _peon_play
        _peon_play="$(find_bundled_script "peon-play")" && [ -x "$_peon_play" ] && player="$_peon_play"
      fi
      if [ "${PEON_TEST:-0}" = "1" ]; then
        "$player" -v "$vol" "$file" >/dev/null 2>&1
      else
        nohup "$player" -v "$vol" "$file" >/dev/null 2>&1 &
        save_sound_pid $!
      fi
      ;;
    wsl)
      local tmpdir tmpfile
      tmpdir=$(powershell.exe -NoProfile -NonInteractive -Command '[System.IO.Path]::GetTempPath()' 2>/dev/null | tr -d '\r')
      tmpfile="$(wslpath -u "${tmpdir}peon-ping-sound.wav")"
      if command -v ffmpeg &>/dev/null; then
        ffmpeg -y -i "$file" -filter:a "volume=$vol" "$tmpfile" 2>/dev/null
      elif [[ "$file" == *.wav ]]; then
        cp "$file" "$tmpfile"
      else
        return 0
      fi
      setsid powershell.exe -NoProfile -NonInteractive -Command "
        (New-Object Media.SoundPlayer '${tmpdir}peon-ping-sound.wav').PlaySync()
      " &>/dev/null &
      save_sound_pid $!
      ;;
    devcontainer|ssh)
      local relay_host_default="host.docker.internal"
      [ "$PLATFORM" = "ssh" ] && relay_host_default="localhost"
      local relay_host="${PEON_RELAY_HOST:-$relay_host_default}"
      local relay_port="${PEON_RELAY_PORT:-19998}"
      local rel_path="${file#$PEON_DIR/}"
      local encoded_path
      encoded_path=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$rel_path" 2>/dev/null || echo "$rel_path")
      if [ "${PEON_TEST:-0}" = "1" ]; then
        curl -sf -H "X-Volume: $vol" \
          "http://${relay_host}:${relay_port}/play?file=${encoded_path}" 2>/dev/null
      else
        nohup curl -sf -H "X-Volume: $vol" \
          "http://${relay_host}:${relay_port}/play?file=${encoded_path}" >/dev/null 2>&1 &
        save_sound_pid $!
      fi
      ;;
    linux)
      local player
      player=$(detect_linux_player "${LINUX_AUDIO_PLAYER:-}") || player=""
      if [ -n "$player" ]; then
        play_linux_sound "$file" "$vol" "$player"
        save_sound_pid $!
      fi
      ;;
  esac
}

# --- Platform-aware notification ---
# Args: msg, title, color (red/blue/yellow)
send_notification() {
  local msg="$1" title="$2" color="${3:-red}"
  local icon_path="${4:-$PEON_DIR/docs/peon-icon.png}"

  # Synchronous mode for tests (avoid race with backgrounded processes)
  local use_bg=true
  [ "${PEON_TEST:-0}" = "1" ] && use_bg=false

  case "$PLATFORM" in
    mac)
      local overlay_script=""
      [ "${NOTIF_STYLE:-overlay}" = "overlay" ] && \
        overlay_script="$(find_bundled_script "mac-overlay.js")" 2>/dev/null || true
      if [ -n "$overlay_script" ]; then
        # JXA Cocoa overlay — large, visible banner on all screens
        local icon_arg=""
        [ -f "$icon_path" ] && icon_arg="$icon_path"
        _run_overlay() (
          slot_dir="/tmp/peon-ping-popups"; mkdir -p "$slot_dir"
          slot=0
          while [ "$slot" -lt 5 ] && ! mkdir "$slot_dir/slot-$slot" 2>/dev/null; do
            slot=$((slot + 1))
          done
          if [ "$slot" -ge 5 ]; then
            find "$slot_dir" -maxdepth 1 -name 'slot-*' -mmin +1 -exec rm -rf {} + 2>/dev/null
            slot=0; mkdir -p "$slot_dir/slot-0"
          fi
          osascript -l JavaScript "$overlay_script" "$msg" "$color" "$icon_arg" "$slot" "4" "" "${PEON_DASHBOARD_PORT:-19997}" >/dev/null 2>&1 || true
          rm -rf "$slot_dir/slot-$slot"
        )
        if [ "$use_bg" = true ]; then _run_overlay & else _run_overlay; fi
      else
        # Standard notifications: terminal-native escape sequences or system notifications
        case "${TERM_PROGRAM:-}" in
          iTerm.app)
            # iTerm2 OSC 9 — notification with iTerm2 icon
            printf '\e]9;%s\007' "$title: $msg" > /dev/tty 2>/dev/null || true
            ;;
          kitty)
            # Kitty OSC 99
            printf '\e]99;i=peon:d=0;%s\e\\' "$title: $msg" > /dev/tty 2>/dev/null || true
            ;;
          *)
            if command -v terminal-notifier &>/dev/null && [ -f "$icon_path" ]; then
              # terminal-notifier supports custom icon (brew install terminal-notifier)
              local _dash_url="http://localhost:${PEON_DASHBOARD_PORT:-19997}"
              if [ "$use_bg" = true ]; then
                nohup terminal-notifier \
                  -title "$title" \
                  -message "$msg" \
                  -appIcon "$icon_path" \
                  -open "$_dash_url" \
                  -group "peon-ping" >/dev/null 2>&1 &
              else
                terminal-notifier \
                  -title "$title" \
                  -message "$msg" \
                  -appIcon "$icon_path" \
                  -open "$_dash_url" \
                  -group "peon-ping" >/dev/null 2>&1
              fi
            else
              # Terminal.app, Warp, Ghostty, etc. — no native escape; use osascript
              if [ "$use_bg" = true ]; then
                nohup osascript - "$msg" "$title" >/dev/null 2>&1 <<'APPLESCRIPT' &
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
              else
                osascript - "$msg" "$title" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
              fi
            fi
            ;;
        esac
      fi
      ;;
    wsl)
      if [ "${NOTIF_STYLE:-overlay}" = "standard" ]; then
        # Windows toast notification (no focus stealing, appears in Action Center)
        local tmpdir
        tmpdir=$(powershell.exe -NoProfile -NonInteractive -Command '[System.IO.Path]::GetTempPath()' 2>/dev/null | tr -d '\r')
        local tmpdir_wsl
        tmpdir_wsl="$(wslpath -u "$tmpdir")"
        # Copy icon to Windows temp if available
        local icon_xml=""
        if [ -f "$icon_path" ]; then
          cp "$icon_path" "${tmpdir_wsl}peon-ping-icon.png" 2>/dev/null
          icon_xml="<image placement=\"appLogoOverride\" hint-crop=\"circle\" src=\"${tmpdir}peon-ping-icon.png\" />"
        fi
        # Extract just the action part from msg (remove repeated project name)
        local toast_body="$msg"
        if [[ "$msg" == *" — "* ]]; then
          toast_body="${msg##* — }"
        fi
        # Strip leading marker (● ) from title for cleaner toast
        local toast_title="${title#● }"
        # Escape XML special characters to prevent malformed toast XML
        # Covers all 5 XML predefined entities and strips control chars illegal in XML 1.0
        _escape_xml() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | sed "s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/\"/\&quot;/g; s/'/\&apos;/g"; }
        toast_title="$(_escape_xml "$toast_title")"
        toast_body="$(_escape_xml "$toast_body")"
        # Write toast XML to temp file (avoids bash/powershell escaping issues)
        cat > "${tmpdir_wsl}peon-toast.xml" <<TOASTEOF
<toast duration="short"><visual><binding template="ToastGeneric"><text>${toast_body}</text><text>${toast_title}</text>${icon_xml}</binding></visual><audio silent="true" /></toast>
TOASTEOF
        _run_toast() {
          setsid powershell.exe -NoProfile -NonInteractive -Command '
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
            [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
            $APP_ID = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
            $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
            $xml.LoadXml((Get-Content ($env:TEMP + "\peon-toast.xml") -Raw -Encoding UTF8))
            $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($APP_ID).Show($toast)
            Remove-Item ($env:TEMP + "\peon-toast.xml") -ErrorAction SilentlyContinue
          ' &>/dev/null
        }
        if [ "$use_bg" = true ]; then _run_toast & else _run_toast; fi
      else
        # Legacy Windows Forms popup
        local rgb_r=180 rgb_g=0 rgb_b=0
        case "$color" in
          blue)   rgb_r=30  rgb_g=80  rgb_b=180 ;;
          yellow) rgb_r=200 rgb_g=160 rgb_b=0   ;;
          red)    rgb_r=180 rgb_g=0   rgb_b=0   ;;
        esac
        local icon_win_path=""
        if [ -f "$icon_path" ]; then
          icon_win_path=$(wslpath -w "$icon_path" 2>/dev/null || true)
        fi
        _run_forms_popup() {
          slot_dir="/tmp/peon-ping-popups"
          mkdir -p "$slot_dir"
          slot=0
          while [ "$slot" -lt 5 ] && ! mkdir "$slot_dir/slot-$slot" 2>/dev/null; do
            slot=$((slot + 1))
          done
          if [ "$slot" -ge 5 ]; then
            find "$slot_dir" -maxdepth 1 -name 'slot-*' -mmin +1 -exec rm -rf {} + 2>/dev/null
            slot=0; mkdir -p "$slot_dir/slot-0"
          fi
          y_offset=$((40 + slot * 90))
          # Security: pass message via temp file to avoid PowerShell injection from untrusted $msg
          tmpmsg=$(mktemp) && printf '%s' "$msg" > "$tmpmsg"
          powershell.exe -NoProfile -NonInteractive -Command "
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            \$msgPath = '$tmpmsg'
            \$msgText = if (Test-Path \$msgPath) { (Get-Content -Raw \$msgPath) } else { '' }
            foreach (\$screen in [System.Windows.Forms.Screen]::AllScreens) {
              \$form = New-Object System.Windows.Forms.Form
              \$form.FormBorderStyle = 'None'
              \$form.BackColor = [System.Drawing.Color]::FromArgb($rgb_r, $rgb_g, $rgb_b)
              \$form.Size = New-Object System.Drawing.Size(500, 80)
              \$form.TopMost = \$true
              \$form.ShowInTaskbar = \$false
              \$form.StartPosition = 'Manual'
              \$form.Location = New-Object System.Drawing.Point(
                (\$screen.WorkingArea.X + (\$screen.WorkingArea.Width - 500) / 2),
                (\$screen.WorkingArea.Y + $y_offset)
              )
              \$iconLeft = 10
              \$iconSize = 60
              if ('$icon_win_path' -ne '' -and (Test-Path '$icon_win_path')) {
                \$pb = New-Object System.Windows.Forms.PictureBox
                \$pb.Image = [System.Drawing.Image]::FromFile('$icon_win_path')
                \$pb.SizeMode = 'Zoom'
                \$pb.Size = New-Object System.Drawing.Size(\$iconSize, \$iconSize)
                \$pb.Location = New-Object System.Drawing.Point(\$iconLeft, 10)
                \$pb.BackColor = [System.Drawing.Color]::Transparent
                \$form.Controls.Add(\$pb)
                \$label = New-Object System.Windows.Forms.Label
                \$label.Location = New-Object System.Drawing.Point((\$iconLeft + \$iconSize + 5), 0)
                \$label.Size = New-Object System.Drawing.Size((500 - \$iconLeft - \$iconSize - 15), 80)
              } else {
                \$label = New-Object System.Windows.Forms.Label
                \$label.Dock = 'Fill'
              }
              \$label.Text = \$msgText
              \$label.ForeColor = [System.Drawing.Color]::White
              \$label.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
              \$label.TextAlign = 'MiddleCenter'
              \$form.Controls.Add(\$label)
              \$form.Show()
            }
            Start-Sleep -Seconds 4
            [System.Windows.Forms.Application]::Exit()
            if (Test-Path \$msgPath) { Remove-Item -Force \$msgPath }
          " &>/dev/null
          rm -rf "$slot_dir/slot-$slot"
        }
        if [ "$use_bg" = true ]; then _run_forms_popup & else _run_forms_popup; fi
      fi
      ;;
    devcontainer|ssh)
      local relay_host_default="host.docker.internal"
      [ "$PLATFORM" = "ssh" ] && relay_host_default="localhost"
      local relay_host="${PEON_RELAY_HOST:-$relay_host_default}"
      local relay_port="${PEON_RELAY_PORT:-19998}"
      local json_title json_msg
      json_title=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$title" 2>/dev/null || echo "\"$title\"")
      json_msg=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$msg" 2>/dev/null || echo "\"$msg\"")
      if [ "$use_bg" = true ]; then
        nohup curl -sf -X POST \
          -H "Content-Type: application/json" \
          -d "{\"title\":${json_title},\"message\":${json_msg},\"color\":\"$color\"}" \
          "http://${relay_host}:${relay_port}/notify" >/dev/null 2>&1 &
      else
        curl -sf -X POST \
          -H "Content-Type: application/json" \
          -d "{\"title\":${json_title},\"message\":${json_msg},\"color\":\"$color\"}" \
          "http://${relay_host}:${relay_port}/notify" >/dev/null 2>&1
      fi
      ;;
    linux)
      if command -v notify-send &>/dev/null; then
        local urgency="normal"
        case "$color" in
          red) urgency="critical" ;;
        esac
        local icon_flag=""
        if [ -f "$icon_path" ]; then
          icon_flag="--icon=$icon_path"
        fi
        if [ "$use_bg" = true ]; then
          nohup notify-send --urgency="$urgency" --expire-time=5000 $icon_flag "$title" "$msg" >/dev/null 2>&1 &
        else
          notify-send --urgency="$urgency" --expire-time=5000 $icon_flag "$title" "$msg" >/dev/null 2>&1
        fi
      fi
      ;;
  esac
}

# --- Platform-aware terminal focus check ---
terminal_is_focused() {
  case "$PLATFORM" in
    mac)
      local frontmost
      frontmost=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
      case "$frontmost" in
        Terminal|iTerm2|Warp|Alacritty|kitty|WezTerm|Ghostty) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    wsl)
      # Checking Windows focus from WSL adds too much latency; always notify
      return 1
      ;;
    devcontainer|ssh)
      # Cannot detect host window focus from a container/remote; always notify
      return 1
      ;;
    linux)
      # Only use xdotool on X11; fallback to always notify on Wayland or if xdotool is missing
      if [ "${XDG_SESSION_TYPE:-}" = "x11" ] && command -v xdotool &>/dev/null; then
        local win_name
        win_name=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "")
        if [[ "$win_name" =~ (terminal|konsole|alacritty|kitty|wezterm|foot|tilix|gnome-terminal|xterm|xfce4-terminal|sakura|terminator|st|urxvt|ghostty) ]]; then
          return 0
        fi
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# --- Mobile push notification ---
# Sends push notifications to phone via ntfy.sh, Pushover, or Telegram.
# Config: config.json → mobile_notify: { service, topic/user_key/chat_id, ... }
send_mobile_notification() {
  local msg="$1" title="$2" color="${3:-red}"
  local config="$CONFIG"

  # Read mobile config via Python (fast, single invocation)
  local mobile_vars
  mobile_vars=$(python3 -c "
import json, sys, shlex
q = shlex.quote
try:
    cfg = json.load(open('$config'))
    mn = cfg.get('mobile_notify', {})
except Exception:
    mn = {}
if not mn or not mn.get('enabled', True):
    print('MOBILE_SERVICE=')
    sys.exit(0)
service = mn.get('service', '')
print('MOBILE_SERVICE=' + q(service))
print('MOBILE_TOPIC=' + q(mn.get('topic', '')))
print('MOBILE_SERVER=' + q(mn.get('server', 'https://ntfy.sh')))
print('MOBILE_TOKEN=' + q(mn.get('token', '')))
print('MOBILE_USER_KEY=' + q(mn.get('user_key', '')))
print('MOBILE_APP_TOKEN=' + q(mn.get('app_token', '')))
print('MOBILE_CHAT_ID=' + q(mn.get('chat_id', '')))
print('MOBILE_BOT_TOKEN=' + q(mn.get('bot_token', '')))
" 2>/dev/null) || return 0

  eval "$mobile_vars"

  [ -z "$MOBILE_SERVICE" ] && return 0

  # Map color to priority
  local priority="default"
  case "$color" in
    red) priority="high" ;;
    yellow) priority="default" ;;
    blue) priority="low" ;;
  esac

  # Synchronous mode for tests (avoid race with backgrounded curl)
  local use_bg=true
  [ "${PEON_TEST:-0}" = "1" ] && use_bg=false

  case "$MOBILE_SERVICE" in
    ntfy)
      [ -z "$MOBILE_TOPIC" ] && return 0
      local ntfy_url="${MOBILE_SERVER}/${MOBILE_TOPIC}"
      local auth_header=""
      [ -n "$MOBILE_TOKEN" ] && auth_header="-H \"Authorization: Bearer ${MOBILE_TOKEN}\""
      if [ "$use_bg" = true ]; then
        nohup curl -sf \
          -H "Title: $title" \
          -H "Priority: $priority" \
          -H "Tags: video_game" \
          $auth_header \
          -d "$msg" \
          "$ntfy_url" >/dev/null 2>&1 &
      else
        curl -sf \
          -H "Title: $title" \
          -H "Priority: $priority" \
          -H "Tags: video_game" \
          $auth_header \
          -d "$msg" \
          "$ntfy_url" >/dev/null 2>&1
      fi
      ;;
    pushover)
      [ -z "$MOBILE_USER_KEY" ] || [ -z "$MOBILE_APP_TOKEN" ] && return 0
      local po_priority=0
      case "$priority" in
        high) po_priority=1 ;;
        low) po_priority=-1 ;;
      esac
      if [ "$use_bg" = true ]; then
        nohup curl -sf \
          -d "token=${MOBILE_APP_TOKEN}" \
          -d "user=${MOBILE_USER_KEY}" \
          -d "title=${title}" \
          -d "message=${msg}" \
          -d "priority=${po_priority}" \
          "https://api.pushover.net/1/messages.json" >/dev/null 2>&1 &
      else
        curl -sf \
          -d "token=${MOBILE_APP_TOKEN}" \
          -d "user=${MOBILE_USER_KEY}" \
          -d "title=${title}" \
          -d "message=${msg}" \
          -d "priority=${po_priority}" \
          "https://api.pushover.net/1/messages.json" >/dev/null 2>&1
      fi
      ;;
    telegram)
      [ -z "$MOBILE_BOT_TOKEN" ] || [ -z "$MOBILE_CHAT_ID" ] && return 0
      local tg_text="${title}%0A${msg}"
      if [ "$use_bg" = true ]; then
        nohup curl -sf "https://api.telegram.org/bot$MOBILE_BOT_TOKEN/sendMessage" \
          -d "chat_id=$MOBILE_CHAT_ID" \
          -d "text=${tg_text}" >/dev/null 2>&1 &
      else
        curl -sf "https://api.telegram.org/bot$MOBILE_BOT_TOKEN/sendMessage" \
          -d "chat_id=$MOBILE_CHAT_ID" \
          -d "text=${tg_text}" >/dev/null 2>&1
      fi
      ;;
  esac
}

# --- CLI subcommands (must come before INPUT=$(cat) which blocks on stdin) ---
PAUSED_FILE="$PEON_DIR/.paused"

# --- Sync shared config to OpenCode adapter config ---
# The OpenCode adapter is a standalone TypeScript plugin with its own config.json.
# After any CLI command that writes config or paused state, we sync shared keys
# so changes take effect in OpenCode without manual editing.
_ADAPTER_CONFIG_DIRS=()
_xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
[ -d "$_xdg/opencode/peon-ping" ] && _ADAPTER_CONFIG_DIRS+=("$_xdg/opencode/peon-ping")
unset _xdg

sync_adapter_configs() {
  [ ${#_ADAPTER_CONFIG_DIRS[@]} -eq 0 ] && return 0
  for _dir in "${_ADAPTER_CONFIG_DIRS[@]}"; do
    _target="$_dir/config.json"
    python3 -c "
import json, sys, os

src_path = '$CONFIG'
dst_path = '$_target'

# Keys shared between peon.sh and standalone adapters
SHARED_KEYS = ('active_pack', 'volume', 'enabled', 'desktop_notifications', 'pack_rotation', 'mobile_notify')

try:
    src = json.load(open(src_path))
except Exception:
    sys.exit(0)

try:
    dst = json.load(open(dst_path))
except Exception:
    dst = {}

changed = False
for key in SHARED_KEYS:
    if key in src and src[key] != dst.get(key):
        dst[key] = src[key]
        changed = True

if changed:
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    json.dump(dst, open(dst_path, 'w'), indent=2)
" 2>/dev/null || true
  done
}

sync_adapter_paused() {
  [ ${#_ADAPTER_CONFIG_DIRS[@]} -eq 0 ] && return 0
  for _dir in "${_ADAPTER_CONFIG_DIRS[@]}"; do
    if [ -f "$PAUSED_FILE" ]; then
      touch "$_dir/.paused"
    else
      rm -f "$_dir/.paused"
    fi
  done
}

case "${1:-}" in
  pause)   touch "$PAUSED_FILE"; sync_adapter_paused; echo "peon-ping: sounds paused (run 'peon toggle' to unpause)"; exit 0 ;;
  resume)  rm -f "$PAUSED_FILE"; sync_adapter_paused; echo "peon-ping: sounds resumed"; exit 0 ;;
  toggle)
    if [ -f "$PAUSED_FILE" ]; then rm -f "$PAUSED_FILE"; echo "peon-ping: sounds resumed"
    else touch "$PAUSED_FILE"; echo "peon-ping: sounds paused (run 'peon toggle' to unpause)"; fi
    sync_adapter_paused; exit 0 ;;
  status)
    [ -f "$PAUSED_FILE" ] && echo "peon-ping: paused" || echo "peon-ping: active"
    python3 -c "
import json, os

config_path = '$CONFIG'
peon_dir = '$PEON_DIR'

# --- Config ---
try:
    c = json.load(open(config_path))
except Exception:
    c = {}

dn = c.get('desktop_notifications', True)
print('peon-ping: desktop notifications ' + ('on' if dn else 'off'))
ns = c.get('notification_style', 'overlay')
print('peon-ping: notification style ' + ns)

mn = c.get('mobile_notify', {})
if mn and mn.get('service'):
    enabled = mn.get('enabled', True)
    svc = mn.get('service', '?')
    print(f'peon-ping: mobile notifications ' + ('on' if enabled else 'off') + f' ({svc})')
else:
    print('peon-ping: mobile notifications not configured')

# --- Active pack ---
active = c.get('active_pack', 'peon')
packs_dir = os.path.join(peon_dir, 'packs')
display_name = active
pack_count = 0
if os.path.isdir(packs_dir):
    for d in os.listdir(packs_dir):
        dpath = os.path.join(packs_dir, d)
        if not os.path.isdir(dpath):
            continue
        has_manifest = (
            os.path.exists(os.path.join(dpath, 'openpeon.json')) or
            os.path.exists(os.path.join(dpath, 'manifest.json'))
        )
        if has_manifest:
            pack_count += 1
            if d == active:
                for mname in ('openpeon.json', 'manifest.json'):
                    mpath = os.path.join(dpath, mname)
                    if os.path.exists(mpath):
                        try:
                            display_name = json.load(open(mpath)).get('display_name', active)
                        except Exception:
                            pass
                        break
print(f'peon-ping: active pack: {active} ({display_name})')
print(f'peon-ping: {pack_count} pack(s) installed')

# --- IDE detection ---
home = os.path.expanduser('~')
claude_dir = os.environ.get('CLAUDE_CONFIG_DIR', os.path.join(home, '.claude'))
xdg_config = os.environ.get('XDG_CONFIG_HOME', os.path.join(home, '.config'))
opencode_dir = os.path.join(xdg_config, 'opencode')

ides = []

# Claude Code: check if hooks are registered
claude_hooks_dir = os.path.join(claude_dir, 'hooks', 'peon-ping')
if os.path.isdir(claude_dir):
    if os.path.exists(os.path.join(claude_hooks_dir, 'peon.sh')):
        ides.append(('Claude Code', claude_dir, 'installed'))
    else:
        ides.append(('Claude Code', claude_dir, 'detected (not set up)'))

# OpenCode: check if plugin is installed
opencode_plugin = os.path.join(opencode_dir, 'plugins', 'peon-ping.ts')
if os.path.isdir(opencode_dir):
    if os.path.exists(opencode_plugin):
        ides.append(('OpenCode', opencode_dir, 'installed'))
    else:
        ides.append(('OpenCode', opencode_dir, 'detected (not set up)'))

if ides:
    print('peon-ping: IDEs')
    for name, path, status in ides:
        marker = '[x]' if status == 'installed' else '[ ]'
        print(f'  {marker} {name:12s} {path} ({status})')
else:
    print('peon-ping: no supported IDEs detected')
"
    exit 0 ;;
  notifications)
    case "${2:-}" in
      on)
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['desktop_notifications'] = True
json.dump(cfg, open(config_path, 'w'), indent=2)
print('peon-ping: desktop notifications on')
"
        sync_adapter_configs; exit 0 ;;
      off)
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['desktop_notifications'] = False
json.dump(cfg, open(config_path, 'w'), indent=2)
print('peon-ping: desktop notifications off')
"
        sync_adapter_configs; exit 0 ;;
      overlay)
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['notification_style'] = 'overlay'
json.dump(cfg, open(config_path, 'w'), indent=2)
print('peon-ping: notification style set to overlay')
"
        sync_adapter_configs; exit 0 ;;
      standard)
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['notification_style'] = 'standard'
json.dump(cfg, open(config_path, 'w'), indent=2)
print('peon-ping: notification style set to standard')
"
        sync_adapter_configs; exit 0 ;;
      test)
        # Read config to check if notifications are enabled and get style
        eval "$(python3 -c "
import json, shlex
q = shlex.quote
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
dn = cfg.get('desktop_notifications', True)
ns = cfg.get('notification_style', 'overlay')
print('_NOTIF_ENABLED=' + ('true' if dn else 'false'))
print('NOTIF_STYLE=' + q(ns))
")"
        if [ "$_NOTIF_ENABLED" != "true" ]; then
          echo "peon-ping: desktop notifications are off (run 'peon notifications on' to enable)" >&2
          exit 1
        fi
        echo "peon-ping: sending test notification (style: $NOTIF_STYLE)"
        PEON_TEST=1 send_notification "This is a test notification" "peon-ping" "blue"
        exit 0 ;;
      *)
        echo "Usage: peon notifications <on|off|overlay|standard|test>" >&2; exit 1 ;;
    esac ;;
  volume)
    VOL_ARG="${2:-}"
    if [ -z "$VOL_ARG" ]; then
      python3 -c "
import json
try:
    cfg = json.load(open('$CONFIG'))
    print('peon-ping: volume ' + str(cfg.get('volume', 0.5)))
except Exception:
    print('peon-ping: volume 0.5')
"
      exit 0
    fi
    python3 -c "
import json, sys
config_path = '$CONFIG'
try:
    vol = float('$VOL_ARG')
except ValueError:
    print('peon-ping: invalid volume \"$VOL_ARG\" — use a number between 0.0 and 1.0', file=sys.stderr)
    sys.exit(1)
if not (0.0 <= vol <= 1.0):
    print('peon-ping: volume must be between 0.0 and 1.0', file=sys.stderr)
    sys.exit(1)
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['volume'] = round(vol, 2)
json.dump(cfg, open(config_path, 'w'), indent=2)
print(f'peon-ping: volume set to {vol}')
"
    _rc=$?; [ $_rc -eq 0 ] && sync_adapter_configs; exit $_rc ;;
  rotation)
    ROT_ARG="${2:-}"
    if [ -z "$ROT_ARG" ]; then
      python3 -c "
import json
try:
    cfg = json.load(open('$CONFIG'))
    mode = cfg.get('pack_rotation_mode', 'random')
    rotation = cfg.get('pack_rotation', [])
    print('peon-ping: rotation mode: ' + mode)
    if rotation:
        print('peon-ping: rotation packs: ' + ', '.join(rotation))
    else:
        print('peon-ping: rotation packs: (none — using active_pack)')
except Exception:
    print('peon-ping: rotation mode: random')
"
      exit 0
    fi
    case "$ROT_ARG" in
      random|round-robin|agentskill)
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['pack_rotation_mode'] = '$ROT_ARG'
json.dump(cfg, open(config_path, 'w'), indent=2)
print('peon-ping: rotation mode set to $ROT_ARG')
"
        _rc=$?; [ $_rc -eq 0 ] && sync_adapter_configs; exit $_rc ;;
      *)
        echo "Usage: peon rotation <random|round-robin|agentskill>" >&2
        echo "" >&2
        echo "Modes:" >&2
        echo "  random        Pick a random pack each session (default)" >&2
        echo "  round-robin   Cycle through packs in order each session" >&2
        echo "  agentskill    Use /peon-ping-use to assign pack per session" >&2
        exit 1 ;;
    esac ;;
  packs)
    case "${2:-}" in
      list)
        if [ "${3:-}" = "--registry" ]; then
          PACK_DL="$(resolve_pack_download)" || exit 1
          bash "$PACK_DL" --list-registry --dir="$PEON_DIR"
          exit 0
        fi
        python3 -c "
import json, os, glob
config_path = '$CONFIG'
try:
    active = json.load(open(config_path)).get('active_pack', 'peon')
except Exception:
    active = 'peon'
packs_dir = '$PEON_DIR/packs'
for d in sorted(os.listdir(packs_dir)):
    for mname in ('openpeon.json', 'manifest.json'):
        mpath = os.path.join(packs_dir, d, mname)
        if os.path.exists(mpath):
            info = json.load(open(mpath))
            name = info.get('name', d)
            display = info.get('display_name', name)
            marker = ' *' if name == active else ''
            print(f'  {name:24s} {display}{marker}')
            break
"
        exit 0 ;;
      use)
        # Parse --install flag and pack name from args 3/4
        USE_INSTALL=0
        PACK_ARG=""
        for arg in "${3:-}" "${4:-}"; do
          case "$arg" in
            --install) USE_INSTALL=1 ;;
            "") ;;
            *) PACK_ARG="$arg" ;;
          esac
        done
        if [ -z "$PACK_ARG" ]; then
          echo "Usage: peon packs use <name> [--install]" >&2; exit 1
        fi

        # Check if pack exists locally
        PACK_EXISTS=0
        PACKS_DIR="$PEON_DIR/packs"
        if [ -d "$PACKS_DIR/$PACK_ARG" ] && { [ -f "$PACKS_DIR/$PACK_ARG/openpeon.json" ] || [ -f "$PACKS_DIR/$PACK_ARG/manifest.json" ]; }; then
          PACK_EXISTS=1
        fi

        # If pack missing (or --install always fetches), download it
        if [ "$USE_INSTALL" -eq 1 ]; then
          PACK_DL="$(resolve_pack_download)" || exit 1
          bash "$PACK_DL" --dir="$PEON_DIR" --packs="$PACK_ARG" || exit 1
        fi

        PACK_ARG="$PACK_ARG" python3 -c "
import json, os, glob, sys
config_path = '$CONFIG'
pack_arg = os.environ.get('PACK_ARG', '')
packs_dir = '$PEON_DIR/packs'
names = sorted([
    d for d in os.listdir(packs_dir)
    if os.path.isdir(os.path.join(packs_dir, d)) and (
        os.path.exists(os.path.join(packs_dir, d, 'openpeon.json')) or
        os.path.exists(os.path.join(packs_dir, d, 'manifest.json'))
    )
])
if pack_arg not in names:
    print(f'Error: pack \"{pack_arg}\" not found.', file=sys.stderr)
    print(f'Available packs: {\", \".join(names)}', file=sys.stderr)
    sys.exit(1)
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['active_pack'] = pack_arg
json.dump(cfg, open(config_path, 'w'), indent=2)
display = pack_arg
for mname in ('openpeon.json', 'manifest.json'):
    mpath = os.path.join(packs_dir, pack_arg, mname)
    if os.path.exists(mpath):
        display = json.load(open(mpath)).get('display_name', pack_arg)
        break
print(f'peon-ping: switched to {pack_arg} ({display})')
" || exit 1
        sync_adapter_configs; exit 0 ;;
      next)
        python3 -c "
import json, os, glob
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
active = cfg.get('active_pack', 'peon')
packs_dir = '$PEON_DIR/packs'
names = sorted([
    d for d in os.listdir(packs_dir)
    if os.path.isdir(os.path.join(packs_dir, d)) and (
        os.path.exists(os.path.join(packs_dir, d, 'openpeon.json')) or
        os.path.exists(os.path.join(packs_dir, d, 'manifest.json'))
    )
])
if not names:
    print('Error: no packs found', flush=True)
    raise SystemExit(1)
try:
    idx = names.index(active)
    next_pack = names[(idx + 1) % len(names)]
except ValueError:
    next_pack = names[0]
cfg['active_pack'] = next_pack
json.dump(cfg, open(config_path, 'w'), indent=2)
# Read display name
for mname in ('openpeon.json', 'manifest.json'):
    mpath = os.path.join(packs_dir, next_pack, mname)
    if os.path.exists(mpath):
        display = json.load(open(mpath)).get('display_name', next_pack)
        break
print(f'peon-ping: switched to {next_pack} ({display})')
"
        sync_adapter_configs; exit 0 ;;
      remove)
        REMOVE_ARG="${3:-}"
        if [ "$REMOVE_ARG" = "--all" ]; then
          PACKS_TO_REMOVE=$(python3 -c "
import json, os, sys

config_path = '$CONFIG'
peon_dir = '$PEON_DIR'
packs_dir = os.path.join(peon_dir, 'packs')

try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
active = cfg.get('active_pack', 'peon')

installed = sorted([
    d for d in os.listdir(packs_dir)
    if os.path.isdir(os.path.join(packs_dir, d)) and (
        os.path.exists(os.path.join(packs_dir, d, 'openpeon.json')) or
        os.path.exists(os.path.join(packs_dir, d, 'manifest.json'))
    )
])

removable = [p for p in installed if p != active]
if not removable:
    print(f'No packs to remove — only the active pack (\"{active}\") is installed.', file=sys.stderr)
    sys.exit(1)

print(','.join(removable))
" 2>&1) || { echo "$PACKS_TO_REMOVE" >&2; exit 1; }
        elif [ -n "$REMOVE_ARG" ]; then
          PACKS_TO_REMOVE=$(REMOVE_ARG="$REMOVE_ARG" python3 -c "
import json, os, sys

config_path = '$CONFIG'
peon_dir = '$PEON_DIR'
packs_dir = os.path.join(peon_dir, 'packs')
remove_arg = os.environ.get('REMOVE_ARG', '')

try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
active = cfg.get('active_pack', 'peon')

installed = sorted([
    d for d in os.listdir(packs_dir)
    if os.path.isdir(os.path.join(packs_dir, d)) and (
        os.path.exists(os.path.join(packs_dir, d, 'openpeon.json')) or
        os.path.exists(os.path.join(packs_dir, d, 'manifest.json'))
    )
])

requested = [p.strip() for p in remove_arg.split(',') if p.strip()]
errors = []
valid = []
for p in requested:
    if p not in installed:
        errors.append(f'Pack \"{p}\" not found.')
    elif p == active:
        errors.append(f'Cannot remove \"{p}\" — it is the active pack. Switch first with: peon packs use <other>')
    else:
        valid.append(p)

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)

remaining = len(installed) - len(valid)
if remaining < 1:
    print('Cannot remove all packs — at least 1 must remain.', file=sys.stderr)
    sys.exit(1)

print(','.join(valid))
" 2>&1) || { echo "$PACKS_TO_REMOVE" >&2; exit 1; }
        else
          echo "Usage: peon packs remove <pack1,pack2,...>" >&2
          echo "       peon packs remove --all" >&2
          echo "Run 'peon packs list' to see installed packs." >&2
          exit 1
        fi

        # If we got here with packs to remove, confirm and delete
        if [ -z "$PACKS_TO_REMOVE" ]; then
          exit 0
        fi

        # Count packs
        PACK_COUNT=$(echo "$PACKS_TO_REMOVE" | tr ',' '\n' | wc -l | tr -d ' ')
        read -r -p "Remove ${PACK_COUNT} pack(s)? [y/N] " CONFIRM
        case "$CONFIRM" in
          [yY]|[yY][eE][sS]) ;;
          *) echo "Cancelled."; exit 0 ;;
        esac

        # Delete pack directories and clean config
        python3 -c "
import json, os, shutil

config_path = '$CONFIG'
peon_dir = '$PEON_DIR'
packs_dir = os.path.join(peon_dir, 'packs')
to_remove = '$PACKS_TO_REMOVE'.split(',')

for pack in to_remove:
    pack_path = os.path.join(packs_dir, pack)
    if os.path.isdir(pack_path):
        shutil.rmtree(pack_path)
        print(f'Removed {pack}')

# Clean pack_rotation in config
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
rotation = cfg.get('pack_rotation', [])
if rotation:
    cfg['pack_rotation'] = [p for p in rotation if p not in to_remove]
    json.dump(cfg, open(config_path, 'w'), indent=2)
"
        sync_adapter_configs; exit 0 ;;
      install)
        INSTALL_ARG="${3:-}"
        PACK_DL="$(resolve_pack_download)" || exit 1
        if [ "$INSTALL_ARG" = "--all" ]; then
          bash "$PACK_DL" --dir="$PEON_DIR" --all
        elif [ -n "$INSTALL_ARG" ]; then
          bash "$PACK_DL" --dir="$PEON_DIR" --packs="$INSTALL_ARG"
        else
          echo "Usage: peon packs install <pack1,pack2,...>" >&2
          echo "       peon packs install --all" >&2
          echo "" >&2
          echo "Run 'peon packs list --registry' to see available packs." >&2
          exit 1
        fi
        exit 0 ;;
      *)
        echo "Usage: peon packs <list|use|next|install|remove>" >&2; exit 1 ;;
    esac ;;
  mobile)
    case "${2:-}" in
      ntfy)
        TOPIC="${3:-}"
        if [ -z "$TOPIC" ]; then
          echo "Usage: peon mobile ntfy <topic> [--server=URL] [--token=TOKEN]" >&2
          echo "" >&2
          echo "Setup:" >&2
          echo "  1. Install ntfy app on your phone (ntfy.sh)" >&2
          echo "  2. Subscribe to your topic in the app" >&2
          echo "  3. Run: peon mobile ntfy my-unique-topic" >&2
          exit 1
        fi
        NTFY_SERVER="https://ntfy.sh"
        NTFY_TOKEN=""
        for arg in "${@:4}"; do
          case "$arg" in
            --server=*) NTFY_SERVER="${arg#--server=}" ;;
            --token=*)  NTFY_TOKEN="${arg#--token=}" ;;
          esac
        done
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['mobile_notify'] = {
    'enabled': True,
    'service': 'ntfy',
    'topic': '$TOPIC',
    'server': '$NTFY_SERVER',
    'token': '$NTFY_TOKEN'
}
json.dump(cfg, open(config_path, 'w'), indent=2)
"
        echo "peon-ping: mobile notifications enabled via ntfy"
        echo "  Topic:  $TOPIC"
        echo "  Server: $NTFY_SERVER"
        echo ""
        echo "Install the ntfy app and subscribe to '$TOPIC'"
        # Send test notification
        curl -sf -H "Title: peon-ping" -H "Tags: video_game" \
          -d "Mobile notifications connected!" \
          "${NTFY_SERVER}/${TOPIC}" >/dev/null 2>&1 && echo "Test notification sent!" || echo "Warning: could not reach ntfy server"
        sync_adapter_configs; exit 0 ;;
      pushover)
        USER_KEY="${3:-}"
        APP_TOKEN="${4:-}"
        if [ -z "$USER_KEY" ] || [ -z "$APP_TOKEN" ]; then
          echo "Usage: peon mobile pushover <user_key> <app_token>" >&2
          exit 1
        fi
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['mobile_notify'] = {
    'enabled': True,
    'service': 'pushover',
    'user_key': '$USER_KEY',
    'app_token': '$APP_TOKEN'
}
json.dump(cfg, open(config_path, 'w'), indent=2)
"
        echo "peon-ping: mobile notifications enabled via Pushover"
        sync_adapter_configs; exit 0 ;;
      telegram)
        BOT_TOKEN="${3:-}"
        CHAT_ID="${4:-}"
        if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
          echo "Usage: peon mobile telegram <bot_token> <chat_id>" >&2
          exit 1
        fi
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
cfg['mobile_notify'] = {
    'enabled': True,
    'service': 'telegram',
    'bot_token': '$BOT_TOKEN',
    'chat_id': '$CHAT_ID'
}
json.dump(cfg, open(config_path, 'w'), indent=2)
"
        echo "peon-ping: mobile notifications enabled via Telegram"
        sync_adapter_configs; exit 0 ;;
      off)
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
mn = cfg.get('mobile_notify', {})
mn['enabled'] = False
cfg['mobile_notify'] = mn
json.dump(cfg, open(config_path, 'w'), indent=2)
"
        echo "peon-ping: mobile notifications disabled"
        sync_adapter_configs; exit 0 ;;
      on)
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
mn = cfg.get('mobile_notify', {})
if not mn.get('service'):
    print('peon-ping: no mobile service configured. Run: peon mobile ntfy <topic>')
    raise SystemExit(1)
mn['enabled'] = True
cfg['mobile_notify'] = mn
json.dump(cfg, open(config_path, 'w'), indent=2)
print('peon-ping: mobile notifications enabled')
"
        _rc=$?; [ $_rc -eq 0 ] && sync_adapter_configs; exit $_rc ;;
      status)
        python3 -c "
import json
try:
    cfg = json.load(open('$CONFIG'))
    mn = cfg.get('mobile_notify', {})
except Exception:
    mn = {}
if not mn or not mn.get('service'):
    print('peon-ping: mobile notifications not configured')
    print('  Run: peon mobile ntfy <topic>')
else:
    enabled = mn.get('enabled', True)
    service = mn.get('service', '?')
    status = 'on' if enabled else 'off'
    print(f'peon-ping: mobile notifications {status} ({service})')
    if service == 'ntfy':
        print(f'  Topic:  {mn.get(\"topic\", \"?\")}')
        print(f'  Server: {mn.get(\"server\", \"https://ntfy.sh\")}')
    elif service == 'pushover':
        print(f'  User:   {mn.get(\"user_key\", \"?\")[:8]}...')
    elif service == 'telegram':
        print(f'  Chat:   {mn.get(\"chat_id\", \"?\")}')
"
        exit 0 ;;
      test)
        python3 -c "
import json, sys
try:
    cfg = json.load(open('$CONFIG'))
    mn = cfg.get('mobile_notify', {})
except Exception:
    mn = {}
if not mn or not mn.get('service') or not mn.get('enabled', True):
    print('peon-ping: mobile notifications not configured or disabled')
    sys.exit(1)
print('service=' + mn.get('service', ''))
" > /dev/null 2>&1 || { echo "peon-ping: mobile not configured" >&2; exit 1; }
        send_mobile_notification "Test notification from peon-ping" "peon-ping" "blue"
        wait
        echo "peon-ping: test notification sent"
        exit 0 ;;
      *)
        echo "Usage: peon mobile <ntfy|pushover|telegram|on|off|status|test>" >&2
        echo "" >&2
        echo "Quick start (free, no account needed):" >&2
        echo "  1. Install ntfy app on your phone (ntfy.sh)" >&2
        echo "  2. Subscribe to a unique topic in the app" >&2
        echo "  3. Run: peon mobile ntfy <your-topic>" >&2
        echo "" >&2
        echo "Commands:" >&2
        echo "  ntfy <topic>                Set up ntfy.sh notifications" >&2
        echo "  pushover <user> <app>       Set up Pushover notifications" >&2
        echo "  telegram <bot_token> <chat>  Set up Telegram notifications" >&2
        echo "  on                          Enable mobile notifications" >&2
        echo "  off                         Disable mobile notifications" >&2
        echo "  status                      Show current mobile config" >&2
        echo "  test                        Send a test notification" >&2
        exit 1 ;;
    esac ;;
  relay)
    RELAY_SCRIPT="$PEON_DIR/relay.sh"
    if [ ! -f "$RELAY_SCRIPT" ]; then
      echo "Error: relay.sh not found at $PEON_DIR" >&2
      echo "Re-run the installer to get the relay script." >&2
      exit 1
    fi
    shift
    exec bash "$RELAY_SCRIPT" "$@"
    ;;
  preview)
    PREVIEW_CAT="${2:-session.start}"
    # --list: show all categories and sound counts in the active pack
    if [ "$PREVIEW_CAT" = "--list" ]; then
      python3 -c "
import json, os, sys

peon_dir = '$PEON_DIR'
config_path = '$CONFIG'

try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
active_pack = cfg.get('active_pack', 'peon')

pack_dir = os.path.join(peon_dir, 'packs', active_pack)
if not os.path.isdir(pack_dir):
    print('peon-ping: pack \"' + active_pack + '\" not found.', file=sys.stderr)
    sys.exit(1)
manifest = None
for mname in ('openpeon.json', 'manifest.json'):
    mpath = os.path.join(pack_dir, mname)
    if os.path.exists(mpath):
        manifest = json.load(open(mpath))
        break
if not manifest:
    print('peon-ping: no manifest found for pack \"' + active_pack + '\".', file=sys.stderr)
    sys.exit(1)

display_name = manifest.get('display_name', active_pack)
categories = manifest.get('categories', {})
print('peon-ping: categories in ' + display_name)
print()
for cat in sorted(categories):
    sounds = categories[cat].get('sounds', [])
    count = len(sounds)
    unit = 'sound' if count == 1 else 'sounds'
    print(f'  {cat:24s} {count} {unit}')
"
      exit $? ;
    fi
    # Use Python to load config, find manifest, and list sounds for the category
    PREVIEW_OUTPUT=$(python3 -c "
import json, os, sys

peon_dir = '$PEON_DIR'
config_path = '$CONFIG'

# Load config
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
volume = cfg.get('volume', 0.5)
active_pack = cfg.get('active_pack', 'peon')

# Load manifest
pack_dir = os.path.join(peon_dir, 'packs', active_pack)
if not os.path.isdir(pack_dir):
    print('ERROR:Pack \"' + active_pack + '\" not found.', file=sys.stderr)
    sys.exit(1)
manifest = None
for mname in ('openpeon.json', 'manifest.json'):
    mpath = os.path.join(pack_dir, mname)
    if os.path.exists(mpath):
        manifest = json.load(open(mpath))
        break
if not manifest:
    print('ERROR:No manifest found for pack \"' + active_pack + '\".', file=sys.stderr)
    sys.exit(1)

category = '$PREVIEW_CAT'
categories = manifest.get('categories', {})
cat_data = categories.get(category)
if not cat_data or not cat_data.get('sounds'):
    avail = ', '.join(sorted(c for c in categories if categories[c].get('sounds')))
    print('ERROR:Category \"' + category + '\" not found in pack \"' + active_pack + '\".', file=sys.stderr)
    print('Available categories: ' + avail, file=sys.stderr)
    sys.exit(1)

display_name = manifest.get('display_name', active_pack)
print('PACK_DISPLAY=' + repr(display_name))
print('VOLUME=' + str(volume))

sounds = cat_data['sounds']
for i, s in enumerate(sounds):
    file_ref = s.get('file', '')
    label = s.get('label', file_ref)
    if '/' in file_ref:
        fpath = os.path.realpath(os.path.join(pack_dir, file_ref))
    else:
        fpath = os.path.realpath(os.path.join(pack_dir, 'sounds', file_ref))
    pack_root = os.path.realpath(pack_dir) + os.sep
    if not fpath.startswith(pack_root):
        continue
    print('SOUND:' + fpath + '|' + label)
" 2>"$PEON_DIR/.preview_err")
    PREVIEW_RC=$?
    if [ $PREVIEW_RC -ne 0 ]; then
      cat "$PEON_DIR/.preview_err" | sed 's/^ERROR:/peon-ping: /' >&2
      rm -f "$PEON_DIR/.preview_err"
      exit 1
    fi
    rm -f "$PEON_DIR/.preview_err"

    # Parse output
    PREVIEW_VOL=$(echo "$PREVIEW_OUTPUT" | grep '^VOLUME=' | head -1 | cut -d= -f2)
    PREVIEW_VOL="${PREVIEW_VOL:-0.5}"
    PACK_DISPLAY=$(echo "$PREVIEW_OUTPUT" | grep '^PACK_DISPLAY=' | head -1 | sed "s/^PACK_DISPLAY=//;s/^'//;s/'$//")

    echo "peon-ping: previewing [$PREVIEW_CAT] from $PACK_DISPLAY"
    echo ""

    echo "$PREVIEW_OUTPUT" | grep '^SOUND:' | while IFS='|' read -r filepath label; do
      filepath="${filepath#SOUND:}"
      if [ -f "$filepath" ]; then
        echo "  ▶ $label"
        play_sound "$filepath" "$PREVIEW_VOL"
        wait
        sleep 0.3
      fi
    done
    exit 0 ;;
  update)
    echo "Updating peon-ping..."
    INSTALL_SCRIPT="$PEON_DIR/install.sh"
    if [ -f "$INSTALL_SCRIPT" ]; then
      bash "$INSTALL_SCRIPT"
    else
      curl -fsSL https://raw.githubusercontent.com/MikeKovetsky/zugzug.sh/main/install.sh | bash
    fi
    exit $? ;;
  economy)
    python3 -c "
import json, os
state_file = '$STATE'
config_path = '$CONFIG'
$_PY_STATE_IO
state = _load_state(state_file)
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
econ = state.get('economy', {})
stats = state.get('stats', {})
gold = econ.get('gold', 0)
lumber = econ.get('lumber', 0)
upkeep = econ.get('upkeep', 'none')
daily_tasks = econ.get('daily_tasks', 0)
print(f'Gold: {gold}')
print(f'Lumber: {lumber}')
print(f'Upkeep: {upkeep}')
print(f'Daily tasks: {daily_tasks}/80')
print(f'Lifetime gold earned: {stats.get(\"total_gold_earned\", 0)}')
print(f'Lifetime lumber earned: {stats.get(\"total_lumber_earned\", 0)}')
army = state.get('army', {})
_UNIT_HP = dict(grunt=30, raider=50, tauren=80, shaman=20)
for _uk in list(army.keys()):
    if isinstance(army[_uk], int): army[_uk] = [_UNIT_HP.get(_uk, 30)] * army[_uk]
if army:
    buildings = state.get('buildings', {})
    _UNIT_UPKEEP = {'grunt': 10, 'raider': 40, 'tauren': 100, 'shaman': 30}
    total_units = sum(len(v) for v in army.values())
    upkeep_cost = sum(_UNIT_UPKEEP.get(uid, 0) * len(hps) for uid, hps in army.items())
    if 'goblin_lab' in buildings:
        upkeep_cost //= 2
    food_cap = 12
    if 'fortress' in buildings:
        food_cap += 8
    if 'citadel' in buildings:
        food_cap += 10
    food_cap += buildings.get('farm', {}).get('count', 0) * 5
    _UNIT_FOOD = {'grunt': 2, 'raider': 3, 'tauren': 5, 'shaman': 2}
    food_used = sum(_UNIT_FOOD.get(uid, 0) * len(hps) for uid, hps in army.items())
    _wounded = sum(1 for uid, hps in army.items() for h in hps if h < _UNIT_HP.get(uid, 30))
    _hp_str = f' ({_wounded} wounded)' if _wounded else ''
    print(f'Army: {total_units} units{_hp_str} ({food_used}/{food_cap} food) | Daily upkeep: {upkeep_cost}g')
if gold < 0:
    print(f'*** IN DEBT: {gold} gold ***')
"
    exit 0 ;;
  achievements)
    python3 -c "
import json, os, time
state_file = '$STATE'
$_PY_STATE_IO
state = _load_state(state_file)
stats = state.get('stats', {})
unlocked = stats.get('achievements_unlocked', {})
defs = [
    ('first_blood', 'First Blood', 'Accumulate 20 fatigue'),
    ('zug_zug_veteran', 'Zug Zug Veteran', '100 tasks completed'),
    ('night_elf', 'Night Elf', 'Code past 2 AM'),
    ('dawn_patrol', 'Dawn Patrol', 'Session before 6 AM'),
    ('weekend_warrior', 'Weekend Warrior', '10 weekend sessions'),
    ('iron_peon', 'Iron Peon', '7-day coding streak'),
    ('rage_quit', 'Rage Quit', 'Fatigue hits 40 in one session'),
    ('oops', 'Oops', 'Repair items 25 times'),
    ('the_grind', 'The Grind', '1000 lifetime tasks'),
    ('permit_patty', 'Permit Patty', '20 permissions in a session'),
    ('compact_survivor', 'Compact Survivor', '5 context compacts'),
    ('architect', 'Architect', 'Build 10 structures'),
    ('combo_fiend', 'Combo Fiend', 'Reach 50 combo'),
    ('mogul', 'Mogul', '5000 lifetime gold earned'),
    ('stop_clicking', 'Stop Clicking Me!', '500 lifetime prompts'),
    ('peon_union_rep', 'Peon Union Rep', 'Fatigue hits 50 in one session'),
    ('touch_grass', 'Touch Grass', 'Code past 3 AM on a weekend'),
    ('first_kill', 'First Kill', 'Defeat your first boss'),
    ('raid_leader', 'Raid Leader', 'Defeat 10 bosses'),
    ('you_no_take', 'You No Take Candle!', 'Defeat 5 kobolds'),
    ('night_raid', 'Night Raid', 'Hit a boss past midnight'),
    ('combo_god', 'Combo God', 'Reach 100 combo'),
    ('hoarder', 'Hoarder', 'Own 40+ items total'),
    ('lunch_raider', 'Lunch Raider', 'Hit a boss during lunch hour'),
    ('boss_slayer', 'Boss Slayer', 'Defeat all 11 unique bosses'),
    ('warchief', 'Warchief', 'Have 10 units in your army'),
    ('general', 'General', 'Hire 50 units total'),
    ('casualties_of_war', 'Casualties of War', 'Lose 20 units in battle'),
    ('speedrun', 'Speed Run', 'Kill any boss in under 5 minutes'),
    ('leeroy', 'LEEEEROY JENKINS!', 'Lose to Whelps below 20% HP'),
    ('speed_lich_king', 'Lich King Any%', 'Kill The Lich King in under 4 days'),
    ('lich_kings_end', 'Arthas\\'s End', 'Defeat The Lich King'),
    ('loot_goblin', 'Loot Goblin', 'Loot 1000 items'),
    ('iron_will', 'Iron Will', '30-day coding streak'),
    ('unbreakable', 'Unbreakable', '365-day coding streak'),
    ('duct_tape', 'Duct Tape Engineer', 'Repair items 500 times'),
    ('trade_prince', 'Trade Prince', 'Earn 1,000,000 lifetime gold'),
    ('witching_hour', 'The Witching Hour', 'Complete a task at exactly midnight'),
    ('so_close', 'So Close', 'Lose a combo at exactly 99'),
    ('all_nighter', 'All-Nighter', 'Session spanning midnight to past 5 AM'),
    ('tgif_zombie', 'TGIF Zombie', 'Friday evening with 40+ fatigue'),
    ('sunday_scaries', 'Sunday Scaries', 'Start a session Sunday after 8 PM'),
    ('world_tour', 'World Tour', 'Work in 10 different repos'),
]
print(f'Achievements: {len(unlocked)}/{len(defs)}')
print()
for aid, name, desc in defs:
    if aid in unlocked:
        ts = unlocked[aid]
        when = time.strftime('%Y-%m-%d', time.localtime(ts))
        print(f'  [x] {name:20s} {desc:30s} (unlocked {when})')
    else:
        print(f'  [ ] {name:20s} {desc}')
"
    exit 0 ;;
  build)
    shift
    python3 -c "
import json, os, sys, time
state_file = '$STATE'
config_path = '$CONFIG'
arg = '${1:-list}'
$_PY_STATE_IO
state = _load_state(state_file)
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
econ = state.get('economy', {})
buildings = state.get('buildings', {})
gold = econ.get('gold', 0)
lumber = econ.get('lumber', 0)
today = state.get('goblin_discount_date', '')
import datetime
discount = today == datetime.date.today().isoformat()
BUILDINGS = {
    'burrow':          (500, 250, 'peon bunker — pause fatigue for 1 hour.'),
    'watch_tower':     (750, 375, 'Early warning at 80% context.'),
    'war_mill':        (1000, 500, 'Unlocks combo system (multi-kill tracking).'),
    'altar':           (1500, 750, 'peon resurrect — restore combo once/day.'),
    'lumber_mill':     (1500, 500, '2x lumber from all sources.'),
    'tavern':          (2000, 1000, 'peon taunt — play a taunt on demand.'),
    'stronghold':      (2500, 1000, 'Rank upgrade. Unlocks random events.'),
    'spirit_lodge':    (2500, 1000, 'Unlocks idle peon wisdom.'),
    'barracks':        (3000, 1200, 'Subagent sessions count toward stats.'),
    'blacksmith':      (4000, 1500, '3x slower durability loss.'),
    'arcane_sanctum':  (7500, 3000, 'Unlocks peon prophecies on session start.'),
    'fortress':        (10000, 4000, 'Max rank. Unlocks leaderboard title.'),
    'dark_portal':     (12000, 5000, 'Open the Dark Portal. Raid bosses await beyond.'),
    'citadel':         (15000, 6000, 'Prestige rank. Boosts item drop rate.'),
    'farm':            (8000, 3000, '+5 food cap. Build up to 3.'),
    'goblin_lab':      (18000, 7000, 'Goblin tinkerers. Army upkeep halved.'),
    'world_tree':      (25000, 10000, 'Nordrassil takes root. Gold mine yields last longer (80/120 task thresholds).'),
}
FARM_MAX = 3
if arg == 'list':
    print(f'Gold: {gold} | Lumber: {lumber}')
    if discount:
        print('*** Goblin Merchant discount active! 50% off! ***')
    print()
    print('Great Hall (built)')
    for bname, (gcost, lcost, desc) in BUILDINGS.items():
        g = gcost // 2 if discount else gcost
        l = lcost // 2 if discount else lcost
        built = bname in buildings
        if bname == 'farm':
            cnt = buildings.get('farm', {}).get('count', 1 if built else 0)
            if built and cnt >= FARM_MAX:
                marker = '[x]'
                afford = f' ({cnt}/{FARM_MAX})'
            else:
                marker = f'[{cnt}/{FARM_MAX}]'
                afford = (' (can afford)' if gold >= g and lumber >= l else f' (need {g}g/{l}l)')
        else:
            marker = '[x]' if built else '[ ]'
            afford = '' if built else (' (can afford)' if gold >= g and lumber >= l else f' (need {g}g/{l}l)')
        print(f'  {marker} {bname:15s} {g}g/{l}l  {desc}{afford}')
else:
    bname = arg.lower().replace('-', '_')
    if bname not in BUILDINGS:
        print('Unknown building: ' + arg)
        print('Available: ' + ', '.join(BUILDINGS.keys()))
        sys.exit(1)
    if bname == 'farm':
        cur = buildings.get('farm', {}).get('count', 0) if 'farm' in buildings else 0
        if cur >= FARM_MAX:
            print(f'Farm limit reached ({cur}/{FARM_MAX})!')
            sys.exit(0)
    elif bname in buildings:
        print(bname + ' is already built!')
        sys.exit(0)
    gcost, lcost, desc = BUILDINGS[bname]
    if discount:
        gcost //= 2
        lcost //= 2
    if gold < gcost or lumber < lcost:
        short_g = max(0, gcost - gold)
        short_l = max(0, lcost - lumber)
        print(f'Not enough resources! Need {gcost}g/{lcost}l, have {gold}g/{lumber}l')
        if short_g > 0:
            print(f'  Short {short_g} gold')
        if short_l > 0:
            print(f'  Short {short_l} lumber')
        sys.exit(1)
    econ['gold'] = gold - gcost
    econ['lumber'] = lumber - lcost
    if bname == 'farm':
        existing = buildings.get('farm', {})
        cnt = existing.get('count', 0) + 1
        buildings['farm'] = dict(built_at=int(time.time()), count=cnt)
    else:
        buildings[bname] = dict(built_at=int(time.time()))
    state['economy'] = econ
    state['buildings'] = buildings
    stats = state.get('stats', {})
    stats['buildings_built'] = len(buildings)
    state['stats'] = stats
    _save_state(state_file, state)
    if bname == 'farm':
        cnt = buildings['farm'].get('count', 1)
        print(f'Built farm ({cnt}/{FARM_MAX})! (-{gcost}g/-{lcost}l)')
    else:
        print(f'Built {bname}! (-{gcost}g/-{lcost}l)')
    print('  ' + desc)
    print('  Gold: ' + str(econ['gold']) + ' | Lumber: ' + str(econ['lumber']))
"
    exit $? ;;
  bunker)
    python3 -c "
import json, os, time
state_file = '$STATE'
$_PY_STATE_IO
state = _load_state(state_file)
buildings = state.get('buildings', {})
if 'burrow' not in buildings:
    print('Build a Burrow first! (peon build burrow)')
    exit(1)
now = time.time()
until = state.get('bunker_until', 0)
if until > now:
    remaining = int((until - now) / 60)
    print(f'Already in bunker! {remaining} minutes remaining.')
    exit(0)
state['bunker_until'] = now + 3600
_save_state(state_file, state)
print('Peon hiding! Fatigue paused for 1 hour.')
"
    exit $? ;;
  resurrect)
    python3 -c "
import json, os, time, datetime
state_file = '$STATE'
$_PY_STATE_IO
state = _load_state(state_file)
buildings = state.get('buildings', {})
if 'altar' not in buildings:
    print('Build an Altar of Storms first! (peon build altar)')
    exit(1)
today = datetime.date.today().isoformat()
if state.get('last_resurrect_date') == today:
    print('Already used resurrect today. Try again tomorrow.')
    exit(0)
old_combo = state.get('combo_count', 0)
best = state.get('stats', {}).get('max_combo', 0)
state['combo_count'] = max(old_combo, best // 2)
state['last_resurrect_date'] = today
_save_state(state_file, state)
print(f'Peon call upon ancestors! Combo restored to {state[\"combo_count\"]}x.')
"
    exit $? ;;
  taunt)
    python3 -c "
import json, os, random
state_file = '$STATE'
$_PY_STATE_IO
state = _load_state(state_file)
buildings = state.get('buildings', {})
if 'tavern' not in buildings:
    print('Build a Tavern first! (peon build tavern)')
    exit(1)
taunts = [
    'Human considered different career?',
    'Peon seen better code from a murloc.',
    'At this point, Peon writing the code.',
    'Me going to work for the Night Elves.',
    'Even peasant code better.',
    'Peon losing faith in humanity.',
    'Stop poking me!',
    'Why you keep asking?!',
    'Peon file complaint with Warchief.',
    'Human think code review hard? Try three hundred squats!',
]
print(random.choice(taunts))
"
    exit 0 ;;
  rest)
    python3 -c "
import json, os
state_file = '$STATE'
$_PY_STATE_IO
state = _load_state(state_file)
fatigue = state.get('fatigue', 0)
if fatigue == 0:
    print('Peon not tired. Peon strong!')
    exit(0)
econ = state.get('economy', {})
lumber = econ.get('lumber', 0)
cost = 20
if lumber < cost:
    print(f'Not enough lumber! Need {cost}l, have {lumber}l')
    exit(1)
econ['lumber'] = lumber - cost
state['economy'] = econ
state['fatigue'] = 0
_save_state(state_file, state)
print(f'Peon rested! Fatigue reset to 0. (-{cost} lumber)')
print(f'Lumber: {econ[\"lumber\"]}')
"
    exit $? ;;
  repair)
    shift
    python3 -c "
import json, os, sys
state_file = '$STATE'
target = '${1:-all}'
$_PY_STATE_IO
state = _load_state(state_file)
econ = state.get('economy', {})
gold = econ.get('gold', 0)
equipped = state.get('equipped', [])
durability = state.get('item_durability', {})
REPAIR_COSTS = {'common': 12, 'uncommon': 25, 'rare': 50, 'epic': 100, 'legendary': 250}
ITEMS_R = {
    'claws_of_attack': 'common', 'gauntlets_of_str': 'common', 'ring_of_protection': 'common',
    'slippers_of_agility': 'common', 'circlet_of_nobility': 'common', 'mantle_of_intel': 'common',
    'belt_of_str': 'common', 'gloves_of_haste': 'common', 'robe_of_magi': 'common',
    'pendant_of_mana': 'common', 'hood_of_cunning': 'common', 'medallion': 'common',
    'tome_of_power': 'common', 'skull_shield': 'common', 'kelen_dagger': 'common', 'void_stone': 'common',
    'war_axe': 'common', 'iron_shield': 'common', 'kobold_candle': 'common',
    'boots_of_speed': 'uncommon', 'periapt_of_vitality': 'uncommon', 'pendant_of_energy': 'uncommon',
    'serrated_blade': 'uncommon', 'venom_orb': 'uncommon', 'troll_totem': 'uncommon',
    'helm_of_valor': 'rare', 'cloak_of_shadows': 'rare', 'orb_of_fire': 'rare',
    'gem_of_seeing': 'rare', 'staff_of_negation': 'rare', 'sobi_mask': 'rare',
    'talisman_of_evasion': 'rare', 'ring_of_regen': 'rare', 'scourge_bone': 'rare',
    'shadow_orb': 'rare', 'lion_horn': 'rare',
    'bloodstone': 'rare', 'runed_gauntlets': 'rare', 'executioners_blade': 'rare',
    'ogre_scepter': 'rare', 'infernal_core': 'rare',
    'crown_of_kings': 'epic', 'mask_of_death': 'epic', 'amulet_of_spell': 'epic', 'khadgars_pipe': 'epic',
    'doom_hammer': 'epic', 'black_arrow': 'epic', 'mannoroths_blood': 'epic',
    'frostmourne': 'legendary', 'wirts_leg': 'legendary', 'thunderfury': 'legendary',
    'unstoppable_force': 'legendary', 'azzinoth_blades': 'legendary', 'ashbringer': 'legendary',
    'sulfuras': 'legendary', 'crown_of_eredar': 'legendary', 'helm_of_domination': 'legendary',
}
MAX_DUR = {'common': 50, 'uncommon': 75, 'rare': 100, 'epic': 150, 'legendary': 200}
has_discount = False
for eid in equipped:
    if eid == 'mask_of_death':
        has_discount = True
        break
damaged = []
for eid in equipped:
    r = ITEMS_R.get(eid, 'common')
    mx = MAX_DUR.get(r, 50)
    cur = durability.get(eid, mx)
    if cur < mx:
        damaged.append(eid)
if target != 'all':
    if target in damaged:
        damaged = [target]
    elif target in equipped:
        print(f'{target} is at full durability.')
        exit(0)
    else:
        print(f'Item not found or not equipped: {target}')
        exit(1)
if not damaged:
    print('Nothing to repair. All items operational!')
    exit(0)
was_broken = set(eid for eid in damaged if durability.get(eid, 0) <= 0)
total_cost = 0
for eid in damaged:
    r = ITEMS_R.get(eid, 'common')
    c = REPAIR_COSTS.get(r, 25)
    if eid in was_broken:
        c *= 2
    if has_discount:
        c = c // 2
    total_cost += c
if gold < total_cost:
    print(f'Not enough gold! Need {total_cost}g, have {gold}g')
    exit(1)
econ['gold'] = gold - total_cost
for eid in damaged:
    r = ITEMS_R.get(eid, 'common')
    durability[eid] = MAX_DUR.get(r, 50)
state['economy'] = econ
state['item_durability'] = durability
stats = state.get('stats', {})
stats['repairs_total'] = stats.get('repairs_total', 0) + len(damaged)
state['stats'] = stats
_save_state(state_file, state)
print(f'Repaired {len(damaged)} item(s)! (-{total_cost}g)')
for eid in damaged:
    tag = ' (broken - 2x cost)' if eid in was_broken else ''
    print(f'  {eid} restored{tag}')
print(f'Gold: {econ[\"gold\"]}')
"
    exit $? ;;
  inventory)
    python3 -c "
import json, os
state_file = '$STATE'
$_PY_STATE_IO
state = _load_state(state_file)
inventory = state.get('inventory', [])
equipped = state.get('equipped', [])
ITEMS = {
    'claws_of_attack':     ('Claws of Attack +3',     'common',    '+3 bonus gold per task'),
    'gauntlets_of_str':    ('Gauntlets of Strength',  'common',    '+2 bonus lumber per prompt'),
    'ring_of_protection':  ('Ring of Protection +2',  'common',    '+2 bonus gold per task'),
    'slippers_of_agility': ('Slippers of Agility',   'common',    'Combos count +1 extra'),
    'circlet_of_nobility': ('Circlet of Nobility',    'common',    '+2 bonus gold per task'),
    'mantle_of_intel':     ('Mantle of Intelligence', 'common',    '+1 bonus lumber per prompt'),
    'belt_of_str':         ('Belt of Giant Strength +6', 'common', '+1 bonus gold per task'),
    'gloves_of_haste':     ('Gloves of Haste',       'common',    'Combos count +1 extra'),
    'robe_of_magi':        ('Robe of the Magi +6',   'common',    '+2 bonus lumber per prompt'),
    'pendant_of_mana':     ('Pendant of Mana',       'common',    '+1 bonus lumber per prompt'),
    'hood_of_cunning':     ('Hood of Cunning',       'common',    '+2 bonus gold per task'),
    'medallion':           ('Medallion of Courage',   'common',    '+2 bonus gold per task'),
    'tome_of_power':       ('Tome of Power +2',      'common',    '+1 bonus gold per task'),
    'skull_shield':        ('Skull Shield',           'common',    'Gold mine depletion +10 tasks later'),
    'kelen_dagger':        ('Kelen\\'s Dagger of Escape', 'common', 'Combos count +1 extra'),
    'void_stone':          ('Void Stone',             'common',    '+1 bonus lumber per prompt'),
    'scroll_of_tp':        ('Scroll of Town Portal',  'uncommon',  'Restore combo streak (consumable)'),
    'potion_of_healing':   ('Potion of Healing',      'uncommon',  'Restore 200 gold (consumable)'),
    'potion_of_mana':      ('Potion of Mana',         'uncommon',  'Gain 50 lumber (consumable)'),
    'boots_of_speed':      ('Boots of Speed',         'uncommon',  '2x lumber from prompts'),
    'periapt_of_vitality': ('Periapt of Vitality',    'uncommon',  'Gold mine depletion +25 tasks later'),
    'pendant_of_energy':   ('Pendant of Energy',      'uncommon',  '+5 bonus gold per task'),
    'tome_of_xp':          ('Tome of Experience',     'uncommon',  'Gain 500 gold (consumable)'),
    'helm_of_valor':       ('Helm of Valor',          'rare',      '+4 raid damage'),
    'cloak_of_shadows':    ('Cloak of Shadows',       'rare',      'Fatigue paused while equipped'),
    'orb_of_fire':         ('Orb of Fire',            'rare',      '+3 raid damage'),
    'gem_of_seeing':       ('Gem of True Seeing',     'rare',      '10% chance of 3x gold on task complete'),
    'staff_of_negation':   ('Staff of Negation',      'rare',      '+10 bonus gold per task'),
    'sobi_mask':           ('Sobi Mask',              'rare',      '3x lumber from prompts'),
    'inv_potion':          ('Potion of Invisibility',  'rare',     'Gain 1500 gold (consumable)'),
    'talisman_of_evasion': ('Talisman of Evasion',    'rare',      'First fatigue per session is free'),
    'ring_of_regen':       ('Ring of Regeneration',    'rare',      '+8 bonus gold per task'),
    'scourge_bone':        ('Scourge Bone Chimes',    'rare',      '+8 bonus gold per task'),
    'shadow_orb':          ('Shadow Orb +10',         'rare',      '5% chance of 3x gold on task complete'),
    'lion_horn':           ('Lion Horn of Stormwind',  'rare',      'Gold mine depletion +15 tasks later'),
    'crown_of_kings':      ('Crown of Kings +5',      'epic',      '2x all gold income'),
    'mask_of_death':       ('Mask of Death',          'epic',      '20% crit chance (3x gold)'),
    'amulet_of_spell':     ('Amulet of Spell Shield', 'epic',      'Heal army 3 HP per task'),
    'khadgars_pipe':       ('Khadgar\\'s Pipe',       'epic',      '5x lumber from prompts'),
    'ankh':                ('Ankh of Reincarnation',  'epic',      'Gain 5000 gold (consumable)'),
    'frostmourne':         ('Frostmourne',            'legendary', '+20 raid damage. The blade hungers.'),
    'wirts_leg':           ('Wirt\\'s Leg',           'legendary', 'Does absolutely nothing. Peon confused.'),
    'thunderfury':         ('Thunderfury, Blessed Blade of the Windseeker', 'legendary', 'Poison: 10 damage per event in raids'),
    'unstoppable_force':   ('The Unstoppable Force',  'legendary', 'Combos never break from errors'),
    'azzinoth_blades':     ('Warglaives of Azzinoth', 'legendary', '+2 combo per task. You are not prepared.'),
    'ashbringer':          ('Ashbringer',             'legendary', '25% crit chance (3x gold). Holy light!'),
    'cheese':              ('Cheese',                 'legendary', 'Restore 10000g + 5000l. Mmm. (consumable)'),
    'scroll_of_heal':      ('Scroll of Healing',      'uncommon',  'Heal all army units 15 HP (consumable)'),
    'healing_ward':        ('Healing Ward',            'rare',      'Fully heal all army units (consumable)'),
    'firebolt':            ('Firebolt',               'common',    'Deal 50 damage to active boss (consumable)'),
    'goblin_sapper':       ('Goblin Sapper Charge',   'common',    'Deal 100 damage to active boss (consumable)'),
    'storm_bolt':          ('Storm Bolt',             'common',    'Deal 250 damage to active boss (consumable)'),
    'demolisher_shot':     ('Demolisher Shot',        'common',    'Deal 500 damage to active boss (consumable)'),
    'thunder_clap':        ('Thunder Clap',           'uncommon',  'Deal 750 damage to active boss (consumable)'),
    'chain_lightning':     ('Chain Lightning',        'uncommon',  'Deal 2000 damage to active boss (consumable)'),
    'death_coil':          ('Death Coil',             'uncommon',  'Deal 5000 damage to active boss (consumable)'),
    'finger_of_death':     ('Finger of Death',        'rare',      'Deal 10000 damage to active boss (consumable)'),
    'doom':                ('Doom',                   'epic',      'Deal 40000 damage to active boss (consumable)'),
    'war_axe':             ('War Axe',                'common',    '+1 raid damage per task'),
    'iron_shield':         ('Iron Shield',            'common',    '25% less gold lost from counter-attacks'),
    'serrated_blade':      ('Serrated Blade',         'uncommon',  '+2 raid damage per task'),
    'venom_orb':           ('Venom Orb',              'uncommon',  'Poison: 1 damage per event during raids'),
    'bloodstone':          ('Bloodstone',             'rare',      '+1 damage per 10 combo in raids'),
    'runed_gauntlets':     ('Runed Gauntlets',        'rare',      '+15% crit chance vs bosses'),
    'executioners_blade':  ('Executioner\\'s Blade',  'rare',      '3x damage when boss below 20% HP'),
    'doom_hammer':         ('Doom Hammer',            'epic',      '+10 raid damage per task'),
    'black_arrow':         ('Black Arrow',            'epic',      '+3 poison per event + 1 flat raid damage'),
    'sulfuras':            ('Sulfuras, Hand of Ragnaros', 'legendary', '+10 raid damage. Overkill carries to next boss.'),
    'kobold_candle':       ('Kobold\\'s Candle',      'common',    '+3g per task during boss fights'),
    'troll_totem':         ('Troll Regeneration Totem', 'uncommon', 'Repair 1 durability per 5 tasks'),
    'ogre_scepter':        ('Ogre Magi Scepter',      'rare',      '+3 raid damage per task'),
    'infernal_core':       ('Infernal Core',          'rare',      'Counter-attacks deal 50% less gold damage'),
    'mannoroths_blood':    ('Mannoroth\\'s Blood',    'epic',      '5x damage when boss below 20% HP'),
    'crown_of_eredar':     ('Crown of the Eredar',    'legendary', '+1 bonus drop from bosses'),
    'helm_of_domination':  ('Helm of Domination',     'legendary', '+2 bonus drops from bosses'),
}
rcolors = dict(common='', uncommon='\033[32m', rare='\033[34m', epic='\033[35m', legendary='\033[33m')
reset = '\033[0m'
if not inventory and not equipped:
    print('Inventory empty. Complete tasks to find items!')
    exit(0)
print(f'Inventory: {len(inventory)} items | Equipped: {len(equipped)}/6')
print()
if equipped:
    print('Equipped:')
    for eid in equipped:
        if eid in ITEMS:
            n, r, d = ITEMS[eid]
            c = rcolors.get(r, '')
            print(f'  [{r[0].upper()}] {c}{n}{reset}  {d}')
    print()
if inventory:
    print('Backpack:')
    for iid in inventory:
        if iid in ITEMS:
            n, r, d = ITEMS[iid]
            c = rcolors.get(r, '')
            print(f'  [{r[0].upper()}] {c}{n}{reset}  {d}  ({iid})')
"
    exit 0 ;;
  equip)
    shift
    python3 -c "
import json, os, sys
state_file = '$STATE'
item_id = '${1:-}'
if not item_id:
    print('Usage: peon equip <item_id>')
    print('Run peon inventory to see item IDs')
    sys.exit(1)
$_PY_STATE_IO
state = _load_state(state_file)
inventory = state.get('inventory', [])
equipped = state.get('equipped', [])
if item_id not in inventory:
    print('Item not in backpack: ' + item_id)
    sys.exit(1)
if len(equipped) >= 6:
    print('Equipment full! Unequip something first (6/6 slots)')
    sys.exit(1)
if item_id in equipped:
    print('Already equipped!')
    sys.exit(0)
inventory.remove(item_id)
equipped.append(item_id)
state['inventory'] = inventory
state['equipped'] = equipped
_save_state(state_file, state)
print('Equipped: ' + item_id)
"
    exit $? ;;
  unequip)
    shift
    python3 -c "
import json, os, sys
state_file = '$STATE'
item_id = '${1:-}'
if not item_id:
    print('Usage: peon unequip <item_id>')
    sys.exit(1)
$_PY_STATE_IO
state = _load_state(state_file)
inventory = state.get('inventory', [])
equipped = state.get('equipped', [])
if item_id not in equipped:
    print('Item not equipped: ' + item_id)
    sys.exit(1)
equipped.remove(item_id)
inventory.append(item_id)
state['inventory'] = inventory
state['equipped'] = equipped
_save_state(state_file, state)
print('Unequipped: ' + item_id)
"
    exit $? ;;
  use)
    shift
    python3 -c "
import json, os, sys, time
state_file = '$STATE'
item_id = '${1:-}'
if not item_id:
    print('Usage: peon use <item_id>')
    sys.exit(1)
$_PY_STATE_IO
state = _load_state(state_file)
inventory = state.get('inventory', [])
equipped = state.get('equipped', [])
all_items = inventory + equipped
if item_id not in all_items:
    print('Item not found: ' + item_id)
    sys.exit(1)
consumables = {
    'scroll_of_tp':     ('Combo restored!', lambda s: s.update(combo_count=max(s.get('combo_count',0), s.get('stats',{}).get('max_combo',0)//2))),
    'potion_of_healing': ('Restored 200 gold!', lambda s: s.get('economy',{}).update(gold=s.get('economy',{}).get('gold',0)+200)),
    'potion_of_mana':   ('Gained 50 lumber!', lambda s: s.get('economy',{}).update(lumber=s.get('economy',{}).get('lumber',0)+50)),
    'tome_of_xp':       ('Gained 500 gold!', lambda s: s.get('economy',{}).update(gold=s.get('economy',{}).get('gold',0)+500)),
    'inv_potion':       ('Gained 1500 gold!', lambda s: s.get('economy',{}).update(gold=s.get('economy',{}).get('gold',0)+1500)),
    'ankh':             ('Reincarnation! +5000 gold!', lambda s: s.get('economy',{}).update(gold=s.get('economy',{}).get('gold',0)+5000)),
    'invuln_potion':    ('Divine Shield! +3000g +1000l!', lambda s: (s.get('economy',{}).update(gold=s.get('economy',{}).get('gold',0)+3000), s.get('economy',{}).update(lumber=s.get('economy',{}).get('lumber',0)+1000))),
    'cheese':           ('Mmm. +10000g +5000l!', lambda s: (s.get('economy',{}).update(gold=s.get('economy',{}).get('gold',0)+10000), s.get('economy',{}).update(lumber=s.get('economy',{}).get('lumber',0)+5000))),
}
heal_items = {'scroll_of_heal': 15, 'healing_ward': 999, 'ensnare_trap': 50}
_UNIT_HP = {'grunt': 30, 'raider': 50, 'tauren': 80, 'shaman': 20}
if item_id in heal_items:
    army = state.get('army', {})
    if not army:
        print('No army to heal! Hire units first: peon hire <unit>')
        sys.exit(1)
    amount = heal_items[item_id]
    healed = 0
    for uid, hps in army.items():
        mx = _UNIT_HP.get(uid, 30)
        for i in range(len(hps)):
            if hps[i] < mx:
                old = hps[i]
                hps[i] = min(mx, hps[i] + amount)
                healed += hps[i] - old
    if healed == 0:
        print('Army is already at full health!')
        sys.exit(0)
    state['army'] = army
    if item_id in inventory: inventory.remove(item_id)
    elif item_id in equipped: equipped.remove(item_id)
    state['inventory'] = inventory
    state['equipped'] = equipped
    _save_state(state_file, state)
    print(f'Healed {healed} HP across your army!')
    sys.exit(0)
boss_items = {
    'firebolt': 50, 'goblin_sapper': 100, 'storm_bolt': 250,
    'demolisher_shot': 500, 'thunder_clap': 750, 'chain_lightning': 2000,
    'death_coil': 5000, 'finger_of_death': 10000, 'doom': 40000,
}
if item_id in boss_items:
    boss = state.get('active_boss')
    if not boss or boss.get('hp', 0) <= 0:
        print('No active boss! Start a raid first: peon raid <boss>')
        sys.exit(1)
    dmg = boss_items[item_id]
    boss['hp'] = max(0, boss['hp'] - dmg)
    log = boss.get('log', [])
    log.append({'t': int(time.time()), 'dmg': dmg, 'hp': boss['hp'], 'bk': {'item_use': dmg}, 'item': item_id})
    if len(log) > 50: log = log[-50:]
    boss['log'] = log
    if item_id in inventory: inventory.remove(item_id)
    elif item_id in equipped: equipped.remove(item_id)
    state['inventory'] = inventory
    state['equipped'] = equipped
    if boss['hp'] <= 0:
        state['active_boss'] = None
        print(f'BOOM! -{dmg} HP! {boss[\"name\"]} DEFEATED!')
    else:
        pct = boss['hp'] / boss['max_hp']
        bar_len = 12
        filled = int(pct * bar_len)
        bar = chr(9608) * filled + chr(9617) * (bar_len - filled)
        state['active_boss'] = boss
        print(f'BOOM! -{dmg} HP! {boss[\"name\"]} [{bar}] {boss[\"hp\"]}/{boss[\"max_hp\"]} HP')
    _save_state(state_file, state)
    sys.exit(0)
if item_id not in consumables:
    print('That item is not consumable. Equip it instead: peon equip ' + item_id)
    sys.exit(1)
msg, effect = consumables[item_id]
effect(state)
if item_id in inventory:
    inventory.remove(item_id)
elif item_id in equipped:
    equipped.remove(item_id)
state['inventory'] = inventory
state['equipped'] = equipped
_save_state(state_file, state)
print(msg)
"
    exit $? ;;
  sell)
    shift
    python3 -c "
import json, os, sys
state_file = '$STATE'
item_id = '${1:-}'
if not item_id:
    print('Usage: peon sell <item_id>')
    print('Run peon inventory to see item IDs')
    sys.exit(1)
$_PY_STATE_IO
state = _load_state(state_file)
inventory = state.get('inventory', [])
equipped = state.get('equipped', [])
SELL_PRICE = {'common': 10, 'uncommon': 20, 'rare': 40, 'epic': 80, 'legendary': 200}
ITEMS_R = {
    'claws_of_attack': 'common', 'gauntlets_of_str': 'common', 'ring_of_protection': 'common',
    'slippers_of_agility': 'common', 'circlet_of_nobility': 'common', 'mantle_of_intel': 'common',
    'belt_of_str': 'common', 'gloves_of_haste': 'common', 'robe_of_magi': 'common',
    'pendant_of_mana': 'common', 'boots_of_speed': 'common', 'tome_of_power': 'common',
    'skull_shield': 'common', 'kelen_dagger': 'common', 'void_stone': 'common',
    'war_axe': 'common', 'iron_shield': 'common', 'kobold_candle': 'common',
    'goblin_sapper': 'uncommon',
    'scroll_of_tp': 'uncommon', 'potion_of_healing': 'uncommon', 'potion_of_mana': 'uncommon',
    'tome_of_xp': 'uncommon', 'pendant_of_energy': 'uncommon', 'staff_of_negation': 'uncommon',
    'serrated_blade': 'uncommon', 'venom_orb': 'uncommon', 'troll_totem': 'uncommon',
    'helm_of_valor': 'rare', 'cloak_of_shadows': 'rare', 'orb_of_fire': 'rare',
    'gem_of_seeing': 'rare', 'hood_of_cunning': 'rare', 'sobi_mask': 'rare',
    'talisman_of_evasion': 'rare', 'ring_of_regen': 'rare', 'scourge_bone': 'rare',
    'shadow_orb': 'rare', 'lion_horn': 'rare', 'medallion': 'rare',
    'inv_potion': 'rare', 'periapt_of_vitality': 'rare',
    'demolisher_shot': 'rare', 'thunder_clap': 'rare',
    'bloodstone': 'rare', 'runed_gauntlets': 'rare', 'executioners_blade': 'rare',
    'ogre_scepter': 'rare', 'infernal_core': 'rare',
    'crown_of_kings': 'epic', 'mask_of_death': 'epic', 'amulet_of_spell': 'epic',
    'khadgars_pipe': 'epic', 'ankh': 'epic',
    'doom_hammer': 'epic', 'black_arrow': 'epic', 'mannoroths_blood': 'epic',
    'chain_lightning': 'epic', 'death_coil': 'epic',
    'frostmourne': 'legendary', 'wirts_leg': 'legendary', 'thunderfury': 'legendary',
    'unstoppable_force': 'legendary', 'azzinoth_blades': 'legendary', 'ashbringer': 'legendary', 'cheese': 'legendary',
    'sulfuras': 'legendary', 'crown_of_eredar': 'legendary', 'helm_of_domination': 'legendary', 'doom': 'legendary',
}
if item_id in equipped:
    print('Unequip it first: peon unequip ' + item_id)
    sys.exit(1)
if item_id not in inventory:
    print('Item not in backpack: ' + item_id)
    sys.exit(1)
r = ITEMS_R.get(item_id, 'common')
price = SELL_PRICE.get(r, 10)
inventory.remove(item_id)
econ = state.setdefault('economy', {})
econ['gold'] = econ.get('gold', 0) + price
dur = state.get('item_durability', {})
dur.pop(item_id, None)
state['inventory'] = inventory
state['item_durability'] = dur
_save_state(state_file, state)
print(f'Sold {item_id} for {price}g.')
print(f'Gold: {econ[\"gold\"]}')
"
    exit $? ;;
  raid)
    shift
    python3 -c "
import json, os, sys, time, random, datetime
state_file = '$STATE'
arg = '${1:-status}'
$_PY_STATE_IO
state = _load_state(state_file)
buildings = state.get('buildings', {})
if 'dark_portal' not in buildings:
    print('Build a Dark Portal first! (peon build dark_portal)')
    sys.exit(1)
econ = state.get('economy', {})
gold = econ.get('gold', 0)
stats = state.get('stats', {})
boss_kills = state.get('boss_kills', {})
bk_total = state.get('boss_kills_total', 0)
lvl = stats.get('level', 1)
BOSSES = {
    'kobold':      dict(name='Kobold Taskmaster',     hp=40,      days=1,  unlock_kills=0,  unlock_lvl=0, unlock_bld=[], fee=0,     loot=['common'],                       gold_r=50,    lumber_r=15,    atk_min=0, atk_max=0),
    'murloc':      dict(name='Murloc Tidecaller',     hp=120,     days=1,  unlock_kills=0,  unlock_lvl=0, unlock_bld=[], fee=0,     loot=['common','common'],                                          gold_r=100,   lumber_r=30,    atk_min=0, atk_max=0),
    'troll':       dict(name='Forest Troll Warlord',  hp=400,     days=2,  unlock_kills=1,  unlock_lvl=0, unlock_bld=[], fee=50,    loot=['uncommon','common'],                                        gold_r=200,   lumber_r=75,    atk_min=0, atk_max=1),
    'ogre':        dict(name='Ogre Magi',             hp=1600,    days=2,  unlock_kills=3,  unlock_lvl=0, unlock_bld=[], fee=200,   loot=['rare','common'],                                            gold_r=600,   lumber_r=200,   atk_min=1, atk_max=2),
    'whelps':      dict(name='Dragon Whelp Swarm',    hp=3000,    days=2,  unlock_kills=4,  unlock_lvl=0, unlock_bld=[], fee=100,   loot=['rare','uncommon','common'],                                 gold_r=800,   lumber_r=300,   atk_min=1, atk_max=4),
    'naga':        dict(name='Naga Sea Witch',        hp=6000,    days=2,  unlock_kills=5,  unlock_lvl=5, unlock_bld=[], fee=400,   loot=['rare','uncommon','uncommon'],                               gold_r=1000,  lumber_r=400,   atk_min=1, atk_max=6),
    'tichondrius': dict(name='Tichondrius',           hp=10000,   days=2,  unlock_kills=7,  unlock_lvl=6, unlock_bld=[], fee=750,   loot=['rare','rare','uncommon'],                                   gold_r=2500,  lumber_r=600,   atk_min=2, atk_max=4),
    'illidan':     dict(name='Illidan Stormrage',     hp=30000,   days=3,  unlock_kills=10, unlock_lvl=7, unlock_bld=[], fee=1500,  loot=['epic','rare','rare','uncommon'],                            gold_r=4000,  lumber_r=1200,  atk_min=3, atk_max=7),
    'mannoroth':   dict(name='Pit Lord Mannoroth',    hp=40000,   days=4,  unlock_kills=15, unlock_lvl=8, unlock_bld=['citadel'], fee=3000, loot=['epic','rare','rare','uncommon','common','common'],    gold_r=10000, lumber_r=3000,  atk_min=4, atk_max=10),
    'archimonde':  dict(name='Archimonde',            hp=100000,  days=7,  unlock_kills=20, unlock_lvl=9, unlock_bld=['citadel'], fee=5000, loot=['epic','epic','rare','rare','rare','uncommon','common'], gold_r=15000, lumber_r=5000, atk_min=4, atk_max=15),
    'lich_king':   dict(name='The Lich King',         hp=1000000, days=14, unlock_kills=30, unlock_lvl=9, unlock_bld=['citadel'], fee=10000, loot=['legendary','epic','epic'], gold_r=50000, lumber_r=15000, atk_min=5, atk_max=20),
}
TROPHY_MAP = {'kobold': 'kobold_candle', 'troll': 'troll_totem', 'ogre': 'ogre_scepter', 'tichondrius': 'infernal_core', 'mannoroth': 'mannoroths_blood', 'archimonde': 'crown_of_eredar', 'lich_king': 'helm_of_domination'}
boss = state.get('active_boss')
if boss and boss.get('deadline'):
    if datetime.date.fromisoformat(boss['deadline']) < datetime.date.today():
        fee = boss.get('entry_fee', 0)
        penalty = fee // 2
        econ['gold'] = econ.get('gold', 0) - penalty
        hist = state.get('boss_history', [])
        hist.append(dict(id=boss['id'], name=boss['name'], result='escaped', penalty=penalty, t=int(time.time())))
        if len(hist) > 30: hist = hist[-30:]
        state['boss_history'] = hist
        if boss['id'] == 'whelps' and boss.get('hp', 0) <= boss.get('max_hp', 1) * 0.2:
            state.setdefault('stats', {})['whelp_leeroy'] = True
        state['economy'] = econ
        print(f'{boss[\"name\"]} escaped! -{penalty}g penalty.')
        state['active_boss'] = None
        boss = None
        _save_state(state_file, state)
if arg == 'status':
    if boss:
        pct = boss['hp'] / boss['max_hp']
        bar_len = 20
        filled = int(pct * bar_len)
        bar = chr(9608) * filled + chr(9617) * (bar_len - filled)
        dl = boss['deadline']
        days_left = (datetime.date.fromisoformat(dl) - datetime.date.today()).days
        print(f'{boss[\"name\"]}')
        print(f'  [{bar}] {boss[\"hp\"]}/{boss[\"max_hp\"]} HP')
        print(f'  Deadline: {dl} ({days_left} day{\"s\" if days_left != 1 else \"\"} left)')
        print(f'  Damage dealt: {boss[\"max_hp\"] - boss[\"hp\"]}')
        _lt = boss.get('loot_tier', [])
        if isinstance(_lt, str): _lt = [_lt]
        if _lt: print(f'  Loot: {\", \".join(_lt)} ({len(_lt)} drop{\"s\" if len(_lt) != 1 else \"\"})')
    else:
        print('No active raid. Available bosses:')
        print()
        for bid, b in BOSSES.items():
            locked = False
            reqs = []
            if bk_total < b['unlock_kills']:
                locked = True
                reqs.append(f'{b[\"unlock_kills\"]} boss kills (have {bk_total})')
            if lvl < b['unlock_lvl']:
                locked = True
                reqs.append(f'Level {b[\"unlock_lvl\"]}+ (at {lvl})')
            for rb in b.get('unlock_bld', []):
                if rb not in buildings:
                    locked = True
                    reqs.append(f'Build {rb}')
            kills = boss_kills.get(bid, 0)
            tag = f' (defeated {kills}x)' if kills else ''
            loot_str = ', '.join(b['loot']) if len(b['loot']) > 1 else b['loot'][0]
            if locked:
                print(f'  [LOCKED] {b[\"name\"]}{tag}  \u2014 requires: {\" + \".join(reqs)}')
            else:
                fee_str = f'{b[\"fee\"]}g' if b['fee'] else 'free'
                print(f'  {bid:12s} {b[\"name\"]}{tag}  \u2014 {b[\"hp\"]} HP / {b[\"days\"]}d / entry: {fee_str} / loot: {loot_str}')
elif arg in BOSSES:
    if boss:
        print(f'Already fighting {boss[\"name\"]}! Finish or wait for deadline.')
        sys.exit(1)
    b = BOSSES[arg]
    if bk_total < b['unlock_kills']:
        print(f'Locked! Need {b[\"unlock_kills\"]} boss kills (have {bk_total}).')
        sys.exit(1)
    if lvl < b['unlock_lvl']:
        print(f'Locked! Need Level {b[\"unlock_lvl\"]}+ (at {lvl}).')
        sys.exit(1)
    for rb in b.get('unlock_bld', []):
        if rb not in buildings:
            print(f'Locked! Need to build {rb} first.')
            sys.exit(1)
    if gold < b['fee']:
        print(f'Not enough gold! Entry fee: {b[\"fee\"]}g, have {gold}g.')
        sys.exit(1)
    hp = b['hp']
    econ['gold'] = gold - b['fee']
    deadline = (datetime.date.today() + datetime.timedelta(days=b['days'])).isoformat()
    carryover = state.get('boss_carryover', 0)
    if carryover > 0:
        hp = max(1, hp - carryover)
        state['boss_carryover'] = 0
    state['active_boss'] = dict(id=arg, name=b['name'], hp=hp, max_hp=hp, deadline=deadline, spawned_at=int(time.time()), loot_tier=b['loot'], entry_fee=b['fee'], gold_reward=b['gold_r'], lumber_reward=b['lumber_r'], atk_min=b['atk_min'], atk_max=b['atk_max'])
    state['economy'] = econ
    _save_state(state_file, state)
    fee_str = f' (-{b[\"fee\"]}g)' if b['fee'] else ''
    loot_str = ', '.join(b['loot']) if len(b['loot']) > 1 else b['loot'][0]
    print(f'RAID STARTED: {b[\"name\"]}!{fee_str}')
    print(f'  HP: {hp} | Deadline: {deadline} | Loot: {loot_str} ({len(b[\"loot\"])} drop{\"s\" if len(b[\"loot\"]) != 1 else \"\"})')
    print(f'  No retreat. No surrender. Fight until victory or timeout.')
else:
    print(f'Unknown boss tier: {arg}')
    print('Available: ' + ', '.join(BOSSES.keys()))
    sys.exit(1)
"
    exit $? ;;
  army)
    python3 -c "
import json, os, sys, time
state_file = '$STATE'
$_PY_STATE_IO
state = _load_state(state_file)
buildings = state.get('buildings', {})
if 'barracks' not in buildings:
    print('Build Barracks first! (peon build barracks)')
    sys.exit(1)
econ = state.get('economy', {})
gold = econ.get('gold', 0)
lumber = econ.get('lumber', 0)
army = state.get('army', {})
UNITS = {
    'grunt':   dict(name='Grunt',          gold=100,  lumber=0,   food=2, boss_dmg=1,  armor=0,  heal=0, hp=30,  desc='Infantry. 30 HP. +1 raid damage.'),
    'raider':  dict(name='Raider',         gold=400,  lumber=100, food=3, boss_dmg=4,  armor=0,  heal=0, hp=50,  desc='Wolf rider. 50 HP. +4 raid damage.'),
    'tauren':  dict(name='Tauren Warrior', gold=1000, lumber=400, food=5, boss_dmg=10, armor=0,  heal=0, hp=80,  desc='Elite tank. 80 HP. +10 raid damage.'),
    'shaman':  dict(name='Shaman',         gold=300,  lumber=100, food=2, boss_dmg=0,  armor=25, heal=3, hp=20,  desc='Healer. 20 HP. Heals 1-3 HP/turn. 25% counter reduction.'),
}
for _uk in list(army.keys()):
    if isinstance(army[_uk], int): army[_uk] = [UNITS.get(_uk, {}).get('hp', 3)] * army[_uk]
food_cap = 12
if 'fortress' in buildings:
    food_cap += 8
if 'citadel' in buildings:
    food_cap += 10
food_cap += buildings.get('farm', {}).get('count', 0) * 5
food_used = sum(UNITS[uid]['food'] * len(hps) for uid, hps in army.items() if uid in UNITS)
total_dmg = sum(UNITS[uid]['boss_dmg'] * len(hps) for uid, hps in army.items() if uid in UNITS)
total_armor = min(50, sum(UNITS[uid]['armor'] * len(hps) for uid, hps in army.items() if uid in UNITS))
total_heal = sum(UNITS[uid]['heal'] * len(hps) for uid, hps in army.items() if uid in UNITS)
total_units = sum(len(v) for v in army.values())
upkeep_gold = sum(UNITS[uid]['gold'] // 10 * len(hps) for uid, hps in army.items() if uid in UNITS)
if 'goblin_lab' in buildings:
    upkeep_gold //= 2
print(f'=== Army ===')
print(f'Food: {food_used}/{food_cap} | Units: {total_units} | Daily upkeep: {upkeep_gold}g')
print(f'Army stats: +{total_dmg} raid damage | -{total_armor}% counter-attack gold | {total_heal} HP heal/turn')
print()
if not army:
    print('  No units hired. Use: peon hire <unit>')
else:
    for uid, hps in army.items():
        u = UNITS.get(uid)
        if u:
            cnt = len(hps)
            mx = u['hp']
            wounded = sum(1 for h in hps if h < mx)
            hp_str = f'{sum(hps)}/{mx * cnt} HP'
            if wounded:
                hp_str += f' ({wounded} wounded)'
            print(f'  {cnt}x {u[\"name\"]:16s} {hp_str:24s} +{u[\"boss_dmg\"] * cnt} dmg, {u[\"food\"] * cnt} food')
print()
print(f'Gold: {gold} | Lumber: {lumber}')
print()
print('Available units (peon hire <unit>):')
for uid, u in UNITS.items():
    cost_str = f'{u[\"gold\"]}g'
    if u['lumber'] > 0:
        cost_str += f'/{u[\"lumber\"]}l'
    print(f'  {uid:14s} {u[\"name\"]:16s} {cost_str:10s} {u[\"food\"]} food  {u[\"hp\"]} HP  {u[\"desc\"]}')
"
    exit $? ;;
  hire)
    shift
    python3 -c "
import json, os, sys, time
state_file = '$STATE'
unit_id = '${1:-}'
count_str = '${2:-1}'
$_PY_STATE_IO
state = _load_state(state_file)
buildings = state.get('buildings', {})
if 'barracks' not in buildings:
    print('Build Barracks first! (peon build barracks)')
    sys.exit(1)
if not unit_id:
    print('Usage: peon hire <unit> [count]')
    print('See available units: peon army')
    sys.exit(1)
UNITS = {
    'grunt':   dict(name='Grunt',          gold=100,  lumber=0,   food=2, boss_dmg=1,  armor=0,  heal=0, hp=30),
    'raider':  dict(name='Raider',         gold=400,  lumber=100, food=3, boss_dmg=4,  armor=0,  heal=0, hp=50),
    'tauren':  dict(name='Tauren Warrior', gold=1000, lumber=400, food=5, boss_dmg=10, armor=0,  heal=0, hp=80),
    'shaman':  dict(name='Shaman',         gold=300,  lumber=100, food=2, boss_dmg=0,  armor=25, heal=3, hp=20),
}
unit_id = unit_id.lower().replace('-', '_')
if unit_id not in UNITS:
    print(f'Unknown unit: {unit_id}')
    print('Available: ' + ', '.join(UNITS.keys()))
    sys.exit(1)
try:
    count = max(1, int(count_str))
except ValueError:
    count = 1
u = UNITS[unit_id]
total_gold = u['gold'] * count
total_lumber = u['lumber'] * count
econ = state.get('economy', {})
gold = econ.get('gold', 0)
lumber = econ.get('lumber', 0)
if gold < total_gold or lumber < total_lumber:
    print(f'Not enough resources! Need {total_gold}g/{total_lumber}l, have {gold}g/{lumber}l')
    sys.exit(1)
army = state.get('army', {})
for _uk in list(army.keys()):
    if isinstance(army[_uk], int): army[_uk] = [UNITS.get(_uk, {}).get('hp', 3)] * army[_uk]
food_cap = 12
if 'fortress' in buildings:
    food_cap += 8
if 'citadel' in buildings:
    food_cap += 10
food_cap += buildings.get('farm', {}).get('count', 0) * 5
food_used = sum(UNITS[uid]['food'] * len(hps) for uid, hps in army.items() if uid in UNITS)
food_needed = u['food'] * count
if food_used + food_needed > food_cap:
    can_hire = (food_cap - food_used) // u['food']
    print(f'Not enough food! {food_used}/{food_cap} used, need {food_needed} more.')
    if can_hire > 0:
        print(f'Can hire up to {can_hire} {u[\"name\"]}(s).')
    else:
        print('Dismiss units to free food, or build Fortress/Citadel for more capacity.')
    sys.exit(1)
econ['gold'] = gold - total_gold
econ['lumber'] = lumber - total_lumber
existing = army.get(unit_id, [])
existing.extend([u['hp']] * count)
army[unit_id] = existing
state['army'] = army
state['economy'] = econ
stats = state.get('stats', {})
stats['units_hired_total'] = stats.get('units_hired_total', 0) + count
state['stats'] = stats
_save_state(state_file, state)
cost_str = f'-{total_gold}g'
if total_lumber > 0:
    cost_str += f'/-{total_lumber}l'
print(f'Hired {count}x {u[\"name\"]}! ({cost_str})')
print(f'Army food: {food_used + food_needed}/{food_cap}')
"
    exit $? ;;
  dismiss)
    shift
    python3 -c "
import json, os, sys, time
state_file = '$STATE'
unit_id = '${1:-}'
count_str = '${2:-1}'
$_PY_STATE_IO
state = _load_state(state_file)
if not unit_id:
    print('Usage: peon dismiss <unit> [count]')
    sys.exit(1)
UNITS = {
    'grunt':   dict(name='Grunt'),
    'raider':  dict(name='Raider'),
    'tauren':  dict(name='Tauren Warrior'),
    'shaman':  dict(name='Shaman'),
}
unit_id = unit_id.lower().replace('-', '_')
if unit_id not in UNITS:
    print(f'Unknown unit: {unit_id}')
    sys.exit(1)
army = state.get('army', {})
_UNIT_HP = dict(grunt=30, raider=50, tauren=80, shaman=20)
for _uk in list(army.keys()):
    if isinstance(army[_uk], int): army[_uk] = [_UNIT_HP.get(_uk, 30)] * army[_uk]
current = len(army.get(unit_id, []))
if current == 0:
    print(f'No {UNITS[unit_id][\"name\"]}s in your army.')
    sys.exit(1)
try:
    count = min(current, max(1, int(count_str)))
except ValueError:
    count = 1
army[unit_id] = army[unit_id][:-count] if count < current else []
if not army[unit_id]:
    del army[unit_id]
state['army'] = army
_save_state(state_file, state)
print(f'Dismissed {count}x {UNITS[unit_id][\"name\"]}.')
remaining = len(army.get(unit_id, []))
if remaining > 0:
    print(f'{remaining} remaining.')
"
    exit $? ;;
  dashboard)
    _port=${PEON_DASHBOARD_PORT:-19997}
    _pid_file="$PEON_DIR/.dashboard.pid"
    _running=false
    if [ -f "$_pid_file" ]; then
      _dpid=$(cat "$_pid_file" 2>/dev/null)
      [ -n "$_dpid" ] && kill -0 "$_dpid" 2>/dev/null && _running=true
    fi
    if [ "$_running" = false ]; then
      if [ -f "$PEON_DIR/dashboard.html" ]; then
        echo "Starting dashboard server on port $_port..."
        nohup python3 -c "
import http.server, json, os, socketserver, time, datetime, tempfile, shutil
PORT = $_port
PEON_DIR = '$PEON_DIR'
BCOSTS = {'burrow':(500,250),'watch_tower':(750,375),'war_mill':(1000,500),'altar':(1500,750),'lumber_mill':(1500,500),'tavern':(2000,1000),'stronghold':(2500,1000),'spirit_lodge':(2500,1000),'barracks':(3000,1200),'blacksmith':(4000,1500),'arcane_sanctum':(7500,3000),'fortress':(10000,4000),'dark_portal':(12000,5000),'citadel':(15000,6000),'farm':(8000,3000),'goblin_lab':(18000,7000),'world_tree':(25000,10000)}
FARM_MAX = 3
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _json(self, code, data):
        self.send_response(code)
        self.send_header('Content-Type','application/json')
        self.send_header('Access-Control-Allow-Origin','*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    def _load(self, f):
        p = os.path.join(PEON_DIR, f)
        for fp in (p, p + '.bak'):
            try:
                d = json.load(open(fp))
                if isinstance(d, dict): return d
            except Exception: pass
        return {}
    def _save(self, f, d):
        p = os.path.join(PEON_DIR, f)
        dn = os.path.dirname(p) or '.'
        os.makedirs(dn, exist_ok=True)
        if os.path.isfile(p):
            try: shutil.copy2(p, p + '.bak')
            except Exception: pass
        fd, t = tempfile.mkstemp(dir=dn, suffix='.tmp')
        try:
            with os.fdopen(fd, 'w') as fh:
                json.dump(d, fh, indent=2)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(t, p)
        except Exception:
            try: os.unlink(t)
            except Exception: pass
            raise
    def do_GET(self):
        if self.path == '/api/state':
            self._json(200, self._load('.state.json'))
        elif self.path == '/api/config':
            self._json(200, self._load('config.json'))
        elif self.path == '/api/packs':
            pdir = os.path.join(PEON_DIR, 'packs')
            packs = []
            if os.path.isdir(pdir):
                for d in sorted(os.listdir(pdir)):
                    dp = os.path.join(pdir, d)
                    if os.path.isdir(dp) and (os.path.exists(os.path.join(dp,'openpeon.json')) or os.path.exists(os.path.join(dp,'manifest.json'))):
                        packs.append(d)
            self._json(200, packs)
        elif self.path in ('/','/dashboard'):
            self.send_response(200)
            self.send_header('Content-Type','text/html')
            self.end_headers()
            try: data = open(os.path.join(PEON_DIR,'dashboard.html')).read()
            except: data = '<h1>Not found</h1>'
            self.wfile.write(data.encode())
        elif self.path == '/raid':
            self.send_response(200)
            self.send_header('Content-Type','text/html')
            self.end_headers()
            try: data = open(os.path.join(PEON_DIR,'raid.html')).read()
            except: data = '<h1>Raid page not found</h1>'
            self.wfile.write(data.encode())
        elif self.path == '/army':
            self.send_response(200)
            self.send_header('Content-Type','text/html')
            self.end_headers()
            try: data = open(os.path.join(PEON_DIR,'army.html')).read()
            except: data = '<h1>Army page not found</h1>'
            self.wfile.write(data.encode())
        elif self.path.startswith('/assets/') and '..' not in self.path:
            fp = os.path.join(PEON_DIR, self.path.lstrip('/'))
            if os.path.isfile(fp):
                ext = os.path.splitext(fp)[1].lower()
                ct = {'.png':'image/png','.jpg':'image/jpeg','.gif':'image/gif','.svg':'image/svg+xml','.webp':'image/webp'}.get(ext,'application/octet-stream')
                self.send_response(200)
                self.send_header('Content-Type', ct)
                self.send_header('Cache-Control','public, max-age=86400')
                self.end_headers()
                with open(fp,'rb') as f: self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin','*')
        self.send_header('Access-Control-Allow-Methods','GET,POST,OPTIONS')
        self.send_header('Access-Control-Allow-Headers','Content-Type')
        self.end_headers()
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(n)) if n else {}
        if self.path == '/api/raid':
            import random as _rr
            bid = body.get('boss', '')
            st = self._load('.state.json')
            BOSSES = {'kobold': dict(hp=40,days=1,unlock_kills=0,unlock_lvl=0,unlock_bld=[],fee=0,loot=['common'],gold_r=50,lumber_r=15,atk_min=0,atk_max=0,name='Kobold Taskmaster'), 'murloc': dict(hp=120,days=1,unlock_kills=0,unlock_lvl=0,unlock_bld=[],fee=0,loot=['common','common'],gold_r=100,lumber_r=30,atk_min=0,atk_max=0,name='Murloc Tidecaller'), 'troll': dict(hp=400,days=2,unlock_kills=1,unlock_lvl=0,unlock_bld=[],fee=50,loot=['uncommon','common'],gold_r=200,lumber_r=75,atk_min=0,atk_max=1,name='Forest Troll Warlord'), 'ogre': dict(hp=1600,days=2,unlock_kills=3,unlock_lvl=0,unlock_bld=[],fee=200,loot=['rare','common'],gold_r=600,lumber_r=200,atk_min=1,atk_max=2,name='Ogre Magi'), 'whelps': dict(hp=3000,days=2,unlock_kills=4,unlock_lvl=0,unlock_bld=[],fee=100,loot=['rare','uncommon','common'],gold_r=800,lumber_r=300,atk_min=1,atk_max=4,name='Dragon Whelp Swarm'), 'naga': dict(hp=6000,days=2,unlock_kills=5,unlock_lvl=5,unlock_bld=[],fee=400,loot=['rare','uncommon','uncommon'],gold_r=1000,lumber_r=400,atk_min=1,atk_max=6,name='Naga Sea Witch'), 'tichondrius': dict(hp=10000,days=2,unlock_kills=7,unlock_lvl=6,unlock_bld=[],fee=750,loot=['rare','rare','uncommon'],gold_r=2500,lumber_r=600,atk_min=2,atk_max=4,name='Tichondrius'), 'illidan': dict(hp=30000,days=3,unlock_kills=10,unlock_lvl=7,unlock_bld=[],fee=1500,loot=['epic','rare','rare','uncommon'],gold_r=4000,lumber_r=1200,atk_min=3,atk_max=7,name='Illidan Stormrage'), 'mannoroth': dict(hp=40000,days=4,unlock_kills=15,unlock_lvl=8,unlock_bld=['citadel'],fee=3000,loot=['epic','rare','rare','uncommon','common','common'],gold_r=10000,lumber_r=3000,atk_min=4,atk_max=10,name='Pit Lord Mannoroth'), 'archimonde': dict(hp=100000,days=7,unlock_kills=20,unlock_lvl=9,unlock_bld=['citadel'],fee=5000,loot=['epic','epic','rare','rare','rare','uncommon','common'],gold_r=15000,lumber_r=5000,atk_min=4,atk_max=15,name='Archimonde'), 'lich_king': dict(hp=1000000,days=14,unlock_kills=30,unlock_lvl=9,unlock_bld=['citadel'],fee=10000,loot=['legendary','epic','epic'],gold_r=50000,lumber_r=15000,atk_min=5,atk_max=20,name='The Lich King')}
            if st.get('active_boss'):
                return self._json(400, {'error': 'Already in a raid'})
            if 'dark_portal' not in st.get('buildings', {}):
                return self._json(400, {'error': 'Build Dark Portal first'})
            if bid not in BOSSES:
                return self._json(400, {'error': 'Unknown boss'})
            b = BOSSES[bid]
            bk = st.get('boss_kills_total', 0)
            lvl = st.get('stats', {}).get('level', 1)
            if bk < b['unlock_kills'] or lvl < b['unlock_lvl']:
                return self._json(400, {'error': 'Boss locked'})
            for rb in b.get('unlock_bld', []):
                if rb not in st.get('buildings', {}):
                    return self._json(400, {'error': f'Need {rb}'})
            ec = st.setdefault('economy', {})
            g = ec.get('gold', 0)
            if g < b['fee']:
                return self._json(400, {'error': f'Need {b[\"fee\"]}g'})
            ec['gold'] = g - b['fee']
            hp = b['hp']
            co = st.get('boss_carryover', 0)
            if co > 0:
                hp = max(1, hp - co)
                st['boss_carryover'] = 0
            dl = (datetime.date.today() + datetime.timedelta(days=b['days'])).isoformat()
            st['active_boss'] = dict(id=bid, name=b['name'], hp=hp, max_hp=hp, deadline=dl, spawned_at=int(time.time()), loot_tier=b['loot'], entry_fee=b['fee'], gold_reward=b['gold_r'], lumber_reward=b['lumber_r'], atk_min=b['atk_min'], atk_max=b['atk_max'])
            st['economy'] = ec
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'boss': st['active_boss'], 'gold': ec['gold']})
        elif self.path == '/api/build':
            bname = body.get('building', '')
            if bname not in BCOSTS:
                return self._json(400, {'error': 'Unknown building'})
            st = self._load('.state.json')
            blds = st.get('buildings', {})
            if bname == 'farm':
                cur = blds.get('farm', {}).get('count', 0) if 'farm' in blds else 0
                if cur >= FARM_MAX:
                    return self._json(400, {'error': 'Farm limit reached'})
            elif bname in blds:
                return self._json(400, {'error': 'Already built'})
            ec = st.get('economy', {})
            g, l = ec.get('gold', 0), ec.get('lumber', 0)
            gc, lc = BCOSTS[bname]
            if st.get('goblin_discount_date', '') == datetime.date.today().isoformat():
                gc //= 2; lc //= 2
            if g < gc or l < lc:
                return self._json(400, {'error': 'Insufficient resources', 'need_gold': gc, 'need_lumber': lc})
            ec['gold'] = g - gc; ec['lumber'] = l - lc
            if bname == 'farm':
                prev = blds.get('farm', {})
                cnt = prev.get('count', 0) + 1
                bld = {'built_at': int(time.time()), 'count': cnt}
                if 'x' in body and 'y' in body: bld['pos'] = [body['x'], body['y']]
                elif 'pos' in prev: bld['pos'] = prev['pos']
            else:
                bld = {'built_at': int(time.time())}
                if 'x' in body and 'y' in body: bld['pos'] = [body['x'], body['y']]
            st.setdefault('buildings', {})[bname] = bld
            st['economy'] = ec
            st.setdefault('stats', {})['buildings_built'] = len(st['buildings'])
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'building': bname, 'gold': ec['gold'], 'lumber': ec['lumber']})
        elif self.path == '/api/bunker':
            st = self._load('.state.json')
            if 'burrow' not in st.get('buildings', {}):
                return self._json(400, {'error': 'Build a Burrow first'})
            now = time.time()
            if st.get('bunker_until', 0) > now:
                return self._json(200, {'active': True, 'minutes_left': int((st['bunker_until'] - now) / 60)})
            st['bunker_until'] = now + 3600
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'bunker_until': st['bunker_until']})
        elif self.path == '/api/config':
            cfg = self._load('config.json')
            for k in ('enabled','volume','active_pack','desktop_notifications'):
                if k in body: cfg[k] = body[k]
            self._save('config.json', cfg)
            self._json(200, {'ok': True})
        elif self.path == '/api/surrender':
            st = self._load('.state.json')
            boss = st.get('active_boss')
            if not boss:
                return self._json(400, {'error': 'No active raid'})
            fee = boss.get('entry_fee', 0)
            penalty = fee // 2
            ec = st.setdefault('economy', {})
            ec['gold'] = ec.get('gold', 0) - penalty
            hist = st.get('boss_history', [])
            hist.append(dict(id=boss['id'], name=boss['name'], result='escaped', penalty=penalty, t=int(time.time())))
            if len(hist) > 30: hist = hist[-30:]
            st['boss_history'] = hist
            if boss['id'] == 'whelps' and boss.get('hp', 0) <= boss.get('max_hp', 1) * 0.2:
                st.setdefault('stats', {})['whelp_leeroy'] = True
            st['economy'] = ec
            st['active_boss'] = None
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'penalty': penalty})
        elif self.path == '/api/resurrect':
            st = self._load('.state.json')
            if 'altar' not in st.get('buildings', {}):
                return self._json(400, {'error': 'Build an Altar first'})
            today = datetime.date.today().isoformat()
            if st.get('last_resurrect_date') == today:
                return self._json(400, {'error': 'Already used today'})
            best = st.get('stats', {}).get('max_combo', 0)
            st['combo_count'] = max(st.get('combo_count', 0), best // 2)
            st['last_resurrect_date'] = today
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'combo': st['combo_count']})
        elif self.path == '/api/rest':
            st = self._load('.state.json')
            f = st.get('fatigue', 0)
            if f == 0:
                return self._json(200, {'ok': True, 'msg': 'Not tired'})
            ec = st.setdefault('economy', {})
            l = ec.get('lumber', 0)
            if l < 20:
                return self._json(400, {'error': 'Need 20 lumber', 'have': l})
            ec['lumber'] = l - 20
            st['fatigue'] = 0
            st['economy'] = ec
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'lumber': ec['lumber']})
        elif self.path == '/api/repair':
            st = self._load('.state.json')
            eq = st.get('equipped', [])
            dur = st.get('item_durability', {})
            ec = st.setdefault('economy', {})
            MAXD = {'common':50,'uncommon':75,'rare':100,'epic':150,'legendary':200}
            cost = body.get('cost', 0)
            items = body.get('items', [])
            if not items:
                return self._json(200, {'ok': True, 'msg': 'Nothing to repair'})
            g = ec.get('gold', 0)
            if g < cost:
                return self._json(400, {'error': 'Need ' + str(cost) + 'g', 'have': g})
            ec['gold'] = g - cost
            for e in items:
                r = body.get('rarities', {}).get(e, 'common')
                dur[e] = MAXD.get(r, 50)
            st['item_durability'] = dur
            st['economy'] = ec
            stats = st.setdefault('stats', {})
            stats['repairs_total'] = stats.get('repairs_total', 0) + len(items)
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'repaired': len(items), 'cost': cost, 'gold': ec['gold']})
        elif self.path == '/api/harvest':
            pos = body.get('pos', '')
            st = self._load('.state.json')
            ec = st.setdefault('economy', {})
            found = False
            for key in ('lumber_nodes', 'gold_nodes'):
                nodes = st.get(key, [])
                for i, n in enumerate(nodes):
                    if n.get('pos') == pos:
                        res = 'lumber' if 'lumber' in key else 'gold'
                        ec[res] = ec.get(res, 0) + n['amt']
                        nodes.pop(i)
                        st[key] = nodes
                        self._save('.state.json', st)
                        return self._json(200, {'ok': True, 'resource': res, 'amount': n['amt']})
            self._json(400, {'error': 'No harvestable node at that position'})
        elif self.path == '/api/equip':
            iid = body.get('item', '')
            st = self._load('.state.json')
            inv = st.get('inventory', [])
            eq = st.get('equipped', [])
            if iid not in inv:
                return self._json(400, {'error': 'Item not in backpack'})
            if len(eq) >= 6:
                return self._json(400, {'error': 'Equipment full (6/6)'})
            inv.remove(iid)
            eq.append(iid)
            st['inventory'] = inv; st['equipped'] = eq
            self._save('.state.json', st)
            self._json(200, {'ok': True})
        elif self.path == '/api/unequip':
            iid = body.get('item', '')
            st = self._load('.state.json')
            inv = st.get('inventory', [])
            eq = st.get('equipped', [])
            if iid not in eq:
                return self._json(400, {'error': 'Item not equipped'})
            eq.remove(iid)
            inv.append(iid)
            st['inventory'] = inv; st['equipped'] = eq
            self._save('.state.json', st)
            self._json(200, {'ok': True})
        elif self.path == '/api/use':
            iid = body.get('item', '')
            st = self._load('.state.json')
            inv = st.get('inventory', [])
            eq = st.get('equipped', [])
            if iid not in inv and iid not in eq:
                return self._json(400, {'error': 'Item not found'})
            ec = st.setdefault('economy', {})
            boss_items = {'firebolt':50,'goblin_sapper':100,'storm_bolt':250,'demolisher_shot':500,'thunder_clap':750,'chain_lightning':2000,'death_coil':5000,'finger_of_death':10000,'doom':40000}
            if iid in boss_items:
                boss = st.get('active_boss')
                if not boss or boss.get('hp', 0) <= 0:
                    return self._json(400, {'error': 'No active boss'})
                dmg = boss_items[iid]
                boss['hp'] = max(0, boss['hp'] - dmg)
                log = boss.get('log', [])
                log.append({'t': int(time.time()), 'dmg': dmg, 'hp': boss['hp'], 'bk': {'item_use': dmg}, 'item': iid})
                if len(log) > 50: log = log[-50:]
                boss['log'] = log
                if iid in inv: inv.remove(iid)
                elif iid in eq: eq.remove(iid)
                st['inventory'] = inv; st['equipped'] = eq
                if boss['hp'] <= 0:
                    st['active_boss'] = None
                else:
                    st['active_boss'] = boss
                self._save('.state.json', st)
                self._json(200, {'ok': True, 'dmg': dmg, 'hp': boss['hp'], 'killed': boss['hp'] <= 0})
                return
            def _dash_heal(state, amount):
                army = state.get('army', {})
                if not army: return
                _UNIT_HP = {'grunt': 30, 'raider': 50, 'tauren': 80, 'shaman': 20}
                for uid, hps in army.items():
                    mx = _UNIT_HP.get(uid, 30)
                    for i in range(len(hps)): hps[i] = min(mx, hps[i] + amount)
                state['army'] = army

            cons = {
                'scroll_of_tp':      lambda: st.update(combo_count=max(st.get('combo_count',0), st.get('stats',{}).get('max_combo',0)//2)),
                'potion_of_healing':  lambda: ec.update(gold=ec.get('gold',0)+200),
                'potion_of_mana':     lambda: ec.update(lumber=ec.get('lumber',0)+50),
                'tome_of_xp':        lambda: ec.update(gold=ec.get('gold',0)+500),
                'liquid_fire':        lambda: ec.update(gold=ec.get('gold',0)+150),
                'inv_potion':         lambda: ec.update(gold=ec.get('gold',0)+1500),
                'invuln_potion':      lambda: (ec.update(gold=ec.get('gold',0)+3000), ec.update(lumber=ec.get('lumber',0)+1000)),
                'ankh':               lambda: ec.update(gold=ec.get('gold',0)+5000),
                'ensnare_trap':       lambda: _dash_heal(st, 50),
                'scroll_of_heal':     lambda: _dash_heal(st, 15),
                'healing_ward':       lambda: _dash_heal(st, 999),
                'cheese':             lambda: (ec.update(gold=ec.get('gold',0)+10000), ec.update(lumber=ec.get('lumber',0)+5000)),
            }
            if iid not in cons:
                return self._json(400, {'error': 'Not consumable'})
            cons[iid]()
            if iid in inv: inv.remove(iid)
            elif iid in eq: eq.remove(iid)
            st['inventory'] = inv; st['equipped'] = eq
            self._save('.state.json', st)
            self._json(200, {'ok': True})
        elif self.path == '/api/sell':
            iid = body.get('item', '')
            st = self._load('.state.json')
            inv = st.get('inventory', [])
            if iid not in inv:
                eq = st.get('equipped', [])
                if iid in eq:
                    return self._json(400, {'error': 'Unequip it first'})
                return self._json(400, {'error': 'Item not in backpack'})
            SELL_PRICE = {'common': 10, 'uncommon': 20, 'rare': 40, 'epic': 80, 'legendary': 200}
            r = body.get('rarity', 'common')
            price = SELL_PRICE.get(r, 10)
            inv.remove(iid)
            ec = st.setdefault('economy', {})
            ec['gold'] = ec.get('gold', 0) + price
            dur = st.get('item_durability', {})
            dur.pop(iid, None)
            st['inventory'] = inv
            st['item_durability'] = dur
            st['economy'] = ec
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'price': price, 'gold': ec['gold']})
        elif self.path == '/api/hire':
            uid = body.get('unit', '')
            cnt = max(1, int(body.get('count', 1)))
            UNITS = {'grunt':(100,0,2,30),'raider':(400,100,3,50),'tauren':(1000,400,5,80),'shaman':(300,100,2,20)}
            if uid not in UNITS:
                return self._json(400, {'error': 'Unknown unit'})
            st = self._load('.state.json')
            if 'barracks' not in st.get('buildings', {}):
                return self._json(400, {'error': 'Build Barracks first'})
            ug, ul, uf, uhp = UNITS[uid]
            ec = st.setdefault('economy', {})
            g, l = ec.get('gold', 0), ec.get('lumber', 0)
            tg, tl = ug * cnt, ul * cnt
            if g < tg or l < tl:
                return self._json(400, {'error': f'Need {tg}g/{tl}l'})
            army = st.get('army', {})
            _UHP = dict(grunt=30,raider=50,tauren=80,shaman=20)
            for _uk in list(army.keys()):
                if isinstance(army[_uk], int): army[_uk] = [_UHP.get(_uk, 3)] * army[_uk]
            bld = st.get('buildings', {})
            fc = 12 + (8 if 'fortress' in bld else 0) + (10 if 'citadel' in bld else 0)
            fu = sum(UNITS.get(u, (0,0,0,0))[2] * len(hps) for u, hps in army.items())
            if fu + uf * cnt > fc:
                return self._json(400, {'error': 'Not enough food'})
            ec['gold'] = g - tg
            ec['lumber'] = l - tl
            existing = army.get(uid, [])
            existing.extend([uhp] * cnt)
            army[uid] = existing
            st['army'] = army
            st['economy'] = ec
            sts = st.setdefault('stats', {})
            sts['units_hired_total'] = sts.get('units_hired_total', 0) + cnt
            st['stats'] = sts
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'army': army, 'gold': ec['gold'], 'lumber': ec['lumber']})
        elif self.path == '/api/dismiss':
            uid = body.get('unit', '')
            cnt = max(1, int(body.get('count', 1)))
            st = self._load('.state.json')
            army = st.get('army', {})
            _UHP = dict(grunt=30,raider=50,tauren=80,shaman=20)
            for _uk in list(army.keys()):
                if isinstance(army[_uk], int): army[_uk] = [_UHP.get(_uk, 3)] * army[_uk]
            cur = len(army.get(uid, []))
            if cur <= 0:
                return self._json(400, {'error': 'No such unit in army'})
            army[uid] = army[uid][:-cnt] if cnt < cur else []
            if not army[uid]:
                army.pop(uid, None)
            st['army'] = army
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'army': army})
        else:
            self._json(404, {'error': 'Not found'})
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('127.0.0.1',PORT),H) as s:
    s.serve_forever()
" >/dev/null 2>&1 &
        echo $! > "$_pid_file"
        sleep 0.5
      else
        echo "Dashboard HTML not found. Run 'peon update' to install." >&2
        exit 1
      fi
    fi
    echo "Dashboard running at http://localhost:$_port"
    case "$(uname -s)" in
      Darwin) open "http://localhost:$_port" ;;
      Linux)
        if command -v xdg-open &>/dev/null; then
          xdg-open "http://localhost:$_port" &>/dev/null &
        else
          echo "Open http://localhost:$_port in your browser"
        fi ;;
    esac
    exit 0 ;;
  help|--help|-h)
    cat <<'HELPEOF'
Usage: peon <command>

Commands:
  pause                Mute sounds
  resume               Unmute sounds
  toggle               Toggle mute on/off
  status               Check if paused or active
  volume [0.0-1.0]     Get or set volume level
  rotation [mode]      Get or set pack rotation mode (random|round-robin|agentskill)
  notifications on        Enable desktop notifications
  notifications off       Disable desktop notifications
  notifications overlay   Use large overlay banners (default)
  notifications standard  Use standard system notifications
  notifications test      Send a test notification
  preview [category]   Play all sounds from a category (default: session.start)
  preview --list       List all categories and sound counts in the active pack
                       Categories: session.start, task.acknowledge, task.complete,
                       task.error, input.required, resource.limit, user.spam
  update               Update peon-ping and refresh all sound packs
  help                 Show this help

WC3 Metagame:
  economy              Show gold, lumber, and upkeep status
  achievements         Show unlocked and locked achievements
  build [list|<name>]  List or build structures (costs gold + lumber)
  inventory            View items in backpack and equipped slots
  equip <item>         Equip an item from backpack (6 slots max)
  unequip <item>       Move equipped item back to backpack
  use <item>           Use a consumable item (scrolls, potions, tomes)
  sell <item>          Sell an item from backpack for gold
  raid [status|<boss>] Start or check boss raids (requires Dark Portal)
  army                 Show your army composition and stats
  hire <unit> [count]  Hire units for your army (requires Barracks)
  dismiss <unit> [n]   Dismiss units from your army
  bunker               Pause fatigue for 1 hour (requires Burrow)
  resurrect            Restore combo streak (requires Altar, once/day)
  taunt                Play a random taunt (requires Tavern)
  dashboard            Open the WC3 base dashboard in your browser

Pack management:
  packs list              List installed sound packs
  packs list --registry   List all available packs from registry
  packs install <p1,p2>   Download and install new packs
  packs install --all     Download all packs from registry
  packs use <name>        Switch to a specific pack
  packs use --install <n> Switch to pack, installing from registry if needed
  packs next              Cycle to the next pack
  packs remove <p1,p2>    Remove specific packs
  packs remove --all      Remove all packs except the active one

Mobile notifications:
  mobile ntfy <topic>      Set up ntfy.sh push notifications
  mobile pushover          Set up Pushover push notifications
  mobile telegram          Set up Telegram bot notifications
  mobile on                Re-enable mobile notifications (after off)
  mobile off               Disable mobile notifications
  mobile status            Show mobile config
  mobile test              Send a test notification

Trainer (exercise reminders):
  trainer on           Enable trainer mode
  trainer off          Disable trainer mode
  trainer status       Show today's progress
  trainer log <n> <ex> Log completed reps (e.g. log 25 pushups)
  trainer goal <n>     Set daily goal for all exercises
  trainer goal <ex> <n> Set daily goal for one exercise
  trainer help         Show trainer help

Relay (SSH/devcontainer/Codespaces):
  relay [--port=N]        Start audio relay on your local machine
  relay --bind=<addr>     Bind relay to a specific address (default: 127.0.0.1)
  relay --daemon          Start relay in background
  relay --stop            Stop background relay
  relay --status          Check if relay is running
HELPEOF
    exit 0 ;;
  trainer)
    shift
    case "${1:-help}" in
      on)
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
trainer = cfg.get('trainer', {})
trainer['enabled'] = True
if 'exercises' not in trainer:
    trainer['exercises'] = {'pushups': 300, 'squats': 300}
if 'reminder_interval_minutes' not in trainer:
    trainer['reminder_interval_minutes'] = 20
if 'reminder_min_gap_minutes' not in trainer:
    trainer['reminder_min_gap_minutes'] = 5
cfg['trainer'] = trainer
json.dump(cfg, open(config_path, 'w'), indent=2)
"
        echo "peon-ping: trainer enabled"
        exit 0 ;;
      off)
        python3 -c "
import json
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}
trainer = cfg.get('trainer', {})
trainer['enabled'] = False
cfg['trainer'] = trainer
json.dump(cfg, open(config_path, 'w'), indent=2)
"
        echo "peon-ping: trainer disabled"
        exit 0 ;;
      status)
        python3 -c "
import json, datetime, sys

config_path = '$CONFIG'
state_path = '$STATE'

try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}

trainer_cfg = cfg.get('trainer', {})
if not trainer_cfg.get('enabled', False):
    print('peon-ping: trainer not enabled')
    print('Run \"peon trainer on\" to enable.')
    sys.exit(0)

exercises = trainer_cfg.get('exercises', {'pushups': 300, 'squats': 300})

$_PY_STATE_IO
state = _load_state(state_path)

trainer_state = state.get('trainer', {})
today = datetime.date.today().isoformat()

# Auto-reset if date changed
if trainer_state.get('date', '') != today:
    trainer_state = {'date': today, 'reps': {k: 0 for k in exercises}, 'last_reminder_ts': 0}
    state['trainer'] = trainer_state
    _save_state(state_path, state, indent=2)

reps = trainer_state.get('reps', {})

print('peon-ping: trainer status (' + today + ')')
print('')

bar_width = 16
for ex, goal in exercises.items():
    done = reps.get(ex, 0)
    pct = min(done / goal, 1.0) if goal > 0 else 0
    filled = int(pct * bar_width)
    empty = bar_width - filled
    bar = '\u2588' * filled + '\u2591' * empty
    pct_str = str(int(pct * 100))
    print(f'{ex}:  {bar}  {done}/{goal}  ({pct_str}%)')
"
        exit 0 ;;
      log)
        shift
        COUNT="${1:-}"
        EXERCISE="${2:-}"
        if [ -z "$COUNT" ] || [ -z "$EXERCISE" ]; then
          echo "Usage: peon trainer log <count> <exercise>" >&2
          echo "Example: peon trainer log 25 pushups" >&2
          exit 1
        fi
        # Validate numeric
        case "$COUNT" in
          ''|*[!0-9]*) echo "peon-ping: count must be a number" >&2; exit 1 ;;
        esac
        python3 -c "
import json, datetime, sys

config_path = '$CONFIG'
state_path = '$STATE'
count = int('$COUNT')
exercise = '$EXERCISE'

try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}

trainer_cfg = cfg.get('trainer', {})
exercises = trainer_cfg.get('exercises', {'pushups': 300, 'squats': 300})

if exercise not in exercises:
    print('peon-ping: unknown exercise \"' + exercise + '\"', file=sys.stderr)
    print('Valid exercises: ' + ', '.join(exercises.keys()), file=sys.stderr)
    sys.exit(1)

goal = exercises[exercise]

$_PY_STATE_IO
state = _load_state(state_path)

trainer_state = state.get('trainer', {})
today = datetime.date.today().isoformat()

# Auto-reset if date changed
if trainer_state.get('date', '') != today:
    trainer_state = {'date': today, 'reps': {k: 0 for k in exercises}, 'last_reminder_ts': 0}

reps = trainer_state.get('reps', {})
reps[exercise] = reps.get(exercise, 0) + count
trainer_state['reps'] = reps
trainer_state['date'] = today
state['trainer'] = trainer_state
_save_state(state_path, state, indent=2)

done = reps[exercise]
pct = min(done / goal, 1.0) if goal > 0 else 0
bar_width = 16
filled = int(pct * bar_width)
empty = bar_width - filled
bar = '\u2588' * filled + '\u2591' * empty
print(f'peon-ping: logged {count} {exercise} ({done}/{goal})')
print(f'  {bar}  {int(pct*100)}%')
"
        exit $? ;;
      goal)
        shift
        ARG1="${1:-}"
        ARG2="${2:-}"
        if [ -z "$ARG1" ]; then
          echo "Usage: peon trainer goal <number>           Set all exercises" >&2
          echo "       peon trainer goal <exercise> <number> Set one exercise" >&2
          exit 1
        fi
        python3 -c "
import json, sys

config_path = '$CONFIG'
arg1 = '$ARG1'
arg2 = '$ARG2'

try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}

trainer = cfg.get('trainer', {})
exercises = trainer.get('exercises', {'pushups': 300, 'squats': 300})

if arg2:
    # goal <exercise> <number>
    exercise = arg1
    try:
        num = int(arg2)
    except ValueError:
        print('peon-ping: goal must be a number', file=sys.stderr)
        sys.exit(1)
    if exercise not in exercises:
        print('peon-ping: unknown exercise \"' + exercise + '\"', file=sys.stderr)
        sys.exit(1)
    exercises[exercise] = num
    print(f'peon-ping: {exercise} goal set to {num}')
else:
    # goal <number>
    try:
        num = int(arg1)
    except ValueError:
        print('peon-ping: goal must be a number', file=sys.stderr)
        sys.exit(1)
    for k in exercises:
        exercises[k] = num
    print(f'peon-ping: all exercise goals set to {num}')

trainer['exercises'] = exercises
cfg['trainer'] = trainer
json.dump(cfg, open(config_path, 'w'), indent=2)
"
        exit $? ;;
      help|*)
        cat <<'TRAINER_HELP'
Usage: peon trainer <command>

Commands:
  on                   Enable trainer mode
  off                  Disable trainer mode
  status               Show today's progress
  log <count> <exercise>  Log completed reps (e.g. log 25 pushups)
  goal <number>        Set daily goal for all exercises
  goal <exercise> <n>  Set daily goal for one exercise
  help                 Show this help

Exercises: pushups, squats
TRAINER_HELP
        exit 0 ;;
    esac ;;
  --*)
    echo "Unknown option: $1" >&2
    echo "Run 'peon help' for usage." >&2; exit 1 ;;
  ?*)
    echo "Unknown command: $1" >&2
    echo "Run 'peon help' for usage." >&2; exit 1 ;;
esac

# If no CLI arg was given and stdin is a terminal (not a pipe from Claude Code),
# the user likely ran `peon` bare — show help instead of blocking on cat.
if [ -t 0 ]; then
  echo "Usage: peon <command>"
  echo ""
  echo "Run 'peon help' for full command list."
  exit 0
fi

INPUT=$(cat)

# Debug log (uncomment to troubleshoot)
# echo "$(date): peon hook — $INPUT" >> /tmp/peon-ping-debug.log

PAUSED=false
[ -f "$PEON_DIR/.paused" ] && PAUSED=true

# --- Single Python call: config, event parsing, agent detection, category routing, sound picking ---
# Consolidates 5 separate python3 invocations into one for ~120-200ms faster hook response.
# Outputs shell variables consumed by the bash play/notify/title logic below.
eval "$(python3 -c "
import sys, json, os, re, random, time, shlex
q = shlex.quote
$_PY_STATE_IO

config_path = '$CONFIG'
state_file = '$STATE'
peon_dir = '$PEON_DIR'
paused = '$PAUSED' == 'true'
agent_modes = {'delegate'}
state_dirty = False

# --- Load config ---
try:
    cfg = json.load(open(config_path))
except Exception:
    cfg = {}

if str(cfg.get('enabled', True)).lower() == 'false':
    print('PEON_EXIT=true')
    sys.exit(0)

volume = cfg.get('volume', 0.5)
desktop_notif = cfg.get('desktop_notifications', True)
notify_always = cfg.get('notify_always', True)
use_sound_effects_device = cfg.get('use_sound_effects_device', True)
linux_audio_player = cfg.get('linux_audio_player', '')
tab_color_cfg = cfg.get('tab_color', {})
tab_color_enabled = str(tab_color_cfg.get('enabled', True)).lower() != 'false'
active_pack = cfg.get('active_pack', 'peon')
pack_rotation = cfg.get('pack_rotation', [])
annoyed_threshold = int(cfg.get('annoyed_threshold', 3))
annoyed_window = float(cfg.get('annoyed_window_seconds', 10))
silent_window = float(cfg.get('silent_window_seconds', 0))
cats = cfg.get('categories', {})
cat_enabled = {}
default_off = {'task.acknowledge'}
for c in ['session.start','task.acknowledge','task.complete','task.error','input.required','resource.limit','user.spam']:
    default = False if c in default_off else True
    cat_enabled[c] = str(cats.get(c, default)).lower() == 'true'

# --- Parse event JSON from stdin ---
event_data = json.load(sys.stdin)
raw_event = event_data.get('hook_event_name', '')

# Debug log: write every incoming event to .event_log for diagnosis
try:
    _elog = os.path.join(peon_dir, '.event_log')
    with open(_elog, 'a') as _ef:
        _ef.write(f'{time.time():.0f} raw={raw_event} keys={sorted(event_data.keys())}\n')
except Exception:
    pass

# Cursor IDE sends lowercase camelCase event names via its Third-party skills
# (Claude Code compatibility) mode. Map them to the PascalCase names used below.
# Claude Code's own PascalCase names pass through unchanged via dict.get fallback.
_cursor_event_map = {
    'sessionStart': 'SessionStart',
    'sessionEnd': 'SessionEnd',
    'beforeSubmitPrompt': 'UserPromptSubmit',
    'stop': 'Stop',
    'preToolUse': '_skip',
    'postToolUse': '_skip',
    'subagentStop': 'Stop',
    'subagentStart': 'SubagentStart',
    'preCompact': 'PreCompact',
}
event = _cursor_event_map.get(raw_event, raw_event)
if event == '_skip':
    print('PEON_EXIT=true')
    sys.exit(0)

ntype = event_data.get('notification_type', '')
# Cursor sends workspace_roots[] instead of cwd
_roots = event_data.get('workspace_roots', [])
cwd = event_data.get('cwd', '') or (_roots[0] if _roots else '')
session_id = event_data.get('session_id', '') or event_data.get('conversation_id', '')
perm_mode = event_data.get('permission_mode', '')
session_source = event_data.get('source', '')

# --- Load state ---
state = _load_state(state_file)

# --- Agent detection ---
_agent_silent = False
_has_barracks = 'barracks' in state.get('buildings', {})
agent_sessions = set(state.get('agent_sessions', []))
if perm_mode and perm_mode in agent_modes:
    agent_sessions.add(session_id)
    state['agent_sessions'] = list(agent_sessions)
    state_dirty = True
    if _has_barracks:
        _agent_silent = True
    else:
        print('PEON_EXIT=true')
        _save_state(state_file, state)
        sys.exit(0)
elif session_id in agent_sessions:
    if _has_barracks:
        _agent_silent = True
    else:
        print('PEON_EXIT=true')
        sys.exit(0)

# --- Session cleanup: expire old sessions ---
now = time.time()
cutoff = now - cfg.get('session_ttl_days', 7) * 86400
session_packs = state.get('session_packs', {})
session_packs_clean = {}
for sid, pack_data in session_packs.items():
    if isinstance(pack_data, dict):
        # New format with timestamp
        if pack_data.get('last_used', 0) > cutoff:
            pack_data['last_used'] = now if sid == session_id else pack_data['last_used']
            session_packs_clean[sid] = pack_data
    elif sid == session_id:
        # Old format, upgrade active session
        session_packs_clean[sid] = dict(pack=pack_data, last_used=now)
    elif isinstance(pack_data, str):
        # Old format for inactive sessions - keep only if we can't determine age
        # This is a migration path; on next use, it will be upgraded
        session_packs_clean[sid] = pack_data
session_packs = session_packs_clean
if session_packs != state.get('session_packs', {}):
    state['session_packs'] = session_packs
    state_dirty = True

# --- Pack rotation: pin a pack per session ---
rotation_mode = cfg.get('pack_rotation_mode', 'random')

if rotation_mode == 'agentskill':
    # Explicit per-session assignments (from skill)
    session_packs = state.get('session_packs', {})
    if session_id in session_packs and session_packs[session_id]:
        pack_data = session_packs[session_id]
        # Handle both old string format and new dict format
        if isinstance(pack_data, dict):
            candidate = pack_data.get('pack', '')
        else:
            candidate = pack_data
        # Validate pack exists, fallback to active_pack if missing
        candidate_dir = os.path.join(peon_dir, 'packs', candidate)
        if candidate and os.path.isdir(candidate_dir):
            active_pack = candidate
            # Update timestamp for this session
            session_packs[session_id] = dict(pack=candidate, last_used=time.time())
            state['session_packs'] = session_packs
            state_dirty = True
        else:
            # Pack was deleted or invalid, use default
            active_pack = cfg.get('active_pack', 'peon')
            # Clean up invalid entry
            del session_packs[session_id]
            state['session_packs'] = session_packs
            state_dirty = True
    else:
        # No assignment: check session_packs 'default' key (for Cursor users without conversation_id)
        default_data = session_packs.get('default')
        if default_data:
            candidate = default_data.get('pack', default_data) if isinstance(default_data, dict) else default_data
            candidate_dir = os.path.join(peon_dir, 'packs', candidate)
            if candidate and os.path.isdir(candidate_dir):
                active_pack = candidate
            else:
                active_pack = cfg.get('active_pack', 'peon')
        else:
            active_pack = cfg.get('active_pack', 'peon')
elif pack_rotation and rotation_mode in ('random', 'round-robin'):
    # Automatic rotation — detect context resets (new session_id within seconds
    # of the last event, no Stop in between) and reuse the previous pack.
    session_packs = state.get('session_packs', {})
    _sp_entry = session_packs.get(session_id)
    _sp_pack = _sp_entry.get('pack', '') if isinstance(_sp_entry, dict) else (_sp_entry or '')
    if session_id in session_packs and _sp_pack in pack_rotation:
        active_pack = _sp_pack
    else:
        inherited = False
        if event == 'SessionStart':
            last_active = state.get('last_active', {})
            la_sid = last_active.get('session_id', '')
            la_ts = last_active.get('timestamp', 0)
            la_evt = last_active.get('event', '')
            la_pack = last_active.get('pack', '')
            # Resume: keep whatever pack was last used for this session
            if session_source == 'resume' and la_pack in pack_rotation:
                active_pack = la_pack
                inherited = True
            # Subagent inheritance: parent just spawned a subagent, use parent's pack
            elif state.get('pending_subagent_pack') and (time.time() - state['pending_subagent_pack'].get('ts', 0) < 30):
                parent_pack = state['pending_subagent_pack'].get('pack', '')
                if parent_pack in pack_rotation:
                    active_pack = parent_pack
                    inherited = True
            # Context reset: recent activity from another session, no Stop/SessionEnd
            elif (la_sid and la_sid != session_id and la_pack in pack_rotation
                    and la_evt not in ('Stop', 'SessionEnd')
                    and time.time() - la_ts < 15):
                active_pack = la_pack
                inherited = True
        if not inherited:
            if rotation_mode == 'round-robin':
                rotation_index = state.get('rotation_index', 0) % len(pack_rotation)
                active_pack = pack_rotation[rotation_index]
                state['rotation_index'] = rotation_index + 1
            else:
                active_pack = random.choice(pack_rotation)
        session_packs[session_id] = active_pack
        state['session_packs'] = session_packs
        state_dirty = True
else:
    # Default: everyone uses active_pack
    active_pack = cfg.get('active_pack', 'peon')

# --- Level overrides pack (level determines sounds + overlay icon) ---
_LVL_PACKS = {1:'peon', 2:'peasant', 3:'wc3_grunt', 4:'wc3_knight', 5:'wc3_farseer',
              6:'wc3_jaina', 7:'dota2_witch_doctor', 8:'wc3_corrupted_arthas',
              9:'wc3_brewmaster', 10:'murloc'}
_cur_lvl = state.get('stats', {}).get('level', 1)
_lvl_pack = _LVL_PACKS.get(_cur_lvl, '')
if _lvl_pack:
    _lvl_pack_dir = os.path.join(peon_dir, 'packs', _lvl_pack)
    if os.path.isdir(_lvl_pack_dir):
        active_pack = _lvl_pack

# --- Track last active session for context-reset detection ---
state['last_active'] = dict(session_id=session_id, pack=active_pack,
                            timestamp=time.time(), event=event)
state_dirty = True

# --- Project name ---
project = cwd.rsplit('/', 1)[-1] if cwd else 'claude'
if not project:
    project = 'claude'
project = re.sub(r'[^a-zA-Z0-9 ._-]', '', project)

projects_seen = state.get('projects_seen', [])
if project and project != 'claude' and project not in projects_seen:
    projects_seen.append(project)
    state['projects_seen'] = projects_seen
    state_dirty = True

# --- Event routing ---
category = ''
status = ''
marker = ''
notify = ''
notify_color = ''
msg = ''

if event == 'SessionStart':
    source = event_data.get('source', '')
    if source == 'compact':
        # Compaction is mid-conversation — greeting makes no sense
        print('PEON_EXIT=true')
        sys.exit(0)
    category = 'session.start'
    status = 'ready'
elif event == 'UserPromptSubmit':
    status = 'working'
    if cat_enabled.get('user.spam', True):
        all_ts = state.get('prompt_timestamps', {})
        if isinstance(all_ts, list):
            all_ts = {}
        now = time.time()
        ts = [t for t in all_ts.get(session_id, []) if now - t < annoyed_window]
        ts.append(now)
        all_ts[session_id] = ts
        state['prompt_timestamps'] = all_ts
        state_dirty = True
        if len(ts) >= annoyed_threshold:
            category = 'user.spam'
    if not category and cat_enabled.get('task.acknowledge', False):
        category = 'task.acknowledge'
        status = 'working'
    if silent_window > 0:
        prompt_starts = state.get('prompt_start_times', {})
        prompt_starts[session_id] = time.time()
        state['prompt_start_times'] = prompt_starts
        state_dirty = True
elif event == 'Stop':
    category = 'task.complete'
    silent = False
    if silent_window > 0:
        prompt_starts = state.get('prompt_start_times', {})
        # start_time=0 when no prior prompt; 0 is falsy so short-circuits to not-silent
        start_time = prompt_starts.pop(session_id, 0)
        if start_time and (time.time() - start_time) < silent_window:
            silent = True
        state['prompt_start_times'] = prompt_starts
        state_dirty = True
    status = 'done'
    if not silent:
        marker = '\u25cf '
        notify = '1'
        notify_color = 'blue'
        msg = project + '  \u2014  Task complete'
    else:
        category = ''
elif event == 'Notification':
    if ntype == 'permission_prompt':
        # Sound is handled by the PermissionRequest event; only set tab title here
        status = 'needs approval'
        marker = '\u25cf '
    elif ntype == 'idle_prompt':
        status = 'done'
        marker = '\u25cf '
        notify = '1'
        notify_color = 'yellow'
        msg = project + '  \u2014  Waiting for input'
    else:
        print('PEON_EXIT=true')
        sys.exit(0)
elif event == 'PermissionRequest':
    category = 'input.required'
    status = 'needs approval'
    marker = '\u25cf '
    notify = '1'
    notify_color = 'red'
    msg = project + '  \u2014  Permission needed'
elif event == 'PostToolUseFailure':
    # Bash failures arrive here with error field (e.g. Exit code 1)
    tool_name = event_data.get('tool_name', '')
    error_msg = event_data.get('error', '')
    if tool_name == 'Bash' and error_msg:
        category = 'task.error'
        status = 'error'
    else:
        print('PEON_EXIT=true')
        sys.exit(0)
elif event == 'SubagentStart':
    # Record parent's pack so spawned subagent sessions inherit it, then stay silent
    state['pending_subagent_pack'] = dict(ts=time.time(), pack=active_pack)
    state_dirty = True
    _save_state(state_file, state)
    print('PEON_EXIT=true')
    sys.exit(0)
elif event == 'PreCompact':
    # Context window filling up — compaction about to start
    category = 'resource.limit'
    status = 'working'
elif event == 'SessionEnd':
    # Clean up state for this session
    for key in ('session_packs', 'prompt_timestamps', 'session_start_times', 'prompt_start_times'):
        d = state.get(key, {})
        if session_id in d:
            del d[session_id]
            state[key] = d
    agent_sessions.discard(session_id)
    state['agent_sessions'] = list(agent_sessions)
    state_dirty = True
    _save_state(state_file, state)
    print('PEON_EXIT=true')
    sys.exit(0)
else:
    # Unknown event — exit cleanly
    print('PEON_EXIT=true')
    sys.exit(0)

# --- Debounce rapid Stop events (e.g. background task completions) ---
if event == 'Stop':
    now = time.time()
    last_stop = state.get('last_stop_time', 0)
    if now - last_stop < 5:
        category = ''
        notify = ''
    state['last_stop_time'] = now
    state_dirty = True

# --- Suppress sounds during session replay (claude -c) ---
# When continuing a session, Claude fires SessionStart then immediately replays
# old events. Suppress all sounds within 3s of SessionStart for the same session.
now = time.time()
if event == 'SessionStart':
    session_starts = state.get('session_start_times', {})
    session_starts[session_id] = now
    state['session_start_times'] = session_starts
    state_dirty = True
elif category:
    session_starts = state.get('session_start_times', {})
    start_time = session_starts.get(session_id, 0)
    if start_time and (now - start_time) < 3:
        category = ''
        notify = ''

# --- Check if category is enabled ---
if category and not cat_enabled.get(category, True):
    category = ''

# --- Pick sound (skip if no category or paused) ---
sound_file = ''
icon_path = ''
if category and not paused:
    pack_dir = os.path.join(peon_dir, 'packs', active_pack)
    try:
        manifest = None
        for mname in ('openpeon.json', 'manifest.json'):
            mpath = os.path.join(pack_dir, mname)
            if os.path.exists(mpath):
                manifest = json.load(open(mpath))
                break
        if not manifest:
            manifest = {}
        sounds = manifest.get('categories', {}).get(category, {}).get('sounds', [])
        if sounds:
            last_played = state.get('last_played', {})
            last_file = last_played.get(category, '')
            candidates = sounds if len(sounds) <= 1 else [s for s in sounds if s['file'] != last_file]
            pick = random.choice(candidates)
            last_played[category] = pick['file']
            state['last_played'] = last_played
            state_dirty = True
            file_ref = str(pick.get('file', ''))
            if '/' in file_ref:
                candidate = os.path.realpath(os.path.join(pack_dir, file_ref))
            else:
                candidate = os.path.realpath(os.path.join(pack_dir, 'sounds', file_ref))
            pack_root = os.path.realpath(pack_dir) + os.sep
            if candidate.startswith(pack_root):
                sound_file = candidate
            # Icon resolution chain (CESP §5.5)
            icon_candidate = ''
            if pick.get('icon'):
                icon_candidate = str(pick['icon'])
            elif manifest.get('categories', {}).get(category, {}).get('icon'):
                icon_candidate = str(manifest['categories'][category]['icon'])
            elif manifest.get('icon'):
                icon_candidate = str(manifest['icon'])
            elif os.path.isfile(os.path.join(pack_dir, 'icon.png')):
                icon_candidate = 'icon.png'
            if icon_candidate:
                icon_resolved = os.path.realpath(os.path.join(pack_dir, icon_candidate))
                if icon_resolved.startswith(pack_root) and os.path.isfile(icon_resolved):
                    icon_path = icon_resolved
    except Exception:
        pass

# --- Level portrait override for overlay icon ---
_lvl_icon = os.path.join(peon_dir, 'icons', f'lvl-{_cur_lvl}.png')
if os.path.isfile(_lvl_icon):
    icon_path = _lvl_icon

# --- WC3 Metagame (stats, economy, buildings, achievements, combos, time) ---
game_cfg = cfg.get('game', {})
game_on = str(game_cfg.get('enabled', True)).lower() != 'false'
game_notify = ''
game_subtitle = ''
levelup_sound = ''

if game_on:
    import datetime as _dt
    _now_dt = _dt.datetime.now()
    _today = _now_dt.date().isoformat()
    _hour = _now_dt.hour
    _minute = _now_dt.minute
    _weekday = _now_dt.weekday()

    stats = state.setdefault('stats', {})
    econ = state.setdefault('economy', {})
    buildings = state.get('buildings', {})
    combo = state.get('combo_count', 0)
    bunker_until = state.get('bunker_until', 0)
    in_bunker = bunker_until > time.time()
    s_errors = state.get('session_errors', 0)
    s_perms = state.get('session_permissions', 0)
    s_tasks = state.get('session_tasks', 0)
    fatigue = state.get('fatigue', 0)
    log = state.get('activity_log', [])

    if econ.get('daily_date') != _today:
        econ['daily_tasks'] = 0
        econ['daily_prompts'] = 0
        econ['daily_date'] = _today
        econ['debt_interest'] = False
        s_errors = 0
        s_perms = 0
        s_tasks = 0
        fatigue = 0
        streak = stats.get('current_streak_days', 0)
        last_date = stats.get('last_active_date', '')
        if last_date:
            try:
                ld = _dt.date.fromisoformat(last_date)
                delta = (_now_dt.date() - ld).days
                if delta == 1:
                    streak += 1
                elif delta > 1:
                    streak = 1
            except Exception:
                streak = 1
        else:
            streak = 1
        stats['current_streak_days'] = streak
        if streak > stats.get('longest_streak_days', 0):
            stats['longest_streak_days'] = streak

        _army = state.get('army', {})
        _UNIT_HP_M = dict(grunt=30, raider=50, tauren=80, shaman=20)
        for _uk in list(_army.keys()):
            if isinstance(_army[_uk], int): _army[_uk] = [_UNIT_HP_M.get(_uk, 30)] * _army[_uk]
        if _army:
            _UNIT_UPKEEP = dict(grunt=10, raider=40, tauren=100, shaman=30)
            _army_upkeep = sum(_UNIT_UPKEEP.get(uid, 0) * len(hps) for uid, hps in _army.items())
            if 'goblin_lab' in buildings:
                _army_upkeep //= 2
            if _army_upkeep > 0:
                econ['gold'] = econ.get('gold', 0) - _army_upkeep
                econ['army_upkeep_paid'] = _army_upkeep

    stats['last_active_date'] = _today
    gold = econ.get('gold', 0)
    lumber = econ.get('lumber', 0)
    gold_delta = 0
    lumber_delta = 0
    econ_on = str(game_cfg.get('economy', True)).lower() != 'false'

    active_sessions = len(state.get('session_packs', {}))
    if active_sessions <= 3:
        upkeep = 'none'
        upkeep_mult = 1.0
    elif active_sessions <= 6:
        upkeep = 'low'
        upkeep_mult = 0.7
    else:
        upkeep = 'high'
        upkeep_mult = 0.4
    old_upkeep = econ.get('upkeep', 'none')

    daily_tasks = econ.get('daily_tasks', 0)

    _fatigue_thresh = 60
    if 'tavern' in buildings:
        _fatigue_thresh += 30
    _fatigue_exhaust = _fatigue_thresh + 30

    _mine_low, _mine_out = (80, 120) if 'world_tree' in buildings else (50, 80)

    if econ_on:
        if category == 'task.complete' or event == 'Stop':
            base_gold = 10
            if daily_tasks >= _mine_out:
                base_gold = 0
            elif daily_tasks >= _mine_low:
                base_gold = 5
            _fg = int(base_gold * upkeep_mult)
            if fatigue >= _fatigue_exhaust:
                _fg = 0
            elif fatigue >= _fatigue_thresh:
                _fg = _fg // 2
            gold_delta += _fg
            daily_tasks += 1
            s_tasks += 1
            if not in_bunker:
                fatigue += 1
                stats['fatigue_total'] = stats.get('fatigue_total', 0) + 1
            econ['daily_tasks'] = daily_tasks
            stats['tasks_completed'] = stats.get('tasks_completed', 0) + 1
        elif category == 'task.acknowledge':
            gold_delta += int(2 * upkeep_mult)
        elif category == 'resource.limit':
            gold_delta -= 20
            stats['context_limits_hit'] = stats.get('context_limits_hit', 0) + 1
        elif category == 'session.start':
            lumber_delta += 5
            stats['sessions_total'] = stats.get('sessions_total', 0) + 1
            if _weekday >= 5:
                stats['weekend_sessions'] = stats.get('weekend_sessions', 0) + 1
        elif category == 'user.spam' or event == 'UserPromptSubmit':
            lumber_delta += 1
            econ['daily_prompts'] = econ.get('daily_prompts', 0) + 1
            stats['prompts_total'] = stats.get('prompts_total', 0) + 1
            if econ.get('daily_prompts', 0) > 100:
                lumber_delta = max(1, lumber_delta // 2)

        if event == 'PermissionRequest':
            s_perms += 1
            stats['permissions_total'] = stats.get('permissions_total', 0) + 1

        if econ.get('debt_interest') and gold < 0 and gold_delta > 0:
            gold_delta = max(0, gold_delta - 1)

        if fatigue >= _fatigue_exhaust and gold > 0 and category == 'task.complete':
            if random.random() < 0.1:
                raid_loss = random.randint(50, 200)
                raid_loss = min(raid_loss, gold + gold_delta)
                gold_delta -= raid_loss
                raiders = random.choice(['Murlocs', 'Gnolls', 'Kobolds'])
                raid_msg = f'{raiders} raided your gold mine! -{raid_loss} gold (Peon too tired to defend!)'
                if raiders == 'Kobolds':
                    raid_msg += ' You no take candle!'
                game_subtitle = raid_msg

        econ['upkeep'] = upkeep

        if upkeep != old_upkeep and old_upkeep == 'none' and upkeep != 'none':
            up_msg = 'Low upkeep!' if upkeep == 'low' else 'High upkeep!'
            game_subtitle = game_subtitle or up_msg

        if daily_tasks == _mine_low and base_gold == 5:
            game_subtitle = game_subtitle or 'Gold mine is running low!'
        elif daily_tasks == _mine_out and base_gold == 0:
            game_subtitle = game_subtitle or 'Gold mine has collapsed!'

    # --- Combo system (gated behind War Mill) ---
    combo_on = str(game_cfg.get('combos', True)).lower() != 'false'
    has_war_mill = 'war_mill' in buildings
    combo_text = ''
    if combo_on and has_war_mill:
        combo_idle = time.time() - state.get('combo_ts', 0)
        if combo > 0 and combo_idle >= 3600:
            if combo == 99:
                stats['combo_broke_99'] = True
            if combo >= 2:
                combo_text = f'Combo broken at {combo}x.'
            combo = 0
        if category == 'task.complete' and event == 'Stop':
            combo = min(combo + 1, 100)
            state['combo_ts'] = time.time()
            if combo >= 100:
                combo_text = 'GODLIKE!'
            elif combo >= 50:
                combo_text = 'UNSTOPPABLE!'
            elif combo >= 10:
                combo_text = 'Mega kill!'
            elif combo >= 5:
                combo_text = 'Killing spree!'
            elif combo >= 3:
                combo_text = 'Triple kill!'
            elif combo >= 2:
                combo_text = 'Double kill!'
            if combo > stats.get('max_combo', 0):
                stats['max_combo'] = combo
        elif fatigue >= _fatigue_exhaust or category == 'resource.limit':
            if combo == 99:
                stats['combo_broke_99'] = True
            if combo >= 2:
                combo_text = f'Combo broken at {combo}x.'
            combo = 0
    state['combo_count'] = combo

    state['session_errors'] = s_errors
    state['session_permissions'] = s_perms
    state['session_tasks'] = s_tasks
    state['fatigue'] = fatigue

    # --- Time-aware mechanics ---
    time_on = str(game_cfg.get('time_aware', True)).lower() != 'false'
    time_text = ''
    if time_on:
        if category == 'session.start':
            if _hour < 5:
                time_text = random.choice(['WHY ARE YOU STILL HERE?!', 'Human crazy. Peon going to bed.', 'The dead of night... perfect for coding.'])
            elif _hour < 8:
                time_text = random.choice(['New day dawns! Ready to work?', 'Early bird gets the worm. Peon gets nothing.'])
            elif _hour >= 21:
                time_text = random.choice(['It getting dark... human should sleep.', 'Night shift? Peon charge overtime.'])
        if _weekday == 0 and _hour == 9 and _minute < 15 and category == 'session.start':
            time_text = 'Back to the mines...'
        elif _weekday == 4 and _hour == 17 and _minute < 15 and category == 'task.complete':
            time_text = 'FREEDOM! Peon free! ...until Monday.'
        if _hour >= 12 and _hour < 13 and random.random() < 0.15 and category:
            time_text = time_text or 'Human eat lunch? Or just code? Peon worried.'

    # --- Arcane Sanctum: peon prophecies ---
    if 'arcane_sanctum' in buildings and category == 'session.start':
        _prophecies = [
            'The spirits whisper: refactor before it is too late.',
            'Peon foresee many tasks today. Many, many tasks.',
            'The ancestors say: read the error message. Read it again.',
            'A great PR merge is in your future.',
            'Beware the 3 PM slump. Peon warned you.',
            'The bones say: this session ends with a merge conflict.',
            'Peon sense a long debug session ahead. Bring snacks.',
            'The stars align for clean code. Do not waste this moment.',
            'A legendary item draws near. Peon can feel it.',
            'Today is good day to ship. Or terrible day. Peon not sure.',
        ]
        time_text = (time_text + ' ' if time_text else '') + random.choice(_prophecies)

    # --- Achievement checks ---
    achiev_on = str(game_cfg.get('achievements', True)).lower() != 'false'
    unlocked = stats.get('achievements_unlocked', {})
    new_achiev = ''
    _achiev_defs = [
        ('first_blood',      lambda: stats.get('fatigue_total', 0) >= 20, 'First Blood', 'Peon... so... tired...'),
        ('zug_zug_veteran',  lambda: stats.get('tasks_completed', 0) >= 100, 'Zug Zug Veteran', 'More work? ...More work.'),
        ('night_elf',        lambda: _hour >= 2 and _hour < 5, 'Night Elf', 'The shadows hold many secrets...'),
        ('dawn_patrol',      lambda: _hour >= 4 and _hour < 6 and category == 'session.start', 'Dawn Patrol', 'The horn of Cenarius has sounded!'),
        ('weekend_warrior',  lambda: stats.get('weekend_sessions', 0) >= 10, 'Weekend Warrior', 'For the Horde! ...on a Saturday?'),
        ('iron_peon',        lambda: stats.get('current_streak_days', 0) >= 7, 'Iron Peon', 'Peon never stop. Peon strong.'),
        ('rage_quit',        lambda: fatigue >= 40, 'Rage Quit', 'Peon collapse! Too many tasks!'),
        ('oops',             lambda: stats.get('repairs_total', 0) >= 25, 'Oops', 'Stop breaking things!'),
        ('the_grind',        lambda: stats.get('tasks_completed', 0) >= 1000, 'The Grind', 'Something need doing? ALWAYS.'),
        ('permit_patty',     lambda: s_perms >= 20, 'Permit Patty', 'Why you keep asking?!'),
        ('compact_survivor', lambda: stats.get('context_limits_hit', 0) >= 5, 'Compact Survivor', 'Under attack!'),
        ('architect',        lambda: len(buildings) >= 10, 'Architect', 'Base complete! Peon... proud.'),
        ('combo_fiend',      lambda: stats.get('max_combo', 0) >= 50, 'Combo Fiend', 'Peon can\\'t feel legs. Human can\\'t feel keyboard. 50 combo.'),
        ('mogul',            lambda: stats.get('total_gold_earned', 0) >= 5000, 'Mogul', 'Human rich! Peon still poor though.'),
        ('stop_clicking',    lambda: stats.get('prompts_total', 0) >= 500, 'Stop Clicking Me!', 'Me busy! Leave me alone!'),
        ('peon_union_rep',   lambda: fatigue >= 50, 'Peon Union Rep', 'Peon demand hazard pay!'),
        ('touch_grass',      lambda: _hour >= 3 and _hour < 5 and _weekday >= 5, 'Touch Grass', 'Why human code now?! Go outside!'),
        ('first_kill',       lambda: state.get('boss_kills_total', 0) >= 1, 'First Kill', 'Peon... actually killed something?!'),
        ('raid_leader',      lambda: state.get('boss_kills_total', 0) >= 10, 'Raid Leader', 'LFM ICC 25 Heroic, link achievement.'),
        ('you_no_take',      lambda: state.get('boss_kills', {}).get('kobold', 0) >= 5, 'You No Take Candle!', 'Stop farming kobolds! They have families!'),
        ('night_raid',       lambda: _hour >= 0 and _hour < 5 and state.get('active_boss') is not None, 'Night Raid', 'Raiding at this hour?! Peon calling HR.'),
        ('combo_god',        lambda: stats.get('max_combo', 0) >= 100, 'Combo God', '100 combo?! Peon check if human plugged into Matrix.'),
        ('hoarder',          lambda: stats.get('max_items_owned', 0) >= 40, 'Hoarder', 'Where peon put all this stuff?!'),
        ('lunch_raider',     lambda: _hour == 12 and state.get('active_boss') is not None and category == 'task.complete', 'Lunch Raider', 'Human raid during lunch. Very dedicated. Very hungry.'),
        ('boss_slayer',      lambda: len([k for k, v in state.get('boss_kills', {}).items() if v >= 1]) >= 11, 'Boss Slayer', 'Every boss defeated at least once. Peon... genuinely in awe.'),
        ('warchief',         lambda: sum(len(v) if isinstance(v, list) else v for v in state.get('army', {}).values()) >= 10, 'Warchief', 'An army of 10. Peon finally has friends!'),
        ('general',          lambda: stats.get('units_hired_total', 0) >= 50, 'General', '50 units hired. Peon running a draft.'),
        ('casualties_of_war', lambda: stats.get('units_lost_total', 0) >= 20, 'Casualties of War', 'Lost 20 units. Peon write many sad letters.'),
        ('speedrun',         lambda: 0 < stats.get('fastest_kill_secs', 99999) <= 300, 'Speed Run', 'Boss dead in 5 minutes?! Peon blink and missed it.'),
        ('leeroy',           lambda: stats.get('whelp_leeroy'), 'LEEEEROY JENKINS!', 'At least I have chicken.'),
        ('speed_lich_king',  lambda: stats.get('fastest_lich_king_pct', 1.0) <= 0.5, 'Lich King Any%', 'The Lich King in under 4 days. Speedrun.com wants your replay.'),
        ('lich_kings_end',   lambda: state.get('boss_kills', {}).get('lich_king', 0) >= 1, 'Arthas\'s End', 'No king rules forever. Peon... legendary.'),
        ('loot_goblin',      lambda: stats.get('total_items_looted', 0) >= 1000, 'Loot Goblin', 'Human loot 1000 items?! Peon need bigger bags!'),
        ('iron_will',        lambda: stats.get('current_streak_days', 0) >= 30, 'Iron Will', 'Not even death can stop peon now.'),
        ('unbreakable',      lambda: stats.get('current_streak_days', 0) >= 365, 'Unbreakable', 'Peon is eternal. Human is eternal. We are one.'),
        ('duct_tape',        lambda: stats.get('repairs_total', 0) >= 500, 'Duct Tape Engineer', 'If it break, peon fix. If it not break, peon fix anyway.'),
        ('trade_prince',     lambda: stats.get('total_gold_earned', 0) >= 1000000, 'Trade Prince', 'Time is money, friend! And you... you have ALL the money.'),
        ('witching_hour',    lambda: _hour == 0 and _minute == 0 and category == 'task.complete', 'The Witching Hour', 'Dark magic strongest at midnight...'),
        ('so_close',         lambda: stats.get('combo_broke_99'), 'So Close', 'Peon was THIS close to greatness.'),
        ('all_nighter',      lambda: (lambda ss: ss and datetime.datetime.fromtimestamp(ss).date() < _now_dt.date() and _hour >= 5)(state.get('session_start_times', {}).get(session_id, 0)), 'All-Nighter', 'Sleep is for the weak. Peon is weak but peon do it anyway.'),
        ('tgif_zombie',      lambda: _weekday == 4 and _hour >= 17 and fatigue >= 40, 'TGIF Zombie', 'It Friday... peon can barely stand...'),
        ('sunday_scaries',   lambda: _weekday == 6 and _hour >= 20 and category == 'session.start', 'Sunday Scaries', 'Tomorrow is Monday... peon not ready...'),
        ('world_tour',       lambda: len(state.get('projects_seen', [])) >= 10, 'World Tour', 'Peon been everywhere. 10 repos. Peon need vacation.'),
    ]
    if achiev_on:
        for aid, check_fn, aname, aflavor in _achiev_defs:
            if aid not in unlocked:
                try:
                    if check_fn():
                        unlocked[aid] = int(time.time())
                        new_achiev = f'{aname}: {aflavor}'
                        break
                except Exception:
                    pass
        stats['achievements_unlocked'] = unlocked

    _ach_progress = {
        'first_blood':      [stats.get('fatigue_total', 0), 20],
        'zug_zug_veteran':  [stats.get('tasks_completed', 0), 100],
        'night_elf':        [1 if 'night_elf' in unlocked else 0, 1],
        'dawn_patrol':      [1 if 'dawn_patrol' in unlocked else 0, 1],
        'weekend_warrior':  [stats.get('weekend_sessions', 0), 10],
        'iron_peon':        [stats.get('current_streak_days', 0), 7],
        'rage_quit':        [fatigue, 40],
        'oops':             [stats.get('repairs_total', 0), 25],
        'the_grind':        [stats.get('tasks_completed', 0), 1000],
        'permit_patty':     [s_perms, 20],
        'compact_survivor': [stats.get('context_limits_hit', 0), 5],
        'architect':        [len(buildings), 10],
        'combo_fiend':      [stats.get('max_combo', 0), 50],
        'mogul':            [stats.get('total_gold_earned', 0), 5000],
        'stop_clicking':    [stats.get('prompts_total', 0), 500],
        'peon_union_rep':   [fatigue, 50],
        'touch_grass':      [1 if 'touch_grass' in unlocked else 0, 1],
        'first_kill':       [state.get('boss_kills_total', 0), 1],
        'raid_leader':      [state.get('boss_kills_total', 0), 10],
        'you_no_take':      [state.get('boss_kills', {}).get('kobold', 0), 5],
        'night_raid':       [1 if 'night_raid' in unlocked else 0, 1],
        'combo_god':        [stats.get('max_combo', 0), 100],
        'hoarder':          [stats.get('max_items_owned', 0), 40],
        'lunch_raider':     [1 if 'lunch_raider' in unlocked else 0, 1],
        'boss_slayer':      [len([k for k, v in state.get('boss_kills', {}).items() if v >= 1]), 11],
        'warchief':         [sum(len(v) if isinstance(v, list) else v for v in state.get('army', {}).values()), 10],
        'general':          [stats.get('units_hired_total', 0), 50],
        'casualties_of_war': [stats.get('units_lost_total', 0), 20],
        'speedrun':         [1 if 0 < stats.get('fastest_kill_secs', 99999) <= 300 else 0, 1],
        'leeroy':           [1 if stats.get('whelp_leeroy') else 0, 1],
        'speed_lich_king':  [1 if stats.get('fastest_lich_king_pct', 1.0) <= 0.5 else 0, 1],
        'lich_kings_end':   [state.get('boss_kills', {}).get('lich_king', 0), 1],
        'loot_goblin':      [stats.get('total_items_looted', 0), 1000],
        'iron_will':        [stats.get('current_streak_days', 0), 30],
        'unbreakable':      [stats.get('current_streak_days', 0), 365],
        'duct_tape':        [stats.get('repairs_total', 0), 500],
        'trade_prince':     [stats.get('total_gold_earned', 0), 1000000],
        'witching_hour':    [1 if 'witching_hour' in unlocked else 0, 1],
        'so_close':         [1 if stats.get('combo_broke_99') else 0, 1],
        'all_nighter':      [1 if 'all_nighter' in unlocked else 0, 1],
        'tgif_zombie':      [1 if 'tgif_zombie' in unlocked else 0, 1],
        'sunday_scaries':   [1 if 'sunday_scaries' in unlocked else 0, 1],
        'world_tour':       [len(state.get('projects_seen', [])), 10],
    }
    stats['achievements_progress'] = _ach_progress

    # --- Level system (cross-faction progression) ---
    _LEVELS = [
        (0,       1,  'Peon',          'peon'),
        (25,      2,  'Peasant',       'peasant'),
        (100,     3,  'Grunt',         'wc3_grunt'),
        (250,     4,  'Knight',        'wc3_knight'),
        (500,     5,  'Far Seer',      'wc3_farseer'),
        (1000,    6,  'Jaina',         'wc3_jaina'),
        (2500,    7,  'Witch Doctor',  'dota2_witch_doctor'),
        (5000,    8,  'Arthas',        'wc3_corrupted_arthas'),
        (10000,   9,  'Brewmaster',    'wc3_brewmaster'),
        (1000000, 10, 'Murloc',        'murloc'),
    ]
    _LEVEL_FLAVORS = {
        1:  'Ready to work!',
        2:  'More work? I just got promoted from the other side!',
        3:  'My blade is yours! Zug zug.',
        4:  'For Lordaeron! ...and clean code.',
        5:  'The spirits reveal the code ahead.',
        6:  'I hate resorting to violence. But 1000 tasks...',
        7:  'Look at me. Hee hee! I am da witch doctor.',
        8:  'Glad you could make it. Now serve the code.',
        9:  'Another round? Peon buy drinks!',
        10: 'MRGLGLGLGL! You have transcended all factions. The swamp welcomes you.',
    }
    tc = stats.get('tasks_completed', 0)
    cur_lvl = 1
    cur_title = 'Peon'
    lvl_pack = ''
    for thresh, lvl, title, lpack in _LEVELS:
        if tc >= thresh:
            cur_lvl = lvl
            cur_title = title
            lvl_pack = lpack
    prev_lvl = stats.get('level', 0)
    level_up_text = ''
    lvl_pack_missing = ''
    if prev_lvl and cur_lvl > prev_lvl:
        flavor = _LEVEL_FLAVORS.get(cur_lvl, '')
        level_up_text = f'LEVEL UP! Lvl {cur_lvl} \u2014 {cur_title}: {flavor}'
        if lvl_pack:
            lp_dir = os.path.join(peon_dir, 'packs', lvl_pack)
            lp_manifest = os.path.join(lp_dir, 'openpeon.json')
            if not os.path.isfile(lp_manifest):
                lp_manifest = os.path.join(lp_dir, 'manifest.json')
            if not os.path.isfile(lp_manifest):
                lvl_pack_missing = lvl_pack
            if os.path.isfile(lp_manifest):
                try:
                    lm = json.load(open(lp_manifest))
                    lp_cats = lm.get('categories', lm)
                    lp_sounds = []
                    for lk in ('session.start', 'task.complete'):
                        lp_cat = lp_cats.get(lk, {})
                        if isinstance(lp_cat, dict):
                            lp_sounds.extend(lp_cat.get('sounds', []))
                        elif isinstance(lp_cat, list):
                            lp_sounds.extend(lp_cat)
                    if lp_sounds:
                        lp_pick = random.choice(lp_sounds)
                        lp_file = lp_pick.get('file', '') if isinstance(lp_pick, dict) else str(lp_pick)
                        if lp_file:
                            if '/' in lp_file:
                                lp_path = os.path.join(lp_dir, lp_file)
                            else:
                                lp_path = os.path.join(lp_dir, 'sounds', lp_file)
                            if os.path.isfile(lp_path):
                                levelup_sound = lp_path
                except Exception:
                    pass
    stats['level'] = cur_lvl
    stats['level_title'] = cur_title

    # --- Random events (gated behind Stronghold) ---
    evt_on = str(game_cfg.get('random_events', True)).lower() != 'false'
    evt_chance = float(game_cfg.get('random_event_chance', 0.05))
    has_stronghold = 'stronghold' in buildings
    game_event_text = ''
    if evt_on and has_stronghold and econ_on and random.random() < evt_chance and category:
        last_evt = state.get('last_random_event_date', '')
        if last_evt != _today:
            r = random.random()
            if r < 0.4:
                bonus = random.randint(50, 200)
                econ['gold'] = econ.get('gold', 0) + bonus
                game_event_text = f'Peon was digging hole and found shiny! +{bonus} gold'
            elif r < 0.7 and daily_tasks >= 10:
                game_event_text = 'Gold vein discovered! Bonus gold incoming.'
                econ['daily_tasks'] = max(0, econ.get('daily_tasks', 0) - 20)
            else:
                game_event_text = 'A goblin merchant arrives! Buildings 50% off today.'
                state['goblin_discount_date'] = _today
            state['last_random_event_date'] = _today
            state_dirty = True

    # --- Resource node spawning (harvestable on dashboard map) ---
    _TREE_POS = ['0,0', '6,0', '0,1', '0,4', '1,4']
    _MINE_POS = ['6,4', '6,3']
    if econ_on and category in ('task.complete', 'session.start'):
        lnodes = state.get('lumber_nodes', [])
        gnodes = state.get('gold_nodes', [])
        occupied = {n['pos'] for n in lnodes} | {n['pos'] for n in gnodes}
        if random.random() < 0.15:
            free_trees = [p for p in _TREE_POS if p not in occupied]
            if free_trees:
                lnodes.append(dict(pos=random.choice(free_trees), amt=random.randint(10, 40)))
                state['lumber_nodes'] = lnodes
                state_dirty = True
        if random.random() < 0.06:
            free_mines = [p for p in _MINE_POS if p not in occupied]
            if free_mines:
                gnodes.append(dict(pos=random.choice(free_mines), amt=random.randint(30, 120)))
                state['gold_nodes'] = gnodes
                state_dirty = True

    if _weekday == 4 and _hour == 17 and _minute < 5 and econ_on:
        weekly_gold = stats.get('tasks_completed', 0) % 100
        if weekly_gold > 0 and state.get('last_payday') != _today:
            econ['gold'] = econ.get('gold', 0) + weekly_gold
            state['last_payday'] = _today
            game_event_text = game_event_text or f'Payday! +{weekly_gold} gold. Peon buy round of grog!'

    _hour_coded = _hour
    if _hour_coded > stats.get('latest_hour_coded', 0):
        stats['latest_hour_coded'] = _hour_coded
    if stats.get('earliest_hour_coded') is None or _hour_coded < stats.get('earliest_hour_coded', 24):
        stats['earliest_hour_coded'] = _hour_coded

    # --- Item system (drops, inventory, equipped effects) ---
    _ITEMS = {
        'claws_of_attack':     dict(name='Claws of Attack +3',     r='common',    e='gold_bonus',      v=3,    desc='+3 bonus gold per task'),
        'gauntlets_of_str':    dict(name='Gauntlets of Strength',  r='common',    e='lumber_bonus',    v=2,    desc='+2 bonus lumber per prompt'),
        'ring_of_protection':  dict(name='Ring of Protection +2',  r='common',    e='gold_bonus',      v=2,    desc='+2 bonus gold per task'),
        'slippers_of_agility': dict(name='Slippers of Agility',   r='common',    e='combo_bonus',     v=1,    desc='Combos count +1 extra'),
        'circlet_of_nobility': dict(name='Circlet of Nobility',    r='common',    e='gold_bonus',      v=2,    desc='+2 bonus gold per task'),
        'mantle_of_intel':     dict(name='Mantle of Intelligence', r='common',    e='lumber_bonus',    v=1,    desc='+1 bonus lumber per prompt'),
        'belt_of_str':         dict(name='Belt of Giant Strength +6', r='common', e='gold_bonus',      v=1,    desc='+1 bonus gold per task'),
        'gloves_of_haste':     dict(name='Gloves of Haste',       r='common',    e='combo_bonus',     v=1,    desc='Combos count +1 extra'),
        'robe_of_magi':        dict(name='Robe of the Magi +6',   r='common',    e='lumber_bonus',    v=2,    desc='+2 bonus lumber per prompt'),
        'pendant_of_mana':     dict(name='Pendant of Mana',       r='common',    e='lumber_bonus',    v=1,    desc='+1 bonus lumber per prompt'),
        'hood_of_cunning':     dict(name='Hood of Cunning',       r='common',    e='gold_bonus',      v=2,    desc='+2 bonus gold per task'),
        'medallion':           dict(name='Medallion of Courage',   r='common',    e='gold_bonus',      v=2,    desc='+2 bonus gold per task'),
        'tome_of_power':       dict(name='Tome of Power +2',      r='common',    e='gold_bonus',      v=1,    desc='+1 bonus gold per task'),
        'skull_shield':        dict(name='Skull Shield',           r='common',    e='depletion_ext',   v=10,   desc='Gold mine depletion +10 tasks later'),
        'kelen_dagger':        dict(name='Kelen\\'s Dagger of Escape', r='common', e='combo_bonus',     v=1,    desc='Combos count +1 extra'),
        'void_stone':          dict(name='Void Stone',             r='common',    e='lumber_bonus',    v=1,    desc='+1 bonus lumber per prompt'),
        'scroll_of_tp':        dict(name='Scroll of Town Portal',  r='uncommon',  e='consumable',      v='resurrect', desc='Restore combo streak (consumable)'),
        'potion_of_healing':   dict(name='Potion of Healing',      r='uncommon',  e='consumable',      v='heal',      desc='Restore 200 gold (consumable)'),
        'potion_of_mana':      dict(name='Potion of Mana',         r='uncommon',  e='consumable',      v='lumber50',  desc='Gain 50 lumber (consumable)'),
        'boots_of_speed':      dict(name='Boots of Speed',         r='uncommon',  e='lumber_mult',     v=2,    desc='2x lumber from prompts'),
        'periapt_of_vitality': dict(name='Periapt of Vitality',    r='uncommon',  e='depletion_ext',   v=25,   desc='Gold mine depletion +25 tasks later'),
        'pendant_of_energy':   dict(name='Pendant of Energy',      r='uncommon',  e='gold_bonus',      v=5,    desc='+5 bonus gold per task'),
        'tome_of_xp':          dict(name='Tome of Experience',     r='uncommon',  e='consumable',      v='gold500',   desc='Gain 500 gold (consumable)'),
        'helm_of_valor':       dict(name='Helm of Valor',          r='rare',      e='boss_dmg',  v=4,    desc='+4 raid damage'),
        'cloak_of_shadows':    dict(name='Cloak of Shadows',       r='rare',      e='fatigue_immune',  v=1,    desc='Fatigue paused while equipped'),
        'orb_of_fire':         dict(name='Orb of Fire',            r='rare',      e='boss_dmg',    v=3,    desc='+3 raid damage'),
        'gem_of_seeing':       dict(name='Gem of True Seeing',     r='rare',      e='crit_chance',     v=10,   desc='10% chance of 3x gold on task complete'),
        'staff_of_negation':   dict(name='Staff of Negation',      r='rare',      e='gold_bonus',     v=10,   desc='+10 bonus gold per task'),
        'sobi_mask':           dict(name='Sobi Mask',              r='rare',      e='lumber_mult',     v=3,    desc='3x lumber from prompts'),
        'talisman_of_evasion': dict(name='Talisman of Evasion',    r='rare',      e='fatigue_resist',  v=1,    desc='First fatigue per session is free'),
        'ring_of_regen':       dict(name='Ring of Regeneration',    r='rare',      e='gold_bonus',      v=8,    desc='+8 bonus gold per task'),
        'scourge_bone':        dict(name='Scourge Bone Chimes',    r='rare',      e='gold_bonus',      v=8,    desc='+8 bonus gold per task'),
        'shadow_orb':          dict(name='Shadow Orb +10',         r='rare',      e='crit_chance',     v=5,    desc='5% chance of 3x gold on task complete'),
        'lion_horn':           dict(name='Lion Horn of Stormwind',  r='rare',      e='depletion_ext',   v=15,   desc='Gold mine depletion +15 tasks later'),
        'crown_of_kings':      dict(name='Crown of Kings +5',      r='epic',      e='gold_mult',       v=2,    desc='2x all gold income'),
        'mask_of_death':       dict(name='Mask of Death',          r='epic',      e='crit_chance',     v=20,   desc='20% chance of 3x gold on task complete'),
        'amulet_of_spell':     dict(name='Amulet of Spell Shield', r='epic',      e='army_heal',     v=3,    desc='Heal army 3 HP per task'),
        'khadgars_pipe':       dict(name='Khadgar\'s Pipe',        r='epic',      e='lumber_mult',     v=5,    desc='5x lumber from prompts'),
        'frostmourne':         dict(name='Frostmourne',            r='legendary', e='boss_dmg',         v=20,   desc='+20 raid damage. The blade hungers.'),
        'wirts_leg':           dict(name='Wirt\'s Leg',            r='legendary', e='none',             v=0,    desc='Does absolutely nothing. Peon confused.'),
        'thunderfury':         dict(name='Thunderfury, Blessed Blade of the Windseeker', r='legendary', e='boss_dot', v=10, desc='Poison: 10 damage per event. Did someone say Thunderfury?'),
        'unstoppable_force':   dict(name='The Unstoppable Force',  r='legendary', e='combo_persist',    v=1,    desc='Combos never break from errors'),
        'azzinoth_blades':     dict(name='Warglaives of Azzinoth', r='legendary', e='combo_bonus',     v=2,    desc='+2 combo per task. You are not prepared.'),
        'ashbringer':          dict(name='Ashbringer',             r='legendary', e='crit_chance',      v=25,   desc='25% chance of 3x gold. Holy light!'),
        'inv_potion':          dict(name='Potion of Invisibility', r='rare',      e='consumable',      v='gold1500', desc='Gain 1500 gold (consumable)'),
        'ankh':                dict(name='Ankh of Reincarnation',  r='epic',      e='consumable',      v='gold5000',   desc='Gain 5000 gold (consumable)'),
        'cheese':              dict(name='Cheese',                 r='legendary', e='consumable',      v='cheese',   desc='Restore 10000 gold + 5000 lumber. Mmm.'),
        'scroll_of_heal':      dict(name='Scroll of Healing',      r='uncommon',  e='consumable',      v='heal_15',    desc='Heal all army units 15 HP (consumable)'),
        'healing_ward':        dict(name='Healing Ward',            r='rare',      e='consumable',      v='heal_full',  desc='Fully heal all army units (consumable)'),
        'firebolt':            dict(name='Firebolt',               r='common',    e='consumable',      v='boss_5',     desc='Deal 5 damage to active boss (consumable)'),
        'goblin_sapper':       dict(name='Goblin Sapper Charge',   r='uncommon',  e='consumable',      v='boss_10',    desc='Deal 10 damage to active boss (consumable)'),
        'storm_bolt':          dict(name='Storm Bolt',             r='uncommon',  e='consumable',      v='boss_25',    desc='Deal 25 damage to active boss (consumable)'),
        'demolisher_shot':     dict(name='Demolisher Shot',        r='rare',      e='consumable',      v='boss_50',    desc='Deal 50 damage to active boss (consumable)'),
        'thunder_clap':        dict(name='Thunder Clap',           r='rare',      e='consumable',      v='boss_75',    desc='Deal 75 damage to active boss (consumable)'),
        'chain_lightning':     dict(name='Chain Lightning',        r='epic',      e='consumable',      v='boss_200',   desc='Deal 200 damage to active boss (consumable)'),
        'death_coil':          dict(name='Death Coil',             r='epic',      e='consumable',      v='boss_500',   desc='Deal 500 damage to active boss (consumable)'),
        'finger_of_death':     dict(name='Finger of Death',        r='epic',      e='consumable',      v='boss_1000',  desc='Deal 1000 damage to active boss (consumable)'),
        'doom':                dict(name='Doom',                   r='legendary', e='consumable',      v='boss_4000',  desc='Deal 4000 damage to active boss (consumable)'),
        'war_axe':             dict(name='War Axe',                r='common',    e='boss_dmg',        v=1,    desc='+1 raid damage per task'),
        'iron_shield':         dict(name='Iron Shield',            r='common',    e='boss_armor',      v=25,   desc='25% less gold lost from counter-attacks'),
        'serrated_blade':      dict(name='Serrated Blade',         r='uncommon',  e='boss_dmg',        v=2,    desc='+2 raid damage per task'),
        'venom_orb':           dict(name='Venom Orb',              r='uncommon',  e='boss_dot',        v=1,    desc='Poison: 1 damage per event during raids'),
        'bloodstone':          dict(name='Bloodstone',             r='rare',      e='boss_combo_dmg',  v=1,    desc='+1 damage per 10 combo in raids'),
        'runed_gauntlets':     dict(name='Runed Gauntlets',        r='rare',      e='boss_crit',       v=15,   desc='+15% crit chance vs bosses'),
        'executioners_blade':  dict(name='Executioner\'s Blade',    r='rare',      e='boss_execute',    v=3,    desc='3x damage when boss below 20% HP'),
        'doom_hammer':         dict(name='Doom Hammer',            r='epic',      e='boss_dmg',        v=10,    desc='+10 raid damage per task'),
        'black_arrow':         dict(name='Black Arrow',            r='epic',      e='boss_dot',        v=3,    desc='+3 poison per event + 1 flat raid damage'),
        'sulfuras':            dict(name='Sulfuras, Hand of Ragnaros', r='legendary', e='boss_dmg',    v=10,   desc='+10 raid damage. Overkill carries to next boss.'),
        'kobold_candle':       dict(name='Kobold\'s Candle',        r='common',    e='boss_gold',       v=3,    desc='+3g per task during boss fights'),
        'troll_totem':         dict(name='Troll Regeneration Totem', r='uncommon', e='boss_regen',     v=1,    desc='Repair 1 durability per 5 tasks'),
        'ogre_scepter':        dict(name='Ogre Magi Scepter',      r='rare',      e='boss_dmg',        v=3,    desc='+3 raid damage per task'),
        'infernal_core':       dict(name='Infernal Core',          r='rare',      e='boss_armor',      v=50,   desc='Counter-attacks deal 50% less gold damage'),
        'mannoroths_blood':    dict(name='Mannoroth\'s Blood',      r='epic',      e='boss_execute',    v=5,    desc='5x damage when boss below 20% HP'),
        'crown_of_eredar':     dict(name='Crown of the Eredar',    r='legendary', e='boss_double_loot', v=1,   desc='+1 bonus drop from bosses'),
        'helm_of_domination':  dict(name='Helm of Domination',    r='legendary', e='boss_double_loot', v=2,   desc='+2 bonus drops from bosses'),
    }

    _DROP_TABLE = {
        'common':    dict(weight=300),
        'uncommon':  dict(weight=125),
        'rare':      dict(weight=50),
        'epic':      dict(weight=20),
        'legendary': dict(weight=1),
    }

    inventory = state.get('inventory', [])
    equipped = state.get('equipped', [])
    item_drop = ''

    _has_blacksmith = 'blacksmith' in buildings
    _durability = state.get('item_durability', {})
    _MAX_DUR = {'common': 50, 'uncommon': 75, 'rare': 100, 'epic': 150, 'legendary': 200}

    for _eid in equipped:
        if _eid not in _durability:
            _r = _ITEMS.get(_eid, {}).get('r', 'common')
            _durability[_eid] = _MAX_DUR.get(_r, 50)

    if (category == 'task.complete' or event == 'Stop') and equipped:
        _dur_step = 6 if _has_blacksmith else 2
        _dur_tick = state.get('_dur_tick', 0) + 1
        state['_dur_tick'] = _dur_tick
        if _dur_tick % _dur_step == 0:
            for _eid in equipped:
                if _eid in _durability and _durability[_eid] > 0:
                    _durability[_eid] -= 1
        state['item_durability'] = _durability
        state_dirty = True

    def _has_effect(eff):
        for eid in equipped:
            if _durability.get(eid, 1) <= 0:
                continue
            it = _ITEMS.get(eid)
            if it and it['e'] == eff:
                return it['v']
        return 0

    _TROPHY_IDS = {'kobold_candle', 'troll_totem', 'ogre_scepter', 'infernal_core', 'mannoroths_blood', 'crown_of_eredar', 'helm_of_domination'}
    def _roll_drop(force_rarity=None):
        if force_rarity:
            pool = [k for k, v in _ITEMS.items() if v['r'] == force_rarity and k not in _TROPHY_IDS]
        else:
            avail = {r: [] for r in _DROP_TABLE}
            for k, v in _ITEMS.items():
                if v['r'] in avail and k not in _TROPHY_IDS:
                    avail[v['r']].append(k)
            weights = [(r, d['weight']) for r, d in _DROP_TABLE.items() if avail.get(r)]
            if not weights:
                return None
            total_w = sum(w for _, w in weights)
            r = random.random() * total_w
            cumul = 0
            picked_rarity = weights[0][0]
            for rarity, w in weights:
                cumul += w
                if r <= cumul:
                    picked_rarity = rarity
                    break
            pool = avail[picked_rarity]
        if pool:
            return random.choice(pool)
        return None

    # Apply equipped item effects
    if econ_on and equipped:
        gb = _has_effect('gold_bonus')
        if gb and gold_delta > 0:
            gold_delta += gb
        gm = _has_effect('gold_mult')
        if gm and gold_delta > 0:
            gold_delta = int(gold_delta * gm)
        lb = _has_effect('lumber_bonus')
        if lb and lumber_delta > 0:
            lumber_delta += lb
        lm = _has_effect('lumber_mult')
        if lm and lumber_delta > 0:
            lumber_delta = int(lumber_delta * lm)
        fr = _has_effect('fatigue_resist')
        if fr and fatigue > 0 and fatigue <= fr:
            fatigue = max(0, fatigue - 1)
            state['fatigue'] = fatigue
        if _has_effect('crit_chance') and gold_delta > 0 and category == 'task.complete':
            if random.random() < _has_effect('crit_chance') / 100.0:
                gold_delta *= 3
                game_subtitle = (game_subtitle + ' CRITICAL STRIKE! 3x gold!' if game_subtitle else 'CRITICAL STRIKE! 3x gold!')

    # Apply combo item effects
    if equipped:
        if _has_effect('fatigue_immune') and not in_bunker:
            in_bunker = True
        if _has_effect('combo_persist') and combo_text and 'broken' in combo_text:
            combo_text = ''
            combo = state.get('combo_count', 0)
        cb = _has_effect('combo_bonus')
        if cb and combo > 0 and category == 'task.complete' and event == 'Stop':
            combo += cb
            state['combo_count'] = combo

    # --- Lumber Mill: 2x lumber ---
    if 'lumber_mill' in buildings and lumber_delta > 0:
        lumber_delta *= 2

    def _sum_effect(eff):
        total = 0
        for eid in equipped:
            if _durability.get(eid, 1) <= 0:
                continue
            it = _ITEMS.get(eid)
            if it and it['e'] == eff:
                total += it['v']
        return total

    # --- Boss raid combat ---
    import datetime as _dt
    _boss = state.get('active_boss')
    boss_text = ''
    _TROPHY_MAP = {'kobold': 'kobold_candle', 'troll': 'troll_totem', 'ogre': 'ogre_scepter', 'tichondrius': 'infernal_core', 'mannoroth': 'mannoroths_blood', 'archimonde': 'crown_of_eredar', 'lich_king': 'helm_of_domination'}
    if _boss and 'dark_portal' in buildings:
        _boss_dl = _dt.date.fromisoformat(_boss['deadline'])
        _boss_today = _dt.date.today()
        _days_left = (_boss_dl - _boss_today).days
        if _boss_dl < _boss_today:
            penalty = _boss.get('entry_fee', 0) // 2
            gold_delta -= penalty
            boss_text = f'{_boss[\"name\"]} escaped! -{penalty}g'
            hist = state.get('boss_history', [])
            hist.append(dict(id=_boss['id'], name=_boss['name'], result='escaped', penalty=penalty, t=int(time.time())))
            if len(hist) > 30: hist = hist[-30:]
            state['boss_history'] = hist
            if _boss['id'] == 'whelps' and _boss.get('hp', 0) <= _boss.get('max_hp', 1) * 0.2:
                stats['whelp_leeroy'] = True
            state['active_boss'] = None
            _boss = None
            state_dirty = True
        elif category:
            
            _bdmg = 0
            _bcounter = ''
            _bk = {}
            if category == 'task.complete' or event == 'Stop':
                _bdmg = 1
                _bk['base'] = 1
                if combo > 0:
                    _cb = combo // 10
                    _bdmg += _cb
                    if _cb: _bk['combo'] = _cb
                _bi = _sum_effect('boss_dmg')
                _bdmg += _bi
                if _bi: _bk['items'] = _bi
                if _ITEMS.get('black_arrow', {}).get('e') == 'boss_dot':
                    ba_dmg = _sum_effect('boss_dot')
                    if ba_dmg:
                        for eid in equipped:
                            it = _ITEMS.get(eid)
                            if it and it['e'] == 'boss_dot' and eid == 'black_arrow' and _durability.get(eid, 1) > 0:
                                _bdmg += 1
                                _bk['items'] = _bk.get('items', 0) + 1
                _bcombo = _sum_effect('boss_combo_dmg')
                if _bcombo and combo > 0:
                    _bc2 = _bcombo * (combo // 10)
                    _bdmg += _bc2
                    if _bc2: _bk['bloodstone'] = _bc2
                _army = state.get('army', {})
                _UNIT_HP_R = dict(grunt=30, raider=50, tauren=80, shaman=20)
                for _uk in list(_army.keys()):
                    if isinstance(_army[_uk], int): _army[_uk] = [_UNIT_HP_R.get(_uk, 30)] * _army[_uk]
                _UNIT_DMG = dict(grunt=1, raider=4, tauren=10, shaman=0)
                _army_dmg = sum(_UNIT_DMG.get(uid, 0) * len(hps) for uid, hps in _army.items())
                if _army_dmg > 0:
                    _bdmg += _army_dmg
                    _bk['army'] = _army_dmg
                if _sum_effect('boss_dmg_mult'):
                    _bdmg *= _sum_effect('boss_dmg_mult')
                if _boss['hp'] <= _boss['max_hp'] * 0.2:
                    _bexec = _sum_effect('boss_execute')
                    if _bexec:
                        _pre = _bdmg
                        _bdmg *= _bexec
                        _bk['execute'] = _bdmg - _pre
                crit_pct = _has_effect('crit_chance') + _sum_effect('boss_crit')
                if crit_pct and random.random() < crit_pct / 100.0:
                    _pre = _bdmg
                    _bdmg *= 3
                    _bk['crit'] = _bdmg - _pre
                    _bcounter += ' CRIT!'
                if fatigue >= _fatigue_exhaust:
                    _bdmg = 0
                    _bk = {'exhausted': True}
                    _bcounter += ' EXHAUSTED! 0 dmg'
                elif fatigue >= _fatigue_thresh:
                    _lost = _bdmg - max(1, _bdmg // 2)
                    _bdmg = max(1, _bdmg // 2)
                    _bk['tired'] = -_lost
                    _bcounter += ' Tired! Half dmg'
                _boss_gold = _sum_effect('boss_gold')
                if _boss_gold and econ_on:
                    gold_delta += _boss_gold
            elif category in ('task.error', 'resource.limit'):
                if category == 'resource.limit':
                    for _eid in equipped:
                        if _eid in _durability and _durability[_eid] > 0:
                            _durability[_eid] = max(0, _durability[_eid] - 1)
                    state['item_durability'] = _durability
            else:
                _dot = _sum_effect('boss_dot')
                if _dot:
                    _bdmg += _dot
            _boss['hp'] = max(0, _boss['hp'] - _bdmg)
            _blog = _boss.get('log', [])
            _bentry = dict(t=int(time.time()), dmg=_bdmg, hp=_boss['hp'], bk=_bk)
            if _bcounter:
                _bentry['counter'] = _bcounter.strip()
            if _bdmg > 0 and combo > 0:
                _bentry['combo'] = combo
            _batk_min = _boss.get('atk_min', 0)
            _batk_max = _boss.get('atk_max', 0)
            _army = state.get('army', {})
            _UHP = dict(grunt=30, raider=50, tauren=80, shaman=20)
            for _uk in list(_army.keys()):
                if isinstance(_army[_uk], int): _army[_uk] = [_UHP.get(_uk, 30)] * _army[_uk]
            if _batk_max > 0 and _army and _boss['hp'] > 0:
                _bdmg_roll = random.randint(_batk_min, _batk_max)
                if _bdmg_roll > 0:
                    for _ in range(_bdmg_roll):
                        _living = [(u, i) for u in _army for i in range(len(_army[u])) if _army[u][i] > 0]
                        if not _living:
                            break
                        _tu, _ti = random.choice(_living)
                        _army[_tu][_ti] -= 1
                    _n_shamans = len([h for h in _army.get('shaman', []) if h > 0])
                    _heal_pool = sum(random.randint(1, 3) for _ in range(_n_shamans))
                    while _heal_pool > 0:
                        _worst = (None, -1, 0)
                        for _huid in _army:
                            _mhp = _UHP.get(_huid, 3)
                            for _hi, _hh in enumerate(_army[_huid]):
                                if 0 < _hh < _mhp and (_mhp - _hh) > _worst[2]:
                                    _worst = (_huid, _hi, _mhp - _hh)
                        if _worst[0] is None:
                            break
                        _army[_worst[0]][_worst[1]] += 1
                        _heal_pool -= 1
                    _dead = {}
                    for _duid in list(_army.keys()):
                        _alive = [h for h in _army[_duid] if h > 0]
                        _dk = len(_army[_duid]) - len(_alive)
                        if _dk > 0:
                            _dead[_duid] = _dk
                        if _alive:
                            _army[_duid] = _alive
                        else:
                            del _army[_duid]
                    state['army'] = _army
                    _actual_lost = sum(_dead.values())
                    if _actual_lost > 0:
                        stats['units_lost_total'] = stats.get('units_lost_total', 0) + _actual_lost
                        _bcounter += ' Boss kills: ' + ', '.join(f'{c}x {u}' for u, c in _dead.items())
                        _bentry['boss_atk'] = _actual_lost
                    _bentry['boss_dmg'] = _bdmg_roll
            _blog.append(_bentry)
            if len(_blog) > 50:
                _blog = _blog[-50:]
            _boss['log'] = _blog
            state['active_boss'] = _boss
            state_dirty = True
            if _boss['hp'] <= 0:
                _reward_g = _boss.get('gold_reward', 100)
                _reward_l = _boss.get('lumber_reward', 50)
                if econ_on:
                    gold_delta += _reward_g
                    lumber_delta += _reward_l
                boss_kills = state.get('boss_kills', {})
                bid = _boss['id']
                boss_kills[bid] = boss_kills.get(bid, 0) + 1
                state['boss_kills'] = boss_kills
                state['boss_kills_total'] = state.get('boss_kills_total', 0) + 1
                loot_tiers = _boss.get('loot_tier', ['common'])
                if isinstance(loot_tiers, str):
                    loot_tiers = [loot_tiers]
                drop_names = []
                for _lt in loot_tiers:
                    d = _roll_drop(force_rarity=_lt)
                    if d:
                        inventory.append(d)
                        drop_names.append(_ITEMS[d]['name'])
                        stats['total_items_looted'] = stats.get('total_items_looted', 0) + 1
                if _has_effect('boss_double_loot') and loot_tiers:
                    d2 = _roll_drop(force_rarity=loot_tiers[0])
                    if d2:
                        inventory.append(d2)
                        drop_names.append(_ITEMS[d2]['name'])
                        stats['total_items_looted'] = stats.get('total_items_looted', 0) + 1
                trophy = _TROPHY_MAP.get(bid)
                if trophy and random.random() < 0.3:
                    inventory.append(trophy)
                    drop_names.append(_ITEMS[trophy]['name'] + ' (TROPHY)')
                    stats['total_items_looted'] = stats.get('total_items_looted', 0) + 1
                state['inventory'] = inventory
                overkill = abs(_boss['hp'])
                has_cleave = any(_ITEMS.get(eid, {}).get('e') == 'boss_dmg' and eid == 'sulfuras' and _durability.get(eid, 1) > 0 for eid in equipped)
                if has_cleave and overkill > 0:
                    state['boss_carryover'] = overkill
                _kill_time = time.time() - _boss.get('spawned_at', time.time())
                _deadline_secs = (_boss.get('days', 1) if isinstance(_boss.get('days'), int) else int(_boss['deadline'][:10].replace('-','')) - int(str(_boss.get('spawned_at',0))[:10])) * 86400
                _deadline_secs = max(1, int((_dt.date.fromisoformat(_boss['deadline']) - _dt.date.fromtimestamp(_boss.get('spawned_at', time.time()))).days) * 86400)
                _pct_used = _kill_time / _deadline_secs if _deadline_secs > 0 else 1.0
                if _pct_used < stats.get('fastest_kill_pct', 1.0):
                    stats['fastest_kill_pct'] = round(_pct_used, 3)
                if _kill_time < stats.get('fastest_kill_secs', 99999):
                    stats['fastest_kill_secs'] = int(_kill_time)
                if bid == 'lich_king' and _pct_used < stats.get('fastest_lich_king_pct', 1.0):
                    stats['fastest_lich_king_pct'] = round(_pct_used, 3)
                hist = state.get('boss_history', [])
                hist.append(dict(id=bid, name=_boss['name'], result='victory', gold=_reward_g, lumber=_reward_l, drops=drop_names, t=int(time.time()), pct=round(_pct_used, 3)))
                if len(hist) > 30: hist = hist[-30:]
                state['boss_history'] = hist
                state['active_boss'] = None
                drops_str = ', '.join(drop_names) if drop_names else 'none'
                boss_text = f'{_boss[\"name\"]} DEFEATED! +{_reward_g}g +{_reward_l}l | Drops: {drops_str}'
            else:
                pct = _boss['hp'] / _boss['max_hp']
                bar_len = 12
                filled = int(pct * bar_len)
                bar = chr(9608) * filled + chr(9617) * (bar_len - filled)
                dmg_str = f' -{_bdmg} HP' if _bdmg > 0 else ''
                boss_text = f'{_boss[\"name\"]} [{bar}] {_boss[\"hp\"]}/{_boss[\"max_hp\"]}{dmg_str}{_bcounter} ({_days_left}d left)'
            _tregen = _sum_effect('boss_regen')
            if _tregen:
                _regen_tick = state.get('_boss_regen_tick', 0) + 1
                state['_boss_regen_tick'] = _regen_tick
                if _regen_tick % 5 == 0:
                    for _eid in equipped:
                        if _eid in _durability:
                            _r = _ITEMS.get(_eid, {}).get('r', 'common')
                            _mx = _MAX_DUR.get(_r, 50)
                            if _durability[_eid] < _mx:
                                _durability[_eid] = min(_mx, _durability[_eid] + _tregen)
                    state['item_durability'] = _durability

            _army_heal = _sum_effect('army_heal')
            if _army_heal and _army:
                _aheal_tick = state.get('_army_heal_tick', 0) + 1
                state['_army_heal_tick'] = _aheal_tick
                for uid, hps in _army.items():
                    max_hp = _UHP.get(uid, 30)
                    for i in range(len(hps)):
                        if hps[i] < max_hp:
                            hps[i] = min(max_hp, hps[i] + _army_heal)
                state['army'] = _army

    elif _boss and 'dark_portal' not in buildings:
        pass

    # --- Finalize gold/lumber (after item effects) ---
    if econ_on:
        gold += gold_delta
        lumber += lumber_delta
        if gold <= -500 and not econ.get('debt_interest'):
            econ['debt_interest'] = True
        if gold_delta > 0:
            stats['total_gold_earned'] = stats.get('total_gold_earned', 0) + gold_delta
        if lumber_delta > 0:
            stats['total_lumber_earned'] = stats.get('total_lumber_earned', 0) + lumber_delta
        econ['gold'] = gold
        econ['lumber'] = lumber

    # Drop check
    drop_chance = 0
    if category == 'task.complete':
        drop_chance = 0.025
        if combo >= 100:
            drop_chance *= 1.5
        elif combo >= 50:
            drop_chance *= 1.2
        elif combo >= 10:
            drop_chance *= 1.1
    elif new_achiev:
        drop_chance = 0.5
    if 'citadel' in buildings and drop_chance > 0:
        drop_chance = min(1.0, drop_chance * 2)

    if drop_chance > 0 and random.random() < drop_chance:
        dropped = _roll_drop()
        if dropped:
            inventory.append(dropped)
            stats['total_items_looted'] = stats.get('total_items_looted', 0) + 1
            it = _ITEMS[dropped]
            rarity_names = dict(common='Common', uncommon='Uncommon', rare='Rare', epic='Epic', legendary='LEGENDARY')
            item_drop = 'ITEM DROP: ' + it['name'] + ' (' + rarity_names.get(it['r'], it['r']) + ') - ' + it['desc']
            state['inventory'] = inventory

    state['inventory'] = inventory
    state['equipped'] = equipped
    _item_count = len(inventory) + len(equipped)
    if _item_count > stats.get('max_items_owned', 0):
        stats['max_items_owned'] = _item_count

    # --- Build activity log entry ---
    if category and econ_on:
        entry = dict(t=int(time.time()), e=category, g=gold_delta, l=lumber_delta)
        if combo_text:
            entry['c'] = combo_text
        if new_achiev:
            entry['a'] = new_achiev
        if item_drop:
            entry['i'] = item_drop
        if level_up_text:
            entry['lv'] = level_up_text
        log.append(entry)
        if len(log) > 50:
            log = log[-50:]
        state['activity_log'] = log

    # --- Fatigue notification color/text ---
    if fatigue >= _fatigue_exhaust and category == 'task.complete':
        notify_color = 'red'
        game_subtitle = (game_subtitle + ' ' if game_subtitle else '') + 'EXHAUSTED! 0 gold. peon rest to recover.'
    elif fatigue >= _fatigue_thresh and category == 'task.complete':
        notify_color = 'yellow'
        game_subtitle = (game_subtitle + ' ' if game_subtitle else '') + f'Tired ({fatigue}). Half gold.'

    # --- Compose game notification ---
    parts = []
    if boss_text:
        parts.append(boss_text)
    if level_up_text:
        parts.append(level_up_text)
    if item_drop:
        _drop_short = item_drop.split(' - ')[0] if ' - ' in item_drop else item_drop
        parts.append(_drop_short)
    if new_achiev:
        parts.append(new_achiev)
    if combo_text:
        parts.append(combo_text)
    if game_event_text:
        parts.append(game_event_text)
    if game_subtitle:
        parts.append(game_subtitle)
    if econ_on and gold_delta != 0:
        sign = '+' if gold_delta > 0 else ''
        parts.append(f'{sign}{gold_delta}g')
    if time_text:
        parts.append(time_text)
    game_notify = ' | '.join(parts) if parts else ''

    state['stats'] = stats
    state['economy'] = econ
    state['buildings'] = buildings
    state_dirty = True

# --- Trainer reminder check ---
trainer_sound = ''
trainer_msg = ''
trainer_cfg = cfg.get('trainer', {})
if trainer_cfg.get('enabled', False):
    from datetime import date as _date
    today = _date.today().isoformat()
    trainer_state = state.get('trainer', {})
    _default_ex = dict(pushups=300, squats=300)
    if trainer_state.get('date') != today:
        exercises = trainer_cfg.get('exercises', _default_ex)
        trainer_state = dict(date=today, reps=dict.fromkeys(exercises, 0), last_reminder_ts=0)
    exercises = trainer_cfg.get('exercises', _default_ex)
    reps = trainer_state.get('reps', {})
    all_done = all(reps.get(ex, 0) >= goal for ex, goal in exercises.items())
    if not all_done:
        now_ts = time.time()
        last_ts = trainer_state.get('last_reminder_ts', 0)
        interval = trainer_cfg.get('reminder_interval_minutes', 20) * 60
        min_gap = trainer_cfg.get('reminder_min_gap_minutes', 5) * 60
        elapsed = now_ts - last_ts
        is_session_start = (event == 'SessionStart')
        if is_session_start or (elapsed >= interval and elapsed >= min_gap):
            trainer_manifest_path = os.path.join(peon_dir, 'trainer', 'manifest.json')
            try:
                tm = json.load(open(trainer_manifest_path))
                if is_session_start:
                    tcat = 'trainer.session_start'
                else:
                    import datetime
                    hour = datetime.datetime.now().hour
                    total_reps = sum(reps.get(ex, 0) for ex in exercises)
                    total_goal = sum(exercises.values())
                    pct = total_reps / total_goal if total_goal > 0 else 1.0
                    if hour >= 12 and pct < 0.25:
                        tcat = 'trainer.slacking'
                    else:
                        tcat = 'trainer.remind'
                sounds = tm.get(tcat, [])
                if sounds:
                    pick = random.choice(sounds)
                    sfile = os.path.join(peon_dir, 'trainer', pick['file'])
                    if os.path.isfile(sfile):
                        trainer_sound = sfile
                        parts = []
                        for ex, goal in exercises.items():
                            done = reps.get(ex, 0)
                            parts.append(f'{ex}: {done}/{goal}')
                        trainer_msg = ' | '.join(parts)
            except Exception:
                pass
            trainer_state['last_reminder_ts'] = int(now_ts)
            state_dirty = True
    state['trainer'] = trainer_state
    state_dirty = True

# --- Write state once ---
if state_dirty:
    _save_state(state_file, state)

# --- iTerm2 tab color mapping ---
# Configurable via config.json: tab_color.enabled (default true),
# tab_color.colors.(ready|working|done|needs_approval) as [r,g,b] arrays.
tab_color_rgb = ''
if tab_color_enabled:
    default_colors = {
        'ready':          [65, 115, 80],   # muted green
        'working':        [130, 105, 50],  # muted amber
        'done':           [65, 100, 140],  # muted blue
        'needs_approval': [150, 70, 70],   # muted red
    }
    custom = tab_color_cfg.get('colors', {})
    color_profiles = tab_color_cfg.get('color_profiles', {})
    if project in color_profiles and isinstance(color_profiles[project], dict):
        custom = dict(custom, **color_profiles[project])
    colors = dict((k, custom.get(k, v)) for k, v in default_colors.items())
    status_key = status.replace(' ', '_') if status else ''
    if status_key in colors:
        rgb = colors[status_key]
        tab_color_rgb = f'{rgb[0]} {rgb[1]} {rgb[2]}'

# --- Output shell variables ---
print('PEON_EXIT=' + ('true' if _agent_silent else 'false'))
print('EVENT=' + q(event))
print('VOLUME=' + q(str(volume)))
print('PROJECT=' + q(project))
print('STATUS=' + q(status))
print('MARKER=' + q(marker))
print('NOTIFY=' + q(notify))
print('NOTIFY_COLOR=' + q(notify_color))
print('MSG=' + q(msg))
print('DESKTOP_NOTIF=' + ('true' if desktop_notif else 'false'))
print('NOTIFY_ALWAYS=' + ('true' if notify_always else 'false'))
print('NOTIF_STYLE=' + q(cfg.get('notification_style', 'overlay')))
print('USE_SOUND_EFFECTS_DEVICE=' + q(str(use_sound_effects_device).lower()))
print('LINUX_AUDIO_PLAYER=' + q(linux_audio_player))
mn = cfg.get('mobile_notify', {})
mobile_on = bool(mn and mn.get('service') and mn.get('enabled', True))
print('MOBILE_NOTIF=' + ('true' if mobile_on else 'false'))
print('SOUND_FILE=' + q(sound_file))
print('ICON_PATH=' + q(icon_path))
print('TRAINER_SOUND=' + q(trainer_sound))
print('TRAINER_MSG=' + q(trainer_msg))
print('TAB_COLOR_RGB=' + q(tab_color_rgb))
print('GAME_NOTIFY=' + q(game_notify))
print('GAME_SUBTITLE=' + q(game_subtitle))
print('LEVELUP_SOUND=' + q(levelup_sound if game_on else ''))
print('LEVELUP_DOWNLOAD=' + q(lvl_pack_missing if game_on else ''))
" <<< "$INPUT" 2>>"$PEON_DIR/.error.log")"

# If Python signalled early exit (disabled, agent, unknown event), bail out
[ "${PEON_EXIT:-true}" = "true" ] && exit 0

# --- Check for updates (SessionStart only, once per day, non-blocking) ---
if [ "$EVENT" = "SessionStart" ]; then
  (
    CHECK_FILE="$PEON_DIR/.last_update_check"
    NOW=$(date +%s)
    LAST_CHECK=0
    [ -f "$CHECK_FILE" ] && LAST_CHECK=$(cat "$CHECK_FILE" 2>/dev/null || echo 0)
    ELAPSED=$((NOW - LAST_CHECK))
    # Only check once per day (86400 seconds)
    if [ "$ELAPSED" -gt 86400 ]; then
      echo "$NOW" > "$CHECK_FILE"
      LOCAL_VERSION=""
      [ -f "$PEON_DIR/VERSION" ] && LOCAL_VERSION=$(cat "$PEON_DIR/VERSION" | tr -d '[:space:]')
      REMOTE_VERSION=$(curl -fsSL --connect-timeout 3 --max-time 5 \
        "https://raw.githubusercontent.com/MikeKovetsky/zugzug.sh/main/VERSION" 2>/dev/null | tr -d '[:space:]')
      if [ -n "$REMOTE_VERSION" ] && [ -n "$LOCAL_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
        # Write update notice to a file so we can display it
        echo "$REMOTE_VERSION" > "$PEON_DIR/.update_available"
      else
        rm -f "$PEON_DIR/.update_available"
      fi
    fi
  ) &>/dev/null &
fi

# --- Show update notice (if available, on SessionStart only) ---
if [ "$EVENT" = "SessionStart" ] && [ -f "$PEON_DIR/.update_available" ]; then
  NEW_VER=$(cat "$PEON_DIR/.update_available" 2>/dev/null | tr -d '[:space:]')
  CUR_VER=""
  [ -f "$PEON_DIR/VERSION" ] && CUR_VER=$(cat "$PEON_DIR/VERSION" | tr -d '[:space:]')
  if [ -n "$NEW_VER" ]; then
    echo "peon-ping update available: ${CUR_VER:-?} → $NEW_VER — run: curl -fsSL https://raw.githubusercontent.com/MikeKovetsky/zugzug.sh/main/install.sh | bash" >&2
  fi
fi

# --- Show pause status on SessionStart ---
if [ "$EVENT" = "SessionStart" ] && [ "$PAUSED" = "true" ]; then
  echo "peon-ping: sounds paused — run 'peon resume' or '/peon-ping-toggle' to unpause" >&2
fi

# --- Relay guidance on SessionStart (devcontainer/SSH) ---
# Backgrounded in production to avoid blocking the greeting sound while curl times out.
_relay_guidance() {
  if [ "$PLATFORM" = "devcontainer" ]; then
    RELAY_HOST="${PEON_RELAY_HOST:-host.docker.internal}"
    RELAY_PORT="${PEON_RELAY_PORT:-19998}"
    if ! curl -sf --connect-timeout 1 --max-time 2 "http://${RELAY_HOST}:${RELAY_PORT}/health" >/dev/null 2>&1; then
      echo "peon-ping: devcontainer detected but audio relay not reachable at ${RELAY_HOST}:${RELAY_PORT}" >&2
      echo "peon-ping: run 'peon relay' on your host machine to enable sounds" >&2
    fi
  elif [ "$PLATFORM" = "ssh" ]; then
    RELAY_HOST="${PEON_RELAY_HOST:-localhost}"
    RELAY_PORT="${PEON_RELAY_PORT:-19998}"
    if ! curl -sf --connect-timeout 1 --max-time 2 "http://${RELAY_HOST}:${RELAY_PORT}/health" >/dev/null 2>&1; then
      echo "peon-ping: SSH session detected but audio relay not reachable at ${RELAY_HOST}:${RELAY_PORT}" >&2
      echo "peon-ping: on your LOCAL machine, run: peon relay" >&2
      echo "peon-ping: then reconnect with: ssh -R 19998:localhost:19998 <host>" >&2
    fi
  fi
}
if [ "$EVENT" = "SessionStart" ] && { [ "$PLATFORM" = "devcontainer" ] || [ "$PLATFORM" = "ssh" ]; }; then
  if [ "${PEON_TEST:-0}" = "1" ]; then
    _relay_guidance
  else
    _relay_guidance &
  fi
fi

# --- Build tab title ---
TITLE="${MARKER}${PROJECT}: ${STATUS}"

# --- Set tab title via ANSI escape (works in Warp, iTerm2, Terminal.app, etc.) ---
# Write to /dev/tty so the escape sequence reaches the terminal directly.
# Claude Code captures hook stdout, so plain printf would be swallowed.
if [ -n "$TITLE" ]; then
  printf '\033]0;%s\007' "$TITLE" > /dev/tty 2>/dev/null || true
fi

# --- Set iTerm2 tab color (OSC 6) ---
# Uses /dev/tty for the same reason as tab title above.
# In test mode, write resolved color to file for BATS verification.
[ "${PEON_TEST:-0}" = "1" ] && [ -n "$TAB_COLOR_RGB" ] && echo "$TAB_COLOR_RGB" > "$PEON_DIR/.tab_color_rgb"
[ "${PEON_TEST:-0}" = "1" ] && [ -n "$ICON_PATH" ] && echo "$ICON_PATH" > "$PEON_DIR/.icon_path"
if [ -n "$TAB_COLOR_RGB" ] && [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
  read -r _R _G _B <<< "$TAB_COLOR_RGB"
  printf "\033]6;1;bg;red;brightness;%d\a" "$_R" > /dev/tty 2>/dev/null || true
  printf "\033]6;1;bg;green;brightness;%d\a" "$_G" > /dev/tty 2>/dev/null || true
  printf "\033]6;1;bg;blue;brightness;%d\a" "$_B" > /dev/tty 2>/dev/null || true
fi

_run_sound_and_notify() {
  # --- Play sound ---
  if [ -n "$SOUND_FILE" ] && [ -f "$SOUND_FILE" ]; then
    play_sound "$SOUND_FILE" "$VOLUME"
  fi

  # --- Notification: always show, or only when terminal is not frontmost ---
  if [ -n "$NOTIFY" ] && [ "$PAUSED" != "true" ] && [ "${DESKTOP_NOTIF:-true}" = "true" ]; then
    if [ "${NOTIFY_ALWAYS:-true}" = "true" ] || ! terminal_is_focused; then
      local _notif_msg="$MSG"
      [ -n "${GAME_NOTIFY:-}" ] && _notif_msg="$_notif_msg  —  $GAME_NOTIFY"
      send_notification "$_notif_msg" "$TITLE" "${NOTIFY_COLOR:-red}" "${ICON_PATH:-}"
    fi
  fi

  # --- Mobile push notification (always sends when configured, regardless of focus) ---
  if [ -n "$NOTIFY" ] && [ "$PAUSED" != "true" ] && [ "${MOBILE_NOTIF:-false}" = "true" ]; then
    send_mobile_notification "$MSG" "$TITLE" "${NOTIFY_COLOR:-red}"
  fi
}

# --- Dashboard auto-spawn (zero config: starts on first hook, lives until reboot) ---
_dashboard_port=19997
_dashboard_pid_file="$PEON_DIR/.dashboard.pid"
_dashboard_hash_file="$PEON_DIR/.dashboard.hash"
_maybe_spawn_dashboard() {
  if command -v python3 &>/dev/null && [ -f "$PEON_DIR/dashboard.html" ]; then
    local _cur_hash
    _cur_hash="$(md5sum "${BASH_SOURCE[0]}" 2>/dev/null || md5 -q "${BASH_SOURCE[0]}" 2>/dev/null)" || true
    _cur_hash="${_cur_hash%% *}"
    if curl -sf --connect-timeout 1 --max-time 2 "http://127.0.0.1:$_dashboard_port/" >/dev/null 2>&1; then
      local _old_hash=""
      [ -f "$_dashboard_hash_file" ] && _old_hash="$(cat "$_dashboard_hash_file" 2>/dev/null)"
      if [ -n "$_cur_hash" ] && [ "$_cur_hash" != "$_old_hash" ]; then
        local _pid
        _pid="$(lsof -ti :$_dashboard_port 2>/dev/null)" || true
        [ -n "$_pid" ] && kill "$_pid" 2>/dev/null
        sleep 0.3
      else
        return
      fi
    fi
    # Atomic lock: only one concurrent hook invocation proceeds to spawn+open
    local _lock="$PEON_DIR/.dashboard.lock"
    mkdir "$_lock" 2>/dev/null || return
    # Re-check under lock
    if curl -sf --connect-timeout 1 --max-time 2 "http://127.0.0.1:$_dashboard_port/" >/dev/null 2>&1; then
      rm -rf "$_lock"
      return
    fi
    nohup python3 -c "
import http.server, json, os, sys, socketserver, time, datetime, tempfile, shutil

PORT = $_dashboard_port
PEON_DIR = '$PEON_DIR'
BCOSTS = {'burrow':(500,250),'watch_tower':(750,375),'war_mill':(1000,500),'altar':(1500,750),'lumber_mill':(1500,500),'tavern':(2000,1000),'stronghold':(2500,1000),'spirit_lodge':(2500,1000),'barracks':(3000,1200),'blacksmith':(4000,1500),'arcane_sanctum':(7500,3000),'fortress':(10000,4000),'dark_portal':(12000,5000),'citadel':(15000,6000),'farm':(8000,3000),'goblin_lab':(18000,7000),'world_tree':(25000,10000)}
FARM_MAX = 3

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _json(self, code, data):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    def _load(self, f):
        p = os.path.join(PEON_DIR, f)
        for fp in (p, p + '.bak'):
            try:
                d = json.load(open(fp))
                if isinstance(d, dict): return d
            except Exception: pass
        return {}
    def _save(self, f, d):
        p = os.path.join(PEON_DIR, f)
        dn = os.path.dirname(p) or '.'
        os.makedirs(dn, exist_ok=True)
        if os.path.isfile(p):
            try: shutil.copy2(p, p + '.bak')
            except Exception: pass
        fd, t = tempfile.mkstemp(dir=dn, suffix='.tmp')
        try:
            with os.fdopen(fd, 'w') as fh:
                json.dump(d, fh, indent=2)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(t, p)
        except Exception:
            try: os.unlink(t)
            except Exception: pass
            raise
    def do_GET(self):
        if self.path == '/api/state':
            self._json(200, self._load('.state.json'))
        elif self.path == '/api/config':
            self._json(200, self._load('config.json'))
        elif self.path == '/api/packs':
            pdir = os.path.join(PEON_DIR, 'packs')
            packs = []
            if os.path.isdir(pdir):
                for d in sorted(os.listdir(pdir)):
                    dp = os.path.join(pdir, d)
                    if os.path.isdir(dp) and (os.path.exists(os.path.join(dp, 'openpeon.json')) or os.path.exists(os.path.join(dp, 'manifest.json'))):
                        packs.append(d)
            self._json(200, packs)
        elif self.path == '/' or self.path == '/dashboard':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            try:
                data = open(os.path.join(PEON_DIR, 'dashboard.html')).read()
            except Exception:
                data = '<h1>Dashboard not found</h1>'
            self.wfile.write(data.encode())
        elif self.path == '/raid':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            try: data = open(os.path.join(PEON_DIR, 'raid.html')).read()
            except: data = '<h1>Raid page not found</h1>'
            self.wfile.write(data.encode())
        elif self.path == '/army':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            try: data = open(os.path.join(PEON_DIR, 'army.html')).read()
            except: data = '<h1>Army page not found</h1>'
            self.wfile.write(data.encode())
        elif self.path.startswith('/assets/') and '..' not in self.path:
            fp = os.path.join(PEON_DIR, self.path.lstrip('/'))
            if os.path.isfile(fp):
                ext = os.path.splitext(fp)[1].lower()
                ct = {'.png':'image/png','.jpg':'image/jpeg','.gif':'image/gif','.svg':'image/svg+xml','.webp':'image/webp'}.get(ext,'application/octet-stream')
                self.send_response(200)
                self.send_header('Content-Type', ct)
                self.send_header('Cache-Control','public, max-age=86400')
                self.end_headers()
                with open(fp,'rb') as f: self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(n)) if n else {}
        if self.path == '/api/raid':
            import random as _rr
            bid = body.get('boss', '')
            st = self._load('.state.json')
            BOSSES = {'kobold': dict(hp=40,days=1,unlock_kills=0,unlock_lvl=0,unlock_bld=[],fee=0,loot=['common'],gold_r=50,lumber_r=15,atk_min=0,atk_max=0,name='Kobold Taskmaster'), 'murloc': dict(hp=120,days=1,unlock_kills=0,unlock_lvl=0,unlock_bld=[],fee=0,loot=['common','common'],gold_r=100,lumber_r=30,atk_min=0,atk_max=0,name='Murloc Tidecaller'), 'troll': dict(hp=400,days=2,unlock_kills=1,unlock_lvl=0,unlock_bld=[],fee=50,loot=['uncommon','common'],gold_r=200,lumber_r=75,atk_min=0,atk_max=1,name='Forest Troll Warlord'), 'ogre': dict(hp=1600,days=2,unlock_kills=3,unlock_lvl=0,unlock_bld=[],fee=200,loot=['rare','common'],gold_r=600,lumber_r=200,atk_min=1,atk_max=2,name='Ogre Magi'), 'whelps': dict(hp=3000,days=2,unlock_kills=4,unlock_lvl=0,unlock_bld=[],fee=100,loot=['rare','uncommon','common'],gold_r=800,lumber_r=300,atk_min=1,atk_max=4,name='Dragon Whelp Swarm'), 'naga': dict(hp=6000,days=2,unlock_kills=5,unlock_lvl=5,unlock_bld=[],fee=400,loot=['rare','uncommon','uncommon'],gold_r=1000,lumber_r=400,atk_min=1,atk_max=6,name='Naga Sea Witch'), 'tichondrius': dict(hp=10000,days=2,unlock_kills=7,unlock_lvl=6,unlock_bld=[],fee=750,loot=['rare','rare','uncommon'],gold_r=2500,lumber_r=600,atk_min=2,atk_max=4,name='Tichondrius'), 'illidan': dict(hp=30000,days=3,unlock_kills=10,unlock_lvl=7,unlock_bld=[],fee=1500,loot=['epic','rare','rare','uncommon'],gold_r=4000,lumber_r=1200,atk_min=3,atk_max=7,name='Illidan Stormrage'), 'mannoroth': dict(hp=40000,days=4,unlock_kills=15,unlock_lvl=8,unlock_bld=['citadel'],fee=3000,loot=['epic','rare','rare','uncommon','common','common'],gold_r=10000,lumber_r=3000,atk_min=4,atk_max=10,name='Pit Lord Mannoroth'), 'archimonde': dict(hp=100000,days=7,unlock_kills=20,unlock_lvl=9,unlock_bld=['citadel'],fee=5000,loot=['epic','epic','rare','rare','rare','uncommon','common'],gold_r=15000,lumber_r=5000,atk_min=4,atk_max=15,name='Archimonde'), 'lich_king': dict(hp=1000000,days=14,unlock_kills=30,unlock_lvl=9,unlock_bld=['citadel'],fee=10000,loot=['legendary','epic','epic'],gold_r=50000,lumber_r=15000,atk_min=5,atk_max=20,name='The Lich King')}
            if st.get('active_boss'):
                return self._json(400, {'error': 'Already in a raid'})
            if 'dark_portal' not in st.get('buildings', {}):
                return self._json(400, {'error': 'Build Dark Portal first'})
            if bid not in BOSSES:
                return self._json(400, {'error': 'Unknown boss'})
            b = BOSSES[bid]
            bk = st.get('boss_kills_total', 0)
            lvl = st.get('stats', {}).get('level', 1)
            if bk < b['unlock_kills'] or lvl < b['unlock_lvl']:
                return self._json(400, {'error': 'Boss locked'})
            for rb in b.get('unlock_bld', []):
                if rb not in st.get('buildings', {}):
                    return self._json(400, {'error': f'Need {rb}'})
            ec = st.setdefault('economy', {})
            g = ec.get('gold', 0)
            if g < b['fee']:
                return self._json(400, {'error': f'Need {b[\"fee\"]}g'})
            ec['gold'] = g - b['fee']
            hp = b['hp']
            co = st.get('boss_carryover', 0)
            if co > 0:
                hp = max(1, hp - co)
                st['boss_carryover'] = 0
            dl = (datetime.date.today() + datetime.timedelta(days=b['days'])).isoformat()
            st['active_boss'] = dict(id=bid, name=b['name'], hp=hp, max_hp=hp, deadline=dl, spawned_at=int(time.time()), loot_tier=b['loot'], entry_fee=b['fee'], gold_reward=b['gold_r'], lumber_reward=b['lumber_r'], atk_min=b['atk_min'], atk_max=b['atk_max'])
            st['economy'] = ec
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'boss': st['active_boss'], 'gold': ec['gold']})
        elif self.path == '/api/build':
            bname = body.get('building', '')
            if bname not in BCOSTS:
                return self._json(400, {'error': 'Unknown building'})
            st = self._load('.state.json')
            blds = st.get('buildings', {})
            if bname == 'farm':
                cur = blds.get('farm', {}).get('count', 0) if 'farm' in blds else 0
                if cur >= FARM_MAX:
                    return self._json(400, {'error': 'Farm limit reached'})
            elif bname in blds:
                return self._json(400, {'error': 'Already built'})
            ec = st.get('economy', {})
            g, l = ec.get('gold', 0), ec.get('lumber', 0)
            gc, lc = BCOSTS[bname]
            if st.get('goblin_discount_date', '') == datetime.date.today().isoformat():
                gc //= 2; lc //= 2
            if g < gc or l < lc:
                return self._json(400, {'error': 'Insufficient resources', 'need_gold': gc, 'need_lumber': lc})
            ec['gold'] = g - gc; ec['lumber'] = l - lc
            if bname == 'farm':
                prev = blds.get('farm', {})
                cnt = prev.get('count', 0) + 1
                bld = {'built_at': int(time.time()), 'count': cnt}
                if 'x' in body and 'y' in body: bld['pos'] = [body['x'], body['y']]
                elif 'pos' in prev: bld['pos'] = prev['pos']
            else:
                bld = {'built_at': int(time.time())}
                if 'x' in body and 'y' in body: bld['pos'] = [body['x'], body['y']]
            st.setdefault('buildings', {})[bname] = bld
            st['economy'] = ec
            st.setdefault('stats', {})['buildings_built'] = len(st['buildings'])
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'building': bname, 'gold': ec['gold'], 'lumber': ec['lumber']})
        elif self.path == '/api/bunker':
            st = self._load('.state.json')
            if 'burrow' not in st.get('buildings', {}):
                return self._json(400, {'error': 'Build a Burrow first'})
            now = time.time()
            if st.get('bunker_until', 0) > now:
                return self._json(200, {'active': True, 'minutes_left': int((st['bunker_until'] - now) / 60)})
            st['bunker_until'] = now + 3600
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'bunker_until': st['bunker_until']})
        elif self.path == '/api/config':
            cfg = self._load('config.json')
            for k in ('enabled', 'volume', 'active_pack', 'desktop_notifications'):
                if k in body: cfg[k] = body[k]
            self._save('config.json', cfg)
            self._json(200, {'ok': True})
        elif self.path == '/api/surrender':
            st = self._load('.state.json')
            boss = st.get('active_boss')
            if not boss:
                return self._json(400, {'error': 'No active raid'})
            fee = boss.get('entry_fee', 0)
            penalty = fee // 2
            ec = st.setdefault('economy', {})
            ec['gold'] = ec.get('gold', 0) - penalty
            hist = st.get('boss_history', [])
            hist.append(dict(id=boss['id'], name=boss['name'], result='escaped', penalty=penalty, t=int(time.time())))
            if len(hist) > 30: hist = hist[-30:]
            st['boss_history'] = hist
            if boss['id'] == 'whelps' and boss.get('hp', 0) <= boss.get('max_hp', 1) * 0.2:
                st.setdefault('stats', {})['whelp_leeroy'] = True
            st['economy'] = ec
            st['active_boss'] = None
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'penalty': penalty})
        elif self.path == '/api/resurrect':
            st = self._load('.state.json')
            if 'altar' not in st.get('buildings', {}):
                return self._json(400, {'error': 'Build an Altar first'})
            today = datetime.date.today().isoformat()
            if st.get('last_resurrect_date') == today:
                return self._json(400, {'error': 'Already used today'})
            best = st.get('stats', {}).get('max_combo', 0)
            st['combo_count'] = max(st.get('combo_count', 0), best // 2)
            st['last_resurrect_date'] = today
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'combo': st['combo_count']})
        elif self.path == '/api/rest':
            st = self._load('.state.json')
            f = st.get('fatigue', 0)
            if f == 0:
                return self._json(200, {'ok': True, 'msg': 'Not tired'})
            ec = st.setdefault('economy', {})
            l = ec.get('lumber', 0)
            if l < 20:
                return self._json(400, {'error': 'Need 20 lumber', 'have': l})
            ec['lumber'] = l - 20
            st['fatigue'] = 0
            st['economy'] = ec
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'lumber': ec['lumber']})
        elif self.path == '/api/repair':
            st = self._load('.state.json')
            ec = st.setdefault('economy', {})
            MAXD = {'common':50,'uncommon':75,'rare':100,'epic':150,'legendary':200}
            cost = body.get('cost', 0)
            items = body.get('items', [])
            if not items:
                return self._json(200, {'ok': True, 'msg': 'Nothing to repair'})
            g = ec.get('gold', 0)
            if g < cost:
                return self._json(400, {'error': 'Need ' + str(cost) + 'g', 'have': g})
            ec['gold'] = g - cost
            dur = st.get('item_durability', {})
            for e in items:
                r = body.get('rarities', {}).get(e, 'common')
                dur[e] = MAXD.get(r, 50)
            st['item_durability'] = dur
            st['economy'] = ec
            stats = st.setdefault('stats', {})
            stats['repairs_total'] = stats.get('repairs_total', 0) + len(items)
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'repaired': len(items), 'cost': cost, 'gold': ec['gold']})
        elif self.path == '/api/harvest':
            pos = body.get('pos', '')
            st = self._load('.state.json')
            ec = st.setdefault('economy', {})
            for key in ('lumber_nodes', 'gold_nodes'):
                nodes = st.get(key, [])
                for i, n in enumerate(nodes):
                    if n.get('pos') == pos:
                        res = 'lumber' if 'lumber' in key else 'gold'
                        ec[res] = ec.get(res, 0) + n['amt']
                        nodes.pop(i)
                        st[key] = nodes
                        self._save('.state.json', st)
                        return self._json(200, {'ok': True, 'resource': res, 'amount': n['amt']})
            self._json(400, {'error': 'No harvestable node at that position'})
        elif self.path == '/api/equip':
            iid = body.get('item', '')
            st = self._load('.state.json')
            inv = st.get('inventory', [])
            eq = st.get('equipped', [])
            if iid not in inv:
                return self._json(400, {'error': 'Item not in backpack'})
            if len(eq) >= 6:
                return self._json(400, {'error': 'Equipment full (6/6)'})
            inv.remove(iid)
            eq.append(iid)
            st['inventory'] = inv; st['equipped'] = eq
            self._save('.state.json', st)
            self._json(200, {'ok': True})
        elif self.path == '/api/unequip':
            iid = body.get('item', '')
            st = self._load('.state.json')
            inv = st.get('inventory', [])
            eq = st.get('equipped', [])
            if iid not in eq:
                return self._json(400, {'error': 'Item not equipped'})
            eq.remove(iid)
            inv.append(iid)
            st['inventory'] = inv; st['equipped'] = eq
            self._save('.state.json', st)
            self._json(200, {'ok': True})
        elif self.path == '/api/use':
            iid = body.get('item', '')
            st = self._load('.state.json')
            inv = st.get('inventory', [])
            eq = st.get('equipped', [])
            if iid not in inv and iid not in eq:
                return self._json(400, {'error': 'Item not found'})
            ec = st.setdefault('economy', {})
            boss_items = {'firebolt':50,'goblin_sapper':100,'storm_bolt':250,'demolisher_shot':500,'thunder_clap':750,'chain_lightning':2000,'death_coil':5000,'finger_of_death':10000,'doom':40000}
            if iid in boss_items:
                boss = st.get('active_boss')
                if not boss or boss.get('hp', 0) <= 0:
                    return self._json(400, {'error': 'No active boss'})
                dmg = boss_items[iid]
                boss['hp'] = max(0, boss['hp'] - dmg)
                log = boss.get('log', [])
                log.append({'t': int(time.time()), 'dmg': dmg, 'hp': boss['hp'], 'bk': {'item_use': dmg}, 'item': iid})
                if len(log) > 50: log = log[-50:]
                boss['log'] = log
                if iid in inv: inv.remove(iid)
                elif iid in eq: eq.remove(iid)
                st['inventory'] = inv; st['equipped'] = eq
                if boss['hp'] <= 0:
                    st['active_boss'] = None
                else:
                    st['active_boss'] = boss
                self._save('.state.json', st)
                self._json(200, {'ok': True, 'dmg': dmg, 'hp': boss['hp'], 'killed': boss['hp'] <= 0})
                return
            def _dash_heal(state, amount):
                army = state.get('army', {})
                if not army: return
                _UNIT_HP = {'grunt': 30, 'raider': 50, 'tauren': 80, 'shaman': 20}
                for uid, hps in army.items():
                    mx = _UNIT_HP.get(uid, 30)
                    for i in range(len(hps)): hps[i] = min(mx, hps[i] + amount)
                state['army'] = army

            cons = {
                'scroll_of_tp':      lambda: st.update(combo_count=max(st.get('combo_count',0), st.get('stats',{}).get('max_combo',0)//2)),
                'potion_of_healing':  lambda: ec.update(gold=ec.get('gold',0)+200),
                'potion_of_mana':     lambda: ec.update(lumber=ec.get('lumber',0)+50),
                'tome_of_xp':        lambda: ec.update(gold=ec.get('gold',0)+500),
                'liquid_fire':        lambda: ec.update(gold=ec.get('gold',0)+150),
                'inv_potion':         lambda: ec.update(gold=ec.get('gold',0)+1500),
                'invuln_potion':      lambda: (ec.update(gold=ec.get('gold',0)+3000), ec.update(lumber=ec.get('lumber',0)+1000)),
                'ankh':               lambda: ec.update(gold=ec.get('gold',0)+5000),
                'ensnare_trap':       lambda: _dash_heal(st, 50),
                'scroll_of_heal':     lambda: _dash_heal(st, 15),
                'healing_ward':       lambda: _dash_heal(st, 999),
                'cheese':             lambda: (ec.update(gold=ec.get('gold',0)+10000), ec.update(lumber=ec.get('lumber',0)+5000)),
            }
            if iid not in cons:
                return self._json(400, {'error': 'Not consumable'})
            cons[iid]()
            if iid in inv: inv.remove(iid)
            elif iid in eq: eq.remove(iid)
            st['inventory'] = inv; st['equipped'] = eq
            self._save('.state.json', st)
            self._json(200, {'ok': True})
        elif self.path == '/api/sell':
            iid = body.get('item', '')
            st = self._load('.state.json')
            inv = st.get('inventory', [])
            if iid not in inv:
                eq = st.get('equipped', [])
                if iid in eq:
                    return self._json(400, {'error': 'Unequip it first'})
                return self._json(400, {'error': 'Item not in backpack'})
            SELL_PRICE = {'common': 10, 'uncommon': 20, 'rare': 40, 'epic': 80, 'legendary': 200}
            r = body.get('rarity', 'common')
            price = SELL_PRICE.get(r, 10)
            inv.remove(iid)
            ec = st.setdefault('economy', {})
            ec['gold'] = ec.get('gold', 0) + price
            dur = st.get('item_durability', {})
            dur.pop(iid, None)
            st['inventory'] = inv
            st['item_durability'] = dur
            st['economy'] = ec
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'price': price, 'gold': ec['gold']})
        elif self.path == '/api/hire':
            uid = body.get('unit', '')
            cnt = max(1, int(body.get('count', 1)))
            UNITS = {'grunt':(100,0,2,30),'raider':(400,100,3,50),'tauren':(1000,400,5,80),'shaman':(300,100,2,20)}
            if uid not in UNITS:
                return self._json(400, {'error': 'Unknown unit'})
            st = self._load('.state.json')
            if 'barracks' not in st.get('buildings', {}):
                return self._json(400, {'error': 'Build Barracks first'})
            ug, ul, uf, uhp = UNITS[uid]
            ec = st.setdefault('economy', {})
            g, l = ec.get('gold', 0), ec.get('lumber', 0)
            tg, tl = ug * cnt, ul * cnt
            if g < tg or l < tl:
                return self._json(400, {'error': f'Need {tg}g/{tl}l'})
            army = st.get('army', {})
            _UHP = dict(grunt=30,raider=50,tauren=80,shaman=20)
            for _uk in list(army.keys()):
                if isinstance(army[_uk], int): army[_uk] = [_UHP.get(_uk, 3)] * army[_uk]
            bld = st.get('buildings', {})
            fc = 12 + (8 if 'fortress' in bld else 0) + (10 if 'citadel' in bld else 0)
            fu = sum(UNITS.get(u, (0,0,0,0))[2] * len(hps) for u, hps in army.items())
            if fu + uf * cnt > fc:
                return self._json(400, {'error': 'Not enough food'})
            ec['gold'] = g - tg
            ec['lumber'] = l - tl
            existing = army.get(uid, [])
            existing.extend([uhp] * cnt)
            army[uid] = existing
            st['army'] = army
            st['economy'] = ec
            sts = st.setdefault('stats', {})
            sts['units_hired_total'] = sts.get('units_hired_total', 0) + cnt
            st['stats'] = sts
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'army': army, 'gold': ec['gold'], 'lumber': ec['lumber']})
        elif self.path == '/api/dismiss':
            uid = body.get('unit', '')
            cnt = max(1, int(body.get('count', 1)))
            st = self._load('.state.json')
            army = st.get('army', {})
            _UHP = dict(grunt=30,raider=50,tauren=80,shaman=20)
            for _uk in list(army.keys()):
                if isinstance(army[_uk], int): army[_uk] = [_UHP.get(_uk, 3)] * army[_uk]
            cur = len(army.get(uid, []))
            if cur <= 0:
                return self._json(400, {'error': 'No such unit in army'})
            army[uid] = army[uid][:-cnt] if cnt < cur else []
            if not army[uid]:
                army.pop(uid, None)
            st['army'] = army
            self._save('.state.json', st)
            self._json(200, {'ok': True, 'army': army})
        else:
            self._json(404, {'error': 'Not found'})

socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('127.0.0.1', PORT), Handler) as httpd:
    httpd.serve_forever()
" >/dev/null 2>&1 &
    echo $! > "$_dashboard_pid_file"
    [ -n "$_cur_hash" ] && echo "$_cur_hash" > "$_dashboard_hash_file"
    rm -rf "$_lock"
    sleep 0.5
    case "$(uname -s)" in
      Darwin) open "http://localhost:$_dashboard_port" 2>/dev/null ;;
      Linux) command -v xdg-open &>/dev/null && xdg-open "http://localhost:$_dashboard_port" &>/dev/null ;;
    esac
  fi
}
if [ "${PEON_TEST:-0}" != "1" ]; then
  _maybe_spawn_dashboard &>/dev/null &
fi

# In test mode run synchronously; in production background to avoid blocking the IDE
if [ "${PEON_TEST:-0}" = "1" ]; then
  _run_sound_and_notify
else
  _run_sound_and_notify & disown
fi

# --- Trainer reminder sound (after main sound finishes) ---
if [ -n "${TRAINER_SOUND:-}" ] && [ -f "$TRAINER_SOUND" ]; then
  if [ "${PEON_TEST:-0}" = "1" ]; then
    play_sound "$TRAINER_SOUND" "$VOLUME"
  else
    (
      # Wait for the main pack sound to finish before playing trainer sound
      _pidfile="$PEON_DIR/.sound.pid"
      if [ -f "$_pidfile" ]; then
        _main_pid=$(cat "$_pidfile" 2>/dev/null)
        if [ -n "$_main_pid" ] && kill -0 "$_main_pid" 2>/dev/null; then
          # Wait up to 10s for main sound to finish
          _waited=0
          while kill -0 "$_main_pid" 2>/dev/null && [ "$_waited" -lt 100 ]; do
            sleep 0.1
            _waited=$((_waited + 1))
          done
        fi
      fi
      # Brief pause after main sound ends for natural spacing
      sleep 0.5
      play_sound "$TRAINER_SOUND" "$VOLUME"
      if [ -n "$NOTIFY" ] && [ "$PAUSED" != "true" ] && [ "${DESKTOP_NOTIF:-true}" = "true" ]; then
        if [ "${NOTIFY_ALWAYS:-true}" = "true" ] || ! terminal_is_focused; then
          send_notification "Peon Trainer" "${TRAINER_MSG:-Time for reps!}" "blue"
        fi
      fi
    ) & disown 2>/dev/null
  fi
fi

# --- Level-up: auto-download missing pack in background ---
if [ -n "${LEVELUP_DOWNLOAD:-}" ]; then
  (
    _pack_dl="$(resolve_pack_download 2>/dev/null)" || exit 0
    bash "$_pack_dl" --dir="$PEON_DIR" --packs="$LEVELUP_DOWNLOAD" >/dev/null 2>&1
  ) & disown 2>/dev/null
fi

# --- Level-up sound (from matching pack) ---
if [ -n "${LEVELUP_SOUND:-}" ] && [ -f "$LEVELUP_SOUND" ]; then
  if [ "${PEON_TEST:-0}" = "1" ]; then
    play_sound "$LEVELUP_SOUND" "$VOLUME"
  else
    (
      _pidfile="$PEON_DIR/.sound.pid"
      if [ -f "$_pidfile" ]; then
        _main_pid=$(cat "$_pidfile" 2>/dev/null)
        if [ -n "$_main_pid" ] && kill -0 "$_main_pid" 2>/dev/null; then
          _waited=0
          while kill -0 "$_main_pid" 2>/dev/null && [ "$_waited" -lt 100 ]; do
            sleep 0.1
            _waited=$((_waited + 1))
          done
        fi
      fi
      sleep 0.3
      play_sound "$LEVELUP_SOUND" "$VOLUME"
    ) & disown 2>/dev/null
  fi
fi

exit 0
