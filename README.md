# great_list_view

A Flutter package that includes a powerful, animated and reorderable list view. Just notify the list view of changes in your underlying list and the list view will automatically animate. You can also change the entire list and automatically dispatch the differences detected by the Myers alghoritm. 
You can also reorder items by simply long-tapping the item you want to move.

Compared to the standard `AnimatedList`, `ReorderableListView` material widgets or other thid-party libraries, this library offers more:

- no specific widget is needed, it works via `Sliver`, so you can include it in a `CustomScrollView` and eventually combine it with other slivers;
- it works without necessarily specifying a `List` object, but simply using a index-based `builder` callback;
- all changes to list view items are gathered and grouped into intervals, so for examaple you can remove a whole interval of a thousand items with a single remove change;
- removal, insertion e modification animations look like on Android framework;
- it is not mandatory to provide a key for each item, although it is advisable, because everything works using only indexes;
- it also works well even with a very long list;
- the library just extends `SliverWithKeepAliveWidget` and `RenderObjectElement` classes, no `Stack`, `Offstage` or `Overlay` widgets are used;
- kept alive items still work well.

This package also provides a tree adapter to create a tree view without defining a new widget for it, but simply by converting your tree data into a linear list view, animated or not. Your tree data can be any data type, just describe it using a model based on a bunch of callbacks.

<b>IMPORTANT!!!
This is still an alpha version! This library is constantly evolving and bug fixing, so it may change very often at the moment. 
</b>

## Installing

Add this to your `pubspec.yaml` file:

```yaml
dependencies:
  great_list_view: ^0.0.10
```

and run;

```sh
flutter packages get
```

## Example 1

This is an example of how to use `AnimatedSliverList` with a `ListAnimatedListDiffDispatcher`, which works on `List` objects, to swap two lists with automated animations.
The list view is even reorderable.

![Example 1](https://drive.google.com/uc?id=1y2jnZ2k0eAfu9KYtH6JG8d5Aj8bwTONL)

```dart
import 'package:flutter/material.dart';

import 'package:great_list_view/great_list_view.dart';
import 'package:worker_manager/worker_manager.dart';

void main() async {
  await Executor().warmUp();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Test App',
        theme: ThemeData(
          primarySwatch: Colors.yellow,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: SafeArea(
            child: Scaffold(
          body: MyListView(),
        )));
  }
}

class MyItem {
  final int id;
  final Color color;
  final double? fixedHeight;
  const MyItem(this.id, [this.color = Colors.blue, this.fixedHeight]);
}

Widget buildItem(BuildContext context, MyItem item, int index,
    AnimatedListBuildType buildType) {
  return GestureDetector(
      onTap: click,
      child: SizedBox(
          height: item.fixedHeight,
          child: DecoratedBox(
              key: buildType == AnimatedListBuildType.NORMAL
                  ? ValueKey(item)
                  : null,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12, width: 0)),
              child: Container(
                  color: item.color,
                  margin: EdgeInsets.all(5),
                  padding: EdgeInsets.all(15),
                  child: Center(
                      child: Text(
                    'Item ${item.id}',
                    style: TextStyle(fontSize: 16),
                  ))))));
}

List<MyItem> listA = [
  MyItem(1, Colors.orange),
  MyItem(2),
  MyItem(3),
  MyItem(4),
  MyItem(5),
  MyItem(8, Colors.green)
];
List<MyItem> listB = [
  MyItem(2),
  MyItem(6),
  MyItem(5, Colors.pink, 100),
  MyItem(7),
  MyItem(8, Colors.yellowAccent)
];

AnimatedListController controller = AnimatedListController();

final diff = ListAnimatedListDiffDispatcher<MyItem>(
  animatedListController: controller,
  currentList: listA,
  itemBuilder: buildItem,
  comparator: MyComparator.instance,
);

class MyComparator extends ListAnimatedListDiffComparator<MyItem> {
  MyComparator._();

  static MyComparator instance = MyComparator._();

  @override
  bool sameItem(MyItem a, MyItem b) => a.id == b.id;

  @override
  bool sameContent(MyItem a, MyItem b) =>
      a.color == b.color && a.fixedHeight == b.fixedHeight;
}

bool swapList = true;

void click() {
  if (swapList) {
    diff.dispatchNewList(listB);
  } else {
    diff.dispatchNewList(listA);
  }
  swapList = !swapList;
}

class MyListView extends StatefulWidget {
  @override
  _MyListViewState createState() => _MyListViewState();
}

class _MyListViewState extends State<MyListView> {
  @override
  Widget build(BuildContext context) {
    return Scrollbar(
        child: CustomScrollView(
      slivers: <Widget>[
        AnimatedSliverList(
          delegate: AnimatedSliverChildBuilderDelegate(
            (BuildContext context, int index, AnimatedListBuildType buildType, [dynamic slot]) {
              return buildItem(
                  context, diff.currentList[index], index, buildType);
            },
            childCount: () => diff.currentList.length,
            onReorderStart: (i, dx, dy) => true,
            onReorderMove: (i, j) => true,
            onReorderComplete: (i, j, slot) {
              var list = diff.currentList;
              var el = list.removeAt(i);
              list.insert(j, el);
              return true;
            },
          ),
          controller: controller,
          reorderable: true,
        )
      ],
    ));
  }
}
```

## Example 2

This is an example of how to use `TreeListAdapter` with an `AnimatedSliverList` to create an editable and reorderable tree view widget.

![Example 2](https://drive.google.com/uc?id=1gvzqX7lp1Q3CgqYTMcvRK5iXa9Ua87DX)

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';
import 'package:worker_manager/worker_manager.dart';

void main() async {
  await Executor().warmUp();
  buildTree(r, root, 5, 3);
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Test App',
        theme: ThemeData(
          primarySwatch: Colors.yellow,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: SafeArea(
            child: Scaffold(
          body: MyTreeView(),
        )));
  }
}

const List<String> kNames = [
  'Liam',
  'Olivia',
  'Noah',
  'Emma',
  'Oliver',
  'Ava',
  'William',
  'Sophia',
  'Elijah',
  'Isabella',
  'James',
  'Charlotte',
  'Benjamin',
  'Amelia',
  'Lucas',
  'Mia',
  'Mason',
  'Harper',
  'Ethan',
  'Evelyn'
];

Random r = Random();

class MyNode {
  final String text;
  List<MyNode> children = [];
  MyNode? parent;

  MyNode(this.text);

  void add(MyNode n, [int? index]) {
    (index == null) ? children.add(n) : children.insert(index, n);
    n.parent = this;
  }

  @override
  String toString() => text;
}

MyNode root = MyNode('Me');

void buildTree(Random r, MyNode node, int maxChildren, [int? startWith]) {
  var n = startWith ?? (maxChildren > 0 ? r.nextInt(maxChildren) : 0);
  if (n == 0) return;
  for (var i = 0; i < n; i++) {
    var child = MyNode(kNames[r.nextInt(kNames.length)]);
    buildTree(r, child, maxChildren - 1);
    node.add(child);
  }
}

Set<MyNode> collapsedMap = {};

AnimatedListController controller = AnimatedListController();
ScrollController scrollController = ScrollController();

TreeListAdapter<MyNode> adapter = TreeListAdapter<MyNode>(
  childAt: (node, index) => node.children[index],
  childrenCount: (node) => node.children.length,
  parentOf: (node) => node.parent!,
  indexOfChild: (parent, node) => parent.children.indexOf(node),
  isNodeExpanded: (node) => !collapsedMap.contains(node),
  includeRoot: true,
  root: root,
);

class MyTreeView extends StatefulWidget {
  @override
  _MyTreeViewState createState() => _MyTreeViewState();
}

class _MyTreeViewState extends State<MyTreeView> {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
        controller: scrollController,
        cacheExtent: 0,
        slivers: <Widget>[
          AnimatedSliverList(
              controller: controller,
              reorderable: true,
              delegate: AnimatedSliverChildBuilderDelegate(
                (BuildContext context, int index,
                    AnimatedListBuildType buildType,
                    [dynamic slot]) {
                  return itemBuilder(adapter, context, index, buildType, slot);
                },
                childCount: () => adapter.count,
                onReorderStart: (index, dx, dy) {
                  if (adapter.includeRoot && index == 0) return false;
                  var node = adapter.indexToNode(index);
                  if (!adapter.isLeaf(node) && adapter.isNodeExpanded(node)) {
                    // cannot reorder an open node! the long click must first collapse it
                    adapter.notifyNodeCollapsing(node, () {
                      collapsedMap.add(node);
                    },
                        index: index,
                        controller: controller,
                        builder: itemBuilder);
                    controller.dispatchChanges();
                    controller.markNeedsSoftRefresh();
                    return false;
                  }
                  return true;
                },
                onReorderFeedback: (fromIndex, toIndex, offset, dx, dy) {
                  var level = adapter.levelOf(adapter.indexToNode(fromIndex)) +
                      dx ~/ 25.0;
                  var levels =
                      adapter.getPossibleLevelsOfMove(fromIndex, toIndex);
                  return level.clamp(levels.from, levels.to - 1);
                },
                onReorderMove: (fromIndex, toIndex) {
                  return !adapter.includeRoot || toIndex != 0;
                },
                onReorderComplete: (fromIndex, toIndex, slot) {
                  var levels =
                      adapter.getPossibleLevelsOfMove(fromIndex, toIndex);
                  if (!levels.isIn(slot as int)) return false;
                  adapter.notifyNodeMoving(
                    fromIndex,
                    toIndex,
                    slot,
                    (pNode, node) => pNode.children.remove(node),
                    (pNode, node, pos) => pNode.add(node, pos),
                  );
                  return true;
                },
              )),
        ]);
  }
}

class TreeNode extends StatelessWidget {
  final MyNode node;
  final Duration duration;
  final int level;
  final bool? expanded;
  final void Function(bool expanded) onExpandCollapseTap;
  final void Function() onRemoveTap;
  final void Function() onInsertTap;
  TreeNode({
    Key? key,
    required this.node,
    required this.duration,
    required this.level,
    required this.expanded,
    required this.onExpandCollapseTap,
    required this.onRemoveTap,
    required this.onInsertTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      trailing: _buildExpandCollapseArrowButton(),
      leading: _buildAddRemoveButtons(),
      title: AnimatedContainer(
        padding: EdgeInsets.only(left: level * 15.0),
        duration: duration,
        child: Text(node.toString(), style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _buildAddRemoveButtons() {
    return SizedBox(
        width: 40,
        child: Row(
          children: [
            _buildIconButton(Colors.red, const Icon(Icons.remove), onRemoveTap),
            _buildIconButton(Colors.green, const Icon(Icons.add), onInsertTap),
          ],
        ));
  }

  Widget? _buildExpandCollapseArrowButton() {
    if (expanded == null) return null;
    return ArrowButton(
      expanded: expanded!,
      turns: 0.25,
      icon: const Icon(Icons.keyboard_arrow_right),
      duration: const Duration(milliseconds: 500),
      onTap: onExpandCollapseTap,
    );
  }

  static Widget _buildIconButton(
      Color color, Icon icon, void Function() onPressed) {
    return DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: color, width: 2)),
        child: SizedBox(
            width: 20,
            height: 25,
            child: IconButton(
                padding: EdgeInsets.all(0.0),
                iconSize: 15,
                icon: icon,
                onPressed: onPressed)));
  }
}

Widget itemBuilder(TreeListAdapter<MyNode> adapter, BuildContext context,
    int index, AnimatedListBuildType buildType,
    [dynamic slot]) {
  var node = adapter.indexToNode(index);
  return TreeNode(
    key: (buildType == AnimatedListBuildType.NORMAL) ? ValueKey(node) : null,
    duration: (buildType == AnimatedListBuildType.REORDERING)
        ? const Duration(milliseconds: 250)
        : Duration.zero,
    node: node,
    level: buildType == AnimatedListBuildType.REORDERING
        ? slot as int
        : adapter.levelOf(node),
    expanded: adapter.isLeaf(node) ? null : adapter.isNodeExpanded(node),
    onExpandCollapseTap: (expanded) {
      if (expanded) {
        adapter.notifyNodeExpanding(node, () {
          collapsedMap.remove(node);
        }, controller: controller);
      } else {
        adapter.notifyNodeCollapsing(node, () {
          collapsedMap.add(node);
        }, controller: controller, builder: itemBuilder);
      }
      controller.dispatchChanges();
    },
    onRemoveTap: () {
      adapter.notifyNodeRemoving(node, () {
        node.parent!.children.remove(node);
      }, controller: controller, builder: itemBuilder);
      controller.dispatchChanges();
      controller.markNeedsSoftRefresh();
    },
    onInsertTap: () {
      var newTree = MyNode(kNames[r.nextInt(kNames.length)]);
      adapter.notifyNodeInserting(newTree, node, 0, () {
        node.add(newTree, 0);
      }, controller: controller);
      controller.dispatchChanges();
      controller.markNeedsSoftRefresh();
    },
  );
}
```
