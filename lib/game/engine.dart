/// sky-hop-v1: integer physics; inputs apply before the numbered tick.
class EngineGate {
  EngineGate(this.x, this.center);
  int x;
  final int center;
  bool scored = false;
  Map<String, Object> snapshot() => {'x': x, 'center': center, 'scored': scored};
}

class GameEngine {
  GameEngine(int seed) : random = seed {
    if (seed < 0 || seed > 0xffffffff) throw RangeError('seed');
  }
  static const version = 'sky-hop-v1';
  int random;
  int tick = 0, y = 500000, velocity = 0, cooldown = 0, score = 0, hits = 0;
  final List<EngineGate> gates = [];
  void step({bool flap = false}) {
    if (tick >= 5400) return;
    if (flap && cooldown == 0) velocity = -69600000;
    if (tick % 198 == 0) {
      random = (1664525 * random + 1013904223) % 4294967296;
      gates.add(EngineGate(1100000, 280000 + random % 440001));
    }
    tick++;
    for (final g in gates) { g.x -= 2500; }
    gates.removeWhere((g) => g.x + 130000 < 0);
    if (cooldown > 0) {
      cooldown--;
      for (final g in gates) { if (g.x + 130000 < 265000) g.scored = true; }
      return;
    }
    velocity += 1350000;
    y += velocity ~/ 14400;
    var collision = y <= 25000 || y >= 975000;
    for (final g in gates) {
      if (265000 > g.x && 215000 < g.x + 130000 &&
          (y - 25000 < g.center - 170000 || y + 25000 > g.center + 170000)) collision = true;
    }
    if (collision) {
      hits++; y = 500000; velocity = 0; cooldown = 102;
      for (final g in gates) { if (g.x < 265000) g.scored = true; }
      return;
    }
    for (final g in gates) {
      if (!g.scored && g.x + 130000 < 215000) { g.scored = true; score++; }
    }
  }
  Map<String, Object> snapshot() => {
    'tick': tick, 'y': y, 'velocity': velocity, 'cooldown': cooldown,
    'score': score, 'hits': hits, 'random': random,
    'gates': gates.map((g) => g.snapshot()).toList(),
  };
}
