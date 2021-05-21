part of 'great_list_view_lib.dart';

//---------------------------------------------------------------------------------------------
// AnimatedSliverMultiBoxAdaptorElement (RenderObjectElement / Child Manager)
//---------------------------------------------------------------------------------------------

/// An element that lazily builds children for a [SliverWithKeepAliveWidget].
///
/// Implements [RenderSliverBoxChildManager], which lets this element manage
/// the children of subclasses of [RenderSliverMultiBoxAdaptor].
///
/// This class takes the implementation of the standard [SliverMultiBoxAdaptorElement] class
/// and provides support for animations in face of list changes and reordering.
class AnimatedSliverMultiBoxAdaptorElement extends RenderObjectElement
    implements RenderSliverBoxChildManager {
  /// Creates an element that lazily builds children for the given widget with support for
  /// animations in response to changes to the list and reordering.
  AnimatedSliverMultiBoxAdaptorElement(AnimatedSliverList widget)
      : super(widget);

  // support for the method didChangeDependencies like in [State.didChangeDependencies]
  bool _didChangeDependencies = false;

  /// additional parameter passed to [AnimatedSliverChildBuilderDelegate.build] method.
  // ignore: prefer_final_fields
  AnimatedListBuildType _buildType = AnimatedListBuildType.UNKNOWN;

  // list of updates to apply to this render object element in response to one or more changes to the list
  final List<_BuildUpdate> _updates = [];

  /// This method has been overridden to give [AnimatedRenderSliverList] an `init` method.
  @override
  void mount(final Element? parent, final dynamic newSlot) {
    super.mount(parent, newSlot);
    renderObject.didChangeDependencies(this);
    renderObject.init();
  }

  /// This method has been overridden to give [AnimatedRenderSliverList] a `dispose` method.
  @override
  void unmount() {
    renderObject.dispose();
    super.unmount();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _didChangeDependencies = true;
  }

  @override
  AnimatedSliverList get widget => super.widget as AnimatedSliverList;

  @override
  AnimatedRenderSliverList get renderObject =>
      super.renderObject as AnimatedRenderSliverList;

  var _hardRebuild = false;

  void markNeedsSoftRefresh() {
    _hardRebuild = true;
    markNeedsBuild();
  }

  /// Copied and adapted from [SliverMultiBoxAdaptorElement.update].
  @override
  void update(covariant AnimatedSliverList newWidget) {
    final oldWidget = widget;
    super.update(newWidget);
    final newDelegate = newWidget.delegate;
    final oldDelegate = oldWidget.delegate;
    if (newDelegate != oldDelegate &&
        (newDelegate.runtimeType != oldDelegate.runtimeType ||
            newDelegate.shouldRebuild(oldDelegate))) {
      renderObject.update(widget); // update also the render object!
      _resizingIntervals.clear();
      _updates.clear();
      _reorderDraggedElement = null;
      _reorderingStopUpdate = false;
      _reorderFromIndex = null;
      _reorderToIndex = null;

      _hardRebuild = true;
      performRebuild();
    } else if (hasPendingUpdates) {
      performRebuild();
    }
  }

  Widget? _build(int index) => renderObject._buildAnimatedWidget(this, index);

  final _resizingIntervals = <AnimatedListInterval, double?>{};

  /// This method is being called from [AnimatedRenderSliverList] when creating a new interval.
  /// A new entry will be added to the update list and this element will be marked to rebuild.
  void _onUpdateOnNewInterval(AnimatedListInterval interval) {
    _BuildUpdateType type;
    switch (interval.state) {
      case _AnimatedListIntervalState.REMOVING:
        type = _BuildUpdateType.NEW_REMOVING_INTERVAL;
        break;
      case _AnimatedListIntervalState.RESIZING:
        type = _BuildUpdateType.NEW_RESIZING_INTERVAL;
        _resizingIntervals.putIfAbsent(interval, () => interval.fromSize);
        break;
      case _AnimatedListIntervalState.CHANGING:
        type = _BuildUpdateType.NEW_CHANGING_INTERVAL;
        break;
      case _AnimatedListIntervalState.INSERTING:
        type = _BuildUpdateType.RESIZED_TO_INSERTING; // immediate inserting
        break;
      default:
        return;
    }
    _updates.add(_BuildUpdate(
      index: interval.index,
      removeCount: interval.removeCount,
      insertCount: interval.insertCount,
      type: type,
    ));
    markNeedsBuild();
  }

  /// This method is being called from [AnimatedRenderSliverList] when a removing interval becomes
  /// a resizing interval.
  /// A new entry will be added to the update list and this element will be marked to rebuild.
  void _onUpdateOnIntervalRemovedToResizing(AnimatedListInterval interval) {
    _updates.add(_BuildUpdate(
      index: interval.index,
      removeCount: interval.removeCount,
      insertCount: interval.insertCount,
      type: _BuildUpdateType.REMOVED_TO_RESIZING,
    ));
    _resizingIntervals.putIfAbsent(interval, () => interval.fromSize);
    markNeedsBuild();
  }

  /// This method is being called from [AnimatedRenderSliverList] when a resizing interval becomes
  /// an inserting interval.
  /// A new entry will be added to the update list and this element will be marked to rebuild.
  void _onUpdateOnIntervalResizedToInserting(AnimatedListInterval interval) {
    _updates.add(_BuildUpdate(
      index: interval.index,
      removeCount: interval.removeCount,
      insertCount: interval.insertCount,
      type: _BuildUpdateType.RESIZED_TO_INSERTING,
    ));
    markNeedsBuild();
  }

  /// This method is being called from [AnimatedRenderSliverList] when a resizing interval (without
  /// insertion) completes.
  /// A new entry will be added to the update list and this element will be marked to rebuild.
  void _onUpdateOnIntervalResizedToDisposing(AnimatedListInterval interval) {
    _updates.add(_BuildUpdate(
      index: interval.index,
      removeCount: interval.removeCount,
      insertCount: interval.insertCount,
      type: _BuildUpdateType.RESIZED_TO_DISPOSING,
    ));
    markNeedsBuild();
  }

  /// This method is being called from [AnimatedRenderSliverList] when a inserting interval completes.
  /// This element will be marked to rebuild.
  void _onUpdateOnIntervalInsertedToDisposing(AnimatedListInterval interval) {
    _updates.add(_BuildUpdate(
      index: interval.index,
      removeCount: interval.removeCount,
      insertCount: interval.insertCount,
      type: _BuildUpdateType.INSERTED_TO_DISPOSING,
    ));
    markNeedsBuild();
  }

  /// This method is being called from [AnimatedRenderSliverList] when a changing interval completes.
  /// This element will be marked to rebuild.
  void _onUpdateOnIntervalChangedToDisposing(AnimatedListInterval interval) {
    _updates.add(_BuildUpdate(
      index: interval.index,
      removeCount: interval.removeCount,
      insertCount: interval.insertCount,
      type: _BuildUpdateType.CHANGED_TO_DISPOSING,
    ));
    markNeedsBuild();
  }

  Element? _reorderDraggedElement, _reorderHiddenElement;
  bool _reorderingStopUpdate = false;
  int? _reorderFromIndex, _reorderToIndex;

  /// Returns the render box of the dragged visible child element.
  RenderBox? get _reorderDraggedRenderBox =>
      _reorderDraggedElement?.renderObject as RenderBox?;

  RenderBox? get _reorderRemovedChild =>
      _reorderHiddenElement?.renderObject as RenderBox?;

  /// Called by [AnimatedRenderSliverList] after reordering is started.
  /// This element will be marked to rebuild.
  void _onUpdateOnStartReording(int index) {
    markNeedsBuild();
    _reorderFromIndex = index;
    _reorderHiddenElement = _childElements[index];
    _parentDataOf(_reorderHiddenElement)!.keepAlive = true;
  }

  /// Called by [AnimatedRenderSliverList] after reordering is completed.
  /// This element will be marked to rebuild or hard rebuild if the move
  /// hasn't been cancelled.
  void _onUpdateOnStopReording(int fromIndex, int? toIndex) {
    assert(_reorderFromIndex == fromIndex);
    _reorderingStopUpdate = true;
    _reorderToIndex = toIndex ?? fromIndex;
    _resizingIntervals.clear();
    _parentDataOf(_reorderHiddenElement)!.keepAlive = false;
    _reorderHiddenElement = null;
    if (toIndex != null) _hardRebuild = true;
    markNeedsBuild();
  }

  /// Calculate the difference between the current size and its last rendered size of all
  /// resizing intervals.
  /// Only the resizing intervals before the specified index are considered.
  /// The sum of these differences is returned.
  double _calculateOffsetCorrection(int firstIndex) {
    var ret = 0.0;
    for (var entry in _resizingIntervals.entries) {
      final interval = entry.key;
      final lastSize = entry.value ?? interval.fromSize;
      assert(lastSize != null);
      final currentSize =
          interval.isInResizingState ? interval.currentSize : interval.toSize;
      if (currentSize != null) {
        if (interval.index < firstIndex) {
          ret += currentSize - lastSize!;
        }
        if (interval.isInResizingState) {
          _resizingIntervals[interval] = currentSize;
        }
      }
    }
    _resizingIntervals
        .removeWhere((interval, lastSize) => !interval.isInResizingState);
    return ret;
  }

  /// Measure the size of a bunch of off-list children up to [count] elements.
  /// If the calculated size exceedes the [maxSize], an estimate will be returned.
  /// You have to provide a [builder] to build the `i`-th widget and the [childConstraints]
  /// to use to layout it.
  double _measureOffListChildren(int count, double maxSize,
      NullableIndexedWidgetBuilder builder, BoxConstraints childConstraints) {
    var size = 0.0;
    int i;
    Element? element;
    for (i = 0; i < count; i++) {
      if (size > maxSize) break;
      final widget = builder.call(this, i);
      element = _createOrUpdateOffListChild(element, widget, childConstraints);
      assert(element != null);
      final renderBox = element!.renderObject as RenderBox?;
      switch (renderObject.constraints.axis) {
        case Axis.horizontal:
          size += renderBox!.size.width;
          break;
        case Axis.vertical:
          size += renderBox!.size.height;
          break;
      }
    }
    if (i < count) size *= (count / i);
    _destroyOffListChild(element!);
    return size;
  }

  /// Inspired by [SliverMultiBoxAdaptorElement.performRebuild].
  /// This method is called to process any pending updates (for example, new intervals
  /// have been added, old intervals have changed state, reordering has started, and so on).
  ///
  /// It considers all pending build updates to move every old last rendered child
  /// to the correct new position.
  ///
  /// On start reordering it creates a new off-list dragged child, whereas on stop reordering
  /// it destroys it and repositions the children taking into account the moved item.
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
    assert(_currentlyUpdatingChildIndex == null);
    try {
      final newChildren = SplayTreeMap<int, Element?>();
      final Map<int, double?> indexToLayoutOffset = HashMap<int, double?>();

      if (_reorderDraggedElement != null &&
          (_reorderingStopUpdate || _reorderFromIndex == null)) {
        // destroy the off-list dragged child
        _destroyOffListChild(_reorderDraggedElement!);
        _reorderDraggedElement = null;
      }

      if (!_reorderingStopUpdate && _reorderFromIndex != null) {
        // create or update the off-list dragged child
        var dragWidget =
            renderObject._buildDraggedChild(this, _reorderFromIndex!);
        _reorderDraggedElement =
            _createOrUpdateOffListChild(_reorderDraggedElement, dragWidget);
      }

      for (final index in _childElements.keys.toList()) {
        assert(_childElements[index] != null);

        var newIndex = _oldIndexToNewIndex(index);

        // reposition the children taking into account the moved item
        if (_reorderingStopUpdate && newIndex != null) {
          if (_reorderFromIndex! < _reorderToIndex!) {
            if (newIndex >= _reorderFromIndex!) {
              if (newIndex == _reorderFromIndex) {
                newIndex = _reorderToIndex;
              } else if (newIndex <= _reorderToIndex!) {
                newIndex--;
              }
            }
          } else if (_reorderFromIndex! > _reorderToIndex!) {
            if (newIndex >= _reorderToIndex!) {
              if (newIndex == _reorderFromIndex) {
                newIndex = _reorderToIndex;
              } else if (newIndex <= _reorderFromIndex!) {
                newIndex++;
              }
            }
          }
        }

        final childParentData = _parentDataOf(_childElements[index]);

        if (newIndex != null &&
            childParentData != null &&
            childParentData.layoutOffset != null) {
          indexToLayoutOffset[newIndex] = childParentData.layoutOffset;
        }

        if (newIndex != null && newIndex != index) {
          // // The layout offset of the child being moved is no longer accurate.
          // if (childParentData != null) {
          //   childParentData.layoutOffset = null;
          // }

          newChildren[newIndex] = _childElements[index];
          // We need to make sure the original index gets processed.
          newChildren.putIfAbsent(index, () => null);
          // We do not want the remapped child to get deactivated during processElement.
          _childElements.remove(index);
        } else {
          newChildren.putIfAbsent(
              index, () => newIndex != null ? _childElements[index] : null);
        }
      }

      void processElement(int index) {
        _currentlyUpdatingChildIndex = index;
        if (_childElements[index] != null &&
            _childElements[index] != newChildren[index]) {
          assert(_childElements[index] != _reorderHiddenElement);
          _childElements[index] =
              updateChild(_childElements[index], null, index);
        }

        var newChild = newChildren[index];
        var rebuild = newChild == null ||
            (_hardRebuild &&
                (newChild != _reorderHiddenElement || _reorderingStopUpdate)) ||
            (newChild != _reorderHiddenElement && newChild.slot != index);
        if (rebuild) {
          newChild = updateChild(newChild, _build(index), index);
        } else if (newChild!.slot != index) {
          updateSlotForChild(newChild, index);
        }

        if (newChild != null) {
          _childElements[index] = newChild;

          final parentData = _parentDataOf(newChild)!;
          if (index == 0) {
            parentData.layoutOffset = 0.0;
          } else if (parentData.layoutOffset == null &&
              indexToLayoutOffset.containsKey(index)) {
            parentData.layoutOffset = indexToLayoutOffset[index];
          }
          if (!parentData.keptAlive) {
            _currentBeforeChild = newChild.renderObject as RenderBox?;
          }
        } else {
          _childElements.remove(index);
        }
      } // processElement

      // Moving children will temporary violate the integrity.
      renderObject.debugChildIntegrityEnabled = false;

      newChildren.keys.forEach(processElement); // !!

      // if (_didUnderflow) {
      //   final lastKey = _childElements.lastKey() ?? -1;
      //   final rightBoundary = lastKey + 1;
      //   newChildren[rightBoundary] = _childElements[rightBoundary];
      //   processElement(rightBoundary);
      // }

      assert(() {
        int? j;
        _childElements.keys.forEach((i) {
          if (renderObject.isBoundaryChild(
              _childElements[i]!.renderObject as RenderBox)) j = i;
        });
        return j == null || j == _childElements.lastKey();
      }());
    } finally {
      _currentlyUpdatingChildIndex = null;
      _updates.clear();
      _hardRebuild = false;
      if (_reorderingStopUpdate) {
        _reorderFromIndex = null;
        _reorderToIndex = null;
        _reorderingStopUpdate = false;
      }
    }
  }

  // It takes the old index of a child and calculates the new one by considering
  // all the pending updates.
  // This method can return `null` if the child no longer exists (for example,
  // all elements of a remove interval disappear when it becomes a resize interval).
  int? _oldIndexToNewIndex(int index) {
    for (final upd in _updates) {
      switch (upd.type) {
        case _BuildUpdateType.NEW_REMOVING_INTERVAL:
        case _BuildUpdateType.NEW_CHANGING_INTERVAL:
          if (index >= upd.index && index < upd.index + upd.removeCount) {
            return null;
          }
          break;
        case _BuildUpdateType.NEW_RESIZING_INTERVAL:
          if (index >= upd.index) index++;
          break;
        case _BuildUpdateType.REMOVED_TO_RESIZING:
          if (index >= upd.index && index < upd.index + upd.removeCount) {
            return null;
          }
          if (index >= upd.index) index += 1 - upd.removeCount;
          break;
        case _BuildUpdateType.RESIZED_TO_INSERTING:
          if (index == upd.index) return null;
          if (index > upd.index) index += upd.insertCount - 1;
          break;
        case _BuildUpdateType.RESIZED_TO_DISPOSING:
          if (index == upd.index) return null;
          if (index > upd.index) index--;
          break;
        case _BuildUpdateType.INSERTED_TO_DISPOSING:
        case _BuildUpdateType.CHANGED_TO_DISPOSING:
          if (index >= upd.index && index < upd.index + upd.insertCount) {
            return null;
          }
          break;
      }
    }
    return index;
  }

  // It creates or update an existing off-list element with a new widget.
  // If [childConstraints] if specified, the render box of the element will also be layouted.
  // The new off-list element is returned.
  Element? _createOrUpdateOffListChild(Element? oldElement, Widget? newWidget,
      [BoxConstraints? childConstraints]) {
    assert(oldElement == null || _parentDataOf(oldElement)!.index == null);
    assert(oldElement == null || oldElement.slot == null);
    _currentlyUpdatingChildIndex = null;
    var e = updateChild(oldElement, newWidget, null);
    if (childConstraints != null) {
      e!.renderObject!.layout(childConstraints, parentUsesSize: true);
    }
    return e;
  }

  // It destroys the specified off-list element.
  void _destroyOffListChild(Element? element) {
    assert(_parentDataOf(element)!.index == null);
    if (element == null) return;
    assert(element.slot == null);
    _currentlyUpdatingChildIndex = null;
    updateChild(element, null, null);
  }

  final SplayTreeMap<int, Element?> _childElements =
      SplayTreeMap<int, Element?>();
  RenderBox? _currentBeforeChild;

  int? get estimatedChildCount => widget.delegate.estimatedChildCount;

  /// Copied from [SliverMultiBoxAdaptorElement.childCount].
  /// The final count will be changed to take in account the last invisibile boundary item
  /// and the items taken by all intervals.
  @override
  int get childCount {
    var result = estimatedChildCount;
    if (result == null) {
      // Since childCount was called, we know that we reached the end of
      // the list (as in, _build return null once), so we know that the
      // list is finite.
      // Let's do an open-ended binary search to find the end of the list
      // manually.
      var lo = 0;
      var hi = 1;
      const max = kIsWeb
          ? 9007199254740992 // max safe integer on JS (from 0 to this number x != x+1)
          : ((1 << 63) - 1);
      while (renderObject._callBuildDelegateCallback(
              this, hi - 1, AnimatedListBuildType.MEASURING) !=
          null) {
        lo = hi - 1;
        if (hi < max ~/ 2) {
          hi *= 2;
        } else if (hi < max) {
          hi = max;
        } else {
          throw FlutterError(
              'Could not find the number of children in ${widget.delegate}.\n'
              'The childCount getter was called (implying that the delegate\'s builder returned null '
              'for a positive index), but even building the child with index $hi (the maximum '
              'possible integer) did not return null. Consider implementing childCount to avoid '
              'the cost of searching for the final child.');
        }
      }
      while (hi - lo > 1) {
        final mid = (hi - lo) ~/ 2 + lo;
        if (renderObject._callBuildDelegateCallback(
                this, mid - 1, AnimatedListBuildType.MEASURING) ==
            null) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      result = lo;
    }
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    return result + 1 + renderObject._intervals.itemCountAdjustment;
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
  }

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
    final childCount = estimatedChildCount;
    if (childCount == null) return double.infinity;
    return renderObject._extrapolateMaxScrollOffset(
      firstIndex,
      lastIndex,
      leadingScrollOffset,
      trailingScrollOffset,
      childCount + renderObject._intervals.itemCountAdjustment,
    )!;
  }

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
  /// This method has been changed to ignore inserting off-list elements into the children list.
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
    //assert(child != null);
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

  int? _currentlyUpdatingChildIndex;

  /// Copied from [SliverMultiBoxAdaptorElement.debugAssertChildListLocked].
  @override
  bool debugAssertChildListLocked() {
    assert(_currentlyUpdatingChildIndex == null);
    return true;
  }

  //bool _didUnderflow = false;

  /// Copied from [SliverMultiBoxAdaptorElement.debugAssertChildListLocked].
  @override
  void setDidUnderflow(final bool value) {
    //_didUnderflow = value;
  }

  /// Copied from [SliverMultiBoxAdaptorElement.removeRenderObjectChild].
  /// This method has been changed to ignore removing off-list elements from the children list.
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
  @override
  void moveRenderObjectChild(
      covariant RenderObject child, final int oldSlot, final int newSlot) {
    //assert(newSlot != null);
    assert(_currentlyUpdatingChildIndex == newSlot);
    renderObject.move(child as RenderBox, after: _currentBeforeChild);
  }

  /// Copied from [SliverMultiBoxAdaptorElement.visitChildren].
  /// This method has been changed to include the dragged element when reording.
  @override
  void visitChildren(final ElementVisitor visitor) {
    // The toList() is to make a copy so that the underlying list can be modified by
    // the visitor:
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
  @override
  void didFinishLayout() {
    assert(debugAssertChildListLocked());
    final firstIndex = _childElements.firstKey() ?? 0;
    final lastIndex = _childElements.lastKey() ?? 0;
    widget.delegate.didFinishLayout(firstIndex, lastIndex);
  }

  /// Returns the [AnimatedListInterval] instance attached to the child element at the
  /// specified [index], if any. Only resizing intervals have it.
  AnimatedListInterval? intervalAtIndex(int index) {
    var key = _childElements[index]?.widget.key;
    if (key is ValueKey && key.value is AnimatedListInterval) {
      return key.value as AnimatedListInterval;
    }
    return null;
  }

  /// Returns the widget attached to the child element at the specified [index].
  Widget? widgetOf(int? index) =>
      index == null ? null : _childElements[index]?.widget;

  /// Returns `true` if there are pending updates.
  bool get hasPendingUpdates => _updates.isNotEmpty;

  SliverMultiBoxAdaptorParentData? _parentDataOf(Element? element) =>
      element?.renderObject?.parentData as SliverMultiBoxAdaptorParentData?;
}

enum _BuildUpdateType {
  NEW_REMOVING_INTERVAL,
  NEW_RESIZING_INTERVAL,
  NEW_CHANGING_INTERVAL,
  REMOVED_TO_RESIZING,
  RESIZED_TO_INSERTING,
  RESIZED_TO_DISPOSING,
  INSERTED_TO_DISPOSING,
  CHANGED_TO_DISPOSING,
}

class _BuildUpdate {
  final int index;
  final int removeCount;
  final int insertCount;
  final _BuildUpdateType type;

  _BuildUpdate(
      {required this.index,
      required this.removeCount,
      required this.insertCount,
      required this.type});
}