import 'dart:ui';
import 'package:flame/game.dart';
import 'round.dart';
import 'shared_round.dart';

class FlightGame extends FlameGame {
  FlightGame({required this.onFinished, this.shared});
  final SharedRound? shared;
  final void Function(int score) onFinished;
  final session = PracticeSession();
  Round get round => shared?.round ?? session.round;
  double get countdown => shared?.countdown ?? session.countdown;
  bool reported = false;
  void flap() {
    if (shared != null) { shared!.flap(); } else { session.flap(); }
  }

  void suspendPractice() {
    session.pause();
    pauseEngine();
  }
  void resumePractice() {
    session.resume();
    resumeEngine();
  }

  @override
  Color backgroundColor() => const Color(0xFF19182D);
  @override
  void update(double dt) {
    super.update(dt);
    if (shared != null) { shared!.advance(); } else { session.advance(dt); }
    if (round.finished && shared?.aborted != true && !reported) {
      reported = true;
      onFinished(round.score);
    }
  }

  void label(Canvas canvas, String text, double x, double y, double fontSize) {
    final builder =
        ParagraphBuilder(ParagraphStyle(fontSize: fontSize))
          ..pushStyle(TextStyle(color: const Color(0xFFFFFFFF)))
          ..addText(text);
    final paragraph =
        builder.build()..layout(ParagraphConstraints(width: size.x));
    canvas.drawParagraph(paragraph, Offset(x, y));
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final w = size.x, h = size.y;
    if (w <= 0 || h <= 0) return;
    final paint = Paint();
    for (var i = 0; i < 30; i++) {
      paint.color = const Color(0xFF45415E);
      canvas.drawCircle(Offset((i * 79.0) % w, (i * 137.0) % h), 2, paint);
    }
    paint.color = const Color(0xFFB8A2FF);
    for (final gate in round.gates) {
      final top = (gate.center - Round.halfGap) * h;
      final bottom = (gate.center + Round.halfGap) * h;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(gate.x * w, 0, Round.gateWidth * w, top),
          const Radius.circular(12),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(gate.x * w, bottom, Round.gateWidth * w, h - bottom),
          const Radius.circular(12),
        ),
        paint,
      );
    }
    final center = Offset(Round.birdX * w, round.y * h);
    paint.color =
        round.cooldown > 0 ? const Color(0xFF8E778A) : const Color(0xFFFFB49C);
    // Ellipse matches the normalized collision extents in both dimensions.
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: Round.radius * w * 2,
        height: Round.radius * h * 2,
      ),
      paint,
    );
    paint.color = const Color(0xFF211B32);
    canvas.drawCircle(center + Offset(w * 0.009, -h * 0.007), 2.5, paint);
    label(canvas, 'SKOR  ${round.score}', 20, 20, 19);
    label(
      canvas,
      '${(Round.duration - round.elapsed).ceil()} sn',
      w - 82,
      20,
      19,
    );
    if (countdown > 0)
      label(canvas, '${countdown.ceil()}', w / 2 - 15, h / 2, 52);
    if (round.cooldown > 0)
      label(canvas, 'Tekrar uç!', w / 2 - 65, h / 2 + 70, 22);
  }
}
