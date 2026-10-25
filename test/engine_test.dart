import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/game/engine.dart';

void main() {
  final vectors = jsonDecode(File('tool/game-tests/vectors.json').readAsStringSync()) as List;
  for (final vector in vectors) {
    test('JS/Dart full-state parity ${vector['seed']} ${vector['mode']}', () {
      final engine = GameEngine(vector['seed'] as int);
      final inputs = Set<int>.from(vector['inputs'] as List);
      for (final expected in vector['checkpoints'] as List) {
        while (engine.tick < expected['tick']) {
          engine.step(flap: inputs.contains(engine.tick));
        }
        expect(engine.snapshot(), expected);
      }
      final end = engine.snapshot();
      engine.step(flap: true);
      expect(engine.snapshot(), end);
    });
  }
  test('seed bounds', () {
    expect(() => GameEngine(-1), throwsRangeError);
    expect(() => GameEngine(4294967296), throwsRangeError);
  });
}
