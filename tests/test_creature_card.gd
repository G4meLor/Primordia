## CreatureCard headless tests — R11 (task 5). The pure functions (stat_bars,
## meta_label, portrait fit) plus the draw_into RID lifecycle on a bare
## offscreen CanvasItem — the card's whole draw path is RenderingServer-level
## (text rides Font.draw_string on the item RID, context-free like the
## painter's RS calls), so everything here runs without xvfb. Pixel
## determinism + the RS-side leak proof live in the xvfb scene test
## (tests/scenes/test_card_render.gd via tools/test_card_scene.sh): headless
## cannot render frames or read the exit RID-warning telemetry.
extends "res://tests/test_base.gd"

const Card := preload("res://src/gfx/creature_card.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

# the painter smoke's fixture genome (size 1.2, legs 4, spots + fur + tail,
# carnivore jaw) plus brain 2 so all three stat bars carry a value
func _genome() -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.2
	g["legs"] = 4
	g["hue"] = 120
	g["sat"] = 0.55
	g["pattern"] = "spots"
	g["coat"] = "fur"
	g["tail"] = true
	g["arms"] = 2
	g["eyes"] = 2
	g["diet"] = "carnivore"
	g["jaw"] = 3
	g["spikes"] = 3
	g["horns"] = 2
	g["brain"] = 2
	return g


# ---- stat_bars (ruling: 3 bars = size / legs / brain) -----------------------

func test_stat_bars_returns_size_legs_brain() -> void:
	var bars: Array = Card.stat_bars(GenomeScript.default_genome())
	eq(bars.size(), 3, "three bars")
	var keys := []
	for b in bars:
		keys.append(String(b["key"]))
	eq(keys, ["size", "legs", "brain"], "bar order size / legs / brain")
	# default genome: size 1 → (1 − 0.6) / 1.6 = 0.25; legs 0; brain 0
	approx(float(bars[0]["frac"]), 0.25, "default size frac 0.25")
	approx(float(bars[1]["frac"]), 0.0, "default legs frac 0")
	approx(float(bars[2]["frac"]), 0.0, "default brain frac 0")
	# labels are the EN keys the editor already ships (vi.csv: BODY SIZE / Leg /
	# Brain) — the draw translates them, the pure function stays untranslated
	eq(String(bars[0]["label"]), "BODY SIZE", "size label key")
	eq(String(bars[1]["label"]), "Leg", "legs label key")
	eq(String(bars[2]["label"]), "Brain", "brain label key")


func test_stat_bars_clamped_and_pure() -> void:
	var g := GenomeScript.default_genome()
	g["size"] = 2.2
	g["legs"] = 8  # the mutation cap (GENE_BOUNDS) — above the buy max 6
	g["brain"] = 5
	var bars: Array = Card.stat_bars(g)
	approx(float(bars[0]["frac"]), 1.0, "size max → 1.0")
	approx(float(bars[1]["frac"]), 1.0, "legs 8 clamps to 1.0")
	approx(float(bars[2]["frac"]), 1.0, "brain max → 1.0")
	var g2 := GenomeScript.default_genome()
	g2["size"] = 0.4  # below the 0.6 bound floor
	approx(float(Card.stat_bars(g2)[0]["frac"]), 0.0, "size below floor → 0.0")
	# pure: the same genome yields the same fracs (determinism contract)
	var a: Array = Card.stat_bars(g)
	var b: Array = Card.stat_bars(g)
	ok(float(a[0]["frac"]) == float(b[0]["frac"]) and float(a[1]["frac"]) == float(b[1]["frac"])
			and float(a[2]["frac"]) == float(b[2]["frac"]), "pure: repeated call identical")


# ---- meta_label (ruling: species + epithet composed via tr BEFORE return) ----

func test_meta_label_composes_species_and_epithet() -> void:
	eq(Card.meta_label({}), "", "empty meta → empty label")
	eq(Card.meta_label({"species": "Glorbus"}), "Glorbus", "species only (no epithet)")
	eq(Card.meta_label({"epithet": "the Spiky"}), "the Spiky", "epithet only")
	# EN passthrough: species first, epithet after (names.full_species_name order)
	eq(Card.meta_label({"species": "Glorbus", "epithet": "the Spiky"}),
			"Glorbus the Spiky", "species + epithet composition order")


func test_meta_label_resolves_translation_before_return() -> void:
	# Scoped vi translation proves the epithet resolves INSIDE meta_label —
	# the QC r6 rule (translate the part, then compose; a plain tr of the
	# composed string could never resolve). Cleanup is unconditional: the
	# assert helpers record failures instead of throwing.
	var tr_res := Translation.new()
	tr_res.set_locale("vi")
	tr_res.add_message("the Spiky", "Gai Nhọn")
	TranslationServer.add_translation(tr_res)
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("vi")
	eq(Card.meta_label({"species": "Glorbus", "epithet": "the Spiky"}),
			"Glorbus Gai Nhọn", "epithet translated before composition")
	TranslationServer.set_locale(prev)
	TranslationServer.remove_translation(tr_res)


# ---- draw_into: bare-item smoke + the deferred RID lifecycle (AC 4) ----------

func test_draw_into_smoke_bare_item_and_release() -> void:
	var ci := Node2D.new()  # offscreen, never in the tree — painter smoke precedent
	Card.draw_into(ci, _genome(), {"species": "Glorbus", "epithet": "the Spiky"},
			Rect2(20.0, 10.0, 220.0, 160.0))
	var rids: Array = Card._rids_for(ci)
	eq(rids.size(), 3, "registry holds the 3 painter sub-RIDs for this item")
	for rid in rids:
		ok((rid as RID).is_valid(), "sub-RID valid (clip/pattern/front)")
	Card.release(ci)
	eq(Card._rids_for(ci).size(), 0, "release empties the entry")
	Card.release(ci)  # must not error on an already-empty entry
	ok(true, "double release is a no-op")
	ci.free()


func test_draw_into_second_draw_frees_previous_rids() -> void:
	# the deferred lifecycle: draw N frees card N-1 (content must survive the
	# call to reach a rendered frame, so a card cannot free its OWN sub-items)
	var ci := Node2D.new()
	Card.draw_into(ci, _genome(), {}, Rect2(0.0, 0.0, 220.0, 160.0))
	var first: Array = Card._rids_for(ci)
	Card.draw_into(ci, _genome(), {"species": "Zor"}, Rect2(0.0, 0.0, 220.0, 160.0))
	var second: Array = Card._rids_for(ci)
	eq(second.size(), 3, "second draw: registry still holds exactly 3")
	for rid in first:
		ok(not second.has(rid), "previous triple freed — fresh sub-items per draw")
	Card.release(ci)
	ci.free()


func test_draw_loop_50_steady_state() -> void:
	# the leak guard's headless half: 50 draw_into calls must not accumulate —
	# the registry holds exactly the last card's 3 sub-RIDs. (The RS-side proof
	# — exit RID-warning delta 0 vs the baseline card — is the scene test.)
	var ci := Node2D.new()
	var meta := {"species": "Glorbus", "epithet": "the Spiky"}
	for i in 50:
		RenderingServer.canvas_item_clear(ci.get_canvas_item())
		Card.draw_into(ci, _genome(), meta, Rect2(30.0, 20.0, 220.0, 160.0))
	var rids: Array = Card._rids_for(ci)
	eq(rids.size(), 3, "50× loop: steady state = exactly 3 live sub-RIDs")
	for rid in rids:
		ok((rid as RID).is_valid(), "steady-state sub-RID valid")
	Card.release(ci)
	eq(Card._rids_for(ci).size(), 0, "release after the loop is clean")
	ci.free()


# ---- portrait fit: pure geometry (the pixel twin is the scene test) ----------

func test_portrait_fit_deterministic_and_in_bounds() -> void:
	# body plans that span the painter's blocks: full kit, legless worm,
	# max size, min size + wings. Sane rects only — the MIN_ZOOM floor
	# (tiny rect, huge genome) is a deliberate overflow clamp, untested here.
	var rect := Rect2(40.0, 30.0, 220.0, 160.0)
	for variant in [{"legs": 4, "tail": true, "arms": 2, "horns": 2, "wings": 2},
			{"legs": 0}, {"size": 2.2}, {"size": 0.6, "wings": 2}]:
		var g := GenomeScript.default_genome()
		g.merge(variant, true)
		var f1: Dictionary = Card._portrait_fit(g, rect)
		var f2: Dictionary = Card._portrait_fit(g, rect)
		ok(absf(float(f1["zoom"]) - float(f2["zoom"])) <= 1e-12, "fit pure: zoom stable")
		ok((f1["pos"] as Vector2).is_equal_approx(f2["pos"]), "fit pure: pos stable")
		var zoom: float = float(f1["zoom"])
		ok(zoom >= Card.MIN_ZOOM and zoom <= Card.MAX_ZOOM, "zoom within the clamp")
		var bbox: Rect2 = f1["bbox"]
		var pw: float = rect.size.x * Card.PORTRAIT_FRAC
		ok(zoom * bbox.size.x <= pw + 0.001, "scaled bbox fits the portrait width")
		ok(zoom * bbox.size.y <= rect.size.y + 0.001, "scaled bbox fits the portrait height")
		# pos maps the bbox center onto the portrait center
		var want: Vector2 = (rect.position + Vector2(pw, rect.size.y) * 0.5) \
				- (bbox.position + bbox.size * 0.5) * zoom
		ok((f1["pos"] as Vector2).is_equal_approx(want), "pos centers the bbox in the portrait")
