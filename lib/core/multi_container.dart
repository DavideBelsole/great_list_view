part of 'core.dart';

mixin MultiContainerRenderObjectMixin<
    ChildType extends RenderObject,
    ParentDataType extends MultiContainerParentDataMixin<ChildType, KeyType>,
    KeyType> on RenderObject {
  final _data = <KeyType,
      MultiContainerRenderObjectList<ChildType, ParentDataType, KeyType>>{};

  Iterable<KeyType> get keys => _data.keys;

  MultiContainerRenderObjectList<ChildType, ParentDataType, KeyType>
      _getOrCreateListOf(KeyType key) => _data.putIfAbsent(
          key,
          () => MultiContainerRenderObjectList<ChildType, ParentDataType,
              KeyType>());

  /// Insert child into this render object's child list after the given child.
  ///
  /// If `after` is null, then this inserts the child at the start of the list,
  /// and the child becomes the new [firstChild].
  void insert(KeyType key, ChildType child, {ChildType? after}) {
    assert(child != this, 'A RenderObject cannot be inserted into itself.');
    assert(after != this,
        'A RenderObject cannot simultaneously be both the parent and the sibling of another RenderObject.');
    assert(child != after, 'A RenderObject cannot be inserted after itself.');
    final data = _getOrCreateListOf(key);
    assert(child != data._firstChild);
    assert(child != data._lastChild);
    adoptChild(child);
    data._insertIntoChildList(child, after: after);
  }

  /// Append child to the end of this render object's child list.
  void add(KeyType key, ChildType child) {
    final data = _getOrCreateListOf(key);
    insert(key, child, after: data._lastChild);
  }

  /// Add all the children to the end of this render object's child list.
  void addAll(KeyType key, List<ChildType>? children) {
    children?.forEach((e) => add(key, e));
  }

  /// Remove this child from the child list.
  ///
  /// Requires the child to be present in the child list.
  void remove(KeyType key, ChildType child) {
    final data = _data[key]!;
    data._removeFromChildList(child);
    dropChild(child);
    // if (data._childCount == 0) _data.remove(key);
  }

  void removeEmptyKeys() {
    _data.removeWhere((key, value) => key != null && value._childCount == 0);
  }

  /// Remove all their children from this render object's child list.
  ///
  /// More efficient than removing them individually.
  void removeAll(KeyType key) {
    final data = _data[key]!;
    var child = data._firstChild;
    while (child != null) {
      final childParentData = child.parentData! as ParentDataType;
      final next = childParentData.nextSibling;
      childParentData.previousSibling = null;
      childParentData.nextSibling = null;
      dropChild(child);
      child = next;
    }
    _data.remove(key);
  }

  /// Move the given `child` in the child list to be after another child.
  ///
  /// More efficient than removing and re-adding the child. Requires the child
  /// to already be in the child list at some position. Pass null for `after` to
  /// move the child to the start of the child list.
  void move(KeyType newKey, ChildType child, {ChildType? after}) {
    assert(child != this);
    assert(after != this);
    assert(child != after);
    assert(child.parent == this);
    final childParentData = child.parentData! as ParentDataType;
    final oldKey = childParentData.key;
    if (childParentData.previousSibling == after && oldKey == newKey) {
      return;
    }
    assert(after == null || (after.parentData as ParentDataType).key == newKey);
    final oldData = _data[oldKey]!;
    oldData._removeFromChildList(child);
    _getOrCreateListOf(newKey)._insertIntoChildList(child, after: after);
    // if (oldData._childCount == 0) _data.remove(oldKey);
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (final e in _data.values) {
      var child = e._firstChild;
      while (child != null) {
        child.attach(owner);
        final childParentData = child.parentData! as ParentDataType;
        child = childParentData.nextSibling;
      }
    }
  }

  @override
  void detach() {
    super.detach();
    for (final e in _data.values) {
      var child = e._firstChild;
      while (child != null) {
        child.detach();
        final childParentData = child.parentData! as ParentDataType;
        child = childParentData.nextSibling;
      }
    }
  }

  @override
  void redepthChildren() {
    for (final e in _data.values) {
      var child = e._firstChild;
      while (child != null) {
        redepthChild(child);
        final childParentData = child.parentData! as ParentDataType;
        child = childParentData.nextSibling;
      }
    }
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    for (final e in _data.values) {
      var child = e._firstChild;
      while (child != null) {
        visitor(child);
        final childParentData = child.parentData! as ParentDataType;
        child = childParentData.nextSibling;
      }
    }
  }

  MultiContainerRenderObjectList<ChildType, ParentDataType, KeyType>? listOf(
          KeyType key,
          [bool createIfNotExists = false]) =>
      createIfNotExists ? _getOrCreateListOf(key) : _data[key];

  /// The previous child before the given child in the child list.
  ChildType? childBefore(ChildType child) {
    assert(child.parent == this);
    final childParentData = child.parentData! as ParentDataType;
    return childParentData.previousSibling;
  }

  /// The next child after the given child in the child list.
  ChildType? childAfter(ChildType child) {
    assert(child.parent == this);
    final childParentData = child.parentData! as ParentDataType;
    return childParentData.nextSibling;
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() {
    final children = <DiagnosticsNode>[];
    for (final e in _data.values) {
      if (e._firstChild != null) {
        var child = e._firstChild!;
        var count = 1;
        while (true) {
          children.add(child.toDiagnosticsNode(name: 'child $count'));
          if (child == e._lastChild) {
            break;
          }
          count += 1;
          final childParentData = child.parentData! as ParentDataType;
          child = childParentData.nextSibling!;
        }
      }
    }
    return children;
  }
}

class MultiContainerRenderObjectList<
    ChildType extends RenderObject,
    ParentDataType extends MultiContainerParentDataMixin<ChildType, KeyType>,
    KeyType> {
  ChildType? _firstChild, _lastChild;
  int _childCount = 0;

  /// The number of children.
  int get childCount => _childCount;

  /// The first child in the child list.
  ChildType? get firstChild => _firstChild;

  /// The last child in the child list.
  ChildType? get lastChild => _lastChild;

  /// It returns `true` if [equals] is the first in the list, where the latter is retraced starting from
  /// the child node
  bool _debugUltimatePreviousSiblingOf(ChildType child, {ChildType? equals}) {
    var childParentData = child.parentData! as ParentDataType;
    while (childParentData.previousSibling != null) {
      assert(childParentData.previousSibling != child);
      child = childParentData.previousSibling!;
      childParentData = child.parentData! as ParentDataType;
    }
    return child == equals;
  }

  /// It returns `true` if [equals] is the last node in the list, where the list is retraced starting from
  /// the child node.
  bool _debugUltimateNextSiblingOf(ChildType child, {ChildType? equals}) {
    var childParentData = child.parentData! as ParentDataType;
    while (childParentData.nextSibling != null) {
      assert(childParentData.nextSibling != child);
      child = childParentData.nextSibling!;
      childParentData = child.parentData! as ParentDataType;
    }
    return child == equals;
  }

  void _insertIntoChildList(ChildType child, {ChildType? after}) {
    final childParentData = child.parentData! as ParentDataType;
    assert(childParentData.nextSibling == null);
    assert(childParentData.previousSibling == null);
    _childCount += 1;
    assert(_childCount > 0);
    if (after == null) {
      // insert at the start (_firstChild)
      childParentData.nextSibling = _firstChild;
      if (_firstChild != null) {
        final firstChildParentData = _firstChild!.parentData! as ParentDataType;
        firstChildParentData.previousSibling = child;
      }
      _firstChild = child;
      _lastChild ??= child;
    } else {
      assert(_firstChild != null);
      assert(_lastChild != null);
      assert(_debugUltimatePreviousSiblingOf(after, equals: _firstChild));
      assert(_debugUltimateNextSiblingOf(after, equals: _lastChild));
      final afterParentData = after.parentData! as ParentDataType;
      if (afterParentData.nextSibling == null) {
        // insert at the end (_lastChild); we'll end up with two or more children
        assert(after == _lastChild);
        childParentData.previousSibling = after;
        afterParentData.nextSibling = child;
        _lastChild = child;
      } else {
        // insert in the middle; we'll end up with three or more children
        // set up links from child to siblings
        childParentData.nextSibling = afterParentData.nextSibling;
        childParentData.previousSibling = after;
        // set up links from siblings to child
        final childPreviousSiblingParentData =
            childParentData.previousSibling!.parentData! as ParentDataType;
        final childNextSiblingParentData =
            childParentData.nextSibling!.parentData! as ParentDataType;
        childPreviousSiblingParentData.nextSibling = child;
        childNextSiblingParentData.previousSibling = child;
        assert(afterParentData.nextSibling == child);
      }
    }
  }

  void _removeFromChildList(ChildType child) {
    final childParentData = child.parentData! as ParentDataType;
    assert(_debugUltimatePreviousSiblingOf(child, equals: _firstChild));
    assert(_debugUltimateNextSiblingOf(child, equals: _lastChild));
    assert(_childCount >= 0);
    if (childParentData.previousSibling == null) {
      assert(_firstChild == child);
      _firstChild = childParentData.nextSibling;
    } else {
      final childPreviousSiblingParentData =
          childParentData.previousSibling!.parentData! as ParentDataType;
      childPreviousSiblingParentData.nextSibling = childParentData.nextSibling;
    }
    if (childParentData.nextSibling == null) {
      assert(_lastChild == child);
      _lastChild = childParentData.previousSibling;
    } else {
      final childNextSiblingParentData =
          childParentData.nextSibling!.parentData! as ParentDataType;
      childNextSiblingParentData.previousSibling =
          childParentData.previousSibling;
    }
    childParentData.previousSibling = null;
    childParentData.nextSibling = null;
    _childCount -= 1;
  }
}

mixin MultiContainerParentDataMixin<ChildType extends RenderObject, KeyType>
    on ParentData {
  KeyType? key;

  /// The previous sibling in the parent's child list.
  ChildType? previousSibling;

  /// The next sibling in the parent's child list.
  ChildType? nextSibling;

  /// Clear the sibling pointers.
  @override
  void detach() {
    assert(previousSibling == null,
        'Pointers to siblings must be nulled before detaching ParentData.');
    assert(nextSibling == null,
        'Pointers to siblings must be nulled before detaching ParentData.');
    super.detach();
  }
}
