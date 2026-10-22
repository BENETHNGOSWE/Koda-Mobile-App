import 'package:flutter/material.dart';
import 'package:kodastock/core/utils/extensions.dart';

/// Wraps a page body in the dashboard's soft emerald top glow.
/// Light mode only; in dark mode the child is returned unchanged.
class AmbientTopGlow extends StatelessWidget {
  final Widget child;

  const AmbientTopGlow({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final glow = context.ambientTopGlow;
    if (glow == null) return child;
    return DecoratedBox(decoration: glow, child: child);
  }
}
