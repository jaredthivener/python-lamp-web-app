// Scene - draws the lamp and its light with one full-screen fragment shader.
//
// The canvas sits on top of the page and its alpha channel is darkness: where the lamp's
// light lands it is transparent and the page shows through, everywhere else it is black.
// Colour is only for what is solid or glows (the lamp itself, haze, dust, moonlight).

const VERTEX = `#version 300 es
void main() {
    // One triangle that covers the screen; no buffers needed.
    gl_Position = vec4(vec2(gl_VertexID & 1, gl_VertexID >> 1) * 4. - 1., 0., 1.);
}`;

const FRAGMENT = `#version 300 es
precision highp float;

uniform vec2 uRes;       // canvas size in device pixels
uniform float uDpr;
uniform vec2 uPivot;     // where the cord meets the ceiling (CSS px, like every length below)
uniform vec2 uTop;       // where the cord meets the lamp
uniform float uR;        // half-width of the shade: the unit every lamp part is sized in
uniform float uTilt;     // how far the lamp body leans from vertical
uniform float uHeat;     // filament temperature, 0..1
uniform float uTime;
uniform float uHint;     // 1 while the knob glints to invite a first pull
uniform vec2 uChain[9];  // pull-chain joints, from inside the shade down to the knob
uniform vec4 uCards[4];  // raised cards on the wall: centre.xy, half-size.zw
uniform vec2 uDesk;      // the desk's top surface: y where it meets the wall, y of its front edge
out vec4 fragColor;

// Signed distance in CSS px -> antialiased coverage.
#define AA(d) clamp(.5 - (d) * uDpr, 0., 1.)
// Paint something solid over what is there.
#define OVER(c, a) { float k = a; color = mix(color, c, k); dark = mix(dark, 1., k); }

const vec3 MOON_DIR = vec3(-.50, -.50, .707);
const vec3 MOON = vec3(.17, .22, .32);
const vec3 BRASS = vec3(.78, .56, .24);
const vec3 ENAMEL = vec3(.045, .17, .145);

float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * .1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3. - 2. * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0., a = .5;
    for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + 17.; a *= .5; }
    return v;
}

float sdBox(vec2 p, vec2 size, float r) {
    vec2 d = abs(p) - size + r;
    return length(max(d, 0.)) + min(max(d.x, d.y), 0.) - r;
}

// Wood: long streaks of grain and the odd wandering ring, laid in boards.
// at.x runs along the boards in px, at.y across them in boards.
vec3 wood(vec2 at) {
    float board = floor(at.y), across = fract(at.y);
    float x = at.x + 900. * hash(vec2(board, 7.));
    float streak = .6 * noise(vec2(x * .004, at.y * 26.)) + .4 * noise(vec2(x * .009 + 5., at.y * 61.));
    float ring = .5 + .5 * sin(at.y * 40. + 9. * noise(vec2(x * .0022, at.y * 2.5)));
    vec3 tone = mix(vec3(.13, .085, .055), vec3(.40, .29, .19), mix(.35, 1., streak) * mix(.7, 1., ring));
    float seam = smoothstep(0., .03, across) * smoothstep(1., .97, across);
    return tone * (.9 + .2 * hash(vec2(board, 3.))) * mix(.45, 1., seam);
}

// One light on a surface with normal n, seen from straight ahead.
vec3 lit(vec3 n, vec3 base, vec3 dir, vec3 light, float gloss) {
    float spec = pow(max(dot(n, normalize(dir + vec3(0, 0, 1))), 0.), gloss);
    return light * (base * max(dot(n, dir), 0.) + spec);
}

// Normal of a dome seen from above. Points outside it are pinned to the edge: these are
// evaluated for every pixel, and an unbounded normal overflows the specular term into NaN.
vec3 dome(vec2 n) {
    n *= inversesqrt(max(dot(n, n), 1.));
    return vec3(n, sqrt(max(0., 1. - dot(n, n))));
}

void main() {
    vec2 p = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y) / uDpr;
    vec2 view = uRes / uDpr;
    float R = uR;

    // Lamp frame: origin where the cord joins, axis down through the bulb, side across it.
    vec2 axis = vec2(sin(uTilt), cos(uTilt));
    vec2 side = vec2(axis.y, -axis.x);
    vec2 q = vec2(dot(p - uTop, side), dot(p - uTop, axis));

    float shadeTop = .2 * R, shadeH = .94 * R, rim = shadeTop + shadeH;
    float bulbR = .27 * R;
    vec2 bulbQ = vec2(0., rim - .05 * R);
    vec2 bulb = uTop + axis * bulbQ.y;

    // An incandescent filament: light output rises far faster than temperature, and
    // the colour reddens as it cools.
    float glow = pow(uHeat, 3.5);
    vec3 warm = mix(vec3(1., .28, .04), vec3(1., .80, .55), uHeat * uHeat);

    // ---- Light reaching the wall ---------------------------------------------------
    vec2 w = p - bulb;
    float wallGap = .42 * view.y;                    // how far the lamp hangs from the wall
    float r2 = dot(w, w) + wallGap * wallGap;
    float falloff = wallGap * wallGap * wallGap / (r2 * sqrt(r2));   // inverse square x cosine
    // The shade only lets light out downwards: a cone, which meets the wall as a hyperbola.
    float coneGap = .45 * wallGap;
    float cone = smoothstep(.30, .50, dot(w, axis) / sqrt(dot(w, w) + coneGap * coneGap));
    float direct = 4.5 * glow * falloff * cone;

    // Each card floats just off the wall, so it blocks the rays that pass through it.
    float shadow = 0.;
    for (int i = 0; i < 4; i++) {
        vec4 card = uCards[i];
        if (card.z < 1.) continue;
        vec2 lifted = bulb + w * .972;               // where this ray crossed the card's height
        float edge = 2. + .012 * length(w);          // penumbra widens with distance
        float blocked = 1. - smoothstep(-edge, edge, sdBox(lifted - card.xy, card.zw, 6.));
        shadow = max(shadow, blocked * smoothstep(-1., 1., sdBox(p - card.xy, card.zw, 6.)));
    }
    direct *= 1. - .85 * shadow;

    // Moonlight through a window behind the viewer: a slanted patch of four panes.
    vec2 m = p - view * vec2(.40, .40);
    m.x += m.y * .30;
    m = abs(m / vec2(min(.21 * view.y, .42 * view.x), .34 * view.y));
    float moon = smoothstep(1., .93, m.x) * smoothstep(1., .96, m.y)
               * smoothstep(.03, .07, m.x) * smoothstep(.02, .045, m.y);

    float plaster = .90 + .2 * fbm(p * .011) + .03 * (hash(floor(p * 1.5)) - .5);
    float night = 1. - .88 * glow;                   // the eye stops noticing moonlight once the lamp is on
    float lux = direct + glow * (.45 * falloff + .05) + (.13 * moon + .035) * night;
    float dark = 1. - (1. - exp(-lux)) * plaster;
    vec3 color = vec3(.012, .035, .085) * moon * night
               + vec3(.008, .014, .028) * dark                       // shadows stay cool, never dead black
               + vec3(1., .88, .68) * .1 * smoothstep(1.8, 4.5, direct);  // the wall overexposes nearest the bulb

    // ---- The desk ------------------------------------------------------------------
    // Seen from in front and a little above: the top is a band that foreshortens toward
    // the wall, and under it is the front edge.
    float deskDepth = uDesk.y - uDesk.x;
    float depth = clamp((p.y - uDesk.x) / deskDepth, 0., 1.);        // 0 at the wall, 1 at the front edge
    dark = mix(dark, 1., .3 * smoothstep(.3 * deskDepth, 0., uDesk.x - p.y) * step(p.y, uDesk.x));  // the corner where they meet
    if (p.y > uDesk.x - 1.) {
        float across = (p.x - .5 * view.x) * mix(1.22, 1., depth);  // further back, the same width shows more desk
        vec3 fromBulb = vec3(p.x - bulb.x, mix(uDesk.x, uDesk.y, .6) - bulb.y, (depth - .55) * 2.6 * R);
        float reach = length(fromBulb);
        float pool = pow(fromBulb.y / reach, 3.) * smoothstep(.30, .50, dot(fromBulb.xy, axis) / reach);
        vec3 cool = vec3(.022, .030, .050) * night;
        vec3 surface;
        if (p.y < uDesk.y) {
            vec3 grain = wood(vec2(across, 3. * depth * (.45 + .55 * depth)));
            float sheen = pow(max(0., 1. - length(vec2(fromBulb.x / (2.4 * R), (depth - .85) / .8))), 2.);
            surface = grain * (warm * glow * (1.5 * pool + .07) + cool) * mix(.55, 1., smoothstep(0., .2, depth))
                    + warm * glow * pool * sheen * .10 * (.4 + grain.r * 2.);   // varnish catching the bulb
        } else {
            float down = (p.y - uDesk.y) / (.5 * deskDepth);
            vec3 grain = wood(vec2(across * .9 + 300., 4. + down * .8));
            surface = grain * (warm * glow * (.38 * pool + .035) + cool) * mix(1., .45, clamp(down, 0., 1.))
                    + warm * glow * pool * .14 * smoothstep(2.5, 0., p.y - uDesk.y);   // the lit top corner of the edge
        }
        OVER(1. - exp(-1.5 * surface), AA(uDesk.x - p.y))
    }

    // ---- Light caught in the air ---------------------------------------------------
    float dist = length(w) + 1e-4;
    float beam = smoothstep(.25, .9, dot(w, axis) / dist) * exp(-dist / (6. * R));
    color += warm * glow * beam * .07 * (.6 + .8 * fbm(p * .005 + uTime * vec2(.012, -.03)));

    float motes = 0.;
    for (int i = 0; i < 3; i++) {
        float k = float(i);
        float cell = R * (.5 + .45 * k);
        vec2 g = (p + uTime * vec2(4., -2.5) * (1. + k)) / cell + k * 31.7;
        vec2 id = floor(g);
        vec2 at = .5 + .3 * (vec2(hash(id), hash(id + 7.7)) - .5)
                + .12 * sin(uTime * (.3 + .4 * hash(id + 3.3)) + 6.28 * vec2(hash(id + 1.1), hash(id + 5.5)));
        float size = 1. + 1.3 * k;                   // near motes are large and soft
        float mote = smoothstep(size, size * .2, length(fract(g) - at) * cell);
        mote *= step(.5, hash(id + 9.9)) * (.55 + .45 * sin(uTime * (1. + hash(id + 2.2)) + 40. * hash(id)));
        motes += mote / (1. + k);
    }
    color += warm * glow * beam * motes * .8;

    // ---- The lamp ------------------------------------------------------------------
    vec3 ambient = vec3(.020, .028, .045) + warm * glow * .16;   // night sky + bounce off the lit wall

    // Cord: a taut line from the ceiling to the lamp
    vec2 span = uTop - uPivot;
    float along = clamp(dot(p - uPivot, span) / dot(span, span), 0., 1.);
    OVER(vec3(.10, .09, .08) * (ambient * 6. + MOON * (.6 + .4 * sin(along * length(span) * .9))),
         AA(distance(p, uPivot + span * along) - .016 * R))

    // Ceiling rose
    vec2 rose = (p - uPivot) / vec2(.34 * R, .12 * R);
    vec3 rn = dome(rose * .9);
    OVER(BRASS * ambient * 3. * (.25 + .75 * rn.z * rn.z) + lit(rn, BRASS, MOON_DIR, MOON, 24.), AA((length(rose) - 1.) * .12 * R))

    // Shade: a bell of green enamel, dark on the outside even when lit
    float t = clamp((q.y - shadeTop) / shadeH, 0., 1.);
    float profile = R * (.2 + .8 * pow(t, .6));
    float slope = .48 * pow(max(t, .03), -.4) * R / shadeH;
    float shade = max((abs(q.x) - profile) / sqrt(1. + slope * slope), max(shadeTop - q.y, q.y - rim));
    float nx = clamp(q.x / profile, -1., 1.);
    vec3 sn = normalize(vec3(nx, -slope, sqrt(1. - nx * nx)));
    OVER(ENAMEL * ambient * 5.
         + lit(sn, ENAMEL, MOON_DIR, MOON * 1.4, 26.)
         + lit(sn, ENAMEL, normalize(vec3(0., .8, .6)), warm * glow * .7, 10.), AA(shade))

    // Brass cap where the cord goes in
    vec2 cap = q - vec2(0., .1 * R);
    vec3 cn = dome(vec2(clamp(cap.x / (.15 * R), -1., 1.), 0.));
    OVER(BRASS * ambient * 3. * (.25 + .75 * cn.z * cn.z) + lit(cn, BRASS, MOON_DIR, MOON * 1.3, 18.),
         AA(sdBox(cap, vec2(.15, .14) * R, .05 * R)))

    // We look up at the lamp a little, so the shade's mouth is an ellipse with the white
    // inside showing. Everything hanging in there is hidden above that ellipse.
    vec2 o = (q - vec2(0., rim)) / vec2(R, .11 * R);
    float mouth = AA((length(o) - 1.) * .11 * R);
    float below = max(mouth, step(rim, q.y));
    vec3 inside = vec3(.85, .82, .75) * (ambient * 3. + MOON * .3 * (.6 - .4 * o.x))
                + warm * glow * (.95 - .55 * o.x * o.x - .15 * o.y);
    OVER(min(inside, 1.), mouth)
    OVER(ENAMEL * (ambient * 9. + MOON) + warm * glow * .5, AA(abs(length(o) - 1.) * .11 * R - .6) * .9)   // rolled lip

    // Bulb: dark glass until the filament heats it
    vec2 b = (q - bulbQ) / bulbR;
    float bb = dot(b, b);
    vec3 glass = vec3(.16, .19, .24) * (.2 + .8 * bb * bb) * (ambient * 9. + MOON)
               + lit(dome(b), vec3(0.), MOON_DIR, MOON * 2.5, 60.);
    float filament = AA(abs(b.y + .12 - .045 * sin(b.x * 42.)) * bulbR - .7) * step(abs(b.x), .4);
    vec3 hot = warm * (1.7 - .8 * bb) * pow(uHeat, 2.5) + vec3(1., .55, .2) * filament * pow(uHeat, 1.5) * 2.;
    OVER(min(glass + hot, 1.), AA((sqrt(bb) - 1.) * bulbR) * below)

    // Ball chain. Beads are counted up from the knob, so they keep their spacing while
    // the top link slides out of the shade.
    vec2 knob = uChain[8];
    float knobR = .085 * R, beadR = .028 * R, pitch = .08 * R;
    if (distance(p, .5 * (uChain[0] + knob)) < R) {
        for (int i = 0; i < 8; i++) {
            vec2 a = uChain[i + 1], up = uChain[i] - a;
            float len = length(up);
            up /= max(len, 1e-4);
            float s = clamp(dot(p - a, up), 0., len);
            vec2 bead = a + up * min(round(s / pitch), floor(len / pitch)) * pitch;
            vec3 lampDir = normalize(vec3(bulb - bead, .6 * R));
            vec3 lampLight = warm * glow * 2.2 * R / (R + distance(bulb, bead));
            OVER(BRASS * (ambient * 3. + lampLight * .4), AA(distance(p, a + up * s) - .5) * .8 * below)
            vec3 n = dome((p - bead) / beadR);
            OVER(BRASS * ambient * 3. + lit(n, BRASS, MOON_DIR, MOON * 1.5, 30.) + lit(n, BRASS, lampDir, lampLight, 30.),
                 AA(distance(p, bead) - beadR) * below)
        }
    }

    // Knob
    vec2 kp = p - knob;
    vec3 kn = dome(kp / knobR);
    vec3 knobLamp = warm * glow * 2.2 * R / (R + distance(bulb, knob));
    OVER(BRASS * ambient * 3. + lit(kn, BRASS, MOON_DIR, MOON * 1.6, 40.)
         + lit(kn, BRASS, normalize(vec3(bulb - knob, .6 * R)), knobLamp, 40.), AA(length(kp) - knobR))
    // In the dark it breathes a little light, so there is something to reach for.
    color += vec3(1., .72, .38) * uHint * (1. - glow) * (.5 + .5 * sin(uTime * 2.4)) * .2
           * exp(-dot(kp, kp) / (.14 * R * R));

    // What a lens does with a bare bulb: a tight core and a wide veil
    vec2 e = (p - bulb - axis * .12 * R) / R;
    float e2 = dot(e, e);
    color += warm * glow * (.9 * exp(-e2 * 9.) * mix(.3, 1., max(below, 1. - AA(shade))) + .22 / (1. + e2 * 2.5));

    // Corners fall away; a little grain stops the dark gradients from banding.
    vec2 uv = p / view - .5;
    dark = mix(dark, 1., .4 * smoothstep(.3, 1., 2. * dot(uv, uv)));
    float grain = (hash(gl_FragCoord.xy + fract(uTime) * 91.) - .5) / 128.;
    color = clamp(color + grain, 0., 1.);
    // Premultiplied alpha: anything that glows must also cover at least that much.
    fragColor = vec4(color, clamp(max(dark + grain, max(color.r, max(color.g, color.b))), 0., 1.));
}`;

const UNIFORMS = ['uRes', 'uDpr', 'uPivot', 'uTop', 'uR', 'uTilt', 'uHeat', 'uTime', 'uHint', 'uChain', 'uCards', 'uDesk'];

/**
 * Set up the scene on a canvas. Returns { draw(state) }, or null when WebGL 2 is unavailable.
 */
export function createScene(canvas) {
    const gl = canvas.getContext('webgl2', { antialias: false, depth: false, stencil: false });
    if (!gl) return null;

    let u;
    const build = () => {
        const program = gl.createProgram();
        for (const [type, source] of [[gl.VERTEX_SHADER, VERTEX], [gl.FRAGMENT_SHADER, FRAGMENT]]) {
            const shader = gl.createShader(type);
            gl.shaderSource(shader, source);
            gl.compileShader(shader);
            if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
            gl.attachShader(program, shader);
        }
        gl.linkProgram(program);
        gl.useProgram(program);
        u = Object.fromEntries(UNIFORMS.map((name) => [name, gl.getUniformLocation(program, name)]));
    };

    try {
        build();
    } catch (error) {
        console.error('Lamp shader failed to compile:', error);
        return null;
    }
    canvas.addEventListener('webglcontextlost', (e) => e.preventDefault());
    canvas.addEventListener('webglcontextrestored', build);

    // How many pixels to shade. If the display's frames start being missed, shade fewer:
    // a slightly softer picture is far better than a stuttering one.
    let budget = 4.2e6, lastDraw = 0;
    const gaps = [];

    return {
        draw({ pivot, top, R, tilt, heat, time, hint, chain, cards, desk }) {
            const now = performance.now();
            if (now - lastDraw < 200) gaps.push(now - lastDraw);  // ignore pauses, such as a hidden tab
            lastDraw = now;
            if (gaps.length === 120) {
                gaps.sort((a, b) => a - b);
                // On time, the typical gap between frames matches the quickest ones. When most
                // frames take half as long again, the GPU is not keeping up.
                // ponytail: only ever steps down; a page left open never claws quality back.
                if (gaps[60] > 1.5 * gaps[12] && budget > 1.2e6) budget *= 0.75;
                gaps.length = 0;
            }
            const cssW = canvas.clientWidth, cssH = canvas.clientHeight;
            const dpr = Math.min(devicePixelRatio, 2, Math.sqrt(budget / (cssW * cssH)));
            const w = Math.round(cssW * dpr), h = Math.round(cssH * dpr);
            if (canvas.width !== w || canvas.height !== h) {
                canvas.width = w;
                canvas.height = h;
                gl.viewport(0, 0, w, h);
            }
            gl.uniform2f(u.uRes, w, h);
            gl.uniform1f(u.uDpr, dpr);
            gl.uniform2f(u.uPivot, pivot.x, pivot.y);
            gl.uniform2f(u.uTop, top.x, top.y);
            gl.uniform1f(u.uR, R);
            gl.uniform1f(u.uTilt, tilt);
            gl.uniform1f(u.uHeat, heat);
            gl.uniform1f(u.uTime, time);
            gl.uniform1f(u.uHint, hint);
            gl.uniform2fv(u.uChain, chain);
            gl.uniform4fv(u.uCards, cards);
            gl.uniform2f(u.uDesk, desk.top, desk.front);
            gl.drawArrays(gl.TRIANGLES, 0, 3);
        },
    };
}
