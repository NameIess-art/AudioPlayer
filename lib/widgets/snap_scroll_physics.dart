import 'package:flutter/widgets.dart';

class SnapScrollPhysics extends ScrollPhysics {
  const SnapScrollPhysics({
    super.parent,
    this.minPageFlingVelocity = 650,
    this.pageTurnDistance = 0.5,
  });

  final double minPageFlingVelocity;
  final double pageTurnDistance;

  @override
  SnapScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SnapScrollPhysics(
      parent: buildParent(ancestor),
      minPageFlingVelocity: minPageFlingVelocity,
      pageTurnDistance: pageTurnDistance,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange || position.viewportDimension <= 0) {
      return super.createBallisticSimulation(position, velocity);
    }

    final page = position.pixels / position.viewportDimension;
    final currentPage = page.roundToDouble();
    final pageDelta = page - currentPage;
    var targetPage = currentPage;

    if (velocity.abs() >= minPageFlingVelocity) {
      targetPage = velocity < 0 ? page.ceilToDouble() : page.floorToDouble();
    } else if (pageDelta.abs() >= pageTurnDistance.clamp(0.05, 0.95)) {
      targetPage = pageDelta > 0 ? page.ceilToDouble() : page.floorToDouble();
    }

    final targetPixels = (targetPage * position.viewportDimension).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((targetPixels - position.pixels).abs() <
        toleranceFor(position).distance) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      targetPixels.toDouble(),
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}
