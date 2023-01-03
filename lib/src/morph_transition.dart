import 'dart:collection';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../ticker_mixin.dart';

typedef MorphComparator = bool Function(Widget a, Widget b);

/// This widget every time it is rebuilt creates a crossfade effect by making the old [child] widget
/// disappear and the new one appear.
///
/// If the instance of the [child] widget doesn't change, the crossfade effect doesn't occur.
/// If the new [child] widget has a different instance, the [comparator] is used to determine if
/// the new widget is really different from the old one. Only if it returns `false` the crossfade
/// effect occur.
///
/// When the crossfade occurs, the [resizeWidgets] attribute is queried. If it is `true`, both children
/// (the old and the new) are resized during the animation, forcing them to have the same size in each frame,
/// changing from the size of the old child to the size of the new child.
/// If it is `false`, both children keep their size during animation, inevitably causing cropping of the
/// biggest child (but only if their dimensions are obviously different).
class MorphTransition extends RenderObjectWidget {
  const MorphTransition({
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
  MorphRenderObjectElement createElement() => MorphRenderObjectElement(this);

  @override
  MorphRenderStack createRenderObject(BuildContext context) {
    return MorphRenderStack(
      context as MorphRenderObjectElement,
      textDirection: textDirection ?? Directionality.of(context),
      clipBehavior: clipBehavior,
      resizeChildrenWhenAnimating: resizeWidgets,
    );
  }

  @override
  void updateRenderObject(BuildContext context, MorphRenderStack renderObject) {
    renderObject
      ..textDirection = textDirection ?? Directionality.of(context)
      ..clipBehavior = clipBehavior
      .._resizeChildrenWhenAnimating = resizeWidgets;
  }
}

class MorphRenderStack extends RenderStack {
  final MorphRenderObjectElement _element;
  final _animations = HashMap<RenderBox, AnimationController>();
  var _paintRenderObjects = HashMap<RenderBox?, int>();
  bool _resizeChildrenWhenAnimating;
  ClipRectLayer? _clipRectLayer;
  final _opacityLayer = <LayerHandle<OpacityLayer>>[];

  MorphRenderStack(
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
      t.whenComplete(() {
        if (controller.status == AnimationStatus.forward ||
            controller.status == AnimationStatus.completed) return;
        remove(child);
      });
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

    var hasFullVisibleOne = false;

    for (var child = firstChild; child != null; child = childAfter(child)) {
      final a = _getAnimationOf(child);
      final alpha = Color.getAlphaFromOpacity(a.value);
      if (a.isDismissed || alpha == 0) continue;
      if (a.isCompleted || alpha == 255) {
        hasFullVisibleOne = true;
      }
      newPaint[child] = alpha;
    }

    if (!_comparePaints(_paintRenderObjects, newPaint)) {
      _paintRenderObjects = newPaint;

      final didNeedCompositing = _currentlyNeedsCompositing;
      _currentlyNeedsCompositing =
          !hasFullVisibleOne && _paintRenderObjects.isNotEmpty;

      if (didNeedCompositing != _currentlyNeedsCompositing) {
        markNeedsCompositingBitsUpdate();
      }

      markNeedsLayout();
      markNeedsPaint();
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

    if (list.isEmpty) {
      assert(!needsCompositing);
      layer = null;
      _disposeLayers(0);
      return;
    }

    final fullVisibleChild = list.firstWhereOrNull((e) => e.value == 255);
    if (fullVisibleChild != null) {
      assert(!needsCompositing);
      layer = null;
      _disposeLayers(0);
      context.paintChild(fullVisibleChild.key!, offset);
      return;
    }

    assert(needsCompositing);

    void paintSingleChild(
        RenderBox child, PaintingContext context, Offset offset) {
      final childParentData = child.parentData as StackParentData;
      context.paintChild(child, childParentData.offset + offset);
    }

    void paintChildren(PaintingContext context, Offset offset) {
      var i = 0;
      var first = true;
      for (final e in list) {
        OpacityLayer? oldLayer;
        LayerHandle<OpacityLayer>? handle;
        if (first) {
          oldLayer = layer as OpacityLayer?;
          handle = null;
        } else {
          if (_opacityLayer.length > i) {
            handle = _opacityLayer[i];
            oldLayer = handle.layer;
          } else {
            _opacityLayer.add(handle = LayerHandle());
            oldLayer = null;
          }
          i++;
        }
        final newLayer = context.pushOpacity(offset, e.value,
            (context, offset) => paintSingleChild(e.key!, context, offset),
            oldLayer: oldLayer);
        if (handle == null) {
          layer = newLayer;
        } else {
          handle.layer = newLayer;
        }
        first = false;
      }
      _disposeLayers(i);
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

    var maxV = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final av = _getAnimationOf(child).value;
      maxV = math.max(maxV, av);
    }

    var width = 0.0, height = 0.0;
    var tot = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final v = maxV == 0 ? 1.0 : _getAnimationOf(child).value / maxV;
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

  void _disposeLayers(int from) {
    for (var i = from; i < _opacityLayer.length; i++) {
      assert(_opacityLayer[i].layer != null);
      _opacityLayer[i].layer = null;
    }
    _opacityLayer.removeRange(from, _opacityLayer.length);
  }

  @override
  void dispose() {
    _animations.values.forEach((e) => e.dispose());
    _animations.clear();
    _paintRenderObjects.clear();
    _disposeLayers(0);
    super.dispose();
  }
}

class MorphRenderObjectElement extends RenderObjectElement
    with TickerProviderMixin {
  final _list = LinkedList<_Entry>();
  Element? _topElement;
  final _removeList = <_Entry>[];

  MorphRenderObjectElement(MorphTransition widget) : super(widget);

  @override
  MorphTransition get widget => super.widget as MorphTransition;

  @override
  MorphRenderStack get renderObject => super.renderObject as MorphRenderStack;

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
      _list.add(_Entry(
          topElement = updateChild(null, widget.child, _list.lastOrNull)!));
    } else {
      topElement = reusedElement;
    }

    if (_topElement != topElement) {
      _topElement = topElement;
      renderObject._coordinateAnimations();
    }
  }

  void _markToRemove(RenderBox child) {
    var e = _list.singleWhere((e) => e.element.renderObject == child);
    if (_removeList.contains(e)) return;
    _removeList.add(e);
    markNeedsBuild();
  }

  @override
  void performRebuild() {
    super.performRebuild();
    if (_removeList.isNotEmpty) {
      _removeList.removeWhere((e) {
        if (_list.length > 1) {
          _list.remove(e);
          updateChild(e.element, null, null);
          return true;
        }
        return false;
      });
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
    super.unmount();
    dispose();
  }
}

class _Entry extends LinkedListEntry<_Entry> {
  final Element element;
  _Entry(this.element);
}
