part of 'core.dart';

/// A scrollable and animated list of widgets arranged linearly, inspired by [ListView].
class AnimatedListView extends BoxScrollView {
  /// Constructs an animated list view.
  ///
  /// Most of the attributes are identical to those of the [ListView].
  /// The specific ones are the following:
  /// - `listController`, an [AnimatedListController] mainly used to be notified about any changes to the underlying list;
  /// - `itemBuilder`, an [AnimatedWidgetBuilder] used to build the widgets of the underlying list items;
  /// - `iniitalItemCount`, the initial count of the underlying list items;
  /// - `animator`, an [AnimatedListAnimator] used to customize all the animations;
  /// - `addLongPressReorderable`, used to wrap each item in a [LongPressReorderable] (see also
  ///   [AnimatedSliverChildBuilderDelegate.addLongPressReorderable]);
  /// - `addAnimatedElevation`, used to wrap each item in a [AnimatedElevation] (see also
  ///   [AnimatedSliverChildBuilderDelegate.addAnimatedElevation]);
  /// - `addFadeTransition`, used to wrap each item in a [FadeTransition] (see also
  ///   [AnimatedSliverChildBuilderDelegate.addFadeTransition]);
  /// - `morphComparator`, used to wrap each item in a [MorphTransition] (see also [MorphTransition.comparator]);
  /// - `resizeChangingitems`, tells wheter or not resize widgets when they are crossfading (see also
  ///   [MorphTransition.resizeWidgets]);
  /// - `reorderModel`, used to provide a model (a bunch of callbacks) which controls the behavior of reorders.
  AnimatedListView({
    Key? key,
    required this.listController,
    required AnimatedWidgetBuilder itemBuilder,
    required int initialItemCount,
    this.itemExtent,
    AnimatedListAnimator animator = const DefaultAnimatedListAnimator(),
    bool addLongPressReorderable = true,
    bool addAnimatedElevation = true,
    bool addFadeTransition = true,
    MorphComparator? morphComparator,
    bool morphResizeWidgets = true,
    Duration morphDuration = const Duration(milliseconds: 500),
    AnimatedListBaseReorderModel? reorderModel,
    //
    Axis scrollDirection = Axis.vertical,
    bool reverse = false,
    ScrollController? scrollController,
    bool? primary,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    EdgeInsetsGeometry? padding,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    // bool addSemanticIndexes = true,
    double? cacheExtent,
    // int? semanticChildCount,
    DragStartBehavior dragStartBehavior = DragStartBehavior.start,
    ScrollViewKeyboardDismissBehavior keyboardDismissBehavior =
        ScrollViewKeyboardDismissBehavior.manual,
    String? restorationId,
    Clip clipBehavior = Clip.hardEdge,
  })  : assert(initialItemCount >= 0),
        // assert(semanticChildCount == null || semanticChildCount <= itemCount),
        delegate = AnimatedSliverChildBuilderDelegate(
          itemBuilder,
          initialItemCount,
          addAutomaticKeepAlives: addAutomaticKeepAlives,
          addRepaintBoundaries: addRepaintBoundaries,
          //  addSemanticIndexes: addSemanticIndexes,
          animator: animator,
          addLongPressReorderable: addLongPressReorderable,
          addAnimatedElevation: addAnimatedElevation,
          addFadeTransition: addFadeTransition,
          morphResizeWidgets: morphResizeWidgets,
          morphDuration: morphDuration,
          morphComparator: morphComparator,
          reorderModel: reorderModel,
        ),
        super(
          key: key,
          scrollDirection: scrollDirection,
          reverse: reverse,
          controller: scrollController ?? ScrollController(),
          primary: primary,
          physics: physics,
          shrinkWrap: shrinkWrap,
          padding: padding,
          cacheExtent: cacheExtent,
          // semanticChildCount: semanticChildCount ?? initialItemCount,
          dragStartBehavior: dragStartBehavior,
          keyboardDismissBehavior: keyboardDismissBehavior,
          restorationId: restorationId,
          clipBehavior: clipBehavior,
        );

  /// Constructs an animated list view with a custom delegate.
  ///
  /// Most of the attributes are identical to those of the [ListView].
  /// The specific ones are the following:
  /// - `listController`, an [AnimatedListController] mainly used to be notified about any changes to the underlying list;
  /// - `delegate`, your custom [AnimatedSliverChildDelegate] delegate.
  const AnimatedListView.custom({
    Key? key,
    required this.listController,
    required this.delegate,
    //
    Axis scrollDirection = Axis.vertical,
    bool reverse = false,
    ScrollController? controller,
    bool? primary,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    EdgeInsetsGeometry? padding,
    this.itemExtent,
    double? cacheExtent,
    int? semanticChildCount,
    DragStartBehavior dragStartBehavior = DragStartBehavior.start,
    ScrollViewKeyboardDismissBehavior keyboardDismissBehavior =
        ScrollViewKeyboardDismissBehavior.manual,
    String? restorationId,
    Clip clipBehavior = Clip.hardEdge,
  }) : super(
          key: key,
          scrollDirection: scrollDirection,
          reverse: reverse,
          controller: controller,
          primary: primary,
          physics: physics,
          shrinkWrap: shrinkWrap,
          padding: padding,
          cacheExtent: cacheExtent,
          semanticChildCount: semanticChildCount,
          dragStartBehavior: dragStartBehavior,
          keyboardDismissBehavior: keyboardDismissBehavior,
          restorationId: restorationId,
          clipBehavior: clipBehavior,
        );

  final AnimatedListController listController;

  final double? itemExtent;

  final AnimatedSliverChildDelegate delegate;

  @override
  Widget buildChildLayout(BuildContext context) {
    if (itemExtent != null) {
      return AnimatedSliverFixedExtentList(
          delegate: delegate,
          itemExtent: itemExtent!,
          controller: listController);
    }
    return AnimatedSliverList(delegate: delegate, controller: listController);
  }
}

/// A base class for animated sliver that have multiple box children, inspired by [SliverMultiBoxAdaptorWidget].
abstract class AnimatedSliverMultiBoxAdaptorWidget
    extends SliverWithKeepAliveWidget {
  const AnimatedSliverMultiBoxAdaptorWidget(
      {Key? key, required this.listController, required this.delegate})
      : super(key: key);

  final AnimatedListController listController;

  final AnimatedSliverChildDelegate delegate;

  static _ControllerListeners? of(BuildContext context) {
    try {
      return context
          .findAncestorRenderObjectOfType<AnimatedRenderSliverList>()
          ?.childManager;
    } catch (e) {
      return null;
    }
  }
}

/// An animated sliver that places multiple box children in a linear array along the main
/// axis, inspired by [SliverList].
class AnimatedSliverList extends AnimatedSliverMultiBoxAdaptorWidget {
  const AnimatedSliverList({
    Key? key,
    required AnimatedSliverChildDelegate delegate,
    required AnimatedListController controller,
  }) : super(key: key, listController: controller, delegate: delegate);

  @override
  AnimatedSliverMultiBoxAdaptorElement createElement() =>
      AnimatedSliverMultiBoxAdaptorElement(this);

  @override
  AnimatedRenderSliverList createRenderObject(BuildContext context) {
    return AnimatedRenderSliverList(
        this, context as AnimatedSliverMultiBoxAdaptorElement);
  }
}

/// An animated sliver that places multiple box children with the same main axis extent in
/// a linear array, inspired by [SliverFixedExtentList].
class AnimatedSliverFixedExtentList
    extends AnimatedSliverMultiBoxAdaptorWidget {
  const AnimatedSliverFixedExtentList({
    Key? key,
    required AnimatedSliverChildDelegate delegate,
    required AnimatedListController controller,
    required this.itemExtent,
  }) : super(key: key, listController: controller, delegate: delegate);

  final double itemExtent;

  @override
  AnimatedSliverMultiBoxAdaptorElement createElement() =>
      AnimatedSliverMultiBoxAdaptorElement(this);

  @override
  AnimatedRenderSliverFixedExtentList createRenderObject(BuildContext context) {
    return AnimatedRenderSliverFixedExtentList(
        widget: this,
        childManager: context as AnimatedSliverMultiBoxAdaptorElement,
        itemExtent: itemExtent);
  }
}

/// Extends [AnimatedListView] by offering intrisic use of the [AnimatedListDiffListDispatcher]
/// to automatically animate the list view when this widget is rebuilt with a different [list].
/// All attributes, except for [list], are identical to those of the [AnimatedListView].
class AutomaticAnimatedListView<T> extends AnimatedListView {
  AutomaticAnimatedListView({
    Key? key,
    required this.list,
    required AnimatedListController listController,
    required this.itemBuilder,
    required this.comparator,
    AnimatedListAnimator animator = const DefaultAnimatedListAnimator(),
    bool addLongPressReorderable = true,
    bool addAnimatedElevation = true,
    bool addFadeTransition = true,
    bool morphResizeWidgets = true,
    Duration morphDuration = const Duration(milliseconds: 500),
    MorphComparator? morphComparator,
    AnimatedListBaseReorderModel? reorderModel,
    //
    Axis scrollDirection = Axis.vertical,
    bool reverse = false,
    ScrollController? scrollController,
    bool? primary,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    EdgeInsetsGeometry? padding,
    double? itemExtent,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    // bool addSemanticIndexes = true,
    double? cacheExtent,
    int? semanticChildCount,
    DragStartBehavior dragStartBehavior = DragStartBehavior.start,
    ScrollViewKeyboardDismissBehavior keyboardDismissBehavior =
        ScrollViewKeyboardDismissBehavior.manual,
    String? restorationId,
    Clip clipBehavior = Clip.hardEdge,
  }) : super.custom(
          key: key,
          scrollDirection: scrollDirection,
          reverse: reverse,
          controller: scrollController ?? ScrollController(),
          primary: primary,
          physics: physics,
          shrinkWrap: shrinkWrap,
          padding: padding,
          cacheExtent: cacheExtent,
          // semanticChildCount: semanticChildCount ?? itemCount,
          dragStartBehavior: dragStartBehavior,
          keyboardDismissBehavior: keyboardDismissBehavior,
          restorationId: restorationId,
          clipBehavior: clipBehavior,
          itemExtent: itemExtent,
          listController: listController,
          delegate: AnimatedSliverChildBuilderDelegate(
            (context, index, data) {
              return itemBuilder(context, list[index], data);
            },
            list.length,
            addAutomaticKeepAlives: addAutomaticKeepAlives,
            addRepaintBoundaries: addRepaintBoundaries,
            //  addSemanticIndexes: addSemanticIndexes,
            animator: animator,
            addLongPressReorderable: addLongPressReorderable,
            addAnimatedElevation: addAnimatedElevation,
            addFadeTransition: addFadeTransition,
            morphResizeWidgets: morphResizeWidgets,
            morphDuration: morphDuration,
            morphComparator: morphComparator,
            reorderModel: reorderModel,
          ),
        );

  final AnimatedListDiffListBuilder<T> itemBuilder;

  final AnimatedListDiffListBaseComparator<T> comparator;

  final List<T> list;

  @override
  Widget buildChildLayout(BuildContext context) {
    final widget = super.buildChildLayout(context);
    return _DiffDispatcherWidget(
        comparator: comparator,
        controller: listController,
        itemBuilder: itemBuilder,
        list: list,
        child: widget);
  }
}

class _DiffDispatcherWidget<T> extends StatefulWidget {
  final AnimatedListController controller;
  final AnimatedListDiffListBuilder<T> itemBuilder;
  final AnimatedListDiffListBaseComparator<T> comparator;
  final List<T> list;
  final Widget child;

  const _DiffDispatcherWidget(
      {Key? key,
      required this.controller,
      required this.comparator,
      required this.list,
      required this.itemBuilder,
      required this.child})
      : super(key: key);

  @override
  _DiffDispatcherWidgetState<T> createState() =>
      _DiffDispatcherWidgetState<T>();
}

class _DiffDispatcherWidgetState<T> extends State<_DiffDispatcherWidget<T>> {
  AnimatedListDiffListDispatcher<T>? _dispatcher;

  void _createDispatcher() {
    final oldProcessingList = _dispatcher?._processingList;
    _dispatcher?._processingList = null;
    _dispatcher = AnimatedListDiffListDispatcher<T>(
      controller: widget.controller,
      currentList: _dispatcher?.currentList ?? widget.list,
      itemBuilder: widget.itemBuilder,
      comparator: widget.comparator,
    );
    if (oldProcessingList != null) {
      _dispatcher!.dispatchNewList(oldProcessingList);
    }
  }

  @override
  void initState() {
    super.initState();
    _createDispatcher();
  }

  @override
  void didUpdateWidget(_DiffDispatcherWidget<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.itemBuilder != widget.itemBuilder ||
        oldWidget.comparator != widget.comparator) {
      _createDispatcher();
    }
    if (oldWidget.list != widget.list) {
      _dispatcher!.dispatchNewList(widget.list);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class AutomaticAnimatedListReorderModel<T>
    extends AnimatedListBaseReorderModel {
  final List<T> list;

  const AutomaticAnimatedListReorderModel(this.list);

  @override
  bool onReorderStart(int index, double dx, double dy) => true;

  @override
  Object? onReorderFeedback(
          int index, int dropIndex, double offset, double dx, double dy) =>
      null;

  @override
  bool onReorderMove(int index, int dropIndex) => true;

  @override
  bool onReorderComplete(int index, int dropIndex, Object? slot) {
    list.insert(dropIndex, list.removeAt(index));
    return true;
  }
}

/// This widget is meant to be wrapped around list items to add automatic reordering
/// functionality using the long press gesture.
/// In general it is not necessary to create this widget directly because it is already done
/// by the most used classes, such [AnimatedListView], [AutomaticAnimatedListView],
/// [AnimatedSliverChildBuilderDelegate] and so on.
class LongPressReorderable extends StatelessWidget {
  const LongPressReorderable({Key? key, required this.child}) : super(key: key);

  final Widget child;

  AnimatedRenderSliverMultiBoxAdaptor? _findRenderSliver(BuildContext context) {
    return (AnimatedSliverMultiBoxAdaptorWidget.of(context)
            as AnimatedSliverMultiBoxAdaptorElement?)
        ?.renderObject;
  }

  void _onLongPressStart(BuildContext context, LongPressStartDetails d) {
    final renderObject = _findRenderSliver(context);
    renderObject?._reorderStart(
        context, d.localPosition.dx, d.localPosition.dy);
  }

  void _onLongPressMoveUpdate(
      BuildContext context, LongPressMoveUpdateDetails d) {
    final renderObject = _findRenderSliver(context);
    renderObject?._reorderUpdate(d.localPosition.dx, d.localPosition.dy);
  }

  void _onLongPressEnd(BuildContext context, LongPressEndDetails d) {
    final renderObject = _findRenderSliver(context);
    renderObject?._reorderStop(false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onLongPressStart: (d) => _onLongPressStart(context, d),
        onLongPressEnd: (d) => _onLongPressEnd(context, d),
        onLongPressMoveUpdate: (d) => _onLongPressMoveUpdate(context, d),
        child: child);
  }
}
