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

const OUTFITS = {
  'Peon: Frostmourne': {
    'editor.fontFamily':                "'Menlo', 'Monaco', monospace",
    'editor.cursorStyle':               'block',
    'editor.cursorBlinking':            'phase',
    'editor.cursorSmoothCaretAnimation':'on',
  },
  "Peon: Wirt's Leg": {
    'editor.fontFamily':                "'Courier New', 'Courier', monospace",
    'editor.cursorStyle':               'line',
    'editor.cursorBlinking':            'blink',
  },
  'Peon: Thunderfury': {
    'editor.fontFamily':                "'Menlo', 'Monaco', monospace",
    'editor.cursorStyle':               'underline',
    'editor.cursorBlinking':            'expand',
  },
  'Peon: The Unstoppable Force': {
    'editor.fontFamily':                "'Menlo', 'Monaco', monospace",
    'editor.cursorStyle':               'block',
    'editor.cursorBlinking':            'solid',
    'editor.fontWeight':                'bold',
  },
  'Peon: Warglaives of Azzinoth': {
    'editor.fontFamily':                "'Monaco', 'Menlo', monospace",
    'editor.cursorStyle':               'line-thin',
    'editor.cursorBlinking':            'smooth',
  },
  'Peon: Ashbringer': {
    'editor.fontFamily':                "'Georgia', 'Times New Roman', serif",
    'editor.cursorStyle':               'line',
    'editor.cursorBlinking':            'smooth',
    'editor.cursorSmoothCaretAnimation':'on',
  },
  'Peon: Cheese (Mmm)': {
    'editor.fontFamily':                "'Comic Sans MS', cursive",
    'editor.cursorStyle':               'underline',
    'editor.cursorBlinking':            'expand',
  },
};
const OUTFIT_KEYS = Array.from(new Set(
  Object.values(OUTFITS).flatMap(o => Object.keys(o))
));

let item, watcher, revertTimer, ctxRef;
let lastState = null, statePath = '', enabled = true;
let revertAt = 0;
let decoTimer, decoTypes = {}, saveDeco;
let lastTitle = '';

function getUnlocked() { return new Set(ctxRef.globalState.get('unlockedThemes', [])); }
function setUnlocked(set) { ctxRef.globalState.update('unlockedThemes', Array.from(set)); }
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
function celebrationsEnabled() {
  return vscode.workspace.getConfiguration('peonMascot').get('celebrations.enabled', true);
}
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
}
function openCelebration(html, durationMs = 6500) {
  if (!celebrationsEnabled()) return null;
  const panel = vscode.window.createWebviewPanel(
    'peonCelebration', '🎉 Peon',
    { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true },
    { enableScripts: true, retainContextWhenHidden: false }
  );
  panel.webview.html = html;
  panel.webview.onDidReceiveMessage(msg => {
    if (msg && msg.cmd === 'apply' && msg.theme) applyTheme(msg.theme);
    if (msg && msg.cmd === 'close') panel.dispose();
  });
  setTimeout(() => { try { panel.dispose(); } catch {} }, durationMs);
  return panel;
}

function legendaryHTML(itemName, themeName, flavor) {
  const particles = [...Array(40)].map((_, i) => {
    const left = Math.random() * 100;
    const delay = Math.random() * 3;
    const dur = 2 + Math.random() * 3;
    const drift = -50 + Math.random() * 100;
    return `<div class="p" style="left:${left}%;animation-delay:${delay}s;animation-duration:${dur}s;--drift:${drift}px"></div>`;
  }).join('');
  return `<!DOCTYPE html><html><head><style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;background:radial-gradient(circle at 50% 60%,#3d2c10 0%,#1a0d00 60%,#000 100%);font-family:-apple-system,'SF Pro Display',sans-serif;color:#fff}
.bg{position:absolute;inset:0;background:conic-gradient(from 0deg,transparent 0deg,#fbbf2422 30deg,transparent 60deg,#fbbf2422 90deg,transparent 120deg,#fbbf2422 150deg,transparent 180deg,#fbbf2422 210deg,transparent 240deg,#fbbf2422 270deg,transparent 300deg,#fbbf2422 330deg,transparent 360deg);animation:spin 8s linear infinite;mix-blend-mode:screen}
@keyframes spin{to{transform:rotate(360deg)}}
.particles{position:absolute;inset:0;overflow:hidden;pointer-events:none}
.p{position:absolute;bottom:-20px;width:6px;height:6px;background:#fbbf24;border-radius:50%;box-shadow:0 0 12px #fbbf24,0 0 4px #fff;animation:float linear infinite}
@keyframes float{0%{transform:translate(0,0);opacity:0}10%{opacity:1}100%{transform:translate(var(--drift),-110vh);opacity:0}}
.wrap{position:relative;height:100%;display:flex;align-items:center;justify-content:center;text-align:center;padding:20px}
.card{animation:drop 0.7s cubic-bezier(0.34,1.56,0.64,1);max-width:520px}
@keyframes drop{0%{transform:scale(0) rotate(-180deg);opacity:0}80%{transform:scale(1.05) rotate(5deg)}100%{transform:scale(1) rotate(0);opacity:1}}
.rarity{font-size:13px;letter-spacing:10px;color:#fbbf24;text-transform:uppercase;text-shadow:0 0 30px #fbbf24,0 0 10px #fbbf24;animation:pulse 1.5s ease-in-out infinite;margin-bottom:8px;font-weight:700}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.5}}
.name{font-size:54px;font-weight:900;background:linear-gradient(45deg,#fff 0%,#fbbf24 25%,#fef3c7 50%,#f59e0b 75%,#fbbf24 100%);background-size:300% 300%;-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;animation:shimmer 3s linear infinite;line-height:1.1;margin:6px 0;text-shadow:0 0 60px rgba(251,191,36,0.5);filter:drop-shadow(0 4px 20px rgba(251,191,36,0.6))}
@keyframes shimmer{to{background-position:300% 0}}
.flavor{font-style:italic;opacity:0.85;margin:14px 0 26px;font-size:16px;color:#fde68a}
.theme{display:inline-flex;align-items:center;gap:10px;padding:14px 26px;border:2px solid #fbbf24;border-radius:6px;background:rgba(0,0,0,0.5);font-size:17px;font-weight:600;letter-spacing:1px;box-shadow:0 0 40px rgba(251,191,36,0.4),inset 0 0 20px rgba(251,191,36,0.1);animation:glow 2s ease-in-out infinite}
@keyframes glow{0%,100%{box-shadow:0 0 40px rgba(251,191,36,0.4),inset 0 0 20px rgba(251,191,36,0.1)}50%{box-shadow:0 0 70px rgba(251,191,36,0.7),inset 0 0 30px rgba(251,191,36,0.2)}}
.btn{margin-top:24px;padding:12px 32px;font-size:14px;font-weight:700;letter-spacing:2px;text-transform:uppercase;background:linear-gradient(180deg,#fbbf24,#d97706);color:#1a0a00;border:none;border-radius:4px;cursor:pointer;box-shadow:0 4px 0 #92400e,0 8px 20px rgba(0,0,0,0.5);transition:transform 0.1s}
.btn:hover{transform:translateY(-2px);box-shadow:0 6px 0 #92400e,0 12px 24px rgba(0,0,0,0.6)}
.btn:active{transform:translateY(2px);box-shadow:0 2px 0 #92400e}
.x{position:absolute;top:14px;right:18px;font-size:20px;cursor:pointer;opacity:0.5}
.x:hover{opacity:1}
</style></head><body>
<div class="bg"></div>
<div class="particles">${particles}</div>
<div class="wrap"><div class="card">
<div class="rarity">🟡 Legendary Drop</div>
<div class="name">${escapeHtml(itemName)}</div>
<div class="flavor">"${escapeHtml(flavor)}"</div>
<div class="theme">🎨 Theme unlocked: ${escapeHtml(themeName)}</div>
<div><button class="btn" onclick="apply()">⚔ Apply Theme</button></div>
</div></div>
<div class="x" onclick="close_()">✕</div>
<script>
const vs=acquireVsCodeApi();
function apply(){vs.postMessage({cmd:'apply',theme:${JSON.stringify(themeName)}});vs.postMessage({cmd:'close'});}
function close_(){vs.postMessage({cmd:'close'});}
</script></body></html>`;
}

function levelUpHTML(level, title) {
  const stars = [...Array(20)].map((_, i) => {
    const left = Math.random() * 100;
    const top = Math.random() * 100;
    const delay = Math.random() * 1.5;
    const size = 3 + Math.random() * 6;
    return `<div class="star" style="left:${left}%;top:${top}%;width:${size}px;height:${size}px;animation-delay:${delay}s"></div>`;
  }).join('');
  return `<!DOCTYPE html><html><head><style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;background:radial-gradient(ellipse at center,#1e3a8a 0%,#0c1c33 50%,#000 100%);font-family:-apple-system,sans-serif;color:#fff}
.rays{position:absolute;inset:0;background:repeating-conic-gradient(from 0deg,transparent 0deg,rgba(165,180,252,0.15) 5deg,transparent 10deg);animation:spin 12s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
.stars{position:absolute;inset:0;pointer-events:none}
.star{position:absolute;background:#fff;border-radius:50%;box-shadow:0 0 10px #fff,0 0 20px #c4b5fd;animation:twinkle 1.5s ease-in-out infinite}
@keyframes twinkle{0%,100%{opacity:0.2;transform:scale(0.5)}50%{opacity:1;transform:scale(1.2)}}
.wrap{position:relative;height:100%;display:flex;align-items:center;justify-content:center;text-align:center;flex-direction:column}
.label{font-size:14px;letter-spacing:14px;color:#a5b4fc;text-transform:uppercase;animation:fadeIn 0.5s;text-shadow:0 0 20px #a5b4fc}
.lvl{font-size:140px;font-weight:900;line-height:1;background:linear-gradient(180deg,#fff,#a5b4fc 50%,#7c3aed);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;animation:burst 1s cubic-bezier(0.34,1.56,0.64,1);text-shadow:0 0 80px rgba(165,180,252,0.6);filter:drop-shadow(0 0 40px rgba(124,58,237,0.8))}
@keyframes burst{0%{transform:scale(0);opacity:0}60%{transform:scale(1.3);opacity:1}100%{transform:scale(1)}}
.title{font-size:32px;font-weight:700;letter-spacing:6px;text-transform:uppercase;color:#fff;margin-top:8px;animation:slideUp 0.7s 0.3s both;text-shadow:0 0 30px #c4b5fd}
@keyframes slideUp{0%{transform:translateY(40px);opacity:0}100%{transform:translateY(0);opacity:1}}
@keyframes fadeIn{0%{opacity:0}100%{opacity:1}}
.flag{position:absolute;width:200%;height:100%;top:0;left:-100%;background:linear-gradient(90deg,transparent 0%,rgba(255,255,255,0.4) 50%,transparent 100%);animation:swipe 1.5s 0.4s}
@keyframes swipe{to{transform:translateX(100%)}}
</style></head><body>
<div class="rays"></div>
<div class="stars">${stars}</div>
<div class="flag"></div>
<div class="wrap">
<div class="label">Level Up</div>
<div class="lvl">${level}</div>
<div class="title">${escapeHtml(title)}</div>
</div>
</body></html>`;
}

function bossKillHTML(bossName, gold, lumber) {
  const splatters = [...Array(15)].map(() => {
    const left = Math.random() * 100;
    const top = Math.random() * 100;
    const size = 20 + Math.random() * 60;
    const delay = Math.random() * 0.5;
    return `<div class="splat" style="left:${left}%;top:${top}%;width:${size}px;height:${size}px;animation-delay:${delay}s"></div>`;
  }).join('');
  return `<!DOCTYPE html><html><head><style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;background:radial-gradient(ellipse at center,#450a0a 0%,#0d0303 50%,#000 100%);font-family:-apple-system,sans-serif;color:#fee2e2}
.splats{position:absolute;inset:0;pointer-events:none}
.splat{position:absolute;background:radial-gradient(circle,#7f1d1d 0%,#450a0a 60%,transparent 100%);border-radius:50%;animation:pop 0.8s cubic-bezier(0.34,1.56,0.64,1) both;transform-origin:center}
@keyframes pop{0%{transform:scale(0);opacity:0}60%{transform:scale(1.2);opacity:1}100%{transform:scale(1);opacity:0.7}}
.wrap{position:relative;height:100%;display:flex;align-items:center;justify-content:center;text-align:center;flex-direction:column;padding:20px}
.skull{font-size:80px;animation:shake 0.5s 0.3s both,float 2s 1s ease-in-out infinite;text-shadow:0 0 40px #f43f5e,0 0 80px rgba(244,63,94,0.5);filter:drop-shadow(0 0 20px #dc2626)}
@keyframes shake{0%,100%{transform:translateX(0)}25%{transform:translateX(-8px) rotate(-5deg)}75%{transform:translateX(8px) rotate(5deg)}}
@keyframes float{0%,100%{transform:translateY(0)}50%{transform:translateY(-10px)}}
.label{font-size:14px;letter-spacing:12px;color:#f43f5e;text-transform:uppercase;font-weight:700;text-shadow:0 0 20px #f43f5e;margin:10px 0;animation:fadeIn 0.6s 0.2s both}
.name{font-size:42px;font-weight:900;color:#fff;text-decoration:line-through;text-decoration-color:#dc2626;text-decoration-thickness:4px;letter-spacing:1px;animation:slideIn 0.7s 0.4s both;text-shadow:0 0 30px rgba(244,63,94,0.6)}
@keyframes slideIn{0%{transform:translateY(-30px);opacity:0}100%{transform:translateY(0);opacity:1}}
.loot{margin-top:24px;display:flex;gap:30px;animation:fadeIn 0.7s 0.7s both}
.coin{font-size:22px;font-weight:700;display:flex;align-items:center;gap:8px;padding:10px 20px;background:rgba(0,0,0,0.5);border:1px solid #7f1d1d;border-radius:6px;box-shadow:0 0 20px rgba(244,63,94,0.3)}
.coin .v{color:#fbbf24;text-shadow:0 0 10px #fbbf24}
@keyframes fadeIn{from{opacity:0}to{opacity:1}}
</style></head><body>
<div class="splats">${splatters}</div>
<div class="wrap">
<div class="skull">💀</div>
<div class="label">Boss Slain</div>
<div class="name">${escapeHtml(bossName)}</div>
<div class="loot">
<div class="coin">💰 <span class="v">+${(gold || 0).toLocaleString()}</span></div>
<div class="coin">🪵 <span class="v">+${(lumber || 0).toLocaleString()}</span></div>
</div>
</div>
</body></html>`;
}

function celebrateUnlock(itemId) {
  const meta = LEGENDARY_THEMES[itemId];
  if (!meta) return;
  flash(`🟡✨ THEME UNLOCKED: ${meta.theme}`, 12000);
  const itemName = Object.keys(LEGENDARY_NAMES).find(k => LEGENDARY_NAMES[k] === itemId) || meta.theme;
  if (!openCelebration(legendaryHTML(itemName, meta.theme, meta.flavor), 9000)) {
    vscode.window.showInformationMessage(
      `🟡 Legendary unlock: ${meta.theme} — ${meta.flavor}`,
      'Apply Theme', 'Later'
    ).then(c => { if (c === 'Apply Theme') applyTheme(meta.theme); });
  }
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
  try { return JSON.parse(fs.readFileSync(statePath, 'utf8')); } catch { return null; }
}
function getLevel(s)   { return (s && (s.level || (s.stats && s.stats.level))) || 1; }
function getTitle(s)   { return (s && (s.level_title || (s.stats && s.stats.level_title))) || 'Peon'; }
function getFatigue(s) { return (s && s.fatigue) || 0; }
function getCaps(s) {
  const b = (s && s.buildings) || {};
  const tired = 60 + ('tavern' in b ? 30 : 0);
  const exhaust = tired + 30;
  return { tired, exhaust };
}

function staticText() {
  const lvl = getLevel(lastState);
  return `${ORC} Lv.${lvl}`;
}
function setStatic() { item.text = staticText(); revertAt = 0; }
function flash(text, ms = 7000) {
  item.text = text;
  revertAt = Date.now() + ms;
  if (revertTimer) clearTimeout(revertTimer);
  revertTimer = setTimeout(setStatic, ms);
}

function diffEvents(prev, cur) {
  if (!prev || !cur) return;
  if (getLevel(cur) > getLevel(prev)) {
    flash(`⭐ LEVEL UP! Lv.${getLevel(cur)} ${getTitle(cur)}`, 12000);
    openCelebration(levelUpHTML(getLevel(cur), getTitle(cur)), 7000);
    return;
  }
  const pKills = (prev.boss_history || []).length;
  const cKills = (cur.boss_history || []).length;
  if (cKills > pKills) {
    const k = cur.boss_history[cKills - 1];
    if (k && k.result === 'victory') {
      flash(`💀 SLAIN: ${k.name} (+${k.gold || 0}g)`, 10000);
      openCelebration(bossKillHTML(k.name, k.gold || 0, k.lumber || 0), 7000);
      return;
    }
    if (k && k.result === 'defeat') { flash(`☠️ Wiped by ${k.name}`, 8000); return; }
  }
  const pAch = Object.keys((prev.stats || {}).achievements_unlocked || {});
  const cAch = Object.keys((cur.stats || {}).achievements_unlocked || {});
  const newAch = cAch.filter(a => !pAch.includes(a));
  if (newAch.length) {
    const n = newAch[0].replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    flash(`🏆 ACHIEVEMENT: ${n}`, 9000); return;
  }
  const newEntries = (cur.activity_log || []).slice((prev.activity_log || []).length);
  for (const e of newEntries) {
    if (!e.i || !e.i.includes('ITEM DROP')) continue;
    const m = e.i.match(/ITEM DROP:\s*([^(]+?)\s*\((\w+)\)/);
    if (!m) continue;
    const name = m[1].trim(), rarity = m[2].trim();
    if (rarity === 'Legendary' && LEGENDARY_NAMES[name]) {
      if (unlockTheme(LEGENDARY_NAMES[name], false)) return;
    }
    if (rarity === 'Common') continue;
    flash(`${RARITY_ICON[rarity] || '🎁'} DROP: ${name} (${rarity})`, 8000);
    return;
  }
  const pCombo = prev.combo_count || 0, cCombo = cur.combo_count || 0;
  if (cCombo >= 50 && Math.floor(cCombo / 50) > Math.floor(pCombo / 50)) {
    flash(`🔥 COMBO x${cCombo}!`, 5000); return;
  }
}

function buildTooltip(s) {
  if (!s) return new vscode.MarkdownString(`${ORC} Peon Mascot — peon-ping state not found.`);
  const e = s.economy || {}, st = s.stats || {};
  const lvl = getLevel(s), title = getTitle(s);
  const fat = getFatigue(s), combo = s.combo_count || 0;
  const caps = getCaps(s);
  const boss = s.active_boss;
  const unlocked = getUnlocked();
  const total = Object.keys(LEGENDARY_THEMES).length;
  const md = new vscode.MarkdownString();
  md.appendMarkdown(`**${ORC} Peon Mascot**\n\n`);
  md.appendMarkdown(`Level **${lvl}** — *${title}*\n\n`);
  md.appendMarkdown(`💰 ${(e.gold || 0).toLocaleString()}g  🪵 ${(e.lumber || 0).toLocaleString()}l\n\n`);
  md.appendMarkdown(`⚡ Fatigue ${fat}/${caps.exhaust} (tired at ${caps.tired})  🔥 Combo x${combo}\n\n`);
  md.appendMarkdown(`📈 ${(st.tasks_completed || 0).toLocaleString()} tasks  •  🏆 ${s.buildings_built || 0} buildings\n\n`);
  if (boss && boss.hp > 0) {
    const pct = Math.round((boss.hp / boss.max_hp) * 100);
    md.appendMarkdown(`👿 **${boss.name}** — ${pct}% HP\n\n`);
  }
  md.appendMarkdown(`🟡 Themes: **${unlocked.size}/${total}** unlocked\n\n`);
  md.appendMarkdown(`---\n*Click to poke peon.*`);
  return md;
}
function refreshTooltip() { item.tooltip = buildTooltip(lastState); }

function poll() {
  const s = readState();
  if (!s) return;
  diffEvents(lastState, s);
  lastState = s;
  refreshTooltip();
  if (!revertAt) setStatic();
  updateWindowTitle();
}

function scanInventoryForLegendaries(s) {
  if (!s) return;
  const owned = new Set([...(s.inventory || []), ...(s.equipped || [])]);
  let n = 0;
  for (const id of Object.keys(LEGENDARY_THEMES)) if (owned.has(id) && unlockTheme(id, true)) n++;
  if (n > 0) {
    vscode.window.showInformationMessage(
      `🟡 Peon Mascot: ${n} legendary theme(s) auto-unlocked from your inventory. Run "Peon: Show unlocked themes" to apply.`
    );
  }
}

// --- Outfits (fonts, cursor, blink that swap with theme) ---

function outfitsEnabled() {
  return vscode.workspace.getConfiguration('peonMascot').get('outfits.enabled', true);
}
function saveBaseline() {
  if (ctxRef.globalState.get('outfitBaseline')) return;
  const cfg = vscode.workspace.getConfiguration();
  const baseline = {};
  for (const k of OUTFIT_KEYS) {
    const v = cfg.inspect(k);
    baseline[k] = v && v.globalValue !== undefined ? v.globalValue : null;
  }
  ctxRef.globalState.update('outfitBaseline', baseline);
}
function restoreBaseline() {
  const baseline = ctxRef.globalState.get('outfitBaseline');
  if (!baseline) return;
  const cfg = vscode.workspace.getConfiguration();
  for (const k of OUTFIT_KEYS) {
    const v = baseline[k];
    cfg.update(k, v === null ? undefined : v, vscode.ConfigurationTarget.Global);
  }
}
function applyOutfit(themeName) {
  const outfit = OUTFITS[themeName];
  const cfg = vscode.workspace.getConfiguration();
  if (!outfit) { restoreBaseline(); return; }
  saveBaseline();
  for (const k of OUTFIT_KEYS) {
    const v = outfit[k];
    cfg.update(k, v === undefined ? undefined : v, vscode.ConfigurationTarget.Global);
  }
}
function onThemeChanged() {
  if (!outfitsEnabled()) return;
  const themeName = vscode.workspace.getConfiguration().get('workbench.colorTheme');
  applyOutfit(themeName);
}

// --- Window title with live peon stats ---

function titleEnabled() {
  return vscode.workspace.getConfiguration('peonMascot').get('windowTitle.enabled', true);
}
function saveTitleBaseline() {
  if (ctxRef.globalState.get('titleBaseline') !== undefined) return;
  const v = vscode.workspace.getConfiguration().inspect('window.title');
  ctxRef.globalState.update('titleBaseline', v && v.globalValue !== undefined ? v.globalValue : null);
}
function restoreTitleBaseline() {
  const t = ctxRef.globalState.get('titleBaseline');
  if (t === undefined) return;
  vscode.workspace.getConfiguration().update(
    'window.title', t === null ? undefined : t, vscode.ConfigurationTarget.Global
  );
}
function updateWindowTitle() {
  if (!titleEnabled() || !lastState) return;
  const lvl = getLevel(lastState);
  const fat = getFatigue(lastState);
  const caps = getCaps(lastState);
  const gold = (lastState.economy || {}).gold || 0;
  const next = `${ORC} Lv.${lvl} ⚡${fat}/${caps.exhaust} 💰${gold.toLocaleString()} — \${dirty}\${activeEditorShort}\${separator}\${rootName}`;
  if (next === lastTitle) return;
  saveTitleBaseline();
  lastTitle = next;
  vscode.workspace.getConfiguration().update('window.title', next, vscode.ConfigurationTarget.Global);
}

// --- Editor decorations: TODO/FIXME/HACK/NOTE/error/save flash ---

function gutterIcon(name) {
  return ctxRef.asAbsolutePath(path.join('icons', 'gutter', `${name}.svg`));
}
function makeDecorations() {
  decoTypes = {
    todo:  vscode.window.createTextEditorDecorationType({ gutterIconPath: gutterIcon('todo'),  gutterIconSize: 'contain', overviewRulerColor: '#fbbf24', overviewRulerLane: vscode.OverviewRulerLane.Right }),
    fixme: vscode.window.createTextEditorDecorationType({ gutterIconPath: gutterIcon('fixme'), gutterIconSize: 'contain', overviewRulerColor: '#f43f5e', overviewRulerLane: vscode.OverviewRulerLane.Right }),
    hack:  vscode.window.createTextEditorDecorationType({ gutterIconPath: gutterIcon('hack'),  gutterIconSize: 'contain', overviewRulerColor: '#a855f7', overviewRulerLane: vscode.OverviewRulerLane.Right }),
    note:  vscode.window.createTextEditorDecorationType({ gutterIconPath: gutterIcon('note'),  gutterIconSize: 'contain', overviewRulerColor: '#94a3b8', overviewRulerLane: vscode.OverviewRulerLane.Right }),
    error: vscode.window.createTextEditorDecorationType({ gutterIconPath: gutterIcon('error'), gutterIconSize: 'contain' }),
  };
  saveDeco = vscode.window.createTextEditorDecorationType({
    backgroundColor: 'rgba(251, 191, 36, 0.25)',
    isWholeLine: true,
  });
}
const TAGS = [
  { kind: 'todo',  re: /\b(TODO|XXX)\b/g,  hover: '🪓 Quest awaits, peon.' },
  { kind: 'fixme', re: /\bFIXME\b/g,       hover: '🔥 Cursed bug. Cleanse it.' },
  { kind: 'hack',  re: /\bHACK\b/g,        hover: '👹 Forbidden magic at work.' },
  { kind: 'note',  re: /\bNOTE\b/g,        hover: '📜 Ancient scroll.' },
];
function decorationsEnabled() {
  return vscode.workspace.getConfiguration('peonMascot').get('decorations.enabled', true);
}
function updateDecorationsFor(editor) {
  if (!editor || !decorationsEnabled()) return;
  const text = editor.document.getText();
  const buckets = { todo: [], fixme: [], hack: [], note: [] };
  for (const t of TAGS) {
    let m;
    while ((m = t.re.exec(text)) !== null) {
      const start = editor.document.positionAt(m.index);
      const end = editor.document.positionAt(m.index + m[0].length);
      buckets[t.kind].push({ range: new vscode.Range(start, end), hoverMessage: t.hover });
    }
    t.re.lastIndex = 0;
  }
  for (const kind of Object.keys(buckets)) editor.setDecorations(decoTypes[kind], buckets[kind]);

  const diags = vscode.languages.getDiagnostics(editor.document.uri)
    .filter(d => d.severity === vscode.DiagnosticSeverity.Error)
    .map(d => ({ range: d.range, hoverMessage: '💀 Peon dies a little inside.' }));
  editor.setDecorations(decoTypes.error, diags);
}
function debounceDeco(editor) {
  if (decoTimer) clearTimeout(decoTimer);
  decoTimer = setTimeout(() => updateDecorationsFor(editor), 300);
}
function flashSave(editor) {
  if (!editor) return;
  const fullRange = new vscode.Range(0, 0, editor.document.lineCount, 0);
  editor.setDecorations(saveDeco, [fullRange]);
  setTimeout(() => editor.setDecorations(saveDeco, []), 250);
}

// --- Activate ---

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
    if (enabled) item.show(); else item.hide();
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
    const pick = await vscode.window.showQuickPick(items, { placeHolder: 'Pick a theme to apply' });
    if (pick && pick.themeName) applyTheme(pick.themeName);
  }));
  ctx.subscriptions.push(vscode.commands.registerCommand('peonMascot.previewCelebration', async () => {
    const pick = await vscode.window.showQuickPick(
      ['🟡 Legendary unlock', '⭐ Level up', '💀 Boss kill'],
      { placeHolder: 'Preview which celebration?' }
    );
    if (!pick) return;
    if (pick.startsWith('🟡')) {
      openCelebration(legendaryHTML('Frostmourne', 'Peon: Frostmourne', 'The blade hungers.'), 9000);
    } else if (pick.startsWith('⭐')) {
      openCelebration(levelUpHTML(9, 'Illidan'), 7000);
    } else {
      openCelebration(bossKillHTML('Pit Lord Mannoroth', 10000, 3000), 7000);
    }
  }));
  ctx.subscriptions.push(vscode.commands.registerCommand('peonMascot.resetCustomizations', async () => {
    const ok = await vscode.window.showWarningMessage(
      'Reset all Peon customizations (font, cursor, window title)?', 'Yes, reset', 'Cancel'
    );
    if (ok !== 'Yes, reset') return;
    restoreBaseline();
    restoreTitleBaseline();
    ctx.globalState.update('outfitBaseline', undefined);
    ctx.globalState.update('titleBaseline', undefined);
    lastTitle = '';
    vscode.window.showInformationMessage('Peon customizations reset.');
  }));

  makeDecorations();
  ctx.subscriptions.push(...Object.values(decoTypes), saveDeco);

  ctx.subscriptions.push(vscode.window.onDidChangeActiveTextEditor(e => debounceDeco(e)));
  ctx.subscriptions.push(vscode.workspace.onDidChangeTextDocument(e => {
    const ed = vscode.window.activeTextEditor;
    if (ed && e.document === ed.document) debounceDeco(ed);
  }));
  ctx.subscriptions.push(vscode.languages.onDidChangeDiagnostics(() => {
    debounceDeco(vscode.window.activeTextEditor);
  }));
  ctx.subscriptions.push(vscode.workspace.onDidSaveTextDocument(doc => {
    const ed = vscode.window.activeTextEditor;
    if (ed && ed.document === doc) flashSave(ed);
  }));

  ctx.subscriptions.push(vscode.workspace.onDidChangeConfiguration(e => {
    if (e.affectsConfiguration('workbench.colorTheme')) onThemeChanged();
  }));
  onThemeChanged();

  setInterval(poll, 1500);
  poll();
  scanInventoryForLegendaries(lastState);
  updateDecorationsFor(vscode.window.activeTextEditor);

  try {
    watcher = fs.watch(statePath, { persistent: false }, () => poll());
    ctx.subscriptions.push({ dispose: () => watcher && watcher.close() });
  } catch {}
}

function deactivate() {
  if (revertTimer) clearTimeout(revertTimer);
  if (decoTimer) clearTimeout(decoTimer);
  if (watcher) watcher.close();
}

module.exports = { activate, deactivate };
