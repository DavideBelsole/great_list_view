part of 'core.dart';

const _kReorderingScrollSpeed = 10.0;

/// If `true` during perform layout a dummy [ScrollUpdateNotification] is sent
/// to repaint the widget that is listening to it (ie. [Scrollbar]).
bool fixScrollableRepainting = true;

/// This mixin is used by [AnimatedRenderSliverList] and [AnimatedRenderSliverFixedExtentList].
mixin AnimatedRenderSliverMultiBoxAdaptor
    implements RenderSliverMultiBoxAdaptor {
  double _resizeCorrectionAmount = 0.0;

  late _IntervalList _intervalList;

  @override
  AnimatedSliverMultiBoxAdaptorElement get childManager;

  void init() {
    _intervalList = _IntervalList(childManager);
  }

  @override
  void dispose() {
    _intervalList.dispose();
  }

  /// Returns the sum of the sizes of a bunch of items, built using the specified builder.
  Future<_Measure> measureItems(
      _Cancelled? cancelled, int count, IndexedWidgetBuilder builder);

  /// Returns the size of a single widget.
  double measureItem(Widget widget, [BoxConstraints? childConstraints]);

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
  void _resizingIntervalUpdated(_AnimatedSpaceInterval interval, double delta) {
    assert(delta != 0.0);
    final firstChild = firstChildWithLayout;
    if (firstChild == null) return;
    if (_intervalList.buildItemIndexOf(interval) < indexOf(firstChild)) {
      _resizeCorrectionAmount += delta;
    }
    markNeedsLayout();
  }

  // Adjusts the layout offset of the first layouted item by the correction amount
  // calculated as a result of resizing the intervals above it.
  bool _adjustTopLayoutOffset() {
    var amount = _resizeCorrectionAmount;
    _resizeCorrectionAmount = 0.0;

    final firstChild = firstChildWithLayout;
    if (firstChild != null) {
      final parentData = _parentDataOf(firstChild)!;
      final firstLayoutOffset = parentData.layoutOffset!;
      if (firstLayoutOffset + amount < 0.0) {
        amount = -firstLayoutOffset; // bring back the offset to zero
      }
      if (amount != 0.0) {
        parentData.layoutOffset = parentData.layoutOffset! + amount;
        if ( childManager.widget.delegate.holdScrollOffset ) {
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
    _intervalList.updateTickerMuted(context);
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

  double childSize(RenderBox child) {
    switch (constraints.axis) {
      case Axis.horizontal:
        return child.size.width;
      case Axis.vertical:
        return child.size.height;
    }
  }

  SliverMultiBoxAdaptorParentData? _parentDataOf(RenderBox? child) =>
      child?.parentData as SliverMultiBoxAdaptorParentData?;

  /// Dispatches a fake change to the [ScrollPosition] to force the listeners
  /// (ie a [Scrollbar]) to refresh its state.
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

  void doPerformLayout(VoidCallback callback) {
    if (!_adjustTopLayoutOffset()) return;

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

    callback();

    if ((geometry!.scrollOffsetCorrection ?? 0.0) != 0.0) {
      return;
    }

    _reorderPerformLayout();

    if (fixScrollableRepainting) {
      WidgetsBinding.instance?.addPostFrameCallback((_) {
        _notifyScrollable();
      });
    }
  }

  RenderBox? _childAfter(RenderBox child) {
    assert(child.parent == this);
    return _parentDataOf(child)?.nextSibling;
  }

  Iterable<RenderBox> allChildren(RenderBox? firstChild) sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = _childAfter(child);
    }
    for (final popUpList in _intervalList.popUpLists) {
      for (final element in popUpList.elements) {
        yield element.renderObject as RenderBox;
      }
    }
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

  void doPaint(
      PaintingContext context, Offset offset, void Function() callback) {
    _popUpChildrenIterator = allChildren(firstChild).skip(1).iterator;
    callback();
    _popUpChildrenIterator = null;
  }

  void doVisitChildren(RenderObjectVisitor visitor, void Function() callback) {
    callback();
    for (final popUpList in _intervalList.popUpLists) {
      for (final element in popUpList.elements) {
        visitor.call(element.renderObject!);
      }
    }
  }

  void layoutWithScrollOffset(RenderBox renderBox, double layoutOffset) {
    renderBox.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final parentData = renderBox.parentData! as SliverMultiBoxAdaptorParentData;
    parentData.layoutOffset = layoutOffset;
  }

  //
  // Reorder Feature Support
  //

  _ReorderPopUpList? get _reorderPopUpList =>
      _intervalList.popUpLists.singleWhereOrNull((e) => e is _ReorderPopUpList)
          as _ReorderPopUpList?;

  RenderBox? get _reorderDraggedRenderBox =>
      _reorderPopUpList?.element?.renderObject as RenderBox?;

  bool get isReordering =>
      _intervalList.any((e) => e is _ReorderHolderNormalInterval);

  double get _reorderDraggedItemSize => _reorderPopUpList!.itemSize;

  final _reorderLayoutData = _ReorderLayoutData();

  bool _reorderStart(BuildContext context, double dx, double dy) {
    if (isReordering) return false;

    var oldBuildIndex = childManager.buildIndexFromContext(context);
    if (oldBuildIndex == null) return false;

    final r =
        childManager.oldIndexToNewIndex(_intervalList.updates, oldBuildIndex);
    if (r.newIndex == null || r.needsRebuild) return false;
    final buildIndex = r.newIndex!;

    final info = _intervalList.intervalAtBuildIndex(buildIndex);
    if (info.interval is! _NormalInterval) return false;

    final itemIndex = info.itemIndex + (buildIndex - info.buildIndex);

    final delegate = childManager.widget.delegate;
    if (!(delegate.reorderModel?.onReorderStart.call(itemIndex, dx, dy) ??
        false)) return false;

    _reorderLayoutData.init(
        constraints,
        _parentDataOf(childManager._childElements[oldBuildIndex]!.renderObject
                as RenderBox)!
            .layoutOffset!,
        dx,
        dy);

    final slot = delegate.reorderModel?.onReorderFeedback.call(itemIndex,
        itemIndex, _reorderLayoutData.currentMainAxisOffset, 0.0, 0.0);

    // notify IntervalList that the reorder has been started
    _intervalList.notifyStartReorder(itemIndex, slot);

    return true;
  }

  // The dragged item has been released, so the reordering can be completed.
  void _reorderStop(bool cancel) {
    if (!isReordering) return;

    final pickIndex = _intervalList.reorderPickListIndex!;
    final dropIndex = _intervalList.reorderDropListIndex(pickIndex);

    final delegate = childManager.widget.delegate;

    cancel = cancel ||
        !(delegate.reorderModel?.onReorderComplete
                .call(pickIndex, dropIndex, _reorderPopUpList?.slot) ??
            false);

    _intervalList.notifyStopReorder(cancel);
  }

  void _reorderUpdate(double dx, double dy) {
    if (!isReordering) return;

    _reorderLayoutData.update(constraints, dx, dy);

    final delegate = childManager.widget.delegate;
    final pickIndex = _intervalList.reorderPickListIndex!;
    final dropIndex = _intervalList.reorderDropListIndex(pickIndex);
    final newSlot = delegate.reorderModel?.onReorderFeedback.call(
        pickIndex,
        dropIndex,
        _reorderLayoutData.currentMainAxisOffset,
        _reorderLayoutData.crossAxisDelta,
        _reorderLayoutData.axisLocalOffset);

    _reorderPopUpList!.updateSlot(newSlot);

    markNeedsLayout();
  }

  // Compute whether the dragged item has been moved up or down by comparing the new position with the old one.
  void _reorderComputeNewOffset() {
    if (!isReordering) return;
    final dir = _reorderLayoutData.updateDirection();
    if (dir == 1) {
      _reorderMoveDownwards();
    } else if (dir == -1) {
      _reorderMoveUpwards();
    }
  }

  // Calculates the new drop position of the item moved down.
  void _reorderMoveDownwards() {
    final draggedBottom =
        _reorderLayoutData.currentMainAxisOffset + _reorderDraggedItemSize;

    RenderBox? child;
    _NormalInterval? lastNormalInterval;
    var lastBuildIndex = 0;
    for (child = lastChild; child != null; child = childBefore(child)) {
      final childParentData = _parentDataOf(child)!;
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
    final draggedTop = _reorderLayoutData.currentMainAxisOffset;

    RenderBox? child;
    _NormalInterval? lastNormalInterval;
    var lastBuildIndex = 0;
    for (child = firstChild; child != null; child = childAfter(child)) {
      final childParentData = _parentDataOf(child)!;
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

  /// Calls the [AnimatedListBaseReorderModel.onReorderMove] callback to find out if the
  /// new drop position is allowed.
  /// If so, the intervals are updated accordingly.
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

  // Updates the layout offset of the dragged item.
  // Also schedules the calculation of the new drop position.
  // Finally, it considers wheter to trigger a scroling of the list because
  // the dragged item has been moved the the top or bottom of it.
  void _reorderPerformLayout() {
    if (!isReordering) return;

    WidgetsBinding.instance!.addPostFrameCallback((_) {
      _reorderComputeNewOffset();
    });

    // layout the dragged item
    _reorderLayoutData.performLayout(
        constraints, geometry!.maxPaintExtent, _reorderDraggedItemSize);

    layoutWithScrollOffset(
        _reorderDraggedRenderBox!, _reorderLayoutData.currentMainAxisOffset);

    // scroll up/down as needed while dragging
    var controller = Scrollable.of(childManager)?.widget.controller;
    if (controller != null) {
      final position = controller.position;
      final delta = _reorderLayoutData.scrollDelta(
          constraints, controller.position, _reorderDraggedItemSize);
      if (delta != 0.0) {
        final value = position.pixels + delta;
        WidgetsBinding.instance!.addPostFrameCallback((_) {
          controller.jumpTo(value);
          markNeedsLayout();
        });
      }
    }
  }

  Rect? _computeItemBox(int itemIndex, bool absolute, bool avoidMeasuring);
}

/// This class extends the original [RenderSliverList] to add support for animation and
/// reordering features to a list of variabile-size items.
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

  // Measures the size of a bunch of off-list children.
  // If the calculated size exceedes the remaining cache extent of the list view,
  // an estimate will be returned.
  @override
  Future<_Measure> measureItems(
      _Cancelled? cancelled, int count, IndexedWidgetBuilder builder) async {
    final childConstraints = constraints.asBoxConstraints();
    final maxSize = constraints.remainingCacheExtent;
    assert(count > 0 && maxSize >= 0.0);
    var size = 0.0;
    var i = 0;
    for (; i < count; i++) {
      if (size > maxSize) break;
      await Future.delayed(Duration(milliseconds: 0), () {
        if (cancelled?.value ?? false) return _Measure.zero;
        size += measureItem(builder.call(childManager, i), childConstraints);
      });
      if (cancelled?.value ?? false) return _Measure.zero;
    }
    // }
    if (i < count) size *= (count / i);
    return _Measure(size, i < count);
  }

  @override
  double measureItem(Widget widget, [BoxConstraints? childConstraints]) {
    late double size;
    childManager._disposableElement(widget, (renderBox) {
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

    var averageTrailingCount = 0.0;
    var innerCount = 0, trailingCount = 0, leadingCount = 0;
    var buildIndex = 0;
    var averageInnerCount = 0.0;
    for (final interval in _intervalList) {
      if (interval is _SpaceInterval) {
        final si = interval as _SpaceInterval;
        if (firstIndex <= buildIndex) {
          if (buildIndex <= lastIndex) {
            // resizing intervals inside the viewport
            innerCount++;
            averageInnerCount += si.averageItemCount;
          } else {
            // resizing intervals outside/after the viewport
            trailingCount++;
            averageTrailingCount += si.averageItemCount;
          }
        } else {
          leadingCount++;
          averageInnerCount += si.averageItemCount;
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
  void visitChildren(RenderObjectVisitor visitor) =>
      doVisitChildren(visitor, () => super.visitChildren(visitor));

  @override
  void paint(PaintingContext context, Offset offset) =>
      doPaint(context, offset, () => super.paint(context, offset));

  @override
  void performLayout() => doPerformLayout(() => super.performLayout());

  @override
  Rect? _computeItemBox(int itemIndex, bool absolute, bool avoidMeasuring) {
    if (_intervalList.hasPendingUpdates) return null;

    final interval = _intervalList.intervalAtItemIndex(itemIndex);
    if (interval.interval is! _InListItemInterval &&
        interval.interval is! _ReadyToChangingInterval) {
      return null;
    }
    var buildIndex = interval.buildIndex + (itemIndex - interval.itemIndex);

    assert(!_intervalList.hasPendingUpdates);
    if (buildIndex < 0 || buildIndex >= _intervalList.buildItemCount) {
      return null;
    }
    var r = 0.0;
    var s = 0.0;
    if (firstChild == null) {
      if (avoidMeasuring) return null;
      for (var i = 0; i < buildIndex; i++) {
        final widget = childManager._build(i, measureOnly: true);
        if (widget == null) return null;
        r += measureItem(widget);
      }
      final widget = childManager._build(buildIndex, measureOnly: true);
      if (widget == null) return null;
      s = measureItem(widget);
    } else {
      s = childSize(firstChild!);
      final parentData = _parentDataOf(firstChild)!;
      var i = parentData.index!;
      r = parentData.layoutOffset!;
      if (buildIndex <= i) {
        if (avoidMeasuring && buildIndex < i) return null;
        while (buildIndex < i) {
          final widget = childManager._build(--i, measureOnly: true);
          if (widget == null) return null;
          s = measureItem(widget);
          r -= s;
        }
      } else {
        var child = firstChild;
        while (buildIndex > i) {
          final nextChild = childAfter(child!);
          if (nextChild == null) break;
          final parentData = _parentDataOf(nextChild)!;
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
            final widget = childManager._build(i++, measureOnly: true);
            if (widget == null) return null;
            r += measureItem(widget);
          }
          final widget = childManager._build(buildIndex, measureOnly: true);
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
  Future<_Measure> measureItems(_Cancelled? cancelled, int count,
          IndexedWidgetBuilder builder) async =>
      (itemExtent * count).toExactMeasure();

  @override
  double measureItem(Widget widget, [BoxConstraints? childConstraints]) =>
      itemExtent;

  @override
  void _resizingIntervalUpdated(_AnimatedSpaceInterval interval, double delta) {
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

    if (lastIndex == childCount - 1) return trailingScrollOffset;

    var trailingSpace = 0.0;
    var trailingCount = 0;
    var buildIndex = 0;
    for (final interval in _intervalList) {
      if (interval is _SpaceInterval) {
        final si = interval as _SpaceInterval;
        if (firstIndex <= buildIndex) {
          if (buildIndex > lastIndex) {
            // resizing intervals outside/after the viewport
            trailingCount++;
            trailingSpace += si.currentSize;
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
  Rect? _computeItemBox(int buildIndex, bool absolute, bool _) {
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

class _ReorderLayoutData {
  var axisLocalOffset = 0.0;
  var crossAxisLocalOffset = 0.0;

  var originScrollOffset = 0.0;

  var originMainAxisOffset = 0.0;
  var originCrossAxisOffset = 0.0;

  var currentMainAxisOffset = 0.0;
  var lastMainAxisOffset = 0.0;

  void init(SliverConstraints constraints, double layoutOffset, double dx,
      double dy) {
    update(constraints, dx, dy);

    originCrossAxisOffset = crossAxisLocalOffset;

    originScrollOffset = constraints.scrollOffset;

    currentMainAxisOffset = layoutOffset;

    lastMainAxisOffset =
        originMainAxisOffset = currentMainAxisOffset - axisLocalOffset;
  }

  void update(SliverConstraints constraints, double dx, double dy) {
    switch (applyGrowthDirectionToAxisDirection(
        constraints.axisDirection, constraints.growthDirection)) {
      case AxisDirection.up:
        crossAxisLocalOffset = dx;
        axisLocalOffset = -dy;
        break;
      case AxisDirection.right:
        axisLocalOffset = dx;
        crossAxisLocalOffset = dy;
        break;
      case AxisDirection.down:
        crossAxisLocalOffset = dx;
        axisLocalOffset = dy;
        break;
      case AxisDirection.left:
        axisLocalOffset = -dx;
        crossAxisLocalOffset = dy;
        break;
    }
  }

  double get crossAxisDelta => crossAxisLocalOffset - originCrossAxisOffset;

  int updateDirection() {
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

  void performLayout(
      SliverConstraints constraints, double maxPaintExtent, double itemSize) {
    currentMainAxisOffset = (originMainAxisOffset +
            axisLocalOffset +
            (constraints.scrollOffset - originScrollOffset))
        .clamp(0.0, maxPaintExtent - itemSize);
  }

  double scrollDelta(
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
