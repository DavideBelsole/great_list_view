library great_list_view;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:worker_manager/worker_manager.dart';
import 'package:diffutil_dart/diffutil.dart';

import 'ticker_mixin.dart';
import 'other_widgets.dart';

part 'intervals.dart';
part 'child_manager.dart';
part 'sliver_list.dart';
part 'delegates.dart';
part 'widgets.dart';
part 'dispatcher.dart';

/// Additional information to build a specific item of the list.
class AnimatedWidgetBuilderData {
  /// The main animation used by dismssing of incoming items. The value 0.0 indicates that the
  /// item is totally dismissed, whereas 1.0 indicates the item is totally income.
  final Animation<double> animation;

  /// If true it indicates that this item is the one dragged during a reorder.
  final bool dragging;

  /// If true it indicates that this item is going to be built just to measure it. You can check
  /// this attribute in order to build am equivalent lighter widget (which is the same size as
  /// the original).
  final bool measuring;

  /// The slot value you have returned from your [AnimatedListBaseReorderModel].
  final Object? slot;

  AnimatedWidgetBuilderData(this.animation,
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

class _Measure {
  final double value;
  final bool estimated;

  static const _Measure zero = _Measure(0, false);

  const _Measure(this.value, [this.estimated = false]);

  _Measure operator +(_Measure m) =>
      _Measure(value + m.value, estimated || m.estimated);

  @override
  String toString() => estimated ? '≈$value' : '$value';
}
