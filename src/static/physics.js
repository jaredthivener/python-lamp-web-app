// Physics - how the lamp moves. No DOM in here, so it runs (and is tested) under Node.
//
// Three things move. The lamp body hangs from a cord, so it can swing on the cord and
// also rock where the cord meets it. A ball chain hangs from the body. And a hand, real
// or scripted, pulls the chain: first through the switch's short spring travel, then
// against the weight of the lamp itself.

const clamp = (value, low, high) => Math.min(high, Math.max(low, value));

/** Calibration. Lengths are in shade half-widths, times in seconds, forces in lamp weights. */
export const TUNING = {
    gravity: 54,          // a 36 cm shade puts one half-width at 0.18 m, which makes this 9.8 m/s^2
    centreOfMass: 0.6,    // below the point where the cord meets the lamp
    gyration: 0.6,        // radius of gyration: how reluctant the shade is to rock
    swingDamping: 0.45,   // per second: air, taking the edge off a big swing
    rockDamping: 4,       // per second: the shade rocking against the cord
    friction: 0.18,       // rad/s^2: dry friction, which is what finally brings it to rest
    socket: [0.36, 0.6],  // where the chain comes out: across, down
    links: 8,
    linkLength: 0.16,
    knobWeight: 4,        // in beads
    chainDrag: 0.8,       // per second
    travel: 0.24,         // how far the switch lets the chain out
    clickAt: 0.6,         // fraction of that travel at which it clicks
    switchForce: 0.7,     // pull needed at full travel: raise it for a livelier lamp
    haulStiffness: 3,     // per half-width, once the switch has bottomed out...
    haulReach: 0.3,       // ...up to this much further. Past it the knob leaves the hand behind
    handDamping: 8,       // per second: a hand on a taut chain steadies the lamp
    retract: 0.07,        // the switch spring taking the chain back
    handLag: 0.02,        // turns the pointer's steps into smooth motion
    tugSeconds: 0.14,     // a scripted pull: down this fast, then let go
    heatUp: 0.08,         // filament
    coolDown: 0.2,
};

export class Lamp {
    on = false;      // what the filament is heading for
    heat = 0;        // filament temperature, 0..1
    swing = 0;       // angle of the cord from vertical
    tilt = 0;        // angle of the lamp body from vertical
    swingRate = 0;
    tiltRate = 0;
    pull = 0;        // how far the chain is drawn out of the switch
    still = false;   // reduced motion: the lamp body stays put
    chain = [];      // { x, y, px, py } per joint, socket to knob; (px, py) is the previous position
    hand = null;     // whatever holds the knob: { x, y } following a target { tx, ty }
    armed = true;    // the switch clicks once per pull
    lastDt = 0;      // the rope infers speed from the previous step, so it must know how long that was

    /** Fit the lamp to a page and hang it at rest. */
    place(pivot, R, cord) {
        Object.assign(this, { pivot, R, cord, swing: 0, tilt: 0, swingRate: 0, tiltRate: 0, pull: 0, hand: null, armed: true, lastDt: 0 });
        const { x, y } = this.socket;
        const link = TUNING.linkLength * R;
        this.chain = Array.from({ length: TUNING.links + 1 }, (_, i) => ({ x, y: y + i * link, px: x, py: y + i * link }));
    }

    /** Where the cord meets the lamp. */
    get top() {
        return { x: this.pivot.x + this.cord * Math.sin(this.swing), y: this.pivot.y + this.cord * Math.cos(this.swing) };
    }

    /** Where the chain comes out of the lamp, for a given pose (the current one by default). */
    socketAt(swing = this.swing, tilt = this.tilt) {
        const across = TUNING.socket[0] * this.R, down = TUNING.socket[1] * this.R;
        return {
            x: this.pivot.x + this.cord * Math.sin(swing) + across * Math.cos(tilt) + down * Math.sin(tilt),
            y: this.pivot.y + this.cord * Math.cos(swing) - across * Math.sin(tilt) + down * Math.cos(tilt),
        };
    }

    get socket() {
        return this.socketAt();
    }

    get knob() {
        return this.chain[this.chain.length - 1];
    }

    /** Take hold of the knob where it is. */
    grab() {
        const { x, y } = this.knob;
        this.hand = { x, y, tx: x, ty: y };
    }

    /** Move the hand that holds the knob. */
    drag(x, y) {
        if (this.hand && !this.hand.scripted) Object.assign(this.hand, { tx: x, ty: y });
    }

    release() {
        this.hand = null;
    }

    /** Pull the chain as if by an unseen hand: a tap, a key, or somebody else's pull. */
    tug() {
        if (this.hand || this.still) return;
        const from = this.socket, { x, y } = this.knob;
        const distance = Math.hypot(x - from.x, y - from.y) || 1;
        // Along the way the chain already hangs, so a swinging chain is not snapped straight.
        this.hand = { x, y, tx: x, ty: y, scripted: true, age: 0, from, ux: (x - from.x) / distance, uy: (y - from.y) / distance };
    }

    /**
     * Angular accelerations of the cord and of the body in a given pose: a compound double
     * pendulum, plus whatever a taut chain is doing to the socket.
     */
    accelerate(swing, tilt, swingRate, tiltRate) {
        const T = TUNING, R = this.R, g = T.gravity * R;
        const L1 = this.cord, L2 = T.centreOfMass * R;
        const across = T.socket[0] * R, down = T.socket[1] * R;
        const s1 = Math.sin(swing), c1 = Math.cos(swing), s2 = Math.sin(tilt), c2 = Math.cos(tilt);
        // How far the socket moves per radian of swing, and per radian of tilt.
        const sx1 = L1 * c1, sy1 = -L1 * s1;
        const sx2 = down * c2 - across * s2, sy2 = -down * s2 - across * c2;

        // Force on the socket, in lamp weights, and how much a hand is steadying things.
        let fx = 0, fy = 0, steady = 0;
        if (this.hand) {
            const socket = this.socketAt(swing, tilt);
            const dx = this.hand.x - socket.x, dy = this.hand.y - socket.y;
            const distance = Math.hypot(dx, dy) || 1;
            const excess = distance - T.links * T.linkLength * R;
            if (excess > 0) {
                const travel = T.travel * R;
                const tension = T.switchForce * Math.min(excess, travel) / travel              // the switch's spring
                              + T.haulStiffness * clamp(excess - travel, 0, T.haulReach * R) / R;  // then the lamp's weight
                fx = tension * dx / distance;
                fy = tension * dy / distance;
                // A hand is not a hook on a wall: it gives, and soaks up the lamp's motion.
                // Without this a held lamp rocks on and on.
                steady = T.handDamping;
            }
        }

        const lean = swing - tilt, sinLean = Math.sin(lean);
        const m11 = L1 * L1, m12 = L1 * L2 * Math.cos(lean), m22 = L2 * L2 + (T.gyration * R) ** 2;
        const joint = T.rockDamping * m22 * (tiltRate - swingRate);
        const f1 = -L1 * L2 * sinLean * tiltRate ** 2 - g * L1 * s1
                 + g * (sx1 * fx + sy1 * fy) - (T.swingDamping + steady) * m11 * swingRate + joint;
        const f2 = L1 * L2 * sinLean * swingRate ** 2 - g * L2 * s2
                 + g * (sx2 * fx + sy2 * fy) - steady * m22 * tiltRate - joint;
        const det = m11 * m22 - m12 * m12;
        return [(f1 * m22 - f2 * m12) / det, (f2 * m11 - f1 * m12) / det];
    }

    /** Advance by dt seconds, which may vary from call to call. Returns true on the step a real hand clicks the switch. */
    step(dt) {
        const T = TUNING, R = this.R, chain = this.chain;
        const link = T.linkLength * R, length = T.links * link, travel = T.travel * R;
        let clicked = false;

        // --- The hand -------------------------------------------------------------
        if (this.hand?.scripted) {
            const tug = this.hand;
            tug.age += dt;
            const phase = tug.age / T.tugSeconds;
            const reach = length + 0.9 * travel * phase * (2 - phase);
            Object.assign(tug, { tx: tug.from.x + tug.ux * reach, ty: tug.from.y + tug.uy * reach });
            if (phase >= 1) this.hand = null;
        }
        const hand = this.hand;
        if (hand) {
            const follow = 1 - Math.exp(-dt / T.handLag);
            hand.x += (hand.tx - hand.x) * follow;
            hand.y += (hand.ty - hand.y) * follow;
        }

        // --- The lamp body, by fourth-order Runge-Kutta --------------------------------
        if (!this.still) {
            const { swing: q1, tilt: q2, swingRate: v1, tiltRate: v2 } = this;
            const h = dt, half = dt / 2;
            const [a1, b1] = this.accelerate(q1, q2, v1, v2);
            const [a2, b2] = this.accelerate(q1 + v1 * half, q2 + v2 * half, v1 + a1 * half, v2 + b1 * half);
            const [a3, b3] = this.accelerate(q1 + (v1 + a1 * half) * half, q2 + (v2 + b1 * half) * half, v1 + a2 * half, v2 + b2 * half);
            const [a4, b4] = this.accelerate(q1 + (v1 + a2 * half) * h, q2 + (v2 + b2 * half) * h, v1 + a3 * h, v2 + b3 * h);
            this.swing = q1 + v1 * h + (a1 + a2 + a3) * h * h / 6;
            this.tilt = q2 + v2 * h + (b1 + b2 + b3) * h * h / 6;
            this.swingRate = v1 + (a1 + 2 * a2 + 2 * a3 + a4) * h / 6;
            this.tiltRate = v2 + (b1 + 2 * b2 + 2 * b3 + b4) * h / 6;

            // Dry friction takes a fixed bite out of the motion, so small sways stop dead
            // instead of fading for ever.
            const bite = T.friction * dt;
            this.swingRate -= clamp(this.swingRate, -bite, bite);
            this.tiltRate -= clamp(this.tiltRate - this.swingRate, -bite, bite);

            // Nothing a hand can do should wrap the lamp over the ceiling.
            if (Math.abs(this.swing) > 1.1) Object.assign(this, { swing: Math.sign(this.swing) * 1.1, swingRate: 0 });
            if (Math.abs(this.tilt) > 1.3) Object.assign(this, { tilt: Math.sign(this.tilt) * 1.3, tiltRate: 0 });
        }

        // --- The chain: a Verlet rope -----------------------------------------------
        const socket = this.socket, knob = this.knob;
        if (hand) {
            const dx = hand.x - socket.x, dy = hand.y - socket.y;
            const distance = Math.hypot(dx, dy) || 1;
            this.pull = clamp(distance - length, 0, travel);
            const reach = Math.min(distance, length + this.pull) / distance;
            knob.px = knob.x;  // so that letting go carries the hand's speed
            knob.py = knob.y;
            knob.x = socket.x + dx * reach;
            knob.y = socket.y + dy * reach;
            if (!hand.scripted && this.armed && this.pull > T.clickAt * travel) {
                this.armed = false;
                clicked = true;
            }
        } else {
            this.pull *= Math.exp(-dt / T.retract);
        }
        if (this.pull < 0.3 * T.clickAt * travel) this.armed = true;

        const drag = Math.exp(-T.chainDrag * dt) * dt / (this.lastDt || dt), fall = T.gravity * R * dt * dt;
        for (let i = 1; i <= T.links - (hand ? 1 : 0); i++) {
            const joint = chain[i];
            const vx = (joint.x - joint.px) * drag, vy = (joint.y - joint.py) * drag;
            joint.px = joint.x;
            joint.py = joint.y;
            joint.x += vx;
            joint.y += vy + fall;
        }
        chain[0].x = socket.x;
        chain[0].y = socket.y;
        for (let pass = 0; pass < 16; pass++) {
            for (let i = 0; i < T.links; i++) {
                const a = chain[i], b = chain[i + 1];
                const dx = b.x - a.x, dy = b.y - a.y;
                const distance = Math.hypot(dx, dy) || 1e-6;
                // How readily each end gives: the socket and a held knob not at all, a free knob little.
                const giveA = i === 0 ? 0 : 1;
                const giveB = i < T.links - 1 ? 1 : hand ? 0 : 1 / T.knobWeight;
                const slack = (distance - link - (i === 0 ? this.pull : 0)) / distance / (giveA + giveB);
                a.x += dx * slack * giveA;
                a.y += dy * slack * giveA;
                b.x -= dx * slack * giveB;
                b.y -= dy * slack * giveB;
            }
        }

        // --- The filament heats quickly and cools slowly ------------------------------
        this.heat += ((this.on ? 1 : 0) - this.heat) * (1 - Math.exp(-dt / (this.on ? T.heatUp : T.coolDown)));
        this.lastDt = dt;
        return clicked;
    }
}
