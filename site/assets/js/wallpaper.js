// The live wallpaper section: the scene photographs with petals falling on a breeze that never repeats, a light
// under the pointer, and petals that drift away from it, the way the wallpaper behaves in the app.
const SCENES = {
  hill: { src: 'assets/wall/hill.jpg', ground: 0.74, canopy: [[0.62, 0.3, 0.25, 0.17], [0.45, 0.42, 0.1, 0.08], [0.8, 0.42, 0.1, 0.07]] },
  bonsai: { src: 'assets/wall/bonsai.jpg', ground: 0.86, canopy: [[0.5, 0.28, 0.18, 0.15], [0.38, 0.5, 0.1, 0.08], [0.66, 0.48, 0.09, 0.08]] },
  'bonsai-hill': { src: 'assets/wall/bonsai-hill.jpg', ground: 0.8, canopy: [[0.5, 0.42, 0.17, 0.08], [0.42, 0.55, 0.09, 0.05], [0.6, 0.54, 0.08, 0.05]] }
};
const stage = document.getElementById('wall-stage');
if (stage) {
  const canvas = stage.querySelector('canvas');
  const image = stage.querySelector('img');
  const ctx = canvas.getContext('2d');
  const tabs = [...document.querySelectorAll('#wallpaper [data-scene]')];
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  let scene = 'hill', petals = [], pointer = null, running = false, last = 0, clock = 0;
  const light = { x: 0, y: 0, level: 0 };
  const wind = (t) => 0.12 + 0.5 * Math.sin(t * 0.11) + 0.28 * Math.sin(t * 0.29 + 1.7) + 0.15 * Math.sin(t * 0.73 + 0.4);
  const box = () => stage.getBoundingClientRect();

  function fit() {
    const r = box(), d = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(r.width * d);
    canvas.height = Math.round(r.height * d);
    ctx.setTransform(d, 0, 0, d, 0, 0);
  }

  function spawn(scattered) {
    const r = box(), s = SCENES[scene], depth = 0.55 + Math.random() * 1.05;
    const p = { depth, size: 10 * depth, fall: 30 * (0.75 + Math.random() * 0.5), sway: 8 + Math.random() * 22, rate: 0.5 + Math.random() * 0.8,
      phase: Math.random() * 6.28, turn: (1.2 + Math.random() * 2) * (Math.random() < 0.5 ? -1 : 1), spin: (Math.random() - 0.5) * 2.2,
      rot: Math.random() * 6.28, age: 0, push: [0, 0], tree: false, rest: null };
    if (Math.random() < 0.55) {
      const c = s.canopy[Math.floor(Math.random() * s.canopy.length)], a = Math.random() * 6.28, k = Math.sqrt(Math.random());
      p.x = (c[0] + Math.cos(a) * k * c[2]) * r.width;
      p.y = (c[1] + Math.sin(a) * k * c[3]) * r.height;
      p.tree = true;
    } else {
      p.x = Math.random() * (r.width + 80) - 80;
      p.y = scattered ? Math.random() * r.height : -20 - Math.random() * 40;
    }
    p.land = (s.ground + Math.random() * (1 - s.ground) * 0.9) * r.height;
    return p;
  }

  function reset() {
    const r = box();
    petals = Array.from({ length: Math.round(Math.min(110, Math.max(40, (r.width * r.height) / 8000))) }, () => spawn(true));
  }

  function petal(p, x, y, alpha, lit) {
    const turn = Math.cos(p.phase + clock * p.turn), s = p.size;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(p.rot);
    ctx.scale((0.18 + 0.82 * Math.abs(turn)) * (turn < 0 ? -1 : 1), 1);
    const g = ctx.createLinearGradient(0, s * 0.5, 0, -s * 0.5);
    g.addColorStop(0, `rgba(255,${Math.round(236 + lit * 19)},${Math.round(242 + lit * 13)},${alpha})`);
    g.addColorStop(1, `rgba(${turn < 0 ? 214 : 245},${Math.round(156 + lit * 80)},${Math.round(182 + lit * 60)},${alpha})`);
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.moveTo(0, -s * 0.46);
    ctx.bezierCurveTo(-s * 0.52, -s * 0.3, -s * 0.56, s * 0.26, -s * 0.12, s * 0.48);
    ctx.lineTo(0, s * 0.36);
    ctx.lineTo(s * 0.12, s * 0.48);
    ctx.bezierCurveTo(s * 0.56, s * 0.26, s * 0.52, -s * 0.3, 0, -s * 0.46);
    ctx.fill();
    ctx.restore();
  }

  function frame(now) {
    if (!running) return;
    const dt = Math.min((now - (last || now)) / 1000, 0.05);
    last = now;
    clock += dt;
    const r = box(), w = wind(clock);
    ctx.clearRect(0, 0, r.width, r.height);
    light.level += ((pointer ? 1 : 0) - light.level) * (1 - Math.exp(-dt * 6));
    if (pointer) {
      const k = 1 - Math.exp(-dt * 12);
      light.x += (pointer[0] - light.x) * k;
      light.y += (pointer[1] - light.y) * k;
    }
    if (light.level > 0.01) {
      const g = ctx.createRadialGradient(light.x, light.y, 0, light.x, light.y, 170);
      g.addColorStop(0, `rgba(255,230,216,${0.4 * light.level})`);
      g.addColorStop(0.4, `rgba(255,192,170,${0.13 * light.level})`);
      g.addColorStop(1, 'rgba(255,180,160,0)');
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = g;
      ctx.fillRect(light.x - 170, light.y - 170, 340, 340);
      ctx.globalCompositeOperation = 'source-over';
    }
    for (let i = 0; i < petals.length; i++) {
      const p = petals[i];
      p.age += dt;
      const strength = 0.55 + 0.4 * Math.min(1, (p.depth - 0.55) / 0.8);
      if (p.rest !== null) {
        const fade = (clock - p.rest) / 3.5;
        if (fade >= 1) petals[i] = spawn(false);
        else petal(p, p.x + p.push[0], p.y + p.push[1], (1 - fade) * strength, 0);
        continue;
      }
      p.x += w * 24 * p.depth * dt;
      p.y += p.fall * p.depth * dt;
      p.rot += p.spin * dt;
      const x = p.x + p.sway * Math.sin(p.phase + clock * p.rate);
      let lit = 0;
      if (pointer) {
        const dx = x + p.push[0] - pointer[0], dy = p.y + p.push[1] - pointer[1], d = Math.max(Math.hypot(dx, dy), 1);
        if (d < 130) {
          const k = (1 - d / 130) ** 2;
          p.push[0] += (dx / d) * k * 160 * dt;
          p.push[1] += (dy / d) * k * 160 * dt;
          lit = 1 - d / 130;
        }
      }
      const decay = Math.exp(-dt * 1.4);
      p.push[0] *= decay;
      p.push[1] *= decay;
      petal(p, x + p.push[0], p.y + p.push[1], Math.min(1, p.age / (p.tree ? 1.2 : 0.3)) * strength, lit);
      if (p.tree && p.y >= p.land && p.age > 1) { p.x = x; p.rest = clock; }
      else if (p.y > r.height + 30 || x > r.width + 90) petals[i] = spawn(false);
    }
    requestAnimationFrame(frame);
  }

  function choose(name) {
    if (name === scene || !SCENES[name]) return;
    scene = name;
    for (const tab of tabs) tab.classList.toggle('on', tab.dataset.scene === name);
    image.style.opacity = '0';
    setTimeout(() => {
      image.onload = () => { image.style.opacity = '1'; };
      image.src = SCENES[name].src;
      reset();
    }, 260);
  }

  for (const tab of tabs) tab.addEventListener('click', () => choose(tab.dataset.scene));
  stage.addEventListener('pointermove', (e) => { const r = box(); pointer = [e.clientX - r.left, e.clientY - r.top]; });
  stage.addEventListener('pointerleave', () => { pointer = null; });
  window.addEventListener('resize', () => { fit(); reset(); });
  fit();
  reset();
  if (!still) {
    new IntersectionObserver((entries) => {
      const visible = entries.some((e) => e.isIntersecting);
      if (visible && !running) { running = true; last = 0; requestAnimationFrame(frame); }
      if (!visible) running = false;
    }).observe(stage);
  }
}
