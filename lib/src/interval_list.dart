part of 'core.dart';

typedef _DistributeNotificationCallback = void Function(
    _Interval interval,
    _IntervalList list,
    int removeCount,
    int insertCount,
    int leading,
    int trailing,
    AnimatedWidgetBuilder? offListItemBuilder,
    int offListItemBuilderOffset,
    Object? params);

/// This class handles all changes to the list view by breaking up the entire list as a
/// list of contigous intervals, each with its own meaning.
///
/// This class is a linked list and all the intervals are its nodes.
class _IntervalList extends _LinkedList<_Interval>
    implements Iterable<_Interval> {
  bool _disposed = false;

  bool changed = false;

  final _IntervalManager manager;

  _PopUpList? popUpList;

  _SubListHolderInterval? holder;

  _Interval? _leftMostDirtyInterval;

  //

  _IntervalList(this.manager);

  _IntervalList.normal(this.manager, int initialCount) {
    if (initialCount > 0) {
      newContent(initialCount, true);
    }
  }

  /// It returns `true` if there is at least one a dirty interval linked to this list.
  bool get isDirty => _leftMostDirtyInterval != null;

  /// Total count of the items to be built in the list view.
  int get buildCount => isEmpty ? 0 : last.nextBuildOffset;

  /// Total count of the underlying list items.
  int get itemCount => isEmpty ? 0 : last.nextItemOffset;

  /// SUm of the average count of all intervals.
  double get averageCount => fold<double>(0.0, (pv, e) => pv + e.averageCount);

  //
  // List manipulation
  //

  void remove(Iterable<_Interval> intervals,
      {_UpdateCallback? updateCallback, bool dispose = true}) {
    assert(_debugAssertNotDisposed());
    assert(debugAssertIntervalsConsistency(intervals));

    final next = intervals.last.next;
    final prev = intervals.first.previous;

    final index = intervals.first.buildOffset;
    final oldBuildCount = intervals.buildCount;

    if (prev == null || !prev.isDirty) {
      next?.invalidate();
      _leftMostDirtyInterval = next;
    }

    intervals.forEach((i) {
      i._remove();
      if (dispose) i.dispose();
    });

    holder?.onChanged();

    updateCallback?.call(
        this, index + (holder?.parentBuildOffset ?? 0), oldBuildCount, 0);

    changed = true;

    assert(debugDirtyConsistency());
  }

  void replace(
      Iterable<_Interval> oldIntervals, Iterable<_Interval> newIntervals,
      {_UpdateCallback? updateCallback,
      _IntervalList? outSubList,
      VoidCallback? intermediateCallback}) {
    assert(_debugAssertNotDisposed());
    assert(debugAssertIntervalsConsistency(oldIntervals));

    if (newIntervals.isEmpty) {
      remove(oldIntervals, updateCallback: updateCallback);
      return;
    }

    var oldBuildCount = oldIntervals.buildCount;

    intermediateCallback?.call();

    var newBuildCount = newIntervals.buildCount;

    final firstNewInterval = newIntervals.first;
    final secondNewInterval = newIntervals.skip(1).firstOrNull;

    if (newIntervals is _IntervalList) {
      newIntervals = newIntervals.toList();
    }

    newIntervals.forEach((i) {
      assert(!oldIntervals.contains(i));
      i.list?.remove(i.iterable(), dispose: false);
      i._invalidate();
    });

    final next = oldIntervals.last.next;
    final prev = oldIntervals.first.previous;
    if (prev != null) {
      if (!prev.isDirty) {
        next?.invalidate();
        _leftMostDirtyInterval = firstNewInterval;
      }
    } else {
      firstNewInterval._validate(0, 0);
      next?.invalidate();
      if (newIntervals.singleOrNull != null) {
        _leftMostDirtyInterval = next;
      } else {
        _leftMostDirtyInterval = secondNewInterval;
      }
    }

    for (final i in newIntervals) {
      oldIntervals.first._insertBefore(i);
    }
    oldIntervals.forEach((i) {
      i._remove();
      outSubList == null ? i.dispose() : outSubList._add(i);
    });

    if (outSubList != null) {
      assert(outSubList.isNotEmpty);
      outSubList._invalidate();
    }

    holder?.onChanged();

    assert(debugDirtyConsistency());

    final index = firstNewInterval.buildOffset;
    updateCallback?.call(this, index + (holder?.parentBuildOffset ?? 0),
        oldBuildCount, newBuildCount);

    changed = true;
  }

  void insertAfter(_Interval interval, Iterable<_Interval> newIntervals,
      {_UpdateCallback? updateCallback}) {
    assert(_debugAssertNotDisposed());
    assert(interval._list == this);

    if (newIntervals.isEmpty) return;

    var newBuildCount = newIntervals.buildCount;

    final firstNewInterval = newIntervals.first;
    if (!interval.isDirty) {
      interval.next?.invalidate();
      _leftMostDirtyInterval = firstNewInterval;
    }

    var next = interval;
    for (final i in newIntervals) {
      i.list?.remove(i.iterable(), dispose: false);
      i._invalidate();
      next._insertAfter(i);
      next = i;
    }

    holder?.onChanged();

    assert(debugDirtyConsistency());

    final index = firstNewInterval.buildOffset;
    updateCallback?.call(
        this, index + (holder?.parentBuildOffset ?? 0), 0, newBuildCount);

    changed = true;
  }

  void insertBefore(_Interval interval, Iterable<_Interval> newIntervals,
      {_UpdateCallback? updateCallback}) {
    assert(_debugAssertNotDisposed());
    assert(interval._list == this);

    if (newIntervals.isEmpty) return;

    var newBuildCount = newIntervals.buildCount;

    final firstNewInterval = newIntervals.first;

    for (final i in newIntervals) {
      i.list?.remove(i.iterable(), dispose: false);
      i._invalidate();
    }

    interval.invalidate();
    if (!(interval.previous?.isDirty ?? false)) {
      _leftMostDirtyInterval = firstNewInterval;
    }

    for (final i in newIntervals) {
      interval._insertBefore(i);
    }

    holder?.onChanged();

    assert(debugDirtyConsistency());

    final index = firstNewInterval.buildOffset;
    updateCallback?.call(
        this, index + (holder?.parentBuildOffset ?? 0), 0, newBuildCount);

    changed = true;
  }

  void split(
    int leading,
    int trailing,
    _IntervalList? leftSubList,
    _IntervalList? middleSubList,
    _IntervalList? rightSubList,
  ) {
    assert(_debugAssertNotDisposed());
    final middleItemCount = itemCount - leading - trailing;
    distributeNotification(leading, middleItemCount, middleItemCount, null, 0,
        (interval, list, count, _, leading, trailing, __, ___, ____) {
      assert(interval is! _SubListInterval);
      final result = interval.split(leading, trailing);
      manager.performSplit(interval, result);
    });

    final middle = leading + middleItemCount;
    var ic = 0;
    _Interval? i = first;
    while (i != null) {
      var next = i.next;
      i._remove();
      if (ic < leading) {
        leftSubList!._add(i);
      } else if (ic < middle) {
        middleSubList!._add(i);
      } else {
        rightSubList!._add(i);
      }
      ic += i.itemCount;
      i = next;
    }

    middleSubList?._invalidate();
    rightSubList?._invalidate();

    assert(isEmpty);

    changed = true;
  }

  void newContent(int count, [bool spawned = false]) {
    assert(_debugAssertNotDisposed());
    assert(isEmpty && count > 0);
    final interval = spawned
        ? _NormalInterval.completed(count)
        : _ReadyToResizingSpawnedInterval(count);
    interval._validate(0, 0);
    _add(interval);
  }

  //

  void distributeNotification(
    int from,
    int removeCount,
    int insertCount,
    AnimatedWidgetBuilder? offListItemBuilder,
    int offListBuilderOffset,
    _DistributeNotificationCallback callback, {
    Object? params,
    // bool Function(Interval left, Interval right)? borderIntervalChooser,
  }) {
    assert(_debugAssertNotDisposed());
    _Interval? interval = first;
    _Interval? nextInterval;
    var ifrom = 0, ito = 0, mapperDelta = 0;

    final checkBorder = removeCount == 0;

    for (; interval != null; interval = nextInterval) {
      nextInterval = interval.next;

      final to = from + removeCount;
      assert(ifrom == interval.itemOffset + mapperDelta);
      final ic = interval.itemCount;
      ito = ifrom + ic;

      assert(from >= ifrom);
      if (from <= ito) {
        final leading = from - ifrom;
        if (to <= ito) {
          final trailing = ito - to;
          // final bool left;
          // if (checkBorder && trailing == 0 && leading == ic) {
          //   left = (nextInterval == null ||
          //       (borderIntervalChooser?.call(interval, nextInterval) ?? true));
          // } else {
          //   left = true;
          // }
          // if (left) {
          callback(interval, this, removeCount, insertCount, leading, trailing,
              offListItemBuilder, offListBuilderOffset, params);
          return;
          // } else {
          //   ifrom += ic;
          // }
        } else {
          assert(!checkBorder);
          final rem = ito - from;
          final ins = math.min(rem, insertCount);
          callback(interval, this, rem, ins, leading, 0, offListItemBuilder,
              offListBuilderOffset, params);
          ifrom = from + ins;
          from = ito + ins - rem;
          offListBuilderOffset += rem;
          insertCount -= ins;
          removeCount -= rem;
        }
      } else {
        ifrom += ic;
      }
    }
    throw Exception('this point should never have been reached');
  }

  _Interval intervalAtBuildIndex(int buildIndex) {
    assert(_debugAssertNotDisposed());
    var buildOffset = 0;
    _Interval? interval, nextInterval;
    for (interval = first; interval != null; interval = nextInterval) {
      nextInterval = interval.next;
      if (buildIndex < interval.buildCount + buildOffset) {
        return interval;
      }
      buildOffset += interval.buildCount;
    }
    throw Exception('this point should never have been reached');
  }

  _Interval intervalAtItemIndex(int listIndex) {
    assert(_debugAssertNotDisposed());
    var itemOffset = 0;
    _Interval? interval, nextInterval;
    for (interval = first; interval != null; interval = nextInterval) {
      nextInterval = interval.next;
      if (listIndex < interval.itemCount + itemOffset) {
        return interval;
      }
      itemOffset += interval.itemCount;
    }
    throw Exception('this point should never have been reached');
  }

  /// The child manager invokes this method in order to retrieve the [Widget]
  /// to be built at the [buildIndex].
  Widget build(BuildContext context, int buildIndex, bool measureOnly) {
    assert(_debugAssertNotDisposed());
    final interval = intervalAtBuildIndex(buildIndex);
    return interval.buildWidget(
      manager.interface,
      context,
      buildIndex - interval.buildOffset,
      measureOnly,
    );
  }

  void validate() {
    assert(_debugAssertNotDisposed());
    _leftMostDirtyInterval?.validate();
  }

  void _invalidate() {
    forEach((i) => i._invalidate());
    _leftMostDirtyInterval = firstOrNull;
  }

  @mustCallSuper
  void dispose() {
    assert(_debugAssertNotDisposed());
    final l = toList();
    l.forEach((i) => i
      .._remove()
      ..dispose());
    popUpList = null;
    holder = null;
    _leftMostDirtyInterval = null;
    _disposed = true;
    assert(isEmpty);
  }

  @override
  String toString() => '[${join(', ')}]';

  String toShortString() =>
      '[${map<String>((i) => i.toShortString()).join(', ')}]';

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

  bool debugAssertIntervalsConsistency(Iterable<_Interval> intervals) {
    assert(() {
      if (intervals.isEmpty) return false;
      _Interval? prev;
      for (final i in intervals) {
        if (!i._debugAssertAttachedToList()) return false;
        if (i.list != this) return false;
        if (prev != null) {
          if (i.previous != prev) return false;
        }
        prev = i;
      }
      return true;
    }());
    return true;
  }

  bool debugDirtyConsistency() {
    assert(() {
      var buildOffset = 0;
      var itemOffset = 0;
      _Interval? interval;
      for (interval = firstOrNull;
          interval != null && interval != _leftMostDirtyInterval;
          interval = interval.next) {
        if (interval.isDirty) return false;
        if (interval.buildOffset != buildOffset ||
            interval.itemOffset != itemOffset) {
          return false;
        }
        buildOffset += interval.buildCount;
        itemOffset += interval.itemCount;
      }
      if (_leftMostDirtyInterval != null) {
        if (interval == null) return false;
        do {
          if (!interval!.isDirty) return false;
          interval = interval.next;
        } while (interval != null);
      }
      return true;
    }());
    return true;
  }
}

extension _InterableIntervalExtension on Iterable<_Interval> {
  int get buildCount => fold<int>(0, (pv, i) => pv + i.buildCount);
  // int get itemCount => fold<int>(0, (pv, i) => pv + i.buildCount);
}
