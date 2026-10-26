import 'package:flutter/material.dart';

import '../../app/models.dart';

class Avatar extends StatelessWidget {
  final User user;
  final double size;

  const Avatar(this.user, {super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(user.color, Colors.white, 0.18)!, user.color],
        ),
      ),
      child: Text(
        user.initial,
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: Colors.white, height: 1),
      ),
    );
  }
}
