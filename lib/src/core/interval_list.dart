part of 'core.dart';

abstract class _ListIntervalInterface extends BuildContext {
  AnimatedSliverChildDelegate get delegate;
  bool get isHorizontal;
  Widget buildWidget(
      AnimatedWidgetBuilder builder, int index, AnimatedWidgetBuilderData data);
  void resizingIntervalUpdated(AnimatedSpaceInterval interval, double delta);
  Future<Measure> measureItems(
      Cancelled? cancelled, int count, IndexedWidgetBuilder builder);
  double measureItem(Widget widget);
  void markNeedsBuild();
  void markNeedsLayout();
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

  /// Any pop-up lists that the child manager has to take into account in the next rebuild
  /// via the [AnimatedSliverMultiBoxAdaptorElement.performRebuild] method.
  final popUpLists = List<_PopUpList>.empty(growable: true);

  /// All animations attached to its intervals.
  final animations = <_ControlledAnimation>{};

  var _disposed = false;

  /// Total count of the items to be built in the list view.
  int get buildItemCount => fold<int>(0, (v, i) => v + i.buildCount);

  /// Total count of the underlying list items.
  int get listItemCount => fold<int>(0, (v, i) => v + i.itemCount);

  /// The [AnimatedListAnimator] instance taken from the [AnimatedSliverChildDelegate].
  AnimatedListAnimator get animator => interface.delegate.animator;

  /// Returns `true` if there are pending updates.
  bool get hasPendingUpdates =>
      updates.isNotEmpty || popUpLists.any((e) => e.updates.isNotEmpty);

  /// The builder for the items of the underlying list.
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
    popUpLists.clear();
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

  /// Returns the index of the first buildable item of the [interval].
  int buildItemIndexOf(_Interval interval) {
    assert(_debugAssertNotDisposed());
    assert(interval.list == this);
    var i = 0;
    for (var node = interval.previous; node != null; node = node.previous) {
      i += node.buildCount;
    }
    return i;
  }

  /// Returns the index of the first item of the undeerlying list covered by the [interval].
  int listItemIndexOf(_Interval interval) {
    assert(_debugAssertNotDisposed());
    assert(interval.list == this);
    var i = 0;
    for (var node = interval.previous; node != null; node = node.previous) {
      i += node.itemCount;
    }
    return i;
  }

  /// Returns the interval responsible for building the item at the [buildIndex].
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

  /// Returns the interval that is covering the item of the underlying list at the [listIndex].
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

  /// The child manager invokes this method in order to retrieve the [Widget]
  /// to be built at the [buildIndex].
  Widget build(BuildContext context, int buildIndex, bool measureOnly) {
    final info = intervalAtBuildIndex(buildIndex);
    return info.interval.buildWidget(
        context, buildIndex - info.buildIndex, info.itemIndex, measureOnly);
  }

  /// Adds a new [_Update] element in the update list of this list interval or pop-up list.
  /// This methods also instructs the child manager to be rebuilt.
  void addUpdate(int index, int oldBuildItemCount, int newBuildCount,
      {_UpdateFlags mode = const _UpdateFlags(),
      _PopUpList? popUpList,
      _PopUpList? ref}) {
    assert(_debugAssertNotDisposed());
    (popUpList?.updates ?? updates)
        .add(_Update(index, oldBuildItemCount, newBuildCount, mode, ref));
    interface.markNeedsBuild();
  }

  // This interval list has notified that a range of the underlying list has been replaced.
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

  // This interval list has notified that a range of the underlying list has been changed.
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

  /// It converts the builder passed in [notifyReplacedRange] or [notifyChangedRange] in an
  /// interval builder with the specified [offset].
  _IntervalBuilder _offListBuilder(final AnimatedWidgetBuilder builder,
      [final int offset = 0]) {
    assert(offset >= 0);
    return (context, buildIndexOffset, listIndexOffset, data) =>
        interface.buildWidget(builder, buildIndexOffset + offset, data);
  }

  /// Distributes the replacment or change notification across all intervals in this list.
  /// The [callback] is called for each interval involved.
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

  /// It transforms the interval affected by a replacement notification.
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
              ri.currentSize, length, ri.currentLength, priority));
    } else if (interval is _PopUpRemovableInterval) {
      if (insertCount > 0) {
        final spawnInterval =
            _ReadyToResizingSpawnedInterval(insertCount, priority);
        interval.insertBefore(spawnInterval);
      }
      if (removeCount > 0) {
        assert(removeCount == 1 && leading == 0 && trailing == 0);

        interval.remove(priority);

        final newInterval = _MoveRemovingInterval(
            interval.popUpList,
            _createAnimation(animator.dismiss())..start(),
            offListItemBuilder!.call());
        add(newInterval);
        addUpdate(0, 1, 1, popUpList: newInterval.popUpList);
      }
    }
  }

  /// It transforms the interval affected by a change notification.
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
              ri.currentSize, length, ri.currentLength, priority));
    } else if (interval is _PopUpChangeableInterval) {
      assert(changeCount == 1);

      final measuredWidget = interval.buildPopUpWidget(
          interface, 0, listItemIndexOf(interval), true);

      final newItemSize = interface.measureItem(measuredWidget);

      if (interval.popUpList.itemSize != newItemSize) {
        interval.popUpList.itemSize = newItemSize;
        interval.change(newItemSize);
      }

      addUpdate(0, 1, 1, popUpList: interval.popUpList);
    }
  }

  /// It transforms some or all ready-to intervals into a new type of intervals.
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
        addUpdate(buildItemIndexOf(interval), interval.buildCount,
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
        addUpdate(buildItemIndexOf(interval), interval.buildCount,
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
        addUpdate(buildItemIndexOf(interval), interval.buildCount,
            newInterval.buildCount,
            mode: _UpdateFlags(_UpdateFlags.discardElement |
                _UpdateFlags.clearLayoutOffset |
                (interval.fromSize!.estimated
                    ? 0
                    : _UpdateFlags.keepFirstLayoutOffset)));
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
        addUpdate(buildItemIndexOf(isi), interval.buildCount, isi.buildCount,
            mode: _UpdateFlags(_UpdateFlags.discardElement |
                _UpdateFlags.clearLayoutOffset |
                (interval.toSize.estimated
                    ? 0
                    : _UpdateFlags.keepFirstLayoutOffset)));
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

  /// This is Called when an [interval] has completed its animation.
  /// It could transform that interval into a new type of interval.
  void _onIntervalCompleted(AnimatedInterval interval) {
    if (interval is _MoveDropInterval) {
      if (interval.areAnimationsCompleted) {
        final buildOffset = buildItemIndexOf(interval);
        _replace(interval, _NormalInterval(1));
        interval.popUpList.interval =
            null; // this marks the pop-up list to be removed
        addUpdate(buildOffset, 1, 1,
            mode: const _UpdateFlags(_UpdateFlags.popupDrop),
            ref: interval.popUpList);
      }
    } else if (interval is _RemovalInterval) {
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
        addUpdate(buildOffset, interval.buildCount, 0);
        interval.dispose();
      }
    } else if (interval is _InsertionInterval) {
      final buildOffset = buildItemIndexOf(interval);
      final newInterval = _NormalInterval(interval.length);
      addUpdate(buildOffset, interval.buildCount, newInterval.buildCount);
      _replace(interval, newInterval);
    } else if (interval is _ReorderClosingInterval) {
      final buildOffset = buildItemIndexOf(interval);
      addUpdate(buildOffset, interval.buildCount, 0);
      interval.dispose();
    } else if (interval is _MoveRemovingInterval) {
      addUpdate(1, 0, 0, popUpList: interval.popUpList);
      interval.popUpList.interval =
          null; // this marks the pop-up list to be removed
      interval.dispose();
    }
  }

  /// It analyzes if there are intervals that can be merged together in order to optimize this list.
  void _optimize() {
    var interval = isEmpty ? null : first;
    _Interval? leftInterval;
    while (interval != null) {
      var nextInterval = interval.next;

      var mergeResult =
          leftInterval != null ? interval.mergeWith(leftInterval) : null;
      if (mergeResult != null) {
        if (mergeResult.physicalMerge) {
          addUpdate(
              buildItemIndexOf(leftInterval!),
              leftInterval.buildCount + interval.buildCount,
              mergeResult.mergedInterval.buildCount,
              mode: const _UpdateFlags(_UpdateFlags.clearLayoutOffset |
                  _UpdateFlags.keepFirstLayoutOffset));
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

  _ControlledAnimation _createAnimation(AnimatedListAnimationData data) {
    assert(_debugAssertNotDisposed());
    final animation = _ControlledAnimation(
      this,
      data.animation,
      data.duration,
      startTime: data.startTime,
      onDispose: (a) => animations.remove(a),
    );
    animations.add(animation);
    animation.addListener(() {
      // when the animation is complete it notifies all its linked intervals
      if (animation.intervals.isNotEmpty) {
        animation.intervals.toList().forEach((i) => _onIntervalCompleted(i));
        coordinate();
      }
    });
    return animation;
  }

  @override
  String toString() =>
      '[${fold<String>('', (v, e) => (v.isEmpty ? '' : '$v, ') + e.toShortString())}]';
  // '[${fold<String>('', (v, e) => (v.isEmpty ? '' : '$v, ') + e.toString())}]';

  //
  // Reorder & Move Feature
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
  int reorderDropListIndex(int pickListIndex) {
    final open = whereType<_ReorderOpeningInterval>();
    late int index;
    assert(open.length == 1);
    index = listItemIndexOf(open.single);
    if (index > pickListIndex) index--;
    return index;
  }

  /// It splits the [_NormalInterval] at the exact point indicated by the [itemIndex] and
  /// removes the item (which will be the one dragged) to make room for two new intervals, a
  /// fully open [_ReorderOpeningInterval] and a [_ReorderHolderNormalInterval] which holds
  /// the item of the underlying list but prevents it from being built.
  /// The dragged item will be built in a new separated pop-up list.
  /// The initial [slot] of the picked item must be provided.
  void reorderStart(int itemIndex, Object? slot) {
    final info = intervalAtItemIndex(itemIndex);
    final normalInterval = info.interval as _NormalInterval;
    final offset = itemIndex - info.itemIndex;
    final result =
        normalInterval.split(offset, normalInterval.itemCount - offset - 1);
    final popUpList = _SingleElementPopUpList();
    popUpList.slot = slot;
    popUpLists.add(popUpList);
    final reorderInterval = _ReorderHolderNormalInterval(popUpList);
    _replaceWithSplit(
        normalInterval, result.left, reorderInterval, result.right);
    popUpList.itemSize = interface.measureItem(
        reorderInterval.buildPopUpWidget(interface, 0, itemIndex, true));
    final openingInterval = _ReorderOpeningInterval(
        const _CompletedAnimation(), popUpList.itemSize, popUpList.itemSize);
    reorderInterval.insertBefore(openingInterval);
    addUpdate(info.buildIndex + offset, 1, 1,
        mode: const _UpdateFlags(_UpdateFlags.popupPick), ref: popUpList);
  }

  /// It converts the open (or opening) interval with a [_MoveDropInterval].
  /// In addition it removes the [_ReorderHolderNormalInterval] from this list.
  void reorderStop(bool cancel, double fromOffset) {
    final dropInterval = whereType<_ReorderOpeningInterval>().single;
    final holderInterval = whereType<_ReorderHolderNormalInterval>().single;

    final popUpList = holderInterval.popUpList;
    addUpdate(0, 1, 1, popUpList: popUpList);

    final itemSize = dropInterval.itemSize;

    if (cancel &&
        listItemIndexOf(dropInterval) != listItemIndexOf(holderInterval)) {
      final newInterval = _MoveDropInterval(
        popUpList,
        _createAnimation(animator.resizingDuringReordering(0.0, itemSize))
          ..start(),
        _createAnimation(animator.moving()),
        itemSize,
        0.0,
        fromOffset,
      );
      _replace(holderInterval, newInterval);
      addUpdate(buildItemIndexOf(newInterval), 0, 1);
      reorderCloseAll();
    } else {
      final newInterval = _MoveDropInterval(
        popUpList,
        dropInterval._animation,
        _createAnimation(animator.moving()),
        itemSize,
        dropInterval.fromSize.value,
        fromOffset,
      );
      _replace(dropInterval, newInterval);
      addUpdate(buildItemIndexOf(newInterval), 1, 1);
      holderInterval.dispose();
    }
  }

  /// It splits the [normalInterval] at the exact point indicated by [offset] by
  /// inserting a new [_ReorderOpeningInterval].
  /// The opening interval, if any, will be replaced with a closing interval.
  void reorderUpdateDropListIndex(
      _NormalInterval normalInterval, int offset, double itemSize) {
    reorderCloseAll();
    final result =
        normalInterval.split(offset, normalInterval.buildCount - offset);
    final middle = _ReorderOpeningInterval(
        _createAnimation(animator.resizingDuringReordering(0.0, itemSize))
          ..start(),
        itemSize,
        0.0);
    _replaceWithSplit(normalInterval, result.left, middle, result.right);
    addUpdate(buildItemIndexOf(middle), 0, 1);
  }

  // It recreates all intervals that are closing to keep stable the offset layout
  // of the items not affected by reordering.
  // Also, eventually transforms the open (or opening) interval in a new
  // closing interval.
  void reorderCloseAll() {
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
      addUpdate(buildIndex, 1, 1);
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
      addUpdate(buildIndex, 1, 1);
    }
  }

  /// It recreates the open interval in order to be eventually resized according to
  /// the [newItemSize].
  void reorderChangeOpeningIntervalSize(double newItemSize) {
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
        addUpdate(buildIndex, 1, 1);
      }
    }
  }

  /// It transforms the specified [_MoveDropInterval] into a new [_ResizingInterval].
  void moveDismissOpeningInterval(_MoveDropInterval interval, int priority) {
    final index = buildItemIndexOf(interval);
    final resizingInterval = _ResizingInterval(
        _createAnimation(animator.resizing(interval.currentSize, 0.0))..start(),
        interval.currentSize.toExactMeasure(),
        Measure.zero,
        interval.currentLength,
        0,
        priority);
    _replace(interval, resizingInterval);
    addUpdate(index, 1, 1);
  }

  /// It recreates the specified [_MoveDropInterval] in order to be rebuilt making room
  /// for the [newItemSize].
  void moveChangeOpeningIntervalSize(
      _MoveDropInterval interval, double newItemSize) {
    if (_isAccetableResizeAmount(interval.toSize.value - newItemSize)) {
      final buildIndex = buildItemIndexOf(interval);
      _replace(
          interval,
          _MoveDropInterval(
              interval.popUpList,
              _createAnimation(
                  animator.resizing(interval.currentSize, newItemSize))
                ..start(),
              interval.moveAnimation,
              newItemSize,
              interval.currentSize,
              interval.currentScrollOffset));
      addUpdate(buildIndex, 1, 1);
    }
  }
}
