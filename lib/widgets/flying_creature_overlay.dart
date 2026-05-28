import 'package:flutter/material.dart';

import '../models/detection_event.dart';

class FlyingCreatureOverlay extends StatefulWidget {
  final DetectionEvent? event;
  final int trigger;

  const FlyingCreatureOverlay({
    super.key,
    required this.event,
    required this.trigger,
  });

  @override
  State<FlyingCreatureOverlay> createState() => _FlyingCreatureOverlayState();
}

class _FlyingCreatureOverlayState extends State<FlyingCreatureOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  DetectionEvent? _shownEvent;

  @override
  void initState() {
    super.initState();

    _shownEvent = widget.event;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    if (_shownEvent != null) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant FlyingCreatureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.event != null && widget.trigger != oldWidget.trigger) {
      _shownEvent = widget.event;
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shownEvent == null) return const SizedBox.shrink();

    final emoji = _shownEvent!.isBat ? '🦇' : '🐦';

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          final width = MediaQuery.of(context).size.width;

          final opacity = _controller.value < 0.86
              ? 1.0
              : (1.0 - _controller.value) * 7;

          return Positioned(
            left: -80 + width * t,
            top: 110 + 60 * (1 - (2 * t - 1).abs()),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: _shownEvent!.isBat ? -0.25 + 0.5 * t : 0.2 - 0.4 * t,
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 64),
                ),
              ),
            ),
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