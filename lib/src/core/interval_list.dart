part of 'core.dart';

abstract class _ListIntervalInterface extends BuildContext {
  AnimatedSliverChildDelegate get delegate;
  bool get isHorizontal;
  Widget buildWidget(
      AnimatedWidgetBuilder builder, int index, AnimatedWidgetBuilderData data);
  void resizingIntervalUpdated(_AnimatedSpaceInterval interval, double delta);
  Future<_Measure> measureItems(
      _Cancelled? cancelled, int count, IndexedWidgetBuilder builder);
  double measureItem(Widget widget);
  void markNeedsBuild();
}

typedef _NotifyCallback = void Function(
  _Interval interval,
  int removeCount,
  int insertCount,
  int leading,
  int trailing,
  _IntervalBuilder Function()? offListItemBuilder,
  int priority,
);

class _IntervalInfo {
  const _IntervalInfo(this.interval, this.buildIndex, this.itemIndex)
      : assert(buildIndex >= 0 && itemIndex >= 0);

  final _Interval interval;
  final int buildIndex;
  final int itemIndex;
}

/// This class handles all changes to the list view by breaking up the entire list as a
/// list of contigous intervals, each with its own meaning.
///
/// This class is a linked list and all the intervals are its nodes.
class _IntervalList extends LinkedList<_Interval> with TickerProviderMixin {
  _IntervalList(this.interface) {
    final initialCount = interface.delegate.initialChildCount;
    if (initialCount > 0) add(_NormalInterval(initialCount));
  }

  // This allows to communicate with the child manager.
  final _ListIntervalInterface interface;

  /// Any updates that the child manager has to take into account in the next rebuild
  /// via the [AnimatedSliverMultiBoxAdaptorElement.performRebuild] method.
  final updates = List<_Update>.empty(growable: true);

  final popUpLists = List<_PopUpList>.empty(growable: true);

  /// All animations attached to the intervals.
  final animations = <_ControlledAnimation>{};

  var _disposed = false;

  // Total count of the items to be built in the list view.
  int get buildItemCount => fold<int>(0, (v, i) => v + i.buildCount);

  // Total count of the underlying list items.
  int get listItemCount => fold<int>(0, (v, i) => v + i.itemCount);

  AnimatedListAnimator get animator => interface.delegate.animator;

  // Returns true if there are pending updates.
  bool get hasPendingUpdates => updates.isNotEmpty;

  // Interval builder for underlying list items.
  Widget inListBuilder(int buildIndexOffset, int listIndexOffset,
      AnimatedWidgetBuilderData data) {
    return interface.buildWidget(
        interface.delegate.builder, listIndexOffset + buildIndexOffset, data);
  }

  @override
  void dispose() {
    _disposed = true;
    toList().forEach((i) => i.dispose());
    animations.clear();
    updates.clear();
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

  _IntervalInfo intervalAtItemIndex(int listIndex) {
    assert(_debugAssertNotDisposed());
    var buildOffset = 0, itemOffset = 0;
    _Interval? interval, nextInterval;
    for (interval = first; interval != null; interval = nextInterval) {
      nextInterval = interval.next;
      if (listIndex < interval.itemCount + itemOffset) {
        return _IntervalInfo(interval, buildOffset, itemOffset);
      }
      buildOffset += interval.buildCount;
      itemOffset += interval.itemCount;
    }
    throw Exception('this point should never have been reached');
  }

  // The child manager invokes this method in order to retrieve the Widget at the
  // specified build index.
  Widget build(BuildContext context, int buildIndex, bool measureOnly) {
    final info = intervalAtBuildIndex(buildIndex);
    return info.interval.buildWidget(
        context, buildIndex - info.buildIndex, info.itemIndex, measureOnly);
  }

  void _addUpdate(int index, int oldBuildItemCount, int newBuildCount,
      [_UpdateFlags mode = 0, _PopUpList? popUpList]) {
    assert(_debugAssertNotDisposed());
    updates
        .add(_Update(index, oldBuildItemCount, newBuildCount, mode, popUpList));
    interface.markNeedsBuild();
  }

  void _addPopUpUpdate(
    _PopUpList popUpList,
    int index,
    int oldBuildItemCount,
    int newBuildCount, [
    _UpdateFlags mode = 0,
  ]) {
    assert(_debugAssertNotDisposed());
    popUpList.updates
        .add(_Update(index, oldBuildItemCount, newBuildCount, mode));
    interface.markNeedsBuild();
  }

  // The list view has notified that a range of the underlying list has been replaced.
  void notifyReplacedRange(int from, int removeCount, int insertCount,
      AnimatedWidgetBuilder? removeItemBuilder, int priority) {
    assert(_debugAssertNotDisposed());
    assert(from >= 0);
    assert(removeCount >= 0 && insertCount >= 0);
    assert(from + removeCount <= listItemCount);

    _distributeNotification(from, removeCount, insertCount, removeItemBuilder,
        priority, _onReplaceNotification);

    _optimize();
  }

  // The list view has notified that a range of the underlying list has been changed.
  void notifyChangedRange(int from, int count,
      AnimatedWidgetBuilder? changeItemBuilder, int priority) {
    assert(_debugAssertNotDisposed());
    assert(from >= 0);
    assert(count >= 0);
    assert(from + count <= listItemCount);

    _distributeNotification(
        from, count, count, changeItemBuilder, priority, _onChangeNotification);

    _optimize();
  }

  void _distributeNotification(
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
              offListItemBuilder == null
                  ? null
                  : () =>
                      _offListBuilder(offListItemBuilder, offListBuilderOffset),
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
              offListItemBuilder == null
                  ? null
                  : () =>
                      _offListBuilder(offListItemBuilder, offListBuilderOffset),
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

  /// It converts the builder passed in [notifyReplacedRange] or [notifyRangeChange] in an
  /// interval builder with offset.
  _IntervalBuilder _offListBuilder(final AnimatedWidgetBuilder builder,
      [final int offset = 0]) {
    assert(offset >= 0);
    return (context, buildIndexOffset, listIndexOffset, data) =>
        interface.buildWidget(builder, buildIndexOffset + offset, data);
  }

  void _onReplaceNotification(
      _Interval interval,
      int removeCount,
      int insertCount,
      int leading,
      int trailing,
      _IntervalBuilder Function()? offListItemBuilder,
      int priority) {
    if (removeCount == 0 && insertCount == 0) return;

    if (interval is _SplittableInterval) {
      final result = interval.split(leading, trailing);
      late _Interval middle;
      if (removeCount > 0) {
        middle = _ReadyToRemovalInterval(interval._animation,
            offListItemBuilder!.call(), removeCount, insertCount, priority);
      } else {
        middle = _ReadyToResizingSpawnedInterval(insertCount, priority);
      }
      _replaceWithSplit(interval, result.left, middle, result.right);
    } else if (interval is _AdjustableInterval) {
      final length = interval.itemCount - removeCount + insertCount;
      if (length != interval.itemCount) {
        final newInterval = interval.cloneWithNewLenght(length);
        if (newInterval != null) {
          _replace(interval, newInterval);
        } else {
          interval.dispose();
        }
      }
    } else if (interval is _ResizableInterval) {
      final length = interval.itemCount - removeCount + insertCount;
      final ri = interval as _ResizableInterval;
      ri.stop();
      _replace(
          interval,
          _ReadyToNewResizingInterval(
              ri.currentSize, length, ri.averageItemCount, priority));
    } else if (interval is _ReorderHolderNormalInterval) {
      if (insertCount > 0) {
        final spawnInterval =
            _ReadyToResizingSpawnedInterval(insertCount, priority);
        interval.insertBefore(spawnInterval);
      }
      if (removeCount > 0) {
        assert(removeCount == 1);
        _reorderUpdateClosingIntervals();
        final newInterval = _ReorderHolderRemovingInterval(
            interval.popUpList,
            _createAnimation(animator.dismiss())..start(),
            offListItemBuilder!.call());
        _replace(interval, newInterval);
        _addPopUpUpdate(newInterval.popUpList, 0, 1, 1);
      }
    }
  }

  void _onChangeNotification(
      _Interval interval,
      int changeCount,
      int _,
      int leading,
      int trailing,
      _IntervalBuilder Function()? offListItemBuilder,
      int priority) {
    assert(changeCount == _);
    if (changeCount == 0) return;

    if (interval is _NormalInterval || interval is _InsertionInterval) {
      final result = (interval as _SplittableInterval).split(leading, trailing);
      late _Interval middle;
      middle = _ReadyToChangingInterval(interval._animation,
          offListItemBuilder!.call(), changeCount, priority);
      _replaceWithSplit(interval, result.left, middle, result.right);
    } else if (interval is _ResizableInterval) {
      final length = interval.itemCount;
      final ri = interval as _ResizableInterval;
      ri.stop();
      _replace(
          interval,
          _ReadyToNewResizingInterval(
              ri.currentSize, length, ri.averageItemCount, priority));
    } else if (interval is _ReorderHolderNormalInterval) {
      final measuredWidget = interval.buildPopUpWidget(
          interface, 0, listItemIndexOf(interval), true);

      final newItemSize = interface.measureItem(measuredWidget);

      if (interval.popUpList.itemSize != newItemSize) {
        interval.popUpList.itemSize = newItemSize;
        _reorderChangeOpeningIntervalSize(newItemSize);
      }

      _addPopUpUpdate(interval.popUpList, 0, 1, 1);
    }
  }

  // Transforms some or all ready-to intervals into a new type of intervals.
  void coordinate() {
    var remPri = -1;
    var rem = whereType<_ReadyToRemovalInterval>();
    if (rem.isNotEmpty) {
      rem.toList().forEach((interval) {
        remPri = math.max(remPri, interval.priority);
        final animation = interval.isWaitingAtEnd
            ? _createAnimation(animator.dismiss())
            : _createAnimation(
                animator.dismissDuringIncoming(interval._animation.time));
        final newInterval = _RemovalInterval(
            animation..start(),
            interval.builder,
            interval.offLength,
            interval.inLength,
            interval.priority);
        _addUpdate(buildItemIndexOf(interval), interval.buildCount,
            newInterval.buildCount);
        _replace(interval, newInterval);
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
        _addUpdate(buildItemIndexOf(interval), interval.buildCount,
            newInterval.buildCount);
        _replace(interval, newInterval);
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
        interval.measure().whenComplete(coordinate);
      });
      res
          .where((e) => e.isMeasured && !e.isMeasuring)
          .toList()
          .forEach((interval) {
        resPri = math.max(resPri, interval.priority);
        final newInterval = _ResizingInterval(
            _createAnimation(animator.resizing(
                interval.fromSize!.value, interval.toSize!.value))
              ..start(),
            interval.fromSize!,
            interval.toSize!,
            interval.fromLength,
            interval.itemCount,
            interval.priority);
        _addUpdate(
            buildItemIndexOf(interval),
            interval.buildCount,
            newInterval.buildCount,
            _UpdateFlagsEx.DISCARD_ELEMENT |
                _UpdateFlagsEx.CLEAR_LAYOUT_OFFSET |
                (interval.fromSize!.estimated
                    ? 0
                    : _UpdateFlagsEx.KEEP_FIRST_LAYOUT_OFFSET));
        _replace(interval, newInterval);
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
            _createAnimation(animator.incoming())..start(), interval.toLength);
        _replace(interval, isi);
        _addUpdate(
            buildItemIndexOf(isi),
            interval.buildCount,
            isi.buildCount,
            _UpdateFlagsEx.DISCARD_ELEMENT |
                _UpdateFlagsEx.CLEAR_LAYOUT_OFFSET |
                (interval.toSize.estimated
                    ? 0
                    : _UpdateFlagsEx.KEEP_FIRST_LAYOUT_OFFSET));
      });
    }

    _optimize();

    assert(() {
      if (length == 1 && first is _NormalInterval) {
        if (animations.isNotEmpty) return false;
        if (hasActiveTickers) return false;
      }
      return true;
    }());
  }

  // Analyze if there are intervals that can be merged together in order to optimize this list.
  void _optimize() {
    var interval = isEmpty ? null : first;
    _Interval? leftInterval;
    while (interval != null) {
      var nextInterval = interval.next;

      var mergeResult =
          leftInterval != null ? interval.mergeWith(leftInterval) : null;
      if (mergeResult != null) {
        if (mergeResult.physicalMerge) {
          _addUpdate(
              buildItemIndexOf(leftInterval!),
              leftInterval.buildCount + interval.buildCount,
              mergeResult.mergedInterval.buildCount,
              _UpdateFlagsEx.CLEAR_LAYOUT_OFFSET |
                  _UpdateFlagsEx.KEEP_FIRST_LAYOUT_OFFSET);
        }
        interval.dispose();
        _replace(leftInterval!, interval = mergeResult.mergedInterval);
      }

      leftInterval = interval;
      interval = nextInterval;
    }
  }

  void _replace(_Interval oldInterval, _Interval newInterval) {
    var prev = oldInterval.previous;
    if (prev != null) {
      oldInterval.insertAfter(newInterval);
    } else {
      addFirst(newInterval);
    }
    oldInterval.dispose();
  }

  void _replaceWithSplit(
      _Interval interval, _Interval? left, _Interval middle, _Interval? right) {
    _replace(interval, middle);
    if (left != null) middle.insertBefore(left);
    if (right != null) middle.insertAfter(right);
  }

  _ControlledAnimation _createAnimation(AnimatedListAnimationData ad) {
    assert(_debugAssertNotDisposed());
    final a = _ControlledAnimation(this, ad.animation, ad.duration,
        startTime: ad.startTime, onDispose: (a) => animations.remove(a));
    animations.add(a);
    a.addListener(() {
      if (a.intervals.isNotEmpty) {
        a.intervals.toList().forEach((i) => _onIntervalCompleted(i));
        coordinate();
      }
    });
    return a;
  }

  // Called when an interval has completed its animation.
  void _onIntervalCompleted(_AnimatedInterval interval) {
    if (interval is _RemovalInterval) {
      var newInterval = _ReadyToResizingIntervalFromRemoval(
          const _DismissedAnimation(),
          interval.builder,
          interval.offLength,
          interval.inLength,
          interval.priority);
      _replace(interval, newInterval);
    } else if (interval is _ResizingInterval) {
      final buildOffset = buildItemIndexOf(interval);
      if (interval.toLength > 0) {
        final newInterval = _ReadyToInsertionInterval(
            interval.toSize, interval.toLength, interval.priority);
        _replace(interval, newInterval);
      } else {
        assert(interval.toSize.value == 0.0);
        _addUpdate(buildOffset, interval.buildCount, 0);
        interval.dispose();
      }
    } else if (interval is _InsertionInterval) {
      final buildOffset = buildItemIndexOf(interval);
      final newInterval = _NormalInterval(interval.length);
      _addUpdate(buildOffset, interval.buildCount, newInterval.buildCount);
      _replace(interval, newInterval);
    } else if (interval is _ReorderClosingInterval) {
      final buildOffset = buildItemIndexOf(interval);
      _addUpdate(buildOffset, interval.buildCount, 0);
      interval.dispose();
    } else if (interval is _ReorderHolderRemovingInterval) {
      _addPopUpUpdate(interval.popUpList, 1, 0, 0);
      interval.popUpList.interval = null;
      interval.dispose();
    }
  }

  @override
  String toString() =>
      '[${fold<String>('', (v, e) => (v.isEmpty ? '' : '$v, ') + e.toShortString())}]';
  // '[${fold<String>('', (v, e) => (v.isEmpty ? '' : '$v, ') + e.toString())}]';

  //
  // Reorder Feature Support
  //

  /// It searches for the interval that holds the underlying list item that is being dragged,
  /// and returns its index if it is found.
  int? get reorderPickListIndex {
    final l = whereType<_ReorderHolderNormalInterval>();
    assert(l.length <= 1);
    if (l.isEmpty) return null;
    return listItemIndexOf(l.single);
  }

  /// It searches for the open (or opening) interval prepared to host the item dragged and returns
  /// its corresponding index of the underlying list.
  /// The initial index of the dragged item is required in this calculation, and if it is available
  /// you can pass it via [pickListIndex], otherwise it will also be calculated.
  int reorderDropListIndex([int? pickListIndex]) {
    final open = whereType<_ReorderOpeningInterval>();
    late int index;
    assert(open.length == 1);
    index = listItemIndexOf(open.single);
    if (index > (pickListIndex ?? reorderPickListIndex!)) index--;
    return index;
  }

  /// It splits the [_NormalInterval] at the exact point indicated by the [itemIndex] and
  /// removes the item (which will be the one dragged) to make room for two new intervals, a
  /// fully open [_ReorderOpeningInterval] and a [_ReorderHolderNormalInterval] which holds the item
  /// of the underlying list but prevents it from being built.
  /// The initial [slot] of the picked item must be provided.
  void notifyStartReorder(int itemIndex, Object? slot) {
    final info = intervalAtItemIndex(itemIndex);
    final normalInterval = info.interval as _NormalInterval;
    final offset = itemIndex - info.itemIndex;
    final result =
        normalInterval.split(offset, normalInterval.itemCount - offset - 1);
    final popUpList = _ReorderPopUpList();
    popUpLists.add(popUpList);
    final reorderInterval = _ReorderHolderNormalInterval(popUpList);
    popUpList.slot = slot;
    _replaceWithSplit(
        normalInterval, result.left, reorderInterval, result.right);
    popUpList.itemSize = interface.measureItem(
        reorderInterval.buildPopUpWidget(interface, 0, itemIndex, true));
    final middle = _ReorderOpeningInterval(
        const _CompletedAnimation(), popUpList.itemSize, popUpList.itemSize);
    reorderInterval.insertBefore(middle);
    _addUpdate(
        info.buildIndex + offset, 1, 1, _UpdateFlagsEx.REORDER_PICK, popUpList);
  }

  /// It replaces the open (or opening) interval with a [_NormalInterval] of length `1`
  /// which represents the dropped item.
  /// In addition it removes the [_ReorderHolderNormalInterval] from this list.
  /// The build index of the dropped item is returned.
  void notifyStopReorder(bool cancel) {
    final dropInterval = whereType<_ReorderOpeningInterval>().single;
    final normalInterval = _NormalInterval(1);
    final holderInterval = whereType<_ReorderHolderNormalInterval>().single;

    popUpLists.remove(holderInterval.popUpList);

    if (cancel) {
      _addUpdate(buildItemIndexOf(dropInterval), 1, 0);
      dropInterval.dispose();
      _replace(holderInterval, normalInterval);
      _addUpdate(buildItemIndexOf(normalInterval), 0, 1,
          _UpdateFlagsEx.REORDER_DROP, holderInterval.popUpList);
    } else {
      _replace(dropInterval, normalInterval);
      holderInterval.dispose();
      _addUpdate(buildItemIndexOf(normalInterval), 1, 1,
          _UpdateFlagsEx.REORDER_DROP, holderInterval.popUpList);
    }

    _optimize();
  }

  /// It splits the [_NormalInterval] at the exact point indicated by [offset] by
  /// inserting a new [_ReorderOpeningInterval].
  /// Any previous opening interval will be replaced with a closing interval.
  void updateReorderDropIndex(
      _NormalInterval normalInterval, int offset, double itemSize) {
    _reorderUpdateClosingIntervals();
    final result =
        normalInterval.split(offset, normalInterval.buildCount - offset);
    final middle = _ReorderOpeningInterval(
        _createAnimation(animator.resizingDuringReordering(0.0, itemSize))
          ..start(),
        itemSize,
        0.0);
    _replaceWithSplit(normalInterval, result.left, middle, result.right);
    _addUpdate(buildItemIndexOf(middle), 0, 1);
  }

  // It recreates all intervals that are closing to keep stable the offset layouts
  // of the items not affected by reordering.
  // Also, eventually transforms the open (or opening) interval in a new
  // closing interval.
  void _reorderUpdateClosingIntervals() {
    whereType<_ReorderClosingInterval>().toList().forEach((interval) {
      final buildIndex = buildItemIndexOf(interval);
      _replace(
          interval,
          _ReorderClosingInterval(
              _createAnimation(
                  animator.resizingDuringReordering(interval.currentSize, 0.0))
                ..start(),
              interval.itemSize,
              interval.currentSize));
      _addUpdate(buildIndex, 1, 1);
    });

    final maybeOpenInterval = whereType<_ReorderOpeningInterval>();
    assert(maybeOpenInterval.length <= 1);
    if (maybeOpenInterval.length == 1) {
      final openInterval = maybeOpenInterval.single;
      final buildIndex = buildItemIndexOf(openInterval);
      _replace(
          openInterval,
          _ReorderClosingInterval(
              _createAnimation(animator.resizingDuringReordering(
                  openInterval.currentSize, 0.0))
                ..start(),
              openInterval.itemSize,
              openInterval.currentSize));
      _addUpdate(buildIndex, 1, 1);
    }
  }

  /// It recreates the open interval in order to be eventually resized according to
  /// the new size [newItemSize].
  void _reorderChangeOpeningIntervalSize(double newItemSize) {
    final maybeOpenInterval = whereType<_ReorderOpeningInterval>();
    assert(maybeOpenInterval.length <= 1);

    if (maybeOpenInterval.length == 1) {
      final openInterval = maybeOpenInterval.single;
      if (_isAccetableResizeAmount(openInterval.toSize.value - newItemSize)) {
        final buildIndex = buildItemIndexOf(openInterval);
        _replace(
            openInterval,
            _ReorderOpeningInterval(
                _createAnimation(animator.resizingDuringReordering(
                    openInterval.currentSize, newItemSize))
                  ..start(),
                newItemSize,
                openInterval.currentSize));
        _addUpdate(buildIndex, 1, 1);
      }
    }
  }
}
