part of 'great_list_view_lib.dart';

/// Animates a morph effect of two widgets.
class MorphTransition extends MultiChildRenderObjectWidget {
  MorphTransition({
    Key? key,
    this.alignment = AlignmentDirectional.topStart,
    this.textDirection,
    this.fit = StackFit.loose,
    this.clipBehavior = Clip.hardEdge,
    required Widget? fromChild,
    required Widget? toChild,
    this.animation,
    this.resizeChildrenWhenAnimating = false,
  }) : super(key: key, children: [fromChild!, toChild!]);

  final AlignmentGeometry alignment;
  final TextDirection? textDirection;
  final StackFit fit;
  final Clip clipBehavior;
  final Animation<double>? animation;
  final bool resizeChildrenWhenAnimating;

  @override
  _MorphRenderStack createRenderObject(BuildContext context) {
    return _MorphRenderStack(
      alignment: alignment,
      textDirection: textDirection ?? Directionality.of(context),
      fit: fit,
      clipBehavior: clipBehavior,
      animation: animation!,
      resizeChildrenWhenAnimating: resizeChildrenWhenAnimating,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _MorphRenderStack renderObject) {
    renderObject
      ..alignment = alignment
      ..textDirection = textDirection ?? Directionality.of(context)
      ..fit = fit
      ..clipBehavior = clipBehavior
      ..animation = animation!
      ..resizeChildrenWhenAnimating = resizeChildrenWhenAnimating;
  }
}

class _MorphRenderStack extends RenderStack {
  RenderBox? _firstChild, _secondChild;

  _MorphRenderStack({
    List<RenderBox>? children,
    AlignmentGeometry alignment = AlignmentDirectional.topStart,
    TextDirection? textDirection,
    StackFit fit = StackFit.loose,
    Clip clipBehavior = Clip.hardEdge,
    required Animation<double> animation,
    required bool resizeChildrenWhenAnimating,
  })   : resizeChildrenWhenAnimating = resizeChildrenWhenAnimating,
        super(
          children: children,
          alignment: alignment,
          textDirection: textDirection,
          fit: fit,
          clipBehavior: clipBehavior,
        ) {
    this.animation = animation;
    _updateAnimation();
  }

  Animation<double> get animation => _animation!;
  Animation<double>? _animation;
  set animation(Animation<double> value) {
    if (_animation == value) return;
    if (attached && _animation != null) {
      _animation!.removeListener(_updateAnimation);
    }
    _animation = value;
    if (attached) _animation!.addListener(_updateAnimation);
    _updateAnimation();
  }

  bool resizeChildrenWhenAnimating;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation!.addListener(_updateAnimation);
    _updateAnimation(); // in case it changed while we weren't listening
  }

  @override
  void detach() {
    _animation!.removeListener(_updateAnimation);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => _currentlyNeedsCompositing;
  bool _currentlyNeedsCompositing = false;

  double? _animationValue;
  int? _alpha;

  void _updateAnimation() {
    final oldValue = _animationValue;
    _animationValue = _animation!.value;
    if (oldValue != _animationValue) {
      markNeedsLayout();
    }

    final oldAlpha = _alpha ?? 0;
    _alpha = ui.Color.getAlphaFromOpacity(_animation!.value);
    if (oldAlpha != _alpha) {
      markNeedsPaint();
    }

    if (oldAlpha == 0 ||
        _alpha == 0 ||
        (oldAlpha < 128 && _alpha! > 128 || oldAlpha > 128 && _alpha! < 128)) {
      markNeedsSemanticsUpdate();
    }

    final didNeedCompositing = _currentlyNeedsCompositing;
    _currentlyNeedsCompositing = (_alpha! > 0 && _alpha! < 255);

    if (didNeedCompositing != _currentlyNeedsCompositing) {
      markNeedsCompositingBitsUpdate();
    }
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitor((_alpha! > 128) ? _secondChild! : _firstChild!);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_alpha == 255) {
      layer = null;
      _opacityLayer = null;
      context.paintChild(_secondChild!, offset);
      return;
    }
    if (_alpha == 0) {
      layer = null;
      _opacityLayer = null;
      context.paintChild(_firstChild!, offset);
      return;
    }
    assert(needsCompositing);

    void paintFirstChild(PaintingContext context, Offset offset) {
      final childParentData = _firstChild!.parentData as StackParentData;
      context.paintChild(_firstChild!, childParentData.offset + offset);
    }

    void paintSecondChild(PaintingContext context, Offset offset) {
      final childParentData = _secondChild!.parentData as StackParentData;
      context.paintChild(_secondChild!, childParentData.offset + offset);
    }

    void paintChildren(PaintingContext context, Offset offset) {
      layer = context.pushOpacity(offset, 255 - _alpha!, paintFirstChild,
          oldLayer: layer as OpacityLayer?);
      _opacityLayer = context.pushOpacity(offset, _alpha!, paintSecondChild,
          oldLayer: _opacityLayer);
    }

    if (resizeChildrenWhenAnimating ||
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
    return _firstChild!.size.width == _secondChild!.size.width &&
        _firstChild!.size.height == _secondChild!.size.height;
  }

  ClipRectLayer? _clipRectLayer;
  OpacityLayer? _opacityLayer = OpacityLayer();

  @override
  void performLayout() {
    super.performLayout();

    _firstChild = firstChild;
    _secondChild = (firstChild!.parentData as StackParentData).nextSibling;

    var height = _firstChild!.size.height +
        (_secondChild!.size.height - _firstChild!.size.height) *
            (_animationValue ?? 0);

    var width = _firstChild!.size.width +
        (_secondChild!.size.width - _firstChild!.size.width) *
            (_animationValue ?? 0);

    width = constraints.constrainWidth(width);
    height = constraints.constrainHeight(height);

    if (resizeChildrenWhenAnimating) {
      BoxConstraints sizedConstraints;
      sizedConstraints = BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: height,
        maxHeight: height,
      );
      _firstChild!.layout(sizedConstraints, parentUsesSize: true);
      _secondChild!.layout(sizedConstraints, parentUsesSize: true);
    } else {
      _firstChild!.layout(constraints, parentUsesSize: true);
      _secondChild!.layout(constraints, parentUsesSize: true);
    }

    size = Size(width, height);
  }
}
