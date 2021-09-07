part of 'core.dart';

const double _kMinAcceptableResizeAmount = 1.0;

typedef _IntervalBuilder = Widget Function(BuildContext context, int buildIndex,
    int listIndex, AnimatedWidgetBuilderData data);

typedef _NotifyCallback = void Function(
  _Interval interval,
  int removeCount,
  int insertCount,
  int leading,
  int trailing,
  _IntervalBuilder Function()? offListItemBuilder,
  int priority,
);

enum _UpdateMode { REPLACE, REBUILD, UNBIND }

class _Update {
  const _Update(this.index, this.oldBuildCount, this.newBuildCount, this.mode)
      : assert(index >= 0 && oldBuildCount >= 0 && newBuildCount >= 0);

  final int index;
  final int oldBuildCount, newBuildCount;
  final _UpdateMode mode;

  int get skipCount => newBuildCount - oldBuildCount;

  @override
  String toString() =>
      'U(i: $index, ob: $oldBuildCount, nb: $newBuildCount, s: $skipCount, m: $mode)';
}

class _IntervalInfo {
  const _IntervalInfo(this.interval, this.buildIndex, this.itemIndex)
      : assert(buildIndex >= 0 && itemIndex >= 0);
  final _Interval interval;
  final int buildIndex;
  final int itemIndex;
}

class _SplitResult {
  const _SplitResult(this.left, this.right);
  final _Interval? left, right;
}

class _AverageItemSizeCount {
  const _AverageItemSizeCount(this.size, this.count)
      : assert(size >= 0 && count >= 0);
  final double size;
  final int count;
}

class _Cancelled {
  bool value = false;
}

// Base class of all intervals.
// It provides the buildCount getter method to provide the count of the items covered by this interval
// for building purpose and the itemCount getter method to provide the actual count of the list items covered.
// It also provides a base method to merge multiple intevrals in order to optimize them and a method
// to build the covered widget at a specific build index.
// Finally, all interval can be disposed.
abstract class _Interval extends LinkedListEntry<_Interval> {
  _IntervalList get intervalList => list as _IntervalList;

  int get buildCount;
  int get itemCount;

  _Interval? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    return null;
  }

  Widget buildWidget(
          BuildContext context, int buildIndexOffset, int listIndexOffset) =>
      throw UnimplementedError('This interval is not meant to be built');

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

// Interval with animation feature.
// An animation will be attached to this interval and automatically detached when the latter is disposed.
abstract class _AnimatedInterval extends _Interval {
  _AnimatedInterval(this._animation) {
    _animation.attachTo(this);
  }

  final _Animation _animation;

  @override
  void dispose() {
    _animation.detachFrom(this);
    super.dispose();
  }

  bool get isWaitingAtBeginning => _animation.isWaitingAtBeginning;
  bool get isWaitingAtEnd => _animation.isWaitingAtEnd;

  @override
  String toString() => '${super.toString()}, t: ${_animation.time}';
}

// Interval that builds an animated piece of the underlying list.
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
  Widget buildWidget(
      BuildContext context, int buildIndexOffset, int listIndexOffset) {
    assert(_debugAssertNotDisposed());
    return intervalList.inListBuilder.call(context, buildIndexOffset,
        listIndexOffset, AnimatedWidgetBuilderData(_animation.animation));
  }
}

// Interval that builds an animated off-list items (for example a range of removed or changed items
// no longer present in the underlying list).
abstract class _OffListItemInterval extends _AnimatedInterval {
  _OffListItemInterval(
      _Animation animation, this.builder, this.offLength, this.inLength)
      : assert(offLength >= 0 && inLength >= 0),
        super(animation);

  final _IntervalBuilder builder;
  final int offLength;
  final int inLength;

  @override
  int get buildCount => offLength;

  @override
  int get itemCount => inLength;

  @override
  Widget buildWidget(
      BuildContext context, int buildIndexOffset, int listIndexOffset) {
    assert(_debugAssertNotDisposed());
    return builder.call(context, buildIndexOffset, listIndexOffset,
        AnimatedWidgetBuilderData(_animation.animation));
  }
}

// Interval that doesn't build any items but just holds some items of the underlying list.
abstract class _HolderInterval extends _Interval {
  _HolderInterval(this.length) : assert(length > 0);

  final int length;

  @override
  int get buildCount => 0;

  @override
  int get itemCount => length;
}

// This interface marks an interval to be able to be split ahd full or partially transformed
// into a ready to removal interval.
// _NormalInterval, _InsertionInterval and _ReadyToChangingInterval implement this.
abstract class _RemovableInterval implements _AnimatedInterval {
  _SplitResult split(int leading, int trailing);
}

// This interface marks an interval to be able to adjust the count of the items of the
// underlying list covered without changing its build.
// _ReadyToRemovalInterval, _RemovalInterval, _ReadyToResizingIntervalFromRemoval,
// _ReadyToNewResizingInterval and _ReadyToResizingSpawnedInterval implement this.
abstract class _AdjustableInterval extends _Interval {
  _AdjustableInterval? from(_AdjustableInterval interval, int newItemCount);
}

// This interface marks an interval to be able to be transformed into a ready to resizing interval,
// giving to it its current size as the initial size.
// This kind of interval has to provide a stop method to interrupt its animation and a method
// to calculate the total size and count of the building items covered.
// _ResizingInterval, _ReadyToInsertionInterval, _ReadyToNewResizingInterval and
// _ReorderResizingInterval implement this.
abstract class _ResizableInterval extends _Interval {
  double get currentSize;
  _AverageItemSizeCount get averageItemSizeCount;
  void stop();
}

// Marks an inteval to be ready to be transformed into another kind of interval.
// A priority must be given which is used to transform the intervals based on priorities.
abstract class _ReadyToInterval {
  int get priority;
}

// Interval that it is ready to be changed into a resizing interval.
// This mixin helps these types of intervals measure their covered items
// to give the overall from and to sizes to the new resizing interval.
// _ReadyToResizingIntervalFromRemoval, _ReadyToNewResizingInterval and
// _ReadyToResizingSpawnedInterval implement this.
mixin _ReadyToResizingInterval implements _Interval, _ReadyToInterval {
  _Measure? fromSize, toSize;
  _Cancelled? cancelled;
  bool isMeasuring = false;

  int get fromLength;

  Future<void> measure() async {
    assert(_debugAssertNotDisposed());
    assert(cancelled == null);

    cancelled = _Cancelled();
    isMeasuring = true;

    if (fromSize == null) {
      await measureFromSize();
    }
    if (!cancelled!.value) {
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
            context,
            index,
            intervalList.listItemIndexOf(this),
            AnimatedWidgetBuilderData(kAlwaysCompleteAnimation,
                measuring: true)));
  }

  bool get isMeasured => fromSize != null && toSize != null;
}

// Interval that builds a piece of the underlying list in a full visible fashion.
class _NormalInterval extends _InListItemInterval
    implements _RemovableInterval {
  _NormalInterval(int length) : super(_CompletedAnimation.INSTANCE, length);

  @override
  _SplitResult split(int leading, int trailing) {
    assert(_debugAssertNotDisposed());
    return _SplitResult(
      leading > 0 ? _NormalInterval(leading) : null,
      trailing > 0 ? _NormalInterval(trailing) : null,
    );
  }

  @override
  _Interval? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _NormalInterval) {
      return _NormalInterval(length + leftInterval.length);
    }
    return null;
  }

  @override
  String toShortString() => 'Nm(${super.toShortString()})';

  @override
  String toString() => 'Nm (${super.toString()})';
}

// Interval that it is ready to be changed into a removal interval.
// It is created against a _RemovableInterval.
class _ReadyToRemovalInterval extends _OffListItemInterval
    implements _AdjustableInterval, _ReadyToInterval {
  _ReadyToRemovalInterval(_Animation animation, _IntervalBuilder builder,
      int offLength, int inLength, this.priority)
      : super(animation, builder, offLength, inLength);

  @override
  final int priority;

  @override
  _Interval? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToRemovalInterval &&
        leftInterval._animation is _CompletedAnimation &&
        _animation is _CompletedAnimation &&
        leftInterval.priority == priority) {
      final ret = _ReadyToRemovalInterval(
          _animation,
          _joinBuilders(leftInterval.builder, builder, leftInterval.offLength),
          leftInterval.offLength + offLength,
          leftInterval.inLength + inLength,
          priority);
      return ret;
    } else if (leftInterval is _ReadyToResizingSpawnedInterval &&
        leftInterval.priority == priority) {
      return _ReadyToRemovalInterval(_animation, builder, offLength,
          leftInterval.itemCount + inLength, priority);
    }
    return null;
  }

  @override
  _ReadyToRemovalInterval from(
      covariant _ReadyToRemovalInterval interval, int itemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToRemovalInterval(
        _animation, builder, offLength, itemCount, priority);
  }

  @override
  String toShortString() => '->Rm(${super.toShortString()})';

  @override
  String toString() => '->Rm (${super.toString()})';
}

// Interval that is dismissing a range of items no longer present in the underlying list.
// It is created against a _ReadyToRemovalInterval.
class _RemovalInterval extends _OffListItemInterval
    implements _AdjustableInterval {
  _RemovalInterval(_Animation animation, _IntervalBuilder builder,
      int offLength, int inLength, this.priority)
      : super(animation, builder, offLength, inLength);

  final int priority;

  @override
  _RemovalInterval from(covariant _RemovalInterval interval, int itemCount) {
    assert(_debugAssertNotDisposed());
    return _RemovalInterval(
        _animation, builder, offLength, itemCount, priority);
  }

  @override
  String toShortString() => 'Rm(${super.toShortString()})';

  @override
  String toString() => 'Rm (${super.toString()})';
}

// Interval that is showing up an incoming range of items of the underlying list.
// It is created against a _ReadyToInsertionInterval or _ReadyToChangingInterval.
class _InsertionInterval extends _InListItemInterval
    implements _RemovableInterval {
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

// Interval that is resizing empty content which is getting bigger or smaller, going from
// an initial size to a final size.
// It is created against a _ReadyToResizingInterval.
class _ResizingInterval extends _AnimatedInterval
    implements _ResizableInterval {
  _ResizingInterval(_Animation animation, this.fromSize, this.toSize,
      this.fromLength, this.toLength, this.priority)
      : lastRenderedSize = fromSize.value,
        super(animation) {
    _animation.animation.addListener(onTick);
  }

  final _Measure fromSize, toSize;
  final int fromLength, toLength;
  final int priority;

  double lastRenderedSize;

  @override
  void dispose() {
    _animation.animation.removeListener(onTick);
    super.dispose();
  }

  void onTick() {
    final delta = currentSize - lastRenderedSize;
    if (delta != 0.0) {
      intervalList.interface.resizingIntervalUpdated(this, delta);
      lastRenderedSize = currentSize;
    }
  }

  @override
  _AverageItemSizeCount get averageItemSizeCount => _AverageItemSizeCount(
      fromSize.value + toSize.value, fromLength + toLength);

  @override
  void stop() {
    assert(_debugAssertNotDisposed());
    (_animation as _ControlledAnimation).stop();
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
    return (fromSize.value - toSize.value).abs() <= _kMinAcceptableResizeAmount;
  }

  @override
  int get buildCount => 1;

  @override
  int get itemCount => toLength;

  @override
  Widget buildWidget(
      BuildContext context, int buildIndexOffset, int listIndexOffset) {
    assert(_debugAssertNotDisposed());
    final animation = Tween<double>(begin: fromSize.value, end: toSize.value)
        .animate(_animation.animation);
    final horizontal = intervalList.interface.isHorizontal;
    return AnimatedBuilder(
        animation: animation,
        builder: (context, child) => SizedBox(
              width: horizontal ? animation.value : null,
              height: !horizontal ? animation.value : null,
            ));
  }

  @override
  String toShortString() => 'Rz(${super.toShortString()})';

  @override
  String toString() =>
      'Rz (${super.toString()}, fs: $fromSize, ts: $toSize, cs: $currentSize)';
}

// Interval that it is ready to be changed into an insertion interval.
// It is created against a _ResizingInterval.
class _ReadyToInsertionInterval extends _Interval
    implements _ResizableInterval, _ReadyToInterval {
  _ReadyToInsertionInterval(this.toSize, this.toLength, this.priority)
      : assert(toLength >= 0);

  final _Measure toSize;
  final int toLength;

  @override
  final int priority;

  @override
  _AverageItemSizeCount get averageItemSizeCount =>
      _AverageItemSizeCount(toSize.value, toLength);

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
  _Interval? mergeWith(_Interval leftInterval) {
    assert(_debugAssertNotDisposed());
    if (leftInterval is _ReadyToInsertionInterval &&
        leftInterval.priority == priority) {
      intervalList.addUpdate(intervalList.buildItemIndexOf(leftInterval), 2, 1,
          _UpdateMode.REPLACE);
      return _ReadyToInsertionInterval(leftInterval.toSize + toSize,
          leftInterval.toLength + toLength, priority);
    }
    return null;
  }

  @override
  Widget buildWidget(
      BuildContext context, int buildIndexOffset, int listIndexOffset) {
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

// Interval that finished its dismissing animation and it is ready to be changed into
// a resizing interval.
// It is created against a _RemovalInterval.
class _ReadyToResizingIntervalFromRemoval extends _OffListItemInterval
    with _ReadyToResizingInterval
    implements _AdjustableInterval {
  _ReadyToResizingIntervalFromRemoval(
      _IntervalBuilder builder, int offLength, int inLength, this.priority)
      : super(_DismissedAnimation.INSTANCE, builder, offLength, inLength);

  @override
  final int priority;

  @override
  _ReadyToResizingIntervalFromRemoval from(
      covariant _ReadyToResizingIntervalFromRemoval interval, int itemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToResizingIntervalFromRemoval(
        builder, offLength, itemCount, priority);
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
  int get fromLength => offLength;

  @override
  String toShortString() => 'Rm->Rz(${super.toShortString()})';

  @override
  String toString() => 'Rm->Rz (${super.toString()})';
}

// Interval that stopped its resizing animation (or was waiting for insertion) and it is ready
// to be changed to a new resizing interval.
// It is created against a _ResizableInterval.
class _ReadyToNewResizingInterval extends _Interval
    with _ReadyToResizingInterval
    implements _AdjustableInterval, _ResizableInterval {
  _ReadyToNewResizingInterval(double fromSize, this.toLength,
      this.oldAverageItemSizeCount, this.priority)
      : assert(fromSize >= 0 && toLength >= 0) {
    this.fromSize = _Measure(fromSize, false);
  }

  final int toLength;
  final _AverageItemSizeCount oldAverageItemSizeCount;

  @override
  final int priority;

  @override
  _AverageItemSizeCount get averageItemSizeCount => oldAverageItemSizeCount;

  @override
  _ReadyToNewResizingInterval from(
      covariant _ReadyToNewResizingInterval interval, int itemCount) {
    assert(_debugAssertNotDisposed());
    return _ReadyToNewResizingInterval(
        fromSize!.value, itemCount, oldAverageItemSizeCount, priority);
  }

  @override
  double get currentSize => fromSize!.value;

  @override
  void stop() {
    assert(_debugAssertNotDisposed());
  }

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
  int get fromLength => oldAverageItemSizeCount.count;

  @override
  Widget buildWidget(
      BuildContext context, int buildIndexOffset, int listIndexOffset) {
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

// Interval that spawned from nothing and it is ready to be changed into a resizing interval.
// It is created against a _RemovableInterval.
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
  _ReadyToResizingSpawnedInterval? from(
      covariant _ReadyToResizingSpawnedInterval interval, int itemCount) {
    assert(_debugAssertNotDisposed());
    if ( itemCount == 0 ) return null;
    return _ReadyToResizingSpawnedInterval(itemCount, priority);
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  @override
  int get fromLength => 0;

  @override
  String toShortString() => '->Rz(${super.toShortString()})';

  @override
  String toString() => '->Rz (${super.toString()})';
}

// Interval that is ready to rebuild some items of the underlying list.
// It is created against a _RemovableInterval.
class _ReadyToChangingInterval extends _OffListItemInterval
    implements _RemovableInterval, _ReadyToInterval {
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
  String toString() => '->Ch (${super.toString()})';

  @override
  String toShortString() => '->Ch(${super.toShortString()})';
}

// Marks an interval to be used during reordering.
abstract class _ReorderInterval implements _Interval {}

// Base class for _ReorderOpeningInterval and _ReorderClosingInterval.
abstract class _ReorderResizingInterval extends _AnimatedInterval
    implements _ResizableInterval {
  _ReorderResizingInterval(_Animation animation, this.itemSize)
      : assert(itemSize >= 0),
        super(animation);

  final double itemSize;

  double get fromSize;
  double get toSize;

  @override
  double get currentSize {
    if (_animation.time == 0.0) {
      return fromSize;
    } else if (_animation.time == 1.0) {
      return toSize;
    } else {
      return fromSize + _animation.animation.value * (toSize - fromSize);
    }
  }

  @override
  void stop() => throw UnimplementedError();

  @override
  _AverageItemSizeCount get averageItemSizeCount =>
      _AverageItemSizeCount(itemSize, 1);

  @override
  Widget buildWidget(
      BuildContext context, int buildIndexOffset, int listIndexOffset) {
    final animation = Tween<double>(begin: fromSize, end: toSize)
        .animate(_animation.animation);
    final horizontal = intervalList.interface.isHorizontal;
    return AnimatedBuilder(
        animation: animation,
        builder: (context, child) => SizedBox(
              width: horizontal ? animation.value : null,
              height: !horizontal ? animation.value : null,
            ));
  }
}

// Interval created during reordering that indicates an opening gap between two items.
class _ReorderOpeningInterval extends _ReorderResizingInterval
    implements _ReorderInterval {
  _ReorderOpeningInterval(_Animation animation, double itemSize, this.fromSize)
      : super(animation, itemSize);

  @override
  final double fromSize;

  @override
  double get toSize => itemSize;

  @override
  int get buildCount => 1;

  @override
  int get itemCount => 0;

  @override
  String toShortString() => 'Ro(${super.toShortString()})';

  @override
  String toString() => 'Ro (${super.toString()})';
}

// Interval created during reordering that indicates a closing gap between two items.
class _ReorderClosingInterval extends _ReorderResizingInterval
    implements _ReorderInterval {
  _ReorderClosingInterval(_Animation animation, double itemSize, this.fromSize)
      : super(animation, itemSize);

  @override
  final double fromSize;

  @override
  double get toSize => 0.0;

  @override
  int get buildCount => 1;

  @override
  int get itemCount => 0;

  @override
  _AverageItemSizeCount get averageItemSizeCount =>
      _AverageItemSizeCount(itemSize, 1);

  @override
  String toShortString() => 'Rc(${super.toShortString()})';

  @override
  String toString() => 'Rc (${super.toString()})';
}

// Interval created during reordering indicating that the dragged item is not to be built.
class _ReorderHolderInterval extends _HolderInterval
    implements _ReorderInterval {
  _ReorderHolderInterval() : super(1);

  @override
  String toShortString() => 'Rh(${super.toShortString()})';

  @override
  String toString() => 'Rh (${super.toString()})';
}

//

class _IntervalList extends LinkedList<_Interval> with TickerProviderMixin {
  final _ListIntervalInterface interface;
  final updates = List<_Update>.empty(growable: true);
  final animations = <_ControlledAnimation>{};

  var _disposed = false;

  _IntervalList(this.interface) {
    final initialCount = interface.delegate.initialChildCount;
    if (initialCount > 0) add(_NormalInterval(initialCount));
  }

  // Interval builder for underlying list items.
  Widget inListBuilder(BuildContext context, int buildIndexOffset,
      int listIndexOffset, AnimatedWidgetBuilderData data) {
    return interface.buildWidget(context, interface.delegate.builder,
        listIndexOffset + buildIndexOffset, data);
  }

  // Total count of the items to be built in the list view.
  int get buildItemCount => fold<int>(0, (v, i) => v + i.buildCount);

  // Total count of the underlying list items.
  int get listItemCount => fold<int>(0, (v, i) => v + i.itemCount);

  AnimatedListAnimator get animator => interface.delegate.animator;

  @override
  void dispose() {
    _disposed = true;
    toList().forEach((i) => i.dispose());
    animations.clear();
    super.dispose();
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

  int buildItemIndexOf(_Interval interval) {
    assert(_debugAssertNotDisposed());
    assert(interval.list == this);
    var i = 0;
    for (var node = interval.previous; node != null; node = node.previous) {
      i += node.buildCount;
    }
    return i;
  }

  int listItemIndexOf(_Interval interval) {
    assert(_debugAssertNotDisposed());
    assert(interval.list == this);
    var i = 0;
    for (var node = interval.previous; node != null; node = node.previous) {
      i += node.itemCount;
    }
    return i;
  }

  _IntervalInfo intervalAtBuildIndex(int buildIndex) {
    assert(_debugAssertNotDisposed());
    var buildOffset = 0, itemOffset = 0;
    _Interval? interval, nextInterval;
    for (interval = first; interval != null; interval = nextInterval) {
      nextInterval = interval.next;
      if (buildIndex < interval.buildCount + buildOffset) {
        return _IntervalInfo(interval, buildOffset, itemOffset);
      }
      buildOffset += interval.buildCount;
      itemOffset += interval.itemCount;
    }
    throw Exception('this point should never have been reached');
  }

  Widget build(BuildContext context, int buildIndex) {
    final info = intervalAtBuildIndex(buildIndex);
    return info.interval
        .buildWidget(context, buildIndex - info.buildIndex, info.itemIndex);
  }

  // Returns true if there are pending updates.
  bool get hasPendingUpdates => updates.isNotEmpty;

  // Add a new update record for AnimatedSliverMultiBoxAdaptorElement.performRebuild.
  void addUpdate(
      int index, int oldBuildItemCount, int newBuildCount, _UpdateMode mode) {
    assert(_debugAssertNotDisposed());
    updates.add(_Update(index, oldBuildItemCount, newBuildCount, mode));
    interface.markNeedsBuild();
  }

  // The list view has notified that a range of the underlying list has been replaced.
  void notifyRangeReplaced(int from, int removeCount, int insertCount,
      AnimatedWidgetBuilder? removeItemBuilder,
      [int priority = 0]) {
    assert(_debugAssertNotDisposed());
    assert(from >= 0);
    assert(removeCount >= 0 && insertCount >= 0);
    assert(from + removeCount <= listItemCount);

    distributeNotification(from, removeCount, insertCount, removeItemBuilder,
        priority, onReplaceNotification);

    optimize();
  }

  // The list view has notified that a range of the underlying list has been changed.
  void notifyRangeChanged(
      int from, int count, AnimatedWidgetBuilder? changeItemBuilder,
      [int priority = 0]) {
    assert(_debugAssertNotDisposed());
    assert(from >= 0);
    assert(count >= 0);
    assert(from + count <= listItemCount);

    distributeNotification(
        from, count, count, changeItemBuilder, priority, onChangeNotification);

    optimize();
  }

  void distributeNotification(
      int from,
      int removeCount,
      int insertCount,
      AnimatedWidgetBuilder? offListItemBuilder,
      int priority,
      _NotifyCallback callback) {
    if (isEmpty) {
      addFirst(_NormalInterval(0));
    }

    _Interval? interval = first;
    _Interval? nextInterval;
    var ifrom = 0, ito = 0;
    var offListBuilderOffset = 0;

    for (; interval != null; interval = nextInterval) {
      nextInterval = interval.next;

      final to = from + removeCount;
      assert(ifrom == listItemIndexOf(interval));
      ito = ifrom + interval.itemCount;

      assert(from >= ifrom);
      if (from <= ito) {
        if (to <= ito) {
          callback(
              interval,
              removeCount,
              insertCount,
              from - ifrom,
              ito - to,
              () => offListBuilder(offListItemBuilder!, offListBuilderOffset),
              priority);
          return;
        } else {
          final rem = ito - from;
          final ins = math.min(rem, insertCount);
          callback(
              interval,
              rem,
              ins,
              from - ifrom,
              0,
              () => offListBuilder(offListItemBuilder!, offListBuilderOffset),
              priority);
          ifrom = from + ins;
          from = ito + ins - rem;
          offListBuilderOffset += rem;
          insertCount -= ins;
          removeCount -= rem;
        }
      } else {
        ifrom += interval.itemCount;
      }
    }
    throw Exception('this point should never have been reached');
  }

  // It converts the builder passed in notifyRangeReplaced or notifyRangeChange in an
  // interval builder with offset.
  _IntervalBuilder offListBuilder(final AnimatedWidgetBuilder builder,
      [final int offset = 0]) {
    assert(offset >= 0);
    return (context, buildIndexOffset, listIndexOffset, data) =>
        interface.buildWidget(context, builder, buildIndexOffset + offset, data);
  }

  void onReplaceNotification(
      _Interval interval,
      int removeCount,
      int insertCount,
      int leading,
      int trailing,
      _IntervalBuilder Function()? offListItemBuilder,
      [int priority = 0]) {
    if (removeCount == 0 && insertCount == 0) return;

    if (interval is _RemovableInterval) {
      final result = interval.split(leading, trailing);
      late _Interval middle;
      if (removeCount > 0) {
        middle = _ReadyToRemovalInterval(interval._animation,
            offListItemBuilder!.call(), removeCount, insertCount, priority);
      } else {
        middle = _ReadyToResizingSpawnedInterval(insertCount, priority);
      }
      replaceWithSplit(interval, result.left, middle, result.right);
    } else if (interval is _AdjustableInterval) {
      final length = interval.itemCount - removeCount + insertCount;
      if (length != interval.itemCount) {
        final newInterval = interval.from(interval, length);
        if ( newInterval != null ) {
          replace(interval, newInterval);
        }
        else {
          interval.dispose();
        }
      }
    } else if (interval is _ResizableInterval) {
      final length = interval.itemCount - removeCount + insertCount;
      interval.stop();
      replace(
          interval,
          _ReadyToNewResizingInterval(interval.currentSize, length,
              interval.averageItemSizeCount, priority));
    } else if (interval is _ReorderHolderInterval) {
      interval.dispose();
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        reorderUpdateClosingIntervals();
      });
      interface.draggedItemHasBeenRemoved();
    }
  }

  void onChangeNotification(
      _Interval interval,
      int changeCount,
      int _,
      int leading,
      int trailing,
      _IntervalBuilder Function()? offListItemBuilder,
      [int priority = 0]) {
    assert(changeCount == _);
    if (changeCount == 0) return;

    if (interval is _RemovableInterval) {
      final result = interval.split(leading, trailing);
      late _Interval middle;
      middle = _ReadyToChangingInterval(interval._animation,
          offListItemBuilder!.call(), changeCount, priority);
      replaceWithSplit(interval, result.left, middle, result.right);
    } else if (interval is _ResizableInterval) {
      final length = interval.itemCount;
      interval.stop();
      replace(
          interval,
          _ReadyToNewResizingInterval(interval.currentSize, length,
              interval.averageItemSizeCount, priority));
    } else if (interval is _ReorderHolderInterval) {
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        interface.draggedItemHasChanged();
      });
    }
  }

  _ControlledAnimation createAnimation(AnimatedListAnimationData ad) {
    assert(_debugAssertNotDisposed());
    final a = _ControlledAnimation(this, ad.animation, ad.duration,
        startTime: ad.startTime);
    animations.add(a);
    a.addListener(() {
      if (a.intervals.isNotEmpty) {
        a.intervals.toList().forEach((i) => onIntervalCompleted(i));
        clearUnbindedAnimations();
        coordinate();
      }
    });
    return a;
  }

  void clearUnbindedAnimations() {
    animations.removeWhere((a) => a.intervals.isEmpty);
  }

  // Called when an interval has completed its animation.
  void onIntervalCompleted(_AnimatedInterval interval) {
    if (interval is _RemovalInterval) {
      var newInterval = _ReadyToResizingIntervalFromRemoval(interval.builder,
          interval.offLength, interval.inLength, interval.priority);
      replace(interval, newInterval);
    } else if (interval is _ResizingInterval) {
      final buildOffset = buildItemIndexOf(interval);
      if (interval.toLength > 0) {
        final newInterval = _ReadyToInsertionInterval(
            interval.toSize, interval.toLength, interval.priority);
        replace(interval, newInterval);
      } else {
        assert(interval.toSize.value == 0.0);
        addUpdate(buildOffset, interval.buildCount, 0, _UpdateMode.REPLACE);
        interval.dispose();
      }
    } else if (interval is _InsertionInterval) {
      final buildOffset = buildItemIndexOf(interval);
      final newInterval = _NormalInterval(interval.length);
      addUpdate(buildOffset, interval.buildCount, newInterval.buildCount,
          _UpdateMode.REBUILD);
      replace(interval, newInterval);
    } else if (interval is _ReorderClosingInterval) {
      final buildOffset = buildItemIndexOf(interval);
      addUpdate(buildOffset, interval.buildCount, 0, _UpdateMode.REPLACE);
      interval.dispose();
    }
  }

  // Transforms some or all ready-to intervals into new ones.
  void coordinate() {
    var remPri = -1;
    var rem = whereType<_ReadyToRemovalInterval>();
    if (rem.isNotEmpty) {
      rem.toList().forEach((interval) {
        remPri = math.max(remPri, interval.priority);
        final animation = interval.isWaitingAtEnd
            ? createAnimation(animator.dismiss())
            : createAnimation(
                animator.dismissDuringIncoming(interval._animation.time));
        final newInterval = _RemovalInterval(
            animation..start(),
            interval.builder,
            interval.offLength,
            interval.inLength,
            interval.priority);
        addUpdate(buildItemIndexOf(interval), interval.buildCount,
            newInterval.buildCount, _UpdateMode.REBUILD);
        replace(interval, newInterval);
      });
    }
    remPri = whereType<_RemovalInterval>()
        .where((i) => !i.isWaitingAtBeginning)
        .fold<int>(remPri, (pv, i) => math.max(pv, i.priority));

    var chg =
        whereType<_ReadyToChangingInterval>().where((i) => i.priority > remPri);
    if (chg.isNotEmpty) {
      chg.toList().forEach((interval) {
        final newInterval = interval.isWaitingAtEnd
            ? _NormalInterval(interval.itemCount)
            : _InsertionInterval(interval._animation, interval.itemCount);
        addUpdate(buildItemIndexOf(interval), interval.buildCount,
            newInterval.buildCount, _UpdateMode.REBUILD);
        replace(interval, newInterval);
      });
    }

    var resPri = -1;
    var res =
        whereType<_ReadyToResizingInterval>().where((i) => i.priority > remPri);
    if (res.isNotEmpty) {
      res
          .where((e) => !e.isMeasured && !e.isMeasuring)
          .toList()
          .forEach((interval) {
        resPri = math.max(resPri, interval.priority);
        interval.measure().whenComplete(() => coordinate());
      });
      res
          .where((e) => e.isMeasured && !e.isMeasuring)
          .toList()
          .forEach((interval) {
        resPri = math.max(resPri, interval.priority);
        final newInterval = _ResizingInterval(
            createAnimation(
                animator.resizing(interval.fromSize!, interval.toSize!))
              ..start(),
            interval.fromSize!,
            interval.toSize!,
            interval.fromLength,
            interval.itemCount,
            interval.priority);
        addUpdate(
            buildItemIndexOf(interval),
            interval.buildCount,
            newInterval.buildCount,
            interval.fromSize!.estimated
                ? _UpdateMode.UNBIND
                : _UpdateMode.REPLACE);
        replace(interval, newInterval);
        if (newInterval.canCompleteImmediately) {
          (newInterval._animation as _ControlledAnimation).complete();
        }
      });
    }
    resPri = whereType<_ResizingInterval>()
        .where((i) => !i.isWaitingAtEnd)
        .fold<int>(resPri, (pv, i) => math.max(pv, i.priority));

    var ins = whereType<_ReadyToInsertionInterval>()
        .where((i) => i.priority > resPri);
    if (ins.isNotEmpty) {
      ins.toList().forEach((interval) {
        final isi = _InsertionInterval(
            createAnimation(animator.incoming())..start(), interval.toLength);
        replace(interval, isi);
        addUpdate(
            buildItemIndexOf(isi),
            interval.buildCount,
            isi.buildCount,
            interval.toSize.estimated
                ? _UpdateMode.UNBIND
                : _UpdateMode.REPLACE);
      });
    }

    optimize();

    assert(() {
      if (length == 1 && first is _NormalInterval) {
        if (animations.isNotEmpty) return false;
        if (hasActiveTickers) return false;
      }
      return true;
    }());
  }

  // Analyze if there are intervals that can be merged in order to optimize the interval list.
  void optimize() {
    var interval = isEmpty ? null : first;
    _Interval? leftInterval;
    while (interval != null) {
      var nextInterval = interval.next;

      var mergedInterval =
          leftInterval != null ? interval.mergeWith(leftInterval) : null;
      if (mergedInterval != null) {
        interval.dispose();
        replace(leftInterval!, interval = mergedInterval);
      }

      leftInterval = interval;
      interval = nextInterval;
    }
  }

  void replace(_Interval oldInterval, _Interval newInterval) {
    var prev = oldInterval.previous;
    if (prev != null) {
      oldInterval.insertAfter(newInterval);
    } else {
      addFirst(newInterval);
    }
    oldInterval.dispose();
  }

  void replaceWithSplit(
      _Interval interval, _Interval? left, _Interval middle, _Interval? right) {
    replace(interval, middle);
    if (left != null) middle.insertBefore(left);
    if (right != null) middle.insertAfter(right);
  }

  @override
  String toString() =>
      '[${fold<String>('', (v, e) => (v.isEmpty ? '' : '$v, ') + e.toShortString())}]';
  // '[${fold<String>('', (v, e) => (v.isEmpty ? '' : '$v, ') + e.toString())}]';

// *************************
//  Reorder Feature Support
// *************************

  // It searches for the interval that holds the underlying list item that is being dragged,
  // and returns its index if it is found.
  int? get reorderPickListIndex {
    final l = whereType<_ReorderHolderInterval>();
    assert(l.length <= 1);
    if (l.isEmpty) return null;
    return listItemIndexOf(l.single);
  }

  // It searches for the open (or opening) interval to host the item dragged in that new position
  // and returns its corresponding index within the underlying list.
  // The initial index of the dragged item is required in this calculation, and if it is available
  // you can pass it as input, otherwise it will also be calculated.
  int reorderDropListIndex([int? pickListIndex]) {
    final open = whereType<_ReorderOpeningInterval>();
    late int index;
    assert(open.length == 1);
    index = listItemIndexOf(open.single);
    if (index > (pickListIndex ?? reorderPickListIndex!)) index--;
    return index;
  }

  // It splits the _NormalInterval at the exact point indicated by the buildIndex and removes
  // the item (which will be the one dragged) to make room for two new intervals, a fully
  // open _ReorderOpeningInterval and a _ReorderHolderInterval which holds the item of
  // the underlying list but prevents it from being built.
  // The size of the dragged item must be provided.
  _ReorderOpeningInterval notifyStartReorder(int buildIndex, double itemSize) {
    final info = intervalAtBuildIndex(buildIndex);
    final normalInterval = info.interval as _NormalInterval;
    final i = buildIndex - info.buildIndex;
    final result = normalInterval.split(i, normalInterval.buildCount - i - 1);
    final middle = _ReorderOpeningInterval(
        _CompletedAnimation.INSTANCE, itemSize, itemSize);
    replaceWithSplit(normalInterval, result.left, middle, result.right);
    middle.insertAfter(_ReorderHolderInterval());
    return middle;
  }

  // It replaces the open (or opening) interval with a _NormalInterval of length 1 which
  // represents the dropped item. In addition it removes the _ReorderHolderInterval.
  // The buildIndex of the dropped item is returned.
  int notifyStopReorder() {
    final dropInterval = whereType<_ReorderOpeningInterval>().single;
    final normalInterval = _NormalInterval(1);
    replace(dropInterval, normalInterval);

    final holderInterval = whereType<_ReorderHolderInterval>().single;
    holderInterval.dispose();

    final buildIndex = buildItemIndexOf(normalInterval);
    optimize();
    return buildIndex;
  }

  // It splits the _NormalIntevral in the exact point indicated by the offset by inserting
  // a new opening interval. Any previous opening interval will be replaced with
  // a closing interval.
  void updateReorderDropIndex(
      _NormalInterval normalInterval, int offset, double itemSize) {
    reorderUpdateClosingIntervals();
    final result =
        normalInterval.split(offset, normalInterval.buildCount - offset);
    final middle = _ReorderOpeningInterval(
        createAnimation(animator.resizingDuringReordering(0.0, itemSize))
          ..start(),
        itemSize,
        0.0);
    replaceWithSplit(normalInterval, result.left, middle, result.right);
    addUpdate(buildItemIndexOf(middle), 0, 1, _UpdateMode.REBUILD);
  }

  // It recreates all interval that are closing to keep stable the offset layouts
  // stable of the items not affected by reordering.
  // Also, eventually transforms the open (or opening) interval in  a new
  // closing interval.
  void reorderUpdateClosingIntervals() {
    whereType<_ReorderClosingInterval>().toList().forEach((interval) {
      final buildIndex = buildItemIndexOf(interval);
      replace(
          interval,
          _ReorderClosingInterval(
              createAnimation(
                  animator.resizingDuringReordering(interval.currentSize, 0.0))
                ..start(),
              interval.itemSize,
              interval.currentSize));
      addUpdate(buildIndex, 1, 1, _UpdateMode.REBUILD);
    });

    final maybeOpenInterval = whereType<_ReorderOpeningInterval>();
    assert(maybeOpenInterval.length <= 1);
    if (maybeOpenInterval.length == 1) {
      final openInterval = maybeOpenInterval.single;
      final buildIndex = buildItemIndexOf(openInterval);
      replace(
          openInterval,
          _ReorderClosingInterval(
              createAnimation(animator.resizingDuringReordering(
                  openInterval.currentSize, 0.0))
                ..start(),
              openInterval.itemSize,
              openInterval.currentSize));
      addUpdate(buildIndex, 1, 1, _UpdateMode.REBUILD);
    }
  }

  // It recreates the open interval in order to be eventually resized according to
  // the new size indicated.
  void reorderChangeOpeningIntervalSize(double newItemSize) {
    final maybeOpenInterval = whereType<_ReorderOpeningInterval>();
    assert(maybeOpenInterval.length <= 1);
    if (maybeOpenInterval.length == 1) {
      final openInterval = maybeOpenInterval.single;
      if ((openInterval.toSize - newItemSize).abs() >
          _kMinAcceptableResizeAmount) {
        final buildIndex = buildItemIndexOf(openInterval);
        replace(
            openInterval,
            _ReorderOpeningInterval(
                createAnimation(animator.resizingDuringReordering(
                    openInterval.currentSize, newItemSize))
                  ..start(),
                newItemSize,
                openInterval.currentSize));
        addUpdate(buildIndex, 1, 1, _UpdateMode.REBUILD);
      }
    }
  }
}

abstract class _Animation {
  const _Animation();

  Animation<double> get animation;
  double get time;

  void attachTo(_AnimatedInterval interval) {}
  void detachFrom(_AnimatedInterval interval) {}
  void dispose() {}

  bool get isWaitingAtBeginning =>
      time == 0.0 && animation.status == AnimationStatus.dismissed;
  bool get isWaitingAtEnd =>
      time == 1.0 && animation.status == AnimationStatus.completed;
}

class _CompletedAnimation extends _Animation {
  const _CompletedAnimation._();

  static const _CompletedAnimation INSTANCE = _CompletedAnimation._();

  @override
  Animation<double> get animation => kAlwaysCompleteAnimation;

  @override
  double get time => 1.0;
}

class _DismissedAnimation extends _Animation {
  const _DismissedAnimation._();

  static const _DismissedAnimation INSTANCE = _DismissedAnimation._();

  @override
  Animation<double> get animation => kAlwaysDismissedAnimation;

  @override
  double get time => 0.0;
}

class _ControlledAnimation extends _Animation with ChangeNotifier {
  final AnimationController _controller;
  final intervals = <_AnimatedInterval>{};

  @override
  late Animation<double> animation;

  bool _disposed = false;

  _ControlledAnimation(
      TickerProvider vsync, Animatable<double> animatable, Duration duration,
      {double startTime = 0.0})
      : assert(startTime >= 0.0 && startTime <= 1.0),
        _controller = AnimationController(
            value: startTime, vsync: vsync, duration: duration) {
    animation = _controller.drive(animatable);
  }

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
    super.dispose();
    _controller.dispose();
    _disposed = true;
  }

  void start() {
    assert(_debugAssertNotDisposed());
    _controller.forward().whenComplete(() => _onCompleted());
  }

  void stop() {
    assert(_debugAssertNotDisposed());
    _controller.stop();
  }

  void complete() {
    assert(_debugAssertNotDisposed());
    _controller.value = 1.0;
    Future.microtask(() => _onCompleted());
  }

  void _onCompleted() {
    assert(_debugAssertNotDisposed());
    notifyListeners();
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
}

// It creates a copy of an interval builder possibly adding more offset.
// If the offset is zero, the same interval builder is returned.
_IntervalBuilder _offsetIntervalBuilder(
    final _IntervalBuilder iBuilder, final int offset) {
  assert(offset >= 0);
  if (offset == 0) return iBuilder;
  return (context, buildIndex, itemIndex, data) =>
      iBuilder.call(context, buildIndex + offset, itemIndex, data);
}

// It joins two interval builder and returns a new merged one.
_IntervalBuilder _joinBuilders(final _IntervalBuilder leftBuilder,
    final _IntervalBuilder rightBuilder, final int leftCount) {
  assert(leftCount > 0);
  return (context, buildIndex, listIndex, data) => (buildIndex < leftCount)
      ? leftBuilder.call(context, buildIndex, listIndex, data)
      : rightBuilder.call(context, buildIndex - leftCount, listIndex, data);
}
