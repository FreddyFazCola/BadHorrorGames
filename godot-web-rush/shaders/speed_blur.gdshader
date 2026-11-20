shader_type canvas_item;

// Radial speed blur.
//
// This is the "motion blur" the Insomniac games actually read as at speed, and
// it is worth being precise about why it is this and not per-object motion
// blur. True camera motion blur is not a built-in in Godot 4 - its Environment
// offers glow, SSAO, SSIL, SSR, depth of field, fog and tonemapping, but no
// motion blur - so it would mean a custom CompositorEffect with its own
// compute shader. What sells the sensation of being flung through a street
// canyon, though, isn't accurate per-pixel velocity: it's the frame smearing
// outward from the centre of vision while the middle stays readable. That is
// exactly a radial blur, it costs one full-screen pass, and it is driven
// straight off the player's speed.
//
// `hint_screen_texture` makes Godot copy what has been drawn so far into a
// back buffer, so a full-screen quad on a CanvasLayer above the 3D viewport
// gets the rendered frame to sample.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// 0 = untouched. Scaled by how far from centre each pixel is, so the smear
// grows toward the edges on its own.
uniform float amount : hint_range(0.0, 0.3) = 0.0;

// The centre of the smear, in screen UV. Leading it toward where the player is
// travelling rather than pinning it to the middle of the screen keeps the
// focal point on the direction of flight.
uniform vec2 centre = vec2(0.5, 0.5);

const int SAMPLES = 10;

void fragment() {
    vec2 dir = SCREEN_UV - centre;
    vec3 acc = vec3(0.0);
    float total = 0.0;

    for (int i = 0; i < SAMPLES; i++) {
        float t = float(i) / float(SAMPLES - 1);
        // Near samples weigh more than far ones. A flat average smears the
        // whole image evenly, which reads as a smudged lens rather than speed;
        // falling off keeps an in-focus core with the motion trailing off it.
        float w = 1.0 - t * 0.65;
        acc += texture(screen_tex, SCREEN_UV - dir * (t * amount)).rgb * w;
        total += w;
    }

    COLOR = vec4(acc / total, 1.0);
}
