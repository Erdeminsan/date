import 'engine.dart';

/// Read-only normalized coordinates for rendering the integer engine.
class Gate {
  const Gate(this.x, this.center);
  final double x;
  final double center;
}

class Round {
  Round({this.seed = 42}) : engine = GameEngine(seed);
  final int seed;
  final GameEngine engine;
  static const duration = 45.0;
  static const radius = 0.025;
  static const birdX = 0.24;
  static const gateWidth = 0.13;
  static const halfGap = 0.17;
  double _accumulator = 0;
  bool _pendingFlap = false;
  final List<int> _inputs = [];
  List<int> get inputs => List.unmodifiable(_inputs);
  Iterable<Gate> get gates => engine.gates.map((g) => Gate(g.x / 1000000, g.center / 1000000));
  double get elapsed => engine.tick / 120;
  double get y => engine.y / 1000000;
  double get cooldown => engine.cooldown / 120;
  int get score => engine.score;
  int get hits => engine.hits;
  bool get finished => engine.tick >= 5400;

  void flap() {
    if (!finished && engine.cooldown == 0) _pendingFlap = true;
  }
  void clearPendingInput() => _pendingFlap = false;

  void advance(double dt) {
    if (finished || !dt.isFinite || dt <= 0) return;
    // At most the remaining round can run, even after a very long frame.
    _accumulator += dt > duration ? duration : dt;
    const step = 1 / 120;
    while (_accumulator + 1e-10 >= step && !finished) {
      final flap = _pendingFlap;
      _pendingFlap = false;
      if (flap) _inputs.add(engine.tick);
      engine.step(flap: flap);
      _accumulator -= step;
      if (_accumulator < 0) _accumulator = 0;
    }
  }
}

/// Local practice pauses explicitly. Network rooms must use server time instead.
class PracticeSession {
  PracticeSession({int seed = 42}) : round = Round(seed: seed);
  final Round round;
  double countdown = 3;
  bool paused = false;
  void flap() {
    if (!paused && countdown <= 0) round.flap();
  }
  void pause() {
    paused = true;
    round.clearPendingInput();
  }
  void resume() => paused = false;
  void advance(double dt) {
    if (paused || !dt.isFinite || dt <= 0) return;
    if (countdown > 0) {
      if (dt < countdown) {
        countdown -= dt;
        return;
      }
      dt -= countdown;
      countdown = 0;
    }
    round.advance(dt);
  }
}
