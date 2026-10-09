(() => {
  // Byte-mode QR encoder (ISO/IEC 18004), versions 1–40, with automatic mask selection.
  const ECC_PER_BLOCK = [
    [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
    [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]
  ];
  const BLOCKS = [
    [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
    [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
    [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
    [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81]
  ];
  const LEVEL = { L: 0, M: 1, Q: 2, H: 3 };
  const FORMAT_BITS = [1, 0, 3, 2];

  const bit = (value, index) => ((value >>> index) & 1) !== 0;

  function rawModules(ver) {
    let result = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
      const align = Math.floor(ver / 7) + 2;
      result -= (25 * align - 10) * align - 55;
      if (ver >= 7) result -= 36;
    }
    return result;
  }

  const dataCodewords = (ver, ecl) => Math.floor(rawModules(ver) / 8) - ECC_PER_BLOCK[ecl][ver] * BLOCKS[ecl][ver];

  function multiply(x, y) {
    let z = 0;
    for (let i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >>> 7) * 0x11d);
      z ^= ((y >>> i) & 1) * x;
    }
    return z;
  }

  function divisor(degree) {
    const result = new Array(degree).fill(0);
    result[degree - 1] = 1;
    let root = 1;
    for (let i = 0; i < degree; i++) {
      for (let j = 0; j < result.length; j++) {
        result[j] = multiply(result[j], root);
        if (j + 1 < result.length) result[j] ^= result[j + 1];
      }
      root = multiply(root, 0x02);
    }
    return result;
  }

  function remainder(data, div) {
    const result = div.map(() => 0);
    for (const byte of data) {
      const factor = byte ^ result.shift();
      result.push(0);
      div.forEach((coef, i) => { result[i] ^= multiply(coef, factor); });
    }
    return result;
  }

  function encode(text, level = 'M') {
    const bytes = Array.from(new TextEncoder().encode(text));
    let ecl = LEVEL[level] ?? 1;
    let ver = 1;
    for (; ver <= 40; ver++) {
      const countBits = ver <= 9 ? 8 : 16;
      if (4 + countBits + bytes.length * 8 <= dataCodewords(ver, ecl) * 8) break;
    }
    if (ver > 40) return null;
    const countBits = ver <= 9 ? 8 : 16;
    const used = 4 + countBits + bytes.length * 8;
    for (const better of [LEVEL.Q, LEVEL.H]) {
      if (better > ecl && used <= dataCodewords(ver, better) * 8) ecl = better;
    }

    const bits = [];
    const append = (value, length) => { for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1); };
    append(0x4, 4);
    append(bytes.length, countBits);
    bytes.forEach((byte) => append(byte, 8));
    const capacity = dataCodewords(ver, ecl) * 8;
    append(0, Math.min(4, capacity - bits.length));
    append(0, (8 - (bits.length % 8)) % 8);
    for (let pad = 0xec; bits.length < capacity; pad ^= 0xec ^ 0x11) append(pad, 8);
    const data = [];
    for (let i = 0; i < bits.length; i += 8) {
      let byte = 0;
      for (let j = 0; j < 8; j++) byte = (byte << 1) | bits[i + j];
      data.push(byte);
    }

    const numBlocks = BLOCKS[ecl][ver];
    const eccLen = ECC_PER_BLOCK[ecl][ver];
    const raw = Math.floor(rawModules(ver) / 8);
    const shortBlocks = numBlocks - (raw % numBlocks);
    const shortLen = Math.floor(raw / numBlocks);
    const div = divisor(eccLen);
    const blocks = [];
    for (let i = 0, k = 0; i < numBlocks; i++) {
      const chunk = data.slice(k, k + shortLen - eccLen + (i < shortBlocks ? 0 : 1));
      k += chunk.length;
      const ecc = remainder(chunk, div);
      if (i < shortBlocks) chunk.push(0);
      blocks.push(chunk.concat(ecc));
    }
    const codewords = [];
    for (let i = 0; i < blocks[0].length; i++) {
      blocks.forEach((block, j) => {
        if (i !== shortLen - eccLen || j >= shortBlocks) codewords.push(block[i]);
      });
    }

    const size = ver * 4 + 17;
    const modules = Array.from({ length: size }, () => new Array(size).fill(false));
    const fixed = Array.from({ length: size }, () => new Array(size).fill(false));
    const set = (x, y, dark) => { modules[y][x] = dark; fixed[y][x] = true; };

    for (let i = 0; i < size; i++) {
      set(6, i, i % 2 === 0);
      set(i, 6, i % 2 === 0);
    }
    const finder = (cx, cy) => {
      for (let dy = -4; dy <= 4; dy++) {
        for (let dx = -4; dx <= 4; dx++) {
          const x = cx + dx;
          const y = cy + dy;
          if (x < 0 || y < 0 || x >= size || y >= size) continue;
          const dist = Math.max(Math.abs(dx), Math.abs(dy));
          set(x, y, dist !== 2 && dist !== 4);
        }
      }
    };
    finder(3, 3);
    finder(size - 4, 3);
    finder(3, size - 4);

    const positions = [];
    if (ver > 1) {
      const count = Math.floor(ver / 7) + 2;
      const step = ver === 32 ? 26 : Math.ceil((ver * 4 + 4) / (count * 2 - 2)) * 2;
      positions.push(6);
      for (let pos = size - 7; positions.length < count; pos -= step) positions.splice(1, 0, pos);
    }
    const last = positions.length - 1;
    positions.forEach((py, i) => positions.forEach((px, j) => {
      if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) return;
      for (let dy = -2; dy <= 2; dy++) {
        for (let dx = -2; dx <= 2; dx++) set(px + dx, py + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
      }
    }));

    const drawFormat = (mask) => {
      const value = (FORMAT_BITS[ecl] << 3) | mask;
      let rem = value;
      for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
      const format = ((value << 10) | rem) ^ 0x5412;
      for (let i = 0; i <= 5; i++) set(8, i, bit(format, i));
      set(8, 7, bit(format, 6));
      set(8, 8, bit(format, 7));
      set(7, 8, bit(format, 8));
      for (let i = 9; i < 15; i++) set(14 - i, 8, bit(format, i));
      for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(format, i));
      for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(format, i));
      set(8, size - 8, true);
    };
    drawFormat(0);

    if (ver >= 7) {
      let rem = ver;
      for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
      const value = (ver << 12) | rem;
      for (let i = 0; i < 18; i++) {
        const a = size - 11 + (i % 3);
        const b = Math.floor(i / 3);
        set(a, b, bit(value, i));
        set(b, a, bit(value, i));
      }
    }

    let index = 0;
    for (let right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < size; vert++) {
        for (let j = 0; j < 2; j++) {
          const x = right - j;
          const upward = ((right + 1) & 2) === 0;
          const y = upward ? size - 1 - vert : vert;
          if (!fixed[y][x] && index < codewords.length * 8) {
            modules[y][x] = bit(codewords[index >>> 3], 7 - (index & 7));
            index++;
          }
        }
      }
    }

    const applyMask = (mask) => {
      for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
          if (fixed[y][x]) continue;
          let invert;
          switch (mask) {
            case 0: invert = (x + y) % 2 === 0; break;
            case 1: invert = y % 2 === 0; break;
            case 2: invert = x % 3 === 0; break;
            case 3: invert = (x + y) % 3 === 0; break;
            case 4: invert = (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0; break;
            case 5: invert = ((x * y) % 2) + ((x * y) % 3) === 0; break;
            case 6: invert = (((x * y) % 2) + ((x * y) % 3)) % 2 === 0; break;
            default: invert = (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
          }
          if (invert) modules[y][x] = !modules[y][x];
        }
      }
    };

    const addHistory = (length, history) => {
      if (history[0] === 0) length += size;
      history.pop();
      history.unshift(length);
    };
    const countPatterns = (history) => {
      const n = history[1];
      const core = n > 0 && history[2] === n && history[3] === n * 3 && history[4] === n && history[5] === n;
      return (core && history[0] >= n * 4 && history[6] >= n ? 1 : 0) + (core && history[6] >= n * 4 && history[0] >= n ? 1 : 0);
    };
    const terminate = (color, length, history) => {
      if (color) {
        addHistory(length, history);
        length = 0;
      }
      length += size;
      addHistory(length, history);
      return countPatterns(history);
    };
    const penalty = () => {
      let result = 0;
      for (let pass = 0; pass < 2; pass++) {
        for (let a = 0; a < size; a++) {
          let color = false;
          let run = 0;
          const history = [0, 0, 0, 0, 0, 0, 0];
          for (let b = 0; b < size; b++) {
            const cell = pass === 0 ? modules[a][b] : modules[b][a];
            if (cell === color) {
              run++;
              if (run === 5) result += 3;
              else if (run > 5) result++;
            } else {
              addHistory(run, history);
              if (!color) result += countPatterns(history) * 40;
              color = cell;
              run = 1;
            }
          }
          result += terminate(color, run, history) * 40;
        }
      }
      for (let y = 0; y < size - 1; y++) {
        for (let x = 0; x < size - 1; x++) {
          const c = modules[y][x];
          if (c === modules[y][x + 1] && c === modules[y + 1][x] && c === modules[y + 1][x + 1]) result += 3;
        }
      }
      let dark = 0;
      modules.forEach((row) => row.forEach((cell) => { if (cell) dark++; }));
      const total = size * size;
      result += (Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1) * 10;
      return result;
    };

    let best = 0;
    let bestScore = Infinity;
    for (let mask = 0; mask < 8; mask++) {
      applyMask(mask);
      drawFormat(mask);
      const score = penalty();
      if (score < bestScore) {
        best = mask;
        bestScore = score;
      }
      applyMask(mask);
    }
    applyMask(best);
    drawFormat(best);
    return { size, version: ver, get: (x, y) => modules[y][x] };
  }

  function draw(canvas, text, { scale = 6, margin = 4, dark = '#141416', light = '#ffffff' } = {}) {
    const code = encode(text);
    if (!code) return null;
    const pixels = (code.size + margin * 2) * scale;
    canvas.width = pixels;
    canvas.height = pixels;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = light;
    ctx.fillRect(0, 0, pixels, pixels);
    ctx.fillStyle = dark;
    for (let y = 0; y < code.size; y++) {
      for (let x = 0; x < code.size; x++) {
        if (code.get(x, y)) ctx.fillRect((x + margin) * scale, (y + margin) * scale, scale, scale);
      }
    }
    return code;
  }

  globalThis.SV_QR = { encode, draw };
})();
