library great_list_view;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../delegates.dart';
import '../ticker_mixin.dart';
import '../widgets.dart';

part 'animation.dart';
part 'child_manager.dart';
part 'controller.dart';
part 'interval_list.dart';
part 'intervals.dart';
part 'sliver_list.dart';

/// Additional information to build a specific item of the list.
class AnimatedWidgetBuilderData {
  /// The main animation used by dismssing of incoming items. The value `0.0` indicates that the
  /// item is totally dismissed, whereas `1.0` indicates the item is totally income.
  final Animation<double> animation;

  /// If `true` it indicates that this item is the one dragged during a reorder.
  final bool dragging;

  /// If `true` it indicates that this item is going to be built just to measure it. You can check
  /// this attribute in order to build am equivalent lighter widget (which is the same size as
  /// the original).
  final bool measuring;

  /// The slot value you have returned from your [AnimatedListBaseReorderModel].
  final Object? slot;

  const AnimatedWidgetBuilderData(this.animation,
      {this.measuring = false, this.dragging = false, this.slot});
}

/// The builder used to build the items of the list view.
typedef AnimatedWidgetBuilder = Widget Function(
    BuildContext context, int index, AnimatedWidgetBuilderData data);

/// This model is used to manage the reordering of a list view.
/// The following callbacks has to be provided:
/// - [onReorderStart] is called first when a new request of reordering is coming. The index of the
///   item is passed and two other additional parameters are passed that indicate the offset of the
///   tap/click from the top left corner of the item; if `false` is returned, the reorder
///   won't start at all;
/// - [onReorderFeedback] called whenever the item is moved by dragging. Its item's index is
///   passed again, then the index where it would like to move, the offset from the top of the sliver and
///   finally a delta indicating the distance of the new point from the original one.
///   Any value can be returned. If the last returned value is changed, a rebuild will be notified for
///   the dragged item. The returned value will be passed to the [AnimatedWidgetBuilderData]
///   of the builder.
/// - [onReorderMove] called when the dragged item, corresponding to the first index, would like to
///   move with the item corresponding to the second index. If `false` is returned, the move
///   won't be taken into consideration at all;
/// - [onReorderComplete] called at the end of reorder when the move must actually be done.
///   The last returned value from [onReorderFeedback] is also passed. Implement this callback
///   to update your underlying list. Return `false` if you want to cancel the move.
abstract class AnimatedListBaseReorderModel {
  const AnimatedListBaseReorderModel();
  bool onReorderStart(int index, double dx, double dy) => false;
  Object? onReorderFeedback(
          int index, int dropIndex, double offset, double dx, double dy) =>
      null;
  bool onReorderMove(int index, int dropIndex) => false;
  bool onReorderComplete(int index, int dropIndex, Object? slot) => false;
}

/// A callback function-based version of [AnimatedListBaseReorderModel].
class AnimatedListReorderModel extends AnimatedListBaseReorderModel {
  const AnimatedListReorderModel({
    bool Function(int index, double dx, double dy)? onReorderStart,
    Object? Function(
            int index, int dropIndex, double offset, double dx, double dy)?
        onReorderFeedback,
    bool Function(int index, int dropIndex)? onReorderMove,
    bool Function(int index, int dropIndex, Object? slot)? onReorderComplete,
  })  : _onReorderStart = onReorderStart,
        _onReorderFeedback = onReorderFeedback,
        _onReorderMove = onReorderMove,
        _onReorderComplete = onReorderComplete;

  final bool Function(int index, double dx, double dy)? _onReorderStart;
  final Object? Function(
          int index, int dropIndex, double offset, double dx, double dy)?
      _onReorderFeedback;
  final bool Function(int index, int dropIndex)? _onReorderMove;
  final bool Function(int index, int dropIndex, Object? slot)?
      _onReorderComplete;

  @override
  bool onReorderStart(int index, double dx, double dy) =>
      _onReorderStart?.call(index, dx, dy) ?? false;

  @override
  Object? onReorderFeedback(
          int index, int dropIndex, double offset, double dx, double dy) =>
      _onReorderFeedback?.call(index, dropIndex, offset, dx, dy);

  @override
  bool onReorderMove(int index, int dropIndex) =>
      _onReorderMove?.call(index, dropIndex) ?? false;

  @override
  bool onReorderComplete(int index, int dropIndex, Object? slot) =>
      _onReorderComplete?.call(index, dropIndex, slot) ?? false;
}

typedef InitialScrollOffsetCallback = double? Function(
    SliverConstraints constraints);

/// The part of the size of the item that is currently visible.
class PercentageSize {
  final double size, referredSize;

  PercentageSize(this.size, this.referredSize);

  double get percentage => size / referredSize;

  @override
  String toString() => '${percentage * 100.0}%';
}

class _Measure {
  final double value;
  final bool estimated;

  static _Measure get zero => const _Measure(0, false);

  const _Measure(this.value, [this.estimated = false]);

  _Measure operator +(_Measure m) =>
      _Measure(value + m.value, estimated || m.estimated);

  @override
  String toString() => estimated ? '≈$value' : '$value';
}

extension _MeasureExtension on double {
  _Measure toExactMeasure() => this == 0.0 ? _Measure.zero : _Measure(this);
}

class _UpdateFlags {
  const _UpdateFlags([int flags = 0])
      : _value = flags,
        assert((flags &
                ~(CLEAR_LAYOUT_OFFSET |
                    KEEP_FIRST_LAYOUT_OFFSET |
                    POPUP_PICK |
                    POPUP_DROP |
                    DISCARD_ELEMENT)) ==
            0),
        assert((flags & (CLEAR_LAYOUT_OFFSET | KEEP_FIRST_LAYOUT_OFFSET)) !=
            KEEP_FIRST_LAYOUT_OFFSET),
        assert(
            (flags & (POPUP_PICK | POPUP_DROP)) != (POPUP_PICK | POPUP_DROP));

  final int _value;

  static const int CLEAR_LAYOUT_OFFSET = 1 << 0;
  static const int KEEP_FIRST_LAYOUT_OFFSET = 1 << 1;
  static const int DISCARD_ELEMENT = 1 << 2;
  static const int POPUP_PICK = 1 << 3;
  static const int POPUP_DROP = 1 << 4;

  int get value => _value;

  bool get hasClearLayoutOffset =>
      (_value & CLEAR_LAYOUT_OFFSET) == CLEAR_LAYOUT_OFFSET;
  bool get hasKeepFirstLayoutOffset =>
      (_value & KEEP_FIRST_LAYOUT_OFFSET) == KEEP_FIRST_LAYOUT_OFFSET;
  bool get hasDiscardElement => (_value & DISCARD_ELEMENT) == DISCARD_ELEMENT;
  bool get hasPopupPick => (_value & POPUP_PICK) == POPUP_PICK;
  bool get hasPopupDrop => (_value & POPUP_DROP) == POPUP_DROP;

  @override
  String toString() => [
        if (hasClearLayoutOffset) 'CLEAR_LAYOUT_OFFSET',
        if (hasKeepFirstLayoutOffset) 'KEEP_FIRST_LAYOUT_OFFSET',
        if (hasDiscardElement) 'DISCARD_ELEMENT',
        if (hasPopupPick) 'POPUP_PICK',
        if (hasPopupDrop) 'POPUP_DROP'
      ].join(', ');
}

class _Update {
  const _Update(this.index, this.oldBuildCount, this.newBuildCount,
      [this.flags = const _UpdateFlags(), this.popUpList])
      : assert(index >= 0 && oldBuildCount >= 0 && newBuildCount >= 0);

  final int index;
  final int oldBuildCount, newBuildCount;
  final _UpdateFlags flags;
  final _PopUpList? popUpList;

  int get skipCount => newBuildCount - oldBuildCount;

  @override
  String toString() =>
      'U(i: $index, ob: $oldBuildCount, nb: $newBuildCount, s: $skipCount, m: $flags, pl: $popUpList)';
}

abstract class _PopUpList {
  _PopUpList() : updates = List<_Update>.empty(growable: true);

  final List<_Update> updates;

  _PopUpInterval? interval;

  Iterable<Element> get elements;

  void clearElements();

  @override
  String toString() =>
      '(updates: $updates, interval: $interval, elements: $elements)';
}

typedef _IntervalBuilder = Widget Function(BuildContext context, int buildIndex,
    int listIndex, AnimatedWidgetBuilderData data);

// Creates a copy of an interval builder possibly adding more offset.
// If the offset is zero, the same interval builder is returned.
_IntervalBuilder _offsetIntervalBuilder(
    final _IntervalBuilder iBuilder, final int offset) {
  assert(offset >= 0);
  if (offset == 0) return iBuilder;
  return (context, buildIndex, itemIndex, data) =>
      iBuilder.call(context, buildIndex + offset, itemIndex, data);
}

// Joins two interval builder and returns a new merged one.
_IntervalBuilder _joinBuilders(final _IntervalBuilder leftBuilder,
    final _IntervalBuilder rightBuilder, final int leftCount) {
  assert(leftCount > 0);
  return (context, buildIndex, listIndex, data) => (buildIndex < leftCount)
      ? leftBuilder.call(context, buildIndex, listIndex, data)
      : rightBuilder.call(context, buildIndex - leftCount, listIndex, data);
}
