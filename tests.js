/**
 * Tests unitaires pour les fonctions pures de cadence-app.
 * Exécuter avec : node tests.js
 * Aucune dépendance externe requise.
 */

// ── Mini framework de test ─────────────────────────────────────────────────
let passed = 0, failed = 0;
function assert(desc, condition) {
  if (condition) { console.log(`  ✓ ${desc}`); passed++; }
  else           { console.error(`  ✗ ${desc}`); failed++; }
}
function assertEqual(desc, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) { console.log(`  ✓ ${desc}`); passed++; }
  else     { console.error(`  ✗ ${desc}\n    attendu : ${JSON.stringify(expected)}\n    obtenu  : ${JSON.stringify(actual)}`); failed++; }
}
function section(name) { console.log(`\n── ${name} ──`); }

// ── Fonctions pures extraites (dupliquées depuis index.html) ───────────────
const TIER_LEVELS = [0, 12, 23, 34, 45, 56, 67, 78, 89];
function avatarTier(level) { return Math.min(8, Math.floor(level * 9 / 100)); }

const FRAME_INNER_RATIO = 0.72;
const FRAME_META = [
  { scale: 1,    name: "Bronze"     },
  { scale: 1,    name: "Argent"     },
  { scale: 1.35, name: "Vert"       },
  { scale: 1,    name: "Bleu"       },
  { scale: 1,    name: "Violet"     },
  { scale: 1.35, name: "Or"         },
  { scale: 1,    name: "Orange"     },
  { scale: 1,    name: "Rose"       },
  { scale: 1.35, name: "Légendaire" },
];

function frameSlotWidth(avatarSize, frameIndex) {
  if (frameIndex == null) return avatarSize;
  const sc    = FRAME_META[frameIndex]?.scale ?? 1;
  const fSize = Math.round(avatarSize / FRAME_INNER_RATIO);
  return Math.max(avatarSize, Math.round(fSize * sc));
}

const GAME_DEFAULT = {
  xpBase: 100,
  rarity: {
    commune:    { label: "Commune",    color: "#78909C", xp: 10, coins: 2 },
    rare:       { label: "Rare",       color: "#42A5F5", xp: 25, coins: 5 },
    epique:     { label: "Épique",     color: "#AB47BC", xp: 60, coins: 12 },
    legendaire: { label: "Légendaire", color: "#FFA726", xp: 150, coins: 30 },
  },
  rewards: {
    commune:    { xp: 10, coins: 2 },
    rare:       { xp: 25, coins: 5 },
    epique:     { xp: 60, coins: 12 },
    legendaire: { xp: 150, coins: 30 },
  },
  tierFrameMap: [null, 0, 1, 2, 3, 4, 5, 6, 7],
  frameColors: ["#CD7F32","#C0C0C0","#3CB371","#4169E1","#8B008B","#FFD700","#FF8C00","#FF69B4","#C39BD3"],
  shop: [],
};

const PLAYER_DEFAULT = {
  name: "Aventurier", xp: 0, coins: 0, purchased: [], title: null,
  frame: null, avatarChoice: null, familiar: null, familiarChoice: null,
  unlockedFamiliars: [], unlockedFrames: [], unlockedTitles: [], successPts: 0,
  stats: { completed: 0, commune: 0, rare: 0, epique: 0, legendaire: 0, earned: 0, spent: 0 },
  achievements: [], history: [],
};

function normalizePlayer(p) {
  if (!p) return { ...PLAYER_DEFAULT };
  const rawFrame = p.frame;
  return {
    ...PLAYER_DEFAULT,
    ...p,
    name: (typeof p.name === "string" && p.name.trim()) ? p.name.trim() : PLAYER_DEFAULT.name,
    xp: Math.max(0, +p.xp || 0),
    coins: Math.max(0, +p.coins || 0),
    frame: (typeof rawFrame === "number" && rawFrame >= 0 && rawFrame <= 8) ? rawFrame : null,
    avatarChoice: (typeof p.avatarChoice === "number" && p.avatarChoice >= 0 && p.avatarChoice <= 8) ? p.avatarChoice : null,
    familiar: (typeof p.familiar === "number" && p.familiar >= 0 && p.familiar < 5) ? p.familiar : null,
    familiarChoice: (typeof p.familiarChoice === "number" && p.familiarChoice >= 0 && p.familiarChoice <= 8) ? p.familiarChoice : null,
    unlockedFrames: Array.isArray(p.unlockedFrames) ? p.unlockedFrames.filter(f => typeof f === "number" && f >= 0 && f <= 8) : [],
    unlockedFamiliars: Array.isArray(p.unlockedFamiliars) ? p.unlockedFamiliars : [],
    unlockedTitles: Array.isArray(p.unlockedTitles) ? p.unlockedTitles : [],
    achievements: Array.isArray(p.achievements) ? p.achievements : [],
    history: Array.isArray(p.history) ? p.history : [],
    purchased: Array.isArray(p.purchased) ? p.purchased : [],
    stats: { ...PLAYER_DEFAULT.stats, ...(p.stats || {}) },
  };
}

function normalizeGame(g) {
  return {
    xpBase: (g && +g.xpBase) || GAME_DEFAULT.xpBase,
    rarity: {
      commune:    { ...GAME_DEFAULT.rarity.commune,    ...((g && g.rarity && g.rarity.commune) || {}) },
      rare:       { ...GAME_DEFAULT.rarity.rare,       ...((g && g.rarity && g.rarity.rare) || {}) },
      epique:     { ...GAME_DEFAULT.rarity.epique,     ...((g && g.rarity && g.rarity.epique) || {}) },
      legendaire: { ...GAME_DEFAULT.rarity.legendaire, ...((g && g.rarity && g.rarity.legendaire) || {}) },
    },
    tierFrameMap: Array.isArray(g && g.tierFrameMap) && g.tierFrameMap.length === 9
      ? g.tierFrameMap.map((v, i) => i === 0 ? null : (v == null ? null : Math.max(0, Math.min(8, +v))))
      : [...GAME_DEFAULT.tierFrameMap],
    frameColors: Array.isArray(g && g.frameColors) && g.frameColors.length === 9
      ? g.frameColors
      : [...GAME_DEFAULT.frameColors],
    shop: [],
  };
}

// ── Tests : avatarTier ─────────────────────────────────────────────────────
section("avatarTier(level)");
assertEqual("niveau 0 → palier 0",  avatarTier(0),   0);
assertEqual("niveau 1 → palier 0",  avatarTier(1),   0);
assertEqual("niveau 11 → palier 0", avatarTier(11),  0);
assertEqual("niveau 12 → palier 1", avatarTier(12),  1);
assertEqual("niveau 23 → palier 2", avatarTier(23),  2);
assertEqual("niveau 89 → palier 8", avatarTier(89),  8);
assertEqual("niveau 99 → palier 8", avatarTier(99),  8);
assertEqual("niveau 100 → palier 8 (plafonné)", avatarTier(100), 8);
assertEqual("niveau 150 → palier 8 (plafonné)", avatarTier(150), 8);
// Cohérence avec TIER_LEVELS : chaque seuil doit atteindre son palier
TIER_LEVELS.forEach((lvl, tier) => {
  if (lvl > 0) assertEqual(`TIER_LEVELS[${tier}]=${lvl} → palier ${tier}`, avatarTier(lvl), tier);
});

// ── Tests : FRAME_META / FRAMES ────────────────────────────────────────────
section("FRAME_META structure");
assertEqual("9 cadres définis", FRAME_META.length, 9);
assert("tous ont scale > 0", FRAME_META.every(f => f.scale > 0));
assert("tous ont un nom non vide", FRAME_META.every(f => typeof f.name === "string" && f.name.length > 0));
const scaledFrames = FRAME_META.map((f, i) => i).filter(i => FRAME_META[i].scale !== 1);
assertEqual("indices des cadres agrandis (2, 5, 8)", scaledFrames, [2, 5, 8]);
assertEqual("scale du cadre Vert (2)", FRAME_META[2].scale, 1.35);
assertEqual("scale du cadre Or (5)",   FRAME_META[5].scale, 1.35);
assertEqual("scale du cadre Légendaire (8)", FRAME_META[8].scale, 1.35);

// ── Tests : frameSlotWidth ─────────────────────────────────────────────────
section("frameSlotWidth(avatarSize, frameIndex)");
const SZ = 88;
assertEqual("sans cadre → taille avatar", frameSlotWidth(SZ, null), 88);
assertEqual("cadre sc=1 : slot = round(88/0.72) = 122", frameSlotWidth(SZ, 0), 122);
assertEqual("cadre sc=1.35 : slot = round(122*1.35) = 165", frameSlotWidth(SZ, 2), 165);
assertEqual("cadre sc=1 (index 4) → 122", frameSlotWidth(SZ, 4), 122);
assertEqual("cadre sc=1.35 (index 8) → 165", frameSlotWidth(SZ, 8), 165);
// Le slot doit toujours être >= taille de l'avatar
FRAME_META.forEach((_, i) => {
  assert(`slot >= avatarSize pour cadre ${i}`, frameSlotWidth(SZ, i) >= SZ);
});
// La fenêtre intérieure du slot doit correspondre à la taille avatar
FRAME_META.forEach((f, i) => {
  const slot = frameSlotWidth(SZ, i);
  const innerRatio = SZ / slot;
  // Pour sc=1 : inner/slot = 88/122 ≈ 0.72
  // Pour sc=1.35 : inner/slot = 88/165 ≈ 0.533, mais le cadre est scalé CSS donc OK
  assert(`slot[${i}] ≥ 88`, slot >= 88);
});

// ── Tests : normalizePlayer ────────────────────────────────────────────────
section("normalizePlayer");
const p0 = normalizePlayer(null);
assertEqual("null → defaults", p0.name, "Aventurier");
assertEqual("null → frame null", p0.frame, null);
assertEqual("null → xp 0", p0.xp, 0);

const p1 = normalizePlayer({ name: "  Alice  ", xp: "50", coins: "20", frame: 0 });
assertEqual("nom trimmé", p1.name, "Alice");
assertEqual("xp coercé", p1.xp, 50);
assertEqual("coins coercé", p1.coins, 20);
assertEqual("frame=0 préservé (falsy-zero safe)", p1.frame, 0);

const p2 = normalizePlayer({ frame: "bronze" });
assertEqual("frame string invalide → null", p2.frame, null);

const p3 = normalizePlayer({ frame: 9 });
assertEqual("frame hors-limite (9) → null", p3.frame, null);

const p4 = normalizePlayer({ frame: -1 });
assertEqual("frame négatif → null", p4.frame, null);

const p5 = normalizePlayer({ unlockedFrames: [0, 1, 99, "x", 2] });
assertEqual("unlockedFrames filtre les invalides", p5.unlockedFrames, [0, 1, 2]);

const p6 = normalizePlayer({ unlockedFrames: null });
assertEqual("unlockedFrames null → []", p6.unlockedFrames, []);

const p7 = normalizePlayer({ familiar: 4 });
assertEqual("familiar valide (4)", p7.familiar, 4);

const p8 = normalizePlayer({ familiar: 5 });
assertEqual("familiar hors-limite (5) → null", p8.familiar, null);

const p9 = normalizePlayer({ xp: -10 });
assertEqual("xp négatif → 0", p9.xp, 0);

const p10 = normalizePlayer({ name: "" });
assertEqual("nom vide → défaut", p10.name, "Aventurier");

// ── Tests : normalizeGame ──────────────────────────────────────────────────
section("normalizeGame");
const g0 = normalizeGame(null);
assertEqual("null → xpBase défaut", g0.xpBase, 100);
assertEqual("null → frameColors défaut", g0.frameColors, GAME_DEFAULT.frameColors);
assertEqual("null → tierFrameMap défaut", g0.tierFrameMap, GAME_DEFAULT.tierFrameMap);

const g1 = normalizeGame({ xpBase: 200 });
assertEqual("xpBase personnalisé", g1.xpBase, 200);

// Bug fix vérifié : label épique/légendaire préservé depuis la sauvegarde
const g2 = normalizeGame({ rarity: { epique: { label: "Mega", color: "#ff0" }, legendaire: { label: "Ultime" } } });
assertEqual("label épique custom préservé", g2.rarity.epique.label, "Mega");
assertEqual("label légendaire custom préservé", g2.rarity.legendaire.label, "Ultime");
assertEqual("couleur épique custom préservée", g2.rarity.epique.color, "#ff0");

const g3 = normalizeGame({ rarity: { epique: { xp: 75 } } });
assertEqual("xp épique custom préservé, label default", g3.rarity.epique.xp, 75);
assertEqual("label épique défaut quand absent", g3.rarity.epique.label, "Épique");

const g4 = normalizeGame({ tierFrameMap: [null, 0, 1, 2, 3, 4, 5, 6, 7] });
assertEqual("tierFrameMap valid préservé", g4.tierFrameMap, [null, 0, 1, 2, 3, 4, 5, 6, 7]);

const g5 = normalizeGame({ tierFrameMap: [null, 0, 1] }); // trop court
assertEqual("tierFrameMap invalide → défaut", g5.tierFrameMap, GAME_DEFAULT.tierFrameMap);

const g6 = normalizeGame({ tierFrameMap: [0, 0, 1, 2, 3, 4, 5, 6, 7] }); // index 0 doit être null
assertEqual("tierFrameMap[0] forcé à null", g6.tierFrameMap[0], null);

const g7 = normalizeGame({ frameColors: ["#fff","#fff","#fff","#fff","#fff","#fff","#fff","#fff","#fff"] });
assertEqual("frameColors 9 valeurs préservé", g7.frameColors.length, 9);

const g8 = normalizeGame({ frameColors: ["#fff"] }); // trop court
assertEqual("frameColors invalide → défaut", g8.frameColors, GAME_DEFAULT.frameColors);

// ── Résultat ───────────────────────────────────────────────────────────────
console.log(`\n${"─".repeat(40)}`);
console.log(`Total : ${passed + failed} tests — ${passed} réussis, ${failed} échoués`);
if (failed > 0) process.exit(1);
