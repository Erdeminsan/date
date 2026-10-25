import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/game/shared_round.dart';
import 'package:playmatch/game/engine.dart';

void main() {
  final now = DateTime.utc(2026);
  test('server schedule controls countdown and preserves deterministic replay', () {
    var elapsed = Duration.zero;
    final r = SharedRound(seed: 42, startsAt: now.add(const Duration(seconds: 5)), serverNow: now,
      roundTrip: Duration.zero, elapsed: () => elapsed);
    r.flap(); expect(r.round.inputs, isEmpty); expect(r.countdown, 5);
    for (var i = 1; i <= 500; i++) {
      elapsed = Duration(milliseconds: i*100);
      r.advance();
      if (i%4 == 0) r.flap();
    }
    expect(r.round.engine.tick, 5400); expect(r.aborted, isFalse);
    final replay = GameEngine(42), inputs = r.round.inputs.toSet();
    while (replay.tick < 5400) { replay.step(flap: inputs.contains(replay.tick)); }
    expect(replay.snapshot(), r.round.engine.snapshot());
  });
  test('separate clients catch up to the same server tick with equal estimated time', () {
    var aTime = Duration.zero, bTime = Duration.zero;
    final a = SharedRound(seed: 9, startsAt: now, serverNow: now, roundTrip: Duration.zero, elapsed: () => aTime);
    final b = SharedRound(seed: 9, startsAt: now, serverNow: now, roundTrip: Duration.zero, elapsed: () => bTime);
    for (var i=1; i<=120; i++) {
      aTime=Duration(microseconds: i*1000000~/120); a.advance();
      if (i%4==0) { bTime=aTime; b.advance(); }
    }
    expect(a.round.engine.snapshot(), b.round.engine.snapshot());
  });
  test('late or slow joins and foreground stalls abort without completion', () {
    final late = SharedRound(seed: 1, startsAt: now, serverNow: now.add(const Duration(seconds:3)),roundTrip:Duration.zero);
    final slow = SharedRound(seed: 1, startsAt: now, serverNow: now,roundTrip:const Duration(seconds:3));
    expect(late.aborted,isTrue); expect(slow.aborted,isTrue);
    var time = Duration.zero;
    final r = SharedRound(seed:1,startsAt:now,serverNow:now,roundTrip:Duration.zero,elapsed:()=>time);
    time=const Duration(seconds:6);r.advance();expect(r.aborted,isTrue);expect(r.round.finished,isFalse);
    r.flap();expect(r.round.inputs,isEmpty);
  });
  test('round trip midpoint adjusts only the initial monotonic clock anchor', () {
    final r=SharedRound(seed:1,startsAt:now.add(const Duration(seconds:5)),serverNow:now,roundTrip:const Duration(seconds:2),elapsed:()=>Duration.zero);
    expect(r.countdown,4);
    r.cancel();r.advance();expect(r.round.engine.tick,0);
  });
}
