// The SAVISUL panel (⌃⌥S), rebuilt from the app's SwiftUI source: same tabs, cards, controls, copy and sizes.
// Copy comes from the app's own string table (app-strings.js); the data is the app's preview sample.
import { h, clear } from './dom.js';
import { mark } from './icons.js';
import { sym, appTile } from './panel-icons.js';
import { APP_STRINGS } from './app-strings.js';
import { lang as siteLang, setLang, onLang } from './i18n.js';
import { CONFIG } from './config.js';
import { FEATURE_GROUPS, FEATURE_DEFAULTS, FEATURE_PHRASES, FEATURE_STRINGS } from './features-data.js';

// The Features tab's two table strings ride with its generated data.
for (const [key, byLang] of Object.entries(FEATURE_STRINGS)) {
  for (const [code, value] of Object.entries(byLang)) if (APP_STRINGS[code]) APP_STRINGS[code][key] ??= value;
}

const C = {
  ink: 'rgb(247, 245, 240)', secondary: 'rgba(255, 255, 255, 0.64)', tertiary: 'rgba(255, 255, 255, 0.48)',
  accent: 'rgb(219, 199, 163)', positive: 'rgb(140, 214, 176)', warning: 'rgb(245, 186, 102)', danger: 'rgb(255, 115, 99)',
  onLight: 'rgb(20, 20, 23)', inkSoft: 'rgba(247, 245, 240, 0.7)'
};
const LOCALES = { en: 'en-US', ru: 'ru-RU', uk: 'uk-UA', fr: 'fr-FR' };
const NATIVE = { en: 'English', ru: 'Русский', uk: 'Українська', fr: 'Français' };
const TABS = [['energy', 'bolt', 'boltFill', 'tabEnergy'], ['sound', 'speaker', 'speakerFill', 'tabSound'], ['system', 'cpu', 'cpuFill', 'tabSystem'],
  ['work', 'code', 'code', 'tabWork'], ['tools', 'grid', 'gridFill', 'tabTools'], ['features', 'wand', 'wandFill', 'tabFeatures']];
const DEVICE_NAMES = {
  speakers: { en: 'MacBook Pro Speakers', ru: 'Динамики MacBook Pro', uk: 'Динаміки MacBook Pro', fr: 'Haut-parleurs MacBook Pro' },
  mic: { en: 'MacBook Pro Microphone', ru: 'Микрофон MacBook Pro', uk: 'Мікрофон MacBook Pro', fr: 'Micro MacBook Pro' },
  music: { en: 'Music', ru: 'Музыка', uk: 'Музика', fr: 'Musique' }
};

// Copy that lives next to its feature in the app (Phrase values in WorkPane, SystemPane/FanControl and the Automations
// files), in the app's four languages.
const PH = {
  aiTokens: { en: 'AI tokens', ru: 'ИИ-токены', uk: 'ШІ-токени', fr: 'Jetons IA' },
  code: { en: 'Code', ru: 'Код', uk: 'Код', fr: 'Code' },
  typedChars: { en: '%@ chars typed', ru: 'набрано %@ симв.', uk: 'набрано %@ симв.', fr: '%@ caractères tapés' },
  tokens: { en: '%@ tokens', ru: '%@ токенов', uk: '%@ токенів', fr: '%@ jetons' },
  workNote: { en: 'AI tokens and code come from the agents’ own logs and Cursor’s AI tracking, inside each project folder. Cache reads aren’t counted as tokens.',
    ru: 'ИИ-токены и код берутся из журналов самих агентов и учёта ИИ в Cursor, только внутри папки проекта. Чтение из кэша не считается токенами.',
    uk: 'ШІ-токени й код беруться з журналів самих агентів і обліку ШІ в Cursor, лише в теці проєкту. Читання з кешу не рахується токенами.',
    fr: 'Les jetons et le code IA viennent des journaux des agents et du suivi IA de Cursor, dans chaque dossier de projet. Les lectures de cache ne comptent pas.' },
  fanTitle: { en: 'Fans and cooling', ru: 'Вентиляторы и охлаждение', uk: 'Вентилятори й охолодження', fr: 'Ventilateurs et refroidissement' },
  modeAuto: { en: 'Auto', ru: 'Авто', uk: 'Авто', fr: 'Auto' },
  modeSmart: { en: 'Smart', ru: 'Умный', uk: 'Розумний', fr: 'Intelligent' },
  modeMax: { en: 'Max', ru: 'Максимум', uk: 'Максимум', fr: 'Max' },
  modeManual: { en: 'Manual', ru: 'Вручную', uk: 'Вручну', fr: 'Manuel' },
  fanAutomatic: { en: 'macOS controls the fans', ru: 'Вентиляторами управляет macOS', uk: 'Вентиляторами керує macOS', fr: 'macOS gère les ventilateurs' },
  fanWaiting: { en: 'Fans join in above %@', ru: 'Включатся выше %@', uk: 'Увімкнуться вище %@', fr: 'Démarrent au-dessus de %@' },
  fanHolding: { en: 'Holding %@ rpm', ru: 'Держим %@ об/мин', uk: 'Тримаємо %@ об/хв', fr: 'Maintien à %@ tr/min' },
  fanRise: { en: 'Start rising at', ru: 'Начинать с', uk: 'Починати з', fr: 'Monter à partir de' },
  fanTop: { en: 'Full speed at', ru: 'Полная скорость при', uk: 'Повна швидкість при', fr: 'Pleine vitesse à' },
  fanSpeedTitle: { en: 'Speed', ru: 'Скорость', uk: 'Швидкість', fr: 'Vitesse' },
  fanCoolNote: { en: 'Speeds stay within each fan’s own limits. At 95 °C the fans go to full speed in any mode until the chip cools to 85 °C.',
    ru: 'Скорость не выходит за пределы самого вентилятора. При 95 °C вентиляторы в любом режиме идут на максимум, пока чип не остынет до 85 °C.',
    uk: 'Швидкість не виходить за межі самого вентилятора. При 95 °C вентилятори в будь-якому режимі йдуть на максимум, доки чип не охолоне до 85 °C.',
    fr: 'Les vitesses restent dans les limites de chaque ventilateur. À 95 °C, ils passent à fond quel que soit le mode, jusqu’à ce que la puce revienne à 85 °C.' },
  autoTitle: { en: 'Automations', ru: 'Автоматизации', uk: 'Автоматизації', fr: 'Automatisations' },
  autoLead: { en: 'When → if → do', ru: 'Когда → если → сделать', uk: 'Коли → якщо → зробити', fr: 'Quand → si → faire' },
  autoLeadDetail: { en: 'Something happens on the Mac and SAVISUL does the steps for you, even with the panel closed.',
    ru: 'Что-то происходит на Mac — и SAVISUL сам выполняет шаги, даже при закрытой панели.',
    uk: 'Щось відбувається на Mac — і SAVISUL сам виконує кроки, навіть із закритою панеллю.',
    fr: 'Quelque chose se passe sur le Mac et SAVISUL fait les étapes, même panneau fermé.' },
  autoNew: { en: 'New automation', ru: 'Новая автоматизация', uk: 'Нова автоматизація', fr: 'Nouvelle automatisation' },
  autoNewToast: { en: 'The editor opens in the app', ru: 'Редактор открывается в приложении', uk: 'Редактор відкривається в застосунку', fr: 'L’éditeur s’ouvre dans l’app' },
  autoTemplates: { en: 'Templates', ru: 'Шаблоны', uk: 'Шаблони', fr: 'Modèles' },
  autoRecent: { en: 'Recent runs', ru: 'Последние запуски', uk: 'Останні запуски', fr: 'Derniers lancements' },
  autoOf: { en: '%@ of %@ on', ru: 'Включено %@ из %@', uk: 'Увімкнено %@ з %@', fr: '%@ sur %@ actives' },
  autoNone: { en: 'None yet · start from a template', ru: 'Пока нет · начните с шаблона', uk: 'Поки немає · почніть із шаблону', fr: 'Aucune · partez d’un modèle' },
  autoSteps: { en: '%@ steps', ru: 'шагов: %@', uk: 'кроків: %@', fr: '%@ étapes' },
  autoAdded: { en: 'Added · %@', ru: 'Добавлено · %@', uk: 'Додано · %@', fr: 'Ajoutée · %@' },
  agoHours: { en: '2 hr ago', ru: '2 ч назад', uk: '2 год тому', fr: 'il y a 2 h' },
  agoMinutes: { en: '12 min ago', ru: '12 мин назад', uk: '12 хв тому', fr: 'il y a 12 min' }
};

// The app's five automation templates (AutomationTemplates.all), as their name and the trigger line.
const AUTO_TEMPLATES = [
  ['headphones', { en: 'AirPods connected', ru: 'Подключились AirPods', uk: 'Підключено AirPods', fr: 'AirPods connectés' },
    { en: 'Audio device connects · AirPods', ru: 'Подключилось аудиоустройство · AirPods', uk: 'Підключено аудіопристрій · AirPods', fr: 'Un appareil audio se connecte · AirPods' }, 3],
  ['folder', { en: 'PDF in Downloads', ru: 'PDF в Загрузках', uk: 'PDF у Завантаженнях', fr: 'PDF dans Téléchargements' },
    { en: 'File appears in a folder · Downloads · pdf', ru: 'В папке появился файл · Downloads · pdf', uk: 'У теці зʼявився файл · Downloads · pdf', fr: 'Un fichier arrive · Downloads · pdf' }, 4],
  ['window', { en: 'Zoom meeting', ru: 'Встреча в Zoom', uk: 'Зустріч у Zoom', fr: 'Réunion Zoom' },
    { en: 'App opens · zoom.us', ru: 'Открылось приложение · zoom.us', uk: 'Відкрито застосунок · zoom.us', fr: 'Une app s’ouvre · zoom.us' }, 4],
  ['sparkles', { en: 'Agent finished', ru: 'Агент закончил', uk: 'Агент завершив', fr: 'Agent terminé' },
    { en: 'AI agent finishes · Any agent', ru: 'ИИ-агент закончил · Любой агент', uk: 'ШІ-агент завершив · Будь-який агент', fr: 'Un agent IA termine · N’importe lequel' }, 3],
  ['battery', { en: 'Battery below 20%', ru: 'Батарея ниже 20%', uk: 'Батарея нижче 20%', fr: 'Batterie sous 20 %' },
    { en: 'Battery drops below 20%', ru: 'Батарея ниже 20%', uk: 'Батарея нижче 20%', fr: 'Batterie sous 20 %' }, 4]
];

// The app's preview data (ActivityTracker.seedPreview); the week multiplies it so the 7-day view has a week in it.
const USAGE = [
  ['cursor', 'Cursor', 'editor', 9420, 15880, 4210, 5.2], ['vscode', 'Visual Studio Code', 'editor', 2160, 2940, 120, 4.1],
  ['xcode', 'Xcode', 'editor', 1310, 1220, 0, 3.3], ['chatgpt', 'ChatGPT', 'assistant', 1870, 1430, 2380, 4.8],
  ['claude', 'Claude', 'assistant', 960, 820, 1060, 6.1], ['chrome', 'Google Chrome', 'other', 3350, 0, 0, 5.5],
  ['telegram', 'Telegram', 'other', 1420, 0, 0, 4.4], ['finder', 'Finder', 'other', 610, 0, 0, 3.9]
];

function freshState() {
  return {
    tab: 'system', menuOpen: false, toast: null,
    lidAwake: true, lidSince: Date.now() - (6 * 60 + 28) * 60000, idleHeld: false,
    battery: { percent: 82, charging: true, toFull: 48, health: 94, cycles: 177 },
    outputs: [{ id: 'speakers', sym: 'laptop', volume: 0.312, muted: false }, { id: 'airpods', name: 'AirPods Pro', sym: 'headphones', volume: 0.45, muted: false },
      { id: 'display', name: 'Studio Display', sym: 'display', volume: 0.6, muted: false }],
    inputs: [{ id: 'mic', sym: 'mic', volume: 0.71, muted: false }, { id: 'airpodsMic', name: 'AirPods Pro', sym: 'headphones', volume: 0.6, muted: false }],
    output: 'speakers', input: 'mic', outputsOpen: false, inputsOpen: false,
    mixerOn: true,
    apps: [{ id: 'music', tile: 'music', volume: 0.8, muted: false, output: null }, { id: 'facetime', name: 'FaceTime', tile: 'facetime', volume: 1, muted: false, output: 'airpods' },
      { id: 'safari', name: 'Safari', tile: 'safari', volume: 1.6, muted: false, output: null }],
    micsMuted: false, guard: true, guardLevel: 0.3, pinnedInput: '',
    cpu: 16, cpuHistory: Array.from({ length: 34 }, (_, i) => 13 + Math.sin(i / 3) * 4 + (i % 4)), memory: 71, temp: 44,
    busiest: [['WindowServer', null, 4.2], ['com.apple.WebKit.WebContent', null, 2.9], ['Safari', 'safari', 2.1], ['Cursor', 'cursor', 1.6], ['SAVISUL', 'savisul', 1.2]],
    range: 'today',
    recording: false, recordStart: 0, lastCapture: null, alerts: true, cpuLimit: 90, memoryLimit: 90, batteryLimit: 15, heatLimit: 95, workDone: true,
    hiddenFiles: false,
    openAtLogin: true, showInDock: true, pinned: false,
    features: { ...FEATURE_DEFAULTS }, featuresOpen: new Set(), featureQuery: '',
    fanMode: 'smart', fanStart: 60, fanFull: 88, fanLevel: 0.4,
    automations: [{ template: 0, on: true, ran: 'agoHours' }, { template: 3, on: false, ran: null }],
    autoLog: [[0, 'AirPods Pro', 'agoHours']]
  };
}

// MARK: Copy and formatting, as the app formats them

function makeCopy(getLang) {
  const L = (key) => APP_STRINGS[getLang()]?.[key] ?? APP_STRINGS.en[key] ?? key;
  const F = (key, ...args) => { let i = 0; return L(key).replace(/%@/g, () => String(args[i++] ?? '')); };
  const nf = (digits) => new Intl.NumberFormat(LOCALES[getLang()], { minimumFractionDigits: digits, maximumFractionDigits: digits });
  const integer = (v) => nf(0).format(Math.round(v));
  const decimal = (v, d) => nf(d).format(v);
  const pct = (number) => (getLang() === 'fr' ? `${number} %` : `${number}%`);
  const percent = (v) => pct(integer(v));
  const finePercent = (v) => { const tenths = Math.round(v * 10); return tenths % 10 === 0 ? percent(v) : pct(decimal(tenths / 10, 1)); };
  const duration = (seconds) => {
    const total = Math.max(0, Math.round(seconds));
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const [hu, mu, su, gap] = { en: ['h', 'm', 's', ''], ru: ['ч', 'мин', 'с', ' '], uk: ['год', 'хв', 'с', ' '], fr: ['h', 'min', 's', ' '] }[getLang()];
    if (hours > 0) return minutes > 0 ? `${hours}${gap}${hu} ${minutes}${gap}${mu}` : `${hours}${gap}${hu}`;
    if (minutes > 0) return `${minutes}${gap}${mu}`;
    return `${total}${gap}${su}`;
  };
  const gigabytes = (gb) => `${decimal(gb, 1)} ${{ en: 'GB', fr: 'Go', ru: 'ГБ', uk: 'ГБ' }[getLang()]}`;
  const name = (thing) => thing.name || DEVICE_NAMES[thing.id]?.[getLang()] || DEVICE_NAMES[thing.id]?.en || thing.id;
  const P = (phrase, ...args) => { let i = 0; const text = typeof phrase === 'string' ? (PH[phrase]?.[getLang()] ?? PH[phrase]?.en ?? phrase) : (phrase[getLang()] ?? phrase.en); return text.replace(/%@/g, () => String(args[i++] ?? '')); };
  // Say.compact: 2 310 000 → "2.3M" / "2,3 млн".
  const compact = (v) => {
    const units = { en: ['K', 'M'], ru: [' тыс.', ' млн'], uk: [' тис.', ' млн'], fr: [' k', ' M'] }[getLang()];
    if (v >= 1e6) return `${decimal(Math.round(v / 1e5) / 10, 1)}${units[1]}`;
    if (v >= 1e4) return `${integer(Math.round(v / 1e3))}${units[0]}`;
    return integer(v);
  };
  return { L, F, P, compact, integer, decimal, percent, finePercent, duration, gigabytes, name, celsius: (v) => `${Math.round(v)}°C` };
}

// MARK: Controls

const glass = (cls = '', shadow = false) => `ap-glass${shadow ? ' shadow' : ''}${cls ? ` ${cls}` : ''}`;

function card(children, { padding = 16, radius = 20, cls = '' } = {}) {
  return h('div', { class: `ap-card ${cls}`.trim(), style: { padding: `${padding}px`, borderRadius: `${radius}px` } }, children);
}

function cardTitle(text, trailing) {
  return h('div', { class: 'ap-card-title' }, h('span', { text }), h('span', { class: 'ap-spacer' }), trailing);
}

function rowIcon(name, tint = C.ink, size = 30) {
  return h('span', { class: 'ap-row-icon', style: { width: `${size}px`, height: `${size}px`, borderRadius: `${size * 0.3}px`, color: tint, '--tint': tint } },
    sym(name, Math.round(size * 0.52)));
}

const hairline = (inset = 0) => h('div', { class: 'ap-hairline', style: { marginLeft: `${inset}px` } });
const footnote = (text) => h('p', { class: 'ap-footnote', text });

function glassSwitch(isOn, label, onToggle) {
  const el = h('button', { class: 'ap-switch', type: 'button', role: 'switch', 'aria-checked': String(isOn), 'aria-label': label });
  el.addEventListener('click', () => {
    const next = el.getAttribute('aria-checked') !== 'true';
    el.setAttribute('aria-checked', String(next));
    setTimeout(() => onToggle(next), 260);
  });
  return el;
}

function glassIconButton(name, { size = 34, selected = false, tint = C.ink, help, onClick }) {
  return h('button', {
    class: `${glass('ap-icon-btn')}${selected ? ' selected' : ''}`, type: 'button', title: help, 'aria-label': help,
    style: { width: `${size}px`, height: `${size}px`, color: selected ? C.onLight : tint }, onclick: onClick
  }, sym(name, Math.round(size * 0.44)));
}

function pillButton(title, { symbol, prominent = false, onClick }) {
  return h('button', { class: `${glass('ap-pill')}${prominent ? ' prominent' : ''}`, type: 'button', onclick: onClick },
    symbol ? sym(symbol, 12) : null, h('span', { text: title }));
}

function levelBar(fraction, tint = C.accent, height = 5) {
  const f = Math.min(Math.max(fraction, 0), 1);
  return h('div', { class: 'ap-level', style: { height: `${height}px` } },
    h('span', { style: { width: `max(${height}px, ${f * 100}%)`, background: `linear-gradient(90deg, color-mix(in srgb, ${tint} 65%, transparent), ${tint})` } }));
}

function statusBadge(text, tint) {
  return h('span', { class: 'ap-badge', style: { '--tint': tint } }, h('i'), h('span', { text }));
}

function keyCaps(keys, size = 24, radius = 7) {
  return h('span', { class: 'ap-keys' }, keys.map((key) => h('span', {
    class: glass('ap-key'), text: key, style: { width: `${size}px`, height: `${size}px`, borderRadius: `${radius}px`, fontSize: `${size * 0.5}px` }
  })));
}

// Drag anywhere on the track; hold ⌥ for tenfold finer steps. Mirrors FineSlider.
function fineSlider({ value, min = 0, max = 1, detent = null, tint = C.accent, onChange, onEnd, label }) {
  const fill = h('span', { class: 'ap-slider-fill' });
  const knob = h('span', { class: 'ap-slider-knob' });
  const el = h('div', { class: 'ap-slider', role: 'slider', tabindex: '0', 'aria-label': label, 'aria-valuemin': String(min), 'aria-valuemax': String(max) },
    h('span', { class: 'ap-slider-track' }), fill, detent != null ? h('span', { class: 'ap-slider-detent' }) : null, knob);
  const span = max - min;
  let current = value;
  const norm = (v) => Math.min(Math.max((v - min) / span, 0), 1);
  const paint = () => {
    const p = norm(current);
    el.style.setProperty('--p', p);
    fill.style.background = `linear-gradient(90deg, color-mix(in srgb, ${typeof tint === 'function' ? tint(current) : tint} 70%, transparent), ${typeof tint === 'function' ? tint(current) : tint})`;
    el.setAttribute('aria-valuenow', String(Math.round(current * 1000) / 1000));
  };
  if (detent != null) el.style.setProperty('--d', norm(detent));
  paint();
  let anchor = null;
  const set = (v) => {
    let next = Math.min(Math.max(v, min), max);
    if (detent != null && Math.abs(next - detent) < span * 0.018) next = detent;
    current = next;
    paint();
    onChange(next);
  };
  el.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    el.setPointerCapture(event.pointerId);
    el.classList.add('dragging');
    const rect = el.getBoundingClientRect();
    const track = rect.width - 20;
    if (event.altKey) anchor = { x: event.clientX, value: current, track };
    else {
      anchor = { x: event.clientX, value: min + Math.min(Math.max((event.clientX - rect.left - 10) / track, 0), 1) * span, track };
      set(anchor.value);
    }
  });
  el.addEventListener('pointermove', (event) => {
    if (!anchor) return;
    const factor = event.altKey ? 0.1 : 1;
    set(anchor.value + ((event.clientX - anchor.x) / anchor.track) * span * factor);
  });
  const end = () => { if (!anchor) return; anchor = null; el.classList.remove('dragging'); onEnd?.(current); };
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', end);
  el.addEventListener('keydown', (event) => {
    const step = span * (event.altKey ? 0.001 : 0.01);
    if (event.key === 'ArrowRight' || event.key === 'ArrowUp') { event.preventDefault(); set(current + step); onEnd?.(current); }
    if (event.key === 'ArrowLeft' || event.key === 'ArrowDown') { event.preventDefault(); set(current - step); onEnd?.(current); }
  });
  el.update = (v) => { current = v; paint(); };
  return el;
}

// Capsule segmented control whose ink thumb slides between options.
function segmented(id, items, selection, onSelect, memory) {
  const index = Math.max(0, items.findIndex(([value]) => value === selection));
  const from = memory.get(id) ?? index;
  memory.set(id, index);
  const thumb = h('span', { class: 'ap-seg-thumb' });
  const el = h('div', { class: glass('ap-seg'), style: { '--n': items.length, '--i': from } }, thumb,
    items.map(([value, title]) => h('button', {
      type: 'button', class: value === selection ? 'on' : '', 'aria-pressed': String(value === selection), onclick: () => onSelect(value)
    }, title)));
  if (from !== index) requestAnimationFrame(() => requestAnimationFrame(() => el.style.setProperty('--i', index)));
  return el;
}

function sparkline(values, tint) {
  const W = 160;
  const H = 30;
  const slots = 60;
  const step = W / (slots - 1);
  const start = W - (values.length - 1) * step;
  const pts = values.map((v, i) => [start + i * step, H - 1 - (Math.min(Math.max(v, 0), 100) / 100) * (H - 2)]);
  const line = pts.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`).join('');
  const area = `${line}L${W} ${H}L${start} ${H}Z`;
  const id = `spark${Math.random().toString(36).slice(2, 7)}`;
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
  svg.setAttribute('preserveAspectRatio', 'none');
  svg.setAttribute('class', 'ap-spark');
  svg.setAttribute('aria-hidden', 'true');
  svg.innerHTML = `<defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${tint}" stop-opacity=".32"/><stop offset="1" stop-color="${tint}" stop-opacity="0"/></linearGradient></defs>
    <path d="M0 ${H - 0.5}H${W}" stroke="rgba(255,255,255,.1)" stroke-dasharray="2 3" vector-effect="non-scaling-stroke"/>
    <path d="${area}" fill="url(#${id})"/><path d="${line}" fill="none" stroke="${tint}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>`;
  return svg;
}

// A small popup menu anchored to a control, like SwiftUI's Menu.
function popupMenu(host, anchor, items, close) {
  const hostRect = host.getBoundingClientRect();
  const r = anchor.getBoundingClientRect();
  const menu = h('div', { class: glass('ap-popup', true), role: 'menu', style: { top: `${r.bottom - hostRect.top + 4}px`, right: `${hostRect.right - r.right}px` } },
    items.map((item) => item === '-' ? h('div', { class: 'ap-popup-sep' }) : h('button', {
      type: 'button', role: 'menuitem', class: 'ap-popup-item', onclick: () => { close(); item.run(); }
    }, h('span', { class: 'ap-popup-check' }, item.checked ? sym('check', 12) : (item.sym ? sym(item.sym, 12) : null)), h('span', { text: item.title }))));
  host.append(menu);
  const away = (event) => { if (!menu.contains(event.target)) { close(); } };
  setTimeout(() => document.addEventListener('pointerdown', away, true));
  return () => { menu.remove(); document.removeEventListener('pointerdown', away, true); };
}

// MARK: Context shared by the panel and the plates

function createContext(bus, getLang) {
  const ctx = { bus, state: freshState(), memory: new Map(), ...makeCopy(getLang), getLang };
  ctx.lidState = () => (ctx.state.lidAwake ? (Date.now() - ctx.state.lidSince >= 60000 ? ctx.F('lidOnFor', ctx.duration((Date.now() - ctx.state.lidSince) / 1000)) : ctx.L('lidOn')) : ctx.L('lidOff'));
  ctx.out = () => ctx.state.outputs.find((d) => d.id === ctx.state.output);
  ctx.inp = () => ctx.state.inputs.find((d) => d.id === ctx.state.input);
  return ctx;
}

// MARK: Energy

function lidCard(ctx, refresh) {
  const s = ctx.state;
  const glyph = h('span', { class: `ap-lid-glyph${s.lidAwake ? ' awake' : ''}` }, sym('laptop', 27),
    h('span', { class: 'ap-lid-badge' }, sym(s.lidAwake ? 'boltFill' : 'moonFill', 10)));
  return card([
    h('div', { class: 'ap-row', style: { gap: '14px' } }, glyph,
      h('div', { class: 'ap-grow ap-stack', style: { gap: '3px' } },
        h('span', { class: 'ap-lid-title', text: ctx.L('lidTitle') }),
        h('span', { class: 'ap-lid-state', style: { color: s.lidAwake ? C.accent : C.secondary }, text: ctx.lidState() })),
      glassSwitch(s.lidAwake, ctx.L('lidTitle'), (on) => { s.lidAwake = on; if (on) s.lidSince = Date.now(); refresh(); })),
    h('p', { class: 'ap-lid-explain', text: ctx.L(s.lidAwake ? 'lidExplainOn' : 'lidExplainOff') })
  ], { padding: 18, cls: 'ap-stack gap14' });
}

function valueRow(name, tint, title, value) {
  return h('div', { class: 'ap-row ap-value-row' }, rowIcon(name, tint), h('span', { class: 'ap-row-title', text: title }), h('span', { class: 'ap-spacer' }),
    h('span', { class: 'ap-row-value', text: value }));
}

function toggleRow(name, tint, title, detail, isOn, onToggle) {
  return h('div', { class: 'ap-row ap-value-row' }, rowIcon(name, tint),
    h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-row-title', text: title }), detail ? h('span', { class: 'ap-row-detail', text: detail }) : null),
    glassSwitch(isOn, title, onToggle));
}

function powerFacts(ctx, refresh, onDisplayOff) {
  const s = ctx.state;
  const b = s.battery;
  const summary = b.charging ? `${ctx.percent(b.percent)} · ${ctx.F('timeToFull', ctx.duration(b.toFull * 60))}` : ctx.percent(b.percent);
  return card([
    valueRow(b.charging ? 'batteryBolt' : 'battery', C.positive, ctx.L(b.charging ? 'srcCharging' : 'srcBattery'), summary),
    hairline(42),
    valueRow('moon', C.ink, ctx.L('rowIdleSleep'), ctx.L('sleepNever')),
    hairline(42),
    valueRow('cup', C.warning, ctx.L('rowHeldBy'), 'sharingd'),
    hairline(42),
    toggleRow('sun', C.accent, ctx.L('idleTitle'), ctx.L('idleDetail'), s.idleHeld, (on) => { s.idleHeld = on; }),
    hairline(42),
    h('button', { class: 'ap-row ap-value-row ap-plain', type: 'button', onclick: onDisplayOff }, rowIcon('moonZzz', C.ink),
      h('span', { class: 'ap-row-title', text: ctx.L('menuDisplayOff') }), h('span', { class: 'ap-spacer' }), h('span', { class: 'ap-chev' }, sym('chevronRight', 12)))
  ], { padding: 14 });
}

// MARK: Sound

function deviceHeader(ctx, caption, device, expanded, toggle) {
  return h('button', { class: 'ap-row ap-plain ap-device-head', type: 'button', onclick: toggle, 'aria-expanded': String(expanded) },
    rowIcon(device.sym, C.accent, 34),
    h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-caption', text: caption }), h('span', { class: 'ap-device-name', text: ctx.name(device) })),
    h('span', { class: `${glass('ap-chevron')}${expanded ? ' open' : ''}` }, sym('chevronDown', 12)));
}

function deviceList(ctx, devices, selected, choose) {
  return h('div', { class: 'ap-device-list' }, devices.map((d) => h('button', {
    type: 'button', class: `ap-device-row${d.id === selected ? ' on' : ''}`, onclick: () => choose(d.id)
  }, h('span', { class: 'ap-device-sym' }, sym(d.sym, 14)), h('span', { class: 'ap-grow ap-ellipsis', text: ctx.name(d) }), d.id === selected ? sym('check', 12, 'ap-accent') : null)));
}

function outputCard(ctx, refresh, setSub) {
  const s = ctx.state;
  const device = ctx.out();
  const readout = h('span', { class: 'ap-readout-num' });
  const paintReadout = () => {
    readout.textContent = ctx.decimal(device.volume * 100, 1);
    readout.classList.toggle('muted', device.muted);
  };
  paintReadout();
  const slider = fineSlider({ value: device.volume, label: ctx.L('output'), onChange: (v) => { device.volume = v; paintReadout(); setSub(); } });
  const nudge = (delta) => { device.volume = Math.min(1, Math.max(0, Math.round((device.volume + delta) * 1000) / 1000)); slider.update(device.volume); paintReadout(); setSub(); };
  const step = (label, delta) => h('button', { type: 'button', onclick: () => nudge(delta) }, label);
  const tenth = ctx.decimal(0.1, 1);
  return card([
    deviceHeader(ctx, ctx.L('output'), device, s.outputsOpen, () => { s.outputsOpen = !s.outputsOpen; refresh(); }),
    s.outputsOpen ? deviceList(ctx, s.outputs, s.output, (id) => { s.output = id; s.outputsOpen = false; refresh(); ctx.bus.emit('peek', 'output', ctx.name(ctx.out())); }) : null,
    h('div', { class: 'ap-row ap-readout' }, readout, h('span', { class: 'ap-readout-unit', text: '%' }), h('span', { class: 'ap-spacer' }),
      glassIconButton(device.muted ? 'speakerSlash' : 'speakerFill', { size: 38, selected: device.muted, help: ctx.L(device.muted ? 'unmute' : 'mute'), onClick: () => { device.muted = !device.muted; refresh(); } })),
    slider,
    h('div', { class: 'ap-stack', style: { gap: '8px' } },
      h('div', { class: glass('ap-steps') }, step('−1', -0.01), h('i'), step(`−${tenth}`, -0.001), h('i'), step(`+${tenth}`, 0.001), h('i'), step('+1', 0.01)),
      footnote(ctx.L('fineHint')))
  ], { padding: 18, cls: 'ap-stack gap14' });
}

function mixerRow(ctx, app, host, refresh) {
  const s = ctx.state;
  const value = h('span', { class: 'ap-mix-value' });
  const paint = () => {
    value.textContent = app.muted ? ctx.L('mix_off') : ctx.percent(app.volume * 100);
    value.style.color = app.volume > 1.005 ? C.warning : app.muted ? C.tertiary : C.secondary;
  };
  paint();
  const routed = s.outputs.find((d) => d.id === app.output);
  const routeLabel = h('button', { type: 'button', class: `ap-route${routed ? ' set' : ''}` },
    sym(routed ? routed.sym : 'speaker', 10), h('span', { text: routed ? ctx.name(routed) : ctx.L('mix_systemOutput') }), sym('chevronDown', 8));
  let closeMenu = null;
  routeLabel.addEventListener('click', () => {
    if (closeMenu) { closeMenu(); closeMenu = null; return; }
    closeMenu = popupMenu(host, routeLabel, [
      { title: ctx.L('mix_systemOutput'), checked: !app.output, sym: 'speaker', run: () => { app.output = null; refresh(); } }, '-',
      ...s.outputs.map((d) => ({ title: ctx.name(d), checked: app.output === d.id, sym: d.sym, run: () => { app.output = d.id; refresh(); } }))
    ], () => { closeMenu?.(); closeMenu = null; });
  });
  const meter = h('span', { class: 'ap-meter' });
  meter.dataset.app = app.id;
  const tint = (v) => (v > 1.005 ? C.warning : C.accent);
  const slider = fineSlider({ value: app.volume, min: 0, max: 2, detent: 1, tint, label: ctx.name(app), onChange: (v) => { app.volume = v; paint(); } });
  return h('div', { class: 'ap-mix-row' },
    h('div', { class: 'ap-row', style: { gap: '10px' } },
      h('span', { class: 'ap-mix-icon' }, appTile(app.tile, 28), h('i', { class: 'ap-live' })),
      h('div', { class: 'ap-grow ap-stack', style: { gap: '1px' } }, h('span', { class: 'ap-mix-name', text: ctx.name(app) }), routeLabel),
      value,
      h('button', { type: 'button', class: `ap-mix-mute${app.muted ? ' on' : ''}`, title: ctx.L(app.muted ? 'mix_unmute' : 'mix_mute'), 'aria-label': ctx.L(app.muted ? 'mix_unmute' : 'mix_mute'), onclick: () => { app.muted = !app.muted; refresh(); } },
        sym(app.muted ? 'speakerSlash' : 'speakerFill', 12))),
    h('div', { class: 'ap-mix-slider' }, meter, slider));
}

function mixerCard(ctx, host, refresh) {
  const s = ctx.state;
  return card([
    h('div', { class: 'ap-row', style: { gap: '10px' } },
      h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-mix-title', text: ctx.L('mix_title') }), h('span', { class: 'ap-row-detail', text: ctx.L('mix_subtitle') })),
      glassSwitch(s.mixerOn, ctx.L('mix_title'), (on) => { s.mixerOn = on; refresh(); })),
    s.mixerOn
      ? h('div', { class: 'ap-stack', style: { gap: '6px' } }, s.apps.map((app) => mixerRow(ctx, app, host, refresh)))
      : h('div', { class: 'ap-row', style: { gap: '14px', alignItems: 'flex-start' } }, s.apps.map((app) => h('div', { class: 'ap-playing' }, appTile(app.tile, 34), h('span', { text: ctx.name(app) }))))
  ], { cls: 'ap-stack gap12' });
}

function inputCard(ctx, refresh) {
  const s = ctx.state;
  const device = ctx.inp();
  const value = h('span', { class: 'ap-input-value', text: ctx.percent(device.volume * 100) });
  return card([
    deviceHeader(ctx, ctx.L('input'), device, s.inputsOpen, () => { s.inputsOpen = !s.inputsOpen; refresh(); }),
    s.inputsOpen ? deviceList(ctx, s.inputs, s.input, (id) => { s.input = id; s.inputsOpen = false; refresh(); }) : null,
    h('div', { class: 'ap-row', style: { gap: '12px' } },
      h('div', { class: 'ap-grow' }, fineSlider({ value: device.volume, tint: C.positive, label: ctx.L('input'), onChange: (v) => { device.volume = v; value.textContent = ctx.percent(v * 100); } })),
      value,
      glassIconButton(device.muted ? 'micSlash' : 'micFill', { size: 32, selected: device.muted, help: ctx.L(device.muted ? 'unmute' : 'mute'), onClick: () => { device.muted = !device.muted; refresh(); } }))
  ], { padding: 18, cls: 'ap-stack gap12' });
}

function soundTricks(ctx, host, refresh) {
  const s = ctx.state;
  const trick = (name, title, keys, active, tint, onClick) => h('button', {
    type: 'button', class: `ap-trick${active ? ' active' : ''}`, style: { '--tint': tint }, onclick: onClick
  }, h('span', { class: 'ap-row' }, h('span', { class: 'ap-trick-sym', style: { color: active ? C.onLight : tint } }, sym(name, 16)), h('span', { class: 'ap-spacer' }), keyCaps(keys, 18, 5)),
  h('span', { class: 'ap-trick-title', text: title }));
  const guardDetail = h('span', { class: 'ap-trick-detail', text: ctx.F('mix_guardDetail', ctx.integer(s.guardLevel * 100)) });
  const pinned = s.inputs.find((d) => d.id === s.pinnedInput);
  const pinLabel = h('button', { type: 'button', class: `ap-pin-label${pinned ? ' set' : ''}`, text: pinned ? ctx.name(pinned) : ctx.L('mix_pinNone') });
  let closeMenu = null;
  pinLabel.addEventListener('click', () => {
    if (closeMenu) { closeMenu(); closeMenu = null; return; }
    closeMenu = popupMenu(host, pinLabel, [{ title: ctx.L('mix_pinNone'), checked: !s.pinnedInput, run: () => { s.pinnedInput = ''; refresh(); } }, '-',
      ...s.inputs.map((d) => ({ title: ctx.name(d), checked: s.pinnedInput === d.id, run: () => { s.pinnedInput = d.id; s.input = d.id; refresh(); } }))], () => { closeMenu?.(); closeMenu = null; });
  });
  return card([
    h('div', { class: 'ap-row', style: { gap: '8px' } },
      trick(s.micsMuted ? 'micSlash' : 'micFill', ctx.L(s.micsMuted ? 'mix_micsOff' : 'mix_muteMics'), ['⌃', '⌥', 'M'], s.micsMuted, C.danger, () => {
        s.micsMuted = !s.micsMuted; refresh(); ctx.bus.emit('peek', s.micsMuted ? 'mics' : 'micsOn');
      }),
      trick('swap', ctx.L('mix_nextOutput'), ['⌃', '⌥', 'O'], false, C.accent, () => {
        const i = s.outputs.findIndex((d) => d.id === s.output);
        s.output = s.outputs[(i + 1) % s.outputs.length].id; refresh(); ctx.bus.emit('peek', 'output', ctx.name(ctx.out()));
      })),
    hairline(),
    h('div', { class: 'ap-row', style: { gap: '10px' } },
      h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-trick-head', text: ctx.L('mix_guardTitle') }), guardDetail),
      glassSwitch(s.guard, ctx.L('mix_guardTitle'), (on) => { s.guard = on; refresh(); })),
    s.guard ? fineSlider({ value: s.guardLevel, label: ctx.L('mix_guardTitle'), onChange: (v) => { s.guardLevel = Math.round(v * 100) / 100; guardDetail.textContent = ctx.F('mix_guardDetail', ctx.integer(s.guardLevel * 100)); } }) : null,
    hairline(),
    h('div', { class: 'ap-row', style: { gap: '10px' } },
      h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-trick-head', text: ctx.L('mix_pinTitle') }), h('span', { class: 'ap-trick-detail', text: ctx.L('mix_pinDetail') })),
      pinLabel)
  ], { cls: 'ap-stack gap10' });
}

// MARK: System

function metricTile(name, tint, title, value, footer) {
  return card([
    h('div', { class: 'ap-row', style: { gap: '6px' } }, h('span', { style: { color: tint, display: 'grid' } }, sym(name, 13)), h('span', { class: 'ap-tile-title', text: title })),
    h('span', { class: 'ap-tile-value', text: value }),
    h('span', { class: 'ap-spacer-v' }),
    footer
  ], { padding: 14, radius: 18, cls: 'ap-tile' });
}

function systemPane(ctx, refresh) {
  const s = ctx.state;
  const b = s.battery;
  const loadTint = s.cpu >= 85 ? C.danger : s.cpu >= 60 ? C.warning : C.accent;
  const detail = (text, tint = C.secondary) => h('span', { class: 'ap-tile-detail', style: { color: tint }, text });
  const top = Math.max(s.busiest[0][2], 1);
  return [
    h('div', { class: 'ap-grid2' },
      metricTile('cpu', loadTint, ctx.L('processor'), ctx.percent(s.cpu), sparkline(s.cpuHistory, loadTint)),
      metricTile('memory', s.memory >= 80 ? C.warning : C.positive, ctx.L('memory'), ctx.percent(s.memory), [
        detail(ctx.F('memoryOf', ctx.gigabytes(24 * s.memory / 100), ctx.gigabytes(24))),
        detail(ctx.L(s.memory >= 80 ? 'pressureWarning' : 'pressureNormal'), s.memory >= 80 ? C.warning : C.positive)]),
      metricTile(b.charging ? 'boltFill' : 'battery', C.positive, ctx.L('battery'), ctx.percent(b.percent), [
        detail(ctx.F('timeToFull', ctx.duration(b.toFull * 60))), detail(ctx.F('healthLine', ctx.percent(b.health), ctx.integer(b.cycles)))]),
      metricTile('thermometer', s.temp >= 80 ? C.warning : C.positive, ctx.L('temperature'), ctx.celsius(s.temp), [detail(ctx.L('chipSensor')), detail(ctx.L('fansIdle'))])),
    card([cardTitle(ctx.L('busiestApps')), ...s.busiest.map(([name, tile, cpu]) => h('div', { class: 'ap-row', style: { gap: '12px' } },
      tile ? appTile(tile, 26) : rowIcon('gear', C.ink, 26),
      h('div', { class: 'ap-grow ap-stack', style: { gap: '5px' } },
        h('div', { class: 'ap-row' }, h('span', { class: 'ap-busy-name ap-ellipsis', text: name }), h('span', { class: 'ap-spacer' }), h('span', { class: 'ap-busy-pct', text: ctx.percent(cpu) })),
        levelBar(cpu / top, C.accent, 4))))], { cls: 'ap-stack gap10' }),
    fansCard(ctx, refresh)
  ];
}

// FansCard with the helper installed: two fans, the four cooling modes and their settings, as on an M4 Pro.
function fansCard(ctx, refresh) {
  const s = ctx.state;
  const [low, high] = [2317, 7826];
  const hot = s.temp >= s.fanStart;
  const target = s.fanMode === 'max' ? high : s.fanMode === 'manual' ? Math.round(low + (high - low) * s.fanLevel)
    : s.fanMode === 'smart' && hot ? Math.round(low + (high - low) * Math.min(Math.max((s.temp - s.fanStart) / Math.max(s.fanFull - s.fanStart, 1), 0), 1)) : null;
  const state = target ? ctx.P('fanHolding', ctx.integer(target)) : s.fanMode === 'smart' ? ctx.P('fanWaiting', ctx.celsius(s.fanStart)) : ctx.P('fanAutomatic');
  const fan = (index, rpm) => h('div', { class: 'ap-stack', style: { gap: '7px' } },
    h('div', { class: 'ap-row', style: { gap: '6px' } }, h('span', { class: `ap-accent ap-fan-glyph${rpm ? ' spin' : ''}`, style: { display: 'grid' } }, sym('fan', 13)),
      h('span', { class: 'ap-fan-name', text: ctx.F('fanName', ctx.integer(index)) }), h('span', { class: 'ap-spacer' }),
      h('span', { class: 'ap-fan-speed', text: rpm ? ctx.F('fanSpeed', ctx.integer(rpm)) : ctx.L('fanStopped') })),
    levelBar(rpm / high, C.accent, 4), h('span', { class: 'ap-tile-detail', style: { color: C.tertiary }, text: ctx.F('fanRange', ctx.integer(low), ctx.integer(high)) }));
  const slider = (title, key, min, max, label, settle) => {
    const value = h('span', { class: 'ap-threshold-value', text: label(s[key]) });
    return h('div', { class: 'ap-stack', style: { gap: '6px' } },
      h('div', { class: 'ap-row' }, h('span', { class: 'ap-threshold-title', text: title }), h('span', { class: 'ap-spacer' }), value),
      fineSlider({ value: s[key], min, max, label: title, onChange: (v) => { s[key] = max > 1 ? Math.round(v) : v; value.textContent = label(s[key]); }, onEnd: () => { settle?.(); refresh(); } }));
  };
  const modes = [['auto', ctx.P('modeAuto')], ['smart', ctx.P('modeSmart')], ['max', ctx.P('modeMax')], ['manual', ctx.P('modeManual')]];
  return card([
    cardTitle(ctx.P('fanTitle'), h('span', { class: 'ap-fan-state', style: { color: target ? C.accent : C.secondary }, text: state })),
    fan(1, target ? target - 6 : 0), fan(2, target ?? 0),
    hairline(),
    segmented('fan-mode', modes, s.fanMode, (v) => { s.fanMode = v; refresh(); }, ctx.memory),
    ...(s.fanMode === 'smart' ? [
      slider(ctx.P('fanRise'), 'fanStart', 45, 85, ctx.celsius, () => { if (s.fanFull < s.fanStart + 5) s.fanFull = Math.min(s.fanStart + 5, 100); }),
      slider(ctx.P('fanTop'), 'fanFull', 55, 100, ctx.celsius, () => { if (s.fanStart > s.fanFull - 5) s.fanStart = Math.max(s.fanFull - 5, 45); })
    ] : []),
    ...(s.fanMode === 'manual' ? [slider(ctx.P('fanSpeedTitle'), 'fanLevel', 0, 1, (v) => ctx.F('fanSpeed', ctx.integer(Math.round(low + (high - low) * v))))] : []),
    footnote(ctx.P('fanCoolNote'))
  ], { cls: 'ap-stack gap12' });
}

// MARK: Work

function workPane(ctx, refresh) {
  const s = ctx.state;
  const week = s.range === 'week';
  const rows = USAGE.map(([tile, name, category, seconds, latin, other, factor]) => {
    const k = week ? factor : 1;
    const lat = Math.round(latin * k);
    const oth = Math.round(other * k);
    return { tile, name, category, seconds: seconds * k, chars: lat + oth, ai: AI_USAGE[tile] && scaleAI(AI_USAGE[tile], week ? 5.4 : 1) };
  }).sort((a, b) => b.seconds - a.seconds);
  const sum = (list, key) => list.reduce((t, r) => t + r[key], 0);
  const editors = rows.filter((r) => r.category === 'editor');
  const assistants = rows.filter((r) => r.category === 'assistant');
  const others = rows.filter((r) => r.category === 'other');
  const typed = rows.filter((r) => r.category !== 'other');
  const stat = (title, value) => h('div', { class: 'ap-stat' }, h('span', { class: 'ap-stat-value', text: value }), h('span', { class: 'ap-stat-title', text: title }));
  const group = (title, list, tint, typing) => card([
    cardTitle(title, h('span', { class: 'ap-group-total', text: ctx.duration(sum(list, 'seconds')) })),
    ...list.map((r) => h('div', { class: 'ap-row', style: { gap: '12px' } },
      r.tile === 'xcode' ? rowIcon('appDashed', C.ink, 30) : appTile(r.tile, 30),
      h('div', { class: 'ap-grow ap-stack', style: { gap: '5px' } },
        h('div', { class: 'ap-row' }, h('span', { class: 'ap-usage-name ap-ellipsis', text: r.name }), h('span', { class: 'ap-spacer' }), h('span', { class: 'ap-usage-time', text: ctx.duration(r.seconds) })),
        levelBar(r.seconds / list[0].seconds, tint, 4),
        typing && r.chars > 0 ? h('span', { class: 'ap-tile-detail', text: ctx.P('typedChars', ctx.integer(r.chars)) }) : null,
        r.ai ? h('span', { class: 'ap-ai-line' }, h('span', { class: 'ap-ai-model' }, sym('sparkles', 10), h('span', { text: r.ai.model })),
          r.ai.tokens ? h('span', { class: 'ap-tile-detail', text: ctx.P('tokens', ctx.compact(r.ai.tokens)) }) : null, codeLine(ctx, r.ai)) : null)))
  ], { cls: 'ap-stack gap12' });
  return [
    segmented('work-range', [['today', ctx.L('today')], ['week', ctx.L('sevenDays')]], s.range, (v) => { s.range = v; refresh(); }, ctx.memory),
    card([
      h('div', { class: 'ap-row' },
        h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-work-big', text: ctx.duration(sum(editors, 'seconds')) }), h('span', { class: 'ap-caption12', text: ctx.L('inEditors') })),
        h('span', { class: 'ap-stackicons' }, editors.slice(0, 3).map((r) => (r.tile === 'xcode' ? rowIcon('code', C.ink, 34) : appTile(r.tile, 34))))),
      h('div', { class: 'ap-row ap-stats' }, stat(ctx.L('typed'), ctx.integer(sum(typed, 'chars'))), h('i'),
        stat(ctx.P('aiTokens'), ctx.compact(rows.reduce((t, r) => t + (r.ai?.tokens ?? 0), 0))), h('i'),
        stat(ctx.P('code'), `+${ctx.compact(rows.reduce((t, r) => t + (r.ai?.added ?? 0), 0))}`), h('i'),
        stat(ctx.L('aiApps'), ctx.duration(sum(assistants, 'seconds'))))
    ], { padding: 18, cls: 'ap-stack gap16' }),
    group(ctx.L('groupEditors'), editors, C.accent, true),
    group(ctx.L('groupAssistants'), assistants, C.positive, true),
    group(ctx.L('groupOther'), others, C.inkSoft, false),
    h('div', { style: { padding: '0 4px' } }, footnote(ctx.P('workNote')))
  ];
}

// What the AI did in each editor today (Claude Code in VS Code, Cursor's own tracking).
const AI_USAGE = {
  vscode: { model: 'Opus 5.5', tokens: 2310000, added: 1078, removed: 16, created: 4, edited: 2 },
  cursor: { model: 'Auto', tokens: 0, added: 412, removed: 0, created: 3, edited: 5 }
};
const scaleAI = (ai, k) => ({ ...ai, tokens: Math.round(ai.tokens * k), added: Math.round(ai.added * k), removed: Math.round(ai.removed * k), created: Math.round(ai.created * k), edited: Math.round(ai.edited * k) });

// CodeLine: +added −removed, new files, edited files.
function codeLine(ctx, ai) {
  return h('span', { class: 'ap-code-line' },
    h('span', { class: 'plus', text: `+${ctx.compact(ai.added)}` }), h('span', { class: 'minus', text: `−${ctx.compact(ai.removed)}` }),
    ai.created ? h('span', { class: 'new' }, sym('page', 10), h('span', { text: ctx.integer(ai.created) })) : null,
    ai.edited ? h('span', { class: 'edit' }, sym('pencil', 10), h('span', { text: ctx.integer(ai.edited) })) : null);
}

// MARK: Tools

function toolsPane(ctx, refresh, actions) {
  const s = ctx.state;
  const capture = (name, title, onClick, tint = C.ink, active = false) => h('button', { type: 'button', class: 'ap-capture', onclick: onClick },
    h('span', { class: `${glass('ap-capture-circle')}${active ? ' active' : ''}`, style: { color: active ? C.onLight : tint } }, sym(name, 20)),
    h('span', { class: 'ap-capture-title', text: title }));
  const shoot = () => {
    const now = new Date();
    const stamp = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')} at ${String(now.getHours()).padStart(2, '0')}.${String(now.getMinutes()).padStart(2, '0')}.${String(now.getSeconds()).padStart(2, '0')}`;
    s.lastCapture = `Screenshot ${stamp}`;
    refresh();
    actions.toast(ctx.L('capSaved'), 'check', C.positive);
  };
  const utilities = [
    ['ecg', 'uActivity', () => actions.setTab('system')], ['terminal', 'uTerminal', () => actions.openTerminal()],
    ['gear', 'uSettings', () => actions.setTab('settings')], ['drive', 'uDisk', () => actions.toast(ctx.L('uDisk'), 'drive')],
    ['moonZzz', 'uDisplayOff', () => actions.displayOff()], ['network', 'uCopyIP', () => { ctx.bus.emit('copy', { kind: 'text', text: '192.168.1.24' }); actions.toast(ctx.F('ipCopied', '192.168.1.24'), 'check', C.positive); }],
    ['eye', 'uHidden', () => { s.hiddenFiles = !s.hiddenFiles; refresh(); actions.toast(ctx.L(s.hiddenFiles ? 'hiddenShown' : 'hiddenHidden'), 'eye'); }]
  ];
  const threshold = (title, key, min, max, label) => {
    const value = h('span', { class: 'ap-threshold-value', text: label(s[key]) });
    return h('div', { class: 'ap-stack', style: { gap: '6px' } },
      h('div', { class: 'ap-row' }, h('span', { class: 'ap-threshold-title', text: title }), h('span', { class: 'ap-spacer' }), value),
      fineSlider({ value: s[key], min, max, label: title, onChange: (v) => { s[key] = Math.round(v); value.textContent = label(s[key]); } }));
  };
  return [
    h('button', { type: 'button', class: 'ap-card ap-entry', style: { padding: '16px', borderRadius: '20px' }, onclick: () => actions.setTab('automations') },
      rowIcon('flow', C.accent),
      h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-card-head', text: ctx.P('autoTitle') }),
        h('span', { class: 'ap-row-detail', text: autoSubtitle(ctx) })),
      h('span', { class: 'ap-chev' }, sym('chevronRight', 12))),
    card([
      cardTitle(ctx.L('capture')),
      h('div', { class: 'ap-row ap-captures' },
        capture('dashedRect', ctx.L('capSelection'), shoot), capture('window', ctx.L('capWindow'), shoot), capture('display', ctx.L('capScreen'), shoot),
        capture(s.recording ? 'stop' : 'record', ctx.L(s.recording ? 'capStop' : 'capRecord'), () => actions.toggleRecording(), C.danger, s.recording),
        capture('viewfinder', ctx.L('capToolbar'), shoot)),
      s.lastCapture ? h('div', { class: 'ap-last' },
        h('span', { class: 'ap-last-thumb' }),
        h('div', { class: 'ap-grow ap-stack', style: { gap: '2px', minWidth: 0 } }, h('span', { class: 'ap-caption', text: ctx.L('lastCapture') }), h('span', { class: 'ap-last-name ap-ellipsis', text: s.lastCapture })),
        glassIconButton('copy', { size: 30, help: ctx.L('copyAgain'), onClick: () => actions.toast(ctx.L('copied'), 'check', C.positive) }),
        glassIconButton('folder', { size: 30, help: ctx.L('revealInFinder'), onClick: () => actions.toast(ctx.L('revealInFinder'), 'folder') })) : null
    ], { cls: 'ap-stack gap14' }),
    card([
      h('div', { class: 'ap-row', style: { gap: '12px' } }, rowIcon('menubar', C.accent),
        h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-card-head', text: ctx.L('browserTitle') }),
          h('span', { class: 'ap-row-detail', style: { color: C.positive }, text: ctx.F('browserConnected', 'Google Chrome') })),
        h('i', { class: 'ap-live-dot' })),
      h('div', { class: 'ap-row ap-end', style: { gap: '8px' } },
        pillButton(ctx.L('browserReveal'), { symbol: 'folder', onClick: () => actions.toast(ctx.L('browserReveal'), 'folder') }),
        pillButton(ctx.L('browserOpen'), { symbol: 'puzzle', onClick: () => actions.openBrowser() }))
    ], { cls: 'ap-stack gap12' }),
    card([
      h('div', { class: 'ap-row', style: { gap: '12px' } }, rowIcon('bell', C.accent),
        h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-card-head', text: ctx.L('alertsTitle') }), h('span', { class: 'ap-row-detail', text: ctx.L('alertsBody') })),
        glassSwitch(s.alerts, ctx.L('alertsTitle'), (on) => { s.alerts = on; refresh(); })),
      ...(s.alerts ? [
        hairline(),
        threshold(ctx.L('alertCPU'), 'cpuLimit', 50, 100, ctx.percent), threshold(ctx.L('alertMemory'), 'memoryLimit', 60, 98, ctx.percent),
        threshold(ctx.L('alertBattery'), 'batteryLimit', 5, 50, ctx.percent), threshold(ctx.L('alertHeat'), 'heatLimit', 60, 105, ctx.celsius),
        hairline(),
        toggleRow('flag', C.positive, ctx.L('alertDone'), ctx.L('alertDoneDetail'), s.workDone, (on) => { s.workDone = on; }),
        h('div', { class: 'ap-row ap-end' }, pillButton(ctx.L('sendTest'), { symbol: 'paperplane', onClick: () => actions.toast(ctx.L('nTest'), 'bell', C.accent) }))
      ] : [])
    ], { cls: 'ap-stack gap12' }),
    card([
      cardTitle(ctx.L('utilities'), h('span', { class: 'ap-row', style: { gap: '8px' } },
        h('span', { class: glass('ap-count'), text: ctx.integer(utilities.length) }),
        glassIconButton('plus', { size: 26, help: ctx.L('addUtility'), onClick: () => actions.toast(ctx.L('utilitiesEmpty'), 'plus') }))),
      h('div', { class: 'ap-util-grid' }, utilities.map(([name, key, run]) => h('button', { type: 'button', class: 'ap-util', onclick: run },
        h('span', { class: glass('ap-util-circle'), style: { color: key === 'uHidden' && s.hiddenFiles ? C.accent : C.ink } }, sym(name, 19)),
        h('span', { class: 'ap-util-title', text: ctx.L(key) })))),
      footnote(ctx.L('utilitiesEmpty'))
    ], { cls: 'ap-stack gap14' })
  ];
}

// MARK: Features

const FEATURE_SYMBOLS = {
  'capsule.inset.filled': 'capsule', 'speaker.wave.3.fill': 'speakerFill', 'macwindow.on.rectangle': 'window',
  'doc.on.clipboard.fill': 'clipboard', command: 'command', sparkles: 'sparkles'
};

// A switch that sits in two groups counts once, and runs if either place runs it. Mirrors FeatureTally.
function featureTally(f) {
  const running = new Map();
  for (const g of FEATURE_GROUPS) {
    const mainOn = f[g.main.key];
    running.set(g.main.key, running.get(g.main.key) || mainOn);
    for (const o of g.options) running.set(o.key, running.get(o.key) || (mainOn && f[o.key]));
  }
  return { on: [...running.values()].filter(Boolean).length, total: running.size };
}

// Options only count while the main switch is on: that is what is actually running.
function groupTally(g, f) {
  const mainOn = f[g.main.key];
  return { on: mainOn ? 1 + g.options.filter((o) => f[o.key]).length : 0, total: 1 + g.options.length };
}

// KeyCaps: square caps, wider ones for words like Tab and Space.
function featureKeys(keys, size = 18) {
  return h('span', { class: 'ap-keys ap-fkeys' }, keys.map((key) => h('span', {
    class: 'ap-fkey', text: key,
    style: { minWidth: `${size}px`, height: `${size}px`, padding: key.length > 1 ? '0 6px' : '0', borderRadius: `${size * 0.3}px`, fontSize: `${size * 0.5}px` }
  })));
}

function featuresPane(ctx, refresh) {
  const s = ctx.state;
  const f = s.features;
  const P = (phrase, ...args) => { let i = 0; return (phrase[ctx.getLang()] ?? phrase.en).replace(/%@|%d/g, () => String(args[i++] ?? '')); };
  const tally = featureTally(f);
  const ring = h('span', { class: 'ap-fring' });
  ring.innerHTML = `<svg viewBox="0 0 50 50" aria-hidden="true"><circle cx="25" cy="25" r="22.5" class="track"/><circle cx="25" cy="25" r="22.5" class="fill" pathLength="1" style="stroke-dasharray:${tally.total ? tally.on / tally.total : 0} 1"/></svg>`;
  ring.append(h('span', { class: 'ap-fring-num', text: ctx.integer(tally.on) }));
  const overview = card([
    h('div', { class: 'ap-row', style: { gap: '14px' } }, ring,
      h('div', { class: 'ap-grow ap-stack', style: { gap: '3px' } },
        h('span', { class: 'ap-ftotal', text: ctx.F('featuresSubtitle', ctx.integer(tally.on), ctx.integer(tally.total)) }),
        h('span', { class: 'ap-flead', text: P(FEATURE_PHRASES.overview) })))
  ], { padding: 18 });

  const list = h('div', { class: 'ap-stack', style: { gap: '12px' } });
  const toggleOpen = (id) => { if (s.featuresOpen.has(id)) s.featuresOpen.delete(id); else s.featuresOpen.add(id); refresh(); };

  const optionRow = (item, enabled) => h('div', { class: `ap-row ap-fopt${enabled ? '' : ' off'}`, style: { gap: '10px' } },
    h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } },
      h('span', { class: 'ap-fopt-title', text: P(item.title) }),
      item.detail ? h('span', { class: 'ap-fopt-detail', text: P(item.detail) }) : null),
    item.keys ? featureKeys(item.keys) : null,
    glassSwitch(f[item.key], P(item.title), (on) => { f[item.key] = on; refresh(); }));

  const groupCard = (g, items, expanded) => {
    const on = f[g.main.key];
    const t = groupTally(g, f);
    const head = h('div', { class: 'ap-row ap-fhead', style: { gap: '12px' } },
      rowIcon(FEATURE_SYMBOLS[g.symbol] ?? 'gear', on ? C.accent : C.secondary, 34),
      h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } },
        h('span', { class: 'ap-ftitle', text: P(g.title) }),
        h('span', { class: 'ap-fsub', text: on ? P(FEATURE_PHRASES.count, ctx.integer(t.on), ctx.integer(t.total)) : P(g.detail) })),
      g.main.keys ? h('span', { style: { opacity: on ? 1 : 0.5, display: 'inline-flex' } }, featureKeys(g.main.keys)) : null,
      glassSwitch(on, P(g.main.title), (next) => { f[g.main.key] = next; refresh(); }));
    head.addEventListener('click', (event) => { if (!event.target.closest('.ap-switch')) toggleOpen(g.id); });
    const rows = [];
    if (expanded) {
      if (P(g.main.title) !== P(g.title)) rows.push(optionRow(g.main, true));
      items.forEach((item) => rows.push(optionRow(item, on)));
    }
    return card([
      head,
      expanded ? h('div', { class: 'ap-fopts' }, rows.flatMap((row, i) => (i ? [hairline(), row] : [row]))) : null,
      h('button', { type: 'button', class: 'ap-fmore', 'aria-expanded': String(expanded), onclick: () => toggleOpen(g.id) },
        h('span', { text: expanded ? P(FEATURE_PHRASES.less) : P(FEATURE_PHRASES.options, ctx.integer(items.length)) }),
        sym(expanded ? 'chevronUp' : 'chevronDown', 9))
    ], { cls: 'ap-fcard' });
  };

  // Searching matches a group's title or any of its switches, and shows only the matches.
  const renderList = () => {
    const needle = s.featureQuery.trim().toLowerCase();
    const has = (phrase) => phrase && P(phrase).toLowerCase().includes(needle);
    const groups = FEATURE_GROUPS.map((g) => {
      if (!needle || has(g.title) || has(g.main.title)) return [g, g.options];
      const matches = g.options.filter((o) => has(o.title) || has(o.detail));
      return matches.length ? [g, matches] : null;
    }).filter(Boolean);
    clear(list).append(...(groups.length
      ? groups.map(([g, items]) => groupCard(g, items, Boolean(needle) || s.featuresOpen.has(g.id)))
      : [h('div', { style: { padding: '0 4px' } }, footnote(P(FEATURE_PHRASES.nothing)))]));
  };
  const field = h('label', { class: 'ap-fsearch' }, sym('search', 13),
    h('input', { type: 'search', placeholder: P(FEATURE_PHRASES.search), 'aria-label': P(FEATURE_PHRASES.search), value: s.featureQuery, autocomplete: 'off', spellcheck: 'false' }));
  field.querySelector('input').addEventListener('input', (event) => { s.featureQuery = event.target.value; renderList(); });
  renderList();
  return [overview, field, list];
}

// MARK: Automations

function autoSubtitle(ctx) {
  const list = ctx.state.automations;
  if (!list.length) return ctx.P('autoNone');
  const on = list.filter((a) => a.on).length;
  const last = list.find((a) => a.ran);
  return ctx.P('autoOf', ctx.integer(on), ctx.integer(list.length)) + (last ? ` · ${ctx.P(last.ran)}` : '');
}

// AutomationsPane: the list with switches, the templates and the latest runs. Editing happens in the app.
function automationsPane(ctx, refresh, actions) {
  const s = ctx.state;
  const summary = (index) => { const [, , when, steps] = AUTO_TEMPLATES[index]; return `${ctx.P(when)} → ${ctx.P('autoSteps', ctx.integer(steps))}`; };
  const list = s.automations.length ? card(s.automations.map((item, i) => {
    const [glyph, name] = AUTO_TEMPLATES[item.template];
    return [i ? hairline(44) : null, h('div', { class: 'ap-row ap-auto-row' }, rowIcon(glyph, item.on ? C.accent : C.secondary, 32),
      h('div', { class: 'ap-grow ap-stack', style: { gap: '2px', minWidth: 0 } },
        h('span', { class: 'ap-auto-name', text: ctx.P(name) }),
        h('span', { class: 'ap-row-detail', text: summary(item.template) })),
      glassSwitch(item.on, ctx.P(name), (on) => { item.on = on; refresh(); }))];
  }).flat(), { padding: 12 }) : null;
  return [
    card([
      h('div', { class: 'ap-row', style: { gap: '12px', alignItems: 'flex-start' } }, rowIcon('flow', C.accent, 34),
        h('div', { class: 'ap-grow ap-stack', style: { gap: '3px' } }, h('span', { class: 'ap-ftotal', text: ctx.P('autoLead') }),
          h('span', { class: 'ap-flead', text: ctx.P('autoLeadDetail') }))),
      h('div', { class: 'ap-row ap-end' }, pillButton(ctx.P('autoNew'), { symbol: 'plus', prominent: true, onClick: () => actions.toast(ctx.P('autoNewToast'), 'flow', C.accent) }))
    ], { cls: 'ap-stack gap12' }),
    list,
    card([cardTitle(ctx.P('autoTemplates')), ...AUTO_TEMPLATES.map(([glyph, name], index) => h('button', {
      type: 'button', class: 'ap-row ap-plain ap-template', onclick: () => { s.automations.unshift({ template: index, on: true, ran: null }); refresh(); actions.toast(ctx.P('autoAdded', ctx.P(name)), 'check', C.positive); }
    }, rowIcon(glyph, C.secondary, 30),
      h('div', { class: 'ap-grow ap-stack', style: { gap: '1px', minWidth: 0 } }, h('span', { class: 'ap-template-name', text: ctx.P(name) }),
        h('span', { class: 'ap-template-detail', text: summary(index) })),
      h('span', { class: 'ap-template-add' }, sym('plus', 11))))], { cls: 'ap-stack gap6' }),
    card([cardTitle(ctx.P('autoRecent')), ...s.autoLog.map(([template, detail, ran]) => h('div', { class: 'ap-row', style: { gap: '8px' } },
      h('span', { style: { color: C.positive, display: 'grid' } }, sym('check', 12)),
      h('div', { class: 'ap-grow ap-stack', style: { gap: '1px' } }, h('span', { class: 'ap-template-name', text: ctx.P(AUTO_TEMPLATES[template][1]) }),
        h('span', { class: 'ap-template-detail', text: detail })),
      h('span', { class: 'ap-template-detail', text: ctx.P(ran) })))], { cls: 'ap-stack gap10' })
  ];
}

// MARK: Settings

function settingsPane(ctx, refresh, actions) {
  const s = ctx.state;
  const permission = (name, title, use, granted) => h('div', { class: 'ap-row ap-perm-row' }, rowIcon(name, granted ? C.positive : C.accent),
    h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-row-title', text: title }), h('span', { class: 'ap-row-detail', text: use })),
    statusBadge(ctx.L(granted ? 'stAllowed' : 'stAskEachTime'), granted ? C.positive : C.accent));
  return [
    card([cardTitle(ctx.L('language')), segmented('language', Object.entries(NATIVE), ctx.getLang(), (code) => actions.setLanguage(code), ctx.memory)], { cls: 'ap-stack gap12' }),
    card([
      h('div', { style: { paddingBottom: '6px' } }, cardTitle(ctx.L('general'))),
      toggleRow('power', C.accent, ctx.L('openAtLogin'), null, s.openAtLogin, (on) => { s.openAtLogin = on; }), hairline(42),
      toggleRow('dock', C.ink, ctx.L('showInDock'), null, s.showInDock, (on) => { s.showInDock = on; }), hairline(42),
      toggleRow('pin', C.ink, ctx.L('keepOpen'), ctx.L('keepOpenDetail'), s.pinned, (on) => { s.pinned = on; }), hairline(42),
      h('div', { class: 'ap-row ap-value-row' }, rowIcon('command', C.ink),
        h('div', { class: 'ap-grow ap-stack', style: { gap: '2px' } }, h('span', { class: 'ap-row-title', text: ctx.L('shortcut') }), h('span', { class: 'ap-row-detail', text: ctx.L('shortcutDetail') })),
        keyCaps(['⌃', '⌥', 'S']))
    ]),
    card([
      h('div', { style: { paddingBottom: '6px' } }, cardTitle(ctx.L('permissions'))),
      permission('keyboard', ctx.L('permAccessibility'), ctx.L('permAccessibilityUse'), true), hairline(42),
      permission('screenRecord', ctx.L('permScreen'), ctx.L('permScreenUse'), true), hairline(42),
      permission('bell', ctx.L('permNotifications'), ctx.L('permNotificationsUse'), true), hairline(42),
      permission('lockShield', ctx.L('permAdmin'), ctx.L('permAdminUse'), false),
      h('div', { style: { paddingTop: '10px' } }, footnote(ctx.L('permissionsNote')))
    ]),
    h('div', { class: 'ap-row ap-about' }, mark(18, 'ap-about-mark'), h('span', { class: 'ap-about-name', text: `SAVISUL ${CONFIG.version}` }), h('span', { class: 'ap-spacer' }),
      pillButton(ctx.L('menuQuit'), { symbol: 'power', onClick: () => actions.quit() }))
  ];
}

// MARK: Panel

export function createPanel(bus) {
  let panelLang = siteLang;
  const ctx = createContext(bus, () => panelLang);
  const s = ctx.state;
  const memory = ctx.memory;

  const title = h('span', { class: 'ap-title' });
  const sub = h('span', { class: 'ap-sub' });
  const chips = h('div', { class: 'ap-chips' });
  const more = h('button', { class: glass('ap-icon-btn'), type: 'button', style: { width: '34px', height: '34px' } }, sym('ellipsis', 15));
  const content = h('div', { class: 'ap-content' });
  const scroll = h('div', { class: 'ap-scroll' }, content);
  const tabs = h('div', { class: glass('ap-tabs', true), role: 'tablist' });
  const gearButton = h('button', { class: glass('ap-gear', true), type: 'button' });
  const toast = h('div', { class: glass('ap-toast', true), role: 'status', 'aria-live': 'polite' });
  const menuLayer = h('div', { class: 'ap-menu-layer' });
  const root = h('div', { class: 'ap-panel' },
    h('div', { class: 'ap-head' }, h('div', { class: 'ap-head-text' }, h('div', { class: 'ap-title-row' }, mark(21, 'ap-mark'), title), sub), h('span', { class: 'ap-spacer' }), chips, more),
    scroll,
    h('div', { class: 'ap-bottom' }, toast, h('div', { class: 'ap-tabbar' }, tabs, gearButton)),
    menuLayer);

  let toastTimer;
  const showToast = (text, symbol = 'check', tint = C.ink) => {
    clear(toast).append(h('span', { style: { color: tint, display: 'grid' } }, sym(symbol, 13)), h('span', { text }));
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 2600);
  };

  const subtitle = () => {
    switch (s.tab) {
      case 'energy': return ctx.L(s.lidAwake ? 'energyOn' : 'energyOff');
      case 'sound': { const d = ctx.out(); return d.muted ? `${ctx.name(d)} · ${ctx.L('muted')}` : `${ctx.name(d)} · ${ctx.finePercent(d.volume * 100)}`; }
      case 'system': return ctx.F('systemSubtitle', ctx.percent(s.cpu), ctx.percent(s.memory));
      case 'work': {
        const k = s.range === 'week';
        const secs = USAGE.filter((u) => u[2] === 'editor').reduce((t, u) => t + u[3] * (k ? u[6] : 1), 0);
        return ctx.F(k ? 'workSubtitleWeek' : 'workSubtitleToday', ctx.duration(secs));
      }
      case 'tools': return ctx.L('toolsSubtitle');
      case 'features': { const t = featureTally(s.features); return ctx.F('featuresSubtitle', ctx.integer(t.on), ctx.integer(t.total)); }
      case 'automations': return autoSubtitle(ctx);
      default: return ctx.F('settingsSubtitle', CONFIG.version);
    }
  };
  const setSub = () => { sub.textContent = subtitle(); };

  const elapsed = () => { const t = Math.floor((Date.now() - s.recordStart) / 1000); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };
  function renderChips() {
    clear(chips);
    if (s.recording) chips.append(h('button', { class: glass('ap-chip ap-rec'), type: 'button', title: ctx.L('capStop'), onclick: () => actions.toggleRecording() }, h('i'), h('span', { class: 'ap-rec-time', text: elapsed() })));
    if (s.lidAwake && s.tab !== 'energy') chips.append(h('span', { class: glass('ap-chip ap-awake') }, sym('boltFill', 12), h('span', { text: ctx.L('chipAwake') })));
  }

  function renderTabs() {
    const index = TABS.findIndex(([id]) => id === s.tab);
    const from = memory.get('tab') ?? index;
    memory.set('tab', index);
    const pill = h('span', { class: 'ap-tab-pill', style: { '--i': from < 0 ? index : from, opacity: index < 0 ? 0 : 1 } });
    clear(tabs).append(pill, ...TABS.map(([id, outline, filled, key]) => h('button', {
      type: 'button', role: 'tab', class: `ap-tab${id === s.tab ? ' on' : ''}`, 'aria-selected': String(id === s.tab), title: ctx.L(key), 'aria-label': ctx.L(key),
      onclick: () => setTab(id)
    }, sym(id === s.tab ? filled : outline, 17))));
    if (index >= 0 && from !== index && from >= 0) requestAnimationFrame(() => requestAnimationFrame(() => pill.style.setProperty('--i', index)));
    gearButton.classList.toggle('on', s.tab === 'settings');
    clear(gearButton).append(sym(s.tab === 'settings' ? 'gearFill' : 'gear', 19));
    gearButton.setAttribute('aria-label', ctx.L('tabSettings'));
    gearButton.title = ctx.L('tabSettings');
  }

  function renderMenu() {
    clear(menuLayer);
    menuLayer.classList.toggle('open', s.menuOpen);
    more.classList.toggle('selected', s.menuOpen);
    more.style.color = s.menuOpen ? C.onLight : C.ink;
    more.setAttribute('aria-label', ctx.L('moreMenu'));
    if (!s.menuOpen) return;
    const quick = (name, label, run, active = false) => h('button', { type: 'button', class: `ap-quick${active ? ' on' : ''}`, title: label, 'aria-label': label, onclick: run }, sym(name, 18));
    const row = (text, name, run, tint = C.ink) => h('button', { type: 'button', class: 'ap-menu-row', style: { color: tint }, onclick: run }, h('span', { text }), sym(name, 15));
    menuLayer.append(
      h('div', { class: 'ap-dim', onclick: () => { s.menuOpen = false; renderMenu(); } }),
      h('div', { class: glass('ap-more', true), role: 'menu' },
        h('div', { class: 'ap-quick-row' },
          quick(s.pinned ? 'pinFill' : 'pin', ctx.L('menuKeepOpen'), () => { s.pinned = !s.pinned; renderMenu(); }, s.pinned),
          quick('moonZzz', ctx.L('menuDisplayOff'), () => { s.menuOpen = false; renderMenu(); actions.displayOff(); }),
          quick('viewfinder', ctx.L('menuScreenshot'), () => { s.menuOpen = false; renderMenu(); showToast(ctx.L('capSaved'), 'check', C.positive); })),
        hairline(),
        h('div', { class: 'ap-menu-rows' },
          row(ctx.L('menuSettings'), 'gear', () => { s.menuOpen = false; setTab('settings'); }),
          row(ctx.L('menuActivityMonitor'), 'ecg', () => { s.menuOpen = false; setTab('system'); }),
          row(ctx.L('menuQuit'), 'power', () => { s.menuOpen = false; renderMenu(); actions.quit(); }, C.danger))));
  }

  let paneTimer;
  function render({ animate = false } = {}) {
    title.textContent = s.tab === 'automations' ? ctx.P('autoTitle') : ctx.L({ energy: 'tabEnergy', sound: 'tabSound', system: 'tabSystem', work: 'tabWork', tools: 'tabTools', features: 'tabFeatures', settings: 'tabSettings' }[s.tab]);
    setSub();
    renderChips();
    renderTabs();
    renderMenu();
    const top = scroll.scrollTop;
    clear(content).append(...[].concat(pane()));
    content.dataset.pane = s.tab;
    if (animate) {
      content.classList.remove('enter');
      void content.offsetWidth;
      content.classList.add('enter');
      scroll.scrollTop = 0;
    } else scroll.scrollTop = top;
  }
  const refresh = () => render();

  function pane() {
    switch (s.tab) {
      case 'energy': return [lidCard(ctx, refresh), powerFacts(ctx, refresh, () => actions.displayOff())];
      case 'sound': return [outputCard(ctx, refresh, setSub), mixerCard(ctx, root, refresh), inputCard(ctx, refresh), soundTricks(ctx, root, refresh)];
      case 'system': return systemPane(ctx, refresh);
      case 'work': return workPane(ctx, refresh);
      case 'tools': return toolsPane(ctx, refresh, actions);
      case 'features': return featuresPane(ctx, refresh);
      case 'automations': return automationsPane(ctx, refresh, actions);
      default: return settingsPane(ctx, refresh, actions);
    }
  }

  function setTab(tab) {
    if (s.tab === tab && !s.menuOpen) return;
    s.tab = tab;
    s.menuOpen = false;
    clearTimeout(paneTimer);
    render({ animate: true });
  }

  const actions = {
    toast: showToast,
    setTab,
    setLanguage: (code) => {
      panelLang = code;
      if (code === 'en' || code === 'ru') setLang(code);
      render();
    },
    toggleRecording: () => {
      s.recording = !s.recording;
      if (s.recording) s.recordStart = Date.now();
      else showToast(ctx.L('videoSaved'), 'check', C.positive);
      render();
    },
    displayOff: () => bus.emit('display-off'),
    openTerminal: () => bus.emit('open-window', 'terminal'),
    openBrowser: () => bus.emit('open-browser'),
    quit: () => bus.emit('panel-close')
  };

  more.addEventListener('click', () => { s.menuOpen = !s.menuOpen; renderMenu(); });
  gearButton.addEventListener('click', () => setTab('settings'));
  root.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && s.menuOpen) { s.menuOpen = false; renderMenu(); event.stopPropagation(); }
    if (/^[1-6]$/.test(event.key) && !event.target.closest('input, textarea')) setTab(TABS[Number(event.key) - 1][0]);
  });

  // Live readings: the System tab breathes, the Sound tab meters move, the recording chip counts.
  setInterval(() => {
    if (document.hidden || !root.isConnected || root.closest('[hidden]')) return;
    s.cpu = Math.max(8, Math.min(42, s.cpu + (Math.random() - 0.5) * 7));
    s.cpuHistory = [...s.cpuHistory.slice(-59), s.cpu];
    s.memory = Math.max(69, Math.min(74, s.memory + (Math.random() - 0.5) * 1.2));
    s.temp = Math.max(42, Math.min(48, s.temp + (Math.random() - 0.5) * 1.1));
    s.busiest = s.busiest.map(([n, t, v]) => [n, t, Math.max(0.4, v + (Math.random() - 0.5) * 0.6)]).sort((a, b) => b[2] - a[2]);
    if (s.tab === 'system' && !s.menuOpen && !root.querySelector('.ap-slider.dragging')) render();
    else if (s.tab === 'system') setSub();
  }, 2000);
  setInterval(() => {
    if (s.recording) { const t = chips.querySelector('.ap-rec-time'); if (t) t.textContent = elapsed(); }
    if (s.tab !== 'sound' || document.hidden) return;
    for (const meter of content.querySelectorAll('.ap-meter')) {
      const app = s.apps.find((a) => a.id === meter.dataset.app);
      const peak = app && !app.muted ? Math.min(1, (0.25 + Math.random() * 0.55) * Math.min(app.volume, 1.6)) : 0;
      meter.style.width = `${peak * 100}%`;
    }
  }, 120);

  onLang((next) => { panelLang = next; render(); });
  render();
  return { root, setTab, get tab() { return s.tab; } };
}

// Standalone cards for the field-guide plates, sharing the panel's look and copy.
export function createPanelCard(bus, kind) {
  const ctx = createContext(bus, () => siteLang);
  const host = h('div', { class: 'ap-panel ap-embedded' });
  const render = () => {
    const nodes = kind === 'mixer' ? [mixerCard(ctx, host, render)] : [lidCard(ctx, render), powerFacts(ctx, render, () => bus.emit('display-off'))];
    host.querySelectorAll('.ap-card').forEach((n) => n.remove());
    host.prepend(...nodes);
  };
  render();
  setInterval(() => {
    if (kind !== 'mixer' || document.hidden || !host.isConnected) return;
    for (const meter of host.querySelectorAll('.ap-meter')) {
      const app = ctx.state.apps.find((a) => a.id === meter.dataset.app);
      meter.style.width = `${app && !app.muted ? Math.min(1, (0.25 + Math.random() * 0.55) * Math.min(app.volume, 1.6)) * 100 : 0}%`;
    }
  }, 140);
  return host;
}
