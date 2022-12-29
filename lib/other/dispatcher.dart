library great_list_view.other;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:diffutil_dart/diffutil.dart';
import 'package:flutter/widgets.dart';
import 'package:great_list_view/core/core.dart'
    show AnimatedListController, AnimatedWidgetBuilderData;
import 'package:worker_manager/worker_manager.dart';

part 'package:great_list_view/other/moved_array.dart';

const int kSpawnNewIsolateCount = 500;

typedef AnimatedListDiffBuilder<T> = Widget Function(
    BuildContext context, T list, int index, AnimatedWidgetBuilderData data);

/// A derivated version of this class has to be implemented to tell [AnimatedListDiffDispatcher]
/// how to compare items of two lists in order to dispatch the differences
/// to the [AnimatedListController].
abstract class AnimatedListDiffBaseComparator<T> {
  const AnimatedListDiffBaseComparator();

  /// It compares the [indexA] of the [listA] with the [indexB] of the [listB] and returns
  /// `true` is they are the same item. Usually, the "id" of the item is compared here.
  bool sameItem(T listA, int indexA, T listB, int indexB);

  /// IT compares the [indexA] of [listA] with the [indexB] of [listB] and returns
  /// `true` is they have the same content. This method is called after [sameItem]
  /// returned `true`, so this method tells if the same item has changed its content;
  /// if so a changing notification will be sent to the [AnimatedListController].
  bool sameContent(T listA, int indexA, T listB, int indexB);

  /// It returns the length of the [list].
  int lengthOf(T list);
}

/// A callback function-based version of [AnimatedListDiffBaseComparator], useful if
/// you are bored of creating a new derivated class.
class AnimatedListDiffComparator<T> extends AnimatedListDiffBaseComparator<T> {
  const AnimatedListDiffComparator({
    required bool Function(T listA, int indexA, T listB, int indexB) sameItem,
    required bool Function(T listA, int indexA, T listB, int indexB)
        sameContent,
    required int Function(T list) lengthOf,
  })  : _sameItem = sameItem,
        _sameContent = sameContent,
        _lengthOf = lengthOf;

  final bool Function(T listA, int indexA, T listB, int indexB) _sameItem;
  final bool Function(T listA, int indexA, T listB, int indexB) _sameContent;
  final int Function(T list) _lengthOf;

  @override
  bool sameItem(T listA, int indexA, T listB, int indexB) =>
      _sameItem(listA, indexA, listB, indexB);

  @override
  bool sameContent(T listA, int indexA, T listB, int indexB) =>
      _sameContent(listA, indexA, listB, indexB);

  @override
  int lengthOf(T list) => _lengthOf(list);
}

/// This class takes an initial list that can be replaced with a new one through
/// the [dispatchNewList] method.
/// When a new list is provided, the Myers diff algorithm runs to detect the differences.
/// These differences will be dispatched to the [controller] provided.
/// If the total item count is greater that the [spawnNewInsolateCount] parameter, the algorithm
/// will be executed in a separated `Isolate`.
/// An [builder] has to be provided to build replaced and changed items (as required
/// by [AnimatedListController.notifyChangedRange], [AnimatedListController.notifyReplacedRange]
/// and [AnimatedListController.notifyRemovedRange] methods).
/// The two lists are compared using the [comparator] provided.
class AnimatedListDiffDispatcher<T> {
  AnimatedListDiffDispatcher(
      {required T initialList,
      required this.controller,
      required this.builder,
      required this.comparator,
      this.spawnNewInsolateCount = kSpawnNewIsolateCount})
      : _currentList = initialList;

  final AnimatedListController controller;
  final AnimatedListDiffBuilder<T> builder;
  final AnimatedListDiffBaseComparator<T> comparator;
  final int spawnNewInsolateCount;

  T _currentList;
  T? _oldList, _processingList;
  Cancelable<_DiffResultDispatcher>? _cancelable;

  /// It replaces the current list with the new one.
  /// Differences are calculated and then dispatched to the [controller].
  Future<void> dispatchNewList(T newList, {bool detectMoves = false}) async {
    _processingList = newList;

    _DiffResultDispatcher dr;
    var futureOr = _computeDiffs(_currentList, newList, detectMoves);
    if (futureOr is Future<_DiffResultDispatcher?>) {
      dr = await futureOr;
    } else {
      dr = futureOr;
    }

    if (newList != _processingList || _processingList == null) {
      return; // discard result
    }

    _oldList = _currentList;
    _currentList = _processingList!;
    _processingList = null;

    final oldList = _oldList!;

    final cl = _ChangeList(comparator.lengthOf(oldList));

    Widget callOldListBuilder(List<_MovedRange> l, int index,
        BuildContext context, AnimatedWidgetBuilderData data) {
      int? oldIndex;
      var i = index;
      for (final e in l) {
        if (i < e.length) {
          oldIndex = e.from + i;
          break;
        }
        i -= e.length;
      }
      assert(oldIndex != null);
      return builder.call(context, oldList, oldIndex!, data);
    }

    controller.batch(() {
      dr._dispatchUpdatesTo(
        onInsert: (position, count) {
          controller.notifyInsertedRange(position, count);
          cl.replaceOrChange(position, 0, count);
        },
        onChange: (position, count) {
          final l = cl.apply(position, count)!;
          assert(l.isNotEmpty);
          controller.notifyChangedRange(position, count,
              (context, index, data) {
            return callOldListBuilder(l, index, context, data);
          });
          cl.replaceOrChange(position, count, count);
        },
        onRemove: (position, count) {
          final l = cl.apply(position, count)!;
          assert(l.isNotEmpty);
          controller.notifyRemovedRange(position, count,
              (context, index, data) {
            return callOldListBuilder(l, index, context, data);
          });
          cl.replaceOrChange(position, count, 0);
        },
        onReplace: (position, removeCount, insertCount) {
          final l = cl.apply(position, removeCount)!;
          assert(l.isNotEmpty);
          controller.notifyReplacedRange(position, removeCount, insertCount,
              (context, index, data) {
            return callOldListBuilder(l, index, context, data);
          });
          cl.replaceOrChange(position, removeCount, insertCount);
        },
        onMove: (position, toPosition, count) {
          controller.notifyMovedRange(position, count, toPosition);
          cl.move(position, count, toPosition);
        },
      );
    });
  }

  /// It returns `true` if the Meyes algorithm is still running.
  bool get hasPendingTask => _processingList != null;

  /// It returns the current underlying list.
  /// This corresponds to the last list passed to the [dispatchNewList] method if only the
  /// Meyes algorithm is not yet running.
  T get currentList => _currentList;

  FutureOr<_DiffResultDispatcher> _computeDiffs(
      final T oldList, final T newList, bool detectMoves) {
    if (_cancelable != null) {
      _cancelable!.cancel();
      _cancelable = null;
    }

    if (comparator.lengthOf(oldList) + comparator.lengthOf(newList) >=
        spawnNewInsolateCount) {
      final completer = Completer<_DiffResultDispatcher>();
      _cancelable = Executor().execute<T, T, AnimatedListDiffBaseComparator<T>,
              bool, _DiffResultDispatcher, dynamic>(
          arg1: oldList,
          arg2: newList,
          arg3: comparator,
          arg4: detectMoves,
          fun4: _calculateDiff)
        ..then((value) {
          _cancelable = null;
          completer.complete(value);
        }).catchError((dynamic e) {});
      return completer.future;
    } else {
      return _calculateDiff(oldList, newList, comparator, detectMoves);
    }
  }

  /// It stops this dispatcher from processing the Meyes algorithm and returns
  /// the list is currently being processed, if any.
  T? discard() {
    final list = _processingList;
    _processingList = null;
    return list;
  }
}

_DiffResultDispatcher _calculateDiff<T>(T oldList, T newList,
    AnimatedListDiffBaseComparator<T> comparator, bool detectMoves,
    [TypeSendPort<dynamic>? port]) {
  return _DiffResultDispatcher(calculateDiff<T>(
    _DiffDelegate<T>(
      oldList,
      newList,
      comparator.sameContent,
      comparator.sameItem,
      comparator.lengthOf,
    ),
    detectMoves: detectMoves,
  ));
}

class _DiffDelegate<T> implements DiffDelegate {
  final T oldList;
  final T newList;
  final bool Function(T, int, T, int) _areContentsTheSame;
  final bool Function(T, int, T, int) _areItemsTheSame;
  final int Function(T) _listLength;

  const _DiffDelegate(this.oldList, this.newList, this._areContentsTheSame,
      this._areItemsTheSame, this._listLength);

  @override
  bool areContentsTheSame(int oldItemPosition, int newItemPosition) {
    return _areContentsTheSame.call(
        oldList, oldItemPosition, newList, newItemPosition);
  }

  @override
  bool areItemsTheSame(int oldItemPosition, int newItemPosition) {
    return _areItemsTheSame.call(
        oldList, oldItemPosition, newList, newItemPosition);
  }

  @override
  Object? getChangePayload(int oldItemPosition, int newItemPosition) {
    return null;
  }

  @override
  int getNewListSize() => _listLength(newList);

  @override
  int getOldListSize() => _listLength(oldList);
}

enum _OperationType {
  INSERT,
  REMOVE,
  REPLACE,
  CHANGE,
  MOVE,
}

class _Operation {
  const _Operation(
      {required this.type,
      required this.data1,
      required this.data2,
      this.data3});

  final _OperationType type;
  final int data1, data2;
  final int? data3;

  String get typeToString {
    switch (type) {
      case _OperationType.INSERT:
        return 'INS';
      case _OperationType.REMOVE:
        return 'REM';
      case _OperationType.REPLACE:
        return 'REP';
      case _OperationType.CHANGE:
        return 'CHG';
      case _OperationType.MOVE:
        return 'MOV';
    }
  }

  @override
  String toString() {
    if (type == _OperationType.REPLACE) {
      return '$typeToString $data1 ($data2,$data3)';
    } else if (type == _OperationType.MOVE) {
      return '$typeToString $data1 -> $data2 ($data3)';
    } else {
      return '$typeToString $data1 ($data2)';
    }
  }
}

class _DiffResultDispatcher {
  _DiffResultDispatcher(final DiffResult diffResult) {
    var upd = diffResult.getUpdates(batch: false);
    for (final u in upd) {
      u.when(
        change: (position, payload) {
          if (_changedPosition != null &&
              position == _changedPosition! - _changedCount) {
            _changedCount++;
          } else {
            _pushPendings();
            _changedPosition = position;
            _changedCount = 1;
          }
        },
        insert: (position, count) {
          if (position == _removedPosition) {
            _list.add(_Operation(
                type: _OperationType.REPLACE,
                data1: position,
                data2: _removedCount,
                data3: count));
            _removedPosition = null;
          } else {
            _pushPendings();
            _list.add(_Operation(
                type: _OperationType.INSERT, data1: position, data2: count));
          }
        },
        remove: (position, count) {
          _pushPendings();
          _removedPosition = position;
          _removedCount = count;
        },
        move: (from, to) {
          if (_movedFrom != null &&
              ((_movedFrom! > _movedTo &&
                      from == _movedFrom &&
                      to == _movedTo) ||
                  (_movedFrom! < _movedTo &&
                      from == _movedFrom! - 1 &&
                      to == _movedTo - 1))) {
            _movedCount++;
          } else {
            _pushPendings();
            _movedCount = 1;
          }
          _movedFrom = from;
          _movedTo = to;
        },
      );
    }

    _pushPendings();
  }

  final List<_Operation> _list = [];
  int? _removedPosition, _changedPosition, _movedFrom;
  int _removedCount = 0, _changedCount = 0, _movedCount = 0, _movedTo = -1;

  void _pushPendings() {
    if (_removedPosition != null) {
      _list.add(_Operation(
          type: _OperationType.REMOVE,
          data1: _removedPosition!,
          data2: _removedCount));
      _removedPosition = null;
    } else if (_changedPosition != null) {
      _list.add(_Operation(
          type: _OperationType.CHANGE,
          data1: _changedPosition! - _changedCount + 1,
          data2: _changedCount));
      _changedPosition = null;
    } else if (_movedFrom != null) {
      _list.add(_Operation(
          type: _OperationType.MOVE,
          data1: (_movedFrom! < _movedTo
              ? _movedFrom!
              : _movedFrom! - _movedCount + 1),
          data2: _movedTo,
          data3: _movedCount));
      _movedFrom = null;
    }
  }

  void _dispatchUpdatesTo(
      {void Function(int position, int count)? onInsert,
      void Function(int position, int count)? onRemove,
      void Function(int position, int removeCount, int insertCount)? onReplace,
      void Function(int position, int count)? onChange,
      void Function(int position, int toPosition, int count)? onMove}) {
    for (final op in _list) {
      switch (op.type) {
        case _OperationType.INSERT:
          onInsert?.call(op.data1, op.data2);
          break;
        case _OperationType.REMOVE:
          onRemove?.call(op.data1, op.data2);
          break;
        case _OperationType.REPLACE:
          onReplace?.call(op.data1, op.data2, op.data3!);
          break;
        case _OperationType.CHANGE:
          onChange?.call(op.data1, op.data2);
          break;
        case _OperationType.MOVE:
          onMove?.call(op.data1, op.data2, op.data3!);
          break;
      }
    }
  }

  @override
  String toString() => _list.toString();
}

//

typedef AnimatedListDiffListBuilder<T> = Widget Function(
    BuildContext context, T element, AnimatedWidgetBuilderData data);

/// This class extends [AnimatedListDiffListBaseComparator] in order to handle easier
/// the simplified version with [List]s objects.
abstract class AnimatedListDiffListBaseComparator<T> {
  const AnimatedListDiffListBaseComparator();

  bool sameItem(T elementA, T elementB);
  bool sameContent(T elementA, T elementB);
}

/// A callback function-based version of [AnimatedListDiffListBaseComparator].
class AnimatedListDiffListComparator<T>
    extends AnimatedListDiffListBaseComparator<T> {
  const AnimatedListDiffListComparator({
    required bool Function(T elementA, T elementB) sameItem,
    required bool Function(T elementA, T elementB) sameContent,
  })  : _sameItem = sameItem,
        _sameContent = sameContent;

  final bool Function(T elementA, T elementB) _sameItem;
  final bool Function(T elementA, T elementB) _sameContent;

  /// It compares the [elementA] with the [elementB] and returns
  /// `true` is they are the same item. Usually, the "id" of the item is compared here.
  @override
  bool sameItem(T elementA, T elementB) => _sameItem(elementA, elementB);

  /// IT compares the [elementA] with the [elementB] and returns
  /// `true` is they have the same content. This method is called after [sameItem]
  /// returned `true`, so this method tells if the same item has changed its content;
  /// if so a changing notification will be sent to the [AnimatedListController].
  @override
  bool sameContent(T elementA, T elementB) => _sameContent(elementA, elementB);
}

/// This class extends [AnimatedListDiffDispatcher] in order to handle easier
/// the simplified version with [List]s objects.
class AnimatedListDiffListDispatcher<T>
    extends AnimatedListDiffDispatcher<List<T>> {
  AnimatedListDiffListDispatcher(
      {required AnimatedListController controller,
      required AnimatedListDiffListBuilder<T> itemBuilder,
      required List<T> currentList,
      required AnimatedListDiffListBaseComparator<T> comparator,
      int spawnNewInsolateCount = kSpawnNewIsolateCount})
      : super(
          controller: controller,
          initialList: currentList,
          builder: (BuildContext context, List<T> list, int index,
                  AnimatedWidgetBuilderData data) =>
              itemBuilder.call(context, list[index], data),
          comparator: _ListDiffComparator<T>(comparator),
          spawnNewInsolateCount: spawnNewInsolateCount,
        );
}

class _ListDiffComparator<T> extends AnimatedListDiffBaseComparator<List<T>> {
  _ListDiffComparator(this.comparator);

  final AnimatedListDiffListBaseComparator<T> comparator;

  @override
  bool sameItem(List<T> listA, int indexA, List<T> listB, int indexB) =>
      comparator.sameItem.call(listA[indexA], listB[indexB]);

  @override
  bool sameContent(List<T> listA, int indexA, List<T> listB, int indexB) =>
      comparator.sameContent.call(listA[indexA], listB[indexB]);

  @override
  int lengthOf(List<T> list) => list.length;
}

class _Range {
  final int from, remove, insert;

  _Range(this.from, this.remove, this.insert);

  @override
  String toString() => '($from, $remove, $insert)';
}

class _ChangeList {
  final List<_Range> ranges = [];
  final _MovedArray movedArray;

  _ChangeList(int length) : movedArray = _MovedArray(length);

  void move(int from, int count, int to) {
    movedArray.dataMove(from, count, to);
  }

  void replaceOrChange(int from, int removeCount, int insertCount) {
    void fn(int from, int remove, int insert) {
      assert(remove > 0 || insert > 0);
      var i = 0;
      _Range? p, r;
      for (; i < ranges.length; i++) {
        r = ranges[i];
        if (from > r.from) {
          from -= r.insert - r.remove;
        } else {
          break;
        }
        p = r;
      }
      _Range nr;
      if (p != null && p.from + p.remove >= from) {
        ranges.removeAt(--i);
        nr = _Range(p.from, p.remove + remove, p.insert + insert);
      } else if (r != null && i < ranges.length && from + remove >= r.from) {
        ranges.removeAt(i);
        nr = _Range(from, remove + r.remove, insert + r.insert);
      } else {
        nr = _Range(from, remove, insert);
      }
      ranges.insert(i, nr);
      // _merge();
    }

    final movedResults =
        movedArray.dataReplaceOrChange(from, removeCount, insertCount);
    for (final r in movedResults) {
      fn(r.from, r.length, r.count);
    }
  }

  // void _merge() {
  //   int i = 0;
  //   _Range? p, r;
  //   for (; i < ranges.length; i++) {
  //     r = ranges[i];
  //     if (p != null) {
  //       if (p.from + p.remove >= r.from) {
  //         var nr = _Range(p.from, p.remove + r.remove, p.insert + r.insert);
  //         ranges.replaceRange(i - 1, i + 1, [nr]);
  //         i--;
  //         r = nr;
  //       }
  //     }
  //     p = r;
  //   }
  // }

  List<_MovedRange>? apply(int from, int count) {
    List<_MovedRange>? list;

    List<_MovedRange>? fn(List<_MovedRange>? list, int from, int count) {
      var i = 0;
      for (; i < ranges.length; i++) {
        final r = ranges[i];
        if (from >= r.from) {
          if (from < r.from + r.insert) return null;
          from -= r.insert - r.remove;
        } else {
          break;
        }
      }
      var to = from + count;
      for (; i < ranges.length; i++) {
        var r = ranges[i];
        if (to <= r.from) {
          break;
        } else {
          if (r.insert > 0) return null;
          assert(r.remove > 0);
          final delta = r.from - from;
          (list ??= <_MovedRange>[]).add(_MovedRange(from, delta));
          from += delta + r.remove;
          to += r.remove;
          count -= delta;
        }
      }
      (list ??= <_MovedRange>[]).add(_MovedRange(from, count));
      return list;
    }

    final movedResults = movedArray.dataReplaceOrChange(from, count, count);
    for (final r in movedResults) {
      list = fn(list, r.from, r.count);
      if (list == null) break;
    }
    return list;
  }

  @override
  String toString() => ranges.toString();
}
