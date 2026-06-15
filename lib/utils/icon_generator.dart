import 'package:flutter/material.dart';

/// A widget that generates the app icon design
/// This can be used to preview the icon or generate it programmatically
class AppIconGenerator extends StatelessWidget {
  const AppIconGenerator({super.key, this.size = 1024});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: AppIconPainter());
  }
}

class AppIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;
    final double scale = size.width / 1024;

    // Background
    final Paint backgroundPaint = Paint()
      ..color = const Color(0xFF1677FF)
      ..style = PaintingStyle.fill;

    final RRect backgroundRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(200 * scale),
    );
    canvas.drawRRect(backgroundRect, backgroundPaint);

    // Shield path
    final Path shieldPath = Path();
    shieldPath.moveTo(
      centerX + (512 - 512) * scale,
      centerY + (200 - 512) * scale,
    );
    shieldPath.lineTo(
      centerX + (800 - 512) * scale,
      centerY + (280 - 512) * scale,
    );
    shieldPath.lineTo(
      centerX + (800 - 512) * scale,
      centerY + (520 - 512) * scale,
    );
    shieldPath.quadraticBezierTo(
      centerX + (800 - 512) * scale,
      centerY + (680 - 512) * scale,
      centerX + (680 - 512) * scale,
      centerY + (800 - 512) * scale,
    );
    shieldPath.quadraticBezierTo(
      centerX + (512 - 512) * scale,
      centerY + (840 - 512) * scale,
      centerX + (344 - 512) * scale,
      centerY + (800 - 512) * scale,
    );
    shieldPath.quadraticBezierTo(
      centerX + (224 - 512) * scale,
      centerY + (680 - 512) * scale,
      centerX + (224 - 512) * scale,
      centerY + (520 - 512) * scale,
    );
    shieldPath.lineTo(
      centerX + (224 - 512) * scale,
      centerY + (280 - 512) * scale,
    );
    shieldPath.close();

    // Shield fill
    final Paint shieldPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;
    canvas.drawPath(shieldPath, shieldPaint);

    // Lock body
    final Paint lockPaint = Paint()
      ..color = const Color(0xFF1677FF)
      ..style = PaintingStyle.fill;

    final double lockWidth = 120 * scale;
    final double lockHeight = 140 * scale;
    final double lockX = centerX - lockWidth / 2;
    final double lockY = centerY - lockHeight / 2;

    final RRect lockRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(lockX, lockY, lockWidth, lockHeight),
      Radius.circular(20 * scale),
    );
    canvas.drawRRect(lockRect, lockPaint);

    // Lock shackle
    final Paint shacklePaint = Paint()
      ..color = const Color(0xFF1677FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24 * scale
      ..strokeCap = StrokeCap.round;

    final Path shacklePath = Path();
    shacklePath.moveTo(lockX, lockY);
    shacklePath.lineTo(lockX, lockY - 40 * scale);
    shacklePath.quadraticBezierTo(
      lockX,
      lockY - 80 * scale,
      lockX + 40 * scale,
      lockY - 80 * scale,
    );
    shacklePath.quadraticBezierTo(
      lockX + 80 * scale,
      lockY - 80 * scale,
      lockX + 80 * scale,
      lockY - 40 * scale,
    );
    shacklePath.lineTo(lockX + 80 * scale, lockY);

    canvas.drawPath(shacklePath, shacklePaint);

    // Keyhole
    final Paint keyholePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Circle part
    canvas.drawCircle(
      Offset(centerX, centerY + 20 * scale),
      20 * scale,
      keyholePaint,
    );

    // Rectangle part
    final RRect keyholeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        centerX - 12 * scale,
        centerY + 20 * scale,
        24 * scale,
        50 * scale,
      ),
      Radius.circular(12 * scale),
    );
    canvas.drawRRect(keyholeRect, keyholePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
