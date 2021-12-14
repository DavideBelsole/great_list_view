part of 'core.dart';

/// An element that lazily builds children for a [SliverWithKeepAliveWidget].
///
/// Implements [RenderSliverBoxChildManager], which lets this element manage
/// the children of subclasses of [RenderSliverMultiBoxAdaptor].
///
/// This class takes the implementation of the standard [SliverMultiBoxAdaptorElement] class
/// and adds support for animations and reordering feature.
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

  /// Support for the method didChangeDependencies like in [State.didChangeDependencies].
  bool _didChangeDependencies = false;

  @override
  AnimatedSliverMultiBoxAdaptorWidget get widget =>
      super.widget as AnimatedSliverMultiBoxAdaptorWidget;

  @override
  AnimatedRenderSliverMultiBoxAdaptor get renderObject =>
      super.renderObject as AnimatedRenderSliverMultiBoxAdaptor;

  _IntervalList get _intervalList => renderObject._intervalList;

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
    if (_intervalList.hasPendingUpdates) {
      performRebuild();
    }
  }

  /// This function takes the old [index] of a child and calculates the new one by considering
  /// all the pending [updates].
  /// This method can return `null` if the child no longer exists (for example,
  /// all elements of a remove interval disappear when it becomes a resizing interval).
  _ReindexResult _oldIndexToNewIndex(List<_Update> updates, int index) {
    var needsRebuild = false;
    var clearLayoutOffset = false;
    var discardElement = false;
    var popupDrop = false;
    var popupPick = false;
    _PopUpList? popUpList;
    for (final upd in updates) {
      if (index >= upd.index && index < upd.index + upd.oldBuildCount) {
        if (index >= upd.index + upd.newBuildCount) {
          // it is upd.newBuildCount < upd.oldBuildCount
          return _ReindexResult(null, needsRebuild, discardElement,
              clearLayoutOffset, popupPick, popupDrop, popUpList);
        }
        if (upd.flags.hasClearLayoutOffset) {
          if (index != upd.index || !upd.flags.hasKeepFirstLayoutOffset) {
            clearLayoutOffset = true;
          }
        }
        if (upd.flags.hasPopupDrop) {
          if (popupPick) {
            // TODO: to be checked
            popupPick = false;
            popUpList = null;
          } else {
            popupDrop = true;
            popUpList = upd.popUpList;
          }
        } else if (upd.flags.hasPopupPick) {
          popupPick = true;
          popUpList = upd.popUpList;
        }
        needsRebuild = true;
        if (upd.flags.hasDiscardElement) {
          discardElement = true;
        }
      }
      if (index >= upd.index + upd.oldBuildCount) index += upd.skipCount;
    }
    return _ReindexResult(index, needsRebuild, discardElement,
        clearLayoutOffset, popupPick, popupDrop, popUpList);
  }

  /// Inspired by [SliverMultiBoxAdaptorElement.performRebuild].
  ///
  /// This method is called to process any pending updates (for example, new intervals
  /// have been added, old intervals have changed state, reordering has started, and so on).
  ///
  /// It considers all pending build updates to move each old last rendered child
  /// to its new position.
  ///
  /// It also calls the [AnimatedRenderSliverMultiBoxAdaptor.didChangeDependencies] method
  /// if a dependency has been changed.
  @override
  void performRebuild() {
    if (_didChangeDependencies) {
      renderObject.didChangeDependencies(this);
      _didChangeDependencies = false;
    }

    super.performRebuild();

    assert(_currentlyUpdatingChildIndex == null);
    _currentBeforeChild = null;
    try {
      final newChildren = SplayTreeMap<int, Element?>();

      // moving children will temporary violate the integrity
      renderObject.debugChildIntegrityEnabled = false;

      for (final popUpList in _intervalList.popUpLists) {
        final r = _oldIndexToNewIndex(popUpList.updates, 0);
        popUpList.updates.clear();
        if (r.needsRebuild) {
          // TODO: to be revisited
          if (popUpList is _SingleElementPopUpList) {
            _currentlyUpdatingChildIndex = null;
            popUpList.element = updateChild(
                popUpList.element, _build(0, popUpList: popUpList), null);
          }
        }
        if (popUpList.interval == null) {
          _intervalList.popUpLists.remove(popUpList);
        }
      }

      for (int? index in _childElements.keys.toList()) {
        Element? element = _childElements[index]!;
        var childParentData = _parentDataOf(element);

        final r = _oldIndexToNewIndex(_intervalList.updates, index!);

        // TODO: to be revisited
        if (r.popUpPick) {
          assert(r.needsRebuild);
          final rl = r.popUpList as _SingleElementPopUpList;
          rl.element = updateChild(element, _build(0, popUpList: rl), index)!;
          element = null;
          final renderBox = rl.element!.renderObject as RenderBox;
          renderObject.remove(renderBox);
          renderObject.adoptChild(renderBox);
        }

        // TODO: to be revisited
        if (r.popUpDrop) {
          final layoutOffset = renderObject
              .childScrollOffset(element!.renderObject as RenderBox);
          _currentlyUpdatingChildIndex = index;
          updateChild(element, null, index);
          element = r.popUpList!.elements.first;
          final renderBox = element.renderObject as RenderBox;
          renderObject.dropChild(renderBox);
          renderObject.insert(renderBox, after: _currentBeforeChild);
          (renderBox.parentData! as SliverMultiBoxAdaptorParentData)
              .layoutOffset = layoutOffset;
          r.popUpList!.clearElements();
        }

        if (r.newIndex == null) {
          updateChild(element, null, index);
        } else {
          if (childParentData != null && r.clearLayoutOffset) {
            childParentData.layoutOffset = null;
          }

          _currentlyUpdatingChildIndex = r.newIndex;

          if (r.needsRebuild) {
            if (r.discardElement && element != null) {
              element = updateChild(element, null, r.newIndex);
            }
            element = updateChild(element, _build(r.newIndex!), r.newIndex)!;
          } else {
            if (index != r.newIndex) {
              // just update the slot
              updateChild(element, element!.widget, r.newIndex);
            }
          }

          childParentData = _parentDataOf(element);
          newChildren[r.newIndex!] = element!;
          if (!childParentData!.keptAlive) {
            _currentBeforeChild = element.renderObject as RenderBox?;
          }
        }
      }

      _childElements = newChildren;
    } finally {
      _currentlyUpdatingChildIndex = null;
      renderObject.debugChildIntegrityEnabled = true;
      _intervalList.updates.clear();
    }
  }

  Widget? _build(int index, {bool measureOnly = false, _PopUpList? popUpList}) {
    if (popUpList == null) {
      final count = _intervalList.buildItemCount;
      if (index < 0 || index >= count) return null;
      return _intervalList.build(this, index, measureOnly);
    } else {
      final count = popUpList.interval?.popUpBuildCount ?? 0;
      if (index < 0 || index >= count) return null;
      final listIndex = _intervalList.listItemIndexOf(popUpList.interval!);
      return popUpList.interval!
          .buildPopUpWidget(this, index, listIndex, measureOnly);
    }
  }

  @override
  int get childCount => _intervalList.buildItemCount;

  /// Copied from [SliverMultiBoxAdaptorElement.estimateMaxScrollOffset].
  /// The [SliverMultiBoxAdaptorWidget.estimateMaxScrollOffset] method call
  /// has been removed just now.
  @override
  double estimateMaxScrollOffset(
    final SliverConstraints constraints, {
    final int? firstIndex,
    final int? lastIndex,
    final double? leadingScrollOffset,
    final double? trailingScrollOffset,
  }) {
    return renderObject._extrapolateMaxScrollOffset(firstIndex!, lastIndex!,
        leadingScrollOffset!, trailingScrollOffset!, childCount)!;
  }

  //
  // Copied part
  //

  int? _currentlyUpdatingChildIndex;
  SplayTreeMap<int, Element?> _childElements = SplayTreeMap<int, Element?>();
  RenderBox? _currentBeforeChild;

  /// Copied from [SliverMultiBoxAdaptorElement.didAdoptChild].
  /// An assertion has been removed to allow adoption of off-list elements.
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
  /// The `didUnderflow` variabile is no longer needed.
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
    // assert(_currentlyUpdatingChildIndex != null);
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
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
  /// This method has been changed to include pop-up elements.
  @override
  void visitChildren(final ElementVisitor visitor) {
    assert(!_childElements.values.any((Element? child) => child == null));
    _childElements.values.cast<Element>().toList().forEach(visitor);
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    for (final popUpList in _intervalList.popUpLists) {
      popUpList.elements.forEach((e) => visitor.call(e));
    }
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
  }

  /// Copied from [SliverMultiBoxAdaptorElement.debugVisitOnstageChildren].
  @override
  void debugVisitOnstageChildren(final ElementVisitor visitor) {
    _childElements.values.cast<Element>().where((Element child) {
      final parentData = _parentDataOf(child)!;
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
  // TODO: to be changed; firstChild and lastChild should be used and item index conversion applied.
  @override
  void didFinishLayout() {
    assert(debugAssertChildListLocked());
    final firstIndex = _childElements.firstKey() ?? 0;
    final lastIndex = _childElements.lastKey() ?? 0;
    widget.delegate.didFinishLayout(firstIndex, lastIndex);
  }

  /// Searchs and returns the build index of specified item by its [context], if it can be found.
  int? _buildIndexFromContext(BuildContext context) {
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

  /// It creates an disposable off-list element built with the specified [widget],
  /// and executes the [callback]. Eventually, the child is disposed.
  void _disposableElement(Widget widget, void Function(RenderBox) callback) {
    owner!.lockState(() {
      _currentlyUpdatingChildIndex = null;
      var _measuringOffListChild = updateChild(null, widget, null);
      assert(_measuringOffListChild != null);
      callback(_measuringOffListChild!.renderObject! as RenderBox);
      _measuringOffListChild = updateChild(_measuringOffListChild, null, null);
      assert(_measuringOffListChild == null);
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
  Widget buildWidget(AnimatedWidgetBuilder builder, int index,
      AnimatedWidgetBuilderData data) {
    Widget child;
    try {
      child = builder.call(this, index, data);
    } catch (exception, stackTrace) {
      child = _createErrorWidget(exception, stackTrace);
    }
    return widget.delegate.wrapWidget(this, child, data);
  }

  /// Notifies that the resizing interval has changed its size by the delta amount.
  @override
  void resizingIntervalUpdated(_AnimatedSpaceInterval interval, double delta) {
    renderObject._resizingIntervalUpdated(interval, delta);
  }

  /// Measures the size of a bunch of off-list children up to [count] elements.
  /// You have to provide a [builder] to build the `i`-th widget.
  /// The calculation is asynchronous and can be [cancelled].
  @override
  Future<_Measure> measureItems(
      _Cancelled? cancelled, int count, IndexedWidgetBuilder builder) async {
    return await renderObject._measureItems(cancelled, count, builder);
  }

  /// Measures the size of the [widget].
  @override
  double measureItem(Widget widget) {
    return renderObject.measureItem(widget);
  }

  @override
  void markNeedsLayout() {
    renderObject._markSafeNeedsLayout();
  }

  //
  // Implementation of _ControllerInterface
  //

  int _batch = 0;

  /// See [AnimatedListController.batch].
  @override
  void batch(VoidCallback callback) {
    _batch++;
    callback();
    _batch--;
    assert(_batch >= 0);
    if (_batch == 0) _intervalList.coordinate();
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

  void _notifyReplacedRange(int from, int removeCount, int insertCount,
      final AnimatedWidgetBuilder? removedItemBuilder, int priority) {
    _intervalList.notifyReplacedRange(
        from, removeCount, insertCount, removedItemBuilder, priority);
    if (_batch == 0) _intervalList.coordinate();
  }

  /// See [AnimatedListController.notifyChangedRange].
  @override
  void notifyChangedRange(int from, int count,
      final AnimatedWidgetBuilder changedItemBuilder, int priority) {
    _intervalList.notifyChangedRange(from, count, changedItemBuilder, priority);
    if (_batch == 0) _intervalList.coordinate();
  }

  /// See [AnimatedListController.notifyStartReorder].
  @override
  bool notifyStartReorder(BuildContext context, double dx, double dy) {
    return renderObject._reorderStart(context, dx, dy);
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

  /// See [AnimatedListController.computeItemBox].
  @override
  Rect? computeItemBox(int index, bool absolute) {
    return renderObject._computeItemBox(index, absolute, false);
  }

  /// See [AnimatedListController.getItemVisibleSize].
  @override
  PercentageSize? getItemVisibleSize(int index) {
    final box = renderObject._computeItemBox(index, true, true);
    if (box != null) {
      final c = renderObject.constraints;
      final v1 = c.scrollOffset +
          c.precedingScrollExtent -
          (c.viewportMainAxisExtent - c.remainingPaintExtent);
      final v2 = v1 + c.viewportMainAxisExtent;

      final r1 = (isHorizontal ? box.left : box.top).clamp(v1, v2);
      final r2 = (isHorizontal ? box.right : box.bottom).clamp(v1, v2);
      return PercentageSize(
          math.max(0.0, r2 - r1), (isHorizontal ? box.width : box.height));
    }
  }
}

// Returns a Widget for the given Exception (copied from the standard package).
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

class _ReindexResult {
  const _ReindexResult(this.newIndex, this.needsRebuild, this.discardElement,
      this.clearLayoutOffset, this.popUpPick, this.popUpDrop, this.popUpList);

  /// The new index of the child.
  final int? newIndex;

  /// Marks the child as to be rebuilt.
  final bool needsRebuild;

  /// Marks the child as to be rebuilt as new, discarding its previous [Element].
  final bool discardElement;

  /// Marks to invalidate its current layout offset (especially used by new resizing intervals in order
  /// to forget the layout offset of the previously built child, to avoid annoying scroll jumps when
  /// these intervals are not accurately measured).
  final bool clearLayoutOffset;

  /// Marks the child to be picked up and its [Element] to be moved into the [popUpList].
  final bool popUpPick;

  /// Marks the child to be dropped and its [Element] to be moved from the [popUpList] into the main list.
  final bool popUpDrop;

  /// The [_PopUpList] referred to [popUpPick] or [popUpDrop].
  final _PopUpList? popUpList;
}
