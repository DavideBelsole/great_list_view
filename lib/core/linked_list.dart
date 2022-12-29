part of 'core.dart';

class _NodePointers<T> {
  _NodePointers<T>? _next, _prev;
}

class _Head<T> extends _NodePointers<T> {
  @override
  String toString() => 'HEAD';
}

class _Tail<T> extends _NodePointers<T> {
  @override
  String toString() => 'TAIL';
}

class _LinkedNode<T extends _LinkedNode<T>> with _NodePointers<T> {
  _LinkedList<T>? _list;

  _LinkedList<T>? get list => _list;

  T? get next => (_list == null || _next!._next == null) ? null : (_next! as T);

  T? get previous =>
      (_list == null || _prev!._prev == null) ? null : (_prev! as T);

  void _remove() {
    assert(_list != null);
    _prev!._next = _next;
    _next!._prev = _prev;
    _next = null;
    _prev = null;
    _list = null;
  }

  void _insertAfter(_LinkedNode<T> newNode) {
    assert(newNode._list == null);
    final n = _next!;
    newNode._next = n;
    newNode._prev = this;
    _next = newNode;
    n._prev = newNode;
    newNode._list = _list;
  }

  void _insertBefore(_LinkedNode<T> newNode) {
    assert(newNode._list == null);
    final p = _prev!;
    newNode._next = this;
    newNode._prev = p;
    _prev = newNode;
    p._next = newNode;
    newNode._list = _list;
  }
}

class _LinkedList<T extends _LinkedNode<T>> extends Iterable<T> {
  final _Head<T> _head = _Head<T>();
  final _Tail<T> _tail = _Tail<T>();

  _LinkedList() {
    _head._next = _tail;
    _tail._prev = _head;
  }

  @override
  String toString() {
    return "(${join(", ")})";
  }

  void _add(_LinkedNode<T> newNode) {
    assert(newNode._list == null);
    final p = _tail._prev;
    p!._next = newNode;
    newNode._next = _tail;
    newNode._prev = p;
    _tail._prev = newNode;
    newNode._list = this;
  }

  // void _addFirst(MyLinkedNode<T> newNode) {
  //   assert(newNode._list == null);
  //   final n = _head._next;
  //   n!._prev = newNode;
  //   newNode._next = n;
  //   newNode._prev = _head;
  //   _head._next = newNode;
  //   newNode._list = this;
  // }

  @override
  Iterator<T> get iterator => _LinkedListIterator<T>(this);
}

class _LinkedListIterator<T extends _LinkedNode<T>> implements Iterator<T> {
  T? _current;
  _NodePointers<T>? _next;

  _LinkedListIterator(_LinkedList<T> list) : _next = list._head._next;

  @override
  T get current => _current as T;

  @override
  bool moveNext() {
    if (_next!._next == null) return false;
    final nn = _next!._next;
    _current = _next as T;
    _next = nn;
    return true;
  }
}
