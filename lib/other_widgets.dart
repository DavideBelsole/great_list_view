library other_widgets;

import 'package:flutter/material.dart';

/// Animated arrow button.
class ArrowButton extends StatefulWidget {
  final bool expanded;
  final void Function(bool expanded)? onTap;
  final Duration duration;
  final Curve curve;
  final Icon icon;
  final double turns;

  ArrowButton({
    Key? key,
    this.expanded = false,
    this.onTap,
    this.curve = Curves.fastOutSlowIn,
    this.duration = const Duration(milliseconds: 300),
    this.icon = const Icon(Icons.keyboard_arrow_down),
    this.turns = 0.5,
  }) : super(key: key);

  @override
  _ArrowButtonState createState() => _ArrowButtonState();
}

class _ArrowButtonState extends State<ArrowButton>
    with SingleTickerProviderStateMixin {
  late Animation<double> _animation;
  AnimationController? _controller;
  bool _expanded = false;

  @override
  void didUpdateWidget(ArrowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.curve != oldWidget.curve ||
        widget.duration != oldWidget.duration ||
        widget.icon != oldWidget.icon ||
        widget.turns != oldWidget.turns) {
      _controller?.dispose();
      _initAnimation();
    }
    if (widget.expanded != _expanded) {
      _expanded = widget.expanded;
      _animate();
    }
  }

  void _animate() {
    if (_expanded) {
      _controller!.forward();
    } else {
      _controller!.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.expanded;
    _initAnimation();
  }

  void _initAnimation() {
    _controller = AnimationController(vsync: this, duration: widget.duration);
    Animation<double> curve =
        CurvedAnimation(parent: _controller!, curve: widget.curve);
    _animation = Tween(begin: 0.0, end: widget.turns).animate(curve);
    if (_expanded) _controller!.value = 1.0;
  }

  @override
  void dispose() {
    _controller!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        setState(() {
          _expanded = !_expanded;
          _animate();
          if (widget.onTap != null) widget.onTap!(_expanded);
        });
      },
      icon: RotationTransition(
        turns: _animation,
        child: widget.icon,
      ),
    );
  }
}
