// Remote control for the demo frame. The welcome page calls SAVISUL_DEMO.run(step) on this window.
(() => {
  const SV = globalThis.SV;
  if (!SV) return;
  // Screenshots capture the whole browser tab, not this frame, so the demo leaves them out.
  delete SV.tools.shot;

  const ready = () => !!SV.root && SV.notch?.view;

  const pointAt = (selector) => {
    const el = document.querySelector(selector);
    if (!el) return;
    el.scrollIntoView({ block: 'center', behavior: 'smooth' });
    setTimeout(() => {
      const r = el.getBoundingClientRect();
      const event = { clientX: r.left + Math.min(r.width / 2, 160), clientY: r.top + Math.min(r.height / 2, 60), bubbles: true };
      document.dispatchEvent(new PointerEvent('pointermove', event));
    }, 420);
  };

  const stopModes = () => {
    for (const id of ['reader', 'inspect', 'ruler', 'zapper', 'fonts']) {
      if (SV.tools[id]?.active?.()) SV.tools[id].stop();
    }
  };

  const steps = {
    notch: () => SV.notch.openHome({ focus: true }),
    reader: () => SV.runTool('reader'),
    dark: () => {
      SV.notch.close();
      SV.tools.dark.toggle();
    },
    inspect: () => {
      if (!SV.tools.inspect.active()) SV.runTool('inspect');
      requestAnimationFrame(() => pointAt('table'));
    },
    data: () => SV.notch.openPanel('tables', { direct: true }),
    translate: () => SV.notch.openPanel('translate', { direct: true }),
    export: () => SV.notch.openPanel('export', { direct: true }),
    notes: () => SV.notch.openPanel('notes', { direct: true }),
    ruler: () => {
      if (!SV.tools.ruler.active()) SV.runTool('ruler');
      requestAnimationFrame(() => pointAt('h1'));
    }
  };

  globalThis.SAVISUL_DEMO = {
    ready,
    run(step) {
      if (!ready() || !steps[step]) return false;
      if (!['inspect', 'ruler'].includes(step)) stopModes();
      if (step !== 'dark' && step !== 'reader' && SV.tools.reader?.active?.()) SV.tools.reader.stop();
      window.focus();
      steps[step]();
      return true;
    },
    state: () => ({
      view: SV.notch.view,
      panel: SV.notch.panel,
      reader: !!SV.tools.reader?.active?.(),
      dark: !!SV.tools.dark?.active?.(),
      inspect: !!SV.tools.inspect?.active?.()
    })
  };
})();
