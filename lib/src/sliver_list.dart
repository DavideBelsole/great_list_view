part of 'core.dart';

const _kReorderingScrollSpeed = 10.0;

/// If `true` during perform layout a dummy [ScrollUpdateNotification] is sent
/// to repaint the widget that is listening to it (ie. [Scrollbar]).
bool fixScrollableRepainting = true;

/// This mixin is used by [AnimatedRenderSliverList] and [AnimatedRenderSliverFixedExtentList].
mixin AnimatedRenderSliverMultiBoxAdaptor
    implements RenderSliverMultiBoxAdaptor {
  bool _inPaint = false;
  double _resizeAmountCorrection = 0.0;

  late _IntervalList _intervalList;

  @override
  AnimatedSliverMultiBoxAdaptorElement get childManager;

  void init() {
    _intervalList = _IntervalList(childManager);
  }

  void dispose() {
    _intervalList.dispose();
  }

  /// It returns the sum of the sizes of a bunch of items, builded by the specified builder.
  Future<_Measure> measureItems(
      _Cancelled cancelled, int count, IndexedWidgetBuilder builder);

  /// It returns the size of a single widget.
  double measureItem(Widget widget, [BoxConstraints? childConstraints]);

  /// It calculates an estimate of the maximum scroll offset.
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
  void _resizingIntervalUpdated(_ResizingInterval interval, double delta) {
    assert(delta != 0.0);
    final firstChild = firstChildWithLayout;
    if (firstChild == null) return;
    if (indexOf(firstChild) <= _intervalList.buildItemIndexOf(interval)) return;
    _resizeAmountCorrection += delta;
    markNeedsLayout();
  }

  // Adjusts the layout offset of the first displayed item by the correction amount
  // calcoluted as a result of resizing the intervals above it.
  void _adjustLayout() {
    var amount = _resizeAmountCorrection;
    _resizeAmountCorrection = 0.0;

    final firstChild = firstChildWithLayout;
    if (firstChild != null) {
      final parentData = parentDataOf(firstChild)!;
      final firstLayoutOffset = parentData.layoutOffset!;
      if (firstLayoutOffset + amount < 0.0) {
        amount = -firstLayoutOffset; // bring back first offset to zero
      }
      parentData.layoutOffset = parentData.layoutOffset! + amount;
    }
  }

  /// A `didChangeDependencies` method like in [State.didChangeDependencies],
  /// necessary to update the tickers correctly when the `muted` attribute changes.
  void didChangeDependencies(BuildContext context) {
    _intervalList.updateTickerMuted(context);
  }

  // It returns the first displayed and layouted item.
  RenderBox? get firstChildWithLayout {
    var child = firstChild;
    while (child != null) {
      var offset = childScrollOffset(child);
      if (offset != null) return child;
      child = childAfter(child);
    }
    return null;
  }

  double childSize(RenderBox child) {
    switch (constraints.axis) {
      case Axis.horizontal:
        return child.size.width;
      case Axis.vertical:
        return child.size.height;
    }
  }

  SliverMultiBoxAdaptorParentData? parentDataOf(RenderBox child) =>
      child.parentData as SliverMultiBoxAdaptorParentData?;

  // It dispatches a fake change to the ScrollPosition to force the listeners
  // (ie a Scrollbar) to refresh its state.
  void _notifyScrollable() {
    final scrollable = Scrollable.of(childManager);
    if (scrollable == null) return;
    final position = scrollable.widget.controller?.position;
    if (position == null) return;
    final context = scrollable.context;
    ScrollUpdateNotification(
            metrics: position.copyWith(),
            context: context,
            scrollDelta: 0,
            dragDetails: null)
        .dispatch(context);
  }

  bool _initScrollPosition = true;

  void doPerformLayout(void Function() callback) {
    if (_initScrollPosition) {
      _initScrollPosition = false;
      final callback = childManager.widget.delegate.initialScrollOffsetCallback;
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

    _adjustLayout();

    callback();

    if ((geometry!.scrollOffsetCorrection ?? 0.0) != 0.0) {
      return;
    }

    _reoderPerformLayout();

    if (fixScrollableRepainting) {
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        _notifyScrollable();
      });
    }
  }

  RenderBox? _childAfter(RenderBox child) {
    assert(child.parent == this);
    return parentDataOf(child)?.nextSibling;
  }

  @override
  RenderBox? childAfter(RenderBox child) {
    if (_inPaint && _reorderDraggedRenderBox != null) {
      // the dragged item is the last child
      if (child == _reorderDraggedRenderBox) {
        return null;
      }

      var after = _childAfter(child);
      after ??= _reorderDraggedRenderBox;

      return after;
    }
    return _childAfter(child);
  }

  void doPaint(
      PaintingContext context, Offset offset, void Function() callback) {
    _inPaint = true;
    callback();
    _inPaint = false;
  }

  void doVisitChildren(RenderObjectVisitor visitor, void Function() callback) {
    callback();
    if (_reorderDraggedRenderBox != null) {
      visitor.call(_reorderDraggedRenderBox!);
    }
  }

  // *************************
  //  Reorder Feature Support
  // *************************

  RenderBox? _reorderDraggedRenderBox;
  var _reorderDraggedItemSize = 0.0;

  var _reorderMainAxisLocalOffset = 0.0;
  var _reorderCrossAxisLocalOffset = 0.0;

  var _reorderOriginScrollOffset = 0.0;

  var _reorderOriginMainAxisOffset = 0.0;
  var _reorderOriginCrossAxisOffset = 0.0;

  var _reorderCurrentMainAxisOffset = 0.0;
  var _reorderLastMainAxisOffset = 0.0;

  Object? _slot;

  bool get isReordering => _reorderDraggedRenderBox != null;

  // Initiazes a new reorder.
  // The onReorderStartcallback will be invoked.
  // Returns true if the reorder can be performed.
  // The picked up item will be removed from the children list in order to be painted above all of them.
  bool _reorderStart(BuildContext itemContext, double dx, double dy) {
    if (isReordering) return false;

    var buildIndex = childManager._findBuildIndexFromContext(itemContext);
    if (buildIndex == null) return false;

    final info = _intervalList.intervalAtBuildIndex(buildIndex);
    if (info.interval is! _NormalInterval) return false;

    final itemIndex = info.itemIndex + (buildIndex - info.buildIndex);

    final delegate = childManager.widget.delegate;
    if (!(delegate.reorderModel?.onReorderStart.call(itemIndex, dx, dy) ??
        false)) return false;

    switch (constraints.axis) {
      case Axis.horizontal:
        _reorderMainAxisLocalOffset = dx;
        _reorderCrossAxisLocalOffset = dy;
        break;
      case Axis.vertical:
        _reorderCrossAxisLocalOffset = dx;
        _reorderMainAxisLocalOffset = dy;
        break;
    }

    childManager._pickUpDraggedItem(buildIndex, itemIndex,
        (RenderBox draggedRenderBox, double itemSize) {
      final oldChildParentData =
          draggedRenderBox.parentData! as SliverMultiBoxAdaptorParentData;

      final previousRenderBox = childBefore(draggedRenderBox);

      _reorderDraggedItemSize = itemSize;

      remove(draggedRenderBox);
      adoptChild(draggedRenderBox);

      draggedRenderBox.layout(constraints.asBoxConstraints(),
          parentUsesSize: true);
      final newChildParentData =
          draggedRenderBox.parentData! as SliverMultiBoxAdaptorParentData;
      newChildParentData.layoutOffset = oldChildParentData.layoutOffset;

      _reorderOriginMainAxisOffset =
          newChildParentData.layoutOffset! - _reorderMainAxisLocalOffset;
      _reorderDraggedRenderBox = draggedRenderBox;
      _reorderOriginCrossAxisOffset = _reorderCrossAxisLocalOffset;

      return previousRenderBox;
    });

    _slot = delegate.reorderModel?.onReorderFeedback
        .call(itemIndex, itemIndex, _reorderCurrentMainAxisOffset, 0.0, 0.0);

    _reorderOriginScrollOffset = constraints.scrollOffset;

    _reorderCurrentMainAxisOffset =
        _reorderOriginMainAxisOffset + _reorderMainAxisLocalOffset;
    _reorderLastMainAxisOffset = _reorderOriginMainAxisOffset;

    markNeedsLayout();

    return true;
  }

  // It calls the onReorderFeedback callback.
  // If the slot is changed, the dragged item will be rebuilded.
  void _reorderUpdate(double dx, double dy) {
    if (!isReordering) return;

    switch (constraints.axis) {
      case Axis.horizontal:
        _reorderMainAxisLocalOffset = dx;
        _reorderCrossAxisLocalOffset = dy;
        break;
      case Axis.vertical:
        _reorderCrossAxisLocalOffset = dx;
        _reorderMainAxisLocalOffset = dy;
        break;
    }

    final delegate = childManager.widget.delegate;
    final pickIndex = _intervalList.reorderPickListIndex!;
    final dropIndex = _intervalList.reorderDropListIndex(pickIndex);
    final newSlot = delegate.reorderModel?.onReorderFeedback.call(
        pickIndex,
        dropIndex,
        _reorderCurrentMainAxisOffset,
        _reorderCrossAxisLocalOffset - _reorderOriginCrossAxisOffset,
        _reorderMainAxisLocalOffset);
    if (_slot != newSlot) {
      _slot = newSlot;

      childManager.notifyChangedRange(
          pickIndex,
          1,
          (context, index, data) => childManager.widget.delegate
              .builder(context, _intervalList.reorderPickListIndex!, data),
          0);
    }

    markNeedsLayout();
  }

  // Compute whether the dragged item has been moved up or down by comparing the new position with the old one.
  void _reorderComputeNewOffset() {
    assert(isReordering);
    final current = _reorderCurrentMainAxisOffset;
    if (current != _reorderLastMainAxisOffset) {
      if (current > _reorderLastMainAxisOffset) {
        _reorderMoveDownwards();
      } else {
        _reorderMoveUpwards();
      }
      _reorderLastMainAxisOffset = current;
    }
  }

  // Calculates the new drop position of the item moved down.
  void _reorderMoveDownwards() {
    final draggedBottom =
        _reorderCurrentMainAxisOffset + _reorderDraggedItemSize;

    RenderBox? child;
    _NormalInterval? lastNormalInterval;
    var lastBuildIndex = 0;
    for (child = lastChild; child != null; child = childBefore(child)) {
      final childParentData = parentDataOf(child)!;
      final childBottom =
          childParentData.layoutOffset! + childSize(child) * 0.75;

      if (draggedBottom > childBottom) {
        final buildIndex = childParentData.index!;
        final intervalData = _intervalList.intervalAtBuildIndex(buildIndex);
        if (intervalData.interval is _NormalInterval) {
          lastNormalInterval = intervalData.interval as _NormalInterval;
          lastBuildIndex = buildIndex;
          _changeDropIndex(buildIndex, lastNormalInterval, true);
          return;
        }
      }
    }
    if (lastNormalInterval == null) return;
    _changeDropIndex(lastBuildIndex, lastNormalInterval, false);
  }

  // Calculates the new drop position of the item moved up.
  void _reorderMoveUpwards() {
    final draggedTop = _reorderCurrentMainAxisOffset;

    RenderBox? child;
    _NormalInterval? lastNormalInterval;
    var lastBuildIndex = 0;
    for (child = firstChild; child != null; child = childAfter(child)) {
      final childParentData = parentDataOf(child)!;
      final childTop = childParentData.layoutOffset! + childSize(child) * 0.25;

      if (draggedTop < childTop) {
        final buildIndex = childParentData.index!;
        final intervalData = _intervalList.intervalAtBuildIndex(buildIndex);
        if (intervalData.interval is _NormalInterval) {
          lastNormalInterval = intervalData.interval as _NormalInterval;
          lastBuildIndex = buildIndex;
          _changeDropIndex(buildIndex, lastNormalInterval, false);
          return;
        }
      }
    }
    if (lastNormalInterval == null) return;
    _changeDropIndex(lastBuildIndex, lastNormalInterval, true);
  }

  // Calls the onReorderMove callback to find out if the new drop position is allowed.
  // If so, the intervals are updated accordingly.
  void _changeDropIndex(
      int buildIndex, _NormalInterval interval, bool onTheRight) {
    final intervalListIndex = _intervalList.listItemIndexOf(interval);
    final intervalBuildIndex = _intervalList.buildItemIndexOf(interval);
    final insertBuildIndex = buildIndex + (onTheRight ? 1 : 0);
    var newDropListIndex =
        intervalListIndex + insertBuildIndex - intervalBuildIndex;
    final pickIndex = _intervalList.reorderPickListIndex!;
    if (newDropListIndex > pickIndex) newDropListIndex--;
    final delegate = childManager.widget.delegate;
    if (newDropListIndex == _intervalList.reorderDropListIndex(pickIndex) ||
        !(delegate.reorderModel?.onReorderMove
                .call(pickIndex, newDropListIndex) ??
            false)) {
      return;
    }
    _intervalList.updateReorderDropIndex(interval,
        insertBuildIndex - intervalBuildIndex, _reorderDraggedItemSize);
  }

  // The dragged item has been released, so the reodering will be completed.
  void _reorderStop(bool cancel) {
    if (!isReordering) return;

    final pickIndex = _intervalList.reorderPickListIndex!;
    var dropIndex = _intervalList.reorderDropListIndex(pickIndex);

    final delegate = childManager.widget.delegate;
    if (cancel ||
        !(delegate.reorderModel?.onReorderComplete
                .call(pickIndex, dropIndex, _slot) ??
            false)) {
      dropIndex = pickIndex;
    }

    _slot = null;

    childManager._dropDraggedItem(dropIndex, (RenderBox? currentRenderBox) {
      if (currentRenderBox == null) {
        _reorderDraggedRenderBox = null;
        return null;
      }

      final currentChildParentData =
          currentRenderBox.parentData! as SliverMultiBoxAdaptorParentData;

      dropChild(_reorderDraggedRenderBox!);

      final previousRenderBox = childBefore(currentRenderBox);
      remove(currentRenderBox);
      insert(_reorderDraggedRenderBox!, after: previousRenderBox);

      _reorderDraggedRenderBox!
          .layout(constraints.asBoxConstraints(), parentUsesSize: true);
      parentDataOf(_reorderDraggedRenderBox!)!.layoutOffset =
          currentChildParentData.layoutOffset;

      _reorderDraggedRenderBox = null;

      return previousRenderBox;
    });

    markNeedsLayout();
  }

  // The dragged item has been removed, the reorder will be aborted.
  void _reorderDraggedItemHasBeenRemoved() {
    assert(isReordering);
    _reorderDraggedRenderBox = null;
    childManager._disposeDraggedItem();
    markNeedsLayout();
  }

  // The dragged item has changed, so this item has be rebuilt and the open reorder interval
  // will eventually be recreated in order to make room for the new item size.
  void _reorderDraggedItemHasChanged() {
    final itemIndex = _intervalList.reorderPickListIndex;
    if (itemIndex == null) return;

    final oldScrollOffset = childScrollOffset(_reorderDraggedRenderBox!);

    childManager._rebuildDraggedItem(itemIndex, (Widget measuredWidget) {
      final childConstraints = constraints.asBoxConstraints();

      final newItemSize = measureItem(measuredWidget, childConstraints);

      _reorderDraggedItemSize = newItemSize;

      _reorderDraggedRenderBox!.layout(childConstraints, parentUsesSize: true);
      final newChildParentData = _reorderDraggedRenderBox!.parentData!
          as SliverMultiBoxAdaptorParentData;
      newChildParentData.layoutOffset = oldScrollOffset;

      return newItemSize;
    });
  }

  // Updates the layout offset of the dragged item.
  // Also schedules the calculation of the new drop position.
  // Finally, it considers wheter to trigger a scroling of the list because
  // the dragged item has been moved the the top or bottom of it.
  void _reoderPerformLayout() {
    if (!isReordering) return;

    WidgetsBinding.instance!.addPostFrameCallback((_) {
      _reorderComputeNewOffset();
    });

    // layout the dragged item
    _reorderCurrentMainAxisOffset = (_reorderOriginMainAxisOffset +
            _reorderMainAxisLocalOffset +
            (constraints.scrollOffset - _reorderOriginScrollOffset))
        .clamp(0.0, geometry!.maxPaintExtent - _reorderDraggedItemSize);

    _reorderDraggedRenderBox!
        .layout(constraints.asBoxConstraints(), parentUsesSize: true);

    parentDataOf(_reorderDraggedRenderBox!)!.layoutOffset =
        _reorderCurrentMainAxisOffset;

    // scroll up/down as needed while dragging
    var fromOffset = constraints.scrollOffset;
    var toOffset = fromOffset + constraints.remainingPaintExtent;

    var controller = Scrollable.of(childManager)?.widget.controller;
    if (controller != null) {
      var position = controller.position;

      var delta = 0.0;
      if (_reorderCurrentMainAxisOffset < fromOffset &&
          position.extentBefore > 0.0) {
        delta = -_kReorderingScrollSpeed;
      } else if (_reorderCurrentMainAxisOffset + _reorderDraggedItemSize >
              toOffset &&
          position.extentAfter > 0.0) {
        delta = _kReorderingScrollSpeed;
      }

      if (delta != 0.0) {
        final value = position.pixels + delta;
        WidgetsBinding.instance!.addPostFrameCallback((_) {
          controller.jumpTo(value);
          markNeedsLayout();
        });
      }
    }
  }

  Rect? _computeItemBox(int buildIndex, bool absolute);
}

// This class extends the original RenderSliverList to add support for animation and
// reordering features to a list of variabile-size items.
class AnimatedRenderSliverList extends RenderSliverList
    with AnimatedRenderSliverMultiBoxAdaptor {
  AnimatedRenderSliverList(AnimatedSliverList widget,
      AnimatedSliverMultiBoxAdaptorElement childManager)
      : super(childManager: childManager) {
    init();
  }

  @override
  AnimatedSliverMultiBoxAdaptorElement get childManager =>
      super.childManager as AnimatedSliverMultiBoxAdaptorElement;

  // Measure the size of a bunch of off-list children.
  // If the calculated size exceedes the remaining cache extent of the list view,
  // an estimate will be returned.
  @override
  Future<_Measure> measureItems(
      _Cancelled cancelled, int count, IndexedWidgetBuilder builder) async {
    final childConstraints = constraints.asBoxConstraints();
    final maxSize = constraints.remainingCacheExtent;
    assert(count > 0 && maxSize >= 0.0);
    var size = 0.0;
    var i = 0;
    for (; i < count; i++) {
      if (size > maxSize) break;
      await Future.delayed(Duration(milliseconds: 0), () {
        if (cancelled.value) return _Measure.zero;
        size += measureItem(builder.call(childManager, i), childConstraints);
      });
      if (cancelled.value) return _Measure.zero;
    }
    // }
    if (i < count) size *= (count / i);
    return _Measure(size, i < count);
  }

  @override
  double measureItem(Widget widget, [BoxConstraints? childConstraints]) {
    late double size;
    childManager.disposableChild(widget, (renderBox) {
      renderBox.layout(childConstraints ?? constraints.asBoxConstraints(),
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
    assert(!_intervalList.hasPendingUpdates);

    if (lastIndex == childCount - 1) return trailingScrollOffset;

    var innerSpace = 0.0, trailingSpace = 0.0;
    var innerCount = 0, trailingCount = 0;
    var buildIndex = 0;
    var resizingTotalItemSize = 0.0;
    var resizingTotalItemCount = 0;
    for (final interval in _intervalList) {
      if (interval is _ResizableInterval) {
        if (firstIndex <= buildIndex) {
          if (buildIndex <= lastIndex) {
            // resizing intervals inside the viewport
            innerCount++;
            innerSpace += interval.currentSize;
          } else {
            // resizing intervals outside/after the viewport
            trailingCount++;
            trailingSpace += interval.currentSize;
          }
        }
        final aisc = interval.averageItemSizeCount;
        resizingTotalItemSize += aisc.size;
        resizingTotalItemCount += aisc.count;
      }
      buildIndex += interval.buildCount;
    }

    var ret = trailingScrollOffset + trailingSpace;

    // items outside/after the viewport, excluding resizing intervals
    final remainingCount = childCount - lastIndex - trailingCount - 1;
    if (remainingCount > 0) {
      // items inside the viewport, excluding resizing intervals
      var reifiedCount = 1 + lastIndex - firstIndex - innerCount;
      double averageExtent;
      // average size of an item (calculated from the items inside the viewport)
      averageExtent = (trailingScrollOffset -
              leadingScrollOffset -
              innerSpace +
              resizingTotalItemSize) /
          (reifiedCount + resizingTotalItemCount);
      ret += averageExtent * remainingCount;
    }
    return ret;
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) =>
      doVisitChildren(visitor, () => super.visitChildren(visitor));

  @override
  void paint(PaintingContext context, Offset offset) =>
      doPaint(context, offset, () => super.paint(context, offset));

  @override
  void performLayout() => doPerformLayout(() => super.performLayout());

  @override
  Rect? _computeItemBox(int buildIndex, bool absolute) {
    if (buildIndex < 0 || buildIndex >= _intervalList.buildItemCount) {
      return null;
    }
    final firstChild = firstChildWithLayout;
    var r = 0.0;
    var s = 0.0;
    if (firstChild == null) {
      for (var i = 0; i < buildIndex; i++) {
        final widget = childManager._build(i, true);
        if (widget == null) return null;
        r += measureItem(widget);
      }
      final widget = childManager._build(buildIndex, true);
      if (widget == null) return null;
      s = measureItem(widget);
    } else {
      s = childSize(firstChild);
      final parentData = parentDataOf(firstChild)!;
      var i = parentData.index!;
      r = parentData.layoutOffset!;
      if (buildIndex <= i) {
        while (buildIndex < i) {
          final widget = childManager._build(--i, true);
          if (widget == null) return null;
          s = measureItem(widget);
          r -= s;
        }
      } else {
        var child = firstChild;
        while (buildIndex > i) {
          final nextChild = childAfter(child);
          if (nextChild == null) break;
          final parentData = parentDataOf(nextChild)!;
          if (parentData.layoutOffset == null) break;
          child = nextChild;
          i = parentData.index!;
          r = parentData.layoutOffset!;
        }
        s = childSize(child);
        if (buildIndex > i) {
          i++;
          r += s;
          while (buildIndex > i) {
            final widget = childManager._build(i++, true);
            if (widget == null) return null;
            r += measureItem(widget);
          }
          final widget = childManager._build(buildIndex, true);
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
}

/// This class extends the original [RenderSliverFixedExtentList] to add support for
/// animations and reordering feature to a list of fixed-extent items.
class AnimatedRenderSliverFixedExtentList extends RenderSliverFixedExtentList
    with AnimatedRenderSliverMultiBoxAdaptor {
  AnimatedRenderSliverFixedExtentList({
    required AnimatedSliverMultiBoxAdaptorElement childManager,
    required double itemExtent,
    required AnimatedSliverFixedExtentList widget,
  }) : super(childManager: childManager, itemExtent: itemExtent) {
    init();
  }

  @override
  AnimatedSliverMultiBoxAdaptorElement get childManager =>
      super.childManager as AnimatedSliverMultiBoxAdaptorElement;

  @override
  Future<_Measure> measureItems(_Cancelled cancelled, int count,
          IndexedWidgetBuilder builder) async =>
      _Measure(itemExtent * count, false);

  @override
  double measureItem(Widget widget, [BoxConstraints? childConstraints]) =>
      itemExtent;

  @override
  void _resizingIntervalUpdated(_ResizingInterval interval, double delta) {
    super._resizingIntervalUpdated(interval, delta);
    markNeedsLayout();
  }

  @override
  double? extrapolateMaxScrollOffset(
    final int firstIndex,
    final int lastIndex,
    final double leadingScrollOffset,
    final double trailingScrollOffset,
    final int childCount,
  ) {
    assert(!_intervalList.hasPendingUpdates);

    if (lastIndex == childCount - 1) {
      return trailingScrollOffset;
    }

    var trailingSpace = 0.0;
    var trailingCount = 0;
    var buildIndex = 0;
    for (final interval in _intervalList) {
      if (interval is _ResizableInterval) {
        if (firstIndex <= buildIndex) {
          if (buildIndex > lastIndex) {
            // resizing intervals outside/after the viewport
            trailingCount++;
            trailingSpace += interval.currentSize;
          }
        }
      }
      buildIndex += interval.buildCount;
    }

    var ret = trailingScrollOffset + trailingSpace;

    // items outside/after the viewport, excluding resizing intervals
    final remainingCount = childCount - lastIndex - trailingCount - 1;
    if (remainingCount > 0) {
      ret += itemExtent * remainingCount;
    }

    return ret;
  }

  @override
  double indexToLayoutOffset(double itemExtent, int index) {
    var bi = 0, n = 0;
    var sz = 0.0;
    for (final interval in _intervalList) {
      if (index <= bi) break;
      if (interval is _ResizingInterval) {
        sz += interval.currentSize;
        n++;
      }
      bi += interval.buildCount;
    }
    return sz + itemExtent * (index - n);
  }

  @override
  double computeMaxScrollOffset(
      SliverConstraints constraints, double itemExtent) {
    var count = childManager.childCount;
    var sz = 0.0;
    for (final interval in _intervalList.whereType<_ResizingInterval>()) {
      sz += interval.currentSize;
      count--;
    }
    return sz + itemExtent * count;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) {
    var toOffset = 0.0, adjust = 0.0;
    var bi = 0;
    for (final interval in _intervalList) {
      if (interval is _ResizingInterval) {
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
    return super
        .getMinChildIndexForScrollOffset(scrollOffset + adjust, itemExtent);
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) {
    var toOffset = 0.0, adjust = 0.0;
    var bi = 0;
    for (final interval in _intervalList) {
      if (interval is _ResizingInterval) {
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
    return super
        .getMaxChildIndexForScrollOffset(scrollOffset + adjust, itemExtent);
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) =>
      doVisitChildren(visitor, () => super.visitChildren(visitor));

  @override
  void paint(PaintingContext context, Offset offset) =>
      doPaint(context, offset, () => super.paint(context, offset));

  @override
  void performLayout() => doPerformLayout(() {
        final constraints = this.constraints;
        childManager.didStartLayout();
        childManager.setDidUnderflow(false);

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

        final firstIndex =
            getMinChildIndexForScrollOffset(scrollOffset, itemExtent);
        final targetLastIndex = targetEndScrollOffset.isFinite
            ? getMaxChildIndexForScrollOffset(targetEndScrollOffset, itemExtent)
            : null;

        if (firstChild != null) {
          final leadingGarbage = _calculateLeadingGarbage(firstIndex);
          final trailingGarbage = targetLastIndex != null
              ? _calculateTrailingGarbage(targetLastIndex)
              : 0;
          collectGarbage(leadingGarbage, trailingGarbage);
        } else {
          collectGarbage(0, 0);
        }

        if (firstChild == null) {
          if (!addInitialChild(
              index: firstIndex,
              layoutOffset: indexToLayoutOffset(itemExtent, firstIndex))) {
            // There are either no children, or we are past the end of all our children.
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
            childManager.didFinishLayout();
            return;
          }
        }

        RenderBox? trailingChildWithLayout;

        for (var index = indexOf(firstChild!) - 1;
            index >= firstIndex;
            --index) {
          final child = insertAndLayoutLeadingChild(childConstraints);
          if (child == null) {
            // Items before the previously first child are no longer present.
            // Reset the scroll offset to offset all items prior and up to the
            // missing item. Let parent re-layout everything.

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            // geometry = SliverGeometry(scrollOffsetCorrection: index * itemExtent);
            geometry = SliverGeometry(
                scrollOffsetCorrection: indexToLayoutOffset(itemExtent, index));
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            return;
          }
          final childParentData =
              child.parentData! as SliverMultiBoxAdaptorParentData;
          childParentData.layoutOffset = indexToLayoutOffset(itemExtent, index);
          assert(childParentData.index == index);
          trailingChildWithLayout ??= child;
        }

        if (trailingChildWithLayout == null) {
          firstChild!.layout(childConstraints);
          final childParentData =
              firstChild!.parentData! as SliverMultiBoxAdaptorParentData;
          childParentData.layoutOffset =
              indexToLayoutOffset(itemExtent, firstIndex);
          trailingChildWithLayout = firstChild;
        }

        var estimatedMaxScrollOffset = double.infinity;
        for (var index = indexOf(trailingChildWithLayout!) + 1;
            targetLastIndex == null || index <= targetLastIndex;
            ++index) {
          var child = childAfter(trailingChildWithLayout!);
          if (child == null || indexOf(child) != index) {
            child = insertAndLayoutChild(childConstraints,
                after: trailingChildWithLayout);
            if (child == null) {
              // We have run out of children.
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
              // estimatedMaxScrollOffset = index * itemExtent;
              estimatedMaxScrollOffset = indexToLayoutOffset(itemExtent, index);
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
              break;
            }
          } else {
            child.layout(childConstraints);
          }
          trailingChildWithLayout = child;
          // assert(child != null);
          final childParentData =
              child.parentData! as SliverMultiBoxAdaptorParentData;
          assert(childParentData.index == index);
          childParentData.layoutOffset =
              indexToLayoutOffset(itemExtent, childParentData.index!);
        }

        final lastIndex = indexOf(lastChild!);
        final leadingScrollOffset = indexToLayoutOffset(itemExtent, firstIndex);
        final trailingScrollOffset =
            indexToLayoutOffset(itemExtent, lastIndex + 1);

        assert(firstIndex == 0 ||
            childScrollOffset(firstChild!)! - scrollOffset <=
                precisionErrorTolerance);
        assert(debugAssertChildListIsNonEmptyAndContiguous());
        assert(indexOf(firstChild!) == firstIndex);
        assert(targetLastIndex == null || lastIndex <= targetLastIndex);

        estimatedMaxScrollOffset = math.min(
          estimatedMaxScrollOffset,
          estimateMaxScrollOffset(
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
                targetEndScrollOffsetForPaint, itemExtent)
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
        childManager.didFinishLayout();
      });

  int _calculateLeadingGarbage(int firstIndex) {
    var walker = firstChild;
    var leadingGarbage = 0;
    while (walker != null && indexOf(walker) < firstIndex) {
      leadingGarbage += 1;
      walker = childAfter(walker);
    }
    return leadingGarbage;
  }

  int _calculateTrailingGarbage(int targetLastIndex) {
    var walker = lastChild;
    var trailingGarbage = 0;
    while (walker != null && indexOf(walker) > targetLastIndex) {
      trailingGarbage += 1;
      walker = childBefore(walker);
    }
    return trailingGarbage;
  }

  @override
  Rect? _computeItemBox(int buildIndex, bool absolute) {
    if (buildIndex < 0 || buildIndex >= _intervalList.buildItemCount) {
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
