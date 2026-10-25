import 'dart:math';

/// UI-independent simulation. Fixed steps keep physics stable across devices.
class Gate {
  Gate(this.x, this.center);
  double x;
  final double center;
  bool scored = false;
}

class Round {
  Round({this.seed = 42}) : random = Random(seed);
  final int seed;
  final Random random;
  static const duration = 45.0;
  static const radius = 0.025;
  static const birdX = 0.24;
  static const gateWidth = 0.13;
  static const halfGap = 0.17;
  final List<Gate> gates = [];
  double elapsed = 0, y = 0.5, velocity = 0, cooldown = 0;
  double spawnClock = 0, accumulator = 0;
  int score = 0, hits = 0;
  bool get finished => elapsed >= duration;
  void flap() {
    if (!finished && cooldown <= 0) velocity = -0.58;
  }

  void advance(double dt) {
    if (finished || !dt.isFinite || dt <= 0) return;
    accumulator += dt;
    while (accumulator >= 1 / 120 && !finished) {
      step(1 / 120);
      accumulator -= 1 / 120;
    }
  }

  void step(double dt) {
    elapsed = min(duration, elapsed + dt);
    spawnClock -= dt;
    if (spawnClock <= 0) {
      gates.add(Gate(1.1, 0.28 + random.nextDouble() * 0.44));
      spawnClock += 1.65;
    }
    for (final gate in gates) {
      gate.x -= 0.30 * dt;
    }
    gates.removeWhere((g) => g.x + gateWidth < 0);
    if (cooldown > 0) {
      cooldown = max(0, cooldown - dt);
      for (final gate in gates) {
        if (gate.x + gateWidth < birdX + radius) gate.scored = true;
      }
      return;
    }
    velocity += 1.35 * dt;
    y += velocity * dt;
    bool collision = y - radius <= 0 || y + radius >= 1;
    for (final gate in gates) {
      final overlaps = birdX + radius > gate.x &&
          birdX - radius < gate.x + gateWidth;
      if (overlaps && (y - radius < gate.center - halfGap ||
          y + radius > gate.center + halfGap)) collision = true;
    }
    if (collision) {
      hits++;
      y = 0.5;
      velocity = 0;
      cooldown = 0.85;
      // Missed obstacles cannot score during respawn.
      for (final gate in gates) {
        if (gate.x < birdX + radius) gate.scored = true;
      }
      return;
    }
    for (final gate in gates) {
      if (!gate.scored && gate.x + gateWidth < birdX - radius) {
        gate.scored = true;
        score++;
      }
    }
  }
}
