import 'dart:math';

import 'package:flutter/material.dart';

class SoundWaveWidget extends StatefulWidget {
  final bool active;
  final double intensity;

  const SoundWaveWidget({
    super.key,
    this.active = true,
    this.intensity = 1.0,
  });

  @override
  State<SoundWaveWidget> createState() => _SoundWaveWidgetState();
}

class _SoundWaveWidgetState extends State<SoundWaveWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(24, (index) {
              final phase = _controller.value * 2 * pi;
              final wave = sin(phase + index * 0.45).abs();
              final height = 12 + wave * 46 * widget.intensity;

              return Container(
                width: 5,
                height: widget.active ? height : 10,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: widget.active
                      ? const Color(0xFF4E8F5B)
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}