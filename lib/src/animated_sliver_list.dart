import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'animated_list_child_manager.dart';
import 'animated_list_intervals.dart';
import 'morph_transition.dart';

const _kAnimationSpeed = 500;

const _kReorderAnimationSpeed = 250;

const _kReorderingScrollSpeed = 10.0;

const Duration _kRemovingDuration = Duration(milliseconds: _kAnimationSpeed);
const Duration _kResizingDuration = Duration(milliseconds: _kAnimationSpeed);
const Duration _kInsertingDuration = Duration(milliseconds: _kAnimationSpeed);
const Duration _kChangingDuration = Duration(milliseconds: _kAnimationSpeed);
const Duration _kReorderingDuration =
    Duration(milliseconds: _kReorderAnimationSpeed);

const Curve _kRemovingCurve = Curves.easeOut;
const Curve _kResizingCurve = Curves.easeInOut;
const Curve _kInsertingCurve = Curves.easeIn;
const Curve _kChangingCurve = Curves.linear;
const Curve _kReorderingCurve = Curves.easeInOut;

/// Provide durations and curves for all animations of the [AnimatedSliverList].
class AnimatedListAnimationSettings {
  final Duration removingDuration,
      resizingDuration,
      insertingDuration,
      changingDuration,
      reorderingDuration;
  final Curve removingCurve,
      resizingCurve,
      insertingCurve,
      changingCurve,
      reorderingCurve;

  const AnimatedListAnimationSettings({
    this.removingDuration = _kRemovingDuration,
    this.resizingDuration = _kResizingDuration,
    this.insertingDuration = _kInsertingDuration,
    this.changingDuration = _kChangingDuration,
    this.reorderingDuration = _kReorderingDuration,
    this.removingCurve = _kRemovingCurve,
    this.resizingCurve = _kResizingCurve,
    this.insertingCurve = _kInsertingCurve,
    this.changingCurve = _kChangingCurve,
    this.reorderingCurve = _kReorderingCurve,
  });
}

/// Status of the widget to build.
enum AnimatedListBuildType {
  /// Normal item. You can provide a key and make it sensitive to inputs (keyboard, touch, and so on).
  NORMAL,

  /// This item is animating for removal. Don't provide any key.
  REMOVING,

  /// This item is animating for insertion. Don't provide any key.
  INSERTING,

  /// This item is animating for modification. Don't provide any key.
  CHANGING,

  /// This item is animating for removal. Don't provide any key.
  REORDERING,

  /// The build request is only for measuring the size of the widget or
  /// to detect if the item just exists.
  MEASURING,

  /// Unknown state. This state should never be required.
  UNKNOWN,
}

//---------------------------------------------------------------------------------------------
// AnimatedListController
//---------------------------------------------------------------------------------------------

/// Use this controller to dispatch the changes of your list to the [AnimatedSliverList].
class AnimatedListController {
  AnimatedRenderSliverList? _adaptor;

  bool get isAttached => _adaptor != null;

  AnimatedRenderSliverList get adaptor {
    if (_adaptor == null) {
      throw 'This controller has not been assigned to an AnimatedListSliver widget yet.';
    }
    return _adaptor!;
  }

  void _setAdaptor(AnimatedRenderSliverList? adaptor) {
    if (_adaptor == adaptor) return;
    if (_adaptor != null && adaptor != null) {
      throw 'This controller cannot be assigned to multiple AnimatedListSliver widgets.';
    }
    _adaptor = adaptor;
  }

  /// Notify the [AnimatedSliverList] that a new range starting from [from] and [count] long
  /// has been inserted. Call this method after actually you have updated your list.
  void notifyInsertedRange(final int from, final int count) {
    if (adaptor.isReordering) {
      throw 'Cannot notify changes while reordering. Cancel reordering first';
    }
    adaptor._notifyReplacedRange(from, 0, count, null);
  }

  /// Notify the [AnimatedSliverList] that a range starting from [from] and [count] long
  /// has been removed. Call this method after actually you have updated your list.
  /// A new builder [removeItemBuilder] has to be provided in order to build the removed
  /// items when animating.
  void notifyRemovedRange(final int from, final int count,
      final IndexedWidgetBuilder removeItemBuilder) {
    if (adaptor.isReordering) {
      throw 'Cannot notify changes while reordering. Cancel reordering first';
    }
    adaptor._notifyReplacedRange(from, count, 0, removeItemBuilder);
  }

  /// Notify the [AnimatedSliverList] that a range starting from [from] and [removeCount] long
  /// has been replaced with a new [insertCount] long range. Call this method after
  /// you have updated your list.
  /// A new builder [removeItemBuilder] has to be provided in order to build the replaced
  /// items when animating.
  void notifyReplacedRange(final int from, final int removeCount,
      final int insertCount, final IndexedWidgetBuilder removeItemBuilder) {
    if (adaptor.isReordering) {
      throw 'Cannot notify changes while reordering. Cancel reordering first';
    }
    adaptor._notifyReplacedRange(
        from, removeCount, insertCount, removeItemBuilder);
  }

  /// Notify the [AnimatedSliverList] that a range starting from [from] and [count] long
  /// has been modified. Call this method after actually you have updated your list.
  /// A new builder [changeItemBuilder] has to be provided in order to build the old
  /// items when animating.
  void notifyChangedRange(final int from, final int count,
      final IndexedWidgetBuilder changeItemBuilder) {
    if (adaptor.isReordering) {
      throw 'Cannot notify changes while reordering. Cancel reordering first';
    }
    adaptor._notifyChangedRange(from, count, changeItemBuilder);
  }

  /// After notifying all your changes, call this method in order to dispatch them to the
  /// [AnimatedSliverList]. Eventually the animations that follow will start.
  void dispatchChanges() {
    if (adaptor.isReordering) {
      throw 'Cannot notify changes while reordering. Cancel reordering first';
    }
    adaptor._dispatchChanges();
  }

  Future<void> cancelReordering() {
    if ( !adaptor.isReordering ) throw 'It wasn\'t reordering';
    adaptor._stopReordering(true);
    var completer = Completer();
    WidgetsBinding.instance!.addPostFrameCallback((_) => completer.complete());
    return completer.future;
  }

  /// Mark the [AnimatedSliverList] to be softly rebuilt, keeping all current pending animations.
  /// Use this method only for soft changes, that is, only if the structure of the list
  /// doesn't change noticeably, for example just to update the widget of some item.
  /// If you need to rebuilt the entire list, provide a new [AnimatedSliverList] widget with a new
  /// delegate, whose [AnimatedSliverChildBuilderDelegate.shouldRebuild] method returns `true`;
  /// however in this case all pending animations will be canceled suddenly.
  void markNeedsSoftRefresh() {
    adaptor.childManager.markNeedsSoftRefresh();
  }
}

//---------------------------------------------------------------------------------------------
// AnimatedListAnimationBuilder
//---------------------------------------------------------------------------------------------

/// Abstract class for building animated Widgets.
abstract class AnimatedListAnimationBuilder {
  /// Wraps the [widget] in an animated widget for removing items.
  Widget buildRemoving(
      BuildContext context, Widget widget, Animation<double> animation);

  /// Wraps the [widget] in an animated widget for inserting new items.
  Widget buildInserting(
      BuildContext context, Widget widget, Animation<double> animation);

  /// Wraps the old Widget [fromWidget] and to new Widget [toWidget] in an animated one
  /// for changing items.
  Widget buildChanging(BuildContext context, Widget fromWidget, Widget toWidget,
      Animation<double> animation);

  /// Wraps the [widget] in a dragged form during reordering.
  Widget buildReordering(BuildContext context, Widget widget, int index);
}

/// Default singleton class for building animated Widgets.
///
/// For removing items a fade out effect will be provided.
/// For inserting new items a fade in effect will be provided.
/// For changing items a morph effect will be provided.
/// For dragged items an opacity effect of 80% and a shadow effect will be provided.
class DefaultAnimatedListAnimationBuilder
    implements AnimatedListAnimationBuilder {
  const DefaultAnimatedListAnimationBuilder._();

  static const DefaultAnimatedListAnimationBuilder instance =
      DefaultAnimatedListAnimationBuilder._();

  @override
  Widget buildRemoving(
      BuildContext context, Widget? widget, Animation<double> animation) {
    return FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.0).animate(animation), child: widget);
  }

  @override
  Widget buildInserting(
      BuildContext context, Widget? widget, Animation<double> animation) {
    return FadeTransition(opacity: animation, child: widget);
  }

  @override
  Widget buildChanging(BuildContext context, Widget? fromWidget,
      Widget? toWidget, Animation<double> animation) {
    return MorphTransition(
        resizeChildrenWhenAnimating: false,
        fromChild: fromWidget,
        toChild: toWidget,
        animation: animation);
  }

  @override
  Widget buildReordering(BuildContext context, Widget widget, int? index) {
    return Opacity(
        opacity: 0.8, child: Material(elevation: 16.0, child: widget));
  }
}

//---------------------------------------------------------------------------------------------
// AnimatedSliverList (Widget)
//---------------------------------------------------------------------------------------------

/// An animated version of the standard [SliverList].
///
/// A new delegate version of [SliverChildBuilderDelegate] called
/// [AnimatedSliverChildBuilderDelegate] has to be provided.
///
/// The [AnimatedListController] controller should also be provided to notify this sliver
/// when a change in the underlying list occurs.
///
/// A custom [AnimatedListAnimationBuilder] can be also provided to customize animations.
///
/// A [AnimatedListAnimationSettings] can be also provided to customize durations and curves
/// of the animations.
///
/// The [updateScrollableWhenResizing] attribute if is set to `false` prevents scroll
/// listeners for being notified when a resize animation occurs.
///
/// The [coordinateAnimations] attribute if is set to `false` prevents coordination of
/// animations. If `true` (by default) all animations will follow the following priorities:
/// intervals in removal state will start first, followed by those in resizing and changing
/// state, and finally those in inserting state.
///
/// Set the [reorderable] attribute to `true` to enable to reordering of the list, by
/// dragging the item to reorder after long touching it.
class AnimatedSliverList extends SliverWithKeepAliveWidget {
  final AnimatedSliverChildBuilderDelegate delegate;
  final AnimatedListController? controller;
  final AnimatedListAnimationBuilder animationBuilder;
  final AnimatedListAnimationSettings animatedListAnimationSettings;
  final bool updateScrollableWhenResizing;
  final bool coordinateAnimations;
  final bool reorderable;

  const AnimatedSliverList({
    Key? key,
    required this.delegate,
    this.controller,
    this.animationBuilder = DefaultAnimatedListAnimationBuilder.instance,
    this.animatedListAnimationSettings = const AnimatedListAnimationSettings(),
    this.updateScrollableWhenResizing = true,
    this.coordinateAnimations = true,
    this.reorderable = false,
  }) : super(key: key);

  @override
  AnimatedSliverMultiBoxAdaptorElement createElement() =>
      AnimatedSliverMultiBoxAdaptorElement(this);

  @override
  AnimatedRenderSliverList createRenderObject(BuildContext context) {
    return AnimatedRenderSliverList(
        childManager: context as AnimatedSliverMultiBoxAdaptorElement,
        widget: this);
  }
}

//---------------------------------------------------------------------------------------------
// AnimatedRenderSliverList (Render Object)
//---------------------------------------------------------------------------------------------

/// Render class of the [AnimatedSliverList].
/// This is an extension of the original class [RenderSliverList].
class AnimatedRenderSliverList extends RenderSliverList
    implements TickerProvider {
  AnimatedSliverList get widget => childManager.widget;

  final AnimatedListIntervalList intervals = AnimatedListIntervalList();
  Set<_WidgetTicker>? _tickers;

  /// Creates a sliver that places multiple box children in a linear array along
  /// the main axis, taking in account of animations resulting from changes
  /// to the underlying list.
  /// Those children can also be reordered.
  AnimatedRenderSliverList({
    required AnimatedSliverMultiBoxAdaptorElement childManager,
    AnimatedSliverList? widget,
  }) : super(childManager: childManager);

  /// Updates this render object against a new [AnimatedSliverList] Widget.
  void update(AnimatedSliverList widget) {
    widget.controller!._setAdaptor(this);
    intervals.clear();
    _notifying = false;
    _clearReordering();
    _tickers?.forEach((t) => _removeTicker(t));
    _tickers?.clear();
  }

  /// Creates a new ticker for animations.
  @override
  Ticker createTicker(final TickerCallback onTick) {
    var onTickNew = (Duration elapsed) {
      _markNeedsLayoutIfResizing();
      onTick(elapsed);
    };
    _tickers ??= <_WidgetTicker>{};
    final result = _WidgetTicker(onTickNew, this);
    _tickers!.add(result);
    return result;
  }

  /// Marks this render object to relayout its children when animating
  /// resizing or changing intervals.
  void _markNeedsLayoutIfResizing() {
    if (intervals.any((interval) =>
        interval.isInResizingState || interval.isInChangingState)) {
      markNeedsLayout();
    }
  }

  // Removes a ticker.
  void _removeTicker(_WidgetTicker ticker) {
    assert(_tickers != null);
    assert(_tickers!.contains(ticker));
    _tickers!.remove(ticker);
  }

  /// Disposing method that clears all previously created tickers and intervals.
  /// In addition, it releases the [AnimatedListController].
  void dispose() {
    intervals.clear();
    widget.controller?._setAdaptor(null);
    assert(() {
      if (_tickers != null) {
        for (final ticker in _tickers!) {
          if (ticker.isActive) {
            throw '$this was disposed with an active Ticker.';
          }
        }
      }
      return true;
    }());
  }

  /// It takes possession of the [AnimatedListController].
  void init() {
    widget.controller?._setAdaptor(this);
  }

  /// A `didChangeDependencies` method like in [State.didChangeDependencies],
  /// necessary to update the tickers correctly when the `muted` attribute changes.
  void didChangeDependencies(BuildContext context) {
    final muted = !TickerMode.of(context);
    if (_tickers != null) {
      for (final ticker in _tickers!) {
        ticker.muted = muted;
      }
    }
  }

  /// This method is responsible for creating the dragged widget during reordering.
  Widget buildDraggedChild(BuildContext context, int index) {
    return widget.animationBuilder.buildReordering(
        context,
        widget.delegate.builder(
            context, index, AnimatedListBuildType.REORDERING, _reorderSlot)!,
        index);
  }

  /// This method is responsible for creating the correct widget for a given child's index.
  Widget? buildAnimatedWidget(BuildContext context, int index) {
    Widget? itemWidget;
    var adj = intervals.search(
      index,
      removeFn: (interval) => itemWidget = AbsorbPointer(
          child: widget.animationBuilder.buildRemoving(
        context,
        interval.removeItemBuilder!(context, index - interval.index),
        interval.animation,
      )),
      insertFn: (interval) => itemWidget = AbsorbPointer(
          child: widget.animationBuilder.buildInserting(
        context,
        defaultInsertItemBuilder(context, index - interval.index, interval),
        interval.animation,
      )),
      changeFn: (interval) => itemWidget = AbsorbPointer(
          child: widget.animationBuilder.buildChanging(
        context,
        interval.removeItemBuilder!(context, index - interval.index),
        defaultInsertItemBuilder(context, index - interval.index, interval),
        interval.animation,
      )),
      resizeFn: (interval) => itemWidget = Container(key: ValueKey(interval)),
    );

    if (adj == null) return itemWidget;

    index += adj;

    /// Create a normal (not animating) widget
    itemWidget =
        callBuildDelegateCallback(context, index, AnimatedListBuildType.NORMAL);

    // we insert a invisible boundary item at the end of the list in order to have
    // always an item in the viewport on the borders between this sliver and the next, so
    // to avoid a recalculation of the items in performLayout from scratch, thus causing
    // an annoying scroll jump due to an estimation error in calculating the size of
    // one or more resizing intervals
    if (itemWidget == null &&
        callBuildDelegateCallback(
                context, index - 1, AnimatedListBuildType.MEASURING) !=
            null) {
      return _BoundaryChild();
    }

    return itemWidget;
  }

  /// Delegates the creation of the item Widget to the
  /// [AnimatedSliverChildBuilderDelegate.build] method.
  Widget? callBuildDelegateCallback(
      BuildContext context, int index, AnimatedListBuildType buildType) {
    childManager.buildType = buildType;
    return widget.delegate.build(context, index);
  }

  bool _notifying = false;

  // Called from [AnimatedListController] when the user notified that a range
  // of its list has been replaced by a new one. This method is also called
  // in case of a simple insertion or removal.
  void _notifyReplacedRange(final int from, final int removeCount,
      final int insertCount, final IndexedWidgetBuilder? removeItemBuilder) {
    if (removeCount == 0 && insertCount == 0) return;
    if (!_notifying) _notifying = true;
    _insertAndAdjust(from, removeCount, insertCount, removeItemBuilder,
        _insertNewInterval, false);
  }

  // Called from [AnimatedListController] when the user notified that a range
  // of its list has been changed.
  void _notifyChangedRange(final int from, final int count,
      final IndexedWidgetBuilder changeItemBuilder) {
    if (count == 0) return;
    if (!_notifying) _notifying = true;
    _insertAndAdjust(from, count, count, changeItemBuilder,
        _insertNewChangingInterval, true);
  }

  // Called from [AnimatedListController] when the user has finished notifying
  // any changes of its list. All pending notification will be optimized first,
  // then all animations that follow will start.
  void _dispatchChanges() {
    if (!_notifying) return;
    intervals.optimize();
    _notifying = false;
    _startAnimations();
  }

  // Core method for adapting or creating new intervals on a new user notification.
  void _insertAndAdjust(
    int from,
    int removeCount,
    int insertCount,
    final IndexedWidgetBuilder? removeItemBuilder,
    final AnimatedListIntervalCreationCallback callback,
    final bool animating,
  ) {
    var adjust = 0;
    var rba = 0;
    for (var i = 0; i < intervals.length; i++) {
      final to = from + removeCount;

      final interval = intervals[i];
      final ifrom = interval.index + adjust;
      final ito = ifrom + interval.insertCount;

      //  from       to                          ifrom       ito
      //   v          v                            v          v
      //   +++++++++++  (new rem/chg interval)     ooooooooooo  (existing final (after inserting) interval)
      // Note: X indicates overlap

      int adjustInterval(
          int rem, int ins, int leading, int trailing, int rbaAdjust) {
        return intervals.adjustInterval(
            interval,
            rem,
            ins,
            leading,
            trailing,
            widget.animationBuilder,
            _shiftItemBuilder(removeItemBuilder, rba + rbaAdjust),
            callback,
            animating);
      }

      if (from < ifrom) {
        if (to <= ifrom) {
          // [+++  ooooo] -> [+++++ooooo]
          break;
        } else if (to <= ito) {
          // [+++++XXXoo] -> [+++++XXXXX]
          final leading = ifrom - from;
          final rem = removeCount - leading;
          final ins = min(rem, insertCount);
          adjustInterval(rem, ins, 0, ito - to, leading);
          insertCount -= ins;
          removeCount -= rem;
          break;
        } else {
          // [+++++XXXXX+++++]
          final overlapSize = ito - ifrom;
          final leading = ifrom - from;
          var rem = leading;
          var ins = min(rem, insertCount);
          callback(from - adjust, rem, ins,
              _shiftItemBuilder(removeItemBuilder, rba));
          i++;
          rba += leading;
          insertCount -= ins;
          removeCount -= rem;
          rem = overlapSize;
          ins = min(rem, insertCount);
          final adj = interval.adjustingItemCount;
          final a = adjustInterval(rem, ins, 0, 0, 0);
          if (a >= 0) {
            adjust += adj;
            from = ito;
          }
          i += a;
          rba += overlapSize;
          insertCount -= ins;
          removeCount -= rem;
          continue;
        }
      } else if (from < ito) {
        if (to <= ito) {
          // [ooXXoo] -> [XXXXXX]
          adjustInterval(removeCount, insertCount, from - ifrom, ito - to, 0);
          return;
        } else {
          // [ooXXXX++++++] -> [XXXXXX++++++]
          final rem = ito - from;
          final ins = min(rem, insertCount);
          final adj = interval.adjustingItemCount;
          final a = adjustInterval(rem, ins, from - ifrom, 0, 0);
          if (a >= 0) {
            adjust += adj;
            from = ito;
          }
          i += a;
          rba += rem;
          insertCount -= ins;
          removeCount -= rem;
          continue;
        }
      } else {
        // [oooooo++++++++] -> [oooooo   ++++++++]
      }
      adjust += interval.adjustingItemCount;
    }

    callback(from - adjust, removeCount, insertCount,
        _shiftItemBuilder(removeItemBuilder, rba));
  }

  // Creates a new interval in initial removing or resizing status.
  AnimatedListInterval _insertNewInterval(final int from, final int removeCount,
      final int insertCount, final IndexedWidgetBuilder? removeItemBuilder,
      [final AnimatedListIntervalEventCallback? onDisposed]) {
    var interval = intervals.insertReplacingInterval(
      vsync: this,
      animationSettings: widget.animatedListAnimationSettings,
      index: from,
      insertCount: insertCount,
      removeCount: removeCount,
      removeItemBuilder: removeItemBuilder,
      onRemovingCompleted: _onIntervalRemovingCompleted,
      onResizingCompleted: _onIntervalResizingCompleted,
      onInsertingCompleted: _onIntervalInsertingCompleted,
      onCompleted: _onIntervalCompleted,
      onDisposed: onDisposed,
    );
    childManager.onUpdateOnNewInterval(interval);
    return interval;
  }

  // Creates a new interval in initial changing status.
  AnimatedListInterval _insertNewChangingInterval(
      final int from,
      final int removeCount,
      final int insertCount,
      final IndexedWidgetBuilder? removeItemBuilder,
      [final AnimatedListIntervalEventCallback? onDisposed]) {
    assert(removeCount == insertCount);
    var interval = intervals.insertChangingInterval(
      vsync: this,
      animationSettings: widget.animatedListAnimationSettings,
      index: from,
      changeCount: removeCount,
      removeItemBuilder: removeItemBuilder,
      onChangingCompleted: _onIntervalChangingCompleted,
      onCompleted: _onIntervalCompleted,
      onDisposed: onDisposed,
    );
    childManager.onUpdateOnNewInterval(interval);
    return interval;
  }

  // Called when interval states change in order to start next animations.
  void _startAnimations() {
    if (!_notifying && !isReordering) {
      intervals.startAnimations(widget.coordinateAnimations);
    }
  }

  // Called when a removing interval is completed.
  void _onIntervalRemovingCompleted(AnimatedListInterval interval) {
    childManager.onUpdateOnIntervalRemovedToResizing(interval);
    _startAnimations();
  }

  // Called when a resizing interval is completed.
  void _onIntervalResizingCompleted(AnimatedListInterval interval) {
    if (interval.insertCount == 0) {
      childManager.onUpdateOnIntervalResizedToDisposing(interval);
    } else {
      childManager.onUpdateOnIntervalResizedToInserting(interval);
    }
    _startAnimations();
  }

  // Called when a inserting interval is completed.
  void _onIntervalInsertingCompleted(AnimatedListInterval interval) {
    childManager.onUpdateOnIntervalInsertedToDisposing(interval);
    _startAnimations();
  }

  // Called when a changing interval is completed.
  void _onIntervalChangingCompleted(AnimatedListInterval interval) {
    childManager.onUpdateOnIntervalChangedToDisposing(interval);
    _startAnimations();
  }

  // Called when an interval has completed its lifecycle.
  void _onIntervalCompleted(AnimatedListInterval interval) {
    _startAnimations();
  }

  /// The builder used to build the new items that are going to be inserted
  /// within an inserting interval.
  /// The builder picks the item directly from the final changed underlying list.
  Widget defaultInsertItemBuilder(
      BuildContext context, int index, AnimatedListInterval interval) {
    index += interval.index;
    var i = intervals.indexOf(interval);
    assert(i >= 0);
    for (var j = 0; j < i; j++) {
      var prevInterval = intervals[j];
      index += prevInterval.adjustingItemCount;
    }
    return callBuildDelegateCallback(
        context, index, AnimatedListBuildType.INSERTING)!;
  }

  @override
  AnimatedSliverMultiBoxAdaptorElement get childManager =>
      super.childManager as AnimatedSliverMultiBoxAdaptorElement;

  /// This method has been overridden for the needs of the reordering for two reasons:
  /// - do not paint the original hidden dragged item: we keep it in the sliver because
  ///   we want it to be kept alive during all the reoder, but with a zero size;
  /// - paint the visible dragged item at the end (and above) of all the others children.
  @override
  RenderBox? childAfter(RenderBox child) {
    if (_inPaint && isReordering) {
      if (child == childManager.reorderDraggedRenderBox) return null;
      var after = super.childAfter(child);
      if (after == childManager.reorderRemovedChild) {
        after = super.childAfter(after!);
      } else {
        after ??= childManager.reorderDraggedRenderBox;
      }
      return after;
    }
    return super.childAfter(child);
  }

  bool _inPaint = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    _inPaint = true;
    super.paint(context, offset);
    _inPaint = false;
  }

  /// This method has been overridden in order to:
  /// - measure any new or modified resizing intervals;
  /// - scroll the first child up or down by the amount of space given by icreasing or decreasing
  ///   the size of the resizing intervals above it;
  /// - in case of reordering the new drop position is calculated;
  /// - in case of reordering the visible dragged item will be layouted and a scroll up or down
  ///   could be required when the latter is at the top or the bottom of the viewport;
  /// - if required by [AnimatedSliverList.updateScrollableWhenResizing] attribute notifies
  ///   any scroll listeners when a resizing interval is animating.
  @override
  void performLayout() {
    assert(!childManager.hasPendingUpdates);

    // measure new resizing intervals
    BoxConstraints? childConstraints;
    double? maxSize;
    intervals
        .where((i) =>
            i.isInResizingState && (i.fromSize == null || i.toSize == null))
        .forEach((interval) {
      childManager.owner!.buildScope(childManager, () {
        invokeLayoutCallback<SliverConstraints>(
            (final SliverConstraints constraints) {
          childConstraints ??= constraints.asBoxConstraints();
          maxSize ??= constraints.viewportMainAxisExtent +
              (parent as RenderViewport).cacheExtent! * 2;
          interval.measureSizesIfNeeded(
              () => childManager.measureOffListChildren(interval.removeCount,
                  maxSize!, interval.removeItemBuilder!, childConstraints!),
              () => childManager.measureOffListChildren(
                  interval.insertCount,
                  maxSize!,
                  (c, i) => defaultInsertItemBuilder(c, i, interval),
                  childConstraints!));
          assert(interval.fromSize != null && interval.toSize != null);
        });
      });
    });

    var offsetCorrection = _adjustScrollOffset();

    // keep always alive the hidden dragged child
    if (childManager.reorderRemovedChild != null &&
        !_parentDataOf(childManager.reorderRemovedChild!)!.keepAlive &&
        !_parentDataOf(childManager.reorderRemovedChild!)!.keptAlive) {
      _parentDataOf(childManager.reorderRemovedChild!)!.keepAlive = true;
    }

    super.performLayout();

    if (isReordering) _computeNewReorderingOffset();

    // prevent many items from scrolling up out of the viewport when
    // resizing intervals placed before the first child shrink
    if (!isReordering && offsetCorrection != 0.0) {
      offsetCorrection += geometry!.scrollOffsetCorrection ?? 0.0;
      geometry = SliverGeometry(
        scrollExtent: geometry!.scrollExtent,
        paintExtent: geometry!.paintExtent,
        paintOrigin: geometry!.paintOrigin,
        layoutExtent: geometry!.layoutExtent,
        maxPaintExtent: geometry!.maxPaintExtent,
        maxScrollObstructionExtent: geometry!.maxScrollObstructionExtent,
        hitTestExtent: geometry!.hitTestExtent,
        visible: geometry!.visible,
        hasVisualOverflow: geometry!.hasVisualOverflow,
        scrollOffsetCorrection:
            offsetCorrection != 0.0 ? offsetCorrection : null,
        cacheExtent: geometry!.cacheExtent,
      );
    }

    var resizing = intervals.any((interval) => interval.isInResizingState);

    if (resizing && !isReordering && widget.updateScrollableWhenResizing) {
      _notifyScrollable();
    }

    if (isReordering && childManager.reorderDraggedRenderBox != null) {
      childManager.reorderDraggedRenderBox!
          .layout(constraints.asBoxConstraints(), parentUsesSize: true);

      var currentOffset = currentReorderingChildOffset;
      _parentDataOf(childManager.reorderDraggedRenderBox!)!.layoutOffset =
          currentOffset;

      // scroll up/down as needed while dragging
      var fromOffset = constraints.scrollOffset;
      var toOffset = fromOffset + constraints.remainingPaintExtent;

      var controller = Scrollable.of(childManager)?.widget.controller;
      var position = controller?.position;

      var delta = 0.0;
      if (currentOffset < fromOffset && position!.extentBefore > 0.0) {
        delta = -_kReorderingScrollSpeed;
      } else if (currentOffset + _reorderChildSize! > toOffset &&
          position!.extentAfter > 0.0) {
        delta = _kReorderingScrollSpeed;
      }

      if (delta != 0.0) {
        final value = position!.pixels + delta;
        WidgetsBinding.instance!.addPostFrameCallback((_) {
          controller!.jumpTo(value);
          markNeedsLayout();
        });
      }
    }

    // if (widget.delegate.onLayoutPerformed != null) {
    //   int? from, to;
    //   for (var child = firstChild; child != null; child = childAfter(child)) {
    //     if (isBoundaryChild(child)) continue;
    //     var index = _parentDataOf(child)?.index;
    //     var adj = intervals.search(index);
    //     if (adj != null) {
    //       from = index + adj;
    //       break;
    //     }
    //   }
    //   if (from != null) {
    //     to = from;
    //     for (var child = lastChild; child != null; child = childBefore(child)) {
    //       if (isBoundaryChild(child)) continue;
    //       var index = _parentDataOf(child)?.index;
    //       var adj = intervals.search(index);
    //       if (adj != null) {
    //         to = index + adj;
    //         break;
    //       }
    //     }
    //     widget.delegate.onLayoutPerformed.call(from, to);
    //   }
    // }
  }

  // Returns the scroll offset correction that takes into account of the changed
  // space of the resizing intervals from their last rendered frame.
  // The first child will also be moved up or down according to it.
  double _adjustScrollOffset() {
    var offsetCorrection = 0.0;

    var firstChild = _findEarliestUsefulChild();
    if (firstChild == null) return 0.0;

    final parentData = _parentDataOf(firstChild)!;

    final firstIndex = parentData.index!;

    offsetCorrection = childManager.calculateOffsetCorrection(firstIndex);

    if (offsetCorrection != 0.0) {
      final firstOffset = parentData.layoutOffset!;
      if (firstOffset + offsetCorrection < 0.0) {
        offsetCorrection = -firstOffset; // bring back first offset to zero
      }
      parentData.layoutOffset = parentData.layoutOffset! + offsetCorrection;
    }

    return offsetCorrection;
  }

  RenderBox? _findEarliestUsefulChild() {
    if (firstChild == null) {
      return null;
    }

    final scrollOffset = constraints.scrollOffset + constraints.cacheOrigin;
    assert(scrollOffset >= 0.0);
    final remainingExtent = constraints.remainingCacheExtent;
    assert(remainingExtent >= 0.0);

    var earliestUsefulChild = firstChild;

    if (childScrollOffset(firstChild!) == null) {
      while (earliestUsefulChild != null &&
          childScrollOffset(earliestUsefulChild) == null) {
        earliestUsefulChild = childAfter(earliestUsefulChild);
      }
      if (firstChild == null) {
        return null;
      }
    }

    return earliestUsefulChild;
  }

  /// This method has been overridden to consider also the visible dragged child.
  @override
  void visitChildren(visitor) {
    super.visitChildren(visitor);
    if (childManager.reorderDraggedRenderBox != null) {
      assert(isReordering);
      visitor.call(childManager.reorderDraggedRenderBox!);
    }
  }

  /// Dispatch a "fake" change to the [ScrollPosition] to force the listeners
  /// (ie a [ScrollBar]) to refresh its state.
  void _notifyScrollable() {
    var position = Scrollable.of(childManager)?.widget.controller?.position;
    if (position == null) return;
    ScrollUpdateNotification(
            metrics: position.copyWith(),
            context: childManager,
            scrollDelta: 0,
            dragDetails: null)
        .dispatch(childManager);
  }

  /// Estimates the max scroll offset based on the rendered viewport data.
  double? extrapolateMaxScrollOffset(
    final int? firstIndex,
    final int? lastIndex,
    final double? leadingScrollOffset,
    final double? trailingScrollOffset,
    final int childCount,
  ) {
    assert(!childManager.hasPendingUpdates);

    if (lastIndex == childCount - 1) return trailingScrollOffset;

    var innerSpace = 0.0, trailingSpace = 0.0;
    var innerCount = 0, trailingCount = 0;
    for (final interval in intervals) {
      if (!interval.isInResizingState) continue;
      if (firstIndex! <= interval.index) {
        if (interval.index <= lastIndex!) {
          innerCount++;
          innerSpace += interval.currentSize;
        } else {
          trailingCount++;
          trailingSpace += interval.currentSize;
        }
      }
    }

    var ret = trailingScrollOffset! + trailingSpace;

    final remainingCount = childCount - lastIndex! - trailingCount - 1;
    if (remainingCount > 0) {
      var reifiedCount = 1 + lastIndex - firstIndex! - innerCount;
      if (isReordering) {
        // exclude from refied count the zero sized being dragged child
        var i = _reorderPickedIndex;
        for (final interval in intervals) {
          assert(interval.isInResizingState);
          if (interval.index > i!) break;
          i++;
        }
        if (firstIndex <= i! && i <= lastIndex) {
          reifiedCount--;
        }
      }
      double averageExtent;
      if (reifiedCount > 0) {
        averageExtent =
            (trailingScrollOffset - leadingScrollOffset! - innerSpace) /
                reifiedCount;
      } else {
        var size = 0.0;
        var count = 0;
        for (final interval in intervals) {
          if (interval.isInResizingState) {
            if (firstIndex <= interval.index && interval.index <= lastIndex) {
              assert(interval.fromSize != null && interval.toSize != null);
              size += interval.fromSize! + interval.toSize!;
              count += interval.removeCount + interval.insertCount;
            }
          }
        }
        averageExtent = size / count;
      }
      ret += averageExtent * remainingCount;
    }
    return ret;
  }

  /// This method has been overridden in order to:
  /// - return the current size of the resizing intervals;
  /// - when reordering, the hidden dragged item must return a zero size.
  @override
  @protected
  double paintExtentOf(final RenderBox child) {
    var parentData = _parentDataOf(child);
    if (isReordering && child == childManager.reorderRemovedChild) return 0.0;
    if (parentData!.index != null) {
      var interval = childManager.intervalAtIndex(indexOf(child));
      if (interval != null && interval.isInResizingState) {
        return interval.currentSize;
      }
    }
    return super.paintExtentOf(child);
  }

  int? _reorderPickedIndex, _reorderDropIndex;
  double? _reorderChildSize;
  double? _reorderStartOffset,
      _reorderOffsetX,
      _reorderDeltaOffset,
      _reorderLastOffset,
      _reorderScrollOffset;

  /// Returns `true` if a reordering process is in progress.
  bool get isReordering => _reorderPickedIndex != null;

  /// Returns `true` if the list view is animating (that is, one o more intervals exist).
  bool get isAnimating => intervals.isNotEmpty;

  /// Returns the current offset of the visible dragged item.
  double get currentReorderingChildOffset {
    return isReordering
        ? (_reorderStartOffset! +
                _reorderDeltaOffset! +
                (constraints.scrollOffset - _reorderScrollOffset!))
            .clamp(0.0, geometry!.maxPaintExtent - _reorderChildSize!)
        : 0.0;
  }

  void _startReordering(int index, double offsetX, double offsetY) {
    childManager.onUpdateOnStartReording(index);

    _reorderChildSize = paintExtentOf(childManager.reorderRemovedChild!);

    _reorderScrollOffset = constraints.scrollOffset;
    _reorderPickedIndex = index;
    _reorderDropIndex = index;
    _reorderDeltaOffset = 0.0;
    _reorderOffsetX = 0.0;
    _reorderStartOffset = _reorderLastOffset =
        _parentDataOf(childManager.reorderRemovedChild!)!.layoutOffset;

    var interval = intervals.insertReorderingInterval(
      vsync: this,
      animationSettings: widget.animatedListAnimationSettings,
      index: index + 1,
      size: _reorderChildSize,
      appearing: false,
      onResizingCompleted: _onIntervalResizingCompleted,
    );
    childManager.onUpdateOnNewInterval(interval);
  }

  void _updateReordering(double dx, double dy) {
    assert(isReordering);
    _reorderOffsetX = dx;
    _reorderDeltaOffset = dy;
    markNeedsLayout();
  }

  void _computeNewReorderingOffset() {
    assert(!childManager.hasPendingUpdates);

    var currentOffset = currentReorderingChildOffset;
    if (currentOffset == _reorderLastOffset) return;

    int? newIndex;

    bool move(RenderBox child, double? childOffset,
        bool Function(double a, double b) fn) {
      if (isBoundaryChild(child)) return true;

      var pd = _parentDataOf(child)!;
      var space = 0.0;
      var adj = 0;
      var j = pd.index;

      for (var i in intervals) {
        if (i.index == j) {
          return true;
        } else if (i.index > j!) break;
        space += i.currentSize;
        adj++;
      }

      var yc1 = pd.layoutOffset! - space + childOffset!;
      var yc2 = yc1 + paintExtentOf(child);

      if (fn.call(currentOffset + childOffset - yc1, yc2 - yc1)) return false;

      newIndex = j! - adj;

      return true;
    }

    if (currentOffset > _reorderLastOffset!) {
      // move down
      for (var child = firstChild; child != null; child = childAfter(child)) {
        if (!move(child, _reorderChildSize, (a, b) => a < b * 0.75)) break;
      }
      if (newIndex != null) {
        newIndex = newIndex! + 1;
        if (newIndex! < _reorderDropIndex!) {
          newIndex = null;
        }
      }
    } else {
      // move up
      for (var child = lastChild; child != null; child = childBefore(child)) {
        if (!move(child, 0.0, (a, b) => a > b * 0.25)) break;
      }
      if (newIndex != null && newIndex! > _reorderDropIndex!) {
        newIndex = null;
      }
    }

    if (newIndex != null) {
      if (newIndex! >= _reorderPickedIndex! + 1) {
        newIndex = newIndex! - 1;
      }
      WidgetsBinding.instance!.addPostFrameCallback((_) {
        _updateReorderingIntervals(newIndex!);
      });
    }

    _reorderLastOffset = currentOffset;
  }

  /// Returns `true` if the render box is the last boundary invisibile item.
  bool isBoundaryChild(RenderBox child) =>
      childManager.widgetOf(_parentDataOf(child)?.index) is _BoundaryChild;

  dynamic _reorderSlot;

  void _feedback(
      int index, int dropIndex, double offset, double dx, double dy) {
    var newSlot = widget.delegate.onReorderFeedback
        ?.call(index, dropIndex, offset, dx, dy);
    if (_reorderSlot != newSlot) {
      _reorderSlot = newSlot;
      childManager.markNeedsBuild();
    }
  }

  void _updateReorderingIntervals(int newIndex) {
    if (_reorderDropIndex == newIndex ||
        !(widget.delegate.onReorderMove?.call(_reorderPickedIndex!, newIndex) ??
            false)) {
      return;
    }

    _feedback(_reorderPickedIndex!, newIndex, currentReorderingChildOffset,
        _reorderOffsetX!, _reorderDeltaOffset!);

    _reorderDropIndex = newIndex;

    if (newIndex > _reorderPickedIndex!) newIndex++;

    var adj = 0, j = 0;
    var create = true;

    for (var i = 0; i < intervals.length; i++) {
      var interval = intervals[i];

      assert(interval.isInResizingState && interval.isReordering);
      if (interval.index != newIndex + adj) {
        if (interval.isWaiting) {
          // the interval is in its full size waiting to be closed...
          // so let's give it the signal
          interval.startAnimation();
        } else {
          // the interval is animating to reach its full size...
          // let's give the signal to resize to dismiss
          if (interval.resize(0.0)) {
            i--;
            continue;
          }
        }
      } else {
        // the interval already exists, just resize it to its full size
        interval.resize(_reorderChildSize);
        create = false;
      }
      if (interval.index < newIndex + adj) j++;
      adj++;
    }

    if (create) {
      var interval = intervals.insertReorderingInterval(
        vsync: this,
        animationSettings: widget.animatedListAnimationSettings,
        index: newIndex + j,
        size: _reorderChildSize,
        appearing: true,
        onResizingCompleted: _onIntervalResizingCompleted,
      );
      childManager.onUpdateOnNewInterval(interval);
    }
  }

  void _stopReordering(bool cancel) {
    intervals.finishReorder();

    childManager.onUpdateOnStopReording(
        _reorderPickedIndex!, cancel ? null : _reorderDropIndex);

    _clearReordering();

    print('_stopReordering');
  }

  void _clearReordering() {
    _reorderPickedIndex = null;
    _reorderDropIndex = null;
    _reorderChildSize = null;
    _reorderStartOffset = null;
    _reorderDeltaOffset = null;
    _reorderOffsetX = null;
    _reorderLastOffset = null;
    _reorderScrollOffset = null;
    _reorderSlot = null;
  }

  /// Redefine the original [RenderSliverMultiBoxAdaptor.indexOf] method by
  /// removing an assertion to accept any off-list elements.
  @override
  int indexOf(final RenderBox child) {
    return _parentDataOf(child)!.index!;
  }

  SliverMultiBoxAdaptorParentData? _parentDataOf(RenderBox child) =>
      child.parentData as SliverMultiBoxAdaptorParentData?;

  String toDebugString() => intervals.toDebugString();
}

// Copied from standard package.
class _WidgetTicker extends Ticker {
  _WidgetTicker(TickerCallback onTick, this._creator) : super(onTick);

  final AnimatedRenderSliverList _creator;

  @override
  void dispose() {
    _creator._removeTicker(this);
    super.dispose();
  }
}

//---------------------------------------------------------------------------------------------
// AnimatedSliverChildBuilderDelegate
//---------------------------------------------------------------------------------------------

int _kDefaultSemanticIndexCallback(Widget _, int localIndex) => localIndex;

int? _kChildCount() => null;

/// Class copied and adapted from [SliverChildBuilderDelegate].
///
/// The [builder] has been changed using a new callback that has a new additional parameter
/// indicating the status of the item. You have to expecially use it to specify a key
/// only when the state is [AnimatedListBuildType.NORMAL].
///
/// The [childCount] attribute has been replaced with a callback function. This callback
/// has to return the actual length of your list that will be changed after every change,
/// insertion, removal and replacement. A `null` value can be also returned, especially for
/// infinite lists.
///
/// New redorder callbacks have been added in order to handle the reordering:
/// - [onReorderStart] called first when it would like to start reordering the specified item by index;
///   two other additional parameters are passed that indicate the offset of the tap/click
///   from the top left corner of the item; if `false` is returned, the reorder won't start at all;
/// - [onReorderFeedback] called whenever the item is moved by dragging; the item's index is
///   passed again, then the index where it would like to move, the offset from the top of the sliver and
///   finally a delta indicating the distance of the new tapped/clicked point from the original one;
///   Any value can be returned. If the last returned value is changed, a rebuild wil be invoked.
///   The returned value will be passed to the [builder] as the last optional parameter.
/// - [onReorderMove] called when the dragged item, indicated by the first index, would like to
///   move with the item indicated by the second index; if `false` is returned, the move
///   won't be taken into consideration at all.
/// - [onReorderComplete] called at the end of reorder when the move must actually be done;
///   the last returned value from [onReorderFeedback] will also be passed; implement this callback
///   to update your underlying list; return `false` if you want to cancel the move.
///
/// The [rebuildMovedItems] attribute if set to `true` (by default) forces items to be rebuilt
/// who have changed their position; it is recommended when you store the index inside the widget or
/// of a closure.
class AnimatedSliverChildBuilderDelegate extends SliverChildDelegate {
  AnimatedSliverChildBuilderDelegate(
    this.builder, {
    this.findChildIndexCallback,
    this.childCount = _kChildCount,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.semanticIndexCallback = _kDefaultSemanticIndexCallback,
    this.semanticIndexOffset = 0,
    this.onReorderStart,
    this.onReorderFeedback,
    this.onReorderMove,
    this.onReorderComplete,
    this.rebuildMovedItems = true,
  });

  final AnimatedNullableIndexedWidgetBuilder builder;
  final int? Function() childCount;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;
  final int semanticIndexOffset;
  final SemanticIndexCallback semanticIndexCallback;
  final ChildIndexGetter? findChildIndexCallback;
  final bool rebuildMovedItems;

  final bool Function(int index, double dx, double dy)? onReorderStart;
  final dynamic Function(
          int index, int dropIndex, double offset, double dx, double dy)?
      onReorderFeedback;
  final bool Function(int index, int dropIndex)? onReorderMove;
  final bool Function(int index, int dropIndex, dynamic slot)?
      onReorderComplete;

  /// Not used anymore.
  @override
  @mustCallSuper
  int findIndexByKey(Key key) {
    throw "The method 'findIndexByKey' is not used anymore";
  }

  /// Copied from [SliverChildBuilderDelegate.build].
  /// This method has been modified to handle the new build type attribute
  /// which indicates in what state the item should be created.
  /// In addition, the new callback [AnimatedSliverChildBuilderDelegate.childCount]
  /// will be called instead of just an attribute.
  /// If the reordering is enabled, a long tap detector will also be added.
  @override
  Widget? build(BuildContext context, int index) {
    final childManager = context as AnimatedSliverMultiBoxAdaptorElement;
    final buildType = childManager.buildType;
    final count = childCount.call();
    if (index < 0 || (count != null && index >= count)) return null;
    Widget? child;
    try {
      child = builder(context, index, buildType);
    } catch (exception, stackTrace) {
      child = _createErrorWidget(exception, stackTrace);
    }
    if (child == null) {
      return null;
    }

    final Key? key = child.key != null ? _SaltedValueKey(child.key!) : null;
    if (addRepaintBoundaries) child = RepaintBoundary(child: child);
    if (addSemanticIndexes && buildType != AnimatedListBuildType.NORMAL) {
      final semanticIndex = semanticIndexCallback(child, index);
      if (semanticIndex != null) {
        child = IndexedSemantics(
            index: semanticIndex + semanticIndexOffset, child: child);
      }
    }

    if (childManager.widget.reorderable) {
      child = GestureDetector(
        onPanCancel: () {
          var renderObject = childManager.renderObject;
          if (renderObject.isReordering) {
            renderObject._stopReordering(true);
          }
        },
        onLongPressStart: (d) {
          var renderObject = childManager.renderObject;
          if (!renderObject.isAnimating &&
              (onReorderStart?.call(
                      index, d.localPosition.dx, d.localPosition.dy) ??
                  false)) {
            renderObject._startReordering(index, 0, 0);
            renderObject._feedback(
                renderObject._reorderPickedIndex!,
                renderObject._reorderDropIndex!,
                renderObject.currentReorderingChildOffset,
                0.0,
                0.0);
          }
        },
        onLongPressEnd: (d) {
          var renderObject = childManager.renderObject;
          if (renderObject.isReordering) {
            var cancel = (!(onReorderComplete?.call(
                    renderObject._reorderPickedIndex!,
                    renderObject._reorderDropIndex!,
                    renderObject._reorderSlot) ??
                false));
            renderObject._stopReordering(cancel);
          }
        },
        onLongPressMoveUpdate: (d) {
          var renderObject = childManager.renderObject;
          if (renderObject.isReordering) {
            renderObject._updateReordering(
                d.localOffsetFromOrigin.dx, d.localOffsetFromOrigin.dy);
            renderObject._feedback(
                renderObject._reorderPickedIndex!,
                renderObject._reorderDropIndex!,
                renderObject.currentReorderingChildOffset,
                renderObject._reorderOffsetX!,
                renderObject._reorderDeltaOffset!);
          }
        },
        child: child,
      );
    }

    if (addAutomaticKeepAlives && buildType == AnimatedListBuildType.NORMAL) {
      child = AutomaticKeepAlive(child: child);
    }

    return KeyedSubtree(key: key, child: child);
  }

  /// Method not supported yet. Don't override it!
  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    throw "'estimateMaxScrollOffset' method not supported yet.";
  }

  /// Copied from [SliverChildBuilderDelegate.estimatedChildCount].
  /// The new callback [AnimatedSliverChildBuilderDelegate.childCount]
  /// will be called instead of just an attribute.
  @override
  int? get estimatedChildCount => childCount();

  /// Copied from [SliverChildBuilderDelegate.shouldRebuild].
  @override
  bool shouldRebuild(
          covariant AnimatedSliverChildBuilderDelegate oldDelegate) =>
      true;
}

class _SaltedValueKey extends ValueKey<Key> {
  const _SaltedValueKey(Key key) : super(key);
}

IndexedWidgetBuilder? _shiftItemBuilder(
    final IndexedWidgetBuilder? builder, final int leading) {
  if (leading == 0 || builder == null) return builder;
  return (context, index) => builder.call(context, index + leading);
}

// Return a Widget for the given Exception (copied from standard package).
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

class _BoundaryChild extends SizedBox {
  _BoundaryChild() : super.shrink();
}
