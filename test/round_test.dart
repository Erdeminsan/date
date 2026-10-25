import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/game/round.dart';

void main() {
  test('Round ends once, at 45 seconds', () {
    final r = Round();
    r.advance(46);
    expect(r.finished, isTrue);
    expect(r.elapsed, 45);
    final score = r.score;
    r.advance(10);
    expect(r.score, score);
  });
  test('Identical input at different frame rates gives same outcome', () {
    final a = Round(seed: 12), b = Round(seed: 12);
    for (var i = 0; i < 600; i++) {
      if (i % 12 == 0) {
        a.flap();
        b.flap();
      }
      a.advance(1 / 30);
      b.advance(1 / 60);
      b.advance(1 / 60);
    }
    expect(a.score, b.score);
    expect(a.hits, b.hits);
    expect(a.y, closeTo(b.y, 0.0001));
  });
  test('A collision resets the bird and keeps the clock running', () {
    final r = Round();
    r.advance(1);
    expect(r.hits, greaterThan(0));
    expect(r.elapsed, closeTo(1, 0.02));
    expect(r.score, 0);
  });
  test('Passing one obstacle scores once', () {
    final r = Round();
    r.spawnClock = 10;
    r.gates.add(Gate(0.07, 0.5));
    r.advance(1 / 60);
    expect(r.score, 1);
    r.advance(1 / 60);
    expect(r.score, 1);
  });
}
