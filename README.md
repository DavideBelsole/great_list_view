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
```