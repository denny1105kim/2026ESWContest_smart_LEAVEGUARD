import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

class StatusTag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusTag(this.label, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Palette.soft(color), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 5)],
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
