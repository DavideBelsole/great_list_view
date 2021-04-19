import 'package:flutter/material.dart';

import 'package:great_list_view/great_list_view.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:worker_manager/worker_manager.dart' show Executor;

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
            rebuildMovedItems: false,
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
