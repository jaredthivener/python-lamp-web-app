// Ash - the writing on the wall turns to ash, and a gust from the window carries it off.

const GUST = 620;   // px per second: how fast the gust crosses the words
const GRAIN = 2;    // px: one fleck of ash for every square this size

/**
 * Break the text of `elements` into flecks and blow them away on `canvas`, which should
 * cover the page. The elements themselves are untouched: hide them once this returns,
 * by which time the canvas shows the same words in the same place.
 */
export function blowAway(elements, canvas) {
    const width = innerWidth, height = innerHeight, sharp = Math.min(devicePixelRatio, 2);
    canvas.width = width * sharp;
    canvas.height = height * sharp;
    const ctx = canvas.getContext('2d');
    ctx.scale(sharp, sharp);

    // Draw the words exactly where the page has them, letter by letter.
    const words = document.createElement('canvas');
    words.width = width;
    words.height = height;
    const pen = words.getContext('2d', { willReadFrequently: true });
    const range = document.createRange();
    let left = width, top = height, right = 0, bottom = 0;
    for (const element of elements) {
        const style = getComputedStyle(element);
        pen.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
        pen.fillStyle = style.color;
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        for (let node; (node = walker.nextNode());) {
            for (let i = 0; i < node.length; i++) {
                range.setStart(node, i);
                range.setEnd(node, i + 1);
                const box = range.getBoundingClientRect();
                if (!box.width) continue;
                const size = pen.measureText(node.data[i]);
                pen.fillText(node.data[i], box.left, box.top + (box.height + size.fontBoundingBoxAscent - size.fontBoundingBoxDescent) / 2);
                left = Math.min(left, box.left);
                top = Math.min(top, box.top);
                right = Math.max(right, box.right);
                bottom = Math.max(bottom, box.bottom);
            }
        }
    }
    if (right <= left) return;
    left = Math.max(0, Math.floor(left) - 8);
    top = Math.max(0, Math.floor(top) - 8);
    right = Math.min(width, Math.ceil(right) + 8);
    bottom = Math.min(height, Math.ceil(bottom) + 8);

    // One fleck for each inked grain. The gust front leans, so it reaches the top of a letter first.
    const ink = pen.getImageData(left, top, right - left, bottom - top);
    const flecks = [];
    for (let y = 0; y < ink.height; y += GRAIN) {
        for (let x = 0; x < ink.width; x += GRAIN) {
            const at = (y * ink.width + x) * 4;
            if (ink.data[at + 3] < 90) continue;
            flecks.push({
                x: left + x,
                y: top + y,
                vx: 0,
                vy: 0,
                colour: `${ink.data[at]} ${ink.data[at + 1]} ${ink.data[at + 2]}`,
                strength: ink.data[at + 3] / 255,
                reached: (x + 0.35 * y) / GUST,      // when the gust gets to it
                hangs: Math.random() * 0.07,         // and how long it clings on after that
                lasts: 0.8 + Math.random() * 1.4,
                flutter: Math.random() * 6.28,
                weight: 0.6 + Math.random() * 0.8,
            });
        }
    }
    const ends = (right - left + 0.35 * (bottom - top)) / GUST + 2.4;

    let began, before;
    const frame = (now) => {
        began ??= now;
        const t = (now - began) / 1000, dt = Math.min(0.05, (now - (before ?? now)) / 1000);
        before = now;
        ctx.clearRect(0, 0, width, height);

        // Ahead of the gust the words still stand: show them as they were.
        const front = left + t * GUST;
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(front, top);
        ctx.lineTo(right, top);
        ctx.lineTo(right, bottom);
        ctx.lineTo(front - 0.35 * (bottom - top), bottom);
        ctx.clip();
        ctx.drawImage(words, 0, 0);
        ctx.restore();

        // Behind it they are ash on the wind: carried off, fluttering, thinning to nothing.
        for (const fleck of flecks) {
            const age = t - fleck.reached - fleck.hangs;
            if (t < fleck.reached || age > fleck.lasts) continue;
            if (age > 0) {
                fleck.vx += (1500 * fleck.weight - 1.6 * fleck.vx) * dt;
                fleck.vy += (-90 * fleck.weight + 260 * Math.sin(fleck.flutter + age * 9) - 2 * fleck.vy) * dt;
                fleck.x += fleck.vx * dt;
                fleck.y += fleck.vy * dt;
            }
            const remains = 1 - Math.max(age, 0) / fleck.lasts, size = GRAIN * (0.45 + 0.65 * remains);
            ctx.fillStyle = `rgb(${fleck.colour} / ${fleck.strength * remains * Math.sqrt(remains)})`;
            ctx.fillRect(fleck.x, fleck.y, size, size);
        }
        if (t < ends) requestAnimationFrame(frame);
        else canvas.width = canvas.height = 0;  // gone; give the memory back
    };
    frame(performance.now());
}
