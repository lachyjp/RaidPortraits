// Renders the RaidPortraits logo with no dependencies.
//   node tools/logo.js
// Writes logo.png (1024 px) and logo-400.png for CurseForge, and
// RaidPortraits/Media/Logo.tga (128 px) for the in-game AddOns list.
//
// Three raid-style frames, each with a portrait bust on the left; the middle
// one has the gold "your target" outline. Dark warm backdrop with a thin gold
// border, like the other add-ons in this family.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const ROOT = path.join(__dirname, "..");
const clamp = (v, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, v));
const mix = (a, b, t) => a.map((x, i) => x + (b[i] - x) * t);

// Signed distance to a rounded rectangle (x0,y0)-(x1,y1) with corner radius r.
function rrect(x, y, x0, y0, x1, y1, r) {
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, hx = (x1 - x0) / 2, hy = (y1 - y0) / 2;
    const qx = Math.abs(x - cx) - (hx - r), qy = Math.abs(y - cy) - (hy - r);
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
}
const circle = (x, y, cx, cy, r) => Math.hypot(x - cx, y - cy) - r;
const ellipse = (x, y, cx, cy, rx, ry) => (Math.hypot((x - cx) / rx, (y - cy) / ry) - 1) * Math.min(rx, ry);

const CLASSES = [
    [1.0, 0.49, 0.04],   // druid orange
    [0.25, 0.78, 0.92],  // mage cyan
    [0.96, 0.55, 0.73],  // paladin pink
];
const GOLD = [0.92, 0.73, 0.40];
const TARGET = [1.0, 0.82, 0.0];

// A portrait: gold-edged square, dark radial interior, class-tinted bust.
function portrait(x, y, px, py, s, cls, c) {
    const b = s * 0.05; // border
    const outer = rrect(x, y, px, py, px + s, py + s, s * 0.06);
    if (outer > 0) return c;
    if (outer > -b) {
        const t = clamp((y - py) / s);
        return mix(mix(GOLD, [0.55, 0.40, 0.18], t), [1, 0.93, 0.7], outer > -b * 0.35 ? 0 : 0.15);
    }
    const cx = px + s / 2, cy = py + s / 2;
    const d = Math.hypot(x - cx, y - (cy - s * 0.1)) / s;
    let col = mix([0.16, 0.13, 0.11], [0.04, 0.035, 0.03], clamp(d * 1.6));
    // Bust: head and shoulders, lit from the top-left.
    const head = circle(x, y, cx, cy - s * 0.1, s * 0.19);
    const body = ellipse(x, y, cx, cy + s * 0.47, s * 0.36, s * 0.3);
    if (Math.min(head, body) < 0) {
        const light = clamp(0.75 - ((x - cx) + (y - cy)) / s * 0.9);
        col = mix(cls.map((v) => v * 0.45), cls.map((v) => Math.min(1, v * 1.15 + 0.05)), light);
    }
    return col;
}

// A raid-style frame bar: dark box, class-coloured health fill with a sheen.
function bar(x, y, bx, by, w, h, fill, cls, c) {
    const outer = rrect(x, y, bx, by, bx + w, by + h, h * 0.06);
    if (outer > 0) return c;
    if (outer > -h * 0.035) return [0, 0, 0];
    let col = [0.07, 0.07, 0.08];
    const fx = bx + w * fill;
    if (x < fx) {
        const t = (y - by) / h;
        col = mix(cls.map((v) => Math.min(1, v * 1.1 + 0.08)), cls.map((v) => v * 0.55), t);
        if (t < 0.12) col = mix(col, [1, 1, 1], 0.18);
    }
    // Name stripe, standing in for the player's name.
    const name = rrect(x, y, bx + w * 0.06, by + h * 0.16, bx + w * 0.42, by + h * 0.3, h * 0.07);
    if (name < 0) col = mix(col, [1, 1, 1], 0.85);
    return col;
}

function background(x, y, S) {
    const d = Math.hypot(x - S / 2, y - S / 2) / (S * 0.62);
    let col = mix([0.23, 0.17, 0.11], [0.055, 0.047, 0.04], clamp(d));
    const inset = S * 0.035, bw = Math.max(2, S / 220);
    const e = Math.min(x - inset, y - inset, S - inset - x, S - inset - y);
    if (e >= 0 && e < bw) col = [0.59, 0.46, 0.27];
    return col;
}

function logoPixel(x, y, S) {
    let c = background(x, y, S);
    const rowH = S * 0.2, gap = S * 0.055;
    const top = (S - (3 * rowH + 2 * gap)) / 2;
    const px = S * 0.13, bx = px + rowH + S * 0.035, bw = S * 0.87 - bx;
    const fills = [0.88, 0.62, 0.95];
    for (let i = 0; i < 3; i++) {
        const py = top + i * (rowH + gap);
        // Drop shadow
        if (rrect(x, y, px + S * 0.012, py + S * 0.016, bx + bw + S * 0.012, py + rowH + S * 0.016, rowH * 0.08) < 0) {
            c = mix(c, [0, 0, 0], 0.55);
        }
        if (i === 1) {
            // Gold target outline around the middle portrait.
            const t = S * 0.016;
            const ring = rrect(x, y, px - t, py - t, px + rowH + t, py + rowH + t, rowH * 0.1);
            if (ring < 0) c = TARGET;
        }
        c = bar(x, y, bx, py + rowH * 0.06, bw, rowH * 0.88, fills[i], CLASSES[i], c);
        c = portrait(x, y, px, py, rowH, CLASSES[i], c);
    }
    return c;
}

// The in-game icon: one portrait filling the square, with the target outline.
function iconPixel(x, y, S) {
    let c = [0, 0, 0, 0];
    const t = S * 0.06;
    if (rrect(x, y, 0, 0, S, S, S * 0.12) < 0) c = TARGET;
    const inner = portrait(x, y, t, t, S - 2 * t, CLASSES[1], null);
    return inner || c;
}

function render(S, fn, ss = 3) {
    const out = new Float32Array(S * S * 4);
    for (let y = 0; y < S; y++) {
        for (let x = 0; x < S; x++) {
            let r = 0, g = 0, b = 0, a = 0;
            for (let j = 0; j < ss; j++) {
                for (let i = 0; i < ss; i++) {
                    const c = fn(x + (i + 0.5) / ss, y + (j + 0.5) / ss, S);
                    const al = c.length > 3 ? c[3] : 1;
                    r += c[0] * al; g += c[1] * al; b += c[2] * al; a += al;
                }
            }
            const n = ss * ss, o = (y * S + x) * 4;
            out[o] = a ? r / a : 0; out[o + 1] = a ? g / a : 0; out[o + 2] = a ? b / a : 0; out[o + 3] = a / n;
        }
    }
    return out;
}

function downscale(src, S, D) {
    // Box filter (S must be a multiple of D... or close enough: area-average).
    const out = new Float32Array(D * D * 4), k = S / D;
    for (let y = 0; y < D; y++) for (let x = 0; x < D; x++) {
        let acc = [0, 0, 0, 0], n = 0;
        for (let sy = Math.floor(y * k); sy < Math.floor((y + 1) * k); sy++)
            for (let sx = Math.floor(x * k); sx < Math.floor((x + 1) * k); sx++) {
                const o = (sy * S + sx) * 4;
                for (let c = 0; c < 4; c++) acc[c] += src[o + c];
                n++;
            }
        for (let c = 0; c < 4; c++) out[(y * D + x) * 4 + c] = acc[c] / n;
    }
    return out;
}

const CRC = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
    return (buf) => { let c = 0xffffffff; for (const b of buf) c = t[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
})();

function png(px, S) {
    const raw = Buffer.alloc(S * (S * 3 + 1));
    for (let y = 0; y < S; y++) {
        raw[y * (S * 3 + 1)] = 0;
        for (let x = 0; x < S; x++) for (let c = 0; c < 3; c++)
            raw[y * (S * 3 + 1) + 1 + x * 3 + c] = Math.round(clamp(px[(y * S + x) * 4 + c]) * 255);
    }
    const chunk = (type, data) => {
        const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
        const td = Buffer.concat([Buffer.from(type), data]);
        const crc = Buffer.alloc(4); crc.writeUInt32BE(CRC(td));
        return Buffer.concat([len, td, crc]);
    };
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(S, 0); ihdr.writeUInt32BE(S, 4); ihdr[8] = 8; ihdr[9] = 2;
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr),
        chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}

function tga(px, S) {
    const buf = Buffer.alloc(18 + S * S * 4);
    buf[2] = 2; buf.writeUInt16LE(S, 12); buf.writeUInt16LE(S, 14); buf[16] = 32; buf[17] = 0x28;
    let o = 18;
    for (let i = 0; i < S * S; i++) {
        const a = clamp(px[i * 4 + 3]);
        buf[o++] = Math.round(clamp(px[i * 4 + 2]) * 255);
        buf[o++] = Math.round(clamp(px[i * 4 + 1]) * 255);
        buf[o++] = Math.round(clamp(px[i * 4]) * 255);
        buf[o++] = Math.round(a * 255);
    }
    return buf;
}

const big = render(1024, logoPixel);
fs.writeFileSync(path.join(ROOT, "logo.png"), png(big, 1024));
fs.writeFileSync(path.join(ROOT, "logo-400.png"), png(downscale(big, 1024, 400), 400));
fs.writeFileSync(path.join(ROOT, "RaidPortraits", "Media", "Logo.tga"), tga(render(128, iconPixel, 4), 128));
console.log("wrote logo.png, logo-400.png, RaidPortraits/Media/Logo.tga");
