part of 'core.dart';

/// Default duration of a dismiss or incoming animation.
const Duration kDismissOrIncomingAnimationDuration =
    Duration(milliseconds: 500);

/// Default duration of a resizing animation.
const Duration kResizeAnimationDuration = Duration(milliseconds: 500);

/// Default duration of a reordering animation.
const Duration kReorderAnimationDuration = Duration(milliseconds: 250);

/// Default duration of a moving animation.
const Duration kMovingAnimationDuration = Duration(milliseconds: 500);

/// Default curve of a dismiss or incoming animation.
const Curve kDismissOrIncomingAnimationCurve = Curves.ease;

/// Default curve of a resizing animation.
const Curve kResizeAnimationCurve = Curves.easeInOut;

/// Default curve of a reordering animation.
const Curve kReorderAnimationCurve = Curves.linear;

/// Default curve of a moving animation.
const Curve kMovingAnimationCurve = Curves.easeInOut;

/// Default value of the [Material.elevation].
const double kDefaultAnimatedElevation = 10.0;

/// Default duration of the [MorphTransition] effect.
const Duration kDefaultMorphTransitionDuration = Duration(milliseconds: 500);

/// A delegate that supplies children for animated slivers.
///
/// This class has been inspired by [SliverChildDelegate].
abstract class AnimatedSliverChildDelegate {
  const AnimatedSliverChildDelegate();

  /// Provides the initial child count of the underlying list.
  int get initialChildCount;

  /// Provides the builder of the items currently present in the undelying list.
  AnimatedWidgetBuilder get builder;

  /// Wrap a built child widget adding extra visual effects, animations and others.
  Widget wrapWidget(
      BuildContext context, Widget widget, AnimatedWidgetBuilderData data);

  /// Provides an animator to customize all the animations.
  AnimatedListAnimator get animator;

  /// Provides a model (a bunch of callbacks) to handle reordering.
  AnimatedListBaseReorderModel? get reorderModel;

  /// A function that is called at the very early stage to give you the option to return the initial scroll offset.
  InitialScrollOffsetCallback? get initialScrollOffsetCallback;

  /// Whether to prevent scrolling up when the above items not visibile are modified.
  bool get holdScrollOffset;

  /// See [SliverChildDelegate.didFinishLayout].
  /// The indices refer to the actual items built in the list view.
  void didFinishLayout(int firstIndex, int lastIndex) {}

  @override
  String toString() {
    final description = <String>[];
    return '${describeIdentity(this)}(${description.join(", ")})';
  }
}

/// Inspired by [SliverChildBuilderDelegate].
class AnimatedSliverChildBuilderDelegate extends AnimatedSliverChildDelegate {
  /// See [SliverChildBuilderDelegate.addAutomaticKeepAlives] for details.
  ///
  /// Defaults to `true`.
  final bool addAutomaticKeepAlives;

  /// See [SliverChildBuilderDelegate.addRepaintBoundaries] for details.
  ///
  /// Defaults to `true`.
  final bool addRepaintBoundaries;

  // final bool addSemanticIndexes;
  // final int semanticIndexOffset;
  // final SemanticIndexCallback semanticIndexCallback;

  /// Whether to wrap each child in a [LongPressReorderable], if a reorder model has been provided.
  ///
  /// This allows the items to be dragged for reordering purpose with a long press gesture.
  ///
  /// Defaults to `true`.
  final bool addLongPressReorderable;

  /// Whether to wrap each child in a [Material], if a reorder model has been provided.
  ///
  /// An elevation effect is automatically applied to the item picked up for reordering.
  /// If the value is `0.0` the child is not wrapped at all.
  /// See [Material.elevation] for details.
  ///
  /// Defaults to [kDefaultAnimatedElevation].
  final double addAnimatedElevation;

  /// Whether to wrap each child in a [FadeTransition].
  ///
  /// A fade effect is automatically applied to dismissing and incoming items.
  ///
  /// Defaults to `true`.
  final bool addFadeTransition;

  /// If provided, it wraps each child in a [MorphTransition].
  ///
  /// It adds a cross-fade effect to the items that change their content, fading out the old content
  /// and fading in the new one.
  /// This callback has to return `false` if the morph effect is to be applied, ie the new widget
  /// content is different from the old one. Avoid returning `false` when not needed, in order
  /// not to apply the effect unnecessarily when the two compared widgets are identical.
  ///
  /// Defaults to `null`.
  final MorphComparator? morphComparator;

  /// Whether to resize the widget that is changing when applying the [MorphTransition] effect.
  /// If `false`, the widget with the largst content will be cropped during the animation.
  /// See also [MorphTransition.resizeWidgets].
  ///
  /// Defaults to `true`.
  final bool morphResizeWidgets;

  /// The duration of the [MorphTransition] effect.
  ///
  /// Defaults to [kDefaultMorphTransitionDuration].
  final Duration morphDuration;

  /// Whether to prevent scrolling up when the above items not visibile are modified.
  /// See [AnimatedSliverChildDelegate.holdScrollOffset].
  ///
  /// Defaults to `false`.
  @override
  final bool holdScrollOffset;

  /// A function that is called at the very early stage to give you the option to return the initial scroll offset.
  /// If `null` not callback will be invoked.
  /// See [AnimatedSliverChildDelegate.initialScrollOffsetCallback].
  ///
  /// Defaults to `null`.
  @override
  final InitialScrollOffsetCallback? initialScrollOffsetCallback;

  /// Provides a model (a bunch of callbacks) that handles reordering.
  /// If `null` the list view cannot be reordered.
  /// See [AnimatedSliverChildDelegate.reorderModel].
  ///
  /// Defaults to `null`.
  @override
  final AnimatedListBaseReorderModel? reorderModel;

  /// Provides the builder of the items currently present in the underlying list.
  /// See [AnimatedSliverChildDelegate.builder].
  @override
  final AnimatedWidgetBuilder builder;

  /// Provides an animator to customize all the animations.
  /// See [AnimatedSliverChildDelegate.animator].
  ///
  /// Defaults to an instance of [DefaultAnimatedListAnimator].
  @override
  final AnimatedListAnimator animator;

  /// The initial count of the children present in the underlying list.
  /// This attribute is only read during the first build.
  /// See [AnimatedSliverChildDelegate.initialChildCount].
  @override
  final int initialChildCount;

  /// The callback [didFinishLayoutCallback] will be invoked, if any.
  ///
  /// See [AnimatedSliverChildDelegate.didFinishLayout] for more information.
  @override
  void didFinishLayout(int firstIndex, int lastIndex) =>
      didFinishLayoutCallback?.call(firstIndex, lastIndex);

  /// The callback to be invoked on [AnimatedSliverChildDelegate.didFinishLayout].
  ///
  /// Defaults to `null`.
  final void Function(int, int)? didFinishLayoutCallback;

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
    this.addAnimatedElevation = kDefaultAnimatedElevation,
    this.addFadeTransition = true,
    this.morphResizeWidgets = true,
    this.morphDuration = kDefaultMorphTransitionDuration,
    this.morphComparator,
    this.reorderModel,
    this.initialScrollOffsetCallback,
    this.didFinishLayoutCallback,
    this.holdScrollOffset = false,
  })  : assert(initialChildCount >= 0),
        initialChildCount = initialChildCount;

  /// See [AnimatedSliverChildDelegate.wrapWidget].
  @override
  Widget wrapWidget(
      BuildContext context, Widget child, AnimatedWidgetBuilderData data) {
    if (data.measuring) return child;
    final originalChild = child;
    final Key? key = child.key != null ? _SaltedValueKey(child.key!) : null;
    if (morphComparator != null) {
      child = MorphTransition(
          duration: morphDuration,
          resizeWidgets: morphResizeWidgets,
          comparator: morphComparator!,
          child: child);
    }
    if (addAnimatedElevation != 0.0 && reorderModel != null) {
      child = Material(
        elevation: data.dragging ? addAnimatedElevation : 0.0,
        child: child,
      );
    }
    if (addFadeTransition) {
      child = FadeTransition(opacity: data.animation, child: child);
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
    child = KeyedSubtree(key: key, child: child);
    if (kDebugMode) {
      child = _DebugWidget(child, () => originalChild.toStringShort());
    }
    return child;
  }
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
  /// is turning into an outgoing item.
  /// The current [time] of the incoming animation is provided (`0` indicates that is
  /// just started whereas `1` is pratically completed).
  AnimatedListAnimationData dismissDuringIncoming(double time);

  /// Provides info about the animation of a resizing interval (space between items)
  /// that appear after removing/replacing old items or before inserting new ones.
  /// The starting [fromSize] and ending [toSize] measures of the interval are also provided.
  AnimatedListAnimationData resizing(double fromSize, double toSize);

  /// Provides info about the animation of a resizing interval (space between items)
  /// that appear only during reordering.
  /// The starting [fromSize] and ending [toSize] sizes of the interval are also provided.
  AnimatedListAnimationData resizingDuringReordering(
      double fromSize, double toSize);

  /// Provides info about the animation of a moving item.
  AnimatedListAnimationData moving();
}

/// Default implementation of the inteface [AnimatedListAnimator] that uses [CurveTween]s objects.
/// Custom animation durations and curves can also be provided.
class DefaultAnimatedListAnimator extends AnimatedListAnimator {
  const DefaultAnimatedListAnimator({
    this.dismissIncomingDuration = kDismissOrIncomingAnimationDuration,
    this.resizeDuration = kResizeAnimationDuration,
    this.reorderDuration = kReorderAnimationDuration,
    this.movingDuration = kMovingAnimationDuration,
    this.dismissIncomingCurve = kDismissOrIncomingAnimationCurve,
    this.resizeCurve = kResizeAnimationCurve,
    this.reorderCurve = kReorderAnimationCurve,
    this.movingCurve = kMovingAnimationCurve,
  });

  final Duration dismissIncomingDuration,
      resizeDuration,
      reorderDuration,
      movingDuration;
  final Curve dismissIncomingCurve, resizeCurve, reorderCurve, movingCurve;

  /// See [AnimatedListAnimator.dismissDuringIncoming].
  @override
  AnimatedListAnimationData dismissDuringIncoming(double dismissTime) {
    return AnimatedListAnimationData(
        Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: dismissIncomingCurve.flipped)),
        dismissIncomingDuration,
        1.0 - dismissTime);
  }

  /// See [AnimatedListAnimator.dismiss].
  @override
  AnimatedListAnimationData dismiss() {
    return AnimatedListAnimationData(
        Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: dismissIncomingCurve)),
        dismissIncomingDuration);
  }

  /// See [AnimatedListAnimator.incoming].
  @override
  AnimatedListAnimationData incoming() {
    return AnimatedListAnimationData(
        CurveTween(curve: dismissIncomingCurve), dismissIncomingDuration);
  }

  /// See [AnimatedListAnimator.resizing].
  @override
  AnimatedListAnimationData resizing(double fromSize, double toSize) {
    return AnimatedListAnimationData(
        CurveTween(curve: resizeCurve), resizeDuration);
  }

  /// See [AnimatedListAnimator.resizingDuringReordering].
  @override
  AnimatedListAnimationData resizingDuringReordering(
      double fromSize, double toSize) {
    return AnimatedListAnimationData(
        CurveTween(curve: reorderCurve), reorderDuration);
  }

  /// See [AnimatedListAnimator.moving].
  @override
  AnimatedListAnimationData moving() {
    return AnimatedListAnimationData(
        CurveTween(curve: movingCurve), movingDuration);
  }
}

/// Holds information about an animation.
///
/// The [animation] attribute is used to convert the linear animation (from `0.0` to `1.0`) in a customized way,
/// like [Tween]s.
///
/// The [duration] attribute indicates the duration of the entire animation.
///
/// The [startTime] attribute, if is greater than zero, indicates that the animation won't start from the beginning
/// but at a specific point.
class AnimatedListAnimationData {
  const AnimatedListAnimationData(this.animation, this.duration,
      [this.startTime = 0.0])
      : assert(startTime >= 0.0 && startTime <= 1.0);

  final Animatable<double> animation;
  final Duration duration;
  final double startTime;
}

class _SaltedValueKey extends ValueKey<Key> {
  const _SaltedValueKey(Key key) : super(key);
}
