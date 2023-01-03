part of 'core.dart';

abstract class MultiRenderSliverMultiBoxAdaptor extends RenderSliver
    with
        MultiContainerRenderObjectMixin<RenderBox,
            MultiSliverMultiBoxAdaptorParentData, _PopUpList?>,
        RenderSliverHelpers,
        RenderSliverWithKeepAliveMixin {
  /// Creates a sliver with multiple box children.
  ///
  /// The [childManager] argument must not be null.
  MultiRenderSliverMultiBoxAdaptor({
    required MultiRenderSliverBoxChildManager childManager,
  }) : _childManager = childManager {
    assert(() {
      _debugDanglingKeepAlives = <RenderBox>[];
      return true;
    }());
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! MultiSliverMultiBoxAdaptorParentData) {
      child.parentData = MultiSliverMultiBoxAdaptorParentData();
    }
  }

  /// The delegate that manages the children of this object.
  ///
  /// Rather than having a concrete list of children, a
  /// [RenderSliverMultiBoxAdaptor] uses a [RenderSliverBoxChildManager] to
  /// create children during layout in order to fill the
  /// [SliverConstraints.remainingPaintExtent].
  @protected
  MultiRenderSliverBoxChildManager get childManager => _childManager;
  final MultiRenderSliverBoxChildManager _childManager;

  /// The nodes being kept alive despite not being visible.
  final _keepAliveBucket = <_PopUpList?, Map<int, RenderBox>>{};

  late List<RenderBox> _debugDanglingKeepAlives;

  /// Indicates whether integrity check is enabled.
  ///
  /// Setting this property to true will immediately perform an integrity check.
  ///
  /// The integrity check consists of:
  ///
  /// 1. Verify that the children index in childList is in ascending order.
  /// 2. Verify that there is no dangling keepalive child as the result of [move].
  bool get debugChildIntegrityEnabled => _debugChildIntegrityEnabled;
  bool _debugChildIntegrityEnabled = true;
  set debugChildIntegrityEnabled(bool enabled) {
    assert(() {
      _debugChildIntegrityEnabled = enabled;
      return _debugVerifyChildOrder() &&
          (!_debugChildIntegrityEnabled || _debugDanglingKeepAlives.isEmpty);
    }());
  }

  @override
  void adoptChild(RenderObject child) {
    super.adoptChild(child);
    final childParentData =
        child.parentData! as MultiSliverMultiBoxAdaptorParentData;
    if (!childParentData._keptAlive) {
      childManager.didAdoptChild(child as RenderBox);
    }
  }

  bool _debugAssertChildListLocked() =>
      childManager.debugAssertChildListLocked();

  /// Verify that the child list index is in strictly increasing order.
  ///
  /// This has no effect in release builds.
  bool _debugVerifyChildOrder() {
    if (_debugChildIntegrityEnabled) {
      for (final popUpList in keys) {
        final list = listOf(popUpList)!;
        var child = list.firstChild;
        int index;
        while (child != null) {
          index = indexOf(child);
          child = childAfter(child);
          assert(child == null || indexOf(child) > index);
        }
      }
    }
    return true;
  }

  @override
  void insert(_PopUpList? popUpList, RenderBox child, {RenderBox? after}) {
    assert(!_keepAliveBucket.values.any((e) => e.containsValue(child)));
    super.insert(popUpList, child, after: after);
    assert(listOf(popUpList)!.firstChild != null);
    assert(_debugVerifyChildOrder());
  }

  @override
  void move(_PopUpList? toPopUpList, RenderBox child, {RenderBox? after}) {
    // There are two scenarios:
    //
    // 1. The child is not keptAlive.
    // The child is in the childList maintained by ContainerRenderObjectMixin.
    // We can call super.move and update parentData with the new slot.
    //
    // 2. The child is keptAlive.
    // In this case, the child is no longer in the childList but might be stored in
    // [_keepAliveBucket]. We need to update the location of the child in the bucket.
    final childParentData =
        child.parentData! as MultiSliverMultiBoxAdaptorParentData;
    if (!childParentData.keptAlive) {
      super.move(toPopUpList, child, after: after);
      childManager.didAdoptChild(child); // updates the slot in the parentData
      // Its slot may change even if super.move does not change the position.
      // In this case, we still want to mark as needs layout.
      markNeedsLayout();
    } else {
      final fromPopUpList = childParentData.key;
      final fromKeepAliveBucket = _keepAliveBucket[fromPopUpList]!;
      final toKeepAliveBucket =
          _keepAliveBucket.putIfAbsent(toPopUpList, () => {});
      // If the child in the bucket is not current child, that means someone has
      // already moved and replaced current child, and we cannot remove this child.
      if (fromKeepAliveBucket[childParentData.index] == child) {
        fromKeepAliveBucket.remove(childParentData.index);
      }
      assert(() {
        _debugDanglingKeepAlives.remove(child);
        return true;
      }());
      // Update the slot and reinsert back to _keepAliveBucket in the new slot.
      childManager.didAdoptChild(child);
      // If there is an existing child in the new slot, that mean that child will
      // be moved to other index. In other cases, the existing child should have been
      // removed by updateChild. Thus, it is ok to overwrite it.
      assert(() {
        if (toKeepAliveBucket.containsKey(childParentData.index)) {
          _debugDanglingKeepAlives
              .add(toKeepAliveBucket[childParentData.index]!);
        }
        return true;
      }());
      toKeepAliveBucket[childParentData.index!] = child;
      if (fromKeepAliveBucket.isEmpty) _keepAliveBucket.remove(fromPopUpList);
    }
  }

  @override
  void remove(_PopUpList? popUpList, RenderBox child) {
    final childParentData =
        child.parentData! as MultiSliverMultiBoxAdaptorParentData;
    if (!childParentData._keptAlive) {
      super.remove(popUpList, child);
      return;
    }
    final keepAliveBucket = _keepAliveBucket[popUpList]!;
    assert(keepAliveBucket[childParentData.index] == child);
    assert(() {
      _debugDanglingKeepAlives.remove(child);
      return true;
    }());
    keepAliveBucket.remove(childParentData.index);
    dropChild(child);
    if (keepAliveBucket.isEmpty) _keepAliveBucket.remove(popUpList);
  }

  @override
  void removeAll(_PopUpList? popUpList) {
    super.removeAll(popUpList);
    final keepAliveBucket = _keepAliveBucket[popUpList]!;
    keepAliveBucket.values.forEach((e) => dropChild(e));
    keepAliveBucket.clear();
    _keepAliveBucket.remove(popUpList);
  }

  void _createOrObtainChild(_PopUpList? popUpList, int index,
      {required RenderBox? after}) {
    invokeLayoutCallback<SliverConstraints>((SliverConstraints constraints) {
      assert(constraints == this.constraints);
      final keepAliveBucket = _keepAliveBucket.putIfAbsent(popUpList, () => {});
      if (keepAliveBucket.containsKey(index)) {
        final child = keepAliveBucket.remove(index)!;
        final childParentData =
            child.parentData! as MultiSliverMultiBoxAdaptorParentData;
        assert(childParentData._keptAlive);
        dropChild(child);
        child.parentData = childParentData;
        insert(popUpList, child, after: after);
        childParentData._keptAlive = false;
      } else {
        _childManager.createChild(popUpList, index, after: after);
      }
    });
  }

  void _destroyOrCacheChild(_PopUpList? popUpList, RenderBox child) {
    final childParentData =
        child.parentData! as MultiSliverMultiBoxAdaptorParentData;
    if (childParentData.keepAlive) {
      assert(!childParentData._keptAlive);
      remove(popUpList, child);
      final keepAliveBucket = _keepAliveBucket.putIfAbsent(popUpList, () => {});
      keepAliveBucket[childParentData.index!] = child;
      child.parentData = childParentData;
      super.adoptChild(child);
      childParentData._keptAlive = true;
    } else {
      assert(child.parent == this);
      _childManager.removeChild(popUpList, child);
      assert(child.parent == null);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (final child in _keepAliveBucket.values.expand((e) => e.values)) {
      child.attach(owner);
    }
  }

  @override
  void detach() {
    super.detach();
    for (final child in _keepAliveBucket.values.expand((e) => e.values)) {
      child.detach();
    }
  }

  @override
  void redepthChildren() {
    super.redepthChildren();
    _keepAliveBucket.values.expand((e) => e.values).forEach(redepthChild);
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    super.visitChildren(visitor);
    _keepAliveBucket.values.expand((e) => e.values).forEach(visitor);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    super.visitChildren(visitor);
    // Do not visit children in [_keepAliveBucket].
  }

  /// Called during layout to create and add the child with the given index and
  /// scroll offset.
  ///
  /// Calls [RenderSliverBoxChildManager.createChild] to actually create and add
  /// the child if necessary. The child may instead be obtained from a cache;
  /// see [MultiSliverMultiBoxAdaptorParentData.keepAlive].
  ///
  /// Returns false if there was no cached child and `createChild` did not add
  /// any child, otherwise returns true.
  ///
  /// Does not layout the new child.
  ///
  /// When this is called, there are no visible children, so no children can be
  /// removed during the call to `createChild`. No child should be added during
  /// that call either, except for the one that is created and returned by
  /// `createChild`.
  @protected
  bool addInitialChild(
      {_PopUpList? popUpList, int index = 0, double layoutOffset = 0.0}) {
    assert(_debugAssertChildListLocked());
    final list = listOf(popUpList, true)!;
    assert(list.firstChild == null);
    _createOrObtainChild(popUpList, index, after: null);
    if (list.firstChild != null) {
      assert(list.firstChild == list.lastChild);
      assert(indexOf(list.firstChild!) == index);
      final firstChildParentData =
          list.firstChild!.parentData! as MultiSliverMultiBoxAdaptorParentData;
      firstChildParentData.layoutOffset = layoutOffset;
      firstChildParentData.key = popUpList;
      return true;
    }
    if (popUpList == null) childManager.setDidUnderflow(true);
    return false;
  }

  /// Called during layout to create, add, and layout the child before
  /// [firstChild].
  ///
  /// Calls [RenderSliverBoxChildManager.createChild] to actually create and add
  /// the child if necessary. The child may instead be obtained from a cache;
  /// see [MultiSliverMultiBoxAdaptorParentData.keepAlive].
  ///
  /// Returns the new child or null if no child was obtained.
  ///
  /// The child that was previously the first child, as well as any subsequent
  /// children, may be removed by this call if they have not yet been laid out
  /// during this layout pass. No child should be added during that call except
  /// for the one that is created and returned by `createChild`.
  @protected
  RenderBox? insertAndLayoutLeadingChild(
    _PopUpList? popUpList,
    BoxConstraints childConstraints, {
    bool parentUsesSize = false,
  }) {
    assert(_debugAssertChildListLocked());
    final list = listOf(popUpList)!;
    final index = indexOf(list.firstChild!) - 1;
    _createOrObtainChild(popUpList, index, after: null);
    if (indexOf(list.firstChild!) == index) {
      list.firstChild!.layout(childConstraints, parentUsesSize: parentUsesSize);
      return list.firstChild;
    }
    if (popUpList == null) childManager.setDidUnderflow(true);
    return null;
  }

  /// Called during layout to create, add, and layout the child after
  /// the given child.
  ///
  /// Calls [RenderSliverBoxChildManager.createChild] to actually create and add
  /// the child if necessary. The child may instead be obtained from a cache;
  /// see [MultiSliverMultiBoxAdaptorParentData.keepAlive].
  ///
  /// Returns the new child. It is the responsibility of the caller to configure
  /// the child's scroll offset.
  ///
  /// Children after the `after` child may be removed in the process. Only the
  /// new child may be added.
  @protected
  RenderBox? insertAndLayoutChild(
    _PopUpList? popUpList,
    BoxConstraints childConstraints, {
    required RenderBox? after,
    bool parentUsesSize = false,
  }) {
    assert(_debugAssertChildListLocked());
    assert(after != null);
    final index = indexOf(after!) + 1;
    _createOrObtainChild(popUpList, index, after: after);
    final child = childAfter(after);
    if (child != null && indexOf(child) == index) {
      child.layout(childConstraints, parentUsesSize: parentUsesSize);
      return child;
    }
    if (popUpList == null) childManager.setDidUnderflow(true);
    return null;
  }

  /// Called after layout with the number of children that can be garbage
  /// collected at the head and tail of the child list.
  ///
  /// Children whose [MultiSliverMultiBoxAdaptorParentData.keepAlive] property is
  /// set to true will be removed to a cache instead of being dropped.
  ///
  /// This method also collects any children that were previously kept alive but
  /// are now no longer necessary. As such, it should be called every time
  /// [performLayout] is run, even if the arguments are both zero.
  @protected
  void collectGarbage(
      _PopUpList? popUpList, int leadingGarbage, int trailingGarbage) {
    assert(_debugAssertChildListLocked());
    final list = listOf(popUpList)!;
    assert(list.childCount >= leadingGarbage + trailingGarbage);
    invokeLayoutCallback<SliverConstraints>((SliverConstraints constraints) {
      while (leadingGarbage > 0) {
        _destroyOrCacheChild(popUpList, list.firstChild!);
        leadingGarbage -= 1;
      }
      while (trailingGarbage > 0) {
        _destroyOrCacheChild(popUpList, list.lastChild!);
        trailingGarbage -= 1;
      }
      // Ask the child manager to remove the children that are no longer being
      // kept alive. (This should cause _keepAliveBucket to change, so we have
      // to prepare our list ahead of time.)
      _keepAliveBucket.values
          .expand((e) => e.values)
          .where((RenderBox child) {
            final childParentData =
                child.parentData! as MultiSliverMultiBoxAdaptorParentData;
            return !childParentData.keepAlive;
          })
          .toList()
          .forEach((e) => _childManager.removeChild(popUpList, e));
      assert(_keepAliveBucket.values
          .expand((e) => e.values)
          .where((RenderBox child) {
        final childParentData =
            child.parentData! as MultiSliverMultiBoxAdaptorParentData;
        return !childParentData.keepAlive;
      }).isEmpty);
    });
  }

  /// Returns the index of the given child, as given by the
  /// [MultiSliverMultiBoxAdaptorParentData.index] field of the child's [parentData].
  int indexOf(RenderBox child) {
    final childParentData =
        child.parentData! as MultiSliverMultiBoxAdaptorParentData;
    assert(childParentData.index != null);
    return childParentData.index!;
  }

  _PopUpList? popUpListOf(RenderBox child) {
    final childParentData =
        child.parentData! as MultiSliverMultiBoxAdaptorParentData;
    assert(childParentData.index != null);
    return childParentData.key;
  }

  /// Returns the dimension of the given child in the main axis, as given by the
  /// child's [RenderBox.size] property. This is only valid after layout.
  @protected
  double paintExtentOf(RenderBox child) {
    assert(child.hasSize);
    switch (constraints.axis) {
      case Axis.horizontal:
        return child.size.width;
      case Axis.vertical:
        return child.size.height;
    }
  }

  @override
  bool hitTestChildren(SliverHitTestResult result,
      {required double mainAxisPosition, required double crossAxisPosition}) {
    var child = listOf(null)!.lastChild; // solo la lista principale!
    final boxResult = BoxHitTestResult.wrap(result);
    while (child != null) {
      if (hitTestBoxChild(boxResult, child,
          mainAxisPosition: mainAxisPosition,
          crossAxisPosition: crossAxisPosition)) {
        return true;
      }
      child = childBefore(child);
    }
    return false;
  }

  @override
  double childMainAxisPosition(RenderBox child) {
    return childScrollOffset(child)! - constraints.scrollOffset;
  }

  @override
  double? childScrollOffset(RenderObject child) {
    assert(child.parent == this);
    final childParentData =
        child.parentData! as MultiSliverMultiBoxAdaptorParentData;
    var offset = childParentData.layoutOffset;
    if (offset == null) return null;
    final popUpList = childParentData.key;
    if (popUpList == null) return offset;
    if (popUpList.currentScrollOffset == null) return null;
    return offset + popUpList.currentScrollOffset!;
  }

  @override
  bool paintsChild(RenderBox child) {
    final childParentData =
        child.parentData as MultiSliverMultiBoxAdaptorParentData?;
    final popUpList = childParentData?.key;
    return childParentData?.index != null &&
        !(_keepAliveBucket[popUpList]?.containsKey(childParentData!.index) ??
            false);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (!paintsChild(child)) {
      // This can happen if some child asks for the global transform even though
      // they are not getting painted. In that case, the transform sets set to
      // zero since [applyPaintTransformForBoxChild] would end up throwing due
      // to the child not being configured correctly for applying a transform.
      // There's no assert here because asking for the paint transform is a
      // valid thing to do even if a child would not be painted, but there is no
      // meaningful non-zero matrix to use in this case.
      transform.setZero();
    } else {
      applyPaintTransformForBoxChild(child, transform);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paint(null, context, offset);
    childManager.listOfPopUps.reversed
        .forEach((e) => _paint(e, context, offset));
  }

  void _paint(_PopUpList? popUpList, PaintingContext context, Offset offset) {
    final list = listOf(popUpList);
    if (list?.firstChild == null) {
      return;
    }

    // offset is to the top-left corner, regardless of our axis direction.
    // originOffset gives us the delta from the real origin to the origin in the axis direction.
    final Offset mainAxisUnit, crossAxisUnit, originOffset;
    final bool addExtent;
    switch (applyGrowthDirectionToAxisDirection(
        constraints.axisDirection, constraints.growthDirection)) {
      case AxisDirection.up:
        mainAxisUnit = const Offset(0.0, -1.0);
        crossAxisUnit = const Offset(1.0, 0.0);
        originOffset = offset + Offset(0.0, geometry!.paintExtent);
        addExtent = true;
        break;
      case AxisDirection.right:
        mainAxisUnit = const Offset(1.0, 0.0);
        crossAxisUnit = const Offset(0.0, 1.0);
        originOffset = offset;
        addExtent = false;
        break;
      case AxisDirection.down:
        mainAxisUnit = const Offset(0.0, 1.0);
        crossAxisUnit = const Offset(1.0, 0.0);
        originOffset = offset;
        addExtent = false;
        break;
      case AxisDirection.left:
        mainAxisUnit = const Offset(-1.0, 0.0);
        crossAxisUnit = const Offset(0.0, 1.0);
        originOffset = offset + Offset(geometry!.paintExtent, 0.0);
        addExtent = true;
        break;
    }
    var child = list?.firstChild;
    while (child != null) {
      final mainAxisDelta = childMainAxisPosition(child);
      final crossAxisDelta = childCrossAxisPosition(child);
      var childOffset = Offset(
        originOffset.dx +
            mainAxisUnit.dx * mainAxisDelta +
            crossAxisUnit.dx * crossAxisDelta,
        originOffset.dy +
            mainAxisUnit.dy * mainAxisDelta +
            crossAxisUnit.dy * crossAxisDelta,
      );
      if (addExtent) {
        childOffset += mainAxisUnit * paintExtentOf(child);
      }

      // If the child's visible interval (mainAxisDelta, mainAxisDelta + paintExtentOf(child))
      // does not intersect the paint extent interval (0, constraints.remainingPaintExtent), it's hidden.
      if (mainAxisDelta < constraints.remainingPaintExtent &&
          mainAxisDelta + paintExtentOf(child) > 0) {
        context.paintChild(child, childOffset);
      }

      child = childAfter(child);
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final list = listOf(null)!;
    properties.add(DiagnosticsNode.message(list.firstChild != null
        ? 'currently live children: ${indexOf(list.firstChild!)} to ${indexOf(list.lastChild!)}'
        : 'no children current live'));
  }

  /// Asserts that the reified child list is not empty and has a contiguous
  /// sequence of indices.
  ///
  /// Always returns true.
  bool debugAssertChildListIsNonEmptyAndContiguous(_PopUpList? popUpList) {
    assert(() {
      final list = listOf(popUpList)!;
      assert(list.firstChild != null);
      var index = indexOf(list.firstChild!);
      var child = childAfter(list.firstChild!);
      while (child != null) {
        index += 1;
        assert(indexOf(child) == index);
        child = childAfter(child);
      }
      return true;
    }());
    return true;
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() {
    final children = <DiagnosticsNode>[];
    for (final popUpList in keys) {
      final list = listOf(popUpList)!;
      if (list.firstChild != null) {
        var child = list.firstChild;
        while (true) {
          final childParentData =
              child!.parentData! as MultiSliverMultiBoxAdaptorParentData;
          children.add(child.toDiagnosticsNode(
              name:
                  'child with popup ${popUpList?.debugId} index ${childParentData.index}'));
          if (child == list.lastChild) {
            break;
          }
          child = childParentData.nextSibling;
        }
      }
      final keepAliveBucket = _keepAliveBucket[popUpList];
      if (keepAliveBucket?.isNotEmpty ?? false) {
        final indices = keepAliveBucket!.keys.toList()..sort();
        for (final index in indices) {
          children.add(keepAliveBucket[index]!.toDiagnosticsNode(
            name:
                'child with popup ${popUpList?.debugId} index $index (kept alive but not laid out)',
            style: DiagnosticsTreeStyle.offstage,
          ));
        }
      }
    }
    return children;
  }

  RenderBox? get firstChild => listOf(null)?.firstChild;

  RenderBox? get lastChild => listOf(null)?.lastChild;
}

class MultiSliverMultiBoxAdaptorParentData extends SliverLogicalParentData
    with
        MultiContainerParentDataMixin<RenderBox, _PopUpList>,
        KeepAliveParentDataMixin {
  /// The index of this child according to the [RenderSliverBoxChildManager].
  int? index;

  @override
  bool get keptAlive => _keptAlive;
  bool _keptAlive = false;

  @override
  String toString() =>
      'index=$index; ${keepAlive == true ? "keepAlive; " : ""}${super.toString()}';
}

abstract class MultiRenderSliverBoxChildManager {
  void createChild(_PopUpList? popUpList, int index,
      {required RenderBox? after});
  void removeChild(_PopUpList? popUpList, RenderBox child);
  double estimateMaxScrollOffset(SliverConstraints constraints,
      {int? firstIndex,
      int? lastIndex,
      double? leadingScrollOffset,
      double? trailingScrollOffset});
  int get childCount;
  void didAdoptChild(RenderBox child);
  void setDidUnderflow(bool value);
  void didStartLayout(_PopUpList? popUpList);
  void didFinishLayout(_PopUpList? popUpList);
  bool debugAssertChildListLocked() => true;
  List<_PopUpList> get listOfPopUps;
}
