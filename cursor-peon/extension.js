const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const os = require('os');

const ORC = '🧌';
const RARITY_ICON = {
  Common:    '⚪',
  Uncommon:  '🟢',
  Rare:      '🔵',
  Epic:      '🟣',
  Legendary: '🟡',
};
const POKE_LINES = [
  'Wrk wrk!', 'Zug zug.', 'Yes m\'lord?', 'Ready to work!',
  'Me busy!', 'Why you poke?', 'Stop touching me.', 'For the Horde!',
];

let item, watcher, revertTimer;
let lastState = null, statePath = '', enabled = true;
let revertAt = 0;

function resolveStatePath() {
  const cfg = vscode.workspace.getConfiguration('peonMascot').get('statePath');
  return cfg || path.join(os.homedir(), '.claude/hooks/peon-ping/.state.json');
}

function readState() {
  try { return JSON.parse(fs.readFileSync(statePath, 'utf8')); }
  catch { return null; }
}

function staticText() {
  const lvl = (lastState && lastState.level) || 1;
  return `${ORC} Lv.${lvl}`;
}

function setStatic() {
  item.text = staticText();
  revertAt = 0;
}

function flash(text, ms = 7000) {
  item.text = text;
  revertAt = Date.now() + ms;
  if (revertTimer) clearTimeout(revertTimer);
  revertTimer = setTimeout(setStatic, ms);
}

function diffEvents(prev, cur) {
  if (!prev || !cur) return;

  if ((cur.level || 1) > (prev.level || 1)) {
    flash(`⭐ LEVEL UP! Lv.${cur.level} ${cur.level_title || ''}`, 12000);
    return;
  }

  const pKills = (prev.boss_history || []).length;
  const cKills = (cur.boss_history || []).length;
  if (cKills > pKills) {
    const k = cur.boss_history[cKills - 1];
    if (k && k.result === 'victory') {
      flash(`💀 SLAIN: ${k.name} (+${k.gold || 0}g)`, 10000);
      return;
    }
    if (k && k.result === 'defeat') {
      flash(`☠️ Wiped by ${k.name}`, 8000);
      return;
    }
  }

  const pAch = Object.keys((prev.stats || {}).achievements_unlocked || {});
  const cAch = Object.keys((cur.stats || {}).achievements_unlocked || {});
  const newAch = cAch.filter(a => !pAch.includes(a));
  if (newAch.length) {
    const name = newAch[0].replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    flash(`🏆 ACHIEVEMENT: ${name}`, 9000);
    return;
  }

  const pLog = prev.activity_log || [];
  const cLog = cur.activity_log || [];
  const newEntries = cLog.slice(pLog.length);
  for (const e of newEntries) {
    if (!e.i || !e.i.includes('ITEM DROP')) continue;
    const m = e.i.match(/ITEM DROP:\s*([^(]+?)\s*\((\w+)\)/);
    if (!m) continue;
    const name = m[1].trim();
    const rarity = m[2].trim();
    if (rarity === 'Common') continue;
    const icon = RARITY_ICON[rarity] || '🎁';
    flash(`${icon} DROP: ${name} (${rarity})`, 8000);
    return;
  }

  const pCombo = prev.combo_count || 0;
  const cCombo = cur.combo_count || 0;
  if (cCombo >= 50 && Math.floor(cCombo / 50) > Math.floor(pCombo / 50)) {
    flash(`🔥 COMBO x${cCombo}!`, 5000);
    return;
  }
}

function buildTooltip(s) {
  if (!s) return new vscode.MarkdownString(`${ORC} Peon Mascot — peon-ping state not found.`);
  const e = s.economy || {}, st = s.stats || {};
  const lvl = s.level || 1, title = s.level_title || 'Peon';
  const fat = s.fatigue || 0, combo = s.combo_count || 0;
  const boss = s.active_boss;
  const md = new vscode.MarkdownString();
  md.appendMarkdown(`**${ORC} Peon Mascot**\n\n`);
  md.appendMarkdown(`Level **${lvl}** — *${title}*\n\n`);
  md.appendMarkdown(`💰 ${(e.gold || 0).toLocaleString()}g  🪵 ${(e.lumber || 0).toLocaleString()}l\n\n`);
  md.appendMarkdown(`⚡ Fatigue ${fat}/30  🔥 Combo x${combo}\n\n`);
  md.appendMarkdown(`📈 ${(st.tasks_completed || 0).toLocaleString()} tasks  •  🏆 ${s.buildings_built || 0} buildings\n\n`);
  if (boss && boss.hp > 0) {
    const pct = Math.round((boss.hp / boss.max_hp) * 100);
    md.appendMarkdown(`👿 **${boss.name}** — ${pct}% HP\n\n`);
  }
  md.appendMarkdown(`---\n*Click to poke peon.*`);
  return md;
}

function refreshTooltip() {
  item.tooltip = buildTooltip(lastState);
}

function poll() {
  const s = readState();
  if (!s) return;
  diffEvents(lastState, s);
  lastState = s;
  refreshTooltip();
  if (!revertAt) setStatic();
}

function activate(ctx) {
  statePath = resolveStatePath();
  item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  item.command = 'peonMascot.poke';
  setStatic();
  item.show();
  ctx.subscriptions.push(item);

  ctx.subscriptions.push(vscode.commands.registerCommand('peonMascot.poke', () => {
    const line = POKE_LINES[Math.floor(Math.random() * POKE_LINES.length)];
    flash(`${ORC} ${line}`, 2500);
  }));

  ctx.subscriptions.push(vscode.commands.registerCommand('peonMascot.toggle', () => {
    enabled = !enabled;
    if (enabled) { item.show(); }
    else { item.hide(); }
  }));

  setInterval(poll, 1500);
  poll();

  try {
    watcher = fs.watch(statePath, { persistent: false }, () => poll());
    ctx.subscriptions.push({ dispose: () => watcher && watcher.close() });
  } catch {}
}

function deactivate() {
  if (revertTimer) clearTimeout(revertTimer);
  if (watcher) watcher.close();
}

module.exports = { activate, deactivate };
