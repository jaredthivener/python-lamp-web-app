// Checks that the lamp moves like a lamp. Run with: npm test
import assert from 'node:assert/strict';
import test from 'node:test';

import { Lamp, TUNING } from '../src/static/physics.js';

const R = 117, CORD = 144;  // a 1440x900 window

function hang() {
    const lamp = new Lamp();
    lamp.place({ x: 720, y: 0 }, R, CORD);
    return lamp;
}

/** Step for a while. `each(t)` runs before every step. Returns how often the switch clicked. */
function run(lamp, seconds, each, dt = 1 / 240) {
    let clicks = 0;
    for (let t = 0; t < seconds; t += dt) {
        each?.(t);
        if (lamp.step(dt)) clicks++;
    }
    return clicks;
}

/** Take the knob and move it by (dx, dy) over `seconds`. */
function pull(lamp, dx, dy, seconds, dt) {
    const from = { ...lamp.knob };
    lamp.grab();
    return run(lamp, seconds, (t) => lamp.drag(from.x + dx * t / seconds, from.y + dy * t / seconds), dt);
}

test('a straight pull clicks once, dips the shade on the chain side, and the lamp comes back to rest', () => {
    const lamp = hang(), rest = { ...lamp.knob };

    const clicks = pull(lamp, 0, 60, 0.15) + run(lamp, 0.5);
    assert.equal(clicks, 1);
    assert.ok(lamp.tilt < -0.1, `shade should dip toward the chain, tilt was ${lamp.tilt}`);

    lamp.release();
    run(lamp, 12);
    assert.deepEqual([lamp.swingRate, lamp.tiltRate], [0, 0], 'friction brings it to a dead stop');
    assert.ok(Math.abs(lamp.swing) < 0.02 && Math.abs(lamp.tilt) < 0.02, 'hanging straight again');
    assert.ok(Math.hypot(lamp.knob.x - rest.x, lamp.knob.y - rest.y) < 3, 'knob back where it hangs');
});

test('a lamp held by its chain goes still in the hand', () => {
    const lamp = hang();
    pull(lamp, -260, 170, 0.2);
    run(lamp, 1.5);
    const held = { swing: lamp.swing, tilt: lamp.tilt, x: lamp.knob.x, y: lamp.knob.y };
    run(lamp, 1);
    assert.ok(Math.abs(lamp.swing - held.swing) < 0.002 && Math.abs(lamp.tilt - held.tilt) < 0.002);
    assert.ok(Math.hypot(lamp.knob.x - held.x, lamp.knob.y - held.y) < 0.5);
    assert.ok(lamp.swing < -0.1, 'and it has been hauled toward the hand');
});

test('letting go keeps the speed the hand had', () => {
    const lamp = hang();
    pull(lamp, 80, -20, 0.1);  // 800 px/s sideways
    const before = lamp.knob.x;
    lamp.release();
    run(lamp, 2 / 240);
    assert.ok((lamp.knob.x - before) * 120 > 500);
});

test('a scripted tug draws the chain without clicking or jumping the knob', () => {
    const lamp = hang();
    lamp.chain.forEach((joint, i) => { joint.x += i * 5; joint.px = joint.x; });  // set it swinging
    run(lamp, 0.25);

    lamp.tug();
    let last = { ...lamp.knob }, jump = 0, drawn = 0;
    const clicks = run(lamp, 1.5, () => {
        jump = Math.max(jump, Math.hypot(lamp.knob.x - last.x, lamp.knob.y - last.y));
        last = { ...lamp.knob };
        drawn = Math.max(drawn, lamp.pull);
    });
    assert.equal(clicks, 0);
    assert.ok(jump < 4, `knob moved ${jump} px in one step`);
    assert.ok(drawn > 0.5 * TUNING.travel * R);
    assert.equal(lamp.hand, null);
});

test('with the dampers off, a free swing keeps its energy', () => {
    const saved = { ...TUNING };
    Object.assign(TUNING, { swingDamping: 0, rockDamping: 0, friction: 0 });
    try {
        const lamp = hang();
        Object.assign(lamp, { swing: 0.4, tilt: -0.2 });
        const g = TUNING.gravity * R, L2 = TUNING.centreOfMass * R, k2 = (TUNING.gyration * R) ** 2;
        const energy = () => {
            const vx = CORD * Math.cos(lamp.swing) * lamp.swingRate + L2 * Math.cos(lamp.tilt) * lamp.tiltRate;
            const vy = -CORD * Math.sin(lamp.swing) * lamp.swingRate - L2 * Math.sin(lamp.tilt) * lamp.tiltRate;
            return (vx * vx + vy * vy) / 2 + k2 * lamp.tiltRate ** 2 / 2 - g * (CORD * Math.cos(lamp.swing) + L2 * Math.cos(lamp.tilt));
        };
        const start = energy(), scale = g * (CORD + L2) * (1 - Math.cos(0.4));
        let drift = 0;
        run(lamp, 20, () => { drift = Math.max(drift, Math.abs(energy() - start) / scale); });
        assert.ok(drift < 0.005, `energy drifted ${(drift * 100).toFixed(2)}%`);
    } finally {
        Object.assign(TUNING, saved);
    }
});

test('the same pull swings the lamp the same at any frame rate', () => {
    const swingAfter = (dt) => {
        const lamp = hang();
        pull(lamp, -200, 120, 0.25, dt);
        lamp.release();
        run(lamp, 0.6, null, dt);
        return lamp.swing;
    };
    const reference = swingAfter(1 / 240);  // 60 Hz in four slices, or 120 Hz in two
    for (const dt of [1 / 288, 1 / 200, 1 / 150]) {  // 144 Hz in two, a slow frame, a dropped one
        assert.ok(Math.abs(swingAfter(dt) - reference) < 0.02, `dt ${dt}: ${swingAfter(dt)} vs ${reference}`);
    }
});

test('wild input cannot break it, and reduced motion keeps the lamp still', () => {
    const lamp = hang();
    lamp.grab();
    run(lamp, 3, (t) => (Math.floor(t * 12) % 2 ? lamp.drag(1440, 900) : lamp.drag(0, -200)));
    lamp.release();
    run(lamp, 10);
    assert.ok([lamp.swing, lamp.tilt, lamp.knob.x, lamp.knob.y].every(Number.isFinite));
    assert.ok(Math.abs(lamp.swing) < 0.02 && Math.abs(lamp.tilt) < 0.02);

    const calm = hang();
    calm.still = true;
    assert.equal(pull(calm, -260, 170, 0.2) + run(calm, 0.5), 1, 'the switch still works');
    assert.deepEqual([calm.swing, calm.tilt], [0, 0]);
});
