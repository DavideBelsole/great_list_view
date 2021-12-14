part of 'core.dart';

abstract class _Animation {
  const _Animation();

  Animation<double> get animation;
  double get time;

  bool get isWaitingAtBeginning =>
      time == 0.0 && animation.status == AnimationStatus.dismissed;
  bool get isWaitingAtEnd =>
      time == 1.0 && animation.status == AnimationStatus.completed;

  void attachTo(_AnimatedInterval interval) {}
  void detachFrom(_AnimatedInterval interval) {}
  void dispose() {}
}

class _CompletedAnimation extends _Animation {
  const _CompletedAnimation();

  @override
  Animation<double> get animation => kAlwaysCompleteAnimation;

  @override
  double get time => 1.0;
}

class _DismissedAnimation extends _Animation {
  const _DismissedAnimation();

  @override
  Animation<double> get animation => kAlwaysDismissedAnimation;

  @override
  double get time => 0.0;
}

class _ControlledAnimation extends _Animation with ChangeNotifier {
  _ControlledAnimation(
      TickerProvider vsync, Animatable<double> animatable, Duration duration,
      {double startTime = 0.0, this.onDispose})
      : assert(startTime >= 0.0 && startTime <= 1.0),
        _controller = AnimationController(
            value: startTime, vsync: vsync, duration: duration) {
    _animation = _controller.drive(animatable);
  }

  final AnimationController _controller;
  final intervals = <_AnimatedInterval>{};
  final void Function(_ControlledAnimation a)? onDispose;

  bool _disposed = false;
  late Animation<double> _animation;

  @override
  Animation<double> get animation => _animation;

  @override
  double get time => _controller.value;

  double get value => animation.value;

  @override
  void attachTo(_AnimatedInterval interval) {
    assert(_debugAssertNotDisposed());
    assert(!intervals.contains(interval));
    intervals.add(interval);
  }

  @override
  void detachFrom(_AnimatedInterval interval) {
    assert(_debugAssertNotDisposed());
    assert(intervals.contains(interval));
    intervals.remove(interval);
    if (intervals.isEmpty) {
      dispose();
    }
  }

  @override
  void dispose() {
    assert(_debugAssertNotDisposed());
    assert(intervals.isEmpty);
    _controller.dispose();
    _disposed = true;
    super.dispose();
    onDispose?.call(this);
  }

  void start() {
    assert(_debugAssertNotDisposed());
    _controller.forward().whenComplete(_onCompleted);
  }

  void stop() {
    assert(_debugAssertNotDisposed());
    _controller.stop();
  }

  void reset() {
    assert(_debugAssertNotDisposed());
    _controller.value = 0.0;
  }

  void complete() {
    assert(_debugAssertNotDisposed());
    _controller.value = 1.0;
    Future.microtask(_onCompleted);
  }

  void _onCompleted() {
    if (!_disposed) notifyListeners();
  }

  bool _debugAssertNotDisposed() {
    assert(() {
      if (_disposed) {
        throw FlutterError(
          'A $runtimeType was used after being disposed.\n'
          'Once you have called dispose() on a $runtimeType, it can no longer be used.',
        );
      }
      return true;
    }());
    return true;
  }

  @override
  String toString() =>
      'attachedTo: $intervals, time: $time, value: $value${_disposed ? ' DISPOSED' : ''}';
}
