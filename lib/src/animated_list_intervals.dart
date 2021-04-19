import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

import 'animated_sliver_list.dart';

typedef AnimatedNullableIndexedWidgetBuilder = Widget? Function(
    BuildContext context, int index, AnimatedListBuildType buildType,
    [dynamic slot]);

typedef AnimatedListIntervalCreationCallback = AnimatedListInterval Function(
    int from,
    int newRemoveCount,
    int newInsertCount,
    IndexedWidgetBuilder? removeItemBuilder,
    [AnimatedListIntervalEventCallback? onDisposed]);

typedef AnimatedListAnimationItemBuilder = Widget Function(
    BuildContext context,
    IndexedWidgetBuilder? oldBuilder,
    int oldIndex,
    IndexedWidgetBuilder? newBuilder,
    int newIndex,
    Animation<double> animation);

IndexedWidgetBuilder? _shiftItemBuilder(
    final IndexedWidgetBuilder? builder, final int leading) {
  if (leading == 0 || builder == null) return builder;
  return (context, index) => builder.call(context, index + leading);
}

//---------------------------------------------------------------------------------------------
// AnimatedListIntervalList
//---------------------------------------------------------------------------------------------

/// Handles a list of [AnimatedListInterval].
/// All intervals are always kept sorted by its [AnimatedListInterval.index].
class AnimatedListIntervalList with IterableMixin<AnimatedListInterval> {
  final List<AnimatedListInterval> _list = [];

  /// Returns an iterator trough all intervals.
  @override
  Iterator<AnimatedListInterval> get iterator => _list.iterator;

  /// Returns the interval at the specified position.
  AnimatedListInterval operator [](int index) => _list[index];

  /// Search for the specified interval or its [AnimatedListInterval.index] and returns
  /// its position in the list.
  int indexOf(dynamic from) => _list.indexOfBinarySearch(from);

  /// Adds a new replacing interval.
  /// See [AnimatedListInterval]'s constructor for other details.
  /// This class will handle the entire life cycle of the new interval, adapting to
  /// any change of status by repositioning all its intervals correctly.
  AnimatedListInterval insertReplacingInterval(
      {required TickerProvider vsync,
      required AnimatedListAnimationSettings animationSettings,
      required int index,
      int insertCount = 0,
      int removeCount = 0,
      IndexedWidgetBuilder? removeItemBuilder,
      AnimatedListIntervalEventCallback? onResizingCompleted,
      AnimatedListIntervalEventCallback? onRemovingCompleted,
      AnimatedListIntervalEventCallback? onInsertingCompleted,
      AnimatedListIntervalEventCallback? onCompleted,
      AnimatedListIntervalEventCallback? onDisposed}) {
    var interval = AnimatedListInterval(
      vsync: vsync,
      animationSettings: animationSettings,
      index: index,
      insertCount: insertCount,
      removeCount: removeCount,
      removeItemBuilder: removeItemBuilder,
      onRemovingCompleted: (interval) {
        var i = indexOf(interval);
        assert(i >= 0);
        while (++i < length) {
          this[i]._index += 1 - interval.removeCount;
        }
        onRemovingCompleted?.call(interval);
      },
      onResizingCompleted: (interval) {
        var i = indexOf(interval);
        assert(i >= 0);
        while (++i < length) {
          this[i]._index += interval.insertCount - 1;
        }
        onResizingCompleted?.call(interval);
      },
      onInsertingCompleted: (interval) => onInsertingCompleted?.call(interval),
      onCompleted: (interval) {
        final i = indexOf(interval);
        assert(i >= 0);
        _list.removeAt(i);
        onCompleted?.call(interval);
      },
      onDisposed: onDisposed,
    );
    var i = _list.insertSorted(interval);
    if (interval.removeCount == 0) {
      while (++i < length) {
        this[i]._index++;
      }
    }
    return interval;
  }

  /// Adds a new changing interval.
  /// See [AnimatedListInterval.change] constructor for other details.
  /// This class will handle the entire life cycle of the new interval, adapting to
  /// any change of status by repositioning all its intervals correctly.
  AnimatedListInterval insertChangingInterval(
      {required TickerProvider vsync,
      required AnimatedListAnimationSettings animationSettings,
      required int index,
      required int changeCount,
      IndexedWidgetBuilder? removeItemBuilder,
      AnimatedListIntervalEventCallback? onChangingCompleted,
      AnimatedListIntervalEventCallback? onCompleted,
      AnimatedListIntervalEventCallback? onDisposed}) {
    var interval = AnimatedListInterval.change(
      vsync: vsync,
      animationSettings: animationSettings,
      index: index,
      changeCount: changeCount,
      removeItemBuilder: removeItemBuilder,
      onChangingCompleted: (interval) => onChangingCompleted?.call(interval),
      onCompleted: (interval) {
        final i = indexOf(interval);
        assert(i >= 0);
        _list.removeAt(i);
        onCompleted?.call(interval);
      },
      onDisposed: onDisposed,
    );
    _list.insertSorted(interval);
    return interval;
  }

  /// Adds a new reorder resizing interval.
  /// See [AnimatedListInterval.reorder] constructor for other details.
  /// This class will handle the entire life cycle of the new interval, adapting to
  /// any change of status by repositioning all its intervals correctly.
  AnimatedListInterval insertReorderingInterval(
      {required TickerProvider vsync,
      required AnimatedListAnimationSettings animationSettings,
      required int index,
      required double? size,
      required bool appearing,
      AnimatedListIntervalEventCallback? onResizingCompleted,
      AnimatedListIntervalEventCallback? onCompleted,
      AnimatedListIntervalEventCallback? onDisposed}) {
    var interval = AnimatedListInterval.reorder(
      vsync: vsync,
      animationSettings: animationSettings,
      index: index,
      size: size,
      appearing: appearing,
      onResizingCompleted: (interval) {
        var i = indexOf(interval);
        assert(i >= 0);
        while (++i < length) {
          this[i]._index--;
        }
        onResizingCompleted?.call(interval);
      },
      onCompleted: (interval) {
        final i = indexOf(interval);
        assert(i >= 0);
        _list.removeAt(i);
        onCompleted?.call(interval);
      },
      onDisposed: onDisposed,
    );
    var i = _list.insertSorted(interval);
    if (appearing) {
      while (++i < length) {
        this[i]._index++;
      }
    }
    return interval;
  }

  /// Returns the interval with the specified [AnimatedListInterval.index], if any,
  /// otherwise `null` is returned.
  AnimatedListInterval? intervalAt(int index) => _list.binarySearch(index);

  /// Calculates the difference between the actual length of the underlying list and
  /// the actual length of the [AnimatedSliverList] that is animating.
  /// For example, consider a list of 10 items; the user notifies an insertion
  /// of 5 elements somewhere. This sliver will start to animate with a resizing interval
  /// that occupies just one element. So, the sliver will count only 11 elements and
  /// this method will return -4.
  /// Only when the resizing interval becomes an inserting interval (or completes) this
  /// method will return 0 (ie no difference detected in the item count).
  int get itemCountAdjustment {
    var n = 0;
    for (final interval in _list) {
      if (interval.isInResizingState) {
        n += 1 - interval._insertCount;
      } else if (interval.isInRemovingState) {
        n += interval._removeCount - interval._insertCount;
      }
    }
    return n;
  }

  /// Start animations of those intervals that are still in waiting state.
  /// If [coordinate] is `true`, this method prioritizes the intervals in removal
  /// state first, then to those in resizing and changing state and finally
  /// to those in inserting state.
  void startAnimations(bool coordinate) {
    if (coordinate) {
      var state = 4;
      _list.forEach((i) {
        if (i.isInRemovingState) {
          state = min(state, 1);
        } else if (i.isInResizingState || i.isInChangingState) {
          state = min(state, 2);
        } else if (i.isInInsertingState) state = min(state, 3);
      });
      _list.forEach((i) {
        if (i.isInRemovingState && state == 1 ||
            (i.isInResizingState || i.isInChangingState) && state == 2 ||
            i.isInInsertingState && state == 3) i.startAnimation();
      });
    } else {
      _list.forEach((i) => i.startAnimation());
    }
  }

  /// Scan the list to find the interval below the specified [index].
  /// If the interval exists, the callback corresponding to its status will be invoked
  /// and `null` is returned.
  /// If the interval doesn't exist (ie it is a normal item), return a correction offset
  /// to add to the [index] to obtain the actual index of the underlying list.
  int? search(int index,
      {void Function(AnimatedListInterval)? removeFn,
      void Function(AnimatedListInterval)? insertFn,
      void Function(AnimatedListInterval)? changeFn,
      void Function(AnimatedListInterval)? resizeFn}) {
    var adj = 0;
    for (final interval in _list) {
      switch (interval.state) {
        case AnimatedListIntervalState.REMOVING:
          if (index >= interval.index) {
            if (index < (interval.index + interval.removeCount)) {
              removeFn?.call(interval);
              return null;
            } else {
              adj += interval.insertCount - interval.removeCount;
            }
          }
          break;
        case AnimatedListIntervalState.CHANGING:
          if (index >= interval.index) {
            if (index < (interval.index + interval.removeCount)) {
              changeFn?.call(interval);
              return null;
            } else {
              adj += interval.insertCount - interval.removeCount;
            }
          }
          break;
        case AnimatedListIntervalState.RESIZING:
          if (index == interval.index) {
            resizeFn?.call(interval);
            return null;
          } else if (index > interval.index) {
            adj += interval.insertCount - 1;
          }
          break;
        case AnimatedListIntervalState.INSERTING:
          if (index >= interval.index &&
              index < (interval.index + interval.insertCount)) {
            insertFn?.call(interval);
            return null;
          }
          break;
        default:
          throw 'Illegal state';
      }
    }
    return adj;
  }

  /// Optimize all its intervals, merging some or all of them if possibile.
  void optimize() {
    AnimatedListInterval? s, i;
    for (var j = length - 1; j >= 0; j--) {
      i = this[j];
      if (s != null) {
        if (AnimatedListInterval._canBeIntervalsMerged(i, s)) {
          final n = i.buildingItemCount + s.buildingItemCount;
          late int m;
          if (AnimatedListInterval._mergeIntervals(i, s)) {
            m = s.buildingItemCount;
            i.dispose();
            i = s;
            _list.removeAt(j);
          } else {
            m = i.buildingItemCount;
            s.dispose();
            _list.removeAt(j + 1);
          }
          if (n != m) {
            for (var k = j + 1; k < length; k++) {
              this[k]._index += m - n;
            }
          }
        }
      }
      s = i;
    }
  }

  /// Adapt an existing interval in order to comply with the new notification.
  int adjustInterval(
      AnimatedListInterval interval,
      int newRemoveCount,
      int newInsertCount,
      int leading,
      int trailing,
      AnimatedListAnimationBuilder animationBuilder,
      IndexedWidgetBuilder? removeItemBuilder,
      AnimatedListIntervalCreationCallback callback,
      bool changing) {
    switch (interval.state) {
      case AnimatedListIntervalState.REMOVING:
        interval._insertCount += newInsertCount - newRemoveCount;
        interval._toSize = (interval._insertCount == 0) ? 0.0 : null;
        break;
      case AnimatedListIntervalState.RESIZING:
        interval._insertCount += newInsertCount - newRemoveCount;
        return interval.resize() ? -1 : 0;
      case AnimatedListIntervalState.INSERTING:
        return _splitInterval(
          interval,
          leading,
          trailing,
          newRemoveCount,
          newInsertCount,
          removeItemBuilder,
          callback,
          (context, oldBuilder, oldIndex, newBuilder, newIndex, animation) {
            return animationBuilder.buildInserting(
                context, newBuilder!.call(context, newIndex), animation);
          },
        );
      case AnimatedListIntervalState.CHANGING:
        if (changing && interval.isWaiting) return 0;
        return _splitInterval(
          interval,
          leading,
          trailing,
          newRemoveCount,
          newInsertCount,
          removeItemBuilder,
          callback,
          (context, oldBuilder, oldIndex, newBuilder, newIndex, animation) {
            return animationBuilder.buildChanging(
                context,
                oldBuilder!.call(context, oldIndex),
                newBuilder!.call(context, newIndex),
                animation);
          },
        );
      default:
        break;
    }
    return 0;
  }

  // Splits eventually an existing interval in more sub intervals.
  int _splitInterval(
    final AnimatedListInterval interval,
    final int leading,
    final int trailing,
    final int newRemoveCount,
    final int newInsertCount,
    final IndexedWidgetBuilder? itemBuilder,
    final AnimatedListIntervalCreationCallback newIntervalBuilder,
    final AnimatedListAnimationItemBuilder animationItemBuilder,
  ) {
    assert(!interval.isReordering &&
        (interval.isInChangingState || interval.isInInsertingState));

    if (newRemoveCount == 0 && newInsertCount == 0) return 0;

    final from = interval._index + leading;

    final w = interval.isWaiting;

    final oldBuilder = interval._removeItemBuilder;

    final orphan = (!interval.isWaiting && newRemoveCount > 0)
        ? _AnimatedListAnimationController.clone(
            interval.vsync, interval._controller!)
        : null;
    var other = interval.split(leading, trailing);
    if (other != null) _list.insertSorted(other);

    var q = newIntervalBuilder.call(
      from,
      newRemoveCount,
      newInsertCount,
      newRemoveCount == 0
          ? null
          : (context, index) => animationItemBuilder.call(
              context,
              oldBuilder,
              index + leading,
              itemBuilder,
              index,
              orphan?.animation ?? kAlwaysDismissedAnimation),
      (disposedInterval) {
        orphan?.dispose();
      },
    );
    if (!w) q.startAnimation();

    return leading == 0 ? 0 : 1;
  }

  /// Completes all reorder resizing intervals when the reorder is complete.
  void finishReorder() {
    while (_list.isNotEmpty) {
      var interval = _list.first;
      assert(interval.isInResizingState && interval.isReordering);
      interval._toSize = 0.0;
      interval._onResizingCompleted();
    }
  }

  /// Removes all intervals.
  void clear() {
    _list.forEach((interval) => interval.dispose());
    _list.clear();
  }

  @override
  String toString() => _list.toString();

  String toDebugString() {
    var s = '';
    _list.forEach((interval) {
      if (s.isNotEmpty) s += '\n';
      s += interval.toDebugString();
    });
    return s;
  }
}

//---------------------------------------------------------------------------------------------
// AnimatedListInterval
//---------------------------------------------------------------------------------------------

/// A state of an interval.
enum AnimatedListIntervalState {
  /// The interval is removing its covered items from the list.
  REMOVING,

  /// The interval is resizing.
  RESIZING,

  /// The interval is inserting its covered items into the list.
  INSERTING,

  /// The interval is changing its covered items.
  CHANGING,

  /// The interval is completed and disposed.
  DISPOSED,

  /// Unknown state. This state should never be required.
  UNKNOWN,
}

typedef AnimatedListIntervalEventCallback = void Function(
    AnimatedListInterval interval);

/// This class represents a single interval.
///
/// The interval changes its [state] during its life:
/// An interval arises with the [AnimatedListIntervalState.REMOVING], [AnimatedListIntervalState.RESIZING]
/// (if no removal is needed) or [AnimatedListIntervalState.CHANGING] state.
/// A removing interval always goes into the [AnimatedListIntervalState.RESIZING] state.
/// A resizing interval can go into the [AnimatedListIntervalState.INSERTING] state or directly into the
/// [AnimatedListIntervalState.DISPOSED] (ie completed) state, if no insertion is needed.
/// An inserting interval, as well as a changing interval, always completes into the
/// [AnimatedListIntervalState.DISPOSED] state.
///
/// The interval takes into account two counts: [removeCount] and [insertCount]. The first indicates how many
/// items this interval will remove when it is in the removal animation, the latter indicates how many items
/// this intervals will insert when it is in the insert animation.
/// A changing interval has those counts always the same.
///
/// The [index] is the actual position in the [AnimatedSliverList] (and not in the underlying list).
///
/// The values of [fromSize], [toSize] respectively indicate the initial size of the interval
/// when begin the resize animation, the final size at the end of the animation.
/// The [currentSize] getter returns the current size based on the animation value.
/// [fromSize] and/or [toSize] can be (initially or reset to) `null`: that tells the renderer to
/// measure them when this interval is in the [AnimatedListIntervalState.RESIZING] state.
///
/// Animations won't start immediately. The [isWaiting] getter indicates that the animation is waiting for.
///
/// The [isReordering] getter returns `true` to indicate that this interval is a special resizing interval
/// used during reordering.
class AnimatedListInterval extends Comparable {
  AnimatedListIntervalState _state = AnimatedListIntervalState.UNKNOWN;
  AnimatedListIntervalState get state => _state;

  int _index;
  int get index => _index;

  late int _insertCount, _removeCount;
  int get insertCount => _insertCount;
  int get removeCount => _removeCount;

  double? _fromSize, _toSize;
  double? get fromSize => _fromSize;
  double? get toSize => _toSize;

  double get currentSize {
    if (_fromSize != null && _toSize != null) {
      return _fromSize! + (_toSize! - _fromSize!) * animationValue;
    } else {
      return _fromSize != null && animationValue == 0.0 ? _fromSize! : 0.0;
    }
  }

  bool _waiting = true;
  bool get isWaiting => _waiting;

  _AnimatedListAnimationController? _controller;

  IndexedWidgetBuilder? _removeItemBuilder;

  /// This builder is used when the interval is in removing or changing state, and it is
  /// used to build the item that is removing or changing, and therefore are no longer
  /// in the underlying list.
  IndexedWidgetBuilder? get removeItemBuilder => _removeItemBuilder;

  /// Those callbacks are used to listen to all state changes.
  final AnimatedListIntervalEventCallback? onResizingCompleted,
      onRemovingCompleted,
      onInsertingCompleted,
      onChangingCompleted,
      onCompleted,
      onDisposed;

  bool get isInRemovingState => _state == AnimatedListIntervalState.REMOVING;
  bool get isInResizingState => _state == AnimatedListIntervalState.RESIZING;
  bool get isInInsertingState => _state == AnimatedListIntervalState.INSERTING;
  bool get isInChangingState => _state == AnimatedListIntervalState.CHANGING;

  bool get _needsRemoveItemBuilder =>
      _state == AnimatedListIntervalState.REMOVING ||
      _state == AnimatedListIntervalState.CHANGING;

  final AnimatedListAnimationSettings animationSettings;

  final TickerProvider vsync;

  final bool _reordering;
  bool get isReordering => _reordering;

  /// Returns the current [Animation].
  Animation<double> get animation =>
      _controller?.animation ?? kAlwaysDismissedAnimation;

  /// Returns the current animation value (or 0 if the interval is waiting for).
  double get animationValue =>
      _waiting ? 0.0 : (_controller?.animationValue ?? 0.0);

  /// This constructor creates a replacing interval.
  /// This interval is being created in the state [AnimatedListIntervalState.REMOVING]
  /// or [AnimatedListIntervalState.RESIZING] state (if no item should be removed).
  /// You must also provide a [TickerProvider] and an [AnimatedListAnimationSettings].
  AnimatedListInterval({
    required this.vsync,
    required this.animationSettings,
    required int index,
    int insertCount = 0,
    int removeCount = 0,
    IndexedWidgetBuilder? removeItemBuilder,
    this.onResizingCompleted,
    this.onRemovingCompleted,
    this.onInsertingCompleted,
    this.onCompleted,
    this.onDisposed,
  })  : _index = index,
        _removeCount = removeCount,
        _insertCount = insertCount,
        _removeItemBuilder = removeItemBuilder,
        onChangingCompleted = null,
        _reordering = false {
    assert(removeCount >= 0 && insertCount >= 0);
    assert(removeCount > 0 || insertCount > 0);
    assert(removeItemBuilder != null || removeCount == 0);

    if (_removeCount == 0) _fromSize = 0.0;
    if (_insertCount == 0) _toSize = 0.0;

    if (_removeCount > 0) {
      _changeState(AnimatedListIntervalState.REMOVING);
    } else if (_insertCount > 0) {
      _changeState(AnimatedListIntervalState.RESIZING);
    }
  }

  /// This constructor creates a changing interval.
  /// This interval is being created in the state [AnimatedListIntervalState.CHANGING].
  /// You must also provide a [TickerProvider] and an [AnimatedListAnimationSettings].
  AnimatedListInterval.change({
    required this.vsync,
    required this.animationSettings,
    required int index,
    required int changeCount,
    required IndexedWidgetBuilder? removeItemBuilder,
    this.onChangingCompleted,
    this.onCompleted,
    this.onDisposed,
  })  : _index = index,
        _removeItemBuilder = removeItemBuilder,
        onInsertingCompleted = null,
        onRemovingCompleted = null,
        onResizingCompleted = null,
        _reordering = false {
    assert(changeCount > 0);

    _removeCount = changeCount;
    _insertCount = changeCount;

    _changeState(AnimatedListIntervalState.CHANGING);
  }

  /// This constructor creates a special resizing interval used during reordering.
  /// This interval is being created in the state [AnimatedListIntervalState.RESIZING].
  /// You must also provide a [TickerProvider] and an [AnimatedListAnimationSettings].
  /// You must also provide the [size] of the resizing interval when is fully expanded.
  /// If [appearing] if `true`, the interval is created with size zero and starts
  /// its animation to get to its full size. If `false`, the interval is already created
  /// in its full size and waits for a signal to be collapsed to size zero.
  AnimatedListInterval.reorder({
    required this.vsync,
    required this.animationSettings,
    required int index,
    required double? size,
    required bool appearing,
    this.onResizingCompleted,
    this.onCompleted,
    this.onDisposed,
  })  : _index = index,
        onRemovingCompleted = null,
        onInsertingCompleted = null,
        onChangingCompleted = null,
        _removeCount = 0,
        _insertCount = 0,
        _reordering = true {
    if (appearing) {
      _fromSize = 0.0;
      _toSize = size;
      _changeState(AnimatedListIntervalState.RESIZING);
      startAnimation();
    } else {
      _fromSize = size;
      _toSize = 0.0;
      _changeState(AnimatedListIntervalState.RESIZING);
    }
  }

  // This constructor clones an existing interval.
  AnimatedListInterval._clone(AnimatedListInterval interval,
      [AnimatedListIntervalEventCallback? onDisposed])
      : _state = interval._state,
        _index = interval._index,
        _insertCount = interval._insertCount,
        _removeCount = interval._removeCount,
        _fromSize = interval._fromSize,
        _toSize = interval._toSize,
        _waiting = interval._waiting,
        _reordering = interval._reordering,
        vsync = interval.vsync,
        _removeItemBuilder = interval._removeItemBuilder,
        onResizingCompleted = interval.onResizingCompleted,
        onRemovingCompleted = interval.onRemovingCompleted,
        onInsertingCompleted = interval.onInsertingCompleted,
        onChangingCompleted = interval.onChangingCompleted,
        onCompleted = interval.onCompleted,
        onDisposed = onDisposed,
        animationSettings = interval.animationSettings {
    assert(_state != AnimatedListIntervalState.DISPOSED);
    if (interval._controller != null) {
      _controller =
          _AnimatedListAnimationController.clone(vsync, interval._controller!);
    }
  }

  void _changeState(AnimatedListIntervalState newState) {
    assert(_state != AnimatedListIntervalState.DISPOSED);
    _state = newState;
    _waiting = true;

    Duration duration;
    Curve curve;
    void Function() whenComplete;
    switch (_state) {
      case AnimatedListIntervalState.REMOVING:
        duration = animationSettings.removingDuration;
        curve = animationSettings.removingCurve;
        whenComplete = _onRemovingCompleted;
        break;
      case AnimatedListIntervalState.RESIZING:
        duration = _reordering
            ? animationSettings.reorderingDuration
            : animationSettings.resizingDuration;
        curve = _reordering
            ? animationSettings.reorderingCurve
            : animationSettings.resizingCurve;
        whenComplete = _onResizingCompleted;
        break;
      case AnimatedListIntervalState.INSERTING:
        duration = animationSettings.insertingDuration;
        curve = animationSettings.insertingCurve;
        whenComplete = _onInsertingCompleted;
        break;
      case AnimatedListIntervalState.CHANGING:
        duration = animationSettings.changingDuration;
        curve = animationSettings.changingCurve;
        whenComplete = _onChangingCompleted;
        break;
      default:
        return;
    }
    if (_controller == null) {
      _controller ??= _AnimatedListAnimationController(
          vsync: vsync,
          duration: duration,
          curve: curve,
          whenComplete: whenComplete,
          startNow: false);
    } else {
      _controller!.restart(
          duration: duration,
          curve: curve,
          whenComplete: whenComplete,
          startNow: false);
    }
  }

  /// Initializes and starts the animation of this interval if it was on hold.
  void startAnimation() {
    if (!_waiting) return;
    _controller?.start();
    _waiting = false;
  }

  void _onRemovingCompleted() {
    if (_state == AnimatedListIntervalState.DISPOSED) return;
    _changeState(AnimatedListIntervalState.RESIZING);
    onRemovingCompleted?.call(this);
  }

  void _onResizingCompleted() {
    if (_state == AnimatedListIntervalState.DISPOSED) return;
    if (_reordering) {
      if (_toSize == 0.0) {
        onResizingCompleted?.call(this);
        _onCompleted();
      } else {
        _controller?.restart(
            whenComplete: _onResizingCompleted, startNow: false);
        _fromSize = _toSize;
        _toSize = 0.0;
        _waiting = true;
      }
    } else {
      if (_insertCount > 0) {
        _removeItemBuilder = null;
        _changeState(AnimatedListIntervalState.INSERTING);
        onResizingCompleted?.call(this);
      } else {
        onResizingCompleted?.call(this);
        _onCompleted();
      }
    }
  }

  void _onInsertingCompleted() {
    if (_state == AnimatedListIntervalState.DISPOSED) return;
    _onCompleted();
    onInsertingCompleted?.call(this);
  }

  void _onChangingCompleted() {
    if (_state == AnimatedListIntervalState.DISPOSED) return;
    _onCompleted();
    onChangingCompleted?.call(this);
  }

  void _onCompleted() {
    if (_state == AnimatedListIntervalState.DISPOSED) return;
    onCompleted?.call(this);
    dispose(); // completed intervals will be automatically disposed
  }

  /// If [fromSize] is currently `null`, the [fromSizeCallback] callback will be invoked
  /// to calculate the new size.
  /// Similiarly, if [toSize] is currently `null`, the [toSizeCallback] callback will be invoked
  /// to calculate the new size.
  void measureSizesIfNeeded(
      double Function() fromSizeCallback, double Function() toSizeCallback) {
    _fromSize ??= fromSizeCallback();
    _toSize ??= toSizeCallback();
  }

  /// This method is called when this interval that was already in the resizing state
  /// changes its [toSize].
  /// Returns `true` if the new size is already the same as the current one, and then the
  /// resizing status has been completed.
  bool resize([double? toSize]) {
    assert(isInResizingState);
    assert(toSize == null || _reordering);
    _fromSize = currentSize;
    _toSize = toSize ?? ((_insertCount == 0) ? 0.0 : null);
    if (_fromSize != null && _toSize != null && _fromSize!.equals(_toSize!)) {
      _onResizingCompleted();
      return true;
    }
    if (!_waiting) {
      _controller?.restart(whenComplete: _onResizingCompleted);
    }
    return false;
  }

  /// Returns the count of items this interval is currently occupying in the [AnimatedSliverList].
  int get buildingItemCount {
    switch (_state) {
      case AnimatedListIntervalState.REMOVING:
        return _removeCount;
      case AnimatedListIntervalState.RESIZING:
        return 1;
      case AnimatedListIntervalState.INSERTING:
      case AnimatedListIntervalState.CHANGING:
        return _insertCount;
      default:
        return 0;
    }
  }

  /// Returns the difference between the count of items currently occupyied and the
  /// count of items it will occupy when this interval will be completed.
  int get adjustingItemCount => _insertCount - buildingItemCount;

  @override
  String toString() {
    return '{index=$_index, state=$state, removeCount:$removeCount, insertCount=$insertCount, fromSize:$fromSize, toSize=$toSize, currentSize=$currentSize}';
  }

  String toDebugString() {
    String s;
    switch (_state) {
      case AnimatedListIntervalState.REMOVING:
        s = 'Rm';
        break;
      case AnimatedListIntervalState.RESIZING:
        s = 'Rz';
        break;
      case AnimatedListIntervalState.INSERTING:
        s = 'In';
        break;
      case AnimatedListIntervalState.CHANGING:
        s = 'Ch';
        break;
      case AnimatedListIntervalState.DISPOSED:
        s = 'Dd';
        break;
      case AnimatedListIntervalState.UNKNOWN:
        s = '??';
        break;
    }
    return '($s $_index R:$removeCount I:$insertCount)';
  }

  @override
  int compareTo(other) {
    if (other is int) {
      return other - _index;
    } else if (other is AnimatedListInterval) return other._index - _index;
    throw 'other in compareTo must be an integer or a ListInterval';
  }

  /// Eventually splits this interval.
  /// There are 4 possibilities:
  /// - if [leading] and [trailing] are both 0, this interval will be completed
  ///   and null is returned; the caller has to create a new interval for that
  ///   completly replaces it;
  /// - if only [leading] is 0, the interval will be narrowed down to [trailing] length
  ///   and null is returned; the [removeItemBuilder] will also be shifted
  ///   accordingly; the caller has to create a new interval that covers
  ///   the left side;
  /// - if only [trailing] is 0, the interval will be narrowed down to [leading] length
  ///   and null is returned; the caller has to create a new interval that covers
  ///   the right side;
  /// - if [leading] and [trailing] are both greater than 0, the interval will be narrowed
  ///   down to [leading] length and a new cloned [AnimatedListInterval] will be
  ///   created and returned covering the right side; the caller has to create a new
  ///   interval that covers the middle part.
  AnimatedListInterval? split(int leading, int trailing) {
    assert(!isReordering && (isInChangingState || isInInsertingState));
    assert(leading >= 0 && trailing >= 0);
    assert(leading + trailing <= insertCount);

    if (leading == 0 && trailing == 0) {
      _onCompleted();
      return null;
    }

    AnimatedListInterval? otherInterval;
    if (leading > 0 && trailing > 0) {
      otherInterval = AnimatedListInterval._clone(this);
      if (otherInterval.isInChangingState) {
        otherInterval._removeCount = trailing;
      }
      otherInterval._insertCount = trailing;

      otherInterval._index += _insertCount - trailing;

      if (otherInterval._needsRemoveItemBuilder) {
        otherInterval._removeItemBuilder = _shiftItemBuilder(
            otherInterval._removeItemBuilder, _removeCount - trailing);
      }
    }

    if (leading > 0) {
      if (_needsRemoveItemBuilder) {
        _removeCount = leading;
      }
      _insertCount = leading;
    } else {
      if (_needsRemoveItemBuilder) {
        _removeItemBuilder =
            _shiftItemBuilder(_removeItemBuilder, _removeCount - trailing);
      }

      _index += _insertCount - trailing;

      if (_needsRemoveItemBuilder) {
        _removeCount = trailing;
      }
      _insertCount = trailing;
    }

    return otherInterval;
  }

  /// Disposes this interval.
  void dispose() {
    if (_state == AnimatedListIntervalState.DISPOSED) return;
    _state = AnimatedListIntervalState.DISPOSED;
    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
    }
    onDisposed?.call(this);
  }

  // Returns `true` if two adjacent intervals can be merged for optimization.
  static bool _canBeIntervalsMerged(AnimatedListInterval leftInterval,
          AnimatedListInterval rightInterval) =>
      leftInterval._index + leftInterval.buildingItemCount ==
          rightInterval._index &&
      leftInterval._waiting &&
      rightInterval._waiting &&
      (leftInterval.isInRemovingState &&
              (rightInterval.isInRemovingState ||
                  rightInterval.isInResizingState &&
                      rightInterval._fromSize == 0.0) ||
          leftInterval.isInResizingState &&
              leftInterval._fromSize == 0.0 &&
              (rightInterval.isInRemovingState ||
                  rightInterval.isInResizingState) ||
          leftInterval.isInChangingState && rightInterval.isInChangingState);

  // Merges two adjacent intervals for optimization.
  // Returns `true` if the right interval will be expanded and the left one removed, while
  // returns `false` if the left interval will be expanded and the right one removed.
  static bool _mergeIntervals(
      AnimatedListInterval leftInterval, AnimatedListInterval rightInterval) {
    assert(_canBeIntervalsMerged(leftInterval, rightInterval));
    if (leftInterval._state == rightInterval._state) {
      final ra = leftInterval._removeItemBuilder;
      final rb = rightInterval._removeItemBuilder;
      final n = leftInterval._removeCount;
      leftInterval._removeCount += rightInterval._removeCount;
      leftInterval._insertCount += rightInterval._insertCount;
      leftInterval._toSize = (leftInterval._insertCount == 0) ? 0.0 : null;
      if (!leftInterval.isInResizingState) {
        leftInterval._removeItemBuilder =
            (c, i) => (i < n) ? ra!.call(c, i) : rb!.call(c, i - n);
      }
      return false;
    } else if (rightInterval.isInResizingState) {
      assert(leftInterval.isInRemovingState);
      leftInterval._insertCount += rightInterval._insertCount;
      leftInterval._toSize = (leftInterval._insertCount == 0) ? 0.0 : null;
      return false;
    } else {
      assert(leftInterval.isInResizingState && rightInterval.isInRemovingState);
      rightInterval._insertCount += leftInterval._insertCount;
      rightInterval._toSize = (rightInterval._insertCount == 0) ? 0.0 : null;
      rightInterval._index = leftInterval._index;
      return true;
    }
  }
}

//---------------------------------------------------------------------------------------------
// _AnimationController
//---------------------------------------------------------------------------------------------

// Helper class to control list animations using an [AnimationController].
class _AnimatedListAnimationController {
  late AnimationController _controller;
  Animation<double>? _animation;
  late void Function() _whenComplete;
  int? id;
  Curve? _curve;

  _AnimatedListAnimationController({
    required TickerProvider vsync,
    required Duration duration,
    Curve? curve,
    required void Function() whenComplete,
    double startingControllerValue = 0.0,
    bool startNow = true,
  }) {
    _curve = curve;
    _controller = AnimationController(
        vsync: vsync, duration: duration, value: startingControllerValue);
    if (curve != null) {
      _animation = Tween(begin: 0.0, end: 1.0)
          .animate(CurvedAnimation(parent: _controller, curve: curve));
    }
    _whenComplete = whenComplete;
    if (startNow) start();
  }

  _AnimatedListAnimationController.clone(
      TickerProvider vsync, _AnimatedListAnimationController controller)
      : this(
            vsync: vsync,
            duration: controller.duration,
            curve: controller._curve,
            whenComplete: controller._whenComplete,
            startingControllerValue: controller.controllerValue,
            startNow: controller._controller.isAnimating);

  void start() {
    if (!_controller.isAnimating) {
      assert(_animation != null);
      var future = _controller.forward();
      future.whenComplete(_whenComplete);
    }
  }

  void restart(
      {Duration? duration,
      Curve? curve,
      required void Function() whenComplete,
      bool startNow = true}) {
    if (_controller.status != AnimationStatus.dismissed) _controller.reset();
    if (duration != null && duration != this.duration) {
      _controller.duration = duration;
    }
    if (curve != null && curve != _curve) {
      _curve = curve;
      _animation = Tween(begin: 0.0, end: 1.0)
          .animate(CurvedAnimation(parent: _controller, curve: curve));
    }
    _whenComplete = whenComplete;
    if (startNow) start();
  }

  Duration get duration => _controller.duration!;

  Animation<double>? get animation => _animation;

  double get animationValue => _animation?.value ?? 0.0;

  double get controllerValue => _controller.value;

  void dispose() {
    _controller.dispose();
  }
}

//---------------------------------------------------------------------------------------------
// Extensions
//---------------------------------------------------------------------------------------------

extension _DoubleExtension on double {
  bool equals(double d, [double precisionErrorTolerance = 1e-10]) {
    var c = this - d;
    return c < precisionErrorTolerance && c > -precisionErrorTolerance;
  }
}

extension _ListComparableExtension<T extends Comparable> on List<T> {
  int indexOfBinarySearch(dynamic element) {
    var min = 0;
    var max = length;
    while (min < max) {
      var mid = min + ((max - min) >> 1);
      var c = this[mid].compareTo(element);
      if (c < 0) {
        max = mid;
      } else if (c > 0) {
        min = mid + 1;
      } else {
        while (mid > 0) {
          if (this[mid - 1].compareTo(element) != 0) break;
          mid--;
        }
        return mid;
      }
    }
    return -1;
  }

  T? binarySearch(dynamic element) {
    var i = indexOfBinarySearch(element);
    return (i >= 0) ? this[i] : null;
  }

  int closestIndexOfBinarySearch(dynamic element) {
    var i = 0;
    var min = 0;
    var max = length;
    while (min < max) {
      final mid = min + ((max - min) >> 1);
      var c = this[mid].compareTo(element);
      if (c < 0) {
        i = max = mid;
      } else if (c > 0) {
        i = min = mid + 1;
      } else {
        i = mid;
        break;
      }
    }
    return i;
  }

  int insertSorted(T element) {
    var i = closestIndexOfBinarySearch(element);
    insert(i, element);
    return i;
  }
}
