/// Sends immutable one-second intervals; an uncertain response retries the same
/// sequence/body. Call regularly while foreground, including the final flush.
class InputSender {
  InputSender(this.send);
  static const protocol = 'sky-hop-input-v1';
  final Future<void> Function(int sequence, List<int> flaps) send;
  int _next = 0;
  List<int>? _pending;
  bool _busy = false, _cancelled = false;
  bool get complete => _next == 45;
  bool get cancelled => _cancelled;
  int get nextSequence => _next;
  void cancel() { _cancelled = true; }

  Future<void> pump({required int completedTick, required List<int> inputs,
    required int elapsedMs}) async {
    if (_cancelled || complete || _busy) return;
    if (elapsedMs > _next * 1000 + 5000) { cancel(); return; }
    if (completedTick < (_next + 1) * 120) return;
    _pending ??= List<int>.unmodifiable(inputs.where((t) => t >= _next * 120 && t < (_next + 1) * 120));
    _busy = true;
    try {
      await send(_next, _pending!).timeout(const Duration(seconds: 2));
      if (!_cancelled) { _next++; _pending = null; }
    } catch (_) {
      // Retry on a later pump, bounded by the interval's receipt deadline.
    } finally { _busy = false; }
  }
}
