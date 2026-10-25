import 'dart:math';
import 'round.dart';

/// Foreground shared-round clock; local practice pause rules do not apply.
class SharedRound {
  SharedRound({required int seed, required DateTime startsAt, required DateTime serverNow,
    required Duration roundTrip, Duration Function()? elapsed})
    : round = Round(seed: seed), _startsAt = startsAt,
      _anchor = serverNow.add(Duration(microseconds: roundTrip.inMicroseconds ~/ 2)),
      _elapsed = elapsed {
    if (roundTrip > const Duration(seconds: 2) || roundTrip.isNegative ||
        _anchor.difference(_startsAt) > const Duration(seconds: 2)) {
      aborted = true;
    }
  }
  final Round round;
  final DateTime _startsAt, _anchor;
  final Duration Function()? _elapsed;
  final Stopwatch _watch = Stopwatch()..start();
  Duration _last = Duration.zero;
  bool aborted = false;
  Duration get elapsed => _elapsed?.call() ?? _watch.elapsed;
  DateTime get estimatedNow => _anchor.add(elapsed);
  double get countdown => max(0, _startsAt.difference(estimatedNow).inMicroseconds / 1000000);
  void cancel() { aborted = true; round.clearPendingInput(); }
  void advance() {
    if (aborted || round.finished) return;
    final current = elapsed;
    if (current < _last || current - _last > const Duration(seconds: 5)) { cancel(); return; }
    _last = current;
    final target = (_anchor.add(current).difference(_startsAt).inMicroseconds * 120 ~/ 1000000).clamp(0,5400);
    if (target > round.engine.tick) round.advance((target - round.engine.tick) / 120);
  }
  void flap() {
    advance();
    if (!aborted && countdown <= 0) round.flap();
  }
}
