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

const LEGENDARY_THEMES = {
  frostmourne:        { theme: 'Peon: Frostmourne',              flavor: 'The blade hungers.' },
  wirts_leg:          { theme: "Peon: Wirt's Leg",               flavor: 'Peon confused. But theme unlocked!' },
  thunderfury:        { theme: 'Peon: Thunderfury',              flavor: 'Did someone say THUNDERFURY?!' },
  unstoppable_force:  { theme: 'Peon: The Unstoppable Force',    flavor: 'NOTHING can stop you now.' },
  azzinoth_blades:    { theme: 'Peon: Warglaives of Azzinoth',   flavor: 'You are not prepared.' },
  ashbringer:         { theme: 'Peon: Ashbringer',               flavor: 'By the Holy Light!' },
  cheese:             { theme: 'Peon: Cheese (Mmm)',             flavor: 'Mmm. Cheese.' },
};
const LEGENDARY_NAMES = {
  Frostmourne:                                     'frostmourne',
  "Wirt's Leg":                                    'wirts_leg',
  "Thunderfury, Blessed Blade of the Windseeker":  'thunderfury',
  "The Unstoppable Force":                         'unstoppable_force',
  "Warglaives of Azzinoth":                        'azzinoth_blades',
  Ashbringer:                                      'ashbringer',
  Cheese:                                          'cheese',
};

let item, watcher, revertTimer, ctxRef;
let lastState = null, statePath = '', enabled = true;
let revertAt = 0;

function getUnlocked() {
  return new Set(ctxRef.globalState.get('unlockedThemes', []));
}
function setUnlocked(set) {
  ctxRef.globalState.update('unlockedThemes', Array.from(set));
}
function unlockTheme(itemId, silent = false) {
  const meta = LEGENDARY_THEMES[itemId];
  if (!meta) return false;
  const unlocked = getUnlocked();
  if (unlocked.has(itemId)) return false;
  unlocked.add(itemId);
  setUnlocked(unlocked);
  if (!silent) celebrateUnlock(itemId);
  return true;
}
function celebrateUnlock(itemId) {
  const meta = LEGENDARY_THEMES[itemId];
  if (!meta) return;
  flash(`🟡✨ THEME UNLOCKED: ${meta.theme}`, 12000);
  vscode.window.showInformationMessage(
    `🟡 Legendary unlock: ${meta.theme} — ${meta.flavor}`,
    'Apply Theme', 'Later'
  ).then(choice => {
    if (choice === 'Apply Theme') applyTheme(meta.theme);
  });
}
function applyTheme(themeName) {
  vscode.workspace.getConfiguration().update(
    'workbench.colorTheme', themeName, vscode.ConfigurationTarget.Global
  );
}

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
    if (rarity === 'Legendary' && LEGENDARY_NAMES[name]) {
      const itemId = LEGENDARY_NAMES[name];
      const wasNew = unlockTheme(itemId, false);
      if (wasNew) return;
    }
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
  const unlocked = getUnlocked();
  const total = Object.keys(LEGENDARY_THEMES).length;
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
  md.appendMarkdown(`🟡 Themes: **${unlocked.size}/${total}** unlocked\n\n`);
  md.appendMarkdown(`---\n*Click to poke peon.*`);
  return md;
}

function scanInventoryForLegendaries(s) {
  if (!s) return;
  const owned = new Set([...(s.inventory || []), ...(s.equipped || [])]);
  let newlyUnlocked = 0;
  for (const itemId of Object.keys(LEGENDARY_THEMES)) {
    if (owned.has(itemId)) {
      if (unlockTheme(itemId, true)) newlyUnlocked++;
    }
  }
  if (newlyUnlocked > 0) {
    vscode.window.showInformationMessage(
      `🟡 Peon Mascot: ${newlyUnlocked} legendary theme(s) auto-unlocked from your inventory. Run "Peon: Show unlocked themes" to apply.`
    );
  }
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
  ctxRef = ctx;
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

  ctx.subscriptions.push(vscode.commands.registerCommand('peonMascot.themes', async () => {
    const unlocked = getUnlocked();
    const total = Object.keys(LEGENDARY_THEMES).length;
    const items = Object.entries(LEGENDARY_THEMES).map(([id, m]) => ({
      label: unlocked.has(id) ? `✨ ${m.theme}` : `🔒 ???`,
      description: unlocked.has(id) ? m.flavor : 'Find the legendary item to unlock.',
      detail: unlocked.has(id) ? `Source: ${id}` : '',
      themeName: unlocked.has(id) ? m.theme : null,
    }));
    items.unshift({ label: '↩ Default Dark+', themeName: 'Default Dark+' });
    items.unshift({ label: `🟡 Unlocked: ${unlocked.size}/${total}`, kind: vscode.QuickPickItemKind.Separator });
    const pick = await vscode.window.showQuickPick(items, {
      placeHolder: 'Pick a theme to apply (locked themes do nothing)',
    });
    if (pick && pick.themeName) applyTheme(pick.themeName);
  }));

  setInterval(poll, 1500);
  poll();
  scanInventoryForLegendaries(lastState);

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
