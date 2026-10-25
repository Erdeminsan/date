import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:playmatch/game/input_sender.dart';

void main() {
  test('sends only completed intervals, including empty heartbeats', () async {
    final sent = <List<int>>[];
    final sender = InputSender((seq, flaps) async { sent.add([seq, ...flaps]); });
    await sender.pump(completedTick: 119, inputs: [0, 119], elapsedMs: 999);
    expect(sent, isEmpty);
    await sender.pump(completedTick: 120, inputs: [0, 119, 120], elapsedMs: 1000);
    await sender.pump(completedTick: 240, inputs: [0, 119], elapsedMs: 2000);
    expect(sent, [[0, 0, 119], [1]]);
  });
  test('uncertain response retries identical immutable sequence and content', () async {
    final sent = <List<int>>[];
    var fail = true;
    final sender = InputSender((seq, flaps) async {
      expect(() => flaps.add(42), throwsUnsupportedError);
      sent.add([seq, ...flaps]);
      if (fail) { fail = false; throw StateError('lost response'); }
    });
    await sender.pump(completedTick: 120, inputs: [1], elapsedMs: 1000);
    expect(sender.nextSequence, 0);
    await sender.pump(completedTick: 240, inputs: [2, 121], elapsedMs: 2000);
    expect(sent, [[0, 1], [0, 1]]);
    expect(sender.nextSequence, 1);
  });
  test('overlapping pumps serialize requests and cancellation ignores late ack', () async {
    final ack = Completer<void>();
    var calls = 0;
    final sender = InputSender((seq, flaps) { calls++; return ack.future; });
    final pending = sender.pump(completedTick: 120, inputs: [], elapsedMs: 1000);
    await sender.pump(completedTick: 240, inputs: [], elapsedMs: 2000);
    expect(calls, 1);
    sender.cancel(); ack.complete(); await pending;
    expect(sender.nextSequence, 0);
    await sender.pump(completedTick: 240, inputs: [], elapsedMs: 2000);
    expect(calls, 1);
  });
  test('late interval cancels without posting retrospective history', () async {
    var calls = 0;
    final sender = InputSender((seq, flaps) async { calls++; });
    await sender.pump(completedTick: 720, inputs: [], elapsedMs: 5001);
    expect(sender.cancelled, isTrue); expect(calls, 0);
  });
  test('all 45 intervals must be acknowledged before completion', () async {
    final sequences = <int>[];
    final sender = InputSender((seq, flaps) async { sequences.add(seq); });
    for (var i = 1; i <= 45; i++) {
      expect(sender.complete, isFalse);
      await sender.pump(completedTick: i * 120, inputs: [], elapsedMs: i * 1000);
    }
    expect(sender.complete, isTrue);
    await sender.pump(completedTick: 5400, inputs: [], elapsedMs: 46000);
    expect(sequences, List.generate(45, (i) => i));
  });
  test('failed final flush remains incomplete and expires', () async {
    final sender = InputSender((seq, flaps) async { if (seq == 44) throw StateError('offline'); });
    for (var i = 1; i <= 45; i++) {
      await sender.pump(completedTick: i * 120, inputs: [], elapsedMs: i * 1000);
    }
    expect(sender.complete, isFalse);
    await sender.pump(completedTick: 5400, inputs: [], elapsedMs: 49001);
    expect(sender.cancelled, isTrue);
  });
}
