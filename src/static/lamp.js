// Lamp - a pendant lamp on a cord with a ball-chain switch, shared live with everyone on the page.
import { blowAway } from './ash.js';
import { Lamp, TUNING } from './physics.js';
import { createScene } from './scene.js';
import { chainPull, chainRelease } from './sound.js';

const $ = (id) => document.getElementById(id);
const clamp = (value, low, high) => Math.min(high, Math.max(low, value));

const root = document.documentElement;
const cord = $('cord');
const notice = $('notice');
const plaques = [...document.querySelectorAll('.plaque')];
const calm = matchMedia('(prefers-reduced-motion: reduce)').matches;
const scene = matchMedia('(forced-colors: active)').matches ? null : createScene($('scene'));

const MAX_STEP = 1 / 200;  // the physics never takes a bigger bite of time than this
const WORDS_STAY = 5000;   // ms after the page opens before the writing on the wall may blow away

const lamp = new Lamp();
lamp.still = calm;
let pointer = null;    // a drag in progress: where on the chain it took hold, and whether it has moved
let latest = null;     // last snapshot from the server
let W, H;
let desk;              // the desk across the bottom of the page: y of its back and front edges
let litSince = null;   // when the lamp last came up to full brightness, while it stays lit
let wordsGone = false;

// --- Drawing ---------------------------------------------------------------

function measure() {
    W = innerWidth;
    H = innerHeight;
    lamp.place({ x: W / 2, y: 0 }, clamp(Math.min(W * 0.2, H * 0.13), 54, 130), clamp(H * 0.14, 44, 210));
    desk = { top: H - Math.max(84, H * 0.115), front: H - Math.max(30, H * 0.04) };
    pointer = null;
}

let previous = performance.now();
const chainBuffer = new Float32Array(18);  // nine joints: matches uChain in scene.js
const cardBuffer = new Float32Array(16);

function frame(now) {
    if (W !== innerWidth || H !== innerHeight) measure();

    // Advance by exactly the time this frame covers, cut into equal slices. A fixed step that
    // does not divide the display's frame time leaves some frames with no motion and others
    // with double, which reads as stutter.
    const elapsed = clamp((now - previous) / 1000, 0, 0.05);
    previous = now;
    const slices = Math.ceil(elapsed / MAX_STEP);
    for (let i = 0; i < slices; i++) {
        if (lamp.step(elapsed / slices)) {
            if (pointer) pointer.clicked = true;
            pullCord();
        }
    }

    lamp.chain.forEach((joint, i) => {
        chainBuffer[i * 2] = joint.x;
        chainBuffer[i * 2 + 1] = joint.y;
    });
    plaques.forEach((plaque, i) => {
        const box = plaque.getBoundingClientRect();
        cardBuffer.set([box.x + box.width / 2, box.y + box.height / 2, box.width / 2, box.height / 2], i * 4);
    });

    // Lay the button along the chain where it shows below the shade, so any of it can be grabbed.
    const knob = lamp.knob, socket = lamp.socket;
    const dx = socket.x - knob.x, dy = socket.y - knob.y;
    const height = Math.max(48, Math.hypot(dx, dy) - 0.45 * lamp.R + 24);
    cord.style.height = `${height}px`;
    cord.style.translate = `${knob.x - 24}px ${knob.y - height + 24}px`;
    cord.style.rotate = `${Math.atan2(dx, -dy)}rad`;

    // The writing stays on the wall a few seconds, then blows away while there is light to see it by.
    litSince = lamp.heat > 0.9 ? litSince ?? now : null;
    if (!wordsGone && now > WORDS_STAY && litSince !== null && now - litSince > 1500) scatterWords();

    scene.draw({
        pivot: lamp.pivot,
        top: lamp.top,
        R: lamp.R,
        tilt: lamp.tilt,
        heat: lamp.heat,
        time: calm ? 0 : (now / 1000) % 3600,  // wrapped hourly: a 32-bit float loses the small steps otherwise
        hint: root.classList.contains('hint') ? 1 : 0,
        chain: chainBuffer,
        cards: cardBuffer,
        desk,
    });
    requestAnimationFrame(frame);
}

// --- The switch ------------------------------------------------------------

/** Show the lamp on or off. */
function setLamp(on) {
    if (on === lamp.on) return;
    lamp.on = on;
    root.classList.toggle('on', on);
    cord.setAttribute('aria-pressed', on);
    document.title = on ? 'Lamp \u00b7 on' : 'Lamp \u00b7 off';
}

/** The writing on the wall has said its piece: it turns to ash and a gust takes it. */
function scatterWords() {
    wordsGone = true;
    if (calm || !scene) {
        root.classList.add('gently');  // no gust: the words just fade
    } else {
        blowAway(document.querySelectorAll('h1, .lede'), $('ash'));
        lamp.swingRate += 0.45;  // the same gust catches the lamp
        lamp.tiltRate += 0.6;
    }
    root.classList.add('wordless');
}

/** This visitor pulled the cord: flip the light now, then tell the server. */
async function pullCord() {
    click();
    root.classList.remove('hint');
    setLamp(!lamp.on);  // the light answers the hand, not the network
    try {
        const response = await fetch('/api/v1/lamp/toggle', { method: 'POST', headers: { 'X-Session-ID': session } });
        if (response.ok) {
            update(await response.json());
        } else if (response.status === 429 && latest) {
            setLamp(latest.is_on);  // someone else pulled it a moment ago; theirs stands
            say('Someone else just pulled it');
        } else {
            throw new Error(`Toggle failed: ${response.status}`);
        }
    } catch (error) {
        console.error(error);
        say('Offline. This pull stayed in your room.');
    }
}

/** Take in a snapshot from the server. */
function update(snapshot) {
    if (latest && snapshot.is_on !== lamp.on) {
        lamp.tug();
        say('Someone pulled the cord');
    }
    latest = snapshot;
    setLamp(snapshot.is_on);

    $('today').textContent = count.format(snapshot.today);
    $('lifetime').textContent = count.format(snapshot.lifetime);
    $('visitors').textContent = count.format(snapshot.visitors_today);
    $('viewers').textContent = count.format(snapshot.viewers);
}

const count = new Intl.NumberFormat();
let noticeTimer;
function say(text, linger = 4000) {
    clearTimeout(noticeTimer);
    if (text) notice.textContent = text;
    notice.classList.toggle('show', Boolean(text));
    if (text && linger) noticeTimer = setTimeout(say, linger, '');
}

let audio;

/** Browsers only let sound start from inside an input handler, so each one calls this. */
function wakeAudio() {
    try {
        audio ??= new AudioContext();
        audio.resume();
    } catch {
        // No audio device, or the browser refused one: the lamp works without the sound.
    }
}

/** Play a sound once audio is running. If the browser never allows it, nothing queues up. */
function play(sound, delay = 0) {
    audio?.resume().then(() => sound(audio, audio.currentTime + delay), () => {});
}

function click() {
    navigator.vibrate?.(8);
    play(chainPull);
}

// --- Input -----------------------------------------------------------------

/** A pull without dragging: tap, Enter, Space, or the L key. */
function pullForMe() {
    lamp.tug();
    pullCord();
    play(chainRelease, TUNING.tugSeconds);  // the unseen hand lets go
}

cord.addEventListener('pointerdown', (e) => {
    wakeAudio();
    if (!scene) return;
    cord.setPointerCapture(e.pointerId);
    lamp.grab();
    pointer = { offsetX: lamp.knob.x - e.clientX, offsetY: lamp.knob.y - e.clientY, startX: e.clientX, startY: e.clientY, dragged: false };
});

cord.addEventListener('pointermove', (e) => {
    if (!pointer) return;
    lamp.drag(e.clientX + pointer.offsetX, e.clientY + pointer.offsetY);
    pointer.dragged ||= Math.hypot(e.clientX - pointer.startX, e.clientY - pointer.startY) > 6;
});

cord.addEventListener('pointerup', () => {
    wakeAudio();
    if (!pointer) return;
    lamp.release();
    if (pointer.clicked) play(chainRelease);
    if (!pointer.dragged) pullForMe();
    pointer = null;
});

cord.addEventListener('pointercancel', () => {
    lamp.release();
    pointer = null;
});

// Keyboard activation arrives as a click with no pointer behind it.
cord.addEventListener('click', (e) => {
    wakeAudio();
    if (e.detail === 0 || !scene) pullForMe();
});

document.addEventListener('keydown', (e) => {
    if (e.key.toLowerCase() !== 'l' || e.repeat || e.metaKey || e.ctrlKey || e.altKey) return;
    wakeAudio();
    pullForMe();
});

// --- Server ----------------------------------------------------------------

const session = Array.from(crypto.getRandomValues(new Uint8Array(12)), (byte) => byte.toString(16).padStart(2, '0')).join('');

function listen() {
    const events = new EventSource('/api/v1/lamp/events');
    events.onopen = () => say('');
    events.onmessage = (e) => update(JSON.parse(e.data));
    events.onerror = () => {
        say('Connection lost. Reconnecting...', 0);
        latest = null;  // whatever comes back is news, not somebody's pull
        // The browser retries a dropped stream by itself, but gives up for good on an HTTP error.
        if (events.readyState === EventSource.CLOSED) setTimeout(listen, 5000);
    };
}

// --- Start -----------------------------------------------------------------

root.classList.toggle('plain', !scene);
if (scene) {
    root.classList.add('hint');
    measure();
    requestAnimationFrame(frame);
} else {
    setTimeout(scatterWords, WORDS_STAY);
}
listen();
