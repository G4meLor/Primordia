# Task 11 (R13) — chaos scar (cheap) + the transposon cosmetic hue mutation.
#   - thresholds: th_i = rest + (1 − rest) × {0.40, 0.65, 0.85}, rest = the
#     difficulty settle floor (0.12 normal / 0.05 peaceful / 0.25 chaos) —
#     exact per-difficulty pins, every tier reachable on every difficulty.
#   - crossings: the run peak folds each game tick; every tier fires ONCE per
#     run; the benign/harsh split reads the karma standing AT the crossing
#     (never consumed).
#   - persistence: chaosPeak/scarTier/scarBenign ride the save wire
#     (camelCase); old saves without them read 0.0 / 0 / [].
#   - world tint: the single scar slot — green-shift benign / chaos-orange
#     harsh, alpha 0.03/0.055/0.08 by tier (tier 3 strongest, ≤ 0.08 ceiling).
#   - transposon: creature-deck-only event — omen warn (2.5 s) BEFORE apply
#     (the chaos law), hue ±30 seeded (either sign, Mulberry32), at most once
#     per run, exact float revert through the LOOK tab.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const GameScript := preload("res://src/game/game.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const StageScript := preload("res://src/game/stage.gd")
const CreatureEvents := preload("res://src/game/creature/creature_events.gd")
const CellEvents := preload("res://src/game/cell/cell_events.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")
const ChaosScript := preload("res://src/game/chaos.gd")
const BackdropScript := preload("res://src/gfx/backdrop.gd")
const I18nScript := preload("res://src/core/i18n.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")

const DT := 1.0 / 60.0
const SCRATCH_CFG := "user://test_chaos_scar_settings.cfg"
const SLOT_RT := 145      # wire round-trip
const SLOT_OLD := 146     # pre-R13 save (no scar fields)
const SLOT_CORRUPT := 147 # corrupt / out-of-range scar fields

# the raw EN keys — pinned (the toast composes through tr at fire time;
# TranslationServer falls back to the key, so the KEYS are the contract)
const SCAR_NAMES := ["Moon Crack", "Apex Bloom", "Core Stirs Early"]
const SCAR_BENIGN_BODY := "The chaos crested and receded — the world glows gently with it."
const SCAR_HARSH_BODY := "The chaos crested and tore through — the world bears the scar."
const TRANSPOSON_NAME := "🧬 TRANSPOSON JUMP"
const TRANSPOSON_WARN := "The air tingles — your COLORS are about to shift…"
const TRANSPOSON_TOAST := "A transposon jumped — your hue changed! Revert is free in the LOOK tab."

# minimal chaos-ctx shape the scheduler tests pass (the sim's update_chaos
# carries the same keys; extra ones are ignored by every weight)
const CHAOS_CTX := {"chaos": 0.5, "karma": 0.0, "stageTime": 0.0, "warnScale": 1.0}


## A stand-in sim stage (the karma-test pattern): registered ids to switch
## between, nothing else.
class FakeStage extends "res://src/game/stage.gd":
	func _init(g: Variant, id_v: String) -> void:
		super(g, id_v)


## Duck stage for the scheduler test — the def's apply lambda calls s.ctx /
## s._fire / s.tr (the CreatureSim surface it ships against). No tr override
## (Object.tr is final for the parser): the test pins the en locale, where
## Object.tr falls back to the key.
class StubStage extends RefCounted:
	var ctx: Variant
	var toasts: Array = []

	func _init(ctx_v: Variant) -> void:
		ctx = ctx_v

	func _fire(hook: String, args: Array) -> void:
		if hook == "hud_toast":
			toasts.append(String(args[0]))


# ---- the threshold formula ------------------------------------------------------

func test_settle_rest_pins() -> void:
	approx(Ctx.settle_rest("normal"), 0.12, "normal settle floor 0.12", 1e-9)
	approx(Ctx.settle_rest("peaceful"), 0.05, "peaceful settle floor 0.05", 1e-9)
	approx(Ctx.settle_rest("chaos"), 0.25, "chaos settle floor 0.25", 1e-9)


func test_threshold_formula_exact() -> void:
	# th_i = rest + (1 − rest) × {0.40, 0.65, 0.85} — the controller's formula,
	# pinned to the exact decimal values (eps 1e-9 dwarfs the float error)
	var th_n: Array = Ctx.scar_thresholds("normal")
	eq(th_n.size(), 3, "three tiers")
	approx(float(th_n[0]), 0.472, "normal th1 = 0.12 + 0.88·0.40", 1e-9)
	approx(float(th_n[1]), 0.692, "normal th2 = 0.12 + 0.88·0.65", 1e-9)
	approx(float(th_n[2]), 0.868, "normal th3 = 0.12 + 0.88·0.85", 1e-9)
	var th_p: Array = Ctx.scar_thresholds("peaceful")
	approx(float(th_p[0]), 0.43, "peaceful th1", 1e-9)
	approx(float(th_p[1]), 0.6675, "peaceful th2", 1e-9)
	approx(float(th_p[2]), 0.8575, "peaceful th3 — 0.85 reachable on peaceful", 1e-9)
	var th_c: Array = Ctx.scar_thresholds("chaos")
	approx(float(th_c[0]), 0.55, "chaos th1", 1e-9)
	approx(float(th_c[1]), 0.7375, "chaos th2", 1e-9)
	approx(float(th_c[2]), 0.8875, "chaos th3", 1e-9)
	# reachability + ordering on every difficulty
	for d in ["peaceful", "normal", "chaos"]:
		var th: Array = Ctx.scar_thresholds(String(d))
		ok(float(th[0]) < float(th[1]) and float(th[1]) < float(th[2]),
				"%s: tiers ascend" % String(d))
		ok(float(th[2]) <= 1.0, "%s: tier 3 reachable (≤ 1.0)" % String(d))
		ok(float(th[0]) > Ctx.settle_rest(String(d)), "%s: th1 above the rest floor" % String(d))


# ---- the crossing fold (once per run) -------------------------------------------

## The brief's sequence: 0.1→0.5→0.7→0.9 must produce 3 scars — not 5 (a
## naive per-tick threshold check refires while chaos loiters above a tier).
func test_crossing_fires_once() -> void:
	var ctx: Variant = Ctx.new(21)
	ctx.difficulty = "normal"
	var fired: Array = []
	for v in [0.1, 0.5, 0.7, 0.9]:
		fired.append(ctx.scar_cross(v))
	eq(fired[0], [], "0.1: below th1, nothing")
	eq(fired[1], [1], "0.5: crosses tier 1 once")
	eq(fired[2], [2], "0.7: crosses tier 2 once")
	eq(fired[3], [3], "0.9: crosses tier 3 once")
	eq(int(ctx.scar_tier), 3, "the peak latched the highest fired tier")
	# loitering above the thresholds (the "not 5" half) and dipping below the
	# floor both fold without refiring — the peak never un-crosses
	for v in [0.9, 0.8, 0.5, 0.2, 0.9]:
		eq(ctx.scar_cross(v), [], "no refire at %s" % str(v))


## A single chaos spike can cross several tiers in one tick — all fire, in
## ascending order, each exactly once.
func test_multi_tier_single_tick() -> void:
	var ctx: Variant = Ctx.new(5)
	ctx.difficulty = "normal"
	eq(ctx.scar_cross(0.95), [1, 2, 3], "one spike fires all three tiers in order")
	eq(ctx.scar_cross(0.95), [], "and never again")


# ---- benign vs harsh — karma AT the crossing -------------------------------------

func test_scar_benign_needs_karma_at_crossing() -> void:
	var ctx: Variant = Ctx.new(7)
	ctx.difficulty = "normal"
	# boundary: exactly 0.3 IS benign (karma >= 0.3)
	ctx.karma = 0.3
	eq(ctx.scar_cross(0.5), [1], "tier 1 fires")
	eq(ctx.scar_benign, [true], "karma 0.3 at the crossing → benign")
	# the karma read is AT the crossing moment, not a latched first read:
	# karma has since crashed — tier 2 reads harsh
	ctx.karma = -0.5
	eq(ctx.scar_cross(0.7), [2], "tier 2 fires")
	eq(bool(ctx.scar_benign[1]), false, "karma -0.5 at ITS crossing → harsh")
	# a later recovery cannot relabel an already-fired tier
	ctx.karma = 0.9
	eq(ctx.scar_cross(0.9), [3], "tier 3 fires")
	eq(bool(ctx.scar_benign[2]), true, "karma 0.9 at the third crossing → benign")
	# the read never consumes: add_karma's meter is untouched by the fold
	approx(float(ctx.karma), 0.9, "crossings do not consume karma", 1e-9)


# ---- the world tint decision (pure) ----------------------------------------------

func test_world_tint_decision() -> void:
	var ctx: Variant = Ctx.new(11)
	eq(BackdropScript.world_tint_color(ctx), null, "no scar → no tint")
	# benign: green-shift (the green channel dominates), alpha by tier
	ctx.scar_tier = 1
	ctx.scar_benign = [true]
	var t1: Variant = BackdropScript.world_tint_color(ctx)
	ok(t1 is Color and float(t1.g) > float(t1.r) and float(t1.g) > float(t1.b),
			"tier 1 benign: green-shift")
	approx(float(t1.a), 0.03, "tier 1 alpha 0.03", 1e-6)  # Color stores f32 components
	ctx.scar_tier = 3
	ctx.scar_benign = [true, false, false]
	var t3: Variant = BackdropScript.world_tint_color(ctx)
	ok(t3 is Color and float(t3.r) > float(t3.g) and float(t3.g) > float(t3.b),
			"tier 3 harsh: chaos-orange")
	approx(float(t3.a), 0.08, "tier 3 alpha 0.08 (strongest)", 1e-6)
	# the alpha ladder rises with the tier and never breaches the 0.08 ceiling
	ctx.scar_tier = 2
	ctx.scar_benign = [true, false]
	approx(float(BackdropScript.world_tint_color(ctx).a), 0.055, "tier 2 alpha 0.055", 1e-6)
	ok(0.03 < 0.055 and 0.055 < 0.08 and 0.08 <= 0.08,
			"alpha ladder: 0.03 < 0.055 < 0.08 ≤ 0.08")
	# the highest fired tier's own benign flag colors the slot
	ctx.scar_tier = 2
	ctx.scar_benign = [false, true]
	var t2b: Variant = BackdropScript.world_tint_color(ctx)
	ok(t2b is Color and float(t2b.g) > float(t2b.r),
			"tier 2 benign reads ITS OWN flag, not tier 1's")


# ---- the transposon (apply / revert round trip) -----------------------------------

func test_transposon_round_trip_exact() -> void:
	var ctx: Variant = Ctx.new(9)
	ctx.genome["hue"] = 263.478  # an arbitrary slider float, not a default
	var rng: Variant = ctx.rng.branch()
	var before: Variant = ctx.transposon_apply(rng)
	approx(float(before), 263.478, "apply returns the exact pre-shift hue", 1e-9)
	ok(bool(ctx.flags.get("transposonFired", false)), "the once-per-run latch is set")
	var shifted := float(ctx.genome["hue"])
	ok(absf(shifted - 263.478 - 30.0) < 1e-9 or absf(shifted - 263.478 + 30.0) < 1e-9,
			"hue shifted exactly ±30 (got %s)" % str(shifted))
	# double apply — the latch holds, the hue stays where the shift put it
	ok(ctx.transposon_apply(rng) == null, "a second apply is refused")
	approx(float(ctx.genome["hue"]), shifted, "hue unchanged by the refused apply", 1e-9)
	# the revert restores EXACTLY (the stored float, bit-for-bit within 1e-9)
	ok(ctx.transposon_revert(), "revert reports a restore")
	approx(float(ctx.genome["hue"]), 263.478, "revert restores the stored hue exactly", 1e-9)
	# the stored value is cleared — a second revert is a no-op…
	ok(not ctx.transposon_revert(), "second revert is a no-op")
	approx(float(ctx.genome["hue"]), 263.478, "…and the hue stays restored", 1e-9)
	# …but the event latch is NOT cleared: the mutation already happened and
	# must never fire twice in one run
	ok(bool(ctx.flags.get("transposonFired", false)), "the latch survives the revert")


## Both seeded directions occur across seeds (either sign, Mulberry32 only) —
## a fixed seed list is deterministic under the frozen Rng.
func test_transposon_seeded_directions() -> void:
	var ups := 0
	var downs := 0
	for s in range(1, 25):
		var ctx: Variant = Ctx.new(s)
		ctx.genome["hue"] = 180.0  # wrap-free center: ±30 never crosses 0/360
		ctx.transposon_apply(ctx.rng.branch())
		var d := float(ctx.genome["hue"]) - 180.0
		if d > 0.0:
			ups += 1
		elif d < 0.0:
			downs += 1
		else:
			downs = -999  # a zero shift would violate the ±30 contract outright
	ok(ups > 0 and downs > 0, "both directions occur (up %d, down %d)" % [ups, downs])
	eq(ups + downs, 24, "every seed shifted exactly once by ±30")


## The stored hue round-trips the save with full precision, so a CONTINUE
## keeps the exact revert value (flags ride the wire verbatim).
func test_transposon_revert_value_survives_save() -> void:
	_wipe(SLOT_RT)
	var ctx: Variant = Ctx.new(31)
	ctx.genome["hue"] = 263.478
	ctx.transposon_apply(ctx.rng.branch())
	ctx.stage = "creature"
	ok(ctx.save(SLOT_RT), "save after the transposon")
	var loader: Variant = Ctx.new()
	ok(loader.load(SLOT_RT), "load")
	approx(float(loader.flags.get("hueBeforeTransposon", -1.0)), 263.478,
			"the stored hue survives the wire bit-exact", 1e-9)
	ok(bool(loader.flags.get("transposonFired", false)), "the latch survives the wire")
	ok(loader.transposon_revert(), "revert on the loaded ctx")
	approx(float(loader.genome["hue"]), 263.478, "revert restores exactly after load", 1e-9)


# ---- the deck gating ---------------------------------------------------------------

func _find_def(deck: Array, id: String) -> Variant:
	for d in deck:
		if String(d["id"]) == id:
			return d
	return null


func test_transposon_gated_into_creature_deck_only() -> void:
	var world: Dictionary = WorldGenomeScript.derive_world_genome(4242)
	var deck: Array = CreatureEvents.make_creature_chaos_events(world)
	var def: Variant = _find_def(deck, "transposon")
	ok(def != null, "the creature deck carries the transposon")
	if def == null:
		return
	eq(String(def["name"]), TRANSPOSON_NAME, "the def name key")
	eq(String(ChaosScript.effective_warn(def)), TRANSPOSON_WARN,
			"the omen names the hue shift (chaos law: warn BEFORE apply)")
	# the window is pinned at 2.5 s (a per-def warnS wins over the temperament bucket)
	approx(float(def.get("warnS", 0.0)), 2.5, "warn phase pinned at 2.5 s", 1e-9)
	# modest weight: below every baseline threat event at the same chaos
	var w: float = float(def["weight"].call({"chaos": 0.5}))
	ok(w > 0.0 and w < 0.85, "modest weight 0 < %s < 0.85" % str(w))
	eq(float(def["weight"].call({"chaos": 0.5, "transposonFired": true})), 0.0,
			"the weight gates to 0 once the latch is set")
	# the other decks do not gain it
	ok(_find_def(CellEvents.make_cell_chaos_events(world), "transposon") == null,
			"the cell deck does not carry it (the cell A-B dump is untouched)")


## The real scheduler path: the omen warn phase runs BEFORE the apply (the
## chaos law), and the apply lands exactly once — the trigger() route
## bypasses weights, so the ctx latch is the second half of the once-guard.
func test_transposon_through_real_scheduler() -> void:
	TranslationServer.set_locale("en")  # Object.tr falls back to the key on en
	var ctx: Variant = Ctx.new(0x51EF)
	var world: Dictionary = WorldGenomeScript.derive_world_genome(0x51EF)
	var def: Variant = _find_def(CreatureEvents.make_creature_chaos_events(world), "transposon")
	ok(def != null, "precondition: the def exists")
	if def == null:
		return
	var stg: Variant = StubStage.new(ctx)
	var warns: Array = []
	var sch: Variant = ChaosScript.new(ctx.rng.branch(), [def])
	sch._since_last = 1000.0  # force the spawn roll on the first tick
	# tick 1: the omen spawn — warn phase opens, no hue move yet
	sch.update(0.01, stg, CHAOS_CTX.duplicate(), {
		"onWarn": func(d: Variant) -> void: warns.append(ChaosScript.effective_warn(d)),
	})
	eq(warns.size(), 1, "the omen fires at spawn")
	if warns.size() == 1:
		eq(String(warns[0]), TRANSPOSON_WARN, "the omen names the hue shift")
	approx(float(ctx.genome["hue"]), 120.0, "no hue move during the warn phase", 1e-9)
	# 2.5 s of warn + the conversion tick
	for i in 170:
		sch.update(DT, stg, CHAOS_CTX.duplicate(), {})
	var shifted := float(ctx.genome["hue"])
	ok(absf(shifted - 90.0) < 1e-9 or absf(shifted - 150.0) < 1e-9,
			"apply moved the hue ±30 after the omen (got %s)" % str(shifted))
	ok(bool(ctx.flags.get("transposonFired", false)), "the latch set through the real path")
	eq(stg.toasts.size(), 1, "one apply toast")
	if stg.toasts.size() == 1:
		eq(String(stg.toasts[0]), TRANSPOSON_TOAST, "the toast explains the free LOOK revert")
	# re-triggering after the event ended cannot re-apply (once per run — the
	# trigger path bypasses weights, the ctx latch is the guard)
	ok(sch.trigger("transposon", stg), "re-trigger spawns again (weightless)")
	for i in 170:
		sch.update(DT, stg, CHAOS_CTX.duplicate(), {})
	approx(float(ctx.genome["hue"]), shifted, "the hue never moves twice in one run", 1e-9)
	eq(stg.toasts.size(), 1, "no second apply toast")


# ---- the save wire ------------------------------------------------------------------

func _path(n: int) -> String:
	return "user://saves/slot%d.json" % n


func _wipe(n: int) -> void:
	if FileAccess.file_exists(_path(n)):
		DirAccess.remove_absolute(_path(n))


func _write_json(n: int, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(_path(n), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))


## Minimal valid v1 blob (the test_context _base shape) WITHOUT the scar
## fields — a pre-R13 save.
func _base() -> Dictionary:
	return {
		"version": 1, "seed": 555, "stage": "creature", "difficulty": "normal",
		"genome": {}, "dna": 10, "karma": 0.0, "chaos": 0.15, "playtime": 0.0,
		"totalDnaEarned": 0, "playerName": "Squish", "bestiary": [], "eco": null,
		"flags": {},
	}


func test_scar_wire_round_trip() -> void:
	_wipe(SLOT_RT)
	var ctx: Variant = Ctx.new(77)
	ctx.difficulty = "normal"
	ctx.karma = 0.5
	ctx.scar_cross(0.5)   # tier 1, benign
	ctx.karma = -0.5
	ctx.scar_cross(0.95)  # tiers 2+3, harsh
	ctx.stage = "creature"
	ok(ctx.save(SLOT_RT), "save with fired scars")
	var f := FileAccess.open(_path(SLOT_RT), FileAccess.READ)
	ok(f != null, "slot file readable")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	ok(parsed is Dictionary, "slot file parses")
	if not (parsed is Dictionary):
		return
	var blob: Dictionary = parsed
	approx(float(blob.get("chaosPeak", -1.0)), 0.95, "wire chaosPeak (camelCase)", 1e-9)
	eq(int(blob.get("scarTier", -1)), 3, "wire scarTier")
	eq(blob.get("scarBenign", null), [true, false, false], "wire scarBenign per fired tier")
	var loader: Variant = Ctx.new()
	ok(loader.load(SLOT_RT), "load round-trips")
	approx(float(loader.chaos_peak), 0.95, "peak restored", 1e-9)
	eq(int(loader.scar_tier), 3, "tier restored")
	eq(loader.scar_benign, [true, false, false], "benign ledger restored")
	# the restored ctx keeps the run's once-only contract: no refires
	eq(loader.scar_cross(0.95), [], "a loaded run never refires its scars")


## Pre-R13 saves (the scar fields absent) read the zero state — and the fold
## still works from it.
func test_scar_wire_old_save_grace() -> void:
	_wipe(SLOT_OLD)
	_write_json(SLOT_OLD, _base())
	var loader: Variant = Ctx.new()
	ok(loader.load(SLOT_OLD), "pre-R13 save loads")
	approx(float(loader.chaos_peak), 0.0, "missing chaosPeak → 0.0", 1e-9)
	eq(int(loader.scar_tier), 0, "missing scarTier → 0")
	ok(loader.scar_benign.is_empty(), "missing scarBenign → []")
	loader.difficulty = "normal"
	eq(loader.scar_cross(0.5), [1], "the fold works from the old-save zero state")


## Corrupt scar fields degrade to the defaults instead of poisoning the fold.
func test_scar_wire_validation() -> void:
	_wipe(SLOT_CORRUPT)
	var blob := _base()
	blob["chaosPeak"] = "high"
	blob["scarTier"] = "many"
	blob["scarBenign"] = "yes"
	_write_json(SLOT_CORRUPT, blob)
	var loader: Variant = Ctx.new()
	ok(loader.load(SLOT_CORRUPT), "corrupt scar fields load")
	approx(float(loader.chaos_peak), 0.0, "garbage peak → 0.0", 1e-9)
	eq(int(loader.scar_tier), 0, "garbage tier → 0")
	ok(loader.scar_benign.is_empty(), "garbage ledger → []")
	# out-of-range / non-bool entries: the peak clamps to the meter, the tier
	# clamps 0..3, the ledger keeps bools only and reconciles to the tier count
	var blob2 := _base()
	blob2["chaosPeak"] = 7.0
	blob2["scarTier"] = 9
	blob2["scarBenign"] = [true, 3, null, false]
	_write_json(SLOT_CORRUPT, blob2)
	var loader2: Variant = Ctx.new()
	ok(loader2.load(SLOT_CORRUPT), "oversized scar fields load")
	approx(float(loader2.chaos_peak), 1.0, "peak clamps to the meter", 1e-9)
	eq(int(loader2.scar_tier), 3, "tier clamps to 3")
	eq(loader2.scar_benign, [true, false, false],
			"ledger: bools only, reconciled to the tier count")


# ---- the per-run reset ---------------------------------------------------------------

func test_reset_chaos_scar() -> void:
	var ctx: Variant = Ctx.new(13)
	ctx.difficulty = "chaos"
	ctx.karma = 0.9
	ctx.scar_cross(0.95)
	ctx.transposon_apply(ctx.rng.branch())
	eq(int(ctx.scar_tier), 3, "preconditions: three scars fired")
	ok(bool(ctx.flags.get("transposonFired", false)), "preconditions: transposon latched")
	# a NEW LIFE wipes the peak, the fired tiers and the ledger (menu.gd's
	# reset block); the flags wipe next to it clears the transposon latch
	ctx.reset_chaos_scar()
	approx(float(ctx.chaos_peak), 0.0, "the peak wipes", 1e-9)
	eq(int(ctx.scar_tier), 0, "the fired tiers wipe")
	ok(ctx.scar_benign.is_empty(), "the ledger wipes")
	eq(ctx.scar_cross(0.6), [1], "and the fold starts over from zero")


# ---- the live game tick (toast path) ---------------------------------------------------

var _toasts: Array = []


func _rec_toast(text: String, kind: String, icon: String, ttl := 4.0, card: Variant = null) -> void:
	_toasts.append({"text": text, "kind": kind, "icon": icon, "ttl": ttl, "card": card})


func _rec_update(_dt: float) -> void:
	pass


func _rec_dismiss() -> void:
	pass


func _rec_banner(_m: Variant) -> void:
	pass


func _rec_float(_x: float, _y: float, _t: String, _c: Variant, _s: float) -> void:
	pass


func _rec_pointer(_x: float, _y: float) -> bool:
	return false


## Seeded boot → menu (the loop kill-switch makes step_for_testing the only
## clock), with the toast recorder hud installed.
func _flow_game(seed_v: int) -> Variant:
	TranslationServer.set_locale("en")
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_chaos_scar_settings.cfg")
		dir.remove("test_chaos_scar_settings.cfg.tmp")
	var ctx: Variant = Ctx.new(seed_v)
	var g: Variant = GameScript.new(ctx)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(g)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	g.i18n.settings_path = SCRATCH_CFG
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	g.muted = g.i18n.get_muted()
	_toasts = []
	g.hud = {
		"update": _rec_update,
		"dismiss_banner": _rec_dismiss,
		"toast": _rec_toast,
		"banner": _rec_banner,
		"float_world": _rec_float,
		"pointer_down": _rec_pointer,
		"set_toast_inset": func(_px: float) -> void: pass,
	}
	g.register(MenuStageScript.new(g))
	for id in ["cell", "creature", "tribe", "civ", "space"]:
		g.register(FakeStage.new(g, id))
	g.start()
	return g


func _drop(g: Variant) -> void:
	if g != null:
		g.hud = {}  # break the recorder-Callable cycle into this test instance
		g.free()


## helper: push chaos up in one step exactly like a wild act would (the
## meter clamp is add_chaos's own contract)
func context_chaos_bump(ctx: Variant, target: float) -> void:
	ctx.add_chaos(target - float(ctx.chaos))


## helper: the tick's scar toasts — chaos ≥ 0.45 also reveals chaos-gated
## world traits on the first tick (kind "world", orthogonal to this pin)
func _scar_toasts() -> Array:
	var out: Array = []
	for t in _toasts:
		if String(t["kind"]) != "world":
			out.append(t)
	return out


## One game tick with chaos pushed past every threshold announces all three
## scars through the live hud — once; the next tick stays silent.
func test_game_tick_announces_each_crossing_once() -> void:
	var g: Variant = _flow_game(0xC0FFEE)
	g.switch_stage("cell")
	var ctx: Variant = g.context
	ctx.karma = 0.9  # benign run
	context_chaos_bump(ctx, 0.95)
	g.step_for_testing(1)
	eq(_scar_toasts().size(), 3, "one spike → three scar toasts")
	if _scar_toasts().size() == 3:
		for i in 3:
			eq(String(_scar_toasts()[i]["text"]),
					"%s — %s" % [String(SCAR_NAMES[i]), SCAR_BENIGN_BODY],
					"toast %d names the scar + benign body" % (i + 1))
			eq(String(_scar_toasts()[i]["kind"]), "good", "benign toasts ride the good kind")
	var after := _toasts.size()
	g.step_for_testing(1)
	eq(_toasts.size(), after, "the next tick stays silent (crossings fire once)")
	_drop(g)


## A harsh run (karma < 0.3 at the crossing) announces the harsh wording and
## the chaos kind.
func test_game_tick_harsh_wording() -> void:
	var g: Variant = _flow_game(0xC0FFEE)
	g.switch_stage("cell")
	var ctx: Variant = g.context
	ctx.karma = -0.8
	context_chaos_bump(ctx, 0.95)
	g.step_for_testing(1)
	eq(_scar_toasts().size(), 3, "three scar toasts")
	if _scar_toasts().size() == 3:
		eq(String(_scar_toasts()[0]["text"]),
				"%s — %s" % [String(SCAR_NAMES[0]), SCAR_HARSH_BODY],
				"the harsh body rides the toast")
		eq(String(_scar_toasts()[0]["kind"]), "chaos", "harsh toasts ride the chaos kind")
	_drop(g)


## The menu never folds scars: a CONTINUE's loaded chaos must not mint them
## on the title screen (the first gameplay tick does).
func test_menu_tick_never_folds() -> void:
	var g: Variant = _flow_game(0xC0FFEE)
	var ctx: Variant = g.context
	context_chaos_bump(ctx, 0.95)
	g.step_for_testing(1)
	eq(int(ctx.scar_tier), 0, "no scars on the menu tick")
	eq(_toasts.size(), 0, "no toasts on the menu tick")
	_drop(g)


# ---- the i18n shipments -----------------------------------------------------------------

## Every new display string ships in vi.csv (the audit scans the call sites;
## the membership here keeps the translations honest).
func test_scar_and_transposon_strings_ship_in_vi() -> void:
	var i18n: Variant = I18nScript.new(SCRATCH_CFG)
	var keys: Array = SCAR_NAMES.duplicate()
	keys.append(SCAR_BENIGN_BODY)
	keys.append(SCAR_HARSH_BODY)
	keys.append(TRANSPOSON_NAME)
	keys.append(TRANSPOSON_WARN)
	keys.append(TRANSPOSON_TOAST)
	keys.append("revert hue")
	keys.append("Hue restored.")
	for k in keys:
		ok(i18n.vi_has(String(k)), "vi.csv ships: %s" % String(k))
