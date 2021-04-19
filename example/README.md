# great_list_view

A Flutter package that includes a powerful, animated and reorderable list view. Just notify the list view of changes in your underlying list and the list view will automatically animate. You can also change the entire list and automatically dispatch the differences detected by the Myers alghoritm. 
You can also reorder items by simply long-tapping the item you want to move.

## Example

This is an example of how to use `AnimatedSliverList` with a `ListAnimatedListDiffDispatcher`, which works on `List` objects, to swap two lists with automated animations.
The list view is even reorderable.

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
          body: AnimatedListExample(),
        )));
  }
}

class MyItem {
  final int id;
  final Color color;
  final double fixedHeight;
  const MyItem(this.id, [this.color = Colors.blue, this.fixedHeight]);
}

Widget buildItem(BuildContext context, MyItem item, final bool animating) {
  return GestureDetector(
      onTap: click,
      child: SizedBox(
          height: item.fixedHeight,
          child: DecoratedBox(
              key: !animating ? ValueKey(item) : null,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12, width: 0)),
              child: Container(
                  color: item.color,
                  margin: EdgeInsets.all(5),
                  padding: EdgeInsets.all(15),
                  child: Center(
                      child: Text(
                    "Item ${item.id}",
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
  MyItem(8, Colors.green)
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

class AnimatedListExample extends StatefulWidget {
  @override
  _AnimatedListExampleState createState() => _AnimatedListExampleState();
}

class _AnimatedListExampleState extends State<AnimatedListExample> {
  @override
  Widget build(BuildContext context) {
    return Scrollbar(
        child: CustomScrollView(
      slivers: <Widget>[
        AnimatedSliverList(
          delegate: AnimatedSliverChildBuilderDelegate(
            (BuildContext context, int index, bool animating) {
              return buildItem(context, diff.currentList[index], animating);
            },
            childCount: () => diff.currentList.length,
          ),
          controller: controller,
        )
      ],
    ));
  }
}
```