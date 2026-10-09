(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);
  const FORMATS = [['hex', 'HEX'], ['rgb', 'RGB'], ['hsl', 'HSL'], ['oklch', 'OKLCH']];

  let current = null;
  let previous = null;
  let palette = null;
  let picking = false;

  function remember(hex) {
    const colors = [hex, ...(SV.settings.colors || []).filter((c) => c !== hex)].slice(0, 16);
    SV.settings.colors = colors;
    SV_STORE.save({ colors });
  }

  async function pick() {
    if (picking) return;
    if (!('EyeDropper' in window)) {
      SV.notch.openPanel('color');
      return;
    }
    picking = true;
    SV.notch.close();
    SV.mode.enter({ id: 'color', icon: 'pipette', name: t('colorTitle'), hint: t('colorPicking') });
    try {
      const result = await new window.EyeDropper().open();
      const hex = result.sRGBHex.startsWith('#') ? result.sRGBHex : SV.toHex(SV.parseColor(result.sRGBHex));
      if (current && current !== hex.toLowerCase()) previous = current;
      current = hex.toLowerCase();
      remember(current);
      if (SV.settings.colorAutoCopy) {
        const text = SV.formatColor(SV.hexToRgb(current), SV.settings.colorFormat);
        await SV.copy(text);
        SV.toast(t('copiedValue', text), { icon: 'pipette' });
      }
    } catch {
      // Esc or a click outside the page cancels the eyedropper.
    } finally {
      picking = false;
      SV.mode.exit('color');
    }
    if (current) SV.notch.openPanel('color');
  }

  function extractPalette() {
    const weights = new Map();
    const add = (color, weight) => {
      if (!color || color.a < 0.6 || !Number.isFinite(color.r)) return;
      const hex = SV.toHex(color);
      weights.set(hex, (weights.get(hex) || 0) + weight);
    };
    const viewport = innerWidth * innerHeight;
    let count = 0;
    for (const el of document.body?.querySelectorAll('*') || []) {
      if (++count > 4000) break;
      if (SV.isOurs(el)) continue;
      const rect = el.getBoundingClientRect();
      if (rect.width < 4 || rect.height < 4 || rect.bottom < 0 || rect.top > innerHeight * 3) continue;
      const style = getComputedStyle(el);
      if (style.visibility === 'hidden' || style.opacity === '0') continue;
      add(SV.parseColor(style.backgroundColor), Math.min(rect.width * rect.height, viewport) / 2000);
      const own = [...el.childNodes].filter((n) => n.nodeType === 3 && n.nodeValue.trim()).reduce((sum, n) => sum + n.nodeValue.trim().length, 0);
      if (own) add(SV.parseColor(style.color), 4 + own / 12);
      if (parseFloat(style.borderTopWidth) > 0 && style.borderTopStyle !== 'none') add(SV.parseColor(style.borderTopColor), 1.5);
      if (el instanceof SVGElement && style.fill && style.fill !== 'none') add(SV.parseColor(style.fill), 3);
    }
    const sorted = [...weights.entries()].sort((a, b) => b[1] - a[1]);
    const chosen = [];
    for (const [hex] of sorted) {
      const rgb = SV.hexToRgb(hex);
      const near = chosen.some((other) => {
        const o = SV.hexToRgb(other);
        return Math.abs(o.r - rgb.r) + Math.abs(o.g - rgb.g) + Math.abs(o.b - rgb.b) < 28;
      });
      if (!near) chosen.push(hex);
      if (chosen.length === 14) break;
    }
    return chosen;
  }

  function panel(api) {
    const body = api.body;
    const render = () => {
      SV.clear(body);
      const supported = 'EyeDropper' in window;
      const top = h('div', { class: 'row' },
        h('button', { class: 'btn primary', type: 'button', disabled: !supported, onclick: () => pick(), 'data-autofocus': '' }, icon('pipette', 15), t('colorPick')),
        h('span', { class: 'grow' }),
        h('span', { class: 'hint', text: t('colorAuto') }),
        SV.toggleSwitch(SV.settings.colorAutoCopy, t('colorAuto'), (on) => {
          SV.settings.colorAutoCopy = on;
          SV_STORE.save({ colorAutoCopy: on });
        }));
      body.append(top);
      if (!supported) body.append(h('div', { class: 'card hint', text: t('colorNoApi') }));

      if (current) {
        const rgb = SV.hexToRgb(current);
        const values = h('div', { class: 'values' }, FORMATS.map(([format, label]) => {
          const text = SV.formatColor(rgb, format);
          return h('button', {
            class: `value-row${SV.settings.colorFormat === format ? ' preferred' : ''}`, type: 'button', title: t('copy'),
            onclick: async () => {
              await SV.copy(text);
              SV.settings.colorFormat = format;
              SV_STORE.save({ colorFormat: format });
              SV.toast(t('copiedValue', text), { icon: 'copy' });
              render();
            }
          }, h('span', { class: 'k', text: label }), h('span', { class: 'v', text }), icon('copy', 14));
        }));
        body.append(h('div', { class: 'card row', style: { gap: '14px', 'align-items': 'center' } },
          h('div', { class: 'swatch-big', style: { background: current } }), values));

        const against = previous || (SV.settings.colors || []).find((c) => c !== current);
        if (against) {
          const ratio = SV.contrast(rgb, SV.hexToRgb(against));
          const badge = (label, ok) => h('span', { class: `pass ${ok ? 'ok' : 'no'}`, text: label });
          body.append(h('div', { class: 'card row', style: { gap: '12px' } },
            h('div', { class: 'pair', style: { background: against, color: current }, text: 'Aa' }),
            h('div', { class: 'grow' },
              h('div', { class: 'hint', text: t('colorContrast', against.toUpperCase()) }),
              h('div', { class: 'row', style: { gap: '8px', 'margin-top': '2px' } },
                h('span', { class: 'ratio', text: `${I.number(ratio, 2)} : 1` }))),
            h('div', { class: 'row', style: { gap: '4px', 'flex-wrap': 'wrap', 'justify-content': 'flex-end', 'max-width': '150px' } },
              badge('AA', ratio >= 4.5), badge('AAA', ratio >= 7), badge('AA Large', ratio >= 3))));
        }
      } else {
        body.append(h('div', { class: 'card empty', text: t('colorEmpty') }));
      }

      const recent = (SV.settings.colors || []).slice(0, 16);
      if (recent.length) {
        body.append(h('div', null,
          h('div', { class: 'section-title', style: { margin: '2px 2px 8px' } }, h('span', { text: t('colorRecent') })),
          h('div', { class: 'swatches' }, recent.map((hex) => h('button', {
            class: 'swatch', type: 'button', title: hex.toUpperCase(), style: { background: hex },
            onclick: () => {
              if (current && current !== hex) previous = current;
              current = hex;
              render();
            }
          })))));
      }

      const paletteBlock = h('div', null,
        h('div', { class: 'section-title', style: { margin: '2px 2px 8px' } },
          h('span', { text: t('colorPalette') }),
          palette ? null : h('button', { class: 'btn small', type: 'button', onclick: () => { palette = extractPalette(); render(); } }, icon('sparkle', 14), t('colorPalette'))),
        palette ? h('div', { class: 'swatches' }, palette.map((hex) => h('button', {
          class: 'swatch', type: 'button', title: hex.toUpperCase(), style: { background: hex },
          onclick: () => {
            if (current && current !== hex) previous = current;
            current = hex;
            remember(hex);
            render();
          }
        }))) : null);
      body.append(paletteBlock);
      api.refit();
    };
    render();
    return null;
  }

  SV.tools.color = {
    label: 'tColor',
    icon: 'pipette',
    kind: 'mode',
    title: () => t('colorTitle'),
    active: () => picking,
    start: pick,
    stop: () => SV.mode.exit('color'),
    panel
  };
})();
