import 'package:flutter/material.dart';

/// White corner brackets around the area where the cover should go.
class ViewfinderFrame extends StatelessWidget {
  const ViewfinderFrame({super.key, required this.child, this.inset = 0});

  final Widget child;

  /// Gap between the brackets and [child].
  final double inset;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: const _CornerPainter(),
      child: Padding(padding: EdgeInsets.all(inset), child: child),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final length = size.shortestSide * 0.12;
    const r = 8.0;
    final w = size.width;
    final h = size.height;

    final corners = [
      Path()
        ..moveTo(0, length)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..lineTo(length, 0),
      Path()
        ..moveTo(w - length, 0)
        ..lineTo(w - r, 0)
        ..quadraticBezierTo(w, 0, w, r)
        ..lineTo(w, length),
      Path()
        ..moveTo(0, h - length)
        ..lineTo(0, h - r)
        ..quadraticBezierTo(0, h, r, h)
        ..lineTo(length, h),
      Path()
        ..moveTo(w - length, h)
        ..lineTo(w - r, h)
        ..quadraticBezierTo(w, h, w, h - r)
        ..lineTo(w, h - length),
    ];
    for (final corner in corners) {
      canvas.drawPath(corner, paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}
