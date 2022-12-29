library great_list_view.other;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:great_list_view/core/core.dart'
    show AnimatedListController, AnimatedListView, AnimatedWidgetBuilderData;

const int _kWindowSize = 80;

bool _kEquals(dynamic a, dynamic b) => a == b;

/// This special builder has to be used to allow [TreeListAdapter] to notify automatically
/// the [AnimatedListView] connected to the [TreeListAdapter.controller].
/// The [adapter] can refer to the whole tree or only to a specific section (subtree) of it.
/// The [index] is the list index referred to the tree o subtree.
typedef AnimatedListTreeBuilder<T> = Widget Function(BuildContext context,
    TreeListAdapter<T> adapter, int index, AnimatedWidgetBuilderData data);

/// Adapter that takes a tree model as input and transforms it into a linear list.
///
/// You have to specify the data type `T` representing its nodes.
class TreeListAdapter<T> {
  /// Creates a new tree adapter.
  ///
  /// A [root] node has to be specified.
  ///
  /// The model consists of the following callbacks:
  /// - [parentOf] returns the parent of a node;
  /// - [childrenCount] returns the count of the children belonging to a node;
  /// - [childAt] returns the child node of a parent node at a specific position;
  /// - [isNodeExpanded] returns `true` if the node is expanded, `false` if it is collapsed;
  /// - [indexOfChild] returns the position of a child node with respect to the parent node;
  /// - [equals] returns `true` if two nodes are equal.
  ///
  /// If [includeRoot] is set to `false`, the root node is not mapped as the first item of the linear list;
  /// the default value is `true`.
  ///
  /// You can specify through [windowSize] the size of the circular list used to cache the nodes;
  /// by default `80` is used.
  ///
  /// You can also pass through [initialCount] the initial count of all nodes if it is known,
  /// to prevent a full scan of the entire tree to calculate its length.
  ///
  /// You can also pass through [startingLevel] the hierarchy level of the root node; if omitted,
  /// `0` is used.
  ///
  /// This adapter can also be connected to an [AnimatedListController] via [controller] to automatically send
  /// change notifications when the tree is modified. In this case a [builder] must also be provided in order
  /// to build changed/removed nodes.
  TreeListAdapter({
    required this.root,
    required this.parentOf,
    required this.childrenCount,
    required this.childAt,
    required this.isNodeExpanded,
    required this.indexOfChild,
    this.equals = _kEquals,
    this.includeRoot = true,
    this.windowSize = _kWindowSize,
    int? initialCount,
    this.startingLevel = 0,
    this.controller,
    this.builder,
  })  : assert(controller == null || builder != null),
        _list = _CircularList(windowSize) {
    if (initialCount != null) {
      assert(initialCount == count);
      _count = initialCount;
    }
  }

  final T Function(T node) parentOf;
  final int Function(T node) childrenCount;
  final T Function(T node, int index) childAt;
  final bool Function(T node) isNodeExpanded;
  final int Function(T parent, T node) indexOfChild;
  final bool Function(T nodeA, T nodeB) equals;

  final bool includeRoot;
  final int windowSize;
  final int startingLevel;

  final AnimatedListController? controller;
  final AnimatedListTreeBuilder<T>? builder;

  T root;

  // the list never contains the root node, although it is displayed
  final _CircularList<T> _list;

  int _offset = 0, _count = -1;

  int get _endOffset => _offset + windowSize;

  /// Returns a sub tree starting from the [node] as its root node.
  ///
  /// If [includeRoot] is set to `true`, the root [node] will be displayed as the first item;
  /// by default is `false`.
  ///
  /// If [alwaysExpandRoot] is set to `true` (as by default), the root [node] is considered expanded
  /// despite the [isNodeExpanded] callback.
  ///
  /// If [keepCurrentLevel] is set to `true` (as by default), the [node] will keep its current
  /// hierarchy level also in the sub tree.
  ///
  /// You can assign a new window size for the subtree via the [windowSize] parameter. If you set
  /// this to `null`, the sub tree will inherit the same [windowSize] of the original tree. By default
  /// `80` is used.
  TreeListAdapter<T> subTreeOf(T node,
      [bool includeRoot = false,
      bool alwaysExpandRoot = true,
      bool keepCurrentLevel = true,
      int? windowSize = _kWindowSize]) {
    var _this = this;
    return TreeListAdapter(
      root: node,
      parentOf: (n) => _this.parentOf(n),
      childrenCount: childrenCount,
      childAt: childAt,
      isNodeExpanded: (n) => (alwaysExpandRoot && equals(n, node))
          ? true
          : _this.isNodeExpanded(n),
      indexOfChild: indexOfChild,
      equals: equals,
      includeRoot: includeRoot,
      windowSize: windowSize ?? _this.windowSize,
      startingLevel:
          keepCurrentLevel ? (levelOf(node) + (includeRoot ? 0 : 1)) : 0,
    );
  }

  /// Returns the number of items needed to build the entire tree as a list view.
  int get count {
    if (_count < 0) {
      _count = _countSubNodesOf(root);
      if (includeRoot) _count++;
    }
    return _count;
  }

  /// Count how many items are needed to show the [node] and its children as a list view,
  /// taking into account when nodes are collapsed or not.
  int countSizeOf(T node) {
    var n = 1;
    if (isNodeExpanded(node)) n += _countSubNodesOf(node);
    return n;
  }

  /// Count how many items are needed to show the children of the [node] as a list view.
  ///
  /// If [treatAsAllExpanded] is set to `true`, descendants will be treated
  /// as if they were always expanded, otherwise the current expand status will be
  /// considered.
  int _countSubNodesOf(T node, [bool treatAsAllExpanded = false]) {
    final n = childrenCount(node);
    var r = n;
    for (var i = 0; i < n; i++) {
      final child = childAt(node, i);
      if (isNodeExpanded(child) || treatAsAllExpanded) {
        r += _countSubNodesOf(child);
      }
    }
    return r;
  }

  /// Returns `true` if the specified [node] is the root node. The calback [equals] will be invoked.
  bool isRootNode(T node) => equals(node, root);

  /// Returns `true` if the specified [node] is a leaf node, that is without children.
  bool isLeaf(T node) => childrenCount(node) == 0;

  /// Calculates the hierarchy level of the [node], also taking into account [startingLevel].
  ///
  /// You could use this value to display the item with a horizontal shifted position.
  int levelOf(T node) {
    var level = includeRoot ? startingLevel : startingLevel - 1;
    for (var n = node; !isRootNode(n); n = parentOf(n)) {
      level++;
    }
    return level;
  }

  int _ensureIndex(T node, int? index) {
    assert((index == null && nodeToIndex(node) != null) ||
        (index != null && nodeToIndex(node) == index));
    return index ?? nodeToIndex(node)!;
  }

  IntRange? _notify(
    int from,
    int to,
    void Function()? fn,
    void Function(int from, int to)? cb,
    void Function(int from, int count)? controllerCb,
  ) {
    cb?.call(from, to);

    final count = to - from;
    if (includeRoot) from++;

    fn?.call();

    if (controller != null) {
      controllerCb?.call(from, count);
      return null;
    } else {
      return IntRange(from, count);
    }
  }

  /// This method has to be called when the [node] is about to be expanded.
  ///
  /// Pass your [expandFn] function that takes care of actually expanding the node as data layer.
  ///
  /// If you also have the index of the corresponding list view item, that's better
  /// pass it via the [index] attribute, otherwise you can just omit it.
  ///
  /// If [dontNotifyController] is set to `false` (as default), the [controller] will be automatically
  /// notified about the change. If [dontNotifyController] is set to `true`, an [IntRange] will be
  /// returned to indicate the range of list view items involved in the modification.
  ///
  /// Set [updateNode] to `true` if you want to notify the [controller] to rebuild the expanded node.
  IntRange? notifyNodeExpanding(T node, void Function() expandFn,
      {int? index,
      bool dontNotifyController = false,
      bool updateNode = false}) {
    index = _ensureIndex(node, index);
    final from = index + (includeRoot ? 0 : 1); // first child index
    final to = from + _countSubNodesOf(node);
    return _notify(
        from,
        to,
        expandFn,
        _insert,
        dontNotifyController
            ? null
            : (from, count) {
                controller!.batch(() {
                  controller!.notifyInsertedRange(from, count);
                  if (updateNode) {
                    controller!.notifyChangedRange(
                        from - 1,
                        1,
                        (context, idx, data) =>
                            builder!.call(context, this, from - 1, data));
                  }
                });
              });
  }

  /// This method has to be called when the [node] is about to be collapsed.
  ///
  /// Pass your [collapseFn] function that takes care of actually collapsing the node as data layer.
  ///
  /// If you also have the index of the corresponding list view item, that's better
  /// pass it via the [index] attribute, otherwise you can just omit it.
  ///
  /// If [dontNotifyController] is set to `false` (as default), the [controller] will be automatically
  /// notified about the change. If [dontNotifyController] is set to `true`, an [IntRange] will be
  /// returned to indicate the range of list view items involved in the modification.
  ///
  /// Set [updateNode] to `true` if you want to notify the [controller] to rebuild the collapsed node.
  IntRange? notifyNodeCollapsing(T node, void Function() collapseFn,
      {int? index,
      bool dontNotifyController = false,
      bool updateNode = false}) {
    index = _ensureIndex(node, index);
    final from = index + (includeRoot ? 0 : 1); // first child index
    final to = from + _countSubNodesOf(node);
    return _notify(
        from,
        to,
        collapseFn,
        _remove,
        dontNotifyController
            ? null
            : (from, count) {
                assert(builder != null);
                final subAdapter = subTreeOf(node);
                controller!.batch(() {
                  controller!.notifyRemovedRange(
                      from,
                      count,
                      (context, idx, data) =>
                          builder!.call(context, subAdapter, idx, data));
                  if (updateNode) {
                    controller!.notifyChangedRange(
                        from - 1,
                        1,
                        (context, idx, data) =>
                            builder!.call(context, this, from - 1, data));
                  }
                });
              });
  }

  /// This method has to be called when the new subtree [newSubTree] is about to be inserted
  /// as child of the [parentNode] at the list [position].
  ///
  /// Pass your [insertFn] function that takes care of actually inserting the node as data layer.
  ///
  /// If you also have the parent's index of the corresponding list view item, that's better
  /// pass it via the [index] attribute, otherwise you can just omit it.
  ///
  /// If [dontNotifyController] is set to `false` (as default), the [controller] will be automatically
  /// notified about the insertion. If [dontNotifyController] is set to `true`, an [IntRange] will be
  /// returned to indicate the range of list view items involved in the modification.
  ///
  /// Set [updateParentNode] to `true` if you want to notify the [controller] to rebuild the
  /// parent node involved.
  IntRange? notifyNodeInserting(
      T newSubTree, T parentNode, int position, void Function() insertFn,
      {int? index,
      bool dontNotifyController = false,
      bool updateParentNode = false}) {
    assert(newSubTree != null && parentNode != null);
    assert(position >= 0 && position <= childrenCount(parentNode));
    if (!isNodeExpanded(parentNode)) {
      insertFn.call();
      return null;
    }
    index = _ensureIndex(parentNode, index);
    var from = index + (includeRoot ? 0 : 1); // first child index
    for (var i = 0; i < position; i++) {
      from += countSizeOf(childAt(parentNode, i));
    }
    final to = from + countSizeOf(newSubTree);
    return _notify(
        from,
        to,
        insertFn,
        _insert,
        dontNotifyController
            ? null
            : (from, count) {
                controller!.batch(() {
                  controller!.notifyInsertedRange(from, count);
                  if (updateParentNode) {
                    final parentNode = parentOf(newSubTree);
                    if (parentNode != null) {
                      final parentIndex = nodeToIndex(parentNode);
                      if (parentIndex != null) {
                        controller!.notifyChangedRange(
                            parentIndex,
                            1,
                            (context, idx, data) => builder!
                                .call(context, this, parentIndex, data));
                      }
                    }
                  }
                });
              });
  }

  /// This method has to be called when the [node] is about to be removed.
  ///
  /// Pass your [removeFn] function that takes care of actually removing the node as data layer.
  ///
  /// If you also have the index of the corresponding list view item, that's better
  /// pass it via the [index] attribute, otherwise you can just omit it.
  ///
  /// If [dontNotifyController] is set to `false` (as default), the [controller] will be automatically
  /// notified about the removal. If [dontNotifyController] is set to `true`, an [IntRange] will be
  /// returned to indicate the range of list view items involved in the modification.
  ///
  /// Set [updateParentNode] to `true` if you want to notify the [controller] to rebuild the
  /// parent node involved.
  IntRange? notifyNodeRemoving(T node, void Function() removeFn,
      {int? index,
      bool dontNotifyController = false,
      bool updateParentNode = false}) {
    assert(!equals(node, root)); // root cannot be removed!
    index = _ensureIndex(node, index);
    final from = index - (includeRoot ? 1 : 0);
    final to = from + countSizeOf(node);
    return _notify(
        from,
        to,
        removeFn,
        _remove,
        dontNotifyController
            ? null
            : (from, count) {
                assert(builder != null);
                final subAdapter = subTreeOf(node, true, isNodeExpanded(node));
                controller!.batch(() {
                  controller!.notifyRemovedRange(
                      from,
                      count,
                      (context, idx, data) =>
                          builder!.call(context, subAdapter, idx, data));
                  if (updateParentNode) {
                    final parentNode = parentOf(node);
                    if (parentNode != null) {
                      final parentIndex = nodeToIndex(parentNode);
                      if (parentIndex != null) {
                        controller!.notifyChangedRange(
                            parentIndex,
                            1,
                            (context, idx, data) => builder!
                                .call(context, this, parentIndex, data));
                      }
                    }
                  }
                });
              });
  }

  /// This method has to be called when a node is about to be moved.
  ///
  /// Both the old and the new list index have to be passed via the [fromIndex] and [toIndex] parameters.
  ///
  /// The new hirearchy [level] of the moved node has to be specified too.
  ///
  /// Pass your [removeFn] function that takes care of actually removing the node from its
  /// original position as data layer.
  ///
  /// Pass your [insertFn] function that takes care of actually inserting the node to its
  /// new position as data layer.
  ///
  /// Set [updateParentNodes] to `true` if you want to notify the [controller] to rebuild the
  /// parent nodes involved.
  void notifyNodeMoving(
      int fromIndex,
      int toIndex,
      int level,
      void Function(T pNode, T removeNode) removeFn,
      void Function(T pNode, T insertNode, int index) insertFn,
      {bool updateParentNodes = false}) {
    assert(getPossibleLevelsOfMove(fromIndex, toIndex).isIn(level));

    final myself = indexToNode(fromIndex);
    assert(isLeaf(myself) || !isNodeExpanded(myself));

    late T prevNode;
    var i = (toIndex > fromIndex) ? toIndex : toIndex - 1;
    if (i == -1) {
      assert(!includeRoot);
      prevNode = root;
    } else {
      prevNode = indexToNode(i);
    }

    final oldParentNode = parentOf(myself);

    final i1 = nodeToIndex(oldParentNode);

    var prevLevel = levelOf(prevNode);

    T pNode;
    int pos;

    if (level == prevLevel + 1) {
      pos = 0;
      pNode = prevNode;
    } else {
      assert(level <= prevLevel);
      pNode = parentOf(prevNode);
      while (level < prevLevel) {
        prevNode = pNode;
        pNode = parentOf(prevNode);
        prevLevel--;
      }
      pos = indexOfChild(pNode, prevNode) + 1;
    }

    final i2 = nodeToIndex(pNode);

    notifyNodeRemoving(myself, () => removeFn(oldParentNode, myself),
        dontNotifyController: true);

    notifyNodeInserting(myself, pNode, pos, () => insertFn(pNode, myself, pos),
        dontNotifyController: true);

    if (updateParentNodes) {
      controller!.batch(() {
        if (i1 != null) {
          controller!.notifyChangedRange(i1, 1,
              (context, idx, data) => builder!.call(context, this, i1, data));
        }
        if (i2 != null) {
          controller!.notifyChangedRange(i2, 1,
              (context, idx, data) => builder!.call(context, this, i2, data));
        }
      });
    }
  }

  /// Call this method when the tree has been completly changed.
  void notifyTreeChanged([T? root, int? initialCount]) {
    _list.clear();
    if (root != null) this.root = root;
    _count = -1;
    _offset = 0;
    if (initialCount != null) {
      assert(initialCount == count);
      _count = initialCount;
    }
  }

  void _remove(int from, int to /* excluded */) {
    assert(from <= to);
    if (from == to) return;
    _count -= to - from;
    if (from >= _endOffset) return;
    if (to <= _offset) {
      _offset -= to - from;
    } else if (from <= _offset && to >= _endOffset) {
      _list.clear();
    } else {
      _list.remove(math.max(from, _offset) - _offset,
          math.min(to, _endOffset) - _offset);
    }
  }

  void _insert(int from, int to /* excluded */) {
    assert(from <= to);
    if (from == to) return;
    _count += to - from;
    if (from >= _endOffset) return;
    if (to <= _offset) {
      _offset += to - from;
    } else if (from <= _offset && to >= _endOffset) {
      _list.clear();
    } else {
      _list.insert(math.max(from, _offset) - _offset,
          math.min(to, _endOffset) - _offset);
    }
  }

  T? _cachedNode(int index) =>
      (index < _offset || index >= _endOffset) ? null : _list[index - _offset];

  void _cacheNode(int index, T node) {
    if (index < _offset) {
      _list.shift(index - _offset);
      _offset = index;
    } else if (index >= _endOffset) {
      _list.shift(index - _endOffset + 1);
      _offset = index - windowSize + 1;
    }
    _list[index - _offset] = node;
  }

  /// Returns the index of the corresponding list item of the specified [node].
  ///
  /// If the node is not present in the tree, `null` is returned.
  int? nodeToIndex(T node) {
    if (equals(node, root)) return (includeRoot ? 0 : -1);
    for (var i = 0; i < windowSize; i++) {
      if (_list[i] != null && equals(_list[i]!, node)) {
        return i + _offset + (includeRoot ? 1 : 0);
      }
    }
    final i = _searchNode(node, root, includeRoot ? 0 : -1);
    if (i < 0) return -i - 1;
    return null;
  }

  int _searchNode(T nodeToSearch, T node, int index) {
    if (equals(nodeToSearch, node)) return -index - 1;
    if (!isNodeExpanded(node)) return index;
    final n = childrenCount(node);
    for (var i = 0; i < n; i++) {
      final child = childAt(node, i);
      index = _searchNode(nodeToSearch, child, ++index);
      if (index < 0) return index;
    }
    return index;
  }

  /// Returns the node corresponding to the specified list item [index].
  T indexToNode(int index) {
    assert(index >= 0 && index < count);
    if (includeRoot) {
      if (index == 0) return root;
      index--;
    }
    var node = _cachedNode(index);
    if (node != null) return node;
    var i = index, j = index;
    bool next;
    do {
      next = false;
      if (--i >= _offset) {
        next = true;
        node = _cachedNode(i);
        if (node != null) {
          _iterateForward(node, i, index);
          node = _cachedNode(index)!;
          return node;
        }
      }
      if (++j < _endOffset) {
        next = true;
        node = _cachedNode(j);
        if (node != null) {
          _iterateBackward(node, j, index);
          node = _cachedNode(index)!;
          return node;
        }
      }
    } while (next);
    _iterateForward(root, -1, index);
    node = _cachedNode(index)!;
    return node;
  }

  void _iterateForward(T node, int index, int toIndex) {
    index = _iterateForwardDescendants(node, index, toIndex);
    if (index >= toIndex) return;
    while (index < toIndex) {
      final parent = parentOf(node);
      final n = childrenCount(parent);
      var j = indexOfChild(parent, node);
      assert(j >= 0 && j < n);
      for (j++; j < n; j++) {
        final child = childAt(parent, j);
        _cacheNode(++index, child);
        if (index >= toIndex) return;
        index = _iterateForwardDescendants(child, index, toIndex);
        if (index >= toIndex) return;
      }
      node = parent;
    }
  }

  int _iterateForwardDescendants(T node, int index, int toIndex) {
    if (index < toIndex && isNodeExpanded(node)) {
      final n = childrenCount(node);
      for (var i = 0; i < n; i++) {
        final child = childAt(node, i);
        _cacheNode(++index, child);
        if (index >= toIndex) break;
        index = _iterateForwardDescendants(child, index, toIndex);
        if (index >= toIndex) break;
      }
    }
    return index;
  }

  void _iterateBackward(T node, int index, int toIndex) {
    while (index > toIndex) {
      final parent = parentOf(node);
      final n = childrenCount(parent);
      var j = indexOfChild(parent, node);
      assert(j >= 0 && j < n);
      for (j--; j >= 0; j--) {
        final child = childAt(parent, j);
        index = _iterateBackwardDescendants(child, index, toIndex);
        if (index <= toIndex) return;
      }
      _cacheNode(--index, parent);
      node = parent;
    }
  }

  int _iterateBackwardDescendants(T node, int index, int toIndex) {
    if (isNodeExpanded(node)) {
      final n = childrenCount(node);
      for (var i = n - 1; i >= 0; i--) {
        final child = childAt(node, i);
        index = _iterateBackwardDescendants(child, index, toIndex);
        if (index <= toIndex) return index;
      }
    }
    _cacheNode(--index, node);
    return index;
  }

  /// Returns the last child node of the parent [node].
  T lastChildrenOf(T node) => childAt(node, childrenCount(node) - 1);

  /// Returns `true` if the [node] descends from [parentNode] (ie has it as its parent or ancestor).
  bool descendsFrom(T parentNode, T node) {
    for (var n = parentNode; !isRootNode(n); n = parentOf(n)) {
      if (equals(node, n)) return true;
    }
    return false;
  }

  /// Returns a range of possibile hierarchy levels where, by moving the node from the specified
  /// position [fromIndex] to the  positiion [toIndex], the latter could occupy.
  IntRange getPossibleLevelsOfMove(int fromIndex, int toIndex) {
    assert(fromIndex >= 0 && fromIndex < count);
    assert(toIndex >= 0 && toIndex < count);
    assert(toIndex != 0 || !includeRoot);

    final myself = indexToNode(fromIndex);
    assert(isLeaf(myself) || !isNodeExpanded(myself));

    var i = (toIndex > fromIndex) ? toIndex : toIndex - 1;
    if (i == -1) {
      assert(!includeRoot);
      return IntRange(0, 1);
    }
    var prevNode = indexToNode(i);

    int fromLevel, toLevel;
    if (!isLeaf(prevNode) && isNodeExpanded(prevNode)) {
      toLevel = levelOf(prevNode) + 1;
      fromLevel = toLevel;
      if (!isRootNode(prevNode)) {
        var pNode = parentOf(prevNode);
        if (fromIndex == toIndex &&
            childrenCount(prevNode) == 1 &&
            equals(childAt(prevNode, 0), myself)) {
          pNode = prevNode;
          prevNode = myself;

          while (!isRootNode(prevNode) && fromLevel > (includeRoot ? 1 : 0)) {
            final last = lastChildrenOf(pNode);
            if (!equals(last, prevNode)) {
              break;
            }
            fromLevel--;
            prevNode = pNode;
            pNode = parentOf(prevNode);
          }
        }
      }
    } else {
      toLevel = levelOf(prevNode);
      fromLevel = toLevel;
      if (isLeaf(prevNode)) toLevel++;
      var pNode = parentOf(prevNode);

      while (!isRootNode(prevNode) && fromLevel > (includeRoot ? 1 : 0)) {
        var last = lastChildrenOf(pNode);
        if (equals(last, myself)) {
          assert(childrenCount(pNode) > 1);
          last = childAt(pNode, childrenCount(pNode) - 2);
        }
        if (!equals(last, prevNode)) {
          break;
        }
        fromLevel--;
        prevNode = pNode;
        pNode = parentOf(prevNode);
      }
    }

    return IntRange(fromLevel, toLevel - fromLevel + 1);
  }
}

class _CircularList<T> {
  int start, size;
  late List<T?> list;

  _CircularList(this.size)
      : assert(size > 0),
        start = 0 {
    list = List<T?>.generate(size, (index) => null, growable: false);
  }

  T? operator [](int index) {
    assert(index >= 0 && index < size);
    var j = index + start;
    return list[(j < size) ? j : j - size];
  }

  operator []=(int index, T? value) {
    assert(index >= 0 && index < size);
    var j = index + start;
    list[(j < size) ? j : j - size] = value;
  }

  void shift(int len) {
    if (len == 0) return;
    if (len > 0) {
      if (len >= size) {
        clear();
      } else {
        var start2 = start + len;
        if (start2 < size) {
          for (var i = start; i < start2; i++) {
            list[i] = null;
          }
        } else {
          start2 -= size;
          for (var i = start; i < size; i++) {
            list[i] = null;
          }
          for (var i = 0; i < start2; i++) {
            list[i] = null;
          }
        }
        start = start2;
      }
    } else {
      if (-len >= size) {
        clear();
      } else {
        var start2 = start + len;
        if (start2 >= 0) {
          for (var i = start2; i < start; i++) {
            list[i] = null;
          }
        } else {
          start2 += size;
          for (var i = start2; i < size; i++) {
            list[i] = null;
          }
          for (var i = 0; i < start; i++) {
            list[i] = null;
          }
        }
        start = start2;
      }
    }
  }

  void clear() {
    start = 0;
    for (var i = 0; i < list.length; i++) {
      list[i] = null;
    }
  }

  void remove(int from, int to /* excluded */) {
    assert(from >= 0 && from < list.length);
    assert(to >= 0 && to <= list.length);
    assert(from <= to);
    final count = to - from;
    if (count == 0) return;
    int i;
    for (i = from; i < list.length - count; i++) {
      this[i] = this[count + i];
    }
    for (; i < list.length; i++) {
      this[i] = null;
    }
  }

  void insert(int from, int to /* excluded */) {
    assert(from >= 0 && from < list.length);
    assert(to >= 0 && to <= list.length);
    assert(from <= to);
    final count = to - from;
    if (count == 0) return;
    int i;
    for (i = list.length - 1; i >= from + count; i--) {
      this[i] = this[i - count];
    }
    for (; i >= from; i--) {
      this[i] = null;
    }
  }
}

/// A range of integers.
class IntRange {
  const IntRange(this.from, this.length);

  final int from, length;

  int get to => from + length;

  bool isIn(int index) => from <= index && index < to;

  @override
  String toString() => '[$from,$to)';
}
