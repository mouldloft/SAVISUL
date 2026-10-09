(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  SV.css = `
:host { all: initial !important; }
*, *::before, *::after { box-sizing: border-box; }
button { font: inherit; color: inherit; }
.icon { display: block; flex: none; }

.sv {
  --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", "Segoe UI", Roboto, Inter, Arial, sans-serif;
  --mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace;
  --spring: linear(0, 0.0157, 0.0572, 0.1174, 0.1899, 0.2698, 0.3529, 0.4359, 0.5165, 0.5927, 0.6633, 0.7275, 0.7848, 0.8352, 0.8787, 0.9157, 0.9466, 0.9718, 0.992, 1.0077, 1.0195, 1.0279, 1.0335, 1.0368, 1.0383, 1.0382, 1.037, 1.035, 1.0324, 1.0294, 1.0263, 1.0231, 1.0199, 1.0169, 1.0141, 1.0115, 1.0092, 1.0072, 1.0054, 1.0038, 1.0026, 1.0015, 1.0006, 1, 0.9994, 0.9991, 0.9988, 0.9986, 1);
  --smooth: linear(0, 0.0108, 0.0393, 0.0806, 0.1306, 0.1862, 0.2449, 0.3046, 0.364, 0.4218, 0.4772, 0.5298, 0.579, 0.6248, 0.6671, 0.7057, 0.7409, 0.7728, 0.8014, 0.8271, 0.85, 0.8704, 0.8884, 0.9043, 0.9182, 0.9303, 0.9409, 0.9501, 0.9581, 0.965, 0.9709, 0.9759, 0.9802, 0.9838, 0.9869, 0.9895, 0.9917, 0.9935, 0.9949, 0.9962, 0.9972, 0.998, 0.9987, 0.9992, 0.9996, 0.9999, 1.0001, 1.0003, 1);
  position: fixed; inset: 0; pointer-events: none;
  font-family: var(--font); font-size: 13px; line-height: 1.35; letter-spacing: -0.003em;
  color: var(--ink); -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility;
  color-scheme: dark;
}
.sv[data-theme="dark"] {
  --ink: #f7f5f0; --ink-2: rgba(247, 245, 240, 0.64); --ink-3: rgba(247, 245, 240, 0.42);
  --line: rgba(255, 255, 255, 0.08); --line-strong: rgba(255, 255, 255, 0.14);
  --glass: rgba(14, 13, 12, 0.9); --glass-top: rgba(30, 28, 26, 0.92); --float: rgba(24, 23, 21, 0.94);
  --tile: rgba(255, 255, 255, 0.055); --tile-hover: rgba(255, 255, 255, 0.1); --tile-active: rgba(219, 199, 163, 0.16);
  --accent: #dbc7a3; --accent-deep: #b0966f; --on-accent: #141416;
  --positive: #8cd6b0; --warning: #f5ba66; --danger: #ff7363;
  --shadow: 0 26px 60px -14px rgba(0, 0, 0, 0.6), 0 10px 26px -12px rgba(0, 0, 0, 0.45);
  --rim: inset 0 0 0 0.5px rgba(255, 255, 255, 0.09), inset 0 -0.5px 0 rgba(255, 255, 255, 0.16);
  --knob: #fbfaf7;
}
.sv[data-theme="light"] {
  color-scheme: light;
  --ink: #1c1b19; --ink-2: rgba(28, 27, 25, 0.62); --ink-3: rgba(28, 27, 25, 0.42);
  --line: rgba(0, 0, 0, 0.07); --line-strong: rgba(0, 0, 0, 0.12);
  --glass: rgba(249, 247, 243, 0.9); --glass-top: rgba(255, 255, 255, 0.94); --float: rgba(255, 255, 255, 0.96);
  --tile: rgba(0, 0, 0, 0.045); --tile-hover: rgba(0, 0, 0, 0.08); --tile-active: rgba(138, 111, 69, 0.14);
  --accent: #8a6f45; --accent-deep: #6f5735; --on-accent: #fffaf2;
  --positive: #2f8f5f; --warning: #b9771f; --danger: #d4483a;
  --shadow: 0 26px 60px -18px rgba(60, 45, 20, 0.38), 0 10px 24px -12px rgba(60, 45, 20, 0.22);
  --rim: inset 0 0 0 0.5px rgba(0, 0, 0, 0.08), inset 0 -0.5px 0 rgba(255, 255, 255, 0.8);
  --knob: #ffffff;
}

/* MARK: Notch */

.notch {
  position: absolute; top: 0;
  width: var(--w, 132px); height: var(--h, 30px);
  border-radius: 0 0 var(--r, 15px) var(--r, 15px);
  background: linear-gradient(180deg, var(--glass-top), var(--glass));
  -webkit-backdrop-filter: blur(30px) saturate(1.6); backdrop-filter: blur(30px) saturate(1.6);
  box-shadow: var(--shadow), var(--rim);
  pointer-events: auto; overflow: hidden; isolation: isolate;
  transition: width 0.62s var(--spring), height 0.62s var(--spring), border-radius 0.62s var(--spring),
    translate 0.5s var(--spring), opacity 0.3s ease, box-shadow 0.4s ease;
}
.sv[data-pos="center"] .notch { left: 50%; translate: -50% var(--ty, 0px); }
.sv[data-pos="left"] .notch { left: 18px; translate: 0 var(--ty, 0px); }
.sv[data-pos="right"] .notch { right: 18px; translate: 0 var(--ty, 0px); }
.notch:focus { outline: none; }

.ears { position: absolute; top: 0; height: 10px; pointer-events: none; width: var(--w, 132px);
  transition: width 0.62s var(--spring), translate 0.5s var(--spring), opacity 0.3s ease; }
.sv[data-pos="center"] .ears { left: 50%; translate: -50% var(--ty, 0px); }
.sv[data-pos="left"] .ears { left: 18px; translate: 0 var(--ty, 0px); }
.sv[data-pos="right"] .ears { right: 18px; translate: 0 var(--ty, 0px); }
.ears::before, .ears::after { content: ""; position: absolute; top: 0; width: 10px; height: 10px; }
.ears::before { left: -10px; background: radial-gradient(circle at 0 100%, transparent 9.5px, var(--glass-top) 10px); }
.ears::after { right: -10px; background: radial-gradient(circle at 100% 100%, transparent 9.5px, var(--glass-top) 10px); }

.sv[data-slim] .notch { --w: 92px !important; --h: 6px !important; --r: 4px !important; }
.sv[data-slim] .ears { opacity: 0; }
.sv[data-gone] .notch { --h: 0px !important; opacity: 0; box-shadow: none; }
.sv[data-gone] .ears { opacity: 0; }
.sv[data-hidden] .notch, .sv[data-hidden] .ears, .sv[data-hidden] .float-toast { opacity: 0 !important; pointer-events: none !important; transition: none !important; }

.layer {
  position: absolute; top: 0; opacity: 0; pointer-events: none;
  transform: scale(0.94); filter: blur(6px); transform-origin: 50% 0;
  transition: opacity 0.18s ease, transform 0.55s var(--spring), filter 0.22s ease;
}
.sv[data-pos="center"] .layer { left: 50%; translate: -50% 0; }
.sv[data-pos="left"] .layer { left: 0; transform-origin: 0 0; }
.sv[data-pos="right"] .layer { right: 0; transform-origin: 100% 0; }
.layer.on { opacity: 1; transform: none; filter: none; pointer-events: auto; transition-delay: 0.07s, 0s, 0.05s; }
.layer.idle, .layer.mode, .layer.toast { width: max-content; }
.sv[data-slim] .layer.idle { opacity: 0; }

/* MARK: Idle */

.sv[data-view="idle"] .notch {
  box-shadow: var(--shadow), var(--rim), 0 0 0 1.5px #e4d0aa, 0 10px 28px rgba(0, 0, 0, 0.4);
}
.idle { height: 30px; padding: 0 16px; display: flex; align-items: center; justify-content: center; gap: 9px; white-space: nowrap; cursor: pointer; }
.idle .mark { color: #f4ead8; opacity: 1; }
.idle .dots { display: flex; gap: 4px; }
.idle .dots:empty { display: none; }
.dot { width: 5px; height: 5px; border-radius: 50%; background: var(--accent); }
.dot.note { background: var(--warning); }
.dot.dark { background: #9fb6ff; }
.dot.live { background: var(--danger); animation: pulse 1.4s ease-in-out infinite; }
@keyframes pulse { 50% { opacity: 0.35; } }

/* MARK: Shared controls */

.iconbtn { width: 28px; height: 28px; border-radius: 9px; border: 0; padding: 0; background: transparent; color: var(--ink-2);
  display: grid; place-items: center; cursor: pointer; flex: none;
  transition: background 0.15s ease, color 0.15s ease, transform 0.3s var(--spring); }
.iconbtn:hover { background: var(--tile-hover); color: var(--ink); }
.iconbtn:active { transform: scale(0.9); }
.iconbtn[aria-pressed="true"] { color: var(--accent); background: var(--tile-active); }
.btn { height: 30px; padding: 0 12px; border-radius: 999px; border: 0; background: var(--tile); color: var(--ink);
  font-size: 12.5px; font-weight: 500; display: inline-flex; align-items: center; justify-content: center; gap: 6px; cursor: pointer; white-space: nowrap;
  transition: background 0.15s ease, transform 0.3s var(--spring), opacity 0.2s ease; }
.btn:hover { background: var(--tile-hover); }
.btn:active { transform: scale(0.95); }
.btn.primary { background: var(--accent); color: var(--on-accent); }
.btn.primary:hover { background: color-mix(in srgb, var(--accent) 88%, white); }
.btn.small { height: 26px; padding: 0 10px; font-size: 12px; }
.btn[disabled] { opacity: 0.45; pointer-events: none; }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
kbd { font-family: var(--font); font-size: 10.5px; line-height: 16px; padding: 0 5px; border-radius: 5px; background: var(--tile); color: var(--ink-2);
  box-shadow: inset 0 -1px 0 var(--line-strong); white-space: nowrap; }

.seg { display: inline-flex; padding: 2px; border-radius: 10px; background: var(--tile); gap: 2px; }
.seg button { height: 26px; padding: 0 10px; border-radius: 8px; border: 0; background: transparent; color: var(--ink-2); font-size: 12px; font-weight: 500; cursor: pointer; white-space: nowrap;
  transition: background 0.2s ease, color 0.2s ease; }
.seg button:hover { color: var(--ink); }
.seg button[aria-pressed="true"] { background: var(--tile-hover); color: var(--ink); box-shadow: 0 1px 3px rgba(0, 0, 0, 0.18), inset 0 0 0 0.5px var(--line-strong); }

.switch { width: 38px; height: 22px; border-radius: 11px; border: 0; padding: 0; background: var(--tile-hover); position: relative; cursor: pointer; flex: none;
  transition: background 0.25s ease; }
.switch::after { content: ""; position: absolute; top: 2px; left: 2px; width: 18px; height: 18px; border-radius: 50%; background: var(--knob);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.35); transition: translate 0.45s var(--spring); }
.switch[aria-checked="true"] { background: var(--accent); }
.switch[aria-checked="true"]::after { translate: 16px 0; }

input[type="range"] { -webkit-appearance: none; appearance: none; height: 22px; margin: 0; background: transparent; cursor: pointer; flex: 1; min-width: 0; }
input[type="range"]::-webkit-slider-runnable-track { height: 6px; border-radius: 3px;
  background: linear-gradient(90deg, var(--accent) var(--p, 50%), var(--tile-hover) var(--p, 50%)); }
input[type="range"]::-webkit-slider-thumb { -webkit-appearance: none; width: 16px; height: 16px; margin-top: -5px; border-radius: 50%;
  background: var(--knob); box-shadow: 0 1px 4px rgba(0, 0, 0, 0.4), 0 0 0 0.5px rgba(0, 0, 0, 0.18); transition: transform 0.25s var(--spring); }
input[type="range"]:active::-webkit-slider-thumb { transform: scale(1.12); }

.muted { color: var(--ink-2); }
.faint { color: var(--ink-3); }
.row { display: flex; align-items: center; gap: 10px; }
.grow { flex: 1; min-width: 0; }
.ellipsis { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.mono { font-family: var(--mono); font-size: 12px; letter-spacing: 0; }
.spinner { width: 14px; height: 14px; border-radius: 50%; border: 2px solid var(--line-strong); border-top-color: var(--ink); animation: spin 0.8s linear infinite; flex: none; }
@keyframes spin { to { rotate: 360deg; } }

/* MARK: Home */

.home, .panel { width: 452px; padding: 10px 14px 14px; }
.head { display: flex; align-items: center; gap: 9px; height: 32px; margin-bottom: 4px; }
.head .mark { color: var(--accent); }
.head .brand { font-weight: 650; font-size: 12.5px; letter-spacing: 0.08em; }
.head .site { color: var(--ink-3); font-size: 12px; }
.section { margin-top: 12px; }
.section-title { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin: 0 2px 8px;
  font-size: 10.5px; font-weight: 650; letter-spacing: 0.08em; text-transform: uppercase; color: var(--ink-3); }
.section-title .aside { text-transform: none; letter-spacing: 0; font-weight: 500; font-size: 11.5px; color: var(--ink-2); display: flex; gap: 10px; }
.grid { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 6px; }
.tile { position: relative; display: flex; flex-direction: column; align-items: center; gap: 6px; padding: 9px 2px 8px; border-radius: 14px; border: 0;
  background: var(--tile); color: var(--ink); cursor: pointer; min-width: 0;
  transition: background 0.15s ease, transform 0.35s var(--spring); }
.tile:hover { background: var(--tile-hover); }
.tile:active { transform: scale(0.94); }
.glyph { width: 34px; height: 34px; border-radius: 11px; display: grid; place-items: center;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.09), rgba(255, 255, 255, 0.02)); box-shadow: inset 0 0 0 0.5px var(--line-strong);
  transition: background 0.25s ease, color 0.25s ease; }
.sv[data-theme="light"] .glyph { background: linear-gradient(180deg, #fff, rgba(255, 255, 255, 0.5)); }
.tile .label { font-size: 11px; color: var(--ink-2); max-width: 100%; padding: 0 3px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tile.on { background: var(--tile-active); }
.tile.on .glyph { background: var(--accent); color: var(--on-accent); box-shadow: none; }
.tile.on .label { color: var(--ink); }
.tile .badge { position: absolute; top: 7px; right: 9px; width: 6px; height: 6px; border-radius: 50%; background: var(--warning); }

.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.chip { flex: 1 1 calc((100% - 12px) / 3); height: 32px; padding: 0 8px; border-radius: 11px; border: 0; background: var(--tile); color: var(--ink); font-size: 12px; font-weight: 500;
  display: inline-flex; align-items: center; justify-content: center; gap: 6px; cursor: pointer; min-width: 0; white-space: nowrap;
  transition: background 0.2s ease, color 0.2s ease, transform 0.35s var(--spring); }
.chip span { overflow: hidden; text-overflow: ellipsis; }
.chip:hover { background: var(--tile-hover); }
.chip:active { transform: scale(0.95); }
.chip.on { background: var(--accent); color: var(--on-accent); }

.mac { padding: 10px; border-radius: 16px; background: var(--tile); box-shadow: inset 0 0 0 0.5px var(--line); }
.mac-row { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 6px; }
.mac-btn { min-height: 52px; padding: 7px 2px; border-radius: 12px; border: 0; background: var(--tile); color: var(--ink); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px;
  font-size: 11px; line-height: 1.15; cursor: pointer; min-width: 0; transition: background 0.2s ease, color 0.2s ease, transform 0.35s var(--spring); }
.mac-btn span { max-width: 100%; padding: 0 3px; overflow: hidden; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2;
  text-align: center; text-wrap: balance; overflow-wrap: anywhere; color: inherit; opacity: 0.8; }
.mac-btn:hover { background: var(--tile-hover); }
.mac-btn:active { transform: scale(0.95); }
.mac-btn.on { background: var(--accent); color: var(--on-accent); }
.mac-btn.on span { opacity: 1; }
.mac-btn.busy { pointer-events: none; opacity: 0.7; }
.volume { display: flex; align-items: center; gap: 10px; margin-top: 8px; height: 30px; padding: 0 4px 0 2px; }
.volume .value { width: 44px; text-align: right; font-variant-numeric: tabular-nums; font-size: 12px; color: var(--ink-2); }
.mac-note { display: flex; align-items: center; gap: 10px; min-height: 40px; padding: 0 2px; font-size: 12.5px; }
.mac-note .icon { color: var(--ink-3); }
.confirm { display: flex; align-items: center; gap: 8px; margin-top: 8px; padding: 8px 8px 8px 12px; border-radius: 12px; font-size: 12px;
  background: color-mix(in srgb, var(--warning) 14%, transparent); box-shadow: inset 0 0 0 0.5px color-mix(in srgb, var(--warning) 30%, transparent); }
.foot { display: flex; justify-content: center; flex-wrap: wrap; gap: 6px 14px; margin-top: 12px; font-size: 11px; color: var(--ink-3); }
.foot span { display: inline-flex; gap: 5px; align-items: center; }

/* MARK: Panels */

.panel-head { display: flex; align-items: center; gap: 6px; height: 32px; margin: 0 -4px 10px; }
.panel-head .title { font-size: 14px; font-weight: 600; flex: 1; min-width: 0; padding-left: 2px; }
.panel-body { display: flex; flex-direction: column; gap: 10px; }
.card { padding: 12px; border-radius: 16px; background: var(--tile); box-shadow: inset 0 0 0 0.5px var(--line); }
.hint { font-size: 11.5px; color: var(--ink-3); line-height: 1.4; }
.empty { padding: 18px 8px; text-align: center; color: var(--ink-2); font-size: 12.5px; }

textarea.note { width: 100%; min-height: 150px; max-height: 360px; resize: none; border: 0; outline: none; display: block;
  padding: 12px 14px; border-radius: 14px; background: var(--tile); color: var(--ink); caret-color: var(--accent);
  font: 13.5px/1.55 var(--font); box-shadow: inset 0 0 0 0.5px var(--line); transition: box-shadow 0.2s ease; }
textarea.note:focus { box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 70%, transparent); }
textarea.note::placeholder { color: var(--ink-3); }

.setting { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 38px; }
.setting + .setting { border-top: 0.5px solid var(--line); }
.setting .name { font-size: 12.5px; }

.swatch-big { width: 68px; height: 68px; border-radius: 18px; flex: none; box-shadow: inset 0 0 0 0.5px rgba(127, 127, 127, 0.35), 0 6px 18px -8px rgba(0, 0, 0, 0.5); }
.values { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; }
.value-row { display: flex; align-items: center; gap: 8px; height: 26px; padding: 0 4px 0 8px; border-radius: 8px; border: 0; background: transparent; cursor: pointer; text-align: left; width: 100%; }
.value-row:hover { background: var(--tile-hover); }
.value-row .k { width: 42px; font-size: 10.5px; font-weight: 600; letter-spacing: 0.05em; color: var(--ink-3); }
.value-row .v { flex: 1; font-family: var(--mono); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.value-row .icon { color: var(--ink-3); opacity: 0; transition: opacity 0.15s ease; }
.value-row:hover .icon { opacity: 1; }
.value-row.preferred .k { color: var(--accent); }
.swatches { display: flex; flex-wrap: wrap; gap: 6px; }
.swatch { width: 26px; height: 26px; border-radius: 8px; border: 0; padding: 0; cursor: pointer; box-shadow: inset 0 0 0 0.5px rgba(127, 127, 127, 0.4); transition: transform 0.3s var(--spring); }
.swatch:hover { transform: scale(1.12); }
.ratio { font-size: 22px; font-weight: 650; font-variant-numeric: tabular-nums; letter-spacing: -0.02em; }
.pass { display: inline-flex; align-items: center; height: 20px; padding: 0 7px; border-radius: 6px; font-size: 10.5px; font-weight: 650; letter-spacing: 0.03em; }
.pass.ok { background: color-mix(in srgb, var(--positive) 20%, transparent); color: var(--positive); }
.pass.no { background: color-mix(in srgb, var(--danger) 18%, transparent); color: var(--danger); }
.pair { width: 40px; height: 28px; border-radius: 8px; display: grid; place-items: center; font-weight: 700; font-size: 13px; flex: none; box-shadow: inset 0 0 0 0.5px rgba(127, 127, 127, 0.35); }

.options { display: flex; flex-direction: column; gap: 6px; }
.option { display: flex; align-items: center; gap: 12px; padding: 10px 12px; border-radius: 14px; border: 0; background: var(--tile); color: var(--ink); cursor: pointer; text-align: left; width: 100%;
  transition: background 0.15s ease, transform 0.35s var(--spring); }
.option:hover { background: var(--tile-hover); }
.option:active { transform: scale(0.98); }
.option .glyph { width: 36px; height: 36px; }
.option .t { font-size: 13px; font-weight: 550; }
.option .d { font-size: 11.5px; color: var(--ink-2); margin-top: 1px; }

.qr-wrap { display: flex; gap: 14px; align-items: center; }
.qr { width: 132px; height: 132px; border-radius: 14px; background: #fff; padding: 0; flex: none; image-rendering: pixelated; box-shadow: 0 6px 18px -8px rgba(0, 0, 0, 0.5); }
.url { font-family: var(--mono); font-size: 11.5px; line-height: 1.45; word-break: break-all; color: var(--ink-2); max-height: 64px; overflow: hidden; }
.url mark { background: color-mix(in srgb, var(--danger) 22%, transparent); color: inherit; border-radius: 3px; text-decoration: line-through; }
.speeds { display: grid; grid-template-columns: repeat(8, minmax(0, 1fr)); gap: 4px; }
.speeds button { height: 30px; border-radius: 9px; border: 0; background: var(--tile); font-size: 12px; font-weight: 550; cursor: pointer; font-variant-numeric: tabular-nums; transition: background 0.15s ease; }
.speeds button:hover { background: var(--tile-hover); }
.speeds button[aria-pressed="true"] { background: var(--accent); color: var(--on-accent); }
.big-rate { font-size: 30px; font-weight: 650; letter-spacing: -0.03em; font-variant-numeric: tabular-nums; min-width: 84px; text-align: center; }

/* MARK: Mode capsule and toast */

.mode { height: 42px; padding: 0 6px 0 14px; display: flex; align-items: center; gap: 10px; white-space: nowrap; }
.mode .live { width: 7px; height: 7px; border-radius: 50%; background: var(--accent); box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 25%, transparent); animation: pulse 1.6s ease-in-out infinite; flex: none; }
.mode .name { font-weight: 600; font-size: 12.5px; }
.mode .what { color: var(--ink-2); font-size: 12px; max-width: 360px; overflow: hidden; text-overflow: ellipsis; }
.mode .actions { display: flex; gap: 4px; align-items: center; }
.mode .sep { width: 0.5px; height: 18px; background: var(--line-strong); }
.toast { height: 36px; padding: 0 16px 0 13px; display: flex; align-items: center; gap: 8px; white-space: nowrap; font-weight: 500; font-size: 12.5px; }
.toast .icon { color: var(--accent); }
.toast[data-tone="ok"] .icon { color: var(--positive); }
.toast[data-tone="warn"] .icon { color: var(--warning); }
.toast[data-tone="bad"] .icon { color: var(--danger); }
.float-toast { position: absolute; top: calc(var(--h, 30px) + 12px); height: 36px; padding: 0 16px 0 13px; border-radius: 999px; display: flex; align-items: center; gap: 8px;
  background: var(--float); -webkit-backdrop-filter: blur(24px); backdrop-filter: blur(24px); box-shadow: var(--shadow), var(--rim);
  font-weight: 500; font-size: 12.5px; white-space: nowrap; opacity: 0; translate: var(--fx, -50%) -8px; pointer-events: none;
  transition: opacity 0.22s ease, translate 0.5s var(--spring), top 0.62s var(--spring); }
.sv[data-pos="center"] .float-toast { left: 50%; --fx: -50%; }
.sv[data-pos="left"] .float-toast { left: 18px; --fx: 0px; }
.sv[data-pos="right"] .float-toast { right: 18px; --fx: 0px; }
.float-toast.on { opacity: 1; translate: var(--fx, -50%) 0; }
.float-toast .icon { color: var(--accent); }
.float-toast[data-tone="ok"] .icon { color: var(--positive); }
.float-toast[data-tone="warn"] .icon { color: var(--warning); }
.float-toast[data-tone="bad"] .icon { color: var(--danger); }

/* MARK: Overlays */

.overlays { position: absolute; inset: 0; pointer-events: none; }
.box { position: fixed; pointer-events: none; }
.box.margin { background: rgba(246, 178, 107, 0.28); }
.box.border { background: rgba(255, 229, 153, 0.35); }
.box.padding { background: rgba(147, 196, 125, 0.4); }
.box.content { background: rgba(111, 168, 220, 0.42); }
.box.pinned { outline: 1.5px solid #ff5c7a; outline-offset: -1px; background: rgba(255, 92, 122, 0.08); }
.box.zap { background: rgba(255, 115, 99, 0.16); outline: 2px solid #ff7363; outline-offset: -1px; border-radius: 3px; transition: all 0.08s linear; }
.tag { position: fixed; pointer-events: none; padding: 3px 7px; border-radius: 6px; background: rgba(20, 20, 22, 0.92); color: #f7f5f0;
  font: 600 11px/1.3 var(--mono); white-space: nowrap; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.35); }
.tag .faint { color: rgba(247, 245, 240, 0.55); font-weight: 500; }
.tag.red { background: #ff5c7a; color: #fff; }
.guide { position: fixed; pointer-events: none; background: #ff5c7a; }
.guide.h { height: 1px; }
.guide.v { width: 1px; }
.guide.dash.h { background: repeating-linear-gradient(90deg, #ff5c7a 0 4px, transparent 4px 7px); }
.guide.dash.v { background: repeating-linear-gradient(180deg, #ff5c7a 0 4px, transparent 4px 7px); }
.measure { position: fixed; pointer-events: none; outline: 1px dashed #ff5c7a; background: rgba(255, 92, 122, 0.08); }
.inspector { position: fixed; pointer-events: none; width: 264px; padding: 12px 13px; border-radius: 16px; background: var(--float); color: var(--ink);
  -webkit-backdrop-filter: blur(24px); backdrop-filter: blur(24px); box-shadow: var(--shadow), var(--rim); font-size: 12px; }
.inspector .family { font-size: 15px; font-weight: 600; margin-bottom: 8px; line-height: 1.25; word-break: break-word; }
.inspector .facts { display: grid; grid-template-columns: auto 1fr; gap: 3px 12px; }
.inspector .facts .k { color: var(--ink-3); }
.inspector .facts .v { font-family: var(--mono); font-size: 11.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.inspector .chipcolor { display: inline-block; width: 10px; height: 10px; border-radius: 3px; vertical-align: -1px; margin-right: 5px; box-shadow: inset 0 0 0 0.5px rgba(127, 127, 127, 0.5); }

.region { position: absolute; inset: 0; pointer-events: auto; cursor: crosshair; background: rgba(0, 0, 0, 0.32); }
.region.dragging { background: transparent; }
.region .sel { position: fixed; box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.42); outline: 1px solid rgba(255, 255, 255, 0.9); pointer-events: none; }
.region .size { position: fixed; pointer-events: none; }

/* MARK: Reader */

.reader { position: absolute; inset: 0; pointer-events: none; overflow-y: auto; overscroll-behavior: contain; opacity: 0; translate: 0 14px;
  background: var(--r-bg); color: var(--r-ink); transition: opacity 0.3s ease, translate 0.55s var(--spring), background 0.3s ease, color 0.3s ease;
  --r-bg: #f8f5ef; --r-ink: #24211d; --r-ink2: #6f695f; --r-link: #8a6f45; --r-rule: rgba(0, 0, 0, 0.09); --r-code: rgba(0, 0, 0, 0.05);
  --r-font: "New York", "Iowan Old Style", Charter, Georgia, "Times New Roman", serif; color-scheme: light; }
.reader.on { opacity: 1; translate: none; pointer-events: auto; }
.sv[data-hidden] .r-bar, .sv[data-hidden] .r-progress { opacity: 0 !important; transition: none !important; }
.reader[data-theme="sepia"] { --r-bg: #f3ead6; --r-ink: #3a2e1f; --r-ink2: #7a6a52; --r-link: #8d5e2a; --r-rule: rgba(80, 50, 10, 0.12); --r-code: rgba(80, 50, 10, 0.07); }
.reader[data-theme="dark"] { --r-bg: #161514; --r-ink: #e8e4db; --r-ink2: #a19a8d; --r-link: #dbc7a3; --r-rule: rgba(255, 255, 255, 0.09); --r-code: rgba(255, 255, 255, 0.07); color-scheme: dark; }
.reader[data-font="sans"] { --r-font: var(--font); }
.reader article { max-width: var(--r-width, 700px); margin: 0 auto; padding: 92px 28px 180px; font-family: var(--r-font); font-size: var(--r-size, 20px); line-height: 1.68;
  overflow-wrap: break-word; hyphens: auto; }
.reader .r-site { font: 600 12px/1 var(--font); letter-spacing: 0.08em; text-transform: uppercase; color: var(--r-link); margin-bottom: 18px; }
.reader .r-title { font-size: 2.05em; line-height: 1.14; letter-spacing: -0.02em; margin: 0 0 0.45em; font-weight: 700; }
.reader .r-meta { font: 14px/1.4 var(--font); color: var(--r-ink2); margin-bottom: 2.4em; display: flex; flex-wrap: wrap; gap: 6px 14px; }
.reader .r-body > :first-child { margin-top: 0; }
.reader .r-body :is(h1, h2, h3, h4, h5) { line-height: 1.25; letter-spacing: -0.012em; margin: 1.7em 0 0.55em; font-weight: 700; }
.reader .r-body h1 { font-size: 1.5em; } .reader .r-body h2 { font-size: 1.32em; } .reader .r-body h3 { font-size: 1.14em; } .reader .r-body :is(h4, h5) { font-size: 1em; }
.reader .r-body p { margin: 0 0 1.1em; }
.reader .r-body :is(img, video, svg, picture, canvas) { max-width: 100%; height: auto; }
.reader .r-body img { display: block; margin: 1.5em auto; border-radius: 10px; }
.reader .r-body figure { margin: 1.8em 0; }
.reader .r-body figure img { margin: 0 auto; }
.reader .r-body figcaption { font: 14px/1.45 var(--font); color: var(--r-ink2); text-align: center; margin-top: 0.7em; }
.reader .r-body blockquote { margin: 1.5em 0; padding: 0.1em 0 0.1em 1.1em; border-left: 3px solid var(--r-link); color: var(--r-ink2); }
.reader .r-body pre { font-family: var(--mono); font-size: 0.74em; line-height: 1.55; background: var(--r-code); padding: 14px 16px; border-radius: 12px; overflow: auto; white-space: pre; hyphens: none; }
.reader .r-body code { font-family: var(--mono); font-size: 0.84em; background: var(--r-code); padding: 0.1em 0.35em; border-radius: 5px; hyphens: none; }
.reader .r-body pre code { background: none; padding: 0; font-size: 1em; }
.reader .r-body a { color: var(--r-link); text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 3px; }
.reader .r-body :is(ul, ol) { padding-left: 1.35em; margin: 0 0 1.1em; }
.reader .r-body li { margin: 0.3em 0; }
.reader .r-body hr { border: 0; border-top: 1px solid var(--r-rule); margin: 2.2em 0; }
.reader .r-body table { border-collapse: collapse; display: block; overflow-x: auto; font: 15px/1.45 var(--font); margin: 1.4em 0; }
.reader .r-body :is(td, th) { border: 1px solid var(--r-rule); padding: 6px 10px; text-align: left; vertical-align: top; }
.reader .r-body iframe { max-width: 100%; border: 0; border-radius: 10px; }
.r-progress { position: fixed; top: 0; left: 0; height: 3px; width: 100%; transform-origin: 0 0; scale: var(--progress, 0) 1; background: var(--r-link); z-index: 2; pointer-events: none; }
.r-bar { position: fixed; bottom: 24px; left: 50%; translate: -50% 0; display: flex; align-items: center; gap: 4px; padding: 5px; border-radius: 999px; z-index: 3;
  background: var(--float); color: var(--ink); -webkit-backdrop-filter: blur(24px); backdrop-filter: blur(24px); box-shadow: var(--shadow), var(--rim);
  font-family: var(--font); transition: opacity 0.3s ease, translate 0.45s var(--spring); }
.r-bar.away { opacity: 0; translate: -50% 20px; pointer-events: none; }
.r-bar .sep { width: 0.5px; height: 18px; background: var(--line-strong); margin: 0 3px; }
.r-bar .tbtn { height: 32px; min-width: 32px; padding: 0 10px; border-radius: 999px; border: 0; background: transparent; cursor: pointer; display: grid; place-items: center; font-size: 13px; font-weight: 600; }
.r-bar .tbtn:hover { background: var(--tile-hover); }
.r-bar .tbtn[aria-pressed="true"] { background: var(--tile-hover); }
.r-bar .theme-dot { width: 18px; height: 18px; border-radius: 50%; box-shadow: inset 0 0 0 1px rgba(127, 127, 127, 0.45); }

/* MARK: Gallery */

.gallery { position: absolute; inset: 0; pointer-events: none; overflow-y: auto; overscroll-behavior: contain; opacity: 0; translate: 0 12px;
  background: color-mix(in srgb, var(--glass) 92%, transparent); -webkit-backdrop-filter: blur(26px) saturate(1.4); backdrop-filter: blur(26px) saturate(1.4);
  transition: opacity 0.3s ease, translate 0.5s var(--spring); }
.gallery.on { opacity: 1; translate: none; pointer-events: auto; }
.gallery .g-head { position: sticky; top: 0; z-index: 2; display: flex; align-items: center; gap: 12px; padding: 64px 32px 16px; max-width: 1240px; margin: 0 auto;
  background: linear-gradient(180deg, var(--glass) 60%, transparent); }
.gallery .g-title { font-size: 20px; font-weight: 650; letter-spacing: -0.015em; }
.gallery .g-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 12px; padding: 4px 32px 80px; max-width: 1240px; margin: 0 auto; }
.g-card { position: relative; border-radius: 14px; overflow: hidden; background: var(--tile); box-shadow: inset 0 0 0 0.5px var(--line); aspect-ratio: 1; cursor: pointer; }
.g-card img { width: 100%; height: 100%; object-fit: contain; display: block; background:
  repeating-conic-gradient(rgba(127, 127, 127, 0.14) 0 25%, transparent 0 50%) 0 0 / 16px 16px; }
.g-card .g-info { position: absolute; left: 0; right: 0; bottom: 0; padding: 22px 10px 8px; display: flex; align-items: center; gap: 6px;
  background: linear-gradient(180deg, transparent, rgba(0, 0, 0, 0.72)); color: #fff; font-size: 11.5px; font-variant-numeric: tabular-nums; }
.g-card .g-info .grow { opacity: 0.9; }
.g-card .iconbtn { color: #fff; width: 26px; height: 26px; background: rgba(255, 255, 255, 0.14); opacity: 0; transition: opacity 0.15s ease; }
.g-card:hover .iconbtn { opacity: 1; }
.g-card .iconbtn:hover { background: rgba(255, 255, 255, 0.28); }

@media (prefers-reduced-motion: reduce) {
  .notch, .ears, .layer, .float-toast, .reader, .gallery { transition-duration: 0.01s !important; }
}
`;
})();
