part of 'core.dart';

/// An element that lazily builds children for a [SliverWithKeepAliveWidget].
///
/// Implements [RenderSliverBoxChildManager], which lets this element manage
/// the children of subclasses of [RenderSliverMultiBoxAdaptor].
///
/// This class takes the implementation of the standard [SliverMultiBoxAdaptorElement] class
/// and provides support for animations and reordering feature.
class AnimatedSliverMultiBoxAdaptorElement extends RenderObjectElement
    implements
        RenderSliverBoxChildManager,
        _ControllerInterface,
        _ListIntervalInterface {
  /// Creates an element that lazily builds children for the given widget with
  /// support for animations and reordering.
  AnimatedSliverMultiBoxAdaptorElement(
      AnimatedSliverMultiBoxAdaptorWidget widget)
      : super(widget);

  // support for the method didChangeDependencies like in State.didChangeDependencies.
  bool _didChangeDependencies = false;

  @override
  AnimatedSliverMultiBoxAdaptorWidget get widget =>
      super.widget as AnimatedSliverMultiBoxAdaptorWidget;

  @override
  AnimatedRenderSliverMultiBoxAdaptor get renderObject =>
      super.renderObject as AnimatedRenderSliverMultiBoxAdaptor;

  _IntervalList get intervalList => renderObject._intervalList;

  /// This method has been overridden to give the render object the `didChangeDependencies` method
  /// and to link this list view to its controller.
  @override
  void mount(final Element? parent, final dynamic newSlot) {
    super.mount(parent, newSlot);
    renderObject.didChangeDependencies(this);
    widget.listController._setInterface(this);
  }

  /// This method has been overridden to give the render object a `dispose` method and to unlink
  /// this list view from its controller.
  @override
  void unmount() {
    widget.listController._unsetInterface(this);
    renderObject.dispose();
    super.unmount();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _didChangeDependencies = true;
  }

  @override
  void update(covariant AnimatedSliverMultiBoxAdaptorWidget newWidget) {
    final oldWidget = widget;
    super.update(newWidget);
    if (newWidget.listController != oldWidget.listController) {
      oldWidget.listController._unsetInterface(this);
      newWidget.listController._setInterface(this);
    }
    if (intervalList.hasPendingUpdates) {
      performRebuild();
    }
  }

  /// Inspired by [SliverMultiBoxAdaptorElement.performRebuild].
  ///
  /// This method is called to process any pending updates (for example, new intervals
  /// have been added, old intervals have changed state, reordering has started, and so on).
  ///
  /// It considers all pending build updates to move each old last rendered child
  /// to the correct new position.
  ///
  /// It also calls the [AnimatedRenderSliverList.didChangeDependencies] method if a dependency
  /// has been changed.
  @override
  void performRebuild() {
    if (_didChangeDependencies) {
      renderObject.didChangeDependencies(this);
      _didChangeDependencies = false;
    }

    super.performRebuild();

    _currentBeforeChild = null;
    var childrenUpdated = false;
    assert(_currentlyUpdatingChildIndex == null);
    try {
      final newChildren = SplayTreeMap<int, Element?>();
      final rebuildChildren = HashSet<int>();

      for (final index in _childElements.keys.toList()) {
        final childParentData = _childElements[index]?.renderObject?.parentData
            as SliverMultiBoxAdaptorParentData?;

        // This function takes the old index of a child and calculates the new one by considering
        // all the pending updates.
        // This method can return `null` if the child no longer exists (for example,
        // all elements of a remove interval disappear when it becomes a resizing interval).
        // Can set `needsRebuild` to `true` to mark the child as to be rebuilt.
        // Can set `unbind` to `true` to invalidate its current layout offset (it is used by new
        // resizing intervals in order to forget the layout offset of the previously built child,
        // to avoid annoying scroll jumps when these intervals are not accurately measured).
        var needsRebuild = false;
        var unbind = false;
        int? _oldIndexToNewIndex(int index) {
          for (final upd in intervalList.updates) {
            if (index >= upd.index && index < upd.index + upd.oldBuildCount) {
              switch (upd.mode) {
                case _UpdateMode.UNBIND:
                  unbind |= unbind;
                  return null;
                case _UpdateMode.REPLACE:
                  return null;
                case _UpdateMode.REBUILD:
                  if (index - upd.index >= upd.oldBuildCount + upd.skipCount) {
                    return null;
                  }
                  needsRebuild = true;
                  break;
              }
            }
            if (index >= upd.index + upd.oldBuildCount) index += upd.skipCount;
          }
          return index;
        }

        var newIndex = _oldIndexToNewIndex(index);

        if (childParentData != null && (newIndex == null || unbind)) {
          childParentData.layoutOffset = null;
        }

        if (newIndex == null) {
          newChildren.putIfAbsent(index, () => null);
        } else {
          if (needsRebuild) rebuildChildren.add(newIndex);

          if (newIndex != index) {
            newChildren[newIndex] = _childElements[index];
            newChildren.putIfAbsent(index, () => null);
            _childElements.remove(index);
          } else {
            newChildren.putIfAbsent(index, () => _childElements[index]);
          }
        }
      }

      void processElement(int index) {
        _currentlyUpdatingChildIndex = index;
        if (_childElements[index] != null &&
            _childElements[index] != newChildren[index]) {
          // This index has an old child that isn't used anywhere and should be deactivated.
          _childElements[index] =
              updateChild(_childElements[index], null, index);
          childrenUpdated = true;
        }
        var oldChild = newChildren[index];
        late final Element? newChild;
        if (!rebuildChildren.contains(index) && oldChild != null) {
          if ((oldChild.slot as int) != index) {
            updateSlotForChild(oldChild, index);
          }
          newChild = oldChild;
        } else {
          newChild = updateChild(oldChild, _build(index), index);
        }

        if (newChild != null) {
          childrenUpdated =
              childrenUpdated || _childElements[index] != newChild;
          _childElements[index] = newChild;
          final parentData = newChild.renderObject!.parentData!
              as SliverMultiBoxAdaptorParentData;
          if (!parentData.keptAlive) {
            _currentBeforeChild = newChild.renderObject as RenderBox?;
          }
        } else {
          childrenUpdated = true;
          _childElements.remove(index);
        }
      }

      renderObject.debugChildIntegrityEnabled =
          false; // Moving children will temporary violate the integrity.
      newChildren.keys.forEach(processElement);
    } finally {
      _currentlyUpdatingChildIndex = null;
      renderObject.debugChildIntegrityEnabled = true;
      intervalList.updates.clear();
    }
  }

  Widget? _build(int index, [bool measureOnly = false]) {
    final count = intervalList.buildItemCount;
    if (index < 0 || index >= count) return null;
    return intervalList.build(this, index, measureOnly);
  }

  // It creates an disposable off-list child, building the specified widget,
  // and executes the callback. Eventually, the child is disposed.
  void disposableChild(Widget widget, void Function(RenderBox) callback) {
    owner!.lockState(() {
      _currentlyUpdatingChildIndex = null;
      Element? _measuringOffListChild;
      _measuringOffListChild =
          updateChild(_measuringOffListChild, widget, null);
      assert(_measuringOffListChild != null);
      callback(_measuringOffListChild!.renderObject! as RenderBox);
      _measuringOffListChild = updateChild(_measuringOffListChild, null, null);
      assert(_measuringOffListChild == null);
    });
  }

  @override
  int get childCount => intervalList.buildItemCount;

  /// Copied from [SliverMultiBoxAdaptorElement.estimateMaxScrollOffset].
  /// The [AnimatedSliverChildBuilderDelegate.estimateMaxScrollOffset] method call
  /// has been removed just now.
  @override
  double estimateMaxScrollOffset(
    final SliverConstraints constraints, {
    final int? firstIndex,
    final int? lastIndex,
    final double? leadingScrollOffset,
    final double? trailingScrollOffset,
  }) {
    return renderObject.extrapolateMaxScrollOffset(firstIndex!, lastIndex!,
        leadingScrollOffset!, trailingScrollOffset!, childCount)!;
  }

  //
  // Copied part
  //

  int? _currentlyUpdatingChildIndex;
  final SplayTreeMap<int, Element?> _childElements =
      SplayTreeMap<int, Element?>();
  RenderBox? _currentBeforeChild;

  /// Copied from [SliverMultiBoxAdaptorElement.didAdoptChild].
  /// An assertion was removed to allow adoption of off-list elements.
  @override
  void didAdoptChild(final RenderBox child) {
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    // assert(_currentlyUpdatingChildIndex != null);
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    final childParentData =
        child.parentData! as SliverMultiBoxAdaptorParentData;
    childParentData.index = _currentlyUpdatingChildIndex;
  }

  /// Copied from [SliverMultiBoxAdaptorElement.insertRenderObjectChild].
  /// This method has been changed to prevent inserting off-list elements into the children list.
  @override
  void insertRenderObjectChild(covariant RenderObject child, final int? slot) {
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    if (slot == null) {
      renderObject.setupParentData(child);
      assert(renderObject.debugValidateChild(child));
      renderObject.adoptChild(child);
      return;
    }
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    assert(_currentlyUpdatingChildIndex == slot);
    assert(renderObject.debugValidateChild(child));
    renderObject.insert(child as RenderBox, after: _currentBeforeChild);
    assert(() {
      final childParentData =
          child.parentData! as SliverMultiBoxAdaptorParentData;
      assert(slot == childParentData.index);
      return true;
    }());
  }

  /// Copied from [SliverMultiBoxAdaptorElement.createChild].
  @override
  void createChild(final int index, {required final RenderBox? after}) {
    assert(_currentlyUpdatingChildIndex == null);
    owner!.buildScope(this, () {
      final insertFirst = after == null;
      assert(insertFirst || _childElements[index - 1] != null);
      _currentBeforeChild = insertFirst
          ? null
          : (_childElements[index - 1]!.renderObject as RenderBox?);
      Element? newChild;
      try {
        _currentlyUpdatingChildIndex = index;
        newChild = updateChild(_childElements[index], _build(index), index);
      } finally {
        _currentlyUpdatingChildIndex = null;
      }
      if (newChild != null) {
        _childElements[index] = newChild;
      } else {
        _childElements.remove(index);
      }
    });
  }

  SliverMultiBoxAdaptorParentData? _parentDataOf(Element? element) =>
      element?.renderObject?.parentData as SliverMultiBoxAdaptorParentData?;

  /// Copied from [SliverMultiBoxAdaptorElement.updateChild].
  @override
  Element? updateChild(
      final Element? child, final Widget? newWidget, final dynamic newSlot) {
    final oldParentData = _parentDataOf(child);
    final newChild = super.updateChild(child, newWidget, newSlot);
    final newParentData = _parentDataOf(newChild);

    // Preserve the old layoutOffset if the renderObject was swapped out.
    if (oldParentData != newParentData &&
        oldParentData != null &&
        newParentData != null) {
      newParentData.layoutOffset = oldParentData.layoutOffset;
    }
    return newChild;
  }

  /// Copied from [SliverMultiBoxAdaptorElement.forgetChild].
  @override
  void forgetChild(final Element child) {
    assert(child.slot != null);
    assert(_childElements.containsKey(child.slot));
    _childElements.remove(child.slot);
    super.forgetChild(child);
  }

  /// Copied from [SliverMultiBoxAdaptorElement.removeChild].
  @override
  void removeChild(final RenderBox child) {
    final index = renderObject.indexOf(child);
    assert(_currentlyUpdatingChildIndex == null);
    assert(index >= 0);
    owner!.buildScope(this, () {
      assert(_childElements.containsKey(index));
      try {
        _currentlyUpdatingChildIndex = index;
        final result = updateChild(_childElements[index], null, index);
        assert(result == null);
      } finally {
        _currentlyUpdatingChildIndex = null;
      }
      _childElements.remove(index);
      assert(!_childElements.containsKey(index));
    });
  }

  /// Copied from [SliverMultiBoxAdaptorElement.debugAssertChildListLocked].
  @override
  bool debugAssertChildListLocked() {
    assert(_currentlyUpdatingChildIndex == null);
    return true;
  }

  /// Copied from [SliverMultiBoxAdaptorElement.setDidUnderflow].
  /// The didUnderflow variabile is no longer needed.
  @override
  void setDidUnderflow(final bool value) {
    // _didUnderflow = value;
  }

  /// Copied from [SliverMultiBoxAdaptorElement.removeRenderObjectChild].
  /// This method has been changed to prevent the removal of unlisted children (eg off-list elements).
  @override
  void removeRenderObjectChild(covariant RenderObject child, final int? slot) {
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    if ((child.parentData as SliverMultiBoxAdaptorParentData).index == null) {
      renderObject.dropChild(child);
      return;
    }
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    assert(_currentlyUpdatingChildIndex != null);
    renderObject.remove(child as RenderBox);
  }

  /// Copied from [SliverMultiBoxAdaptorElement.moveRenderObjectChild].
  /// This method has been changed to prevent assertion errors.
  @override
  void moveRenderObjectChild(
      covariant RenderObject child, final int? oldSlot, final int? newSlot) {
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    // assert(newSlot != null);
    if (oldSlot == null) return;
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    assert(_currentlyUpdatingChildIndex == newSlot);
    renderObject.move(child as RenderBox, after: _currentBeforeChild);
  }

  /// Copied from [SliverMultiBoxAdaptorElement.visitChildren].
  /// This method has been changed to include the dragged element during reording.
  @override
  void visitChildren(final ElementVisitor visitor) {
    assert(!_childElements.values.any((Element? child) => child == null));
    _childElements.values.cast<Element>().toList().forEach(visitor);
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    if (_reorderDraggedElement != null) {
      visitor.call(_reorderDraggedElement!);
    }
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
  }

  /// Copied from [SliverMultiBoxAdaptorElement.debugVisitOnstageChildren].
  @override
  void debugVisitOnstageChildren(final ElementVisitor visitor) {
    _childElements.values.cast<Element>().where((Element child) {
      final parentData =
          child.renderObject!.parentData! as SliverMultiBoxAdaptorParentData;
      late double itemExtent;
      switch (renderObject.constraints.axis) {
        case Axis.horizontal:
          itemExtent = child.renderObject!.paintBounds.width;
          break;
        case Axis.vertical:
          itemExtent = child.renderObject!.paintBounds.height;
          break;
      }

      return parentData.layoutOffset != null &&
          parentData.layoutOffset! <
              renderObject.constraints.scrollOffset +
                  renderObject.constraints.remainingPaintExtent &&
          parentData.layoutOffset! + itemExtent >
              renderObject.constraints.scrollOffset;
    }).forEach(visitor);
  }

  /// Copied from [SliverMultiBoxAdaptorElement.didStartLayout].
  @override
  void didStartLayout() {
    assert(debugAssertChildListLocked());
  }

  /// Copied from [SliverMultiBoxAdaptorElement.didFinishLayout].
  /// The call of the didFinishLayout callback has been removed.
  @override
  void didFinishLayout() {
    assert(debugAssertChildListLocked());
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    // final firstIndex = _childElements.firstKey() ?? 0;
    // final lastIndex = _childElements.lastKey() ?? 0;
    // widget.delegate.didFinishLayout(firstIndex, lastIndex);
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
  }

  int? _findBuildIndexFromContext(BuildContext context) {
    if (context is! Element) return null;
    int? slot;
    if (context.slot is! int) {
      context.visitAncestorElements((element) {
        if (element is AnimatedSliverMultiBoxAdaptorElement) return false;
        if (element.slot is int) {
          slot = element.slot as int;
          return false;
        }
        return true;
      });
      if (slot == null || slot is! int) return null;
    } else {
      slot = context.slot as int;
    }
    assert(() {
      AnimatedSliverMultiBoxAdaptorElement? e;
      context.visitAncestorElements((element) {
        if (element is AnimatedSliverMultiBoxAdaptorElement) {
          e = element;
          return false;
        }
        return true;
      });
      return e != null && e == this;
    }());
    return slot;
  }

// *************************
//  Reorder Feature Support
// *************************

  Element? _reorderDraggedElement;

  void _pickUpDraggedItem(int buildIndex, int listIndex,
      RenderBox? Function(RenderBox, double) callback) {
    assert(_reorderDraggedElement == null);
    owner!.buildScope(this, () {
      // pop out the dragged child from the list
      _reorderDraggedElement = _childElements[buildIndex];

      // measure it
      final itemSize = renderObject.measureItem(buildWidget(
          this,
          widget.delegate.builder,
          listIndex,
          AnimatedWidgetBuilderData(kAlwaysCompleteAnimation,
              measuring: true, dragging: true)));

      // delegate the work back to the render object
      _currentBeforeChild =
          callback(_reorderDraggedElement!.renderObject as RenderBox, itemSize);

      // notify IntervalList that the reorder has been started:
      // a _ReorderOpeningInterval is returned
      final openInterval =
          intervalList.notifyStartReorder(buildIndex, itemSize);

      // replace the in-list dragged item with a new resizing interval widget
      _currentlyUpdatingChildIndex = buildIndex;
      final newElement = updateChild(
          null, openInterval.buildWidget(this, 0, 0, false), buildIndex);
      _childElements[buildIndex] = newElement;
      _currentlyUpdatingChildIndex = null;

      // rebuild dragged child with dragging attribute set
      _reorderDraggedElement = updateChild(
          _reorderDraggedElement,
          buildWidget(
              this,
              widget.delegate.builder,
              listIndex,
              AnimatedWidgetBuilderData(kAlwaysCompleteAnimation,
                  dragging: true, slot: renderObject._slot)),
          buildIndex);
    });
  }

  void _dropDraggedItem(int listItemIndex,
      RenderBox? Function(RenderBox? currentRenderBox) callback) {
    owner!.buildScope(this, () {
      var draggedElement = _reorderDraggedElement!;

      // notify IntervalList that the reorder has been stopped:
      // the buildIndex where the dragged item will be dropped is returned
      final buildIndex = intervalList.notifyStopReorder();

      // retrieve the resizing interval child that will be replaced with the dragged item
      final currentElement = _childElements[buildIndex];

      // delegate the work back to the render object
      final currentRenderBox = currentElement?.renderObject as RenderBox?;
      _currentlyUpdatingChildIndex = buildIndex;
      final previousRenderBox = callback(currentRenderBox);

      if (currentRenderBox != null) {
        // the drop zone is still visibile, the off-list dragged item must be rebuilt
        // with the dragging attribute unset and put back in the list
        _currentBeforeChild = previousRenderBox;
        draggedElement = updateChild(
            draggedElement,
            buildWidget(
                this,
                widget.delegate.builder,
                listItemIndex,
                AnimatedWidgetBuilderData(kAlwaysCompleteAnimation,
                    slot: renderObject._slot)),
            buildIndex)!;
        _childElements[buildIndex] = draggedElement;
      } else {
        // the drop zone is no longer visibile, the off-list dragged item can be disposed
        _currentlyUpdatingChildIndex = null;
        updateChild(draggedElement, null, null);
      }

      _reorderDraggedElement = null;
      _currentlyUpdatingChildIndex = null;
    });
  }

  void _disposeDraggedItem() {
    assert(_reorderDraggedElement != null);
    owner!.buildScope(this, () {
      var draggedElement = _reorderDraggedElement!;
      _currentlyUpdatingChildIndex = null;
      _reorderDraggedElement = null;
      updateChild(draggedElement, null, null);
    });
  }

  void _rebuildDraggedItem(int itemIndex, double Function(Widget) callback) {
    assert(_reorderDraggedElement != null);
    owner!.buildScope(this, () {
      final measuredWidget = buildWidget(
          this,
          widget.delegate.builder,
          itemIndex,
          AnimatedWidgetBuilderData(kAlwaysCompleteAnimation,
              measuring: true, dragging: true, slot: renderObject._slot));
      final newWidget = buildWidget(
          this,
          widget.delegate.builder,
          itemIndex,
          AnimatedWidgetBuilderData(kAlwaysCompleteAnimation,
              dragging: true, slot: renderObject._slot));

      // _currentlyUpdatingChildIndex = null;
      _currentBeforeChild = null;

      _reorderDraggedElement =
          updateChild(_reorderDraggedElement, newWidget, null);

      final newItemSize = callback(measuredWidget);

      intervalList.reorderChangeOpeningIntervalSize(newItemSize);
    });
  }

  //
  // Implementation of _ListIntervalInterface
  //

  @override
  AnimatedSliverChildDelegate get delegate => widget.delegate;

  @override
  bool get isHorizontal => renderObject.constraints.axis == Axis.horizontal;

  @override
  Widget buildWidget(BuildContext context, AnimatedWidgetBuilder builder,
      int index, AnimatedWidgetBuilderData data) {
    Widget child;
    try {
      child = builder.call(context, index, data);
    } catch (exception, stackTrace) {
      child = _createErrorWidget(exception, stackTrace);
    }
    return widget.delegate.wrapWidget(context, child, data);
  }

  // It notifies that the resizing interval has changed its size by the delta amount.
  @override
  void resizingIntervalUpdated(_ResizingInterval interval, double delta) {
    renderObject._resizingIntervalUpdated(interval, delta);
  }

  /// Measure the size of a bunch of off-list children up to [count] elements.
  /// You have to provide a [builder] to build the `i`-th widget.
  /// The calculation is asynchronous and can be cancelled.
  @override
  Future<_Measure> measureItems(
      _Cancelled cancelled, int count, IndexedWidgetBuilder builder) async {
    return await renderObject.measureItems(cancelled, count, builder);
  }

  @override
  void draggedItemHasBeenRemoved() {
    renderObject._reorderDraggedItemHasBeenRemoved();
  }

  @override
  void draggedItemHasChanged() {
    renderObject._reorderDraggedItemHasChanged();
  }

  //
  // Implementation of _ControllerListeners
  //

  int _batch = 0;

  /// See [AnimatedListController.batch].
  @override
  void batch(VoidCallback callback) {
    _batch++;
    callback();
    _batch--;
    assert(_batch >= 0);
    if (_batch == 0) intervalList.coordinate();
  }

  /// See [AnimatedListController.notifyInsertedRange].
  @override
  void notifyInsertedRange(int from, int count, int priority) =>
      _notifyReplacedRange(from, 0, count, null, priority);

  /// See [AnimatedListController.notifyRemovedRange].
  @override
  void notifyRemovedRange(int from, int count,
          final AnimatedWidgetBuilder removedItemBuilder, int priority) =>
      _notifyReplacedRange(from, count, 0, removedItemBuilder, priority);

  /// See [AnimatedListController.notifyReplacedRange].
  @override
  void notifyReplacedRange(int from, int removeCount, final int insertCount,
          final AnimatedWidgetBuilder removedItemBuilder, int priority) =>
      _notifyReplacedRange(
          from, removeCount, insertCount, removedItemBuilder, priority);

  /// See [AnimatedListController.notifyChangedRange].
  @override
  void notifyChangedRange(int from, int count,
          final AnimatedWidgetBuilder changedItemBuilder, int priority) =>
      _notifyChangedRange(from, count, changedItemBuilder, priority);

  void _notifyReplacedRange(int from, int removeCount, final int insertCount,
      final AnimatedWidgetBuilder? removedItemBuilder, int priority) {
    intervalList.notifyRangeReplaced(
        from, removeCount, insertCount, removedItemBuilder, priority);
    if (_batch == 0) intervalList.coordinate();
  }

  void _notifyChangedRange(int from, int count,
      final AnimatedWidgetBuilder changedItemBuilder, int priority) {
    intervalList.notifyRangeChanged(from, count, changedItemBuilder, priority);
    if (_batch == 0) intervalList.coordinate();
  }

  /// See [AnimatedListController.notifyStartReorder].
  @override
  void notifyStartReorder(BuildContext context, double dx, double dy) {
    renderObject._reorderStart(context, dx, dy);
  }

  /// See [AnimatedListController.notifyUpdateReorder].
  @override
  void notifyUpdateReorder(double dx, double dy) {
    renderObject._reorderUpdate(dx, dy);
  }

  /// See [AnimatedListController.notifyStopReorder].
  @override
  void notifyStopReorder(bool cancel) {
    renderObject._reorderStop(cancel);
  }

  @override
  Rect? computeItemBox(int index, bool absolute) {
    return renderObject._computeItemBox(index, absolute);
  }

  @override
  int? listToActualItemIndex(int index) {
    if (index < 0 || index >= intervalList.listItemCount) {
      return null;
    }
    final interval = intervalList.intervalAtListIndex(index);
    if (interval.interval is _InListItemInterval ||
        interval.interval is _ReadyToChangingInterval) {
      return interval.buildIndex + (index - interval.itemIndex);
    }
    return null;
  }

  @override
  int? actualToListItemIndex(int index) {
    if (index < 0 || index >= intervalList.buildItemCount) {
      return null;
    }
    final interval = intervalList.intervalAtBuildIndex(index);
    if (interval.interval is _InListItemInterval ||
        interval.interval is _ReadyToChangingInterval) {
      return interval.itemIndex + (index - interval.buildIndex);
    }
    return null;
  }
}

abstract class _ListIntervalInterface {
  AnimatedSliverChildDelegate get delegate;
  bool get isHorizontal;
  Widget buildWidget(BuildContext context, AnimatedWidgetBuilder builder,
      int index, AnimatedWidgetBuilderData data);
  void resizingIntervalUpdated(_ResizingInterval interval, double delta);
  Future<_Measure> measureItems(
      _Cancelled cancelled, int count, IndexedWidgetBuilder builder);
  void draggedItemHasBeenRemoved() {}
  void draggedItemHasChanged() {}
  void markNeedsBuild();
}

// Return a Widget for the given Exception (copied from the standard package).
Widget _createErrorWidget(Object exception, StackTrace stackTrace) {
  final details = FlutterErrorDetails(
    exception: exception,
    stack: stackTrace,
    library: 'widgets library',
    context: ErrorDescription('building'),
  );
  FlutterError.reportError(details);
  return ErrorWidget.builder(details);
}
