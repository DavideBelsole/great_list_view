part of 'core.dart';

const Duration kDismissOrIncomingAnimationDuration =
    Duration(milliseconds: 500 * 1);
const Duration kResizeAnimationDuration = Duration(milliseconds: 500 * 1);
const Duration kReorderAnimationDuration = Duration(milliseconds: 250 * 1);

const Curve kDismissOrIncomingAnimationCurve = Curves.ease;
const Curve kResizeAnimationCurve = Curves.easeInOut;
const Curve kReorderAnimationCurve = Curves.linear;

const kAnimatedEvelationDuration = Duration(milliseconds: 600);
const kAnimatedEvelationValue = 30.0;

/// A delegate that supplies children for animated slivers, inspired by [SliverChildDelegate].
abstract class AnimatedSliverChildDelegate {
  const AnimatedSliverChildDelegate();

  /// Provides the initial child count of the underlying list.
  int get initialChildCount;

  /// Provides the builder of the items currently present in the undelying list.
  AnimatedWidgetBuilder get builder;

  /// Wrap a built child widget adding extra visual effects, animations and other.
  Widget wrapWidget(
      BuildContext context, Widget widget, AnimatedWidgetBuilderData data);

  /// Provides an animator to customize all the animations.
  AnimatedListAnimator get animator;

  /// Provides a model (a bunch of callbacks) to handle reorders.
  AnimatedListBaseReorderModel? get reorderModel;

  InitialScrollOffsetCallback? get initialScrollOffsetCallback;

  @override
  String toString() {
    final description = <String>[];
    return '${describeIdentity(this)}(${description.join(", ")})';
  }
}

/// Inspired by [SliverChildBuilderDelegate].
class AnimatedSliverChildBuilderDelegate extends AnimatedSliverChildDelegate {
  /// See [SliverChildBuilderDelegate.addAutomaticKeepAlives] for details.
  final bool addAutomaticKeepAlives;

  /// See [SliverChildBuilderDelegate.addRepaintBoundaries] for details.
  final bool addRepaintBoundaries;

  // final bool addSemanticIndexes;
  // final int semanticIndexOffset;
  // final SemanticIndexCallback semanticIndexCallback;

  /// Whether to wrap each child in a [LongPressReorderable].
  ///
  /// This allows the items to be dragged for reordering purpose with a long press gesture.
  ///
  /// Defaults to true.
  final bool addLongPressReorderable;

  /// Whether to wrap each child in a [AnimatedElevation].
  ///
  /// An elevation effect is automatically applied to the item picked up for reordering.
  /// See [Material.elevation] for details.
  ///
  /// Defaults to true.
  final bool addAnimatedElevation;

  /// Whether to wrap each child in a [FadeTransition].
  ///
  /// A fade effect is automatically applied to dismissing and incoming items.
  ///
  /// Defaults to true.
  final bool addFadeTransition;

  /// If provided, it wraps each child in a [MorphTransition].
  ///
  /// It adds a cross-fade effect to the items that change their content, fading out the old content
  /// and fading in the new one.
  /// This callback has to return `false` if the morph effect is to be applied, ie the new widget
  /// content is different from the old one. Avoid returning `false` when not needed, in order
  /// not to apply the effect unnecessarily when the two compared widgets are identical.
  ///
  /// Defaults to null.
  final MorphComparator? morphComparator;

  /// Whether to resize the widget it is changing when applying the [MorphTransition] effect.
  /// If `false`, the widget with the largst content will be cropped during the animation.
  /// See also [MorphTransition.resizeWidgets].
  ///
  /// Defaults to true.
  final bool morphResizeWidgets;

  final Duration morphDuration;

  @override
  final InitialScrollOffsetCallback? initialScrollOffsetCallback;

  /// Provides a model (a bunch of callbacks) to handle reorders.
  /// If `null` the list view cannot be reordered.
  ///
  /// Defaults to null.
  @override
  final AnimatedListBaseReorderModel? reorderModel;

  /// Provides the builder of the items currently present in the underlying list.
  @override
  final AnimatedWidgetBuilder builder;

  /// Provides an animator to customize all the animations.
  ///
  /// Defaults to an instance of [DefaultAnimatedListAnimator].
  @override
  final AnimatedListAnimator animator;

  AnimatedSliverChildBuilderDelegate(
    this.builder,
    int initialChildCount, {
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    // this.addSemanticIndexes = true,
    // this.semanticIndexCallback = _kDefaultSemanticIndexCallback,
    // this.semanticIndexOffset = 0,
    this.animator = const DefaultAnimatedListAnimator(),
    this.addLongPressReorderable = true,
    this.addAnimatedElevation = true,
    this.addFadeTransition = true,
    this.morphResizeWidgets = true,
    this.morphDuration = const Duration(milliseconds: 500),
    this.morphComparator,
    this.reorderModel,
    this.initialScrollOffsetCallback,
  })  : assert(initialChildCount >= 0),
        initialChildCount = initialChildCount;

  @override
  Widget wrapWidget(
      BuildContext context, Widget child, AnimatedWidgetBuilderData data) {
    if (data.measuring) return child;
    final Key? key = child.key != null ? _SaltedValueKey(child.key!) : null;
    if (morphComparator != null) {
      child = MorphTransition(
          duration: morphDuration,
          resizeWidgets: morphResizeWidgets,
          comparator: morphComparator!,
          child: child);
    }
    if (addFadeTransition) {
      child = FadeTransition(opacity: data.animation, child: child);
    }
    if (addAnimatedElevation) {
      child = AnimatedElevation(
        duration: kAnimatedEvelationDuration,
        elevation: data.dragging ? kAnimatedEvelationValue : 0.0,
        child: child,
      );
    }
    if (addLongPressReorderable && reorderModel != null) {
      child = LongPressReorderable(child: child);
    }
    if (addRepaintBoundaries) {
      child = RepaintBoundary(child: child);
    }
    // if (addSemanticIndexes) {
    //   final int? semanticIndex = semanticIndexCallback(child, index);
    //   if (semanticIndex != null) {
    //     child = IndexedSemantics(
    //         index: semanticIndex + semanticIndexOffset, child: child);
    //   }
    // }
    if (addAutomaticKeepAlives) {
      child = AutomaticKeepAlive(child: child);
    }
    return KeyedSubtree(key: key, child: child);
  }

  /// The initial count of the children present in the underlying list.
  /// This attribute is only read on the first build.
  @override
  final int initialChildCount;
}

/// This interface can be implemented to customize all animations.
/// [DefaultAnimatedListAnimator] is the default implementation.
abstract class AnimatedListAnimator {
  const AnimatedListAnimator();

  /// Provides info about the animation of an outgoing item.
  AnimatedListAnimationData dismiss();

  /// Provides info about the animation of an incoming item.
  AnimatedListAnimationData incoming();

  /// Provides info about the animation of an incoming item that doesn't complete and
  /// turns into an outgoing item.
  /// The current [time] of the incoming animation is provided (0 indicates it is
  /// just started whereas 1 is pratically completed).
  AnimatedListAnimationData dismissDuringIncoming(double time);

  /// Provides info about the animation of a resizing interval (space between items)
  /// that appear after removing/replacing old items or before inserting new ones.
  /// The starting [fromSize] and ending [toSize] measures of the interval are also provided.
  AnimatedListAnimationData resizing(_Measure fromSize, _Measure toSize);

  /// Provides info about the animation of a resizing interval (space between items)
  /// that appear only during reordering.
  /// The starting [fromSize] and ending [toSize] sizes of the interval are also provided.
  AnimatedListAnimationData resizingDuringReordering(
      double fromSize, double toSize);
}

/// Default implementation of the inteface [AnimatedListAnimator] that uses [CurveTween]s objects.
/// Custom animation durations and curves can also be provided.
class DefaultAnimatedListAnimator extends AnimatedListAnimator {
  final Duration dismissIncomingDuration, resizeDuration, reorderDuration;
  final Curve dismissIncomingCurve, resizeCurve, reorderCurve;

  const DefaultAnimatedListAnimator({
    this.dismissIncomingDuration = kDismissOrIncomingAnimationDuration,
    this.resizeDuration = kResizeAnimationDuration,
    this.reorderDuration = kReorderAnimationDuration,
    this.dismissIncomingCurve = kDismissOrIncomingAnimationCurve,
    this.resizeCurve = kResizeAnimationCurve,
    this.reorderCurve = kReorderAnimationCurve,
  });

  @override
  AnimatedListAnimationData dismissDuringIncoming(double dismissTime) {
    return AnimatedListAnimationData(
        Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: dismissIncomingCurve.flipped)),
        dismissIncomingDuration,
        1.0 - dismissTime);
  }

  @override
  AnimatedListAnimationData dismiss() {
    return AnimatedListAnimationData(
        Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: dismissIncomingCurve)),
        dismissIncomingDuration);
  }

  @override
  AnimatedListAnimationData incoming() {
    return AnimatedListAnimationData(
        CurveTween(curve: dismissIncomingCurve), dismissIncomingDuration);
  }

  @override
  AnimatedListAnimationData resizing(_Measure fromSize, _Measure toSize) {
    return AnimatedListAnimationData(
        CurveTween(curve: resizeCurve), resizeDuration);
  }

  @override
  AnimatedListAnimationData resizingDuringReordering(
      double fromSize, double toSize) {
    return AnimatedListAnimationData(
        CurveTween(curve: reorderCurve), reorderDuration);
  }
}

/// Holds the info about an animation.
/// The [animation] attribute is used to convert the linear animation (from 0.0 to 1.0) in a customized way,
/// like [Tween]s.
/// The [duration] attribute indicates the duration of the entire animation.
/// The [startTime] attribute, if is greater than zeor, indicates that the animation won't start from the beginning
/// but at a specific point.
class AnimatedListAnimationData {
  final Animatable<double> animation;
  final Duration duration;
  final double startTime;
  const AnimatedListAnimationData(this.animation, this.duration,
      [this.startTime = 0.0])
      : assert(startTime >= 0.0 && startTime <= 1.0);
}

/// Use this controller to notify to the [AnimatedListView] about changes in your underlying list and more.
class AnimatedListController {
  _ControllerInterface? _interface;

  /// Notifies the [AnimatedListView] that a range starting from [from] and [count] long
  /// has been modified. Call this method after actually you have updated your list.
  /// A new builder [changeItemBuilder] has to be provided in order to build the old
  /// items when animating.
  /// A [priority] can be also specified if you need to prioritize this notification.
  void notifyChangedRange(
      int from, int count, AnimatedWidgetBuilder changeItemBuilder,
      [int priority = 0]) {
    assert(_debugAssertBinded());
    _interface!.notifyChangedRange(from, count, changeItemBuilder, priority);
  }

  /// Notifies the [AnimatedListView] that a new range starting from [from] and [count] long
  /// has been inserted. Call this method after actually you have updated your list.
  /// A [priority] can be also specified if you need to prioritize this notification.
  void notifyInsertedRange(int from, int count, [int priority = 0]) {
    assert(_debugAssertBinded());
    _interface!.notifyInsertedRange(from, count, priority);
  }

  /// Notifies the [AnimatedListView] that a range starting from [from] and [count] long
  /// has been removed. Call this method after actually you have updated your list.
  /// A new builder [removeItemBuilder] has to be provided in order to build the removed
  /// items when animating.
  /// A [priority] can be also specified if you need to prioritize this notification.
  void notifyRemovedRange(
      int from, int count, AnimatedWidgetBuilder removeItemBuilder,
      [int priority = 0]) {
    assert(_debugAssertBinded());
    _interface!.notifyRemovedRange(from, count, removeItemBuilder, priority);
  }

  /// Notifies the [AnimatedListView] that a range starting from [from] and [removeCount] long
  /// has been replaced with a new [insertCount] long range. Call this method after
  /// you have updated your list.
  /// A new builder [removeItemBuilder] has to be provided in order to build the replaced
  /// items when animating.
  /// A [priority] can be also specified if you need to prioritize this notification.
  void notifyReplacedRange(int from, int removeCount, int insertCount,
      AnimatedWidgetBuilder removeItemBuilder,
      [int priority = 0]) {
    assert(_debugAssertBinded());
    _interface!.notifyReplacedRange(
        from, removeCount, insertCount, removeItemBuilder, priority);
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
  /// Use this method only if you have decided not to use the
  /// [AnimatedSliverChildBuilderDelegate.addLongPressReorderable] attribute or the
  /// [LongPressReorderable] widget (for example if you want to reorder using your
  /// custom drag handles).
  void notifyStartReorder(BuildContext context, double dx, double dy) {
    assert(_debugAssertBinded());
    _interface!.notifyStartReorder(context, dx, dy);
  }

  /// Notifies the [AnimatedListView] that the dragged item has moved.
  /// The attributs [dx] and [dy] are the coordinates relative to the original position of the item.
  /// Use this method only if you have decided not to use the
  /// [AnimatedSliverChildBuilderDelegate.addLongPressReorderable] attribute or the
  /// [LongPressReorderable] widget (for example if you want to reorder using your
  /// custom drag handles).
  void notifyUpdateReorder(double dx, double dy) {
    assert(_debugAssertBinded());
    _interface!.notifyUpdateReorder(dx, dy);
  }

  /// Notifies the [AnimatedListView] that the reorder has finished or cancelled.
  /// Use this method only if you have decided not to use the
  /// [AnimatedSliverChildBuilderDelegate.addLongPressReorderable] attribute or the
  /// [LongPressReorderable] widget (for example if you want to reorder using your
  /// custom drag handles).
  void notifyStopReorder(bool cancel) {
    assert(_debugAssertBinded());
    _interface!.notifyStopReorder(cancel);
  }

  /// Computes the box (in pixels) of the item indicated by the index provided.
  /// If [absolute] is `false` the offset is relative to the upper edge of the list view or sliver,
  /// otherwise the offset is relative to the upper edge of the topmost sliver.
  /// The index of the item refers to the actual item of the list view, therefore in case of animations in progress
  /// it may not correspond to the index of the underlying list. If you want to specify the index of the latter,
  /// first convert it by using the [AnimatedListController.listToActualItemIndex] method.
  /// For one, you might pass the result to the [ScrollController.jumpTo] or [ScrollController.animateTo] methods 
  /// of a [ScrollController] to scroll to the desired item.
  Rect? computeItemBox(int index, [bool absolute = false]) {
    assert(_debugAssertBinded());
    return _interface!.computeItemBox(index, absolute);
  }

  /// Converts the index of an item in the underlying list into the actual index displayed in the list view. 
  /// If the list view is not animating, the same index will be returned.
  /// If the item is not yet visible, as the list view is animating, `null` will be returned.
  int? listToActualItemIndex(int index) {
    assert(_debugAssertBinded());
    return _interface!.listToActualItemIndex(index);
  }

  /// Converts the actual index displayed in the list view into the underlying list index. 
  /// If the list view is not animating, the same index will be returned.
  /// If the actual item dosen't match a list item (such as a resizing interval when the list view is being animated), 
  /// `null` will be returned.
  int? actualToListItemIndex(int index) {
    assert(_debugAssertBinded());
    return _interface!.actualToListItemIndex(index);
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
    if (_interface == interface) {
      _interface = null;
    }
  }

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
}

abstract class _ControllerInterface {
  void notifyChangedRange(
      int from, int count, final AnimatedWidgetBuilder changeItemBuilder,
      int priority);

  void notifyInsertedRange(int from, int count, int priority);

  void notifyRemovedRange(
      int from, int count, final AnimatedWidgetBuilder removeItemBuilder,
      int priority);

  void notifyReplacedRange(int from, int removeCount, final int insertCount,
      final AnimatedWidgetBuilder removeItemBuilder,
      int priority);

  void batch(VoidCallback callback);

  void notifyStartReorder(BuildContext context, double dx, double dy) {}

  void notifyUpdateReorder(double dx, double dy) {}

  void notifyStopReorder(bool cancel) {}

  Rect? computeItemBox(int index, bool absolute);

  int? listToActualItemIndex(int index);

  int? actualToListItemIndex(int index);
}

class _SaltedValueKey extends ValueKey<Key> {
  const _SaltedValueKey(Key key) : super(key);
}
