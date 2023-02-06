part of 'core.dart';

const double _kMinAcceptableResizeAmount = 1;

extension _Double on double {
  bool get isAcceptableResizeAmount => abs() > _kMinAcceptableResizeAmount;
}

class _SplitResult {
  final Iterable<_Interval>? left, right;
  final Iterable<_Interval>? middle;
  final _UpdateCallback? updateCallback;
  final void Function()? subListSplitCallback;

  const _SplitResult(this.left, this.right, this.middle,
      {this.updateCallback, this.subListSplitCallback});

  @override
  String toString() => 'SplitResult(left=$left, middle=$middle, right=$right)';
}

class _MergeResult {
  final Iterable<_Interval> mergedIntervals;
  final _UpdateCallback? callback;

  const _MergeResult(this.mergedIntervals, [this.callback]);

  @override
  String toString() => 'MergeResult($mergedIntervals)';
}

/// Base class of all kind of intervals.
///
/// An interval is a linked node for an [_IntervalList]. The interval may or may not actually be linked to a list.
///
/// Eventually intervals can be disposed.
abstract class _Interval extends _LinkedNode<_Interval> {
  bool _disposed = false;

  int? _buildOffset, _itemOffset;

  static var _counter = 0;

  final int _debugId;

  _Interval() : _debugId = ++_counter;
  _Interval.id(int id) : _debugId = id;

  /// It returns `true` if the [buildOffset] or [itemOffset] has not yet been calculated, or is no longer valid.
  bool get isDirty => _buildOffset == null || _itemOffset == null;

  /// It returns the count of the items covered by this interval for building purpose.
  int get buildCount;

  /// It returns the actual count of the items covered of the underlying list.
  int get itemCount;

  /// The current average count of the covered items for building purpose, which at the end of all animations will
  /// always be equal to the number of items in the underlying list.
  ///
  /// The default implementation returns the [itemCount].
  ///
  /// This property is used by [AnimatedRenderSliverMultiBoxAdaptor.extrapolateMaxScrollOffset] and
  /// [AnimatedRenderSliverMultiBoxAdaptor.estimateLayoutOffset] methods.
  double get averageCount => itemCount.toDouble();

  /// It returns `true` if this interval has been disposed.
  bool get isDisposed => _disposed;

  /// The list to which the interval belongs, or null if the inteval has not yet been attached to any list.
  @override
  _IntervalList? get list => super.list as _IntervalList?;

  /// The offset of the first item that can be build, relative to its list to which it is linked.
  int get buildOffset {
    assert(_debugAssertAttachedToList());
    if (isDirty) validate();
    return _buildOffset!;
  }

  /// The offset of the first covered item in the underlying list, relative to its list to which it is linked.
  int get itemOffset {
    assert(_debugAssertAttachedToList());
    if (isDirty) validate();
    return _itemOffset!;
  }

  int get nextBuildOffset => buildOffset + buildCount;
  int get nextItemOffset => itemOffset + itemCount;

  int get actualBuildOffset =>
      buildOffset + (list!.holder?.parentBuildOffset ?? 0);

  /// It marks this interval as dirty, i.e., reports the request to recalculate the [buildOffset] and
  /// [itemOffset] properties.
  void invalidate() {
    assert(_debugAssertAttachedToList());
    if (isDirty) return;
    list!._leftMostDirtyInterval = this;
    _Interval? i = this;
    do {
      i!._invalidate();
      i = i.next;
    } while (i != null && !i.isDirty);
    assert(isDirty);
  }

  /// If the inteval is marked as dirty, proceeds with the calculation of the [buildOffset] and
  /// [itemOffset] properties.
  void validate() {
    assert(_debugAssertAttachedToList());
    if (!isDirty) return;
    assert(isDirty && list!._leftMostDirtyInterval != null);
    var interval = list!._leftMostDirtyInterval;
    final prev = interval!.previous;
    int buildOffset, itemOffset;
    if (prev == null) {
      buildOffset = 0;
      itemOffset = 0;
    } else {
      buildOffset = prev._buildOffset! + prev.buildCount;
      itemOffset = prev._itemOffset! + prev.itemCount;
    }
    do {
      final nextInterval = interval!.next;
      interval._validate(buildOffset, itemOffset);
      list!._leftMostDirtyInterval = nextInterval;
      if (interval == this) break;
      buildOffset += interval.buildCount;
      itemOffset += interval.itemCount;
      interval = nextInterval;
    } while (interval != null);
    assert(!isDirty);
  }

  /// It splits the interval in the middle into a maximum of three new intervals (left, middle and right).
  /// It is called by indicating how many items in the underlying list should cover the left [leading] interval and
  /// how many the right [trailing] interval.
  /// The new intervals are not necessarily of the same type.
  _SplitResult split(int leading, int trailing) {
    return _split(leading, trailing, null, true, null);
  }

  /// It splits the interval in the middle into a maximum of three new intervals (left, middle and right).
  /// It is called by indicating how many items in the underlying list should cover the left [leading] interval and
  /// how many the right [trailing] interval.
  /// The split middle interval is replaced by the ones passed as the input parameter [middle]. An update callback
  /// [middleUpdateCallback] can also be passed for the middle interval.
  /// The new intervals are not necessarily of the same type.
  _SplitResult splitWith(int leading, int trailing, Iterable<_Interval> middle,
      [_UpdateCallback? middleUpdateCallback]) {
    return _split(leading, trailing, middle, false, middleUpdateCallback);
  }

  /// This method give the possibility to merge this interval with another left interval,
  /// generating a single or multiple intervals given by merging the two, for optimization purpose.
  _MergeResult? mergeWith(_Interval leftInterval) => null;

  /// This method builds the widget related to a specific item [index] within its [buildCount].
  Widget buildWidget(_ListIntervalInterface interface, BuildContext context,
          int index, bool measureOnly) =>
      throw UnimplementedError('This interval is not meant to be built');

  /// The interval name.
  @protected
  String get name;

  /// It returns just itself as an [Iterable].
  Iterable<_Interval> iterable() sync* {
    yield this;
  }

  @mustCallSuper
  void dispose() {
    assert(_debugAssertNotDisposed());
    assert(list == null);
    _disposed = true;
  }

  @protected
  String toShortString() => kDebugMode
      ? '$name[$_debugId]($buildCount,$itemCount)'
      : '$name($buildCount,$itemCount)';

  List<MapEntry<String?, Object>> get _state {
    if (_disposed) {
      return [MapEntry(null, 'DISPOSED')];
    } else if (list == null) {
      return [MapEntry(null, 'UNLINKED')];
    } else if (isDirty) {
      return [MapEntry(null, 'DIRTY')];
    } else {
      return [MapEntry('bo', buildOffset), MapEntry('io', itemOffset)];
    }
  }

  Iterable<MapEntry<String?, Object?>> get attributes => [
        if (kDebugMode) MapEntry('id', _debugId),
        ..._state,
        if (_disposed) MapEntry(null, 'DISPOSED'),
        MapEntry('bc', buildCount),
        MapEntry('ic', itemCount),
        MapEntry('avc', averageCount),
      ];

  @protected
  @override
  String toString() =>
      '$name (${attributes.map((e) => e.key != null ? '${e.key}: ${e.value}' : '${e.value}').join(', ')})';

  _SplitResult _split(int leading, int trailing, Iterable<_Interval>? middle,
      bool createMiddle, _UpdateCallback? middleUpdateCallback) {
    assert(_debugAssertNotDisposed());
    assert((createMiddle && middle == null && middleUpdateCallback == null) ||
        !createMiddle);
    assert(leading >= 0 && trailing >= 0);
    assert(leading + trailing <= itemCount);
    return _performSplit(
        leading, trailing, middle, createMiddle, middleUpdateCallback);
  }

  _SplitResult _performSplit(
          int leading,
          int trailing,
          Iterable<_Interval>? middle,
          bool createMiddle,
          _UpdateCallback? middleUpdateCallback) =>
      throw UnimplementedError('This interval is not meant to be split');

  bool _debugAssertAttachedToList() {
    assert(() {
      _debugAssertNotDisposed();
      if (list == null) {
        throw FlutterError(
          'This interval has not yet been attached to any list.',
        );
      }
      return true;
    }());
    return true;
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

  void _invalidate() {
    _buildOffset = null;
    _itemOffset = null;
  }

  void _validate(int buildOffset, int itemOffset) {
    _buildOffset = buildOffset;
    _itemOffset = itemOffset;
  }

  //
  // helpful methods
  //

  /// It calls the builder passed by the user to build the items of the underlying list.
  Widget _inListBuilder(_ListIntervalInterface interface, int listIndexOffset,
      AnimatedWidgetBuilderData data) {
    return interface.wrapWidget(interface.delegate.builder,
        listIndexOffset + (list!.holder?.parentItemOffset ?? 0), data);
  }

  /// It builds a fixed size [SizedBox].
  Widget _buildSizedBox(_ListIntervalInterface interface, double size) {
    assert(_debugAssertAttachedToList());
    final horizontal = interface.isHorizontal;
    Widget widget = SizedBox(
        width: horizontal ? size : null, height: !horizontal ? size : null);
    if (kDebugMode) {
      widget = _DebugBox(widget, this);
    }
    return widget;
  }

  /// It builds an animated [SizedBox].
  Widget _buildAnimatedSizedBox(_ListIntervalInterface interface,
      _IntervalAnimation animation, Tween<double> tween, bool measureOnly) {
    assert(_debugAssertAttachedToList());
    if (measureOnly) {
      return _buildSizedBox(interface, tween.evaluate(animation.animation));
    }
    final tweenAnimation = tween.animate(animation.animation);
    final horizontal = interface.isHorizontal;
    Widget widget = AnimatedBuilder(
        animation: tweenAnimation,
        builder: (context, child) {
          final value = tweenAnimation.value;
          return SizedBox(
            width: horizontal ? value : null,
            height: !horizontal ? value : null,
          );
        });
    if (kDebugMode) {
      widget = _DebugBox(widget, this);
    }
    return widget;
  }

  AnimatedWidgetBuilderData _builderData(
          Animation<double> animation, bool measureOnly) =>
      AnimatedWidgetBuilderData(
        animation,
        measuring: measureOnly,
        moving:
            list!.popUpList != null && list!.popUpList is! _ReorderPopUpList,
        dragging: list!.popUpList is _ReorderPopUpList,
        slot: list!.manager.reorderLayoutData?.slot,
      );
}

/// Interval with animation feature.
///
/// An animation will be attached to this interval.
mixin _AnimatedIntervalMixin implements _Interval {
  _IntervalAnimation get animation;

  bool get isWaitingAtBeginning => animation.isWaitingAtBeginning;

  bool get isWaitingAtEnd => animation.isWaitingAtEnd;

  bool get areAnimationsCompleted => isWaitingAtEnd;

  bool areBothAnimationsCompleted(_AnimatedIntervalMixin interval) =>
      areAnimationsCompleted && interval.areAnimationsCompleted;

  bool get canCompleteImmediately => false;

  void startAnimation() {
    if (animation is _ControlledAnimation) {
      final animation = this.animation as _ControlledAnimation;
      animation.start();
      if (canCompleteImmediately) {
        animation.complete();
      }
    }
  }

  List<MapEntry<String?, Object>> get animationAttributes =>
      [MapEntry('t', animation.time)];
}

/// This interface marks an interval to be able to adjust the count of the covered items of the
/// underlying list without changing its build.
///
/// Classes [_ReadyToRemovalInterval], [_RemovalInterval], [_ReadyToResizingFromRemovalInterval],
/// [_ReadyToNewResizingInterval] and [_ReadyToResizingSpawnedInterval] implement this.
///
/// This mark is checked by the [_IntervalManager.onReplaceNotification] and
/// [_IntervalManager.onChangeNotification] methods.
abstract class _AdjustableInterval implements _Interval {
  /// Clones this interval providing a new item count of the underlying list.
  _AdjustableInterval clone(int newItemCount);
}

/// This interface marks an interval to be a space interval.
///
/// It implements the method [currentSize] used to retrieve the size in pixels of the spacing widget.
///
/// Classes [_ReadyToNewResizingInterval], [_ReadyToInsertionInterval], [_ResizingInterval], [_MovingInterval],
/// [_ReadyToPopupMoveInterval],  [_ReorderClosingInterval] and [_ReorderOpeningInterval] implement this.
abstract class _SpaceInterval implements _Interval {
  /// The current size in pixels of the spacing widget.
  double get currentSize;
}

/// This interface marks a space interval to be able to be transformed into a [_ReadyToNewResizingInterval].
///
/// Classes [_ResizingInterval] and [_ReadyToInsertionInterval] implement this.
///
/// This mark is checked by the [_IntervalManager.onReplaceNotification] and
/// [_IntervalManager.onChangeNotification] methods.
abstract class _ResizableInterval implements _SpaceInterval {}

/// Marks the interval that can also build one or more pop-up items.
/// A [_PopUpList] is linked to it.
abstract class _PopUpInterval implements _Interval {
  _PopUpList get popUpList;
}

/// It marks an interval to be linked to a sub list [_IntervalList].
///
/// Classes [_ReadyToMoveInterval], [_ReadyToPopupMoveInterval], [_DropInterval], [_MovingInterval],
/// [_ReorderHolderInterval] and [_ReorderOpeningInterval] implement this.
abstract class _SubListInterval implements _Interval {
  _IntervalList get subList;
}

/// The sub list linked to the interval that implements this interface is also the "holder" of the sub list.
/// It means that the [buildOffset] and [itemOffset] of each item of the sub list need to be adjusted by
/// this "parent" interval.
/// Intervals implementing this interface has to set itself in the [_IntervalList.holder] attribute of the sub list.
///
/// Classes [_ReadyToMoveInterval], [_ReadyToPopupMoveInterval], [_MovingInterval] and [_ReorderOpeningInterval]
/// implement this.
abstract class _SubListHolderInterval extends _SubListInterval {
  int get parentBuildOffset;

  int get parentItemOffset;

  /// Called when one or more items of the linked sublist have changed.
  void onChanged();
}

// Animated interval that builds a range of an off-list items (for example a range of removed
// or changed items no longer present in the underlying list) using an off-list builder.
abstract class _OffListAnimatedInterval extends _Interval
    with _AnimatedIntervalMixin {
  _OffListAnimatedInterval(this.animation, this.builder, this.buildCount)
      : assert(buildCount > 0) {
    animation.attachTo(this);
  }

  @override
  final _IntervalAnimation animation;

  final _IntervalBuilder builder;

  @override
  final int buildCount;

  @override
  double get averageCount => buildCount.toDouble();

  @override
  Widget buildWidget(_ListIntervalInterface interface, BuildContext context,
      int index, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    return builder.call(
        context, index, _builderData(animation.animation, measureOnly));
  }

  @override
  void dispose() {
    animation.detachFrom(this);
    super.dispose();
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy(animationAttributes);
}

/// Animated space interval that is resizing an animated empty [SizedBox] widget which is getting bigger
/// or smaller, going from an initial size to a final size.
///
/// A tick listener is attached to the animation and the [_IntervalManager.onResizeTick] will be invoked
/// passing the delta between the current size and the previous size.
abstract class _AnimatedSpaceInterval extends _Interval
    with _AnimatedIntervalMixin
    implements _SpaceInterval {
  _AnimatedSpaceInterval(this.animation, this.fromSize, this.toSize,
      this.fromLength, this.toLength)
      : lastSize = fromSize.value,
        assert(fromSize.value >= 0 && toSize.value >= 0),
        assert(fromLength >= 0 && toLength >= 0) {
    animation.attachTo(this);
    animation.animation.addListener(onTick);
  }

  @override
  final _ControlledAnimation animation;

  final _Measure fromSize, toSize;
  final double fromLength;
  final int toLength;

  double lastSize;

  @override
  int get buildCount => 1;

  @override
  int get itemCount => toLength;

  @override
  double get averageCount {
    if (animation.time == 0.0) {
      return fromLength;
    } else if (animation.time == 1.0) {
      return toLength.toDouble();
    } else {
      return fromLength + animation.animation.value * (toLength - fromLength);
    }
  }

  @override
  double get currentSize {
    if (animation.time == 0.0) {
      return fromSize.value;
    } else if (animation.time == 1.0) {
      return toSize.value;
    } else {
      return fromSize.value +
          animation.animation.value * (toSize.value - fromSize.value);
    }
  }

  double futureSize(double deltaTimeInSec) {
    final t = ((animation.time * animation.durationInSec) + deltaTimeInSec) /
        animation.durationInSec;
    return fromSize.value +
        animation.futureValue(t) * (toSize.value - fromSize.value);
  }

  void onTick() {
    if (list == null) return;
    final delta = currentSize - lastSize;
    if (delta != 0.0) {
      list!.manager.onResizeTick(this, delta);
      lastSize = currentSize;
    }
  }

  @override
  bool get canCompleteImmediately {
    return !(fromSize.value - toSize.value).isAcceptableResizeAmount;
  }

  @override
  Widget buildWidget(_ListIntervalInterface interface, BuildContext context,
      int index, bool measureOnly) {
    return _buildAnimatedSizedBox(interface, animation,
        Tween<double>(begin: fromSize.value, end: toSize.value), measureOnly);
  }

  @override
  void dispose() {
    animation.detachFrom(this);
    animation.animation.removeListener(onTick);
    super.dispose();
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy(animationAttributes).followedBy([
        MapEntry('cs', currentSize),
        MapEntry('fs', fromSize),
        MapEntry('ts', toSize),
        MapEntry('fl', fromLength),
        MapEntry('tl', toLength),
      ]);
}

//
// Core Intervals
//

/// Animated interval that builds a piece of the underlying list.
/// The animation refers to the a possibly fading-in effect of items (when inserting (In)).
class _NormalInterval extends _Interval
    with _AnimatedIntervalMixin, _SplitMixin {
  _NormalInterval(this.animation, this.itemCount) : assert(itemCount > 0) {
    animation.attachTo(this);
  }

  _NormalInterval.completed(int itemCount)
      : this(const _CompletedAnimation(), itemCount);

  @override
  final _IntervalAnimation animation;

  @override
  int get buildCount => itemCount;

  @override
  final int itemCount;

  @override
  _SplitBuildCounts splitCounts(int leading, int middle, int trailing) =>
      _basicSplitCounts(leading, middle, trailing);

  @override
  _NormalInterval createSplitInterval(
      int buildCount, int itemCount, int offset) {
    assert(buildCount == itemCount);
    return _NormalInterval(animation, itemCount);
  }

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _NormalInterval &&
        areBothAnimationsCompleted(leftInterval)) {
      return _MergeResult(_NormalInterval(
              const _CompletedAnimation(), itemCount + leftInterval.itemCount)
          .iterable());
    }
    return null;
  }

  @override
  Widget buildWidget(_ListIntervalInterface interface, BuildContext context,
      int index, bool measureOnly) {
    assert(_debugAssertAttachedToList());
    return _inListBuilder(interface, itemOffset + index,
        _builderData(animation.animation, measureOnly));
  }

  @override
  void dispose() {
    animation.detachFrom(this);
    super.dispose();
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy(animationAttributes);
  @override
  String get name => areAnimationsCompleted ? 'Nm' : 'In';
}

/// Interval that it is ready to be changed into a [_RemovalInterval].
///
/// The widget of the items that are ready to be removed will be created using an off-list builder.
///
/// The animation is inherited from the [_NormalInterval], and represents the fading-in effect of the items
/// (so the animation is not necessarily always completed, it is not when going from In to ->Rm).
class _ReadyToRemovalInterval extends _OffListAnimatedInterval
    with _SplitMixin
    implements _AdjustableInterval {
  _ReadyToRemovalInterval(
      this.animation, _IntervalBuilder builder, int buildCount, this.itemCount)
      : assert(buildCount > 0 && itemCount >= 0),
        super(animation, builder, buildCount);

  @override
  final _IntervalAnimation animation;

  @override
  final int itemCount;

  @override
  _SplitBuildCounts splitCounts(int leading, int middle, int trailing) =>
      _complexSplitCounts(leading, middle, trailing);

  @override
  _ReadyToRemovalInterval createSplitInterval(
          int buildCount, int itemCount, int offset) =>
      _ReadyToRemovalInterval(animation,
          offsetIntervalBuilder(builder, offset)!, buildCount, itemCount);

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToRemovalInterval &&
        areBothAnimationsCompleted(leftInterval)) {
      return _MergeResult(_ReadyToRemovalInterval(
              const _CompletedAnimation(),
              joinBuilders(
                  leftInterval.builder, builder, leftInterval.buildCount),
              leftInterval.buildCount + buildCount,
              leftInterval.itemCount + itemCount)
          .iterable());
    } else if (leftInterval is _ReadyToResizingSpawnedInterval) {
      return _MergeResult(_ReadyToRemovalInterval(animation, builder,
              buildCount, leftInterval.itemCount + itemCount)
          .iterable());
    }
    return null;
  }

  @override
  _ReadyToRemovalInterval clone(int newItemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToRemovalInterval(
        animation, builder, buildCount, newItemCount);
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy(animationAttributes);

  @override
  String get name => '->Rm';
}

/// Animated interval that is dismissing a range of items no longer present in the underlying list.
///
/// The widget of the items that you are dismissing will be created using an off-list builder.
///
/// It is created against a [_ReadyToRemovalInterval].
class _RemovalInterval extends _OffListAnimatedInterval
    with _SplitMixin
    implements _AdjustableInterval {
  _RemovalInterval(_IntervalAnimation animation, _IntervalBuilder builder,
      int buildCount, this.itemCount)
      : assert(buildCount > 0 && itemCount >= 0),
        super(animation, builder, buildCount);

  @override
  final int itemCount;

  @override
  _SplitBuildCounts splitCounts(int leading, int middle, int trailing) =>
      _complexSplitCounts(leading, middle, trailing);

  @override
  _RemovalInterval createSplitInterval(
          int buildCount, int itemCount, int offset) =>
      _RemovalInterval(animation, offsetIntervalBuilder(builder, offset)!,
          buildCount, itemCount);

  @override
  _RemovalInterval clone(int newItemCount) {
    assert(_debugAssertNotDisposed());
    return _RemovalInterval(animation, builder, buildCount, newItemCount);
  }

  @override
  String get name => 'Rm';
}

/// Animated space interval that covers items of the underlying list.
///
/// It is created against intervals that implement [_ReadyToResizing] interface and when a [_WithDropInterval] is
/// beginning to be moved.
class _ResizingInterval extends _AnimatedSpaceInterval
    with _SplitMixin, _ResizingSplitMixin
    implements _ResizableInterval {
  _ResizingInterval(_ControlledAnimation animation, _Measure fromSize,
      _Measure toSize, double fromLength, int toLength)
      : super(animation, fromSize, toSize, fromLength, toLength);

  @override
  String get name => 'Rz';
}

/// Interval showing an empty space that it is ready to be changed into an [_NormalInterval] (in its "In" form).
///
/// It is created against intervals that implement [_ResizingInterval] interface.
class _ReadyToInsertionInterval extends _Interval
    with _SplitMixin, _ResizingSplitMixin
    implements _ResizableInterval {
  _ReadyToInsertionInterval(this.size, this.itemCount) : assert(itemCount > 0);

  final _Measure size;

  @override
  int get buildCount => 1;

  @override
  final int itemCount;

  @override
  double get currentSize => size.value;

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToInsertionInterval) {
      return _MergeResult(
        _ReadyToInsertionInterval(
                leftInterval.size + size, leftInterval.itemCount + itemCount)
            .iterable(),
        (list, index, oldBuildCount, newBuildCount) {
          list.addUpdate(index, oldBuildCount, newBuildCount,
              flags: const _UpdateFlags(_UpdateFlags.CLEAR_LAYOUT_OFFSET |
                  _UpdateFlags.KEEP_FIRST_LAYOUT_OFFSET));
        },
      );
    }
    return null;
  }

  @override
  Widget buildWidget(_ListIntervalInterface interface, BuildContext context,
      int index, bool measureOnly) {
    return _buildSizedBox(interface, size.value);
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy([MapEntry('cs', size)]);

  @override
  String get name => '->In';
}

/// Interval that is ready to rebuild the covered (changed) items of the underlying list.
///
/// The interval builds the old covered items of the underlying list using an off-list builder,
/// waiting to be changed into a [_NormalInterval].
///
/// It is created against a [_NormalInterval] from [_IntervalManager.onChangeNotification] method.
///
/// The animation is inherited from the [_NormalInterval], and represents the fading-in effect of the items
/// (so the animation is not necessarily always completed, it is not when going from In to ->Ch).
class _ReadyToChangingInterval extends _OffListAnimatedInterval
    with _SplitMixin {
  _ReadyToChangingInterval(
      _IntervalAnimation animation, _IntervalBuilder builder, this.itemCount)
      : assert(itemCount > 0),
        super(animation, builder, itemCount);

  @override
  final int itemCount;

  @override
  _SplitBuildCounts splitCounts(int leading, int middle, int trailing) =>
      _basicSplitCounts(leading, middle, trailing);

  @override
  _ReadyToChangingInterval createSplitInterval(
      int buildCount, int itemCount, int offset) {
    assert(buildCount == itemCount);
    return _ReadyToChangingInterval(
        animation, offsetIntervalBuilder(builder, offset)!, itemCount);
  }

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToChangingInterval &&
        areBothAnimationsCompleted(leftInterval)) {
      return _MergeResult(_ReadyToChangingInterval(
        const _CompletedAnimation(),
        joinBuilders(leftInterval.builder, builder, leftInterval.buildCount),
        leftInterval.itemCount + itemCount,
      ).iterable());
    }
    return null;
  }

  @override
  String get name => '->Ch';
}

//
// Measuring Intervals
//

class _Cancelled {
  bool value = false;
}

/// Abstract generic class that allows a measurement to be performed asynchronously.
/// The [performMeasure] method will have to be overridden to actually perform the measurement.
abstract class _MeasureTask {
  _Measure? measure;

  bool _measuring = false;

  _Cancelled? cancelled;

  bool get isMeasuring => _measuring;

  bool get isCompleted => measure != null;

  /// It starts the measuring in asynchronous mode.
  /// The future returns `false` if the measurement has been cancelled.
  FutureOr<bool> start(_ListIntervalInterface interface, _Interval interval) {
    if (isCompleted) return true;

    assert(cancelled == null);

    cancelled = _Cancelled();
    _measuring = true;

    bool nextStep(_Measure f) {
      final ret = !cancelled!.value;
      _measuring = false;
      cancelled = null;
      measure = f;
      return ret;
    }

    final f = performMeasure(interface, interval);
    if (f is Future<_Measure>) {
      return f.then<bool>(nextStep);
    } else {
      return nextStep(f);
    }
  }

  FutureOr<_Measure> performMeasure(
      _ListIntervalInterface interface, _Interval interval);

  void cancel() {
    cancelled?.value = true;
    _measuring = false;
  }
}

/// It perform asynchronously the measurement of a bunch of items generated by the off-list builder
/// of an [_OffListAnimatedInterval].
class _MeasureOffListItemsTask extends _MeasureTask {
  _MeasureOffListItemsTask();

  @override
  FutureOr<_Measure> performMeasure(_ListIntervalInterface interface,
      covariant _OffListAnimatedInterval interval) {
    assert(interval._debugAssertAttachedToList());
    final r = interface.measureItems(
        cancelled!,
        interval.buildCount,
        (context, index) => interval.builder.call(
            context,
            index,
            AnimatedWidgetBuilderData(kAlwaysDismissedAnimation,
                measuring: true)));
    return r;
  }
}

/// It perform asynchronously the measurement of a bunch of items generated by the in-list builder
/// provided by the user.
class _MeasureInListItemsTask extends _MeasureTask {
  @override
  FutureOr<_Measure> performMeasure(
      _ListIntervalInterface interface, _Interval interval) {
    assert(interval._debugAssertAttachedToList());
    if (interval.itemCount == 0) return _Measure.zero;
    final r = interface.measureItems(cancelled!, interval.itemCount,
        (context, index) {
      return interval._inListBuilder(interface, index + interval.itemOffset,
          AnimatedWidgetBuilderData(kAlwaysCompleteAnimation, measuring: true));
    });
    return r;
  }
}

/// Intervals implementing this interface must take a measure to calculate the space required by a bunch of items.
/// After finishing the measurement, the interval is ready to be transformed into a [_ResizingInterval].
///
/// Classes [_ReadyToResizingFromRemovalInterval], [_ReadyToNewResizingInterval] and
/// [_ReadyToResizingSpawnedInterval] implement this.
abstract class _ReadyToResizing implements _AdjustableInterval {
  FutureOr<bool> startMeasuring(_ListIntervalInterface interface);

  bool get isMeasured;

  bool get isMeasuring;

  _Measure? get fromSize;

  _Measure? get toSize;

  double get fromLength;
}

/// Interval that finished its dismissing animation and it is ready to be measured.
///
/// The widget of the removed items will be created by an off-list builder using a full fade-out effect.
///
/// It is created against a [_RemovalInterval].
class _ReadyToResizingFromRemovalInterval extends _OffListAnimatedInterval
    with _SplitMixin
    implements _ReadyToResizing {
  _ReadyToResizingFromRemovalInterval(
      this.builder, this.buildCount, this.itemCount)
      : assert(buildCount > 0 && itemCount >= 0),
        super(const _DismissedAnimation(), builder, buildCount);

  @override
  final int buildCount;

  @override
  final int itemCount;

  @override
  final _IntervalBuilder builder;

  final _MeasureOffListItemsTask fromSizeTask = _MeasureOffListItemsTask();

  final _MeasureInListItemsTask toSizeTask = _MeasureInListItemsTask();

  @override
  double get fromLength => buildCount.toDouble();

  @override
  _Measure? get fromSize => fromSizeTask.measure;

  @override
  _Measure? get toSize => toSizeTask.measure;

  @override
  bool get isMeasured => fromSizeTask.isCompleted && toSizeTask.isCompleted;

  @override
  bool get isMeasuring => fromSizeTask.isMeasuring || toSizeTask.isMeasuring;

  @override
  _SplitBuildCounts splitCounts(int leading, int middle, int trailing) =>
      _complexSplitCounts(leading, middle, trailing);

  @override
  _ReadyToResizingFromRemovalInterval createSplitInterval(
          int buildCount, int itemCount, int offset) =>
      _ReadyToResizingFromRemovalInterval(
          offsetIntervalBuilder(builder, offset)!, buildCount, itemCount);

  @override
  FutureOr<bool> startMeasuring(_ListIntervalInterface interface) {
    final f = fromSizeTask.start(interface, this);

    FutureOr<bool> nextStep(bool b) {
      if (!b) return false;
      return toSizeTask.start(interface, this);
    }

    if (f is Future<bool>) {
      return f.then<bool>(nextStep);
    } else {
      return nextStep(f);
    }
  }

  @override
  _ReadyToResizingFromRemovalInterval clone(int newItemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToResizingFromRemovalInterval(
        builder, buildCount, newItemCount);
  }

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToResizingSpawnedInterval) {
      return _MergeResult(_ReadyToResizingFromRemovalInterval(
              builder, buildCount, itemCount + leftInterval.itemCount)
          .iterable());
    }
    return null;
  }

  @override
  void dispose() {
    fromSizeTask.cancel();
    toSizeTask.cancel();
    super.dispose();
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy([
        MapEntry('fs', fromSizeTask.measure),
        MapEntry('ts', toSizeTask.measure),
        MapEntry('fl', fromLength),
      ]);

  @override
  String get name => 'Rm->Rz';
}

/// Interval that spawned from nothing and it is ready to be changed into a [_ResizingInterval].
/// This interval does not need to be built.
class _ReadyToResizingSpawnedInterval extends _Interval
    with _SplitMixin
    implements _ReadyToResizing {
  _ReadyToResizingSpawnedInterval(this.itemCount) : assert(itemCount > 0);

  final _MeasureInListItemsTask toSizeTask = _MeasureInListItemsTask();

  @override
  int get buildCount => 0;

  @override
  final int itemCount;

  @override
  double get averageCount => 0.0;

  @override
  double get fromLength => 0;

  @override
  _Measure? get fromSize => _Measure.zero;

  @override
  _Measure? get toSize => toSizeTask.measure;

  @override
  bool get isMeasured => toSizeTask.isCompleted;

  @override
  bool get isMeasuring => toSizeTask.isMeasuring;

  @override
  _SplitBuildCounts splitCounts(int leading, int middle, int trailing) =>
      const _SplitBuildCounts(0, 0, 0);

  @override
  _ReadyToResizingSpawnedInterval createSplitInterval(
          int buildCount, int itemCount, int offset) =>
      _ReadyToResizingSpawnedInterval(itemCount);

  @override
  _ReadyToResizingSpawnedInterval clone(int newItemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToResizingSpawnedInterval(newItemCount);
  }

  @override
  FutureOr<bool> startMeasuring(_ListIntervalInterface interface) =>
      toSizeTask.start(interface, this);

  @override
  void dispose() {
    toSizeTask.cancel();
    super.dispose();
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy([
        MapEntry('ts', toSizeTask.measure),
      ]);

  @override
  String get name => '->Rz';
}

/// Interval that stopped its resizing animation, or was waiting for insertion or to be resized again,
/// and it is ready to be changed into a new [_ResizingInterval].
///
/// It is created against intervals that implement [_ResizableInterval] interface.
class _ReadyToNewResizingInterval extends _Interval
    with _SplitMixin, _ResizingSplitMixin
    implements _ReadyToResizing, _SpaceInterval {
  _ReadyToNewResizingInterval(this.itemCount, this.fromSize, this.fromLength)
      : assert(itemCount >= 0 && fromSize.value >= 0 && fromLength >= 0);

  final _MeasureInListItemsTask toSizeTask = _MeasureInListItemsTask();

  @override
  int get buildCount => 1;

  @override
  final int itemCount;

  @override
  final double fromLength;

  @override
  final _Measure fromSize;

  @override
  _Measure? get toSize => toSizeTask.measure;

  @override
  double get averageCount => fromLength;

  @override
  double get currentSize => fromSize.value;

  @override
  bool get isMeasured => toSizeTask.isCompleted;

  @override
  bool get isMeasuring => toSizeTask.isMeasuring;

  @override
  FutureOr<bool> startMeasuring(_ListIntervalInterface interface) =>
      toSizeTask.start(interface, this);

  @override
  _ReadyToNewResizingInterval clone(int newItemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToNewResizingInterval(newItemCount, fromSize, fromLength);
  }

  @override
  Widget buildWidget(_ListIntervalInterface interface, BuildContext context,
      int index, bool measureOnly) {
    return _buildSizedBox(interface, fromSize.value);
  }

  @override
  void dispose() {
    toSizeTask.cancel();
    super.dispose();
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy([
        MapEntry('fs', fromSize),
        MapEntry('ts', toSizeTask.measure),
        MapEntry('fl', fromLength),
      ]);

  @override
  String get name => 'Rz->Rz';
}

//
// Intervals for Moving
//

/// It marks an interval, linked to a sub list of which it is holder, to have and be linked to a [_DropInterval].
///
/// Classes [_ReadyToMoveInterval] and [_ReadyToPopupMoveInterval] implement this.
abstract class _WithDropInterval implements _SubListHolderInterval {
  _DropInterval get dropInterval;

  double futureDeltaSize(double deltaTimeInSec) {
    var v = 0.0;
    for (final i in subList) {
      if (i is _AnimatedSpaceInterval) {
        v += i.futureSize(deltaTimeInSec) - i.currentSize;
      }
    }
    return v;
  }

  _SplitResult dropSplit(int leading, int trailing,
      [_UpdateCallback? middleUpdateCallback]) {
    assert(_debugAssertNotDisposed());
    // assert(middle == null || !createMiddle);
    assert(leading >= 0 && trailing >= 0);
    assert(leading + trailing <= subList.itemCount);
    // assert(!createMiddle || middle == null);
    return _performSplit(leading, trailing, null, true, middleUpdateCallback);
  }
}

/// This interval is born in pair with an interval that implements the [_WithDropInterval] interface.
/// It does not need to be built, but serves only to hold a bunch of items from the underlying list,
/// identified by the linked sub list, that are moved to the new position corresponding to the [itemOffset]
/// of this interval.
class _DropInterval extends _Interval implements _SubListInterval {
  _DropInterval(int debugId, this.withDropInterval) : super.id(debugId);

  final _WithDropInterval withDropInterval;

  @override
  int get buildCount => 0;

  @override
  int get itemCount => subList.itemCount;

  @override
  _IntervalList get subList => withDropInterval.subList;

  @override
  double get averageCount => 0;

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToMoveInterval &&
        leftInterval.dropInterval == this) {
      // ... ->Mv[1], Md[1] ... => ... (sub list) ...
      return _MergeResult(subList);
    }
    return null;
  }

  @override
  String get name => 'Md';
}

/// This interval is born in pair with a [_DropInterval], with which it will remain connected for life.
/// It is also linked to a sublist.
/// The interval is built by serially building all the items of its sublist.
/// The interval does not hold any items from the underlying list, as it is born only to construct items that have
/// actually been moved elsewhere in the underlying list. The position of its [_DropInterval] will reveal the
/// actual [itemOffset] position of these items.
class _ReadyToMoveInterval extends _Interval with _WithDropInterval {
  _ReadyToMoveInterval(this.subList) {
    subList.holder = this;
    dropInterval = _DropInterval(_debugId, this);
  }

  @override
  final _IntervalList subList;

  @override
  late final _DropInterval dropInterval;

  @override
  int get buildCount => subList.buildCount;

  @override
  int get itemCount => 0;

  @override
  int get parentBuildOffset => buildOffset;

  @override
  int get parentItemOffset => dropInterval.itemOffset;

  @override
  double get averageCount => subList.averageCount;

  @override
  void onChanged() {
    next?.invalidate();
    dropInterval.next?.invalidate();
  }

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _DropInterval && dropInterval == leftInterval) {
      // ... Md[1], ->Mv[1] ... => ... (sub list) ...
      return _MergeResult(subList);
    } else if (leftInterval is _ReadyToMoveInterval &&
        (dropInterval.previous == leftInterval.dropInterval)) {
      // ... Md[1], Md[2], ... ->Mv[1], ->Mv[2] ... => ... Md[3] ... ->Mv[3] ...
      leftInterval.subList.insertAfter(leftInterval.subList.last, subList);
      final newInterval = _ReadyToMoveInterval(leftInterval.subList);
      final r = _MergeResult(newInterval.iterable());
      list!.replace(() sync* {
        yield leftInterval.dropInterval;
        yield dropInterval;
      }(), newInterval.dropInterval.iterable());
      return r;
    }
    return null;
  }

  @override
  Widget buildWidget(_ListIntervalInterface interface, BuildContext context,
      int index, bool measureOnly) {
    assert(_debugAssertAttachedToList());
    return subList.build(context, index, measureOnly);
  }

  _ReadyToMoveInterval? _createSplitInterval(int itemCount) {
    if (itemCount == 0) return null;
    return _ReadyToMoveInterval(_IntervalList(list!.manager));
  }

  @override
  _SplitResult _performSplit(
      int leading,
      int trailing,
      Iterable<_Interval>? middle,
      bool createMiddle,
      _UpdateCallback? middleUpdateCallback) {
    assert(createMiddle);
    final middleItemCount = subList.itemCount - leading - trailing;
    final leftInterval = _createSplitInterval(leading);
    final rightInterval = _createSplitInterval(trailing);
    final middleInterval = _createSplitInterval(middleItemCount);
    final r = _SplitResult(
      leftInterval?.iterable(),
      rightInterval?.iterable(),
      middleInterval?.iterable(),
      subListSplitCallback: () {
        subList.split(leading, trailing, leftInterval?.subList,
            middleInterval?.subList, rightInterval?.subList);
        invalidate();
        dropInterval.invalidate();
      },
    );
    return r;
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy([
        MapEntry('sl', subList),
      ]);

  @override
  String get name => '->Mv';
}

/// This interval is born in pair with a [_DropInterval], with which it will remain connected for life.
/// It is also linked to a subl ist and a pop-up list.
/// The interval is built with a single still [SizedBox], which is generally derived from the spacing widget of an
/// interrupted [_MovingInterval] in its last size.
/// The interval does not hold any items from the underlying list, which are instead held by its [_DropInterval].
/// The interval is also responsible for building all the items in the sub list that is part of a chunk or
/// the entire popup.
class _ReadyToPopupMoveInterval extends _Interval
    with _WithDropInterval
    implements _SpaceInterval, _PopUpInterval {
  _ReadyToPopupMoveInterval(
      this.subList, this.popUpList, this.averageCount, this.currentSize) {
    subList.holder = this;
    subList.popUpList = popUpList;
    popUpList.updateScrollOffset = null;
    dropInterval = _DropInterval(_debugId, this);
  }

  @override
  final _IntervalList subList;

  @override
  final _MovingPopUpList popUpList;

  @override
  late final _DropInterval dropInterval;

  @override
  final double averageCount;

  @override
  final double currentSize;

  @override
  int get buildCount => 1;

  @override
  int get itemCount => 0;

  @override
  int get parentBuildOffset {
    final n = popUpList.subLists.indexOf(subList);
    var r = 0;
    for (var i = 0; i < n; i++) {
      final sl = popUpList.subLists[i];
      r += sl.buildCount;
    }
    return r;
  }

  @override
  int get parentItemOffset => dropInterval.itemOffset;

  @override
  void onChanged() {
    next?.invalidate();
    dropInterval.next?.invalidate();
  }

  // TODO: implement the mergeWith method
  // @override
  // MergeResult? mergeWith(Interval leftInterval) {
  //   assert(_debugAssertNotDisposed());
  //   return null;
  // }

  @override
  Widget buildWidget(_ListIntervalInterface interface, BuildContext context,
      int index, bool measureOnly) {
    return _buildSizedBox(interface, currentSize);
  }

  @override
  _SplitResult _performSplit(
      int leading,
      int trailing,
      Iterable<_Interval>? middle,
      bool createMiddle,
      _UpdateCallback? middleUpdateCallback) {
    assert(createMiddle);
    final itemCount = subList.itemCount;
    final currentLength = averageCount;
    final currentSize = this.currentSize;
    final middleItemCount = itemCount - leading - trailing;

    _ReadyToPopupMoveInterval? leftInterval, middleInterval, rightInterval;
    if (trailing > 0) {
      var fr = trailing / itemCount;
      rightInterval = _ReadyToPopupMoveInterval(_IntervalList(list!.manager),
          popUpList, currentLength * fr, currentSize * fr);
    }
    if (createMiddle && middleItemCount > 0) {
      var fm = middleItemCount / itemCount;
      middleInterval = _ReadyToPopupMoveInterval(_IntervalList(list!.manager),
          popUpList, currentLength * fm, currentSize * fm);
    }
    if (leading > 0) {
      var fl = leading / itemCount;
      leftInterval = _ReadyToPopupMoveInterval(_IntervalList(list!.manager),
          popUpList, currentLength * fl, currentSize * fl);
    }

    return _SplitResult(
      leftInterval?.iterable(),
      rightInterval?.iterable(),
      middleInterval?.iterable(),
      subListSplitCallback: () {
        subList.split(leading, trailing, leftInterval?.subList,
            middleInterval?.subList, rightInterval?.subList);

        final subListIndex = popUpList.subLists.indexOf(subList);
        assert(subListIndex >= 0);
        popUpList.subLists.removeAt(subListIndex);
        if (rightInterval != null) {
          popUpList.subLists.insert(subListIndex, rightInterval.subList);
        }
        if (middleInterval != null) {
          popUpList.subLists.insert(subListIndex, middleInterval.subList);
        }
        if (leftInterval != null) {
          popUpList.subLists.insert(subListIndex, leftInterval.subList);
        }

        invalidate();
        dropInterval.invalidate();
      },
      updateCallback: (list, index, oldBuildCount, newBuildCount) {
        list.addUpdate(index, oldBuildCount, newBuildCount);
      },
    );
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy([
        MapEntry('cs', currentSize),
        MapEntry('cl', averageCount),
        MapEntry('pl', popUpList.debugId),
        MapEntry('sl', subList),
      ]);

  @override
  String get name => '->Mp';
}

/// This interval is built with an animated [SizedBox], starting from scratch and increasing its size, which will
/// eventually host within it all the items of the linked sub list.
/// The interval is also responsabile to build all those items, that are rendered inside a linked popup.
/// The interval has two animations, the first related to the animated [SizedBox], and the second related to the
/// popup itself, which will move to reposition its items eventually within the [SizedBox].
/// The items in the underlying list are held by the interval itself, since although they are built inside the popup
/// it is as if they were already present in its [SizedBox].
class _MovingInterval extends _AnimatedSpaceInterval
    implements _PopUpInterval, _SubListHolderInterval {
  _MovingInterval(
      _ControlledAnimation animation,
      this._moveAnimation,
      _IntervalList subList,
      this.popUpList,
      _Measure toSize,
      this.startingScrollOffset)
      : super(animation, _Measure.zero, toSize, 0.0, subList.itemCount) {
    assert(popUpList.subLists.isEmpty);
    popUpList.subLists.add(subList);
    popUpList.lastBuildCount = subList.buildCount;
    popUpList.updateScrollOffset = updateToOffset;
    popUpList.currentScrollOffset = startingScrollOffset;

    subList.popUpList = popUpList;
    subList.holder = this;

    _moveAnimation.attachTo(this);
    _moveAnimation.animation.addListener(onMoveTick);
  }

  _MovingInterval.from(
    _MovingInterval i,
    double newToOffset,
  )   : _moveAnimation = i._moveAnimation,
        popUpList = i.popUpList,
        startingScrollOffset = i.popUpList.currentScrollOffset!,
        _toOffset = newToOffset,
        super(i.animation, _Measure(i.currentSize), i.toSize, i.averageCount,
            i.subList.itemCount) {
    _moveAnimation.animation.removeListener(i.onMoveTick);
    _moveAnimation.reset();
    _moveAnimation.attachTo(this);
    _moveAnimation.animation.addListener(onMoveTick);
    _moveAnimation.start();

    popUpList.updateScrollOffset = updateToOffset;
    subList.holder = this;
  }

  final _ControlledAnimation _moveAnimation;
  double startingScrollOffset;

  @override
  final _MovingPopUpList popUpList;

  double? _toOffset;
  double? get toOffset => _toOffset;

  @override
  int get itemCount => subList.itemCount;

  @override
  int get parentBuildOffset => 0;

  @override
  int get parentItemOffset => itemOffset;

  @override
  _IntervalList get subList => popUpList.subLists.single;

  double get durationInSec =>
      math.max(animation.durationInSec, _moveAnimation.durationInSec);

  double get elapsedTimeInSec =>
      (animation.durationInSec > _moveAnimation.durationInSec)
          ? animation.timeInSec
          : _moveAnimation.timeInSec;

  set toOffset(double? offset) {
    assert(offset != null);
    assert(_toOffset == null);
    _toOffset = offset;
  }

  @override
  bool get areAnimationsCompleted =>
      animation.isWaitingAtEnd && _moveAnimation.isWaitingAtEnd;

  @override
  void onChanged() {
    next?.invalidate();
  }

  @override
  void startAnimation() {
    super.startAnimation();
    _moveAnimation.start();
    // if (!(fromSize.value - toSize.value).isAcceptableResizeAmount;) {
    //   _moveAnimation.complete();
    // }
  }

  void updateToOffset(UpdateToOffsetCallback callback) {
    final buildIndex = buildOffset;
    final remainingTime = durationInSec - elapsedTimeInSec;
    final newToOffset =
        callback.call(buildIndex, list!.buildCount, remainingTime);
    if (_toOffset == null) {
      toOffset = newToOffset;
    } else {
      if ((_toOffset! - newToOffset).isAcceptableResizeAmount) {
        // print("##### CHANGED $this [$_toOffset -> $newToOffset] ");
        callback.call(buildIndex, list!.buildCount, remainingTime);
        final n = _MovingInterval.from(this, newToOffset);
        list!.replace(
          iterable(),
          n.iterable(),
        );
      }
    }
  }

  void onMoveTick() {
    if (_disposed) return;
    if (_toOffset != null) {
      // final oldOffset = popUpList.currentScrollOffset!;
      final newOffset = (startingScrollOffset +
              _moveAnimation.value * (_toOffset! - startingScrollOffset))
          .ceil() // it needs, otherwise with addRepaintBoundary you have annoying flickering!
          .toDouble();

      popUpList.currentScrollOffset = newOffset;
    }
    list?.manager.onMovingTick();
  }

  @override
  _SplitResult _performSplit(
      int leading,
      int trailing,
      Iterable<_Interval>? middle,
      bool createMiddle,
      _UpdateCallback? middleUpdateCallback) {
    assert(createMiddle || (middle?.buildCount ?? 0) == 0);
    final itemCount = this.itemCount;
    final currentLength = averageCount;
    final currentSize = this.currentSize;
    final middleItemCount = itemCount - leading - trailing;

    _ReadyToPopupMoveInterval? leftInterval, middleInterval, rightInterval;
    if (leading > 0) {
      var fl = leading / itemCount;
      leftInterval = _ReadyToPopupMoveInterval(_IntervalList(list!.manager),
          popUpList, currentLength * fl, currentSize * fl);
    }
    if (createMiddle && middleItemCount > 0) {
      var fm = middleItemCount / itemCount;
      middleInterval = _ReadyToPopupMoveInterval(_IntervalList(list!.manager),
          popUpList, currentLength * fm, currentSize * fm);
    }
    if (trailing > 0) {
      var fr = trailing / itemCount;
      rightInterval = _ReadyToPopupMoveInterval(_IntervalList(list!.manager),
          popUpList, currentLength * fr, currentSize * fr);
    }

    return _SplitResult(
      () sync* {
        if (leftInterval != null) {
          yield leftInterval;
          yield leftInterval.dropInterval;
        }
      }(),
      () sync* {
        if (rightInterval != null) {
          yield rightInterval;
          yield rightInterval.dropInterval;
        }
      }(),
      createMiddle ? middleInterval?.iterable() : middle,
      subListSplitCallback: () {
        subList.split(leading, trailing, leftInterval?.subList,
            middleInterval?.subList, rightInterval?.subList);

        popUpList.subLists.clear();
        if (leftInterval != null) {
          popUpList.subLists.add(leftInterval.subList);
        }
        if (middleInterval != null) {
          popUpList.subLists.add(middleInterval.subList);
        }
        if (rightInterval != null) {
          popUpList.subLists.add(rightInterval.subList);
        }

        invalidate();
      },
      updateCallback: (list, index, oldBuildCount, newBuildCount) {
        list.addUpdate(index, oldBuildCount, newBuildCount);
      },
    );
  }

  @override
  void dispose() {
    _moveAnimation.detachFrom(this);
    super.dispose();
  }

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy([
        MapEntry('mt', _moveAnimation.time),
        MapEntry('fl', fromLength),
        MapEntry('fz', fromSize),
        MapEntry('tz', toSize),
        MapEntry('to', toOffset),
        MapEntry('sl', subList),
      ]);

  @override
  String get name => 'Mv';
}

//
// Intervals for Reordering
//

/// This interval does not need to be built, but only serves to hold the underlying list item being reordered.
class _ReorderHolderInterval extends _Interval implements _SubListInterval {
  @override
  int get buildCount => 0;

  @override
  int get itemCount => 1;

  @override
  _IntervalList get subList =>
      list!.manager.reorderLayoutData!.openingInterval.subList;

  @override
  String get name => 'Rh';
}

/// This interval is built as an animated [SizedBox] that is closing, resulting from the passage of the item
/// being reordered that has changed position.
class _ReorderClosingInterval extends _AnimatedSpaceInterval {
  _ReorderClosingInterval(_ControlledAnimation animation, double fromSize)
      : super(animation, fromSize.toExactMeasure(), _Measure.zero, 1, 0);

  @override
  String get name => 'Rc';
}

/// This interval is built as an animated [SizedBox] that is opening to accommodate within it the item
/// being reordered.
/// The interval does not hold any items in the underlying list, since the item has not yet actually been moved,
/// but its actual position is held by the unique [_ReorderHolderInterval].
/// The interval is also responsible for building the item being reordered, which will be rendered within a popup
/// linked to it.
/// When the item is finally released, this interval will turn into a [_MovingInterval].
class _ReorderOpeningInterval extends _AnimatedSpaceInterval
    implements _PopUpInterval, _SubListHolderInterval {
  _ReorderOpeningInterval(
      this.holder,
      _ControlledAnimation animation,
      double fromSize,
      double toSize,
      this.popUpList,
      _ListIntervalInterface interface)
      : assert(!holder._disposed),
        super(animation, fromSize.toExactMeasure(), toSize.toExactMeasure(), 0,
            1) {
    subList.holder = this;
  }

  final _ReorderHolderInterval holder;

  @override
  final _ReorderPopUpList popUpList;

  @override
  int get itemCount => 0;

  @override
  int get parentBuildOffset => 0;

  @override
  int get parentItemOffset => holder.itemOffset;

  @override
  _IntervalList get subList => popUpList.intervalList;

  @override
  void onChanged() {}

  @override
  Iterable<MapEntry<String?, Object?>> get attributes =>
      super.attributes.followedBy([
        MapEntry('pl', popUpList.debugId),
      ]);

  @override
  String get name => 'Ro';
}

//

class _SplitBuildCounts {
  final int left, middle, right;

  const _SplitBuildCounts(this.left, this.middle, this.right);
}

mixin _SplitMixin implements _Interval {
  _Interval? _createSplitInterval(int buildCount, int itemCount, int offset) {
    if (itemCount == 0 && buildCount == 0) return null;
    return buildCount == 0
        ? _ReadyToResizingSpawnedInterval(itemCount)
        : createSplitInterval(buildCount, itemCount, offset);
  }

  _Interval createSplitInterval(int buildCount, int itemCount, int offset);

  _SplitBuildCounts splitCounts(int leading, int middle, int trailing);

  _SplitBuildCounts _basicSplitCounts(int leading, int middle, int trailing) =>
      _SplitBuildCounts(leading, middle, trailing);

  _SplitBuildCounts _sizedBoxSplitCounts(
          int leading, int middle, int trailing) =>
      _SplitBuildCounts(
          leading > 0 ? 1 : 0, middle > 0 ? 1 : 0, trailing > 0 ? 1 : 0);

  _SplitBuildCounts _complexSplitCounts(int leading, int middle, int trailing) {
    final leftBuildCount = math.min(leading, buildCount);
    var middleBuildCount =
        math.min(itemCount - trailing - leading, buildCount - leftBuildCount);
    final int rightBuildCount;
    if (trailing == 0) {
      rightBuildCount = 0;
      middleBuildCount += buildCount - leftBuildCount - middleBuildCount;
    } else {
      rightBuildCount = buildCount - leftBuildCount - middleBuildCount;
    }
    return _SplitBuildCounts(leftBuildCount, middleBuildCount, rightBuildCount);
  }

  bool get forceRebuild => false;

  @override
  _SplitResult _performSplit(
      int leading,
      int trailing,
      Iterable<_Interval>? middle,
      bool createMiddle,
      _UpdateCallback? middleUpdateCallback) {
    final middleItemCount = itemCount - leading - trailing;
    final buildCounts = splitCounts(leading, middleItemCount, trailing);
    return _SplitResult(
      _createSplitInterval(buildCounts.left, leading, 0)?.iterable(),
      _createSplitInterval(buildCounts.right, trailing,
              buildCounts.left + buildCounts.middle)
          ?.iterable(),
      createMiddle
          ? _createSplitInterval(
                  buildCounts.middle, middleItemCount, buildCounts.left)
              ?.iterable()
          : middle,
      updateCallback: (list, index, oldBuildCount, newBuildCount) {
        if (forceRebuild) {
          list.addUpdate(index, oldBuildCount, newBuildCount);
        }
        if (!createMiddle) {
          middleUpdateCallback?.call(list, index + buildCounts.left,
              buildCounts.middle, middle?.buildCount ?? 0);
        }
      },
    );
  }
}

mixin _ResizingSplitMixin on _SplitMixin implements _ResizableInterval {
  @override
  _ReadyToNewResizingInterval createSplitInterval(
          int buildCount, int itemCount, int offset) =>
      _ReadyToNewResizingInterval(
          itemCount,
          _Measure(currentSize * itemCount / this.itemCount),
          averageCount * itemCount / this.itemCount);

  @override
  _SplitBuildCounts splitCounts(int leading, int middle, int trailing) =>
      _sizedBoxSplitCounts(leading, middle, trailing);

  @override
  bool get forceRebuild => true;
}

class _DebugBox extends _DebugWidget {
  _DebugBox(Widget child, this.interval)
      : super(child, () => 'SizedBox(${interval._debugId})');

  final _Interval interval;
}
