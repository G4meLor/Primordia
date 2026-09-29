// Glitch chaos-event overlay — the Godot equivalent of the TS canvas
// 'difference' composite fillRect (CellStage.ts:1155-1161):
//   globalCompositeOperation = 'difference';
//   fillStyle = rgba(120,255,180, 0.06 + sin(t*12)*0.03)
// The W3C difference blend with source alpha a over an opaque backdrop is
// Co = a·|Cb − Cs| + (1−a)·Cb — ported exactly. The animated alpha rides the
// `strength` uniform (the stage sets it from sim time — frame-deterministic,
// no TIME dependency). SCREEN_TEXTURE reads the back buffer as of the
// BackBufferCopy node sitting between the world canvas (…+ vignette) and this
// overlay — the same position the TS fillRect occupies in its draw order.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec4 tint : source_color = vec4(0.470588, 1.0, 0.705882, 0.09);

void fragment() {
	vec4 prev = texture(screen_tex, SCREEN_UV);
	COLOR = vec4(mix(prev.rgb, abs(prev.rgb - tint.rgb), tint.a), 1.0);
}
