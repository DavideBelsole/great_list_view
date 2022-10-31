library great_list_view;

import 'dart:async';

import 'package:diffutil_dart/diffutil.dart';
import 'package:flutter/widgets.dart';
import 'package:worker_manager/worker_manager.dart';

import 'core/core.dart';

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
  /// Differences are calculated and then dispatched to the [coontroller].
  Future<void> dispatchNewList(final T newList) async {
    _processingList = newList;

    _DiffResultDispatcher dr;
    var futureOr = _computeDiffs(_currentList, newList);
    if (futureOr is Future<_DiffResultDispatcher?>) {
      dr = await futureOr;
    } else {
      dr = futureOr;
    }

    if (newList != _processingList || _processingList == null) {
      return; // discard result
    }

    _oldList = _currentList;
    _currentList = _processingList as T;
    _processingList = null;

    final oldList = _oldList as T;

    controller.batch(() {
      dr._dispatchUpdatesTo(
        onInsert: (position, count) {
          controller.notifyInsertedRange(position, count);
        },
        onChange: (position, count) {
          controller.notifyChangedRange(position, count,
              (context, index, data) {
            return builder.call(context, oldList, position + index, data);
          });
        },
        onRemove: (position, count) {
          controller.notifyRemovedRange(position, count,
              (context, index, data) {
            return builder.call(context, oldList, position + index, data);
          });
        },
        onReplace: (position, removeCount, insertCount) {
          controller.notifyReplacedRange(position, removeCount, insertCount,
              (context, index, data) {
            return builder.call(context, oldList, position + index, data);
          });
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
      final T oldList, final T newList) {
    if (_cancelable != null) {
      _cancelable!.cancel();
      _cancelable = null;
    }

    if ((comparator.lengthOf(oldList) + comparator.lengthOf(newList) >=
        spawnNewInsolateCount)) {
      final completer = Completer<_DiffResultDispatcher>();
      _cancelable = Executor().execute(
        arg1: oldList, arg2: newList, arg3: comparator, fun3: _calculateDiff,
      )
      ..then((value) {
        _cancelable = null;
        completer.complete(value);
      }).catchError((e) {});
      return completer.future;
    } else {
      return _calculateDiff(oldList, newList, comparator, null);
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

_DiffResultDispatcher _calculateDiff<T>(
  final T oldList,
  final T newList,
  final AnimatedListDiffBaseComparator<T> comparator,
  final TypeSendPort? port,
) {
  return _DiffResultDispatcher(calculateDiff(
    _DiffDelegate<T>(
      oldList,
      newList,
      comparator.sameContent,
      comparator.sameItem,
      comparator.lengthOf,
    ),
    detectMoves: false,
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
  insert,
  remove,
  replace,
  change,
}

class _Operation {
  const _Operation(
      {required this.type,
      required this.position,
      required this.count1,
      this.count2});

  final _OperationType type;
  final int position, count1;
  final int? count2;

  String get typeToString {
    switch (type) {
      case _OperationType.insert:
        return 'INS';
      case _OperationType.remove:
        return 'REM';
      case _OperationType.replace:
        return 'REP';
      case _OperationType.change:
        return 'CHG';
    }
  }

  @override
  String toString() {
    if (type == _OperationType.replace) {
      return '$typeToString $position ($count1,$count2)';
    } else {
      return '$typeToString $position ($count1)';
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
                type: _OperationType.replace,
                position: position,
                count1: _removedCount,
                count2: count));
            _removedPosition = null;
          } else {
            _pushPendings();
            _list.add(_Operation(
                type: _OperationType.insert,
                position: position,
                count1: count));
          }
        },
        remove: (position, count) {
          _pushPendings();
          _removedPosition = position;
          _removedCount = count;
        },
        move: (from, to) {
          throw Exception('operation not supported yet!');
        },
      );
    }

    _pushPendings();
  }

  final List<_Operation> _list = [];
  int? _removedPosition, _changedPosition;
  int _removedCount = 0, _changedCount = 0;

  void _pushPendings() {
    if (_removedPosition != null) {
      _list.add(_Operation(
          type: _OperationType.remove,
          position: _removedPosition!,
          count1: _removedCount));
      _removedPosition = null;
    }
    if (_changedPosition != null) {
      _list.add(_Operation(
          type: _OperationType.change,
          position: _changedPosition! - _changedCount + 1,
          count1: _changedCount));
      _changedPosition = null;
    }
  }

  void _dispatchUpdatesTo(
      {void Function(int position, int count)? onInsert,
      void Function(int position, int count)? onRemove,
      void Function(int position, int removeCount, int insertCount)? onReplace,
      void Function(int position, int count)? onChange}) {
    for (final op in _list) {
      switch (op.type) {
        case _OperationType.insert:
          onInsert?.call(op.position, op.count1);
          break;
        case _OperationType.remove:
          onRemove?.call(op.position, op.count1);
          break;
        case _OperationType.replace:
          onReplace?.call(op.position, op.count1, op.count2!);
          break;
        case _OperationType.change:
          onChange?.call(op.position, op.count1);
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
