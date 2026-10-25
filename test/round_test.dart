import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/game/round.dart';
import 'package:playmatch/game/engine.dart';

void main() {
  test('Round ends exactly at 5400 ticks and never changes afterwards', () {
    final r = Round();
    r.advance(46);
    expect(r.finished, isTrue);
    expect(r.elapsed, 45);
    final state = r.engine.snapshot();
    r.flap(); r.advance(10);
    expect(r.engine.snapshot(), state);
  });
  test('30/60/120 Hz input produces identical full state and replay', () {
    final rounds = [Round(seed: 12), Round(seed: 12), Round(seed: 12)];
    for (var i = 0; i < 1350; i++) {
      if (i % 12 == 0) { for (final r in rounds) { r.flap(); } }
      for (var j = 0; j < rounds.length; j++) {
        final frames = 1 << j;
        for (var frame = 0; frame < frames; frame++) { rounds[j].advance(1 / (30 * frames)); }
      }
    }
    final reference = rounds.first;
    for (final r in rounds) {
      expect(r.engine.snapshot(), reference.engine.snapshot());
      expect(r.inputs, reference.inputs);
    }
    final replay = GameEngine(12), inputs = reference.inputs.toSet();
    while (replay.tick < 5400) { replay.step(flap: inputs.contains(replay.tick)); }
    expect(replay.snapshot(), reference.engine.snapshot());
  });
  test('sub-tick taps coalesce and recording is immutable', () {
    final r = Round();
    r.flap(); r.flap(); r.advance(1 / 240);
    expect(r.inputs, isEmpty);
    r.advance(1 / 240);
    expect(r.inputs, [0]);
    expect(() => r.inputs.add(2), throwsUnsupportedError);
  });
  test('invalid frame deltas do not change state or discard input', () {
    final r = Round(); r.flap();
    for (final dt in [double.nan, double.infinity, -1.0, 0.0]) { r.advance(dt); }
    expect(r.engine.tick, 0);
    r.advance(1 / 120); expect(r.inputs, [0]);
  });
  test('countdown crossing keeps the remaining frame time', () {
    final s = PracticeSession(); s.flap(); s.advance(3.5);
    expect(s.countdown, 0); expect(s.round.engine.tick, 60);
    expect(s.round.inputs, isEmpty);
  });
  test('background pauses countdown and physics until explicit resume', () {
    final s = PracticeSession(); s.advance(1); s.pause(); s.advance(30);
    expect(s.countdown, 2);
    s.resume(); s.advance(2); s.flap(); s.pause(); s.flap(); s.advance(30);
    expect(s.round.engine.tick, 0);
    s.resume(); s.advance(1 / 120);
    expect(s.round.inputs, isEmpty);
    expect(s.round.engine.y, 500093);
  });
  test('large finite frame is bounded by terminal state', () {
    final s = PracticeSession(); s.advance(1e300);
    expect(s.round.engine.tick, 5400);
  });
}
