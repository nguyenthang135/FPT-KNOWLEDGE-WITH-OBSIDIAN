import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The official FPT logo asset, kept at its original 1504:925 aspect ratio.
class FptLogoMark extends StatelessWidget {
  const FptLogoMark({super.key, this.height = 36});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * 1.626,
      height: height,
      child: Image.asset(
        'img/fpt-logo-official.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'FPT',
      ),
    );
  }
}

class FptBrand extends StatelessWidget {
  const FptBrand({super.key, this.logoHeight = 32, this.showSubtitle = true});

  final double logoHeight;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FptLogoMark(height: logoHeight),
        SizedBox(width: logoHeight * .34),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Knowledge',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showSubtitle)
              const Text(
                'Second Brain',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
          ],
        ),
      ],
    );
  }
}
