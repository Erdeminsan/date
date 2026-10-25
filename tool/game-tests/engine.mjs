// sky-hop-v1: integer physics; inputs apply before the numbered tick.
export class GameEngine {
  static version = 'sky-hop-v1';
  constructor(seed) {
    if (!Number.isInteger(seed) || seed < 0 || seed > 0xffffffff) throw new RangeError('seed');
    this.random = seed;
    this.tick = 0; this.y = 500000; this.velocity = 0;
    this.cooldown = 0; this.score = 0; this.hits = 0; this.gates = [];
  }
  step(flap = false) {
    if (this.tick >= 5400) return;
    if (flap && this.cooldown === 0) this.velocity = -69600000;
    if (this.tick % 198 === 0) {
      this.random = (1664525 * this.random + 1013904223) % 4294967296;
      this.gates.push({x: 1100000, center: 280000 + this.random % 440001, scored: false});
    }
    this.tick++;
    for (const g of this.gates) g.x -= 2500;
    this.gates = this.gates.filter(g => g.x + 130000 >= 0);
    if (this.cooldown > 0) {
      this.cooldown--;
      for (const g of this.gates) if (g.x + 130000 < 265000) g.scored = true;
      return;
    }
    this.velocity += 1350000;
    this.y += Math.trunc(this.velocity / 14400);
    let collision = this.y <= 25000 || this.y >= 975000;
    for (const g of this.gates) {
      if (265000 > g.x && 215000 < g.x + 130000 &&
          (this.y - 25000 < g.center - 170000 || this.y + 25000 > g.center + 170000)) collision = true;
    }
    if (collision) {
      this.hits++; this.y = 500000; this.velocity = 0; this.cooldown = 102;
      for (const g of this.gates) if (g.x < 265000) g.scored = true;
      return;
    }
    for (const g of this.gates) {
      if (!g.scored && g.x + 130000 < 215000) { g.scored = true; this.score++; }
    }
  }
  snapshot() {
    return {tick:this.tick,y:this.y,velocity:this.velocity,cooldown:this.cooldown,
      score:this.score,hits:this.hits,random:this.random,gates:this.gates.map(g=>({...g}))};
  }
}

// Offline replay only. Authorization, time windows and ordered network batches
// must be enforced by the future room service before accepting a result.
export function replay(seed, ticks) {
  if (!Array.isArray(ticks) || ticks.length > 5400) throw new RangeError('inputs');
  let previous = -1;
  for (const tick of ticks) {
    if (!Number.isInteger(tick) || tick <= previous || tick >= 5400) throw new RangeError('input tick');
    previous = tick;
  }
  const engine = new GameEngine(seed);
  let index = 0;
  while (engine.tick < 5400) {
    const flap = ticks[index] === engine.tick;
    if (flap) index++;
    engine.step(flap);
  }
  return engine.snapshot();
}
