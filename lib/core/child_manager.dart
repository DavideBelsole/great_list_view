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
        MultiRenderSliverBoxChildManager,
        _ControllerInterface,
        _ListIntervalInterface {
  /// Creates an element that lazily builds children for the given widget with
  /// support for animations and reordering.
  AnimatedSliverMultiBoxAdaptorElement(
      AnimatedSliverMultiBoxAdaptorWidget widget)
      : super(widget) {
    _childElements[null] = SplayTreeMap<int, Element?>();
  }

  /// Support for the method didChangeDependencies like in [State.didChangeDependencies].
  bool _didChangeDependencies = false;

  @override
  AnimatedSliverMultiBoxAdaptorWidget get widget =>
      super.widget as AnimatedSliverMultiBoxAdaptorWidget;

  @override
  AnimatedRenderSliverMultiBoxAdaptor get renderObject =>
      super.renderObject as AnimatedRenderSliverMultiBoxAdaptor;

  _IntervalManager get _intervalListManager => renderObject.intervalManager;

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
    if (_intervalListManager.hasPendingUpdates) {
      performRebuild();
    }
  }

  /// This function takes the old [index] of a child and calculates the new one by considering
  /// all the pending [updates].
  /// This method can return `null` if the child no longer exists (for example,
  /// all elements of a remove interval disappear when it becomes a resizing interval).
  _ReindexResult oldIndexToNewIndex(int? index, _PopUpList? popUpList) {
    var needsRebuild = false;
    var clearLayoutOffset = false;
    var discardElement = false;

    for (final upd in _intervalListManager.updates) {
      if (upd.popUpList == popUpList) {
        // stessa popup, ci interessa
      } else if (upd.flags.hasPopupDrop && popUpList == upd.toPopUpList) {
        // l'elemento sta per posarsi nella nostra popup, ci interessa
      } else {
        // siamo in un'altra popup, questo update non ci interessa
        continue;
      }

      if (upd.flags.hasPopupDrop && upd.popUpList == popUpList) {
        // l'elemento sta per uscire dalla nostra popup per posarsi in un'altra

        // index è la posizione dell'elemento relativa alla popup, dobbiamo sommare upd.index ch'è la posizione
        // della vecchia popup in cui si inserirà il primo elemento dell'intervallo
        index = index! + upd.index;
        popUpList = upd.toPopUpList; // cambio popup!
        needsRebuild = true;
        clearLayoutOffset = true;
        continue;
      }

      if (index! >= upd.index && index < upd.index + upd.oldBuildCount) {
        // l'indice ricade nell'intervallo di update (il vecchio)
        if (upd.flags.hasPopupDrop) {
          // l'indice ricade in un vecchio intervallo che sta per essere completamente sovrascritto dagli elementi
          // che prevongono da un'altra popup, pertanto l'elemento non esiste più
          index = null;
          // clearLayoutOffset = true;
          break;
        } else if (upd.flags.hasPopupPick) {
          // l'elemento si sta per spostare in un'altra popup
          // index va reso relativo alla nuova popup, pertanto va sotratto la posizione in cui si trovava nella
          // vecchia popup
          index -= upd.index;
          popUpList = upd.toPopUpList; // cambio popup!
          needsRebuild = true;
          clearLayoutOffset = true;
          continue;
        }
        if (index >= upd.index + upd.newBuildCount) {
          // l'elemento non esiste più, ricadeva nella parte finale del vecchio intervallo che era più grande
          // di quello nuovo
          index = null;
          break;
        }
        if (upd.flags.hasClearLayoutOffset) {
          // se c'è il flag CLEAR_LAYOUT_OFFSET....
          if (index != upd.index || !upd.flags.hasKeepFirstLayoutOffset) {
            // azzera l'offset se non è il primo elemento dell'update, oppure se è il primo elemento
            // quest'ultimo non ha il flag kEEP_FIRST_LAYOUT_OFFSET
            clearLayoutOffset = true;
          }
        }

        // l'indice ricade nell'update, pertanto necessita di un rebuild
        needsRebuild = true;

        if (upd.flags.hasDiscardElement) {
          discardElement = true;
        }
      }
      if (index >= upd.index + upd.oldBuildCount) {
        // se l'indice ricade dopo quest'update, l'indice va riadattato di un delta dato dalla lunghezza
        // del nuovo intervallo meno quella del vecchio intervallo (per esempio, se l'update agisce su 4 elementi
        // che vengono convertiti in soli 3 nuovi elementi, il delta da sommare all'indice è -1)
        index += upd.skipCount;
      }
    }
    return _ReindexResult(
        index, needsRebuild, discardElement, clearLayoutOffset, popUpList);
  }

  String _debugChildrenList(SplayTreeMap<int, Element?> cl) {
    final l = <String>[];
    cl.forEach((index, element) => l.add('$index: ${debugElement(element!)}'));
    return "{${l.join(', ')}}";
  }

  Widget? build(int index, {bool measureOnly = false, _PopUpList? popUpList}) {
    if (popUpList == null) {
      final count = _intervalListManager.list.buildCount;
      if (index < 0 || index >= count) return null;
      return _intervalListManager.list.build(this, index, measureOnly);
    } else {
      if (index < 0 || index >= popUpList.popUpBuildCount) return null;
      return popUpList.buildPopUp(this, index, measureOnly);
    }
  }

  MultiSliverMultiBoxAdaptorParentData? _parentDataOf(Element? element) =>
      element?.renderObject?.parentData
          as MultiSliverMultiBoxAdaptorParentData?;

  int? _currentlyUpdatingChildIndex;
  _PopUpList? _currentlyUpdatingPopUpList;

  final Map<_PopUpList?, SplayTreeMap<int, Element?>> _childElements =
      <_PopUpList?, SplayTreeMap<int, Element?>>{};

  RenderBox? _currentBeforeChild;

  Iterable<_PopUpList> get managedPopUpLists =>
      _childElements.keys.whereNotNull();

  SplayTreeMap<int, Element?> get _mainChildElements => _childElements[null]!;

  //
  // ### RenderSliverBoxChildManager implementation
  //

  /// Copied from [SliverMultiBoxAdaptorElement.createChild].
  @override
  void createChild(_PopUpList? popUpList, int index,
      {required RenderBox? after}) {
    assert(_currentlyUpdatingChildIndex == null);
    owner!.buildScope(this, () {
      final childElements = _childElements.putIfAbsent(
          popUpList, () => SplayTreeMap<int, Element?>());
      final insertFirst = after == null;
      assert(insertFirst || childElements[index - 1] != null);
      _currentBeforeChild = insertFirst
          ? null
          : (childElements[index - 1]!.renderObject as RenderBox?);
      Element? newChild;
      try {
        _currentlyUpdatingPopUpList = popUpList;
        _currentlyUpdatingChildIndex = index;
        newChild = updateChild(childElements[index],
            build(index, popUpList: popUpList), _Slot(index, popUpList));
      } finally {
        _currentlyUpdatingChildIndex = null;
        _currentlyUpdatingPopUpList = null;
      }
      if (newChild != null) {
        childElements[index] = newChild;
      } else {
        childElements.remove(index);
      }
    });
  }

  /// Copied from [SliverMultiBoxAdaptorElement.removeChild].
  @override
  void removeChild(_PopUpList? popUpList, RenderBox child) {
    final index = renderObject.indexOf(child);
    final popUpList =
        (child.parentData! as MultiSliverMultiBoxAdaptorParentData).key;
    assert(_currentlyUpdatingPopUpList == null);
    assert(_currentlyUpdatingChildIndex == null);
    assert(index >= 0);
    owner!.buildScope(this, () {
      final childElements = _childElements[popUpList]!;
      assert(childElements.containsKey(index));
      try {
        _currentlyUpdatingPopUpList = popUpList;
        _currentlyUpdatingChildIndex = index;
        final result =
            updateChild(childElements[index], null, _Slot(index, popUpList));
        assert(result == null);
      } finally {
        _currentlyUpdatingChildIndex = null;
        _currentlyUpdatingPopUpList = null;
      }
      childElements.remove(index);
      assert(!childElements.containsKey(index));
    });
  }

  /// Copied from [SliverMultiBoxAdaptorElement.estimateMaxScrollOffset].
  /// The [SliverMultiBoxAdaptorWidget.estimateMaxScrollOffset] method call
  /// has been removed just now.
  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) {
    return renderObject.extrapolateMaxScrollOffset(firstIndex!, lastIndex!,
        leadingScrollOffset!, trailingScrollOffset!, childCount);
  }

  @override
  int get childCount => _intervalListManager.list.buildCount;

  /// Copied from [SliverMultiBoxAdaptorElement.didAdoptChild].
  /// An assertion has been removed to allow adoption of off-list elements.
  @override
  void didAdoptChild(final RenderBox child) {
    if (_creatingDisposableElement) return;
    assert(_currentlyUpdatingChildIndex != null);
    final childParentData =
        child.parentData! as MultiSliverMultiBoxAdaptorParentData;
    childParentData.index = _currentlyUpdatingChildIndex;
    childParentData.key = _currentlyUpdatingPopUpList;
  }

  /// Copied from [SliverMultiBoxAdaptorElement.setDidUnderflow].
  /// The `didUnderflow` variabile is no longer needed.
  @override
  void setDidUnderflow(final bool value) {
    // _didUnderflow = value;
  }

  /// Copied from [SliverMultiBoxAdaptorElement.didStartLayout].
  @override
  void didStartLayout(_PopUpList? popUpList) {
    assert(debugAssertChildListLocked());
  }

  /// Copied from [SliverMultiBoxAdaptorElement.didFinishLayout].
  // TODO: to be changed; firstChild and lastChild should be used and item index conversion applied.
  @override
  void didFinishLayout(_PopUpList? popUpList) {
    assert(debugAssertChildListLocked());
    if (popUpList == null) {
      final firstIndex = _mainChildElements.firstKey() ?? 0;
      final lastIndex = _mainChildElements.lastKey() ?? 0;
      widget.delegate.didFinishLayout(firstIndex, lastIndex);
    }
  }

  /// Copied from [SliverMultiBoxAdaptorElement.debugAssertChildListLocked].
  @override
  bool debugAssertChildListLocked() {
    assert(_currentlyUpdatingChildIndex == null);
    return true;
  }

  //
  // ### RenderObjectElement overrides
  //

  /// Inspired by [SliverMultiBoxAdaptorElement.performRebuild].
  ///
  /// This method is called to process any pending updates (for example, new intervals
  /// have been added, old intervals have changed state, reordering has started, and so on).
  ///
  /// It considers all pending build updates to move each old last rendered child
  /// to its new position.
  ///
  /// It also calls the [_AnimatedRenderSliverMultiBoxAdaptor.didChangeDependencies] method
  /// if a dependency has been changed.
  @override
  void performRebuild() {
    _dbgBegin('performRebuild');
    _intervalListManager.updates.forEach((e) => _dbgPrint(e.toString()));

    if (_didChangeDependencies) {
      renderObject.didChangeDependencies(this);
      _didChangeDependencies = false;
    }

    super.performRebuild();

    assert(_currentlyUpdatingChildIndex == null);
    _currentBeforeChild = null;
    try {
      // moving children will temporary violate the integrity
      renderObject.debugChildIntegrityEnabled = false;

      final results = <_PopUpList?, SplayTreeMap<int, _RebuildResult>>{};
      final removeList = <Element>[];

      final newChildrenMap = <_PopUpList?, SplayTreeMap<int, Element?>>{};

      Element? update(Element? element, _ReindexResult r) {
        if (r.needsRebuild) {
          if (r.discardElement && element != null) {
            _dbgPrint(
                'updating ${debugElement(element)} discard and update...');
            element =
                updateChild(element, null, _Slot(r.newIndex!, r.popUpList));
          } else {
            _dbgPrint('updating ${debugElement(element)} update...');
          }
          _currentlyUpdatingChildIndex = r.newIndex;
          _currentlyUpdatingPopUpList = r.popUpList;
          final widget = build(r.newIndex!, popUpList: r.popUpList);
          element =
              updateChild(element, widget, _Slot(r.newIndex!, r.popUpList))!;
          _currentlyUpdatingChildIndex = null;
          _currentlyUpdatingPopUpList = null;
          _dbgPrint('    ....updated into ${debugElement(element)}');
        } else {
          assert(!r.discardElement);
          final newSlot = _Slot(r.newIndex!, r.popUpList);
          if (newSlot != element?.slot) {
            _dbgPrint(
                'updating ${debugElement(element)} slot only: ${element?.slot} -> $newSlot');
          }
          _currentlyUpdatingChildIndex = r.newIndex;
          _currentlyUpdatingPopUpList = r.popUpList;
          updateChild(element, element!.widget, newSlot);
          _currentlyUpdatingChildIndex = null;
          _currentlyUpdatingPopUpList = null;
        }
        return element;
      }

      // final offsets = <PopUpList, double>{};
      void considerElements(
          _PopUpList? popUpList, SplayTreeMap<int, Element?> childElements) {
        _dbgBegin('considering popUpList=${popUpList?.debugId}');
        _dbgPrint('children=${_debugChildrenList(childElements)}');
        _dbgPrint('renderBoxes=${renderObject.debugRenderBoxes(popUpList)}');
        for (int? index in childElements.keys.toList()) {
          var element = childElements[index]!;

          final r = oldIndexToNewIndex(index!, popUpList);

          if (r.newIndex == null) {
            removeList.add(element);
            _dbgPrint(
                'element ${debugElement(element)} scheduled for removing');
          } else {
            _dbgPrint(
                'element ${debugElement(element)} from pl(${popUpList?.debugId}):$index -> pl(${r.popUpList?.debugId}}):${r.newIndex}');
            results.putIfAbsent(r.popUpList,
                    () => SplayTreeMap<int, _RebuildResult>())[r.newIndex!] =
                _RebuildResult(r, element);
          }
        }
        _dbgEnd();
      }

      _childElements.forEach((popUpList, elements) {
        results.putIfAbsent(
            popUpList, () => SplayTreeMap<int, _RebuildResult>());
        considerElements(popUpList, elements);
      });

      for (final popUpList in results.keys) {
        final newChildren = newChildrenMap.putIfAbsent(
            popUpList, () => SplayTreeMap<int, Element?>());

        _currentBeforeChild = null;

        _dbgBegin('finalizing popUpList=${popUpList?.debugId}');
        for (final index in results[popUpList]!.keys) {
          final rr = results[popUpList]![index]!;
          final r = rr.result;
          var childParentData = _parentDataOf(rr.element);

          if (childParentData != null && r.clearLayoutOffset) {
            _dbgPrint('clearing layout offset of ${debugElement(rr.element)}');
            childParentData.layoutOffset = null;
          }

          _currentlyUpdatingChildIndex = r.newIndex;

          final element = update(rr.element, r)!;

          newChildren[r.newIndex!] = element;

          childParentData = _parentDataOf(element);
          if (r.newIndex == 0) {
            childParentData?.layoutOffset = 0.0;
          }

          if (!childParentData!.keptAlive) {
            _currentBeforeChild = element.renderObject as RenderBox?;
          }
        }

        _childElements.putIfAbsent(popUpList, () => newChildren);
        _childElements[popUpList] = newChildren;
        _dbgPrint(
            'result childrenList: ${_debugChildrenList(_childElements[popUpList]!)}');

        if (newChildren.isEmpty && popUpList != null) {
          _dbgPrint('dismissing popup ${popUpList.debugId}');
          _childElements.remove(popUpList);
        }

        _dbgEnd();
      }

      _dbgBegin('result RenderBoxes');
      for (final popUpList in results.keys) {
        _dbgPrint(
            'popup ${popUpList?.debugId}: ${renderObject.debugRenderBoxes(popUpList)}');
      }
      _dbgEnd();

      for (final element in removeList) {
        _dbgPrint('removing ${debugElement(element)}');
        final slot = element.slot as _Slot;
        _currentlyUpdatingChildIndex = slot.index;
        _currentlyUpdatingPopUpList = slot.popUpList;
        updateChild(element, null, slot);
      }
    } catch (e) {
      _dbgPrint('EXCEPTION!!!!');
    } finally {
      _currentlyUpdatingChildIndex = null;
      _currentlyUpdatingPopUpList = null;
      renderObject.debugChildIntegrityEnabled = true;
      _intervalListManager.updates.clear();
      // renderObject.removeEmptyKeys();
      _dbgEnd();
    }
  }

  /// Copied from [SliverMultiBoxAdaptorElement.insertRenderObjectChild].
  /// This method has been changed to prevent inserting off-list elements into the children list.
  @override
  void insertRenderObjectChild(
      covariant RenderObject child, final _Slot? slot) {
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    if (_creatingDisposableElement) {
      assert(slot == null);
      renderObject.setupParentData(child);
      renderObject.adoptChild(child);
      return;
    }
    //""""""""""""""""""""""""""""""""""""""""""""""""""""""
    assert(_currentlyUpdatingChildIndex == slot!.index);
    // assert(renderObject.debugValidateChild(child)); // l'ho asteriscato in MultiContainerRenderObjectMixin!!!!!!!!!!!!

    // final x = debugRenderBox(child);

    renderObject.insert(_currentlyUpdatingPopUpList, child as RenderBox,
        after: _currentBeforeChild);
    assert(() {
      final childParentData =
          child.parentData! as MultiSliverMultiBoxAdaptorParentData;
      assert(slot!.index == childParentData.index);
      return true;
    }());
  }

  /// Copied from [SliverMultiBoxAdaptorElement.removeRenderObjectChild].
  /// This method has been changed to prevent the removal of unlisted children (eg off-list elements).
  @override
  void removeRenderObjectChild(
      covariant RenderObject child, final _Slot? slot) {
    if (_creatingDisposableElement) {
      assert(slot == null);
      renderObject.dropChild(child);
      return;
    }
    assert(_creatingDisposableElement || _currentlyUpdatingChildIndex != null);
    final childParentData =
        child.parentData! as MultiSliverMultiBoxAdaptorParentData;
    renderObject.remove(childParentData.key, child as RenderBox);
  }

  /// Copied from [SliverMultiBoxAdaptorElement.moveRenderObjectChild].
  /// This method has been changed to prevent assertion errors.
  @override
  void moveRenderObjectChild(covariant RenderObject child, final _Slot? oldSlot,
      final _Slot? newSlot) {
    assert(newSlot != null);
    assert(_currentlyUpdatingChildIndex == newSlot!.index);
    assert(_currentlyUpdatingPopUpList == newSlot!.popUpList);
    renderObject.move(newSlot!.popUpList, child as RenderBox,
        after: _currentBeforeChild);
  }

  //
  // ### Element overrides
  //

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
    final popUpList = _parentDataOf(child)!.key;
    final childElements = _childElements[popUpList]!;
    assert(childElements.containsKey(child.slot));
    childElements.remove(child.slot);
    super.forgetChild(child);
  }

  /// Copied from [SliverMultiBoxAdaptorElement.visitChildren].
  /// This method has been changed to include pop-up elements.
  @override
  void visitChildren(final ElementVisitor visitor) {
    _childElements.values
        .expand((l) => l.values)
        .toList()
        .forEach((e) => visitor.call(e!));
  }

  /// Copied from [SliverMultiBoxAdaptorElement.debugVisitOnstageChildren].
  @override
  void debugVisitOnstageChildren(final ElementVisitor visitor) {
    _mainChildElements.values.cast<Element>().where((Element child) {
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

  // ------------------------------------

  // Searchs and returns the build index of specified item by its [context], if it can be found.
  _Slot? buildIndexFromContext(BuildContext context) {
    if (context is! Element) return null;
    _Slot? slot;
    if (context.slot is! _Slot) {
      context.visitAncestorElements((element) {
        if (element is AnimatedSliverMultiBoxAdaptorElement) return false;
        if (element.slot is _Slot) {
          slot = element.slot as _Slot;
          return false;
        }
        return true;
      });
      if (slot == null || slot is! _Slot) return null;
    } else {
      slot = context.slot as _Slot;
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

  var _creatingDisposableElement = false;

  /// It creates an disposable off-list element built with the specified [widget],
  /// and executes the [callback]. Eventually, the child is disposed.
  void disposableElement(Widget widget, void Function(RenderBox) callback) {
    owner!.lockState(() {
      _currentlyUpdatingChildIndex = null;
      _currentlyUpdatingPopUpList = null;
      _creatingDisposableElement = true;
      var _measuringOffListChild = updateChild(null, widget, null);
      assert(_measuringOffListChild != null);
      callback.call(_measuringOffListChild!.renderObject! as RenderBox);
      _measuringOffListChild = updateChild(_measuringOffListChild, null, null);
      _creatingDisposableElement = false;
      assert(_measuringOffListChild == null);
    });
  }

  //
  // ListIntervalInterface implementation
  //

  @override
  AnimatedSliverChildDelegate get delegate => widget.delegate;

  @override
  bool get isHorizontal => renderObject.constraints.axis == Axis.horizontal;

  @override
  Widget wrapWidget(
      AnimatedWidgetBuilder builder, int index, AnimatedWidgetBuilderData data,
      [bool map = true]) {
    Widget child;
    // if (map) index = _intervalListManager.movedArray.map(index);
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
    renderObject.resizingIntervalUpdated(interval, delta);
  }

  /// Measures the size of a bunch of off-list children up to [count] elements.
  /// You have to provide a [builder] to build the `i`-th widget.
  /// The calculation is asynchronous and can be [cancelled].
  @override
  Future<_Measure> measureItems(
      _Cancelled? cancelled, int count, IndexedWidgetBuilder builder,
      [double startingSize = 0, int startingCount = 0]) async {
    return await renderObject.measureItems(
        cancelled, count, builder, startingSize, startingCount);
  }

  /// Measures the size of the [widget].
  @override
  double measureItem(Widget widget) {
    return renderObject.measureItem(widget);
  }

  @override
  void markNeedsLayout() {
    renderObject.markSafeNeedsLayout();
  }

  @override
  _SizeResult? getItemSizesFromSliverList(int buildFrom, int buildTo) {
    return renderObject.getItemSizesFromSliverList(buildFrom, buildTo);
  }

  //
  // _ControllerInterface implementation
  //

  int _batch = 0;

  /// See [AnimatedListController.batch].
  @override
  void batch(VoidCallback callback) {
    _batch++;
    callback();
    _batch--;
    assert(_batch >= 0);
    if (_batch == 0) _intervalListManager.coordinate();
  }

  /// See [AnimatedListController.notifyInsertedRange].
  @override
  void notifyInsertedRange(int from, int count) =>
      _notifyReplacedRange(from, 0, count, null);

  /// See [AnimatedListController.notifyRemovedRange].
  @override
  void notifyRemovedRange(
          int from, int count, AnimatedWidgetBuilder removedItemBuilder) =>
      _notifyReplacedRange(from, count, 0, removedItemBuilder);

  /// See [AnimatedListController.notifyReplacedRange].
  @override
  void notifyReplacedRange(int from, int removeCount, int insertCount,
          AnimatedWidgetBuilder removedItemBuilder) =>
      _notifyReplacedRange(from, removeCount, insertCount, removedItemBuilder);

  void _notifyReplacedRange(int from, int removeCount, int insertCount,
      AnimatedWidgetBuilder? removedItemBuilder) {
    _intervalListManager.notifyReplacedRange(
        from, removeCount, insertCount, removedItemBuilder);
    if (_batch == 0) _intervalListManager.coordinate();
  }

  /// See [AnimatedListController.notifyChangedRange].
  @override
  void notifyChangedRange(
      int from, int count, final AnimatedWidgetBuilder changedItemBuilder) {
    _intervalListManager.notifyChangedRange(from, count, changedItemBuilder);
    if (_batch == 0) _intervalListManager.coordinate();
  }

  /// See [AnimatedListController.notifyMovedRange].
  @override
  void notifyMovedRange(int from, int count, int newIndex) {
    _intervalListManager.notifyMovedRange(from, count, newIndex);
    if (_batch == 0) _intervalListManager.coordinate();
  }

  /// See [AnimatedListController.notifyStartReorder].
  @override
  bool notifyStartReorder(BuildContext context, double dx, double dy) {
    return renderObject.reorderStart(context, dx, dy);
  }

  /// See [AnimatedListController.notifyUpdateReorder].
  @override
  void notifyUpdateReorder(double dx, double dy) {
    renderObject.reorderUpdate(dx, dy);
  }

  /// See [AnimatedListController.notifyStopReorder].
  @override
  void notifyStopReorder(bool cancel) {
    renderObject.reorderStop(cancel);
  }

  /// See [AnimatedListController.computeItemBox].
  @override
  Rect? computeItemBox(int index, bool absolute) {
    return renderObject.computeItemBox(index, absolute, false);
  }

  /// See [AnimatedListController.getItemVisibleSize].
  @override
  _PercentageSize? getItemVisibleSize(int index) {
    final box = renderObject.computeItemBox(index, true, true);
    if (box != null) {
      final c = renderObject.constraints;
      final v1 = c.scrollOffset +
          c.precedingScrollExtent -
          (c.viewportMainAxisExtent - c.remainingPaintExtent);
      final v2 = v1 + c.viewportMainAxisExtent;

      final r1 = (isHorizontal ? box.left : box.top).clamp(v1, v2);
      final r2 = (isHorizontal ? box.right : box.bottom).clamp(v1, v2);
      return _PercentageSize(
          math.max(0.0, r2 - r1), (isHorizontal ? box.width : box.height));
    }
    return null;
  }

  @override
  _Measure estimateLayoutOffset(int buildIndex, int childCount,
      {double? time, _MovingPopUpList? popUpList}) {
    return renderObject.estimateLayoutOffset(
        buildIndex, childCount, time, popUpList);
  }

  RenderBox? renderBoxAt(int buildIndex) =>
      _childElements[null]?[buildIndex]?.renderObject as RenderBox?;

  @override
  void reorderCancel() => renderObject.reorderStop(true);

  @override
  void test() {
    _intervalListManager.test();
  }

  @override
  List<_PopUpList> get listOfPopUps => _intervalListManager.listOfPopUps;
}

/*
 *
 */

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
      this.clearLayoutOffset, this.popUpList); //, this.droppedBy);

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

  /// La [_PopUpList] nella quale il child ricadrà a valle degli update.
  final _PopUpList? popUpList;

  @override
  String toString() => '(${[
        'newIndex=$newIndex',
        if (needsRebuild) 'NEEDS_REBUILD',
        if (discardElement) 'DISCARD_ELEMENT',
        if (clearLayoutOffset) 'CLEAR_LAYOUT_OFFSET',
        if (popUpList != null) 'popUpList=$popUpList',
      ].join(', ')})';
}

class _RebuildResult {
  final _ReindexResult result;
  final Element element;

  _PopUpList? get toPopUpList => result.popUpList;

  const _RebuildResult(this.result, this.element);
}

class _Slot {
  final int index;
  final _PopUpList? popUpList;

  const _Slot(this.index, this.popUpList);

  @override
  bool operator ==(Object? s) =>
      s is _Slot && s.index == index && s.popUpList == popUpList;

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() => '($index,${popUpList?.debugId})';
}

/*
 * Controller
 */

abstract class _ControllerInterface {
  void notifyChangedRange(
      int from, int count, final AnimatedWidgetBuilder changeItemBuilder);

  void notifyInsertedRange(int from, int count);

  void notifyRemovedRange(
      int from, int count, final AnimatedWidgetBuilder removeItemBuilder);

  void notifyReplacedRange(int from, int removeCount, final int insertCount,
      final AnimatedWidgetBuilder removeItemBuilder);

  void notifyMovedRange(int from, int count, int newIndex);

  void batch(VoidCallback callback);

  bool notifyStartReorder(BuildContext context, double dx, double dy);

  void notifyUpdateReorder(double dx, double dy) {}

  void notifyStopReorder(bool cancel) {}

  Rect? computeItemBox(int index, bool absolute);

  _PercentageSize? getItemVisibleSize(int index);

  void test() {}
}

/// Use this controller to notify to the [AnimatedListView] about changes in your underlying list and more.
class AnimatedListController {
  _ControllerInterface? _interface;

  /// Notifies the [AnimatedListView] that a range starting from [from] and [count] long
  /// has been modified. Call this method after actually you have updated your list.
  /// A new builder [changeItemBuilder] has to be provided in order to build the old
  /// items when animating.

  void notifyChangedRange(
      int from, int count, AnimatedWidgetBuilder changeItemBuilder) {
    assert(_debugAssertBinded());
    _interface!.notifyChangedRange(from, count, changeItemBuilder);
  }

  /// Notifies the [AnimatedListView] that a new range starting from [from] and [count] long
  /// has been inserted. Call this method after actually you have updated your list.

  void notifyInsertedRange(int from, int count) {
    assert(_debugAssertBinded());
    _interface!.notifyInsertedRange(from, count);
  }

  /// Notifies the [AnimatedListView] that a range starting from [from] and [count] long
  /// has been removed. Call this method after actually you have updated your list.
  /// A new builder [removeItemBuilder] has to be provided in order to build the removed
  /// items when animating.
  void notifyRemovedRange(
      int from, int count, AnimatedWidgetBuilder removeItemBuilder) {
    assert(_debugAssertBinded());
    _interface!.notifyRemovedRange(from, count, removeItemBuilder);
  }

  /// Notifies the [AnimatedListView] that a range starting from [from] and [removeCount] long
  /// has been replaced with a new [insertCount] long range. Call this method after
  /// you have updated your list.
  /// A new builder [removeItemBuilder] has to be provided in order to build the replaced
  /// items when animating.
  void notifyReplacedRange(int from, int removeCount, int insertCount,
      AnimatedWidgetBuilder removeItemBuilder) {
    assert(_debugAssertBinded());
    _interface!
        .notifyReplacedRange(from, removeCount, insertCount, removeItemBuilder);
  }

  /// Notifies the [AnimatedListView] that a range starting from [from] and [count] long
  /// has been moved to a new location, at [newIndex] position (the new index considers the interval just removed).
  /// Call this method after you have updated your list.
  void notifyMovedRange(
    int from,
    int count,
    int newIndex,
  ) {
    assert(_debugAssertBinded());
    _interface!.notifyMovedRange(from, count, newIndex);
  }

  /// If more changes to the underlying list need be applied in a row, it is more efficient
  /// to call this method and notify all the changes within the callback.
  void batch(VoidCallback callback) {
    assert(_debugAssertBinded());
    _interface!.batch(callback);
  }

  /// Notifies the [AnimatedListView] that a new reoder has begun.
  /// The [context] has to be provided to help [AnimatedListView] to locate the item
  /// to be picked up for reordering.
  /// The attributs [dx] and [dy] are the coordinates relative to the position of the item.
  ///
  /// Use this method only if you have decided not to use the
  /// [AnimatedSliverChildBuilderDelegate.addLongPressReorderable] attribute or the
  /// [LongPressReorderable] widget (for example if you want to reorder using your
  /// custom drag handles).
  ///
  /// This method could return `false` indicating that the reordering cannot be started.
  bool notifyStartReorder(BuildContext context, double dx, double dy) {
    assert(_debugAssertBinded());
    return _interface!.notifyStartReorder(context, dx, dy);
  }

  /// Notifies the [AnimatedListView] that the dragged item has moved.
  /// The attributs [dx] and [dy] are the coordinates relative to the original position
  /// of the item.
  ///
  /// Use this method only if you have decided not to use the
  /// [AnimatedSliverChildBuilderDelegate.addLongPressReorderable] attribute or the
  /// [LongPressReorderable] widget (for example if you want to reorder using your
  /// custom drag handles).
  void notifyUpdateReorder(double dx, double dy) {
    assert(_debugAssertBinded());
    _interface!.notifyUpdateReorder(dx, dy);
  }

  /// Notifies the [AnimatedListView] that the reorder has finished or cancelled
  /// ([cancel] set to `true`).
  ///
  /// Use this method only if you have decided not to use the
  /// [AnimatedSliverChildBuilderDelegate.addLongPressReorderable] attribute or the
  /// [LongPressReorderable] widget (for example if you want to reorder using your
  /// custom drag handles).
  void notifyStopReorder(bool cancel) {
    assert(_debugAssertBinded());
    _interface!.notifyStopReorder(cancel);
  }

  /// Calculates the box (in pixels) of the item indicated by the [index] provided.
  ///
  /// The index of the item refers to the index of the underlying list.
  ///
  /// If [absolute] is `false` the offset is relative to the upper edge of the sliver,
  /// otherwise the offset is relative to the upper edge of the topmost sliver.
  ///
  /// For one, you might pass the result to the [ScrollController.jumpTo] or [ScrollController.animateTo] methods
  /// of a [ScrollController] to scroll to the desired item.
  ///
  /// The method returns `null` if the box cannot be calculated. This happens when the item isn't yet diplayed
  /// (because animations are still in progress) or when the state of the list view has been changed via notifications
  /// but these changes are not yet taken into account.
  ///
  /// Be careful! This method calculates the item box starting from items currently built in the viewport, therefore,
  /// if the desired item is very far from them, the method could take a long time to return the result
  /// since it must measure all the intermediate items that are among those of the viewport and the desired one.
  Rect? computeItemBox(int index, [bool absolute = false]) {
    assert(_debugAssertBinded());
    return _interface!.computeItemBox(index, absolute);
  }

  /// Returns the size of the visible part (in pixels) of a certain item in the list view.
  ///
  /// The index of the item refers to the index of the underlying list.
  ///
  /// The method returns `null` if the box of the item cannot be calculated. This happens when the item
  /// isn't yet diplayed or when the state of the list view has been changed via notifications
  /// but these changes are not yet taken into account.
  _PercentageSize? getItemVisibleSize(int index) {
    assert(_debugAssertBinded());
    return _interface!.getItemVisibleSize(index);
  }

  void _setInterface(_ControllerInterface interface) {
    if (_interface != null) {
      throw FlutterError(
          'You are trying to bind this controller to multiple animated list views.\n'
          'A $runtimeType can only be binded to one list view at a time.');
    }
    _interface = interface;
  }

  void _unsetInterface(_ControllerInterface interface) {
    if (_interface == interface) _interface = null;
  }

  BuildContext get context => _interface! as BuildContext;

  bool _debugAssertBinded() {
    assert(() {
      if (_interface == null) {
        throw FlutterError(
          'This controller was used before it was connected to an animated list view.\n'
          'Make sure you passed this instance to the listController attribute of an AutomaticAnimatedListView, AnimatedListView, AnimatedSliverList or AnimatedSliverFixedExtentList.',
        );
      }
      return true;
    }());
    return true;
  }

  void test() {
    _interface?.test();
  }
}
