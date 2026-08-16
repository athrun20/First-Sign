import 'package:flutter/material.dart';

/// Canonical FirstSign mark: navy square, white F, cyan S.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 40,
    this.radius = 12,
  });

  static const assetPath = 'assets/branding/firstsign_logo.png';
  static const navy = Color(0xFF0B1B2B);

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: navy,
          alignment: Alignment.center,
          child: Text(
            'F',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.42,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ),
    );
  }
}
