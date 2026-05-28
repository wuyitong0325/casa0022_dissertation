import 'package:flutter/material.dart';

import '../models/detection_event.dart';

class DetectionCelebrationOverlay extends StatefulWidget {
  final DetectionEvent event;
  final VoidCallback onFinished;

  const DetectionCelebrationOverlay({
    super.key,
    required this.event,
    required this.onFinished,
  });

  @override
  State<DetectionCelebrationOverlay> createState() =>
      _DetectionCelebrationOverlayState();
}

class _DetectionCelebrationOverlayState
    extends State<DetectionCelebrationOverlay> with TickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _backgroundOpacity;
  late final Animation<double> _creatureScale;
  late final Animation<double> _creatureOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1850),
    );

    _backgroundOpacity = Tween<double>(begin: 0.0, end: 0.82).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
      ),
    );

    _creatureScale = Tween<double>(begin: 0.18, end: 5.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.58, curve: Curves.easeOutBack),
      ),
    );

    _creatureOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.50, 0.78, curve: Curves.easeIn),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.56, 0.90, curve: Curves.easeOut),
      ),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.38),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.56, 0.95, curve: Curves.easeOutBack),
      ),
    );

    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.68, 1.0, curve: Curves.elasticOut),
      ),
    );

    _controller.forward().whenComplete(() async {
      await Future.delayed(const Duration(milliseconds: 650));
      if (mounted) {
        widget.onFinished();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isBat = widget.event.isBat;
    final emoji = isBat ? '🦇' : '🐦';
    final title = isBat ? 'BAT DETECTED!' : 'BIRD DETECTED!';
    final subtitle = widget.event.commonName;
    final accent = isBat ? const Color(0xFFB78CFF) : const Color(0xFF69E68B);
    final glow = isBat ? const Color(0xFF7B4DFF) : const Color(0xFF23C45E);

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            children: [
              Container(
                color: Colors.black.withOpacity(_backgroundOpacity.value),
              ),

              Center(
                child: Opacity(
                  opacity: _creatureOpacity.value.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: _creatureScale.value,
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 82),
                    ),
                  ),
                ),
              ),

              Center(
                child: FadeTransition(
                  opacity: _textOpacity,
                  child: SlideTransition(
                    position: _textSlide,
                    child: Transform.scale(
                      scale: _pulseScale.value,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: accent.withOpacity(0.85),
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: glow.withOpacity(0.55),
                              blurRadius: 38,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              emoji,
                              style: const TextStyle(fontSize: 54),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: accent,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.event.confidenceText,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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