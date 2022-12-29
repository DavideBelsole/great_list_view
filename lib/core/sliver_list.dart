part of 'core.dart';

const _kReorderingScrollSpeed = 10.0;

/// If `true` during perform layout a dummy [ScrollUpdateNotification] is sent
/// to repaint the widget that is listening to it (ie. [Scrollbar]).
bool fixScrollableRepainting = true;

typedef _ChildList = MultiContainerRenderObjectList<RenderBox,
    MultiSliverMultiBoxAdaptorParentData, _PopUpList?>;

/// This mixin is used by [AnimatedRenderSliverList] and [AnimatedRenderSliverFixedExtentList].
abstract class AnimatedRenderSliverMultiBoxAdaptor
    extends MultiRenderSliverMultiBoxAdaptor {
  AnimatedRenderSliverMultiBoxAdaptor(
      AnimatedSliverMultiBoxAdaptorElement childManager)
      : super(childManager: childManager);

  double _resizeCorrectionAmount = 0.0;

  late _IntervalManager intervalManager;

  @override
  AnimatedSliverMultiBoxAdaptorElement get childManager;

  void init() {
    intervalManager = _IntervalManager(childManager);
  }

  @override
  void dispose() {
    intervalManager.dispose();
    super.dispose();
  }

  void markSafeNeedsLayout() {
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => markNeedsLayout());
    } else {
      markNeedsLayout();
    }
  }

  /// Returns the sum of the sizes of a bunch of items, built using the specified builder.
  Future<_Measure> measureItems(_Cancelled? cancelled, int count,
      IndexedWidgetBuilder builder, double startingSize, int startingCount);

  /// Returns the size of a single widget.
  double measureItem(Widget widget, [BoxConstraints? childConstraints]);

  String debugRenderBoxes(_PopUpList? popUpList) {
    final sl = <String>[];
    var child = listOf(popUpList)?.firstChild;
    while (child != null) {
      sl.add('(${parentDataOf(child)?.index}: ${debugRenderBox(child)})');
      child = _childAfter(child);
    }
    return '{${sl.join(', ')}}';
  }

  /// Calculates an estimate of the maximum scroll offset.
  double? extrapolateMaxScrollOffset(
    final int firstIndex,
    final int lastIndex,
    final double leadingScrollOffset,
    final double trailingScrollOffset,
    final int childCount,
  );

  /// The specified interval has been resized by a delta amount.
  /// If this interval is above the first item layouted in the list view, this amount will be
  /// added up to a cumulative variabile.
  void resizingIntervalUpdated(_AnimatedSpaceInterval interval, double delta) {
    assert(delta != 0.0);
    final firstChild = firstChildWithLayout;
    if (firstChild == null) return;
    if (interval.buildOffset < indexOf(firstChild)) {
      _resizeCorrectionAmount += delta;
    }
    markSafeNeedsLayout();
  }

  _SizeResult? getItemSizesFromSliverList(int buildFrom, int buildTo) {
    assert(!intervalManager.hasPendingUpdates);

    if (firstChild == null) return null;

    var listFrom = indexOf(firstChild!);
    var listTo = indexOf(lastChild!) + 1;

    if (buildTo <= listFrom || buildFrom >= listTo) return null;

    var from = math.max(listFrom, buildFrom);
    var to = math.min(listTo, buildTo);

    if (to <= from) return null;

    var child = firstChild;
    for (var i = listFrom; i < from; i++) {
      child = childAfter(child!);
    }
    var size = 0.0;
    for (var i = from; i < to; i++) {
      size += childSize(child!);
      child = childAfter(child);
    }
    return _SizeResult(from, to, size);
  }

  /// Adjusts the layout offset of the first layouted item by the correction amount
  /// calculated as a result of resizing the intervals above it.
  /// If [AnimatedSliverChildDelegate.holdScrollOffset] if set to `true`, this method
  /// returns `false` and a new geometry will be calculated in order to hold still
  /// the scroll offset.
  bool _adjustTopLayoutOffset() {
    var amount = _resizeCorrectionAmount;
    _resizeCorrectionAmount = 0.0;

    final firstChild = firstChildWithLayout;
    if (firstChild != null) {
      final parentData = parentDataOf(firstChild)!;
      final firstLayoutOffset = parentData.layoutOffset!;
      if (firstLayoutOffset + amount < 0.0) {
        amount = -firstLayoutOffset; // bring back the offset to zero
      }
      if (amount != 0.0) {
        parentData.layoutOffset = parentData.layoutOffset! + amount;
        if (childManager.widget.delegate.holdScrollOffset) {
          geometry = SliverGeometry(scrollOffsetCorrection: amount);
          return false;
        }
      }
    }
    return true;
  }

  /// A `didChangeDependencies` method like in [State.didChangeDependencies],
  /// necessary to update the tickers correctly when the `muted` attribute changes.
  void didChangeDependencies(BuildContext context) {
    intervalManager.updateTickerMuted(context);
  }

  // Returns the first displayed and layouted item.
  RenderBox? get firstChildWithLayout {
    var child = firstChild;
    while (child != null) {
      var offset = childScrollOffset(child);
      if (offset != null) return child;
      child = childAfter(child);
    }
    return null;
  }

  /// Returns the size of the [child] according to the main direction (see [SliverConstraints.axis]).
  double childSize(RenderBox child) {
    switch (constraints.axis) {
      case Axis.horizontal:
        return child.size.width;
      case Axis.vertical:
        return child.size.height;
    }
  }

  MultiSliverMultiBoxAdaptorParentData? parentDataOf(RenderBox? child) =>
      child?.parentData as MultiSliverMultiBoxAdaptorParentData?;

  /// Dispatches a fake change to the [ScrollPosition] to force the listeners
  /// (ie a [Scrollbar]) to refresh its state.
  void _notifyScrollable() {
    final scrollable = Scrollable.of(childManager);
    if (scrollable == null) return;
    final controller = scrollable.widget.controller;
    if (controller == null || !controller.hasClients) return;
    ScrollUpdateNotification(
            metrics: controller.position.copyWith(),
            context: childManager,
            scrollDelta: 0,
            dragDetails: null)
        .dispatch(childManager);
  }

  bool _initScrollOffset = true;

  @override
  void performLayout() {
    _dbgBegin('performLayout()');

    void fn() {
      if (!_adjustTopLayoutOffset()) return;

      if (_initScrollOffset) {
        _initScrollOffset = false;
        final callback =
            childManager.widget.delegate.initialScrollOffsetCallback;
        if (callback != null) {
          double? offset;
          invokeLayoutCallback<SliverConstraints>(
              (SliverConstraints constraints) {
            offset = callback.call(constraints);
          });
          if (offset != null && constraints.scrollOffset != offset) {
            geometry = SliverGeometry(
                scrollOffsetCorrection: offset! - constraints.scrollOffset);
            return;
          }
        }
      }

      _performLayoutAllLists();

      if ((geometry!.scrollOffsetCorrection ?? 0.0) != 0.0) {
        return;
      }

      _reorderPerformLayout();

      intervalManager.listOfPopUps.forEach((popUpList) {
        popUpList.updateScrollOffset?.call(
            (buildIndex, childCount, remainingTime) => childManager
                .estimateLayoutOffset(buildIndex, childCount,
                    time: remainingTime)
                .value);
      });

      if (fixScrollableRepainting) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _notifyScrollable();
        });
      }
    }

    fn();

    childManager.managedPopUpLists.forEach((popUpList) {
      _dbgBegin('structure of $popUpList');
      var c = listOf(popUpList)?.firstChild;
      while (c != null) {
        _dbgPrint('${debugRenderBox(c)}: size=${childSize(c)}');
        c = childAfter(c);
      }
      _dbgEnd();
    });

    _dbgEnd();
  }

  void _performLayoutAllLists() {
    _performLayoutSingleList(null);
    for (final popUpList in intervalManager.listOfPopUps) {
      _performLayoutSingleList(popUpList);
    }
    removeEmptyKeys();
  }

  void _performLayoutSingleList(_PopUpList? popUpList) {
    _dbgBegin('_performLayout popUpList=$popUpList');
    _dbgPrint('[${debugRenderBoxes(popUpList)}]');

    _performLayout(popUpList);

    _dbgPrint('[${debugRenderBoxes(popUpList)}]');
    _dbgEnd();
  }

  @protected
  void _performLayout(_PopUpList? popUpList);

  RenderBox? _childAfter(RenderBox child) {
    assert(child.parent == this);
    return parentDataOf(child)?.nextSibling;
  }

  @override
  RenderBox? childAfter(RenderBox child) {
    if (_popUpChildrenIterator != null) {
      if (!_popUpChildrenIterator!.moveNext()) {
        return null;
      } else {
        return _popUpChildrenIterator!.current;
      }
    }
    return _childAfter(child);
  }

  Iterator<RenderBox>? _popUpChildrenIterator;

  BoxConstraints get childConstraints;

  _Measure estimateLayoutOffset(int buildIndex, int childCount, double? time,
      _MovingPopUpList? popUpList) {
    assert(!intervalManager.hasPendingUpdates);
    final list = listOf(popUpList)!;

    late int firstBuildIndex, lastBuildIndex;
    late double size, pos, count, leadingScrollOffset;
    late _Measure value;
    var outside = false;
    if (buildIndex == 0) {
      value = _Measure.zero;
    } else if (buildIndex == childCount && popUpList == null) {
      value = _Measure(geometry!.scrollExtent);
    } else if (buildIndex < indexOf(list.firstChild!)) {
      // above
      firstBuildIndex = 0;
      lastBuildIndex = indexOf(list.firstChild!);
      leadingScrollOffset = 0.0;
      size = parentDataOf(list.firstChild!)!.layoutOffset!;
      count = lastBuildIndex.toDouble();
      pos = buildIndex.toDouble();
      outside = true;
    } else if (buildIndex > indexOf(list.lastChild!)) {
      // bottom
      firstBuildIndex = indexOf(list.lastChild!) + 1;
      lastBuildIndex = childCount;
      leadingScrollOffset = parentDataOf(list.lastChild!)!.layoutOffset! +
          childSize(list.lastChild!);
      if (childCount == firstBuildIndex) {
        value = _Measure(leadingScrollOffset);
      } else {
        if (popUpList == null) {
          size = geometry!.scrollExtent - leadingScrollOffset;
        } else {
          // For popups you can only estimate
          var list = popUpList.intervals;
          var sz = 0.0, sza = 0.0, aca = 0.0;
          var cnt = 0, cnta = 0;
          var bi = 0;
          for (final i in list) {
            if (i is _SpaceInterval) {
              sz += i.currentSize;
              if (bi < firstBuildIndex) {
                sza += i.currentSize;
                aca += i.averageCount;
              }
            } else {
              cnt += i.buildCount;
              if (bi < firstBuildIndex) {
                cnta += math.min(i.buildCount, firstBuildIndex - bi);
              }
            }
            bi += i.buildCount;
          }
          size = sz - sza;
          final cntb = cnt - cnta;
          if (cnta > 0) {
            if (cntb > 0) {
              size += (leadingScrollOffset - sza) * cntb / cnta;
            }
          } else {
            size += sza * cntb / aca;
          }
        }
        count = (childCount - firstBuildIndex).toDouble();
        pos = (buildIndex - firstBuildIndex).toDouble();
        outside = true;
      }
    } else {
      // inner
      var child = list.firstChild;
      while (child != null) {
        if (indexOf(child) == buildIndex) {
          value = parentDataOf(child)!.layoutOffset!.toExactMeasure();
          break;
        }
        child = childAfter(child);
      }
    }
    if (outside) {
      var bi = 0;
      Iterable<_Interval> list;
      if (popUpList == null) {
        list = intervalManager.list;
      } else {
        list = popUpList.subLists.expand((e) => e);
      }
      for (final interval in list) {
        if (bi >= firstBuildIndex) {
          if (bi >= lastBuildIndex) break;
          if (interval is _SpaceInterval) {
            if (bi < buildIndex) {
              leadingScrollOffset += interval.currentSize;
            }
            count--;
            size -= interval.currentSize;
          }
        }
        bi += interval.buildCount;
      }
      if (count > 0) leadingScrollOffset += (pos * size) / count;
      value = _Measure(leadingScrollOffset);
      assert(value.value.isFinite);
    }
    if (time != null) {
      var adjust = 0.0;
      Iterable<_Interval> list;
      if (popUpList == null) {
        list = intervalManager.list;
      } else {
        list = popUpList.subLists.expand((e) => e);
      }
      var bi = 0;
      for (final i in list) {
        if (bi >= buildIndex) break;
        if (i is _AnimatedSpaceInterval) {
          adjust += i.futureSize(time) - i.currentSize;
        }
        bi += i.buildCount;
      }
      value += adjust.toExactMeasure();
    }
    if (popUpList != null) value += _Measure(popUpList.currentScrollOffset!);
    return value;
  }

  Rect? computeItemBox(int itemIndex, bool absolute, bool avoidMeasuring);

  //
  // Reorder Feature
  //

  _ReorderLayoutData? _reorderLayoutData;

  bool get isReordering => _reorderLayoutData != null;

  bool reorderStart(BuildContext context, double dx, double dy) {
    if (isReordering) return false;

    final slot = childManager.buildIndexFromContext(context);
    if (slot == null || slot.popUpList != null) return false;

    final r = childManager.oldIndexToNewIndex(slot.index, slot.popUpList);
    if (r.newIndex == null || r.needsRebuild || r.discardElement) return false;
    final buildIndex = r.newIndex!;

    final interval = intervalManager.list.intervalAtBuildIndex(buildIndex);
    if (interval is! _NormalInterval) {
      return false;
    }

    final child = childManager.renderBoxAt(slot.index);
    if (child == null) return false;

    final childOffset = parentDataOf(child)?.layoutOffset;
    if (childOffset == null) return false;

    final itemSize = childSize(child);

    final offset = buildIndex - interval.buildOffset;
    final itemIndex = interval.itemOffset + offset;

    final delegate = childManager.widget.delegate;
    if (!(delegate.reorderModel?.onReorderStart.call(itemIndex, dx, dy) ??
        false)) return false;

    final rslot = delegate.reorderModel?.onReorderFeedback
        .call(itemIndex, itemIndex, childOffset, 0.0, 0.0);

    _reorderLayoutData =
        _ReorderLayoutData(constraints, childOffset, dx, dy, itemSize, rslot);

    intervalManager.reorderStart(
        _reorderLayoutData!, interval, offset, itemIndex);

    markSafeNeedsLayout();

    return true;
  }

  // The dragged item has been released, so the reordering can be completed.
  void reorderStop(bool cancel) {
    if (!isReordering) return null;

    final pickedListIndex = _reorderLayoutData!.pickedListIndex;
    final dropListIndex = _reorderLayoutData!.dropListIndex;

    final delegate = childManager.widget.delegate;
    cancel = cancel ||
        !(delegate.reorderModel?.onReorderComplete.call(
                pickedListIndex, dropListIndex, _reorderLayoutData!.slot) ??
            false);

    intervalManager.reorderStop(cancel);

    markSafeNeedsLayout();

    _reorderLayoutData = null;
  }

  void reorderUpdate(double dx, double dy) {
    if (!isReordering) return;

    _reorderLayoutData!.update(constraints, dx, dy);

    final pickedListIndex = _reorderLayoutData!.pickedListIndex;
    final dropListIndex = _reorderLayoutData!.dropListIndex;

    final delegate = childManager.widget.delegate;
    final newSlot = delegate.reorderModel?.onReorderFeedback.call(
        pickedListIndex,
        dropListIndex,
        _reorderLayoutData!.currentMainAxisOffset,
        _reorderLayoutData!.crossAxisDelta,
        _reorderLayoutData!.mainAxisLocalOffset);

    intervalManager.reorderUpdateSlot(newSlot);

    markSafeNeedsLayout();
  }

  // Updates the layout offset of the dragged item.
  // Also schedules the calculation of the new drop position.
  // Finally, it considers wheter to trigger a scroling of the list because
  // the dragged item has been moved the the top or bottom of it.
  void _reorderPerformLayout() {
    if (!isReordering) return;

    _reorderLayoutData!
        .updateCurrentOffset(constraints, geometry!.maxPaintExtent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reorderComputeNewOffset();
    });

    // scroll up/down as needed while dragging
    var controller = Scrollable.of(childManager)?.widget.controller;
    if (controller != null) {
      final position = controller.position;
      final delta = _reorderLayoutData!.computeScrollDelta(
          constraints, controller.position, _reorderLayoutData!.itemSize);
      if (delta != 0.0) {
        final value = position.pixels + delta;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.jumpTo(value);
          markNeedsLayout();
        });
      }
    }
  }

  // Compute whether the dragged item has been moved up or down by comparing the new position with the old one.
  void _reorderComputeNewOffset() {
    if (!isReordering) return;
    final dir = _reorderLayoutData!.updateMainAxisOffset();
    if (dir == 1) {
      _reorderMoveDownwards();
    } else if (dir == -1) {
      _reorderMoveUpwards();
    }
  }

  // Calculates the new drop position of the item moved down.
  void _reorderMoveDownwards() {
    final draggedChildBottom = _reorderLayoutData!.currentMainAxisOffset +
        _reorderLayoutData!.itemSize;

    RenderBox? child;
    for (child = lastChild; child != null; child = childBefore(child)) {
      final childParentData = parentDataOf(child)!;
      final childGoalLine =
          childParentData.layoutOffset! + childSize(child) * 0.75;

      if (draggedChildBottom > childGoalLine) {
        final buildIndex = childParentData.index!;
        final interval = intervalManager.list.intervalAtBuildIndex(buildIndex);
        if (interval is _NormalInterval) {
          _reorderChangeDropIndex(interval, buildIndex + 1);
          return;
        }
      }
    }
  }

  // Calculates the new drop position of the item moved up.
  void _reorderMoveUpwards() {
    final draggedChildTop = _reorderLayoutData!.currentMainAxisOffset;

    RenderBox? child;
    for (child = firstChild; child != null; child = childAfter(child)) {
      final childParentData = parentDataOf(child)!;
      final childGoalLine =
          childParentData.layoutOffset! + childSize(child) * 0.25;

      if (draggedChildTop < childGoalLine) {
        final buildIndex = childParentData.index!;
        final interval = intervalManager.list.intervalAtBuildIndex(buildIndex);
        if (interval is _NormalInterval) {
          _reorderChangeDropIndex(interval, buildIndex);
          return;
        }
      }
    }
  }

  /// Calls the [AnimatedListBaseReorderModel.onReorderMove] callback to find out if the
  /// new drop position is allowed.
  /// If so, the intervals are updated accordingly.
  void _reorderChangeDropIndex(_NormalInterval interval, int buildIndex) {
    final offset = buildIndex - interval.buildOffset;

    final pickedListIndex = _reorderLayoutData!.pickedListIndex;
    var dropListIndex = interval.itemOffset + offset;
    if (pickedListIndex < dropListIndex) dropListIndex--;

    // print('_reorderChangeDropIndex($pickedListIndex, $dropListIndex)');
    final delegate = childManager.widget.delegate;
    if (dropListIndex == _reorderLayoutData!.dropListIndex ||
        !(delegate.reorderModel?.onReorderMove
                .call(pickedListIndex, dropListIndex) ??
            false)) {
      return;
    }

    intervalManager.reorderUpdateDropListIndex(interval, offset, dropListIndex);

    markSafeNeedsLayout();
  }
}

class _ReorderLayoutData {
  var mainAxisLocalOffset = 0.0;
  var crossAxisLocalOffset = 0.0;

  var originMainAxisOffset = 0.0;
  var originCrossAxisOffset = 0.0;

  var originScrollOffset = 0.0;

  var lastMainAxisOffset = 0.0;

  var itemSize = 0.0;

  Object? slot;

  late _ReorderOpeningInterval openingInterval;

  _ReorderLayoutData(SliverConstraints constraints, double layoutOffset,
      double dx, double dy, double itemSize, Object? slot) {
    update(constraints, dx, dy);

    originCrossAxisOffset = crossAxisLocalOffset;

    originScrollOffset = constraints.scrollOffset;

    lastMainAxisOffset = layoutOffset;
    originMainAxisOffset = layoutOffset - mainAxisLocalOffset;

    this.itemSize = itemSize;
    this.slot = slot;
  }

  double get currentMainAxisOffset => popUpList!.currentScrollOffset!;

  set currentMainAxisOffset(double v) => popUpList!.currentScrollOffset = v;

  _ReorderPopUpList? get popUpList => openingInterval.popUpList;

  int get pickedListIndex => openingInterval.holder.itemOffset;

  int get dropListIndex {
    var offset = openingInterval.itemOffset;
    if (pickedListIndex < offset) offset--;
    return offset;
  }

  double get crossAxisDelta => crossAxisLocalOffset - originCrossAxisOffset;

  void update(SliverConstraints constraints, double dx, double dy) {
    switch (applyGrowthDirectionToAxisDirection(
        constraints.axisDirection, constraints.growthDirection)) {
      case AxisDirection.up:
        crossAxisLocalOffset = dx;
        mainAxisLocalOffset = -dy;
        break;
      case AxisDirection.right:
        mainAxisLocalOffset = dx;
        crossAxisLocalOffset = dy;
        break;
      case AxisDirection.down:
        crossAxisLocalOffset = dx;
        mainAxisLocalOffset = dy;
        break;
      case AxisDirection.left:
        mainAxisLocalOffset = -dx;
        crossAxisLocalOffset = dy;
        break;
    }
  }

  int updateMainAxisOffset() {
    final current = currentMainAxisOffset;
    if ((current - lastMainAxisOffset).abs() > 1E-3) {
      if (current > lastMainAxisOffset) {
        lastMainAxisOffset = current;
        return 1;
      } else {
        lastMainAxisOffset = current;
        return -1;
      }
    }
    return 0;
  }

  void updateCurrentOffset(
      SliverConstraints constraints, double maxPaintExtent) {
    currentMainAxisOffset = (originMainAxisOffset +
            mainAxisLocalOffset +
            (constraints.scrollOffset - originScrollOffset))
        .clamp(0.0, maxPaintExtent - itemSize);
  }

  double computeScrollDelta(
      SliverConstraints constraints, ScrollPosition position, double itemSize) {
    var fromOffset = constraints.scrollOffset;
    var toOffset = fromOffset + constraints.remainingPaintExtent;
    if (currentMainAxisOffset < fromOffset && position.extentBefore > 0.0) {
      return -_kReorderingScrollSpeed;
    } else if (currentMainAxisOffset + itemSize > toOffset &&
        position.extentAfter > 0.0) {
      return _kReorderingScrollSpeed;
    }
    return 0.0;
  }
}

// ------------------------
// AnimatedRenderSliverList
// ------------------------

/// This class extends the original [RenderSliverList] to add support for animations and
/// reordering feature to a list of variabile-size items.
class AnimatedRenderSliverList extends AnimatedRenderSliverMultiBoxAdaptor {
  AnimatedRenderSliverList(AnimatedSliverList widget,
      AnimatedSliverMultiBoxAdaptorElement childManager)
      : super(childManager) {
    init();
  }

  @override
  void _performLayout(_PopUpList? popUpList) {
    final constraints = this.constraints;
    childManager.didStartLayout(popUpList);
    if (popUpList == null) childManager.setDidUnderflow(false);

    final scrollOffset = constraints.scrollOffset + constraints.cacheOrigin;
    assert(scrollOffset >= 0.0);

    final remainingExtent = constraints.remainingCacheExtent;
    assert(remainingExtent >= 0.0);

    final targetEndScrollOffset = scrollOffset + remainingExtent;

    final childConstraints = constraints.asBoxConstraints();

    var leadingGarbage = 0;
    var trailingGarbage = 0;
    var reachedEnd = false;

    // This algorithm in principle is straight-forward: find the first child
    // that overlaps the given scrollOffset, creating more children at the top
    // of the list if necessary, then walk down the list updating and laying out
    // each child and adding more at the end if necessary until we have enough
    // children to cover the entire viewport.
    //
    // It is complicated by one minor issue, which is that any time you update
    // or create a child, it's possible that the some of the children that
    // haven't yet been laid out will be removed, leaving the list in an
    // inconsistent state, and requiring that missing nodes be recreated.
    //
    // To keep this mess tractable, this algorithm starts from what is currently
    // the first child, if any, and then walks up and/or down from there, so
    // that the nodes that might get removed are always at the edges of what has
    // already been laid out.

    var list = listOf(popUpList, true)!;

    // Make sure we have at least one child to start from.
    if (list.firstChild == null) {
      if (!addInitialChild(popUpList: popUpList)) {
        // There are no children.
        if (popUpList == null) {
          geometry = SliverGeometry.zero;
        }
        childManager.didFinishLayout(popUpList);
        return;
      }
    }

    // We have at least one child.

    // These variables track the range of children that we have laid out. Within
    // this range, the children have consecutive indices. Outside this range,
    // it's possible for a child to get removed without notice.
    RenderBox? leadingChildWithLayout, trailingChildWithLayout;

    var earliestUsefulChild = list.firstChild;

    // *** rimuove tutti i null in cima alla lista
    // A firstChild with null layout offset is likely a result of children
    // reordering.
    //
    // We rely on firstChild to have accurate layout offset. In the case of null
    // layout offset, we have to find the first child that has valid layout
    // offset.
    if ((list.firstChild != null) &&
        childScrollOffset(list.firstChild!) == null) {
      var leadingChildrenWithoutLayoutOffset = 0;
      while (earliestUsefulChild != null &&
          childScrollOffset(earliestUsefulChild) == null) {
        earliestUsefulChild = childAfter(earliestUsefulChild);
        leadingChildrenWithoutLayoutOffset += 1;
      }
      // We should be able to destroy children with null layout offset safely,
      // because they are likely outside of viewport
      collectGarbage(popUpList, leadingChildrenWithoutLayoutOffset, 0);
      // If can not find a valid layout offset, start from the initial child.
      // if (popUpList == null) {

      if (list.firstChild == null) {
        // era tutti null? lista vuota?
        if (!addInitialChild(popUpList: popUpList)) {
          // There are no children.
          if (popUpList == null) {
            geometry = SliverGeometry.zero;
          }
          childManager.didFinishLayout(popUpList);
          return;
        }
        // }
      }
    }

    //

    // Find the last child that is at or before the scrollOffset.
    earliestUsefulChild = list.firstChild; // di sicuro non ha scrollOffset null
    double earliestScrollOffset;
    // if (popUpList != null && earliestUsefulChild == null) {
    //   earliestScrollOffset = popUpList.currentScrollOffset!;
    // } else {
    earliestScrollOffset = childScrollOffset(earliestUsefulChild!)!;
    // }
    for (;
        earliestScrollOffset > scrollOffset;
        earliestScrollOffset = childScrollOffset(earliestUsefulChild)!) {
      // *** aggiungi i figli in alto al primo della lista, che di sicuro ha un layout
      // We have to add children before the earliestUsefulChild.
      earliestUsefulChild = insertAndLayoutLeadingChild(
          popUpList, childConstraints,
          parentUsesSize: true);
      if (earliestUsefulChild == null) {
        // *** caso in cui non ci sono più figli da aggiungere al di sopra!
        // non ci sono più figli da aggiungere al di sopra!
        final childParentData = list.firstChild!.parentData!
            as MultiSliverMultiBoxAdaptorParentData;
        childParentData.layoutOffset = 0.0;

        if (scrollOffset == 0.0 || popUpList != null) {
          // insertAndLayoutLeadingChild only lays out the children before
          // firstChild. In this case, nothing has been laid out. We have
          // to lay out firstChild manually.
          list.firstChild!.layout(childConstraints, parentUsesSize: true);
          earliestUsefulChild = list.firstChild;
          leadingChildWithLayout = earliestUsefulChild;
          trailingChildWithLayout ??= earliestUsefulChild;
          break;
        } else {
          // We ran out of children before reaching the scroll offset.
          // We must inform our parent that this sliver cannot fulfill
          // its contract and that we need a scroll offset correction.
          assert(popUpList == null);
          geometry = SliverGeometry(
            scrollOffsetCorrection: -scrollOffset,
          );

          return;
        }
      } // if (earliestUsefulChild == null) (caso in cui non ci sono più figli)

      final firstChildScrollOffset =
          earliestScrollOffset - paintExtentOf(list.firstChild!);
      // firstChildScrollOffset may contain double precision error
      if (firstChildScrollOffset < -precisionErrorTolerance) {
        // Let's assume there is no child before the first child. We will
        // correct it on the next layout if it is not.
        if (popUpList == null) {
          geometry = SliverGeometry(
            scrollOffsetCorrection: -firstChildScrollOffset,
          );
        }
        final childParentData = list.firstChild!.parentData!
            as MultiSliverMultiBoxAdaptorParentData;
        childParentData.layoutOffset = 0.0;
        return;
      }

      final childParentData = earliestUsefulChild.parentData!
          as MultiSliverMultiBoxAdaptorParentData;
      childParentData.layoutOffset = firstChildScrollOffset;
      assert(earliestUsefulChild == list.firstChild);
      leadingChildWithLayout = earliestUsefulChild;
      trailingChildWithLayout ??= earliestUsefulChild;
    } // for

    //

    if (popUpList == null) {
      assert(childScrollOffset(list.firstChild!)! > -precisionErrorTolerance);
    }

    // If the scroll offset is at zero, we should make sure we are
    // actually at the beginning of the list.
    if (scrollOffset < precisionErrorTolerance && popUpList == null) {
      // We iterate from the firstChild in case the leading child has a 0 paint
      // extent.
      while (indexOf(list.firstChild!) > 0) {
        final earliestScrollOffset = childScrollOffset(list.firstChild!)!;
        // We correct one child at a time. If there are more children before
        // the earliestUsefulChild, we will correct it once the scroll offset
        // reaches zero again.
        earliestUsefulChild = insertAndLayoutLeadingChild(
            popUpList, childConstraints,
            parentUsesSize: true);
        assert(earliestUsefulChild != null);
        final firstChildScrollOffset =
            earliestScrollOffset - paintExtentOf(list.firstChild!);
        final childParentData = list.firstChild!.parentData!
            as MultiSliverMultiBoxAdaptorParentData;
        childParentData.layoutOffset = 0.0;
        // We only need to correct if the leading child actually has a
        // paint extent.
        // if (popUpList == null) {
        if (firstChildScrollOffset < -precisionErrorTolerance) {
          geometry = SliverGeometry(
            scrollOffsetCorrection: -firstChildScrollOffset,
          );
          return;
        }
        // }
      }
    }

    //

    // At this point, earliestUsefulChild is the first child, and is a child
    // whose scrollOffset is at or before the scrollOffset, and
    // leadingChildWithLayout and trailingChildWithLayout are either null or
    // cover a range of render boxes that we have laid out with the first being
    // the same as earliestUsefulChild and the last being either at or after the
    // scroll offset.

    assert(earliestUsefulChild == list.firstChild);
    assert(popUpList != null ||
        childScrollOffset(earliestUsefulChild!)! <= scrollOffset);

    // Make sure we've laid out at least one child.
    // if (popUpList == null) {
    if (leadingChildWithLayout == null) {
      earliestUsefulChild!.layout(childConstraints, parentUsesSize: true);
      leadingChildWithLayout = earliestUsefulChild;
      trailingChildWithLayout = earliestUsefulChild;
    }
    // }

    // Here, earliestUsefulChild is still the first child, it's got a
    // scrollOffset that is at or before our actual scrollOffset, and it has
    // been laid out, and is in fact our leadingChildWithLayout. It's possible
    // that some children beyond that one have also been laid out.

    var inLayoutRange = true;
    var child = earliestUsefulChild;
    var index = indexOf(child!);
    var endScrollOffset = childScrollOffset(child)! + paintExtentOf(child);
    bool advance() {
      // returns true if we advanced, false if we have no more children
      // This function is used in two different places below, to avoid code duplication.
      assert(child != null);
      if (child == trailingChildWithLayout) {
        inLayoutRange = false;
      }
      child = childAfter(child!);
      if (child == null) {
        inLayoutRange = false;
      }
      index += 1;
      if (!inLayoutRange) {
        if (child == null || indexOf(child!) != index) {
          // We are missing a child. Insert it (and lay it out) if possible.
          // *** aggiunge un nuovo figlio in basso
          child = insertAndLayoutChild(
            popUpList,
            childConstraints,
            after: trailingChildWithLayout,
            parentUsesSize: true,
          );
          if (child == null) {
            // We have run out of children.
            return false;
          }
        } else {
          // Lay out the child.
          child!.layout(childConstraints, parentUsesSize: true);
        }
        trailingChildWithLayout = child;
      }
      assert(child != null);
      final childParentData =
          child!.parentData! as MultiSliverMultiBoxAdaptorParentData;
      childParentData.layoutOffset =
          endScrollOffset - (popUpList?.currentScrollOffset ?? 0.0);
      assert(childParentData.index == index);
      endScrollOffset = childScrollOffset(child!)! + paintExtentOf(child!);
      return true;
    } // advance()

    // *** caso in cui avevo già da prima altri figli sopra lo scrollOffset, vanno rimossi quelli fuori dalla viewport
    // Find the first child that ends after the scroll offset.
    while (endScrollOffset < scrollOffset) {
      leadingGarbage += 1;
      if (!advance()) {
        // *** caso in cui erano tutti sopra la viewport
        assert(leadingGarbage == list.childCount);
        assert(child == null);
        // we want to make sure we keep the last child around so we know the end scroll offset
        collectGarbage(popUpList, leadingGarbage - 1, 0);
        assert(list.firstChild == list.lastChild);
        if (popUpList == null) {
          final extent = childScrollOffset(list.lastChild!)! +
              paintExtentOf(list.lastChild!);
          geometry = SliverGeometry(
            scrollExtent: extent,
            maxPaintExtent: extent,
          );
        }
        return;
      }
    }

    // Now find the first child that ends after our end.
    while (endScrollOffset < targetEndScrollOffset) {
      if (!advance()) {
        reachedEnd = true;
        break;
      }
    }

    // Finally count up all the remaining children and label them as garbage.
    if (child != null) {
      child = childAfter(child!);
      while (child != null) {
        trailingGarbage += 1;
        child = childAfter(child!);
      }
    }

    // At this point everything should be good to go, we just have to clean up
    // the garbage and report the geometry.

    collectGarbage(popUpList, leadingGarbage, trailingGarbage);

    if (popUpList == null) {
      assert(debugAssertChildListIsNonEmptyAndContiguous(popUpList));
      final double estimatedMaxScrollOffset;
      if (reachedEnd) {
        estimatedMaxScrollOffset = endScrollOffset;
      } else {
        estimatedMaxScrollOffset = childManager.estimateMaxScrollOffset(
          constraints,
          firstIndex: indexOf(list.firstChild!),
          lastIndex: indexOf(list.lastChild!),
          leadingScrollOffset: childScrollOffset(list.firstChild!),
          trailingScrollOffset: endScrollOffset,
        );
        assert(estimatedMaxScrollOffset >=
            endScrollOffset - childScrollOffset(list.firstChild!)!);
      }
      final paintExtent = calculatePaintOffset(
        constraints,
        from: childScrollOffset(list.firstChild!)!,
        to: endScrollOffset,
      );
      final cacheExtent = calculateCacheOffset(
        constraints,
        from: childScrollOffset(list.firstChild!)!,
        to: endScrollOffset,
      );
      final targetEndScrollOffsetForPaint =
          constraints.scrollOffset + constraints.remainingPaintExtent;
      geometry = SliverGeometry(
        scrollExtent: estimatedMaxScrollOffset,
        paintExtent: paintExtent,
        cacheExtent: cacheExtent,
        maxPaintExtent: estimatedMaxScrollOffset,
        // Conservative to avoid flickering away the clip during scroll.
        hasVisualOverflow: endScrollOffset > targetEndScrollOffsetForPaint ||
            constraints.scrollOffset > 0.0,
      );

      // We may have started the layout while scrolled to the end, which would not
      // expose a new child.
      if (estimatedMaxScrollOffset == endScrollOffset) {
        childManager.setDidUnderflow(true);
      }
    }
    childManager.didFinishLayout(popUpList);
  }

  @override
  AnimatedSliverMultiBoxAdaptorElement get childManager =>
      super.childManager as AnimatedSliverMultiBoxAdaptorElement;

  // Measures the size of a bunch of off-list children.
  // If the calculated size exceedes the remaining cache extent of the list view,
  // an estimate will be returned.
  @override
  Future<_Measure> measureItems(
      _Cancelled? cancelled,
      int count,
      IndexedWidgetBuilder builder,
      double startingSize,
      int startingCount) async {
    assert(count > 0);
    final maxSize = constraints.remainingCacheExtent;
    assert(maxSize >= 0.0);
    var size = startingSize;
    int i;
    for (i = startingCount; i < count; i++) {
      if (size >= maxSize) break;
      await Future.delayed(Duration(milliseconds: 0), () {
        if (cancelled?.value ?? false) return _Measure.zero;
        size += measureItem(
            builder.call(childManager, i - startingCount), childConstraints);
      });
      if (cancelled?.value ?? false) return _Measure.zero;
    }
    if (i < count) size *= (count / i);
    return _Measure(size, i < count);
  }

  /// Measures the size of a single widget.
  @override
  double measureItem(Widget widget, [BoxConstraints? childConstraints]) {
    late double size;
    childManager.disposableElement(widget, (renderBox) {
      renderBox.layout(childConstraints ?? this.childConstraints,
          parentUsesSize: true);
      size = childSize(renderBox);
    });
    return size;
  }

  /// Estimates the max scroll offset based on the rendered viewport data.
  @override
  double? extrapolateMaxScrollOffset(
    final int firstIndex,
    final int lastIndex,
    final double leadingScrollOffset,
    final double trailingScrollOffset,
    final int childCount,
  ) {
    assert(!intervalManager.hasPendingUpdates);

    if (lastIndex == childCount - 1) {
      return trailingScrollOffset;
    }

    var averageTrailingCount = 0.0;
    var innerCount = 0, trailingCount = 0, leadingCount = 0;
    var buildIndex = 0;
    var averageInnerCount = 0.0;
    for (final interval in intervalManager.list) {
      if (interval is _SpaceInterval) {
        if (firstIndex <= buildIndex) {
          if (buildIndex <= lastIndex) {
            // resizing intervals inside the viewport
            innerCount++;
            averageInnerCount += interval.averageCount;
          } else {
            // resizing intervals outside/after the viewport
            trailingCount++;
            averageTrailingCount += interval.averageCount;
          }
        } else {
          leadingCount++;
          averageInnerCount += interval.averageCount;
        }
      }
      buildIndex += interval.buildCount;
    }

    var ret = trailingScrollOffset;

    // # items outside/after the viewport, excluding resizing intervals
    final remainingCount = childCount - lastIndex - trailingCount - 1;
    if (remainingCount > 0) {
      final averageExtent = trailingScrollOffset /
          (1 + lastIndex - innerCount - leadingCount + averageInnerCount);
      ret += averageExtent * (remainingCount + averageTrailingCount);
    }

    return ret;
  }

  @override
  Rect? computeItemBox(int itemIndex, bool absolute, bool avoidMeasuring) {
    if (intervalManager.hasPendingUpdates) return null;

    final interval = intervalManager.list.intervalAtItemIndex(itemIndex);
    if (interval is! _NormalInterval && interval is! _ReadyToChangingInterval) {
      return null;
    }
    var buildIndex = interval.buildOffset + (itemIndex - interval.itemOffset);

    assert(!intervalManager.hasPendingUpdates);
    if (buildIndex < 0 || buildIndex >= intervalManager.list.buildCount) {
      return null;
    }
    var r = 0.0;
    var s = 0.0;
    if (firstChild == null) {
      if (avoidMeasuring) return null;
      for (var i = 0; i < buildIndex; i++) {
        final widget = childManager.build(i, measureOnly: true);
        if (widget == null) return null;
        r += measureItem(widget);
      }
      final widget = childManager.build(buildIndex, measureOnly: true);
      if (widget == null) return null;
      s = measureItem(widget);
    } else {
      s = childSize(firstChild!);
      final parentData = parentDataOf(firstChild)!;
      var i = parentData.index!;
      r = parentData.layoutOffset!;
      if (buildIndex <= i) {
        if (avoidMeasuring && buildIndex < i) return null;
        while (buildIndex < i) {
          final widget = childManager.build(--i, measureOnly: true);
          if (widget == null) return null;
          s = measureItem(widget);
          r -= s;
        }
      } else {
        var child = firstChild;
        while (buildIndex > i) {
          final nextChild = childAfter(child!);
          if (nextChild == null) break;
          final parentData = parentDataOf(nextChild)!;
          if (parentData.layoutOffset == null) break;
          child = nextChild;
          i = parentData.index!;
          r = parentData.layoutOffset!;
        }
        s = childSize(child!);
        if (buildIndex > i) {
          if (avoidMeasuring) return null;
          i++;
          r += s;
          while (buildIndex > i) {
            final widget = childManager.build(i++, measureOnly: true);
            if (widget == null) return null;
            r += measureItem(widget);
          }
          final widget = childManager.build(buildIndex, measureOnly: true);
          if (widget == null) return null;
          s = measureItem(widget);
        }
      }
    }
    if (absolute) {
      r += constraints.precedingScrollExtent;
    }
    switch (constraints.axis) {
      case Axis.horizontal:
        return Rect.fromLTWH(r, 0, s, constraints.crossAxisExtent);
      case Axis.vertical:
        return Rect.fromLTWH(0, r, constraints.crossAxisExtent, s);
    }
  }

  @override
  BoxConstraints get childConstraints => constraints.asBoxConstraints();
}

// -----------------------------------
// AnimatedRenderSliverFixedExtentList
// -----------------------------------

/// This class extends the original [RenderSliverFixedExtentList] to add support for
/// animations and reordering feature to a list of fixed-extent items.
class AnimatedRenderSliverFixedExtentList
    extends AnimatedRenderSliverMultiBoxAdaptor {
  AnimatedRenderSliverFixedExtentList({
    required AnimatedSliverMultiBoxAdaptorElement childManager,
    required double itemExtent,
    required AnimatedSliverFixedExtentList widget,
  })  : _itemExtent = itemExtent,
        super(childManager) {
    init();
  }

  // @override
  double get itemExtent => _itemExtent;
  double _itemExtent;
  set itemExtent(double value) {
    if (_itemExtent == value) {
      return;
    }
    _itemExtent = value;
    markNeedsLayout();
  }

  @override
  AnimatedSliverMultiBoxAdaptorElement get childManager =>
      super.childManager as AnimatedSliverMultiBoxAdaptorElement;

  @override
  Future<_Measure> measureItems(
          _Cancelled? cancelled,
          int count,
          IndexedWidgetBuilder builder,
          double startingSize,
          int startingCount) async =>
      (itemExtent * (count + startingCount)).toExactMeasure();

  @override
  double measureItem(Widget widget, [BoxConstraints? childConstraints]) =>
      itemExtent;

  @override
  void resizingIntervalUpdated(_AnimatedSpaceInterval interval, double delta) {
    super.resizingIntervalUpdated(interval, delta);
    markSafeNeedsLayout();
  }

  @override
  _SizeResult? getItemSizesFromSliverList(int buildFrom, int buildTo) =>
      _SizeResult(buildFrom, buildTo, (buildTo - buildFrom) * itemExtent);

  @override
  double? extrapolateMaxScrollOffset(
    final int firstIndex,
    final int lastIndex,
    final double leadingScrollOffset,
    final double trailingScrollOffset,
    final int childCount,
  ) {
    assert(!intervalManager.hasPendingUpdates);

    if (lastIndex == childCount - 1) return trailingScrollOffset;

    var trailingSpace = 0.0;
    var trailingCount = 0;
    var buildIndex = 0;
    for (final interval in intervalManager.list) {
      if (interval is _SpaceInterval) {
        final si = interval;
        if (firstIndex <= buildIndex) {
          if (buildIndex > lastIndex) {
            trailingCount++;
            trailingSpace += si.currentSize;
          }
        }
      }
      buildIndex += interval.buildCount;
    }

    var ret = trailingScrollOffset + trailingSpace;

    final remainingCount = childCount - lastIndex - trailingCount - 1;
    if (remainingCount > 0) {
      ret += itemExtent * remainingCount;
    }

    return ret;
  }

  double indexToLayoutOffset(
      Iterable<_Interval> list, double itemExtent, int index) {
    var bi = 0, n = 0;
    var sz = 0.0;
    for (final interval in list) {
      if (index <= bi) break;
      if (interval is _SpaceInterval) {
        sz += interval.currentSize;
        n++;
      }
      bi += interval.buildCount;
    }
    return sz + itemExtent * (index - n);
  }

  double computeMaxScrollOffset(
      SliverConstraints constraints, double itemExtent) {
    var count = childManager.childCount;
    var sz = 0.0;
    for (final interval in intervalManager.list.whereType<_SpaceInterval>()) {
      sz += interval.currentSize;
      count--;
    }
    return sz + itemExtent * count;
  }

  int getMinChildIndexForScrollOffset(
      Iterable<_Interval> list, double scrollOffset, double itemExtent) {
    if (scrollOffset <= 0) return 0;
    var toOffset = 0.0, adjust = 0.0;
    var bi = 0;
    for (final interval in list) {
      if (interval is _SpaceInterval) {
        toOffset += interval.currentSize;
        if (scrollOffset < toOffset) {
          return bi;
        }
        adjust += itemExtent - interval.currentSize;
      } else {
        toOffset += interval.buildCount * itemExtent;
        if (scrollOffset < toOffset) break;
      }
      bi += interval.buildCount;
    }
    scrollOffset += adjust;
    if (itemExtent > 0.0) {
      final actual = scrollOffset / itemExtent;
      final round = actual.round();
      if ((actual * itemExtent - round * itemExtent).abs() <
          precisionErrorTolerance) {
        return round;
      }
      return actual.floor();
    }
    return 0;
  }

  int getMaxChildIndexForScrollOffset(
      Iterable<_Interval> list, double scrollOffset, double itemExtent) {
    var toOffset = 0.0, adjust = 0.0;
    var bi = 0;
    for (final interval in list) {
      if (interval is _SpaceInterval) {
        toOffset += interval.currentSize;
        if (scrollOffset < toOffset) {
          return bi;
        }
        adjust += itemExtent - interval.currentSize;
      } else {
        toOffset += interval.buildCount * itemExtent;
        if (scrollOffset < toOffset) break;
      }
      bi += interval.buildCount;
    }
    scrollOffset += adjust;
    if (itemExtent > 0.0) {
      final actual = scrollOffset / itemExtent - 1;
      final round = actual.round();
      if ((actual * itemExtent - round * itemExtent).abs() <
          precisionErrorTolerance) {
        return math.max(0, round);
      }
      return math.max(0, actual.ceil());
    }
    return 0;
  }

  @override
  void _performLayout(_PopUpList? popUpList) {
    final constraints = this.constraints;
    childManager.didStartLayout(popUpList);
    if (popUpList == null) childManager.setDidUnderflow(false);

    final itemExtent = this.itemExtent;

    final scrollOffset = constraints.scrollOffset + constraints.cacheOrigin;
    assert(scrollOffset >= 0.0);

    final remainingExtent = constraints.remainingCacheExtent;
    assert(remainingExtent >= 0.0);
    final targetEndScrollOffset = scrollOffset + remainingExtent;

    final childConstraints = constraints.asBoxConstraints(
      minExtent: itemExtent,
      maxExtent: itemExtent,
    );

    final list = listOf(popUpList, true)!;
    final ilist = popUpList?.intervals ?? intervalManager.list;
    final lo = popUpList?.currentScrollOffset ?? 0;
    final childCount = ilist.buildCount;

    final firstIndex =
        getMinChildIndexForScrollOffset(ilist, scrollOffset - lo, itemExtent);
    assert(targetEndScrollOffset.isFinite);
    var targetLastIndex = //targetEndScrollOffset.isFinite
        //?
        getMaxChildIndexForScrollOffset(
            ilist, targetEndScrollOffset - lo, itemExtent);
    //: null;
    if (targetLastIndex >= childCount) {
      targetLastIndex = childCount - 1;
    }

    if (list.firstChild != null) {
      final leadingGarbage = _calculateLeadingGarbage(list, firstIndex);
      final trailingGarbage = //targetLastIndex != null
          // ?
          _calculateTrailingGarbage(list, targetLastIndex);
      // : 0;
      collectGarbage(popUpList, leadingGarbage, trailingGarbage);
    } else {
      collectGarbage(popUpList, 0, 0);
    }

    if (firstIndex >= childCount && popUpList != null) {
      childManager.didFinishLayout(popUpList);
      return;
    }

    if (list.firstChild == null) {
      if (!addInitialChild(
          popUpList: popUpList,
          index: firstIndex,
          layoutOffset: indexToLayoutOffset(ilist, itemExtent, firstIndex))) {
        // There are either no children, or we are past the end of all our children.
        if (popUpList == null) {
          final double max;
          if (firstIndex <= 0) {
            max = 0.0;
          } else {
            max = computeMaxScrollOffset(constraints, itemExtent);
          }
          geometry = SliverGeometry(
            scrollExtent: max,
            maxPaintExtent: max,
          );
        }
        childManager.didFinishLayout(popUpList);
        return;
      }
    }

    RenderBox? trailingChildWithLayout;

    for (var index = indexOf(list.firstChild!) - 1;
        index >= firstIndex;
        --index) {
      final child = insertAndLayoutLeadingChild(popUpList, childConstraints,
          parentUsesSize: true);
      if (child == null) {
        // Items before the previously first child are no longer present.
        // Reset the scroll offset to offset all items prior and up to the
        // missing item. Let parent re-layout everything.

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        // geometry = SliverGeometry(scrollOffsetCorrection: index * itemExtent);
        if (popUpList == null) {
          geometry = SliverGeometry(
              scrollOffsetCorrection:
                  indexToLayoutOffset(ilist, itemExtent, index));
        }
//++++++++++++++++++++++ì+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        return;
      }
      final childParentData =
          child.parentData! as MultiSliverMultiBoxAdaptorParentData;
      childParentData.layoutOffset =
          indexToLayoutOffset(ilist, itemExtent, index);
      assert(childParentData.index == index);
      trailingChildWithLayout ??= child;
    }

    if (trailingChildWithLayout == null) {
      list.firstChild!.layout(childConstraints, parentUsesSize: true);
      final childParentData =
          list.firstChild!.parentData! as MultiSliverMultiBoxAdaptorParentData;
      childParentData.layoutOffset =
          indexToLayoutOffset(ilist, itemExtent, firstIndex);
      trailingChildWithLayout = list.firstChild;
    }

    var estimatedMaxScrollOffset = double.infinity;
    for (var index = indexOf(trailingChildWithLayout!) + 1;
        // targetLastIndex == null ||
        index <= targetLastIndex;
        ++index) {
      var child = childAfter(trailingChildWithLayout!);
      if (child == null || indexOf(child) != index) {
        child = insertAndLayoutChild(popUpList, childConstraints,
            after: trailingChildWithLayout, parentUsesSize: true);
        if (child == null) {
          // We have run out of children.
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
          // estimatedMaxScrollOffset = index * itemExtent;
          if (popUpList == null) {
            estimatedMaxScrollOffset =
                indexToLayoutOffset(ilist, itemExtent, index);
          }
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
          break;
        }
      } else {
        child.layout(childConstraints, parentUsesSize: true);
      }
      trailingChildWithLayout = child;
      // assert(child != null);
      final childParentData =
          child.parentData! as MultiSliverMultiBoxAdaptorParentData;
      assert(childParentData.index == index);
      childParentData.layoutOffset =
          indexToLayoutOffset(ilist, itemExtent, childParentData.index!);
    }

    if (popUpList == null) {
      final lastIndex = indexOf(list.lastChild!);
      final leadingScrollOffset =
          indexToLayoutOffset(ilist, itemExtent, firstIndex);
      final trailingScrollOffset =
          indexToLayoutOffset(ilist, itemExtent, lastIndex + 1);

      assert(firstIndex == 0 ||
          childScrollOffset(list.firstChild!)! - scrollOffset <=
              precisionErrorTolerance);
      assert(debugAssertChildListIsNonEmptyAndContiguous(popUpList));
      assert(indexOf(list.firstChild!) == firstIndex);
      assert(//targetLastIndex == null ||
          lastIndex <= targetLastIndex);

      estimatedMaxScrollOffset = math.min(
        estimatedMaxScrollOffset,
        childManager.estimateMaxScrollOffset(
          constraints,
          firstIndex: firstIndex,
          lastIndex: lastIndex,
          leadingScrollOffset: leadingScrollOffset,
          trailingScrollOffset: trailingScrollOffset,
        ),
      );

      final paintExtent = calculatePaintOffset(
        constraints,
        from: leadingScrollOffset,
        to: trailingScrollOffset,
      );

      final cacheExtent = calculateCacheOffset(
        constraints,
        from: leadingScrollOffset,
        to: trailingScrollOffset,
      );

      final targetEndScrollOffsetForPaint =
          constraints.scrollOffset + constraints.remainingPaintExtent;
      final targetLastIndexForPaint = targetEndScrollOffsetForPaint.isFinite
          ? getMaxChildIndexForScrollOffset(
              ilist, targetEndScrollOffsetForPaint, itemExtent)
          : null;
      geometry = SliverGeometry(
        scrollExtent: estimatedMaxScrollOffset,
        paintExtent: paintExtent,
        cacheExtent: cacheExtent,
        maxPaintExtent: estimatedMaxScrollOffset,
        // Conservative to avoid flickering away the clip during scroll.
        hasVisualOverflow: (targetLastIndexForPaint != null &&
                lastIndex >= targetLastIndexForPaint) ||
            constraints.scrollOffset > 0.0,
      );

      // We may have started the layout while scrolled to the end, which would not
      // expose a new child.
      if (estimatedMaxScrollOffset == trailingScrollOffset) {
        childManager.setDidUnderflow(true);
      }
    }
    childManager.didFinishLayout(popUpList);
  }

  int _calculateLeadingGarbage(_ChildList list, int firstIndex) {
    var walker = list.firstChild;
    var leadingGarbage = 0;
    while (walker != null && indexOf(walker) < firstIndex) {
      leadingGarbage += 1;
      walker = childAfter(walker);
    }
    return leadingGarbage;
  }

  int _calculateTrailingGarbage(_ChildList list, int targetLastIndex) {
    var walker = list.lastChild;
    var trailingGarbage = 0;
    while (walker != null && indexOf(walker) > targetLastIndex) {
      trailingGarbage += 1;
      walker = childBefore(walker);
    }
    return trailingGarbage;
  }

  @override
  BoxConstraints get childConstraints => constraints.asBoxConstraints(
        minExtent: itemExtent,
        maxExtent: itemExtent,
      );

  @override
  Rect? computeItemBox(int buildIndex, bool absolute, bool _) {
    if (buildIndex < 0 || buildIndex >= intervalManager.list.buildCount) {
      return null;
    }
    var r = itemExtent * buildIndex;
    if (absolute) {
      r += constraints.precedingScrollExtent;
    }
    switch (constraints.axis) {
      case Axis.horizontal:
        return Rect.fromLTWH(r, 0, itemExtent, constraints.crossAxisExtent);
      case Axis.vertical:
        return Rect.fromLTWH(0, r, constraints.crossAxisExtent, itemExtent);
    }
  }
}
