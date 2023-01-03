import 'dart:async';
import 'dart:collection';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:great_list_view/src/dispatcher.dart';
import 'package:great_list_view/src/morph_transition.dart'
    show MorphComparator, MorphTransition;
import 'package:great_list_view/ticker_mixin.dart';

part 'animation.dart';
part 'child_manager.dart';
part 'delegates.dart';
part 'interval_list.dart';
part 'interval_manager.dart';
part 'intervals.dart';
part 'linked_list.dart';
part 'multi_container.dart';
part 'sliver_list.dart';
part 'sliver_multi_box_adaptor.dart';
part 'widgets.dart';

/// Additional information to build a specific item of the list.
class AnimatedWidgetBuilderData {
  /// The main animation used by dismssing of incoming items. The value `0.0` indicates that the
  /// item is totally dismissed, whereas `1.0` indicates the item is totally income.
  final Animation<double> animation;

  /// If `true` it indicates that this item is the one dragged during a reorder.
  final bool dragging;

  /// If `true` it indicates that this item is moving whitin a pop up.
  final bool moving;

  /// If `true` it indicates that this item is going to be built just to measure it. You can check
  /// this attribute in order to build am equivalent lighter widget (which is the same size as
  /// the original).
  final bool measuring;

  /// The slot value you have returned from your [AnimatedListReorderModel].
  final Object? slot;

  const AnimatedWidgetBuilderData(this.animation,
      {this.measuring = false,
      this.dragging = false,
      this.slot,
      this.moving = false});
}

/// The builder used to build the items of the list view.
typedef AnimatedWidgetBuilder = Widget Function(
    BuildContext context, int index, AnimatedWidgetBuilderData data);

typedef InitialScrollOffsetCallback = double? Function(
    SliverConstraints constraints);

typedef UpdateToOffsetCallback = double Function(
    int index, int count, double remainingTime);

/// The part of the size of the item that is currently visible.
class _PercentageSize {
  final double size, referredSize;

  _PercentageSize(this.size, this.referredSize);

  double get percentage => size / referredSize;

  @override
  String toString() => '${percentage * 100.0}%';
}

class _Measure {
  final double value;
  final bool estimated;

  static const _Measure zero = _Measure(0, false);

  const _Measure(this.value, [this.estimated = false]);

  _Measure operator +(_Measure m) =>
      _Measure(value + m.value, estimated || m.estimated);

  _Measure operator -(_Measure m) =>
      _Measure(value - m.value, estimated || m.estimated);

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
  _Update(this.index, this.oldBuildCount, this.newBuildCount,
      [this.flags = const _UpdateFlags(), this.popUpList, this.toPopUpList])
      : assert(index >= 0 && oldBuildCount >= 0 && newBuildCount >= 0),
        assert(!flags.hasPopupPick || toPopUpList != null),
        assert(!flags.hasPopupDrop || popUpList != null);

  final int index;
  final int oldBuildCount, newBuildCount;
  final _UpdateFlags flags;
  final _PopUpList? popUpList, toPopUpList;

  int get skipCount => newBuildCount - oldBuildCount;

  @override
  String toString() =>
      'U(i: $index, obc: $oldBuildCount, nbc: $newBuildCount, fl: $flags, pl: ${popUpList?.debugId}, tpl: ${toPopUpList?.debugId})';
}

typedef _IntervalBuilder = Widget Function(
    BuildContext context, int index, AnimatedWidgetBuilderData data);

// Creates a copy of an interval builder possibly adding more offset.
// If the offset is zero, the same interval builder is returned.
_IntervalBuilder? offsetIntervalBuilder(
    final _IntervalBuilder? iBuilder, final int offset) {
  if (offset == 0 || iBuilder == null) return iBuilder;
  assert(offset > 0);
  return (context, index, data) => iBuilder.call(context, index + offset, data);
}

// Joins two interval builder and returns a new merged one.
_IntervalBuilder joinBuilders(final _IntervalBuilder leftBuilder,
    final _IntervalBuilder rightBuilder, final int leftCount) {
  assert(leftCount > 0);
  return (context, index, data) => (index < leftCount)
      ? leftBuilder.call(context, index, data)
      : rightBuilder.call(context, index - leftCount, data);
}

class _DebugWidget extends StatelessWidget {
  const _DebugWidget(this.child, this.debugText);

  final Widget child;
  final String Function() debugText;

  @override
  StatelessElement createElement() => _DebugElement(this);

  @override
  Widget build(BuildContext context) => child;
}

class _DebugElement extends StatelessElement {
  _DebugElement(super.widget);
}

String debugElement(Element? element) {
  if (element == null) return 'null';
  var ret = 'UNKNOWN';
  if (element.parent is AnimatedSliverMultiBoxAdaptorElement &&
      element is _DebugElement) {
    ret = (element.widget as _DebugWidget).debugText.call();
  }
  return ret;
}

String debugRenderBox(RenderObject? ro) {
  if (ro == null) return 'null';
  final dc = ro.debugCreator;
  if (dc is DebugCreator) {
    Element? p, e = dc.element;
    while (e != null) {
      if (e is AnimatedSliverMultiBoxAdaptorElement) {
        return debugElement(p);
      }
      p = e;
      e = e.parent;
    }
  }
  return 'UNKNOWN';
}

extension _Element on Element {
  Element? get parent {
    Element? ret;
    visitAncestorElements((element) {
      ret = element;
      return false;
    });
    return ret;
  }
}

abstract class _PopUpList {
  double? currentScrollOffset;

  int get popUpBuildCount;

  static var counter = 0;
  final int debugId;

  _PopUpList() : debugId = counter + 1 {
    counter++;
  }

  Widget buildPopUp(BuildContext context, int index, bool measureOnly);

  void Function(double Function(int, int, double) callback)? updateScrollOffset;

  Iterable<_Interval> get intervals;
}

class _ReorderPopUpList extends _PopUpList {
  final _IntervalList intervalList;

  _ReorderPopUpList(this.intervalList) {
    intervalList.popUpList = this;
  }

  @override
  Widget buildPopUp(BuildContext context, int index, bool measureOnly) {
    return intervalList.build(context, index, measureOnly);
  }

  @override
  int get popUpBuildCount => 1;

  @override
  Iterable<_Interval> get intervals => intervalList;

  @override
  String toString() => 'PopUp[$debugId] reorder';
}

class _MovingPopUpList extends _PopUpList {
  List<_IntervalList> subLists = [];

  @override
  int get popUpBuildCount =>
      subLists.fold<int>(0, (pv, e) => pv + e.buildCount);

  @override
  Widget buildPopUp(BuildContext context, int index, bool measureOnly) {
    for (final sl in subLists) {
      if (index < sl.buildCount) {
        return sl.build(context, index, measureOnly);
      }
      index -= sl.buildCount;
    }
    throw Exception('this point should never have been reached');
  }

  @override
  Iterable<_Interval> get intervals => subLists.expand((e) => e);

  @override
  String toString() => 'PopUp[$debugId] subLists=$subLists';

  int buildIndexOf(_IntervalList subList) {
    assert(subLists.contains(subList));
    var o = 0;
    for (final sl in subLists) {
      if (sl == subList) break;
      o += sl.buildCount;
    }
    return o;
  }
}

class _SizeResult {
  final int from, to;
  final double size;

  int get count => to - from;

  const _SizeResult(this.from, this.to, this.size);

  @override
  String toString() => 'from=$from, to=$to, size=$size';
}

typedef _UpdateCallback = void Function(
    _IntervalList list, int index, int oldBuildCount, int newBuildCount);

//
// Debug
//

String _spaces = '';

void dbgBegin(String message) {
  dbgPrint('$message {');
  _spaces += '    ';
}

void dbgPrint(String message) {
  // debugPrintSynchronously('$_spaces$s');
  io.stderr.writeln('$_spaces$message');
}

void dbgEnd() {
  final l = _spaces.length - 4;
  if (l <= 0) {
    _spaces = '';
  } else {
    _spaces = _spaces.substring(l);
  }
  dbgPrint('}');
}

const DEBUG_ENABLED = false;

void Function(String message) _dbgBegin =
    kDebugMode && DEBUG_ENABLED ? dbgBegin : (m) {};
void Function(String message) _dbgPrint =
    kDebugMode && DEBUG_ENABLED ? dbgPrint : (m) {};
void Function() _dbgEnd = kDebugMode && DEBUG_ENABLED ? dbgEnd : () {};
