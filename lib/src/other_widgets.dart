import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:collection/collection.dart';

import 'ticker_mixin.dart';

typedef MorphComparator = bool Function(Widget a, Widget b);

/// Wraps the [child] widget in a [Material] widget in order to provide an implicit
/// animation of the [Material.elevation] attribute.
class AnimatedElevation extends ImplicitlyAnimatedWidget {
  const AnimatedElevation(
      {Key? key,
      this.child,
      this.elevation = 0.0,
      Curve curve = Curves.linear,
      required Duration duration,
      VoidCallback? onEnd})
      : super(key: key, curve: curve, duration: duration, onEnd: onEnd);

  final double elevation;
  final Widget? child;

  @override
  _AnimatedElevationWidgetState createState() =>
      _AnimatedElevationWidgetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('elevation', elevation));
  }
}

class _AnimatedElevationWidgetState
    extends AnimatedWidgetBaseState<AnimatedElevation> {
  Tween<double>? _elevation;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _elevation = visitor(_elevation, widget.elevation,
            (dynamic value) => Tween<double>(begin: value as double))
        as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final animation = this.animation;
    return Material(
      elevation: _elevation!.evaluate(animation),
      child: widget.child,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(DiagnosticsProperty<Tween<double>>('elevation', _elevation,
        showName: false, defaultValue: 0.0));
  }
}

/// This widget every time it is rebuilt creates a crossfade effect by making the old [child] widget
/// disappear and making the new one appear.
/// 
/// If the instance of the [child] widget doesn't change, the crossfade effect doesn't occur.
/// If the new [child] widget has a different instance, the [comparator] is used to determine if
/// the new widget is really different from the old one. Only if it returns `true` the crossfade 
/// effect doesn't occur.
/// 
/// When the crossfade occurs, the [resizeWidgets] attribute is queried. If it is `true`, both children
/// (the old and the new) are resized during the animation, forcing them to have the same size in each frame, 
/// changing from the size of the old child to the size of the new child.
/// If it is `false`, both children keep their size during animation, inevitably causing cropping of the
/// biggest child (but only if their dimensions are obviously different).
class MorphTransition extends RenderObjectWidget {
  MorphTransition({
    Key? key,
    required this.child,
    required this.comparator,
    this.resizeWidgets = false,
    required this.duration,
    this.textDirection,
    this.clipBehavior = Clip.hardEdge,
  }) : super(key: key);

  final Widget child;
  final MorphComparator comparator;
  final bool resizeWidgets;
  final Duration duration;
  final TextDirection? textDirection;
  final Clip clipBehavior;

  @override
  _MorphRenderObjectElement createElement() => _MorphRenderObjectElement(this);

  @override
  _MorphRenderStack createRenderObject(BuildContext context) {
    return _MorphRenderStack(
      context as _MorphRenderObjectElement,
      textDirection: textDirection ?? Directionality.of(context),
      clipBehavior: clipBehavior,
      resizeChildrenWhenAnimating: resizeWidgets,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _MorphRenderStack renderObject) {
    renderObject
      ..textDirection = textDirection ?? Directionality.of(context)
      ..clipBehavior = clipBehavior
      .._resizeChildrenWhenAnimating = resizeWidgets;
  }
}

class _MorphRenderStack extends RenderStack {
  final _MorphRenderObjectElement _element;
  final _animations = HashMap<RenderBox, AnimationController>();
  var _paintRenderObjects = HashMap<RenderBox?, int>();
  bool _resizeChildrenWhenAnimating;
  ClipRectLayer? _clipRectLayer;
  var _opacityLayer = <OpacityLayer>[];

  _MorphRenderStack(
    this._element, {
    bool resizeChildrenWhenAnimating = false,
    TextDirection? textDirection,
    Clip clipBehavior = Clip.hardEdge,
  })  : _resizeChildrenWhenAnimating = resizeChildrenWhenAnimating,
        super(clipBehavior: clipBehavior, textDirection: textDirection);

  AnimationController _getAnimationOf(RenderBox child) =>
      _animations.putIfAbsent(child, () => _createAnimation());

  void _coordinateAnimations() {
    var topRenderBox = _element._topElement!.renderObject;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final a = _getAnimationOf(child);
      if (child == topRenderBox) {
        _forwardAnimation(child, a);
      } else {
        _backwardAnimation(child, a);
      }
    }
  }

  void _forwardAnimation(RenderBox child, AnimationController controller) {
    if (controller.status == AnimationStatus.forward ||
        controller.status == AnimationStatus.completed) return;
    controller.forward();
  }

  void _backwardAnimation(RenderBox child, AnimationController controller) {
    if (controller.status == AnimationStatus.reverse ||
        controller.status == AnimationStatus.dismissed) return;
    final t = controller.reverse();
    void remove(RenderBox child) {
      _animations.remove(child);
      _element._markToRemove(child);
    }

    if (controller.status == AnimationStatus.dismissed) {
      remove(child);
    } else {
      t.whenComplete(() => remove(child));
    }
  }

  @override
  bool get alwaysNeedsCompositing => _currentlyNeedsCompositing;
  bool _currentlyNeedsCompositing = false;

  void _init() {
    var initialChild = firstChild!;
    _paintRenderObjects[initialChild] = 255;
    _animations[initialChild] = _createAnimation(true);
  }

  AnimationController _createAnimation([bool completed = false]) {
    return AnimationController(
      vsync: _element,
      duration: _element.widget.duration,
      value: completed ? 1.0 : 0.0,
    )..addListener(_updateAnimation);
  }

  void _updateAnimation() {
    final newPaint = HashMap<RenderBox?, int>();

    var onlyOne = false;

    for (var child = firstChild; child != null; child = childAfter(child)) {
      var a = _getAnimationOf(child);
      if (a.isDismissed || a.value == 0.0) continue;
      if (a.isCompleted || a.value == 1.0) {
        onlyOne = true;
      }
      newPaint[child] = Color.getAlphaFromOpacity(a.value);
    }

    if (_comparePaints(_paintRenderObjects, newPaint)) return;

    _paintRenderObjects = newPaint;

    markNeedsLayout();
    markNeedsPaint();

    final didNeedCompositing = _currentlyNeedsCompositing;
    _currentlyNeedsCompositing = !onlyOne;

    if (didNeedCompositing != _currentlyNeedsCompositing) {
      markNeedsCompositingBitsUpdate();
    }
  }

  bool _comparePaints(HashMap<RenderBox?, int> a, HashMap<RenderBox?, int> b) {
    if (a.length != b.length) return false;
    for (final ea in a.entries) {
      if (!b.containsKey(ea.key) || b[ea.key] != ea.value) return false;
    }
    return true;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    RenderBox? mostVisibleChild;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (mostVisibleChild == null ||
          _getAnimationOf(mostVisibleChild).value >
              _getAnimationOf(child).value) {
        mostVisibleChild = child;
      }
    }
    if (mostVisibleChild != null) visitor(mostVisibleChild);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final list = _paintRenderObjects.entries.toList();

    if (list.any((e) => e.value == 255)) {
      layer = null;
      _opacityLayer.clear();
      context.paintChild(list.where((e) => e.value == 255).first.key!, offset);
      return;
    }

    assert(needsCompositing);

    void paintSingleChild(
        RenderBox child, PaintingContext context, Offset offset) {
      final childParentData = child.parentData as StackParentData;
      context.paintChild(child, childParentData.offset + offset);
    }

    void paintChildren(PaintingContext context, Offset offset) {
      var oldLayers = <OpacityLayer>[
        if (layer != null) layer as OpacityLayer,
        ..._opacityLayer
      ];
      var newLayers = <OpacityLayer>[];
      var i = 0;
      for (final e in list) {
        newLayers.add(context.pushOpacity(offset, e.value,
            (context, offset) => paintSingleChild(e.key!, context, offset),
            oldLayer: oldLayers.length > i ? oldLayers[i] : null));
        i++;
      }
      layer = newLayers[0];
      newLayers.removeAt(0);
      _opacityLayer = newLayers;
    }

    if (_resizeChildrenWhenAnimating ||
        clipBehavior == Clip.none ||
        _hasSameSizes) {
      paintChildren(context, offset);
    } else {
      _clipRectLayer = context.pushClipRect(
          needsCompositing, offset, Offset.zero & size, paintChildren,
          clipBehavior: clipBehavior, oldLayer: _clipRectLayer);
    }
  }

  bool get _hasSameSizes {
    var child = firstChild;
    RenderBox? prevChild;
    while (child != null) {
      if (prevChild != null) {
        if (prevChild.size.width != child.size.width ||
            prevChild.size.height != child.size.height) {
          return false;
        }
      }
      prevChild = child;
      child = childAfter(child);
    }
    return true;
  }

  @override
  void performLayout() {
    super.performLayout();

    var width = 0.0, height = 0.0;
    var tot = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final v = _getAnimationOf(child).value;
      width += child.size.width * v;
      height += child.size.height * v;
      tot += v;
    }
    width /= tot;
    height /= tot;

    width = constraints.constrainWidth(width);
    height = constraints.constrainHeight(height);

    if (_resizeChildrenWhenAnimating) {
      BoxConstraints sizedConstraints;
      sizedConstraints = BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: height,
        maxHeight: height,
      );
      for (var child = firstChild; child != null; child = childAfter(child)) {
        child.layout(sizedConstraints, parentUsesSize: true);
      }
    } else {
      for (var child = firstChild; child != null; child = childAfter(child)) {
        child.layout(constraints, parentUsesSize: true);
      }
    }

    size = Size(width, height);
  }

  void dispose() {
    _animations.values.forEach((e) {
      e.dispose();
    });
    _animations.clear();
    _paintRenderObjects.clear();
    _opacityLayer.clear();
  }
}

class _MorphRenderObjectElement extends RenderObjectElement
    with TickerProviderMixin {
  final _list = LinkedList<_Entry>();
  Element? _topElement;
  final _removeList = <_Entry>[];

  _MorphRenderObjectElement(MorphTransition widget) : super(widget);

  @override
  MorphTransition get widget => super.widget as MorphTransition;

  @override
  _MorphRenderStack get renderObject => super.renderObject as _MorphRenderStack;

  @override
  void insertRenderObjectChild(RenderBox child, _Entry? slot) {
    final renderObject = this.renderObject;
    assert(renderObject.debugValidateChild(child));
    renderObject.insert(child, after: slot?.element.renderObject as RenderBox?);
    assert(renderObject == this.renderObject);
  }

  @override
  void moveRenderObjectChild(
      RenderBox child, _Entry? oldSlot, _Entry? newSlot) {
    final renderObject = this.renderObject;
    assert(child.parent == renderObject);
    renderObject.move(child,
        after: newSlot?.element.renderObject as RenderBox?);
    assert(renderObject == this.renderObject);
  }

  @override
  void removeRenderObjectChild(RenderBox child, _Entry? slot) {
    final renderObject = this.renderObject;
    assert(child.parent == renderObject);
    renderObject.remove(child);
    assert(renderObject == this.renderObject);
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    for (final child in _list) {
      visitor(child.element);
    }
  }

  @override
  Element inflateWidget(Widget newWidget, Object? newSlot) {
    final newChild = super.inflateWidget(newWidget, newSlot);
    return newChild;
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _list.add(_Entry(_topElement = inflateWidget(widget.child, null)));
    renderObject._init();
  }

  @override
  void update(MorphTransition newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);

    Element? reusedElement;
    for (final child in _list) {
      if (_removeList.contains(child)) continue;
      if (child.element.widget == newWidget.child ||
          widget.comparator.call(child.element.widget, newWidget.child)) {
        reusedElement = child.element;
        updateChild(child.element, newWidget.child, child.previous);
        break;
      }
    }

    late Element topElement;
    if (reusedElement == null) {
      _list.add(
          _Entry(topElement = inflateWidget(widget.child, _list.lastOrNull)));
    } else {
      topElement = reusedElement;
    }

    if (_topElement != topElement) {
      _topElement = topElement;
      renderObject._coordinateAnimations();
    }
  }

  void _markToRemove(RenderBox child) {
    var e = _list.where((e) => e.element.renderObject == child).first;
    if (_removeList.contains(e)) return;
    _removeList.add(e);
    markNeedsBuild();
  }

  @override
  void performRebuild() {
    super.performRebuild();
    if (_removeList.isNotEmpty) {
      _removeList.forEach((e) {
        _list.remove(e);
        updateChild(e.element, null, null);
      });
      _removeList.clear();
      renderObject._coordinateAnimations();
    }
  }

  @override
  void didChangeDependencies() {
    updateTickerMuted(this);
    super.didChangeDependencies();
  }

  @override
  void unmount() {
    renderObject.dispose();
    dispose();
    super.unmount();
  }
}

class _Entry extends LinkedListEntry<_Entry> {
  final Element element;
  _Entry(this.element);
}

/// Animated arrow button.
class ArrowButton extends StatefulWidget {
  final bool expanded;
  final void Function(bool expanded)? onTap;
  final Duration duration;
  final Curve curve;
  final Icon icon;
  final double turns;

  ArrowButton({
    Key? key,
    this.expanded = false,
    this.onTap,
    this.curve = Curves.fastOutSlowIn,
    this.duration = const Duration(milliseconds: 300),
    this.icon = const Icon(Icons.keyboard_arrow_down),
    this.turns = 0.5,
  }) : super(key: key);

  @override
  _ArrowButtonState createState() => _ArrowButtonState();
}

class _ArrowButtonState extends State<ArrowButton>
    with SingleTickerProviderStateMixin {
  late Animation<double> _animation;
  AnimationController? _controller;
  bool _expanded = false;

  @override
  void didUpdateWidget(ArrowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.curve != oldWidget.curve ||
        widget.duration != oldWidget.duration ||
        widget.icon != oldWidget.icon ||
        widget.turns != oldWidget.turns) {
      _controller?.dispose();
      _initAnimation();
    }
    if (widget.expanded != _expanded) {
      _expanded = widget.expanded;
      _animate();
    }
  }

  void _animate() {
    if (_expanded) {
      _controller!.forward();
    } else {
      _controller!.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.expanded;
    _initAnimation();
  }

  void _initAnimation() {
    _controller = AnimationController(vsync: this, duration: widget.duration);
    Animation<double> curve =
        CurvedAnimation(parent: _controller!, curve: widget.curve);
    _animation = Tween(begin: 0.0, end: widget.turns).animate(curve);
    if (_expanded) _controller!.value = 1.0;
  }

  @override
  void dispose() {
    _controller!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        setState(() {
          _expanded = !_expanded;
          _animate();
          if (widget.onTap != null) widget.onTap!(_expanded);
        });
      },
      icon: RotationTransition(
        turns: _animation,
        child: widget.icon,
      ),
    );
  }
}
