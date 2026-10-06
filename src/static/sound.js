// Sound - a real pull chain: the switch being pulled, and the chain being let go.
//
// Recorded, not synthesised: no handful of generated tones sounds like beads rattling
// through a brass collar. Both files are cut from "Desk Lamp - Chain Pull (Fast)" by
// PhillipArthurSimmons (https://freesound.org/s/541762/), which is public domain (CC0).
// To use your own lamp, record it and replace the two .wav files.

// Fetched as the page loads, so the first pull does not wait on the network.
const files = Object.fromEntries(['pull', 'release'].map((name) => [
    name,
    fetch(`chain-${name}.wav`).then((response) => (response.ok ? response.arrayBuffer() : Promise.reject(response.status))),
]));
Object.values(files).forEach((file) => file.catch(() => {}));  // a missing file is handled at play time

const decoded = {};  // name -> Promise<AudioBuffer>; decoding consumes the bytes, so it happens once

async function play(context, name, when) {
    try {
        decoded[name] ??= files[name].then((bytes) => context.decodeAudioData(bytes));
        const source = context.createBufferSource(), level = context.createGain();
        source.buffer = await decoded[name];
        // No two pulls of a real chain sound quite alike.
        source.playbackRate.value = 0.97 + Math.random() * 0.06;
        level.gain.value = 0.45 + Math.random() * 0.1;
        source.connect(level).connect(context.destination);
        source.start(when);
    } catch {
        // The lamp works without its sound.
    }
}

/** The beads going taut and the switch snapping over. Its loudest moment is 30 ms in. */
export function chainPull(context, when = context.currentTime) {
    return play(context, 'pull', when);
}

/** The chain let go: beads rattling back through the collar. */
export function chainRelease(context, when = context.currentTime) {
    return play(context, 'release', when);
}
