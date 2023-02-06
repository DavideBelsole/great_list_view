## [0.0.1] to [0.0.8] - 13-11-2020

Initial alpha release. Includes `AnimatedSliverList`, `AnimatedListDiffDispatcher` and `TreeListAdapter` core classes.

## [0.0.9] - 19-04-2021

- Bug fixes;
- Null-safety support.

## [0.0.10] - 17-05-2021

- fixed worker_manager depedencies error.

## [0.1.0] - 07-09-2021

- Library completely revised and rewritten;
- Removed animation builders (AnimatedListAnimationBuilder) in favor of keeping item states at all times: wrapping the item to add animation effects was resulting in losing the item state);
- Outcoming and incoming items share the same animation now (see AnimatedWidgetBuilderData.animation);
- Removed changing animation in favor of implicit flutter animations: alternatively, the new widget MorphTransition has been introduced to create a cross-fade effect when item is changing its content;
- Introduced the AnimatedSliverFixedExtentList, inspired by SliverFixedExtentList, to create a list with fixed size items;
- Introduced the AnimatedListView, inspired by ListView, to create a list view faster, without necessarily using slivers;
- Reordering now works even while the list is animating.

## [0.2.0] - 28-12-2022

- Library has been revised and rewritten (again);
- New feature: now, items can be moved with animations;
- Library dependencies bug fixed.

## [0.2.1] - 31.01.2023

- bug fix assertion '_notificationCallStackDepth == 0'

## [0.2.2] to [0.2.3] - 02.02.2023

- fixed several bugs, more stable version
