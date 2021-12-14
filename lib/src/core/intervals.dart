part of 'core.dart';

const double _kMinAcceptableResizeAmount = 1.0;

bool _isAccetableResizeAmount(double delta) =>
    delta.abs() >= _kMinAcceptableResizeAmount;

class _SplitResult {
  const _SplitResult(this.left, this.right);
  final _Interval? left, right;
}

class _MergeResult {
  const _MergeResult(this.mergedInterval, [this.physicalMerge = false]);
  final _Interval mergedInterval;
  final bool physicalMerge;
}

class _Cancelled {
  bool value = false;
}

/// Base class of all kind of intervals.
///
/// It defines the [buildCount] getter method to provide the count of the items covered by this interval
/// for building purpose and the [itemCount] getter method to provide the actual count of the items covered
/// of the underlying list.
///
/// It defines the [buildWidget] method usedd to build a covered item at a specific index.
///
/// It also defines the [mergeWith] method to give the opportunity to merge this interval with another intevral
/// for optimization purpose.
///
/// Eventually intervals can be disposed.
abstract class _Interval extends LinkedListEntry<_Interval> {
  _IntervalList get intervalList => list as _IntervalList;

  int get buildCount;

  int get itemCount;

  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    return null;
  }

  Widget buildWidget(BuildContext context, int buildIndexOffset,
          int listIndexOffset, bool measureOnly) =>
      throw UnimplementedError('This interval is not meant to be built');

  @mustCallSuper
  void dispose() {
    assert(_debugAssertNotDisposed());
    list!.remove(this);
    assert(list == null);
  }

  bool _debugAssertNotDisposed() {
    assert(() {
      if (list == null) {
        throw FlutterError(
          'A $runtimeType was used after being disposed.\n'
          'Once you have called dispose() on a $runtimeType, it can no longer be used.',
        );
      }
      return true;
    }());
    return true;
  }

  String toShortString() => '$buildCount,$itemCount';

  @override
  String toString() => 'b: $buildCount, i: $itemCount';
}

/// Interval with animation feature.
///
/// An animation will be attached to this interval and automatically detached when the latter is disposed.
abstract class _AnimatedInterval extends _Interval {
  _AnimatedInterval(this._animation) {
    _animation.attachTo(this);
  }

  final _Animation _animation;

  bool get isWaitingAtBeginning => _animation.isWaitingAtBeginning;

  bool get isWaitingAtEnd => _animation.isWaitingAtEnd;

  @override
  void dispose() {
    _animation.detachFrom(this);
    super.dispose();
  }

  @override
  String toString() => '${super.toString()}, t: ${_animation.time}';
}

/// Interval that builds a range of items covered of the underlying list with animation.
abstract class _InListItemInterval extends _AnimatedInterval {
  _InListItemInterval(_Animation animation, this.length)
      : assert(length >= 0),
        super(animation);

  final int length;

  @override
  int get buildCount => length;

  @override
  int get itemCount => length;

  @override
  Widget buildWidget(BuildContext context, int buildIndexOffset,
      int listIndexOffset, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    return intervalList.inListBuilder.call(
        buildIndexOffset,
        listIndexOffset,
        AnimatedWidgetBuilderData(_animation.animation,
            measuring: measureOnly));
  }
}

/// Animated interval that builds a range of an off-list items (for example a range of removed
/// or changed items no longer present in the underlying list).
/// The [inLength] of the underlying items covered is preserved.
abstract class _OffListItemInterval extends _AnimatedInterval {
  _OffListItemInterval(
      _Animation animation, this.builder, this.offLength, this.inLength)
      : assert(offLength >= 0 && inLength >= 0),
        super(animation);

  final _IntervalBuilder builder;

  final int offLength, inLength;

  @override
  int get buildCount => offLength;

  @override
  int get itemCount => inLength;

  @override
  Widget buildWidget(BuildContext context, int buildIndexOffset,
      int listIndexOffset, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    return builder.call(
        context,
        buildIndexOffset,
        listIndexOffset,
        AnimatedWidgetBuilderData(_animation.animation,
            measuring: measureOnly));
  }
}

/// Interval that doesn't build any items but just holds some items of the underlying list.
abstract class _HolderInterval extends _Interval {
  _HolderInterval(this.length) : assert(length > 0);

  final int length;

  @override
  int get buildCount => 0;

  @override
  int get itemCount => length;
}

/// This interface marks an interval to be able to be full or partially transformed
/// into a [_ReadyToRemovalInterval], [_ReadyToResizingSpawnedInterval] or [_ReadyToChangingInterval].
///
/// Class [_NormalInterval], [_InsertionInterval] and [_ReadyToChangingInterval] implement this.
///
/// This mark is checked by the [_IntervalList._onReplaceNotification] and
/// [_IntervalList._onReplaceNotification] methods.
abstract class _SplittableInterval implements _AnimatedInterval {
  /// Splits this interval in the middle by creating two new intervals on the left (if [leading] is
  /// greater than zero) and right (if [trailing] is greater then zero).
  _SplitResult split(int leading, int trailing);
}

/// This interface marks an interval to be able to adjust the count of the covered items of the
/// underlying list without changing its build.
///
/// Classes [_ReadyToRemovalInterval], [_RemovalInterval], [_ReadyToResizingIntervalFromRemoval],
/// [_ReadyToNewResizingInterval] and [_ReadyToResizingSpawnedInterval] implement this.
///
/// This mark is checked by the [_IntervalList._onReplaceNotification] method.
abstract class _AdjustableInterval extends _Interval {
  /// Clones this interval providing a new item count of the underlying list.
  _AdjustableInterval? cloneWithNewLenght(int newItemCount);
}

/// This interface marks an interval to be a space interval.
///
/// A space interval is built as a single item but covers many items of the underlying list.
///
/// This mark is checked by the [AnimatedRenderSliverMultiBoxAdaptor._extrapolateMaxScrollOffset],
/// [AnimatedRenderSliverMultiBoxAdaptor._estimateLayoutOffset], 
/// [AnimatedRenderSliverFixedExtentList.indexToLayoutOffset],
/// [AnimatedRenderSliverFixedExtentList.computeMaxScrollOffset],
/// [AnimatedRenderSliverFixedExtentList.getMinChildIndexForScrollOffset] and
/// [AnimatedRenderSliverFixedExtentList.getMaxChildIndexForScrollOffset] methods.
abstract class _SpaceInterval {
  /// The current size of the space interval.
  double get currentSize;

  /// The current average count of the covered items of the underlying list.
  double get currentLength;
}

/// This interface marks a space interval to be able to be transformed into a [_ReadyToNewResizingInterval],
/// giving to it its [currentSize] as the initial size.
///
/// This kind of interval has to provide the [stop] method to interrupt its animation.
///
/// Classes [_ResizingInterval], [_ReadyToInsertionInterval] and [_ReadyToNewResizingInterval] implement this.
///
/// This mark is checked by the [_IntervalList._onReplaceNotification] and
/// [_IntervalList._onReplaceNotification] methods.
abstract class _ResizableInterval extends _SpaceInterval {
  void stop();
}

/// Interval that is built as an animated space interval.
class _AnimatedSpaceInterval extends _AnimatedInterval
    implements _SpaceInterval {
  _AnimatedSpaceInterval(_Animation animation, this.fromSize, this.toSize,
      this.fromLength, this.toLength)
      : lastRenderedSize = fromSize.value,
        super(animation) {
    _animation.animation.addListener(onTick);
  }

  final _Measure fromSize, toSize;

  final double fromLength;
  final int toLength;

  double lastRenderedSize;

  void onTick() {
    final delta = currentSize - lastRenderedSize;
    if (delta != 0.0) {
      intervalList.interface.resizingIntervalUpdated(this, delta);
      lastRenderedSize = currentSize;
    }
  }

  @override
  void dispose() {
    _animation.animation.removeListener(onTick);
    super.dispose();
  }

  @override
  double get currentLength {
    if (_animation.time == 0.0) {
      return fromLength;
    } else if (_animation.time == 1.0) {
      return toLength.toDouble();
    } else {
      return fromLength + _animation.animation.value * (toLength - fromLength);
    }
  }

  @override
  double get currentSize {
    if (_animation.time == 0.0) {
      return fromSize.value;
    } else if (_animation.time == 1.0) {
      return toSize.value;
    } else {
      return fromSize.value +
          _animation.animation.value * (toSize.value - fromSize.value);
    }
  }

  bool get canCompleteImmediately {
    return !_isAccetableResizeAmount(fromSize.value - toSize.value);
  }

  @override
  int get buildCount => 1;

  @override
  int get itemCount => toLength;

  @override
  Widget buildWidget(BuildContext context, int buildIndexOffset,
      int listIndexOffset, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    final tween = Tween<double>(begin: fromSize.value, end: toSize.value);
    final horizontal = intervalList.interface.isHorizontal;
    if (measureOnly) {
      return SizedBox(
        width: horizontal ? tween.evaluate(_animation.animation) : null,
        height: !horizontal ? tween.evaluate(_animation.animation) : null,
      );
    }
    final animation = tween.animate(_animation.animation);
    return AnimatedBuilder(
        animation: animation,
        builder: (context, child) => SizedBox(
              width: horizontal ? animation.value : null,
              height: !horizontal ? animation.value : null,
            ));
  }
}

/// Marks an inteval to be ready to be transformed into another kind of interval.
///
/// A [priority] must be given which is used to transform the intervals based on priorities.
abstract class _ReadyToInterval {
  int get priority;
}

/// Marks an interval that is ready to be changed into a [_ResizingInterval].
///
/// The resizing interval has to be measured first; the [isMeasured] method should return `true`
/// if it is ready to be transformed.
///
/// This mixin helps these kind of intervals measure their covered items to give the overall
/// from and to sizes to the new resizing interval.
///
/// Classes [_ReadyToResizingIntervalFromRemoval], [_ReadyToNewResizingInterval] and
/// [_ReadyToResizingSpawnedInterval] implement this.
///
/// This mark is checked by the [_IntervalList.coordinate] method.
mixin _ReadyToResizingInterval implements _Interval, _ReadyToInterval {
  _Measure? fromSize, toSize;

  _Cancelled? cancelled;

  bool isMeasuring = false;

  double get fromLength;

  Future<void> measure() async {
    assert(_debugAssertNotDisposed());
    assert(cancelled == null);

    cancelled = _Cancelled();
    isMeasuring = true;

    if (fromSize == null) {
      await measureFromSize();
    }

    if (!cancelled!.value && toSize == null) {
      if (itemCount == 0) {
        toSize = _Measure.zero;
      } else {
        await measureToSize();
      }
    }

    isMeasuring = false;
    cancelled = null;
  }

  void cancel() {
    cancelled?.value = true;
  }

  Future<void> measureFromSize() async {}

  Future<void> measureToSize() async {
    toSize = await intervalList.interface.measureItems(
        cancelled!,
        itemCount,
        (context, index) => intervalList.inListBuilder.call(
            index,
            intervalList.listItemIndexOf(this),
            AnimatedWidgetBuilderData(kAlwaysCompleteAnimation,
                measuring: true)));
  }

  bool get isMeasured => fromSize != null && toSize != null;
}

/// Marks an interval that can also build one or more pop-up items.
/// A [popUpList] is linked to it.
abstract class _PopUpInterval extends _Interval {
  Widget buildPopUpWidget(BuildContext context, int buildIndexOffset,
      int listIndexOffset, bool measureOnly);

  int get popUpBuildCount;

  _SingleElementPopUpList get popUpList;
}

/// Marks a pop-up interval that can be removed.
///
/// This mark is checked by the [_IntervalList._onReplaceNotification] method.
abstract class _PopUpRemovableInterval extends _PopUpInterval {
  void remove(int priority);
}

/// Marks a pop-up interval that can be changed.
///
/// This mark is checked by the [_IntervalList._onChangeNotification] method.
abstract class _PopUpChangeableInterval extends _PopUpInterval {
  void change(double newItemSize);
}

//
// Core Intervals
//

/// Interval that builds a piece of the underlying list in a full visible fashion.
class _NormalInterval extends _InListItemInterval
    implements _SplittableInterval {
  _NormalInterval(int length) : super(const _CompletedAnimation(), length);

  @override
  _SplitResult split(int leading, int trailing) {
    assert(_debugAssertNotDisposed());
    return _SplitResult(
      leading > 0 ? _NormalInterval(leading) : null,
      trailing > 0 ? _NormalInterval(trailing) : null,
    );
  }

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _NormalInterval) {
      return _MergeResult(_NormalInterval(length + leftInterval.length));
    }
    return null;
  }

  @override
  String toShortString() => 'Nm(${super.toShortString()})';

  @override
  String toString() => 'Nm (${super.toString()})';
}

/// Interval that it is ready to be changed into a [_RemovalInterval].
///
/// It is created against a [_SplittableInterval].
class _ReadyToRemovalInterval extends _OffListItemInterval
    implements _AdjustableInterval, _ReadyToInterval {
  _ReadyToRemovalInterval(_Animation animation, _IntervalBuilder builder,
      int offLength, int inLength, this.priority)
      : super(animation, builder, offLength, inLength);

  @override
  final int priority;

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToRemovalInterval &&
        leftInterval._animation is _CompletedAnimation &&
        _animation is _CompletedAnimation &&
        leftInterval.priority == priority) {
      final ret = _MergeResult(_ReadyToRemovalInterval(
          _animation,
          _joinBuilders(leftInterval.builder, builder, leftInterval.offLength),
          leftInterval.offLength + offLength,
          leftInterval.inLength + inLength,
          priority));
      return ret;
    } else if (leftInterval is _ReadyToResizingSpawnedInterval &&
        leftInterval.priority == priority) {
      return _MergeResult(_ReadyToRemovalInterval(_animation, builder,
          offLength, leftInterval.itemCount + inLength, priority));
    }
    return null;
  }

  @override
  _ReadyToRemovalInterval cloneWithNewLenght(int newItemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToRemovalInterval(
        _animation, builder, offLength, newItemCount, priority);
  }

  @override
  String toShortString() => '->Rm(${super.toShortString()})';

  @override
  String toString() => '->Rm (${super.toString()})';
}

/// Interval that is dismissing a range of items no longer present in the underlying list.
///
/// It is created against a [_ReadyToRemovalInterval].
class _RemovalInterval extends _OffListItemInterval
    implements _AdjustableInterval {
  _RemovalInterval(_Animation animation, _IntervalBuilder builder,
      int offLength, int inLength, this.priority)
      : super(animation, builder, offLength, inLength);

  final int priority;

  @override
  _RemovalInterval cloneWithNewLenght(int newItemCount) {
    assert(_debugAssertNotDisposed());
    return _RemovalInterval(
        _animation, builder, offLength, newItemCount, priority);
  }

  @override
  String toShortString() => 'Rm(${super.toShortString()})';

  @override
  String toString() => 'Rm (${super.toString()})';
}

/// Interval that is showing up an incoming range of items of the underlying list.
///
/// It is created against a [_ReadyToInsertionInterval] or [_ReadyToChangingInterval].
class _InsertionInterval extends _InListItemInterval
    implements _SplittableInterval {
  _InsertionInterval(_Animation animation, int length)
      : super(animation, length);

  @override
  _SplitResult split(int leading, int trailing) {
    assert(_debugAssertNotDisposed());
    return _SplitResult(
      leading > 0 ? _InsertionInterval(_animation, leading) : null,
      trailing > 0 ? _InsertionInterval(_animation, trailing) : null,
    );
  }

  @override
  String toShortString() => 'In(${super.toShortString()})';

  @override
  String toString() => 'In (${super.toString()})';
}

/// Interval that is resizing an empty space which is getting bigger or smaller, going from
/// an initial size to a final size.
///
/// It is created against a [_ReadyToResizingInterval].
class _ResizingInterval extends _AnimatedSpaceInterval
    implements _ResizableInterval {
  _ResizingInterval(_ControlledAnimation animation, _Measure fromSize,
      _Measure toSize, double fromLength, int toLength, this.priority)
      : super(animation, fromSize, toSize, fromLength, toLength);

  final int priority;

  @override
  void stop() {
    assert(_debugAssertNotDisposed());
    (_animation as _ControlledAnimation).stop();
  }

  @override
  String toShortString() => 'Rz(${super.toShortString()})';

  @override
  String toString() =>
      'Rz (${super.toString()}, fs: $fromSize, ts: $toSize, cs: $currentSize)';
}

/// Interval showing an empty space that it is ready to be changed into an [_InsertionInterval].
///
/// It is created against a [_ResizingInterval].
class _ReadyToInsertionInterval extends _Interval
    implements _ResizableInterval, _ReadyToInterval {
  _ReadyToInsertionInterval(this.toSize, this.toLength, this.priority)
      : assert(toLength >= 0);

  final _Measure toSize;

  final int toLength;

  @override
  final int priority;

  @override
  double get currentLength => toLength.toDouble();

  @override
  void stop() {
    assert(_debugAssertNotDisposed());
  }

  @override
  double get currentSize => toSize.value;

  @override
  int get buildCount => 1;

  @override
  int get itemCount => toLength;

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToInsertionInterval &&
        leftInterval.priority == priority) {
      return _MergeResult(
          _ReadyToInsertionInterval(leftInterval.toSize + toSize,
              leftInterval.toLength + toLength, priority),
          true);
    }
    return null;
  }

  @override
  Widget buildWidget(BuildContext context, int buildIndexOffset,
      int listIndexOffset, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    final horizontal = intervalList.interface.isHorizontal;
    return SizedBox(
        width: horizontal ? toSize.value : null,
        height: !horizontal ? toSize.value : null);
  }

  @override
  String toShortString() => 'Rz->In(${super.toShortString()})';

  @override
  String toString() => 'Rz->In (${super.toString()})';
}

/// Interval that finished its dismissing animation and it is ready to be changed into
/// a [_ResizingInterval].
///
/// It is created against a [_RemovalInterval].
class _ReadyToResizingIntervalFromRemoval extends _OffListItemInterval
    with _ReadyToResizingInterval
    implements _AdjustableInterval {
  _ReadyToResizingIntervalFromRemoval(_Animation animation,
      _IntervalBuilder builder, int offLength, int inLength, this.priority)
      : super(animation, builder, offLength, inLength);

  @override
  final int priority;

  @override
  _ReadyToResizingIntervalFromRemoval cloneWithNewLenght(int newItemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToResizingIntervalFromRemoval(
        _animation, builder, offLength, newItemCount, priority);
  }

  @override
  Future<void> measureFromSize() async {
    final listItemOffset = intervalList.listItemIndexOf(this);
    fromSize = await intervalList.interface.measureItems(
        cancelled!,
        offLength,
        (context, index) => builder.call(
            context,
            index,
            listItemOffset,
            AnimatedWidgetBuilderData(kAlwaysDismissedAnimation,
                measuring: true)));
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  @override
  double get fromLength => offLength.toDouble();

  @override
  String toShortString() => 'Rm->Rz(${super.toShortString()})';

  @override
  String toString() => 'Rm->Rz (${super.toString()})';
}

/// Interval that stopped its resizing animation, or was waiting for insertion or to be resized again,
/// and it is ready to be changed into a new [_ResizingInterval].
///
/// It is created against a [_ResizableInterval].
class _ReadyToNewResizingInterval extends _Interval
    with _ReadyToResizingInterval
    implements _AdjustableInterval, _SpaceInterval {
  _ReadyToNewResizingInterval(
      double fromSize, this.toLength, this.currentLength, this.priority)
      : assert(fromSize >= 0 && toLength >= 0) {
    this.fromSize = fromSize.toExactMeasure();
  }

  final int toLength;

  @override
  final int priority;

  @override
  final double currentLength;

  @override
  _ReadyToNewResizingInterval cloneWithNewLenght(int newItemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToNewResizingInterval(
        fromSize!.value, newItemCount, currentLength, priority);
  }

  @override
  double get currentSize => fromSize!.value;

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  @override
  int get buildCount => 1;

  @override
  int get itemCount => toLength;

  @override
  double get fromLength => currentLength;

  @override
  Widget buildWidget(BuildContext context, int buildIndexOffset,
      int listIndexOffset, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    final horizontal = intervalList.interface.isHorizontal;
    return SizedBox(
        width: horizontal ? fromSize!.value : null,
        height: !horizontal ? fromSize!.value : null);
  }

  @override
  String toShortString() => 'Rz->Rz(${super.toShortString()})';

  @override
  String toString() => 'Rz->Rz (${super.toString()})';
}

/// Interval that spawned from nothing and it is ready to be changed into a [_ResizingInterval].
///
/// It is created against a [_SplittableInterval].
class _ReadyToResizingSpawnedInterval extends _HolderInterval
    with _ReadyToResizingInterval
    implements _AdjustableInterval {
  _ReadyToResizingSpawnedInterval(int inLength, this.priority)
      : super(inLength) {
    fromSize = _Measure.zero;
  }

  @override
  final int priority;

  @override
  _ReadyToResizingSpawnedInterval? cloneWithNewLenght(int newItemCount) {
    assert(_debugAssertNotDisposed());
    if (newItemCount == 0) return null;
    return _ReadyToResizingSpawnedInterval(newItemCount, priority);
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  @override
  double get fromLength => 0;

  @override
  String toShortString() => '->Rz(${super.toShortString()})';

  @override
  String toString() => '->Rz (${super.toString()})';
}

/// Interval that is ready to rebuild the covered items of the underlying list.
///
/// The interval builds the old covered items of the underlying list waiting to be changed into
/// a [_NormalInterval] or [_InsertionInterval].
///
/// It is created against a [_SplittableInterval].
class _ReadyToChangingInterval extends _OffListItemInterval
    implements _SplittableInterval, _ReadyToInterval {
  _ReadyToChangingInterval(
      _Animation animation, _IntervalBuilder builder, int length, this.priority)
      : super(animation, builder, length, length);

  @override
  final int priority;

  @override
  _SplitResult split(
    int leading,
    int trailing,
  ) {
    return _SplitResult(
      leading > 0
          ? _ReadyToChangingInterval(_animation, builder, leading, priority)
          : null,
      trailing > 0
          ? _ReadyToChangingInterval(
              _animation,
              _offsetIntervalBuilder(builder, itemCount - trailing),
              trailing,
              priority)
          : null,
    );
  }

  @override
  _MergeResult? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToChangingInterval &&
        leftInterval._animation is _CompletedAnimation &&
        _animation is _CompletedAnimation &&
        leftInterval.priority == priority) {
      return _MergeResult(_ReadyToChangingInterval(
          _animation,
          _joinBuilders(leftInterval.builder, builder, leftInterval.offLength),
          leftInterval.inLength + inLength,
          priority));
    }
    return null;
  }

  @override
  String toString() => '->Ch (${super.toString()})';

  @override
  String toShortString() => '->Ch(${super.toShortString()})';
}

//
// Intervals for Reordering & Moving
//

class _ReorderSpaceInterval extends _AnimatedSpaceInterval {
  _ReorderSpaceInterval(
      _Animation animation, this.itemSize, double fromSize, double toSize)
      : super(animation, fromSize.toExactMeasure(), toSize.toExactMeasure(), 0,
            0);

  final double itemSize;

  @override
  double get currentLength => currentSize / itemSize;
}

/// Interval created during reordering that indicates an opening gap between two items.
class _ReorderOpeningInterval extends _ReorderSpaceInterval {
  _ReorderOpeningInterval(
      _Animation animation, double itemSize, double fromSize)
      : super(animation, itemSize, fromSize, itemSize);

  @override
  String toShortString() => 'Ro(${super.toShortString()})';

  @override
  String toString() => 'Ro (${super.toString()})';
}

/// Interval created during reordering that indicates a closing gap between two items.
class _ReorderClosingInterval extends _ReorderSpaceInterval {
  _ReorderClosingInterval(
      _Animation animation, double itemSize, double fromSize)
      : super(animation, itemSize, fromSize, 0);

  @override
  String toShortString() => 'Rc(${super.toShortString()})';

  @override
  String toString() => 'Rc (${super.toString()})';
}

/// Interval created during reordering indicating that the item of the underlying list covered
/// is the dragged item that is being built as a normal pop-up item.
class _ReorderHolderNormalInterval extends _HolderInterval
    implements _PopUpRemovableInterval, _PopUpChangeableInterval {
  _ReorderHolderNormalInterval(this.popUpList) : super(1) {
    popUpList.interval = this;
  }

  @override
  final _SingleElementPopUpList popUpList;

  @override
  int get popUpBuildCount => 1;

  @override
  void remove(int priority) {
    intervalList.reorderCloseAll();
    dispose();
  }

  @override
  void change(double newItemSize) {
    intervalList.reorderChangeOpeningIntervalSize(newItemSize);
  }

  @override
  Widget buildPopUpWidget(BuildContext context, int buildIndexOffset,
      int listIndexOffset, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    assert(buildIndexOffset == 0);
    return intervalList.inListBuilder.call(
        buildIndexOffset,
        listIndexOffset,
        AnimatedWidgetBuilderData(kAlwaysCompleteAnimation,
            measuring: measureOnly, dragging: true, slot: popUpList.slot));
  }

  @override
  String toShortString() => 'Rh(${super.toShortString()})';

  @override
  String toString() => 'Rh (${super.toString()})';
}

/// This interval cannot be build and doesn't hold any underlying item.
/// It is just linked to a pop-up list in order to build an off-list pop-up removing item.
/// Those kind of intevrals are added at the end of the interval list in order to be treated as if they were unlinked.
class _MoveRemovingInterval extends _AnimatedInterval
    implements _PopUpInterval {
  _MoveRemovingInterval(this.popUpList, _Animation animation, this.builder)
      : super(animation) {
    popUpList.interval = this;
  }

  @override
  final _SingleElementPopUpList popUpList;

  final _IntervalBuilder builder;

  @override
  int get buildCount => 0;

  @override
  int get itemCount => 0;

  @override
  int get popUpBuildCount => 1;

  @override
  Widget buildPopUpWidget(BuildContext context, int buildIndexOffset,
      int listIndexOffset, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    return builder.call(
        context,
        buildIndexOffset,
        listIndexOffset,
        AnimatedWidgetBuilderData(_animation.animation,
            measuring: measureOnly, slot: popUpList.slot));
  }

  @override
  String toShortString() => 'Mrm(${super.toShortString()})';

  @override
  String toString() => 'Mrm (${super.toString()})';
}

/// This interval is built as an animated space interval.
/// In addition, this interval is linked to a pop-up list of moving items.
/// The [moveAnimation] is used to calculate the scroll offset of the moving items.
class _MoveDropInterval extends _AnimatedSpaceInterval
    implements _PopUpRemovableInterval, _PopUpChangeableInterval {
  _MoveDropInterval(this.popUpList, _Animation animation, this.moveAnimation,
      this.itemSize, double fromSize, this.fromOffset)
      : super(animation, fromSize.toExactMeasure(), itemSize.toExactMeasure(),
            1, 1) {
    popUpList.interval = this;
    moveAnimation.attachTo(this);
    moveAnimation.animation.addListener(onMoveTick);
  }

  @override
  final _SingleElementPopUpList popUpList;

  final _ControlledAnimation moveAnimation;
  final double itemSize;
  double fromOffset;
  double? _toOffset;

  double? get toOffset => _toOffset;

  set toOffset(double? offset) {
    if (_toOffset != offset) {
      if (_toOffset != null) fromOffset = currentScrollOffset;
      moveAnimation.reset();
      _toOffset = offset;
      if (moveAnimation.isWaitingAtBeginning) {
        moveAnimation.start();
      }
    }
  }

  double get currentScrollOffset =>
      fromOffset + moveAnimation.time * (_toOffset! - fromOffset);

  bool get areAnimationsCompleted =>
      _animation.isWaitingAtEnd && moveAnimation.isWaitingAtEnd;

  @override
  double get currentLength => currentSize / itemSize;

  @override
  int get popUpBuildCount => 1;

  void onMoveTick() {
    intervalList.interface.markNeedsLayout();
  }

  @override
  void dispose() {
    moveAnimation.animation.removeListener(onMoveTick);
    moveAnimation.detachFrom(this);
    super.dispose();
  }

  @override
  Widget buildPopUpWidget(BuildContext context, int buildIndexOffset,
      int listIndexOffset, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    return intervalList.inListBuilder.call(
        buildIndexOffset,
        listIndexOffset,
        AnimatedWidgetBuilderData(kAlwaysCompleteAnimation,
            measuring: measureOnly));
  }

  @override
  void remove(int priority) {
    intervalList.moveDismissOpeningInterval(this, priority);
  }

  @override
  void change(double newItemSize) {
    intervalList.moveChangeOpeningIntervalSize(this, newItemSize);
  }

  @override
  String toShortString() => 'Md(${super.toShortString()})';

  @override
  String toString() => 'Md (${super.toString()})';
}

class _SingleElementPopUpList extends _PopUpList {
  Element? element;
  late double itemSize;
  Object? slot;

  @override
  Iterable<Element> get elements sync* {
    if (element != null) yield element!;
  }

  @override
  void clearElements() => element = null;

  void updateSlot(Object? newSlot) {
    if (slot != newSlot) {
      slot = newSlot;

      // rebuild the pop-up item
      if (interval != null) {
        final intervalList = interval!.intervalList;
        intervalList.addUpdate(0, 1, 1, popUpList: this);
        intervalList.interface.markNeedsBuild();
      }
    }
  }
}
