## Task 10 determinism SHARD (spawned by tests/test_econ_probes.gd — not a
## test_* file, the runner never picks it up). One shard builds every seed in
## [from, to) TWICE (the T3 bot-arc A/B pattern at scale), runs a 600-tick cell
## sim with the T6-style scripted messy input (headless input-dictionary form),
## and quantizes the end state into a fingerprint (T6 fingerprint extended with
## pellet/zone counts + eco state). A == B per seed, else exit 1 with the
## failing seeds on stdout and the JSON written for the parent.
##
## Usage: godot --headless -s res://tests/econ_det_shard.gd --path . -- <out.json> <from> <to>
extends SceneTree

const CtxScript := preload("res://src/game/context.gd")
const CellSimScript := preload("res://src/game/cell/cell_sim.gd")

const DT := 1.0 / 60.0
const TICKS := 600


var _ran := false


func _process(_d: float) -> bool:
	if _ran:
		return true
	_ran = true
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("DET_SHARD_FAIL: need <out.json> <from> <to>")
		quit(1)
		return true
	var out_path: String = args[0]
	var from_seed := int(args[1])
	var to_seed := int(args[2])
	var bad: Array = []
	var t0 := Time.get_ticks_msec()
	for seed_v in range(from_seed, to_seed):
		var a := _run_seed(seed_v)
		var b := _run_seed(seed_v)
		if a != b:
			bad.append(seed_v)
			print("DET_SHARD_DIVERGED seed=%d a=%d b=%d" % [seed_v, a, b])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("DET_SHARD_FAIL: cannot write %s" % out_path)
		quit(1)
		return true
	f.store_string(JSON.stringify({"from": from_seed, "to": to_seed,
			"ms": Time.get_ticks_msec() - t0, "bad": bad}))
	f.close()
	if not bad.is_empty():
		printerr("DET_SHARD_FAIL: %d diverged seeds in [%d,%d)" % [bad.size(), from_seed, to_seed])
		quit(1)
		return true
	print("DET_SHARD_OK [%d,%d) in %d ms" % [from_seed, to_seed, Time.get_ticks_msec() - t0])
	quit(0)
	return true


## One full A-or-B pass for a seed: bootstrap → 600 scripted-input ticks →
## quantized state hash.
func _run_seed(seed_v: int) -> int:
	var ctx: Variant = CtxScript.new(seed_v)
	var sim: Variant = CellSimScript.new(ctx, ctx.rng.branch(), {})
	var lcg := 12345  # the T6 bot LCG seed — same scripted walk for A and B
	var target_x := 100.0
	var target_y := 100.0
	var inp := {"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0, "down": false,
			"clicked": false, "take_click": false, "keys_held": [], "keys_pressed": []}
	for f in TICKS:
		if f % 90 == 0:
			lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
			var r1: float = float(lcg) / float(0x7fffffff)
			lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
			var r2: float = float(lcg) / float(0x7fffffff)
			target_x = float(sim.px) + (r1 - 0.5) * 900.0
			target_y = float(sim.py) + (r2 - 0.5) * 900.0
			inp["down"] = true
		elif f % 90 == 45:
			inp["down"] = false
		inp["wx"] = target_x
		inp["wy"] = target_y
		var pressed: Array = []
		if f % 240 == 120:
			pressed.append("Space")
		if f % 300 == 200:
			pressed.append("Digit1")
		if f % 360 == 300:
			pressed.append("Digit2")
		if f % 180 == 90:
			pressed.append("KeyE")
		inp["keys_pressed"] = pressed
		sim.update(DT, inp)
	return _hash(sim, ctx)


## T6 fingerprint, extended: pellet/zone counts, eco state, rng stream states.
func _hash(sim: Variant, ctx: Variant) -> int:
	var rows := PackedStringArray()
	rows.append("px=%d py=%d pvx=%d pvy=%d php=%d time=%d" % [
		floori(float(sim.px) * 100.0), floori(float(sim.py) * 100.0),
		floori(float(sim.pvx) * 1000.0), floori(float(sim.pvy) * 1000.0),
		floori(float(sim.php) * 1000.0), floori(float(sim.time) * 1000.0)])
	rows.append("dna=%d chaos=%d karma=%d kills=%d" % [
		int(ctx.dna), floori(float(ctx.chaos) * 1000.0),
		floori(float(ctx.karma) * 1e6), int(ctx.world_stats["kills"])])
	rows.append("ents=%d" % sim.ents.size())
	for e in sim.ents:
		rows.append("e %s %d %d %d" % [String(e["speciesId"]),
				floori(float(e["x"]) * 100.0), floori(float(e["y"]) * 100.0),
				floori(float(e["hp"]) * 1000.0)])
	rows.append("pel=%d zones=%d" % [sim.pellets.size(), sim.zones.size()])
	for p in sim.pellets:
		rows.append("p %s %d %d" % [String(p["kind"]),
				floori(float(p["x"]) * 100.0), floori(float(p["y"]) * 100.0)])
	var eco: Variant = sim.eco
	rows.append("flora=%d corpses=%d n=%d" % [floori(float(eco.flora) * 1000.0),
			floori(float(eco.corpses) * 1000.0), eco.species.size()])
	for sp in eco.species:
		rows.append("s %s %d %d" % [String(sp["id"]), floori(float(sp["pop"]) * 1000.0),
				1 if bool(sp.get("extinct", false)) else 0])
	rows.append("rng=%d eco=%d chaos=%d" % [int(sim.rng.state()),
			int(eco.rng.state()), int(sim.chaos._rng.state())])
	return String("\n".join(rows)).hash()
