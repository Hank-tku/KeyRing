import 'package:flutter/material.dart';

/// A preview widget to visualize the new app icon design
/// This matches the updated SVG icon with teal theme
class AppIconPreview extends StatelessWidget {
  final double size;

  const AppIconPreview({super.key, this.size = 200});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: AppIconPainter());
  }
}

class AppIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 1024;

    // Background rounded rectangle
    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [Color(0xFF121A2E), Color(0xFF1E293B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(226 * scale),
    );
    canvas.drawRRect(bgRect, bgPaint);

    // Shield path
    final shieldPath = Path();
    shieldPath.moveTo(512 * scale, 200 * scale);
    shieldPath.lineTo(800 * scale, 280 * scale);
    shieldPath.lineTo(800 * scale, 520 * scale);
    shieldPath.quadraticBezierTo(
      800 * scale,
      680 * scale,
      512 * scale,
      840 * scale,
    );
    shieldPath.quadraticBezierTo(
      224 * scale,
      680 * scale,
      224 * scale,
      520 * scale,
    );
    shieldPath.lineTo(224 * scale, 280 * scale);
    shieldPath.close();

    // Shield gradient
    final shieldPaint = Paint()
      ..shader =
          LinearGradient(
            colors: [Color(0xFF2DD4BF), Color(0xFF14B8A6)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(
            Rect.fromLTWH(224 * scale, 200 * scale, 576 * scale, 640 * scale),
          );

    canvas.drawPath(shieldPath, shieldPaint);

    // Shield border
    final shieldBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale;
    canvas.drawPath(shieldPath, shieldBorderPaint);

    // Lock body
    final lockRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(432 * scale, 420 * scale, 160 * scale, 180 * scale),
      Radius.circular(24 * scale),
    );

    final lockPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white, Color(0xFFE0F2FE)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(lockRect.outerRect);

    canvas.drawRRect(lockRect, lockPaint);

    // Lock body border
    final lockBorderPaint = Paint()
      ..color = Color(0xFF2DD4BF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * scale;
    canvas.drawRRect(lockRect, lockBorderPaint);

    // Lock shackle
    final shacklePath = Path();
    shacklePath.moveTo(440 * scale, 420 * scale);
    shacklePath.lineTo(440 * scale, 370 * scale);
    shacklePath.quadraticBezierTo(
      440 * scale,
      320 * scale,
      512 * scale,
      290 * scale,
    );
    shacklePath.quadraticBezierTo(
      584 * scale,
      320 * scale,
      584 * scale,
      370 * scale,
    );
    shacklePath.lineTo(584 * scale, 420 * scale);

    final shacklePaint = Paint()
      ..shader =
          LinearGradient(
            colors: [Colors.white, Color(0xFFE0F2FE)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(
            Rect.fromLTWH(440 * scale, 290 * scale, 144 * scale, 130 * scale),
          )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28 * scale
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(shacklePath, shacklePaint);

    // Keyhole - circle
    final keyholePaint = Paint()..color = Color(0xFF2DD4BF);
    canvas.drawCircle(
      Offset(512 * scale, 490 * scale),
      20 * scale,
      keyholePaint,
    );

    // Keyhole - slot
    final keyholeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(502 * scale, 490 * scale, 20 * scale, 50 * scale),
      Radius.circular(10 * scale),
    );
    canvas.drawRRect(keyholeRect, keyholePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A preview widget for the splash screen logo
class SplashLogoPreview extends StatelessWidget {
  final double size;
  final bool darkMode;

  const SplashLogoPreview({super.key, this.size = 200, this.darkMode = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 1.2,
      height: size * 1.5,
      color: darkMode ? Color(0xFF121A2E) : Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: SplashLogoPainter()),
          SizedBox(height: size * 0.1),
          Text(
            'KeyRing',
            style: TextStyle(
              fontSize: size * 0.18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2DD4BF),
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class SplashLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 512;

    // Shield path
    final shieldPath = Path();
    shieldPath.moveTo(256 * scale, 60 * scale);
    shieldPath.lineTo(440 * scale, 120 * scale);
    shieldPath.lineTo(440 * scale, 280 * scale);
    shieldPath.quadraticBezierTo(
      440 * scale,
      370 * scale,
      256 * scale,
      470 * scale,
    );
    shieldPath.quadraticBezierTo(
      72 * scale,
      370 * scale,
      72 * scale,
      280 * scale,
    );
    shieldPath.lineTo(72 * scale, 120 * scale);
    shieldPath.close();

    // Shield gradient
    final shieldPaint = Paint()
      ..shader =
          LinearGradient(
            colors: [Color(0xFF2DD4BF), Color(0xFF14B8A6)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(
            Rect.fromLTWH(72 * scale, 60 * scale, 368 * scale, 410 * scale),
          );

    canvas.drawPath(shieldPath, shieldPaint);

    // Lock body
    final lockRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(206 * scale, 210 * scale, 100 * scale, 120 * scale),
      Radius.circular(16 * scale),
    );

    final lockPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white, Color(0xFFE0F2FE)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(lockRect.outerRect);

    canvas.drawRRect(lockRect, lockPaint);

    // Lock shackle
    final shacklePath = Path();
    shacklePath.moveTo(214 * scale, 210 * scale);
    shacklePath.lineTo(214 * scale, 180 * scale);
    shacklePath.quadraticBezierTo(
      214 * scale,
      150 * scale,
      256 * scale,
      134 * scale,
    );
    shacklePath.quadraticBezierTo(
      298 * scale,
      150 * scale,
      298 * scale,
      180 * scale,
    );
    shacklePath.lineTo(298 * scale, 210 * scale);

    final shacklePaint = Paint()
      ..shader =
          LinearGradient(
            colors: [Colors.white, Color(0xFFE0F2FE)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(
            Rect.fromLTWH(214 * scale, 134 * scale, 84 * scale, 76 * scale),
          )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18 * scale
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(shacklePath, shacklePaint);

    // Keyhole
    final keyholePaint = Paint()..color = Color(0xFF2DD4BF);
    canvas.drawCircle(
      Offset(256 * scale, 255 * scale),
      13 * scale,
      keyholePaint,
    );

    final keyholeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(249 * scale, 255 * scale, 14 * scale, 35 * scale),
      Radius.circular(7 * scale),
    );
    canvas.drawRRect(keyholeRect, keyholePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
