import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';
import 'package:worker_manager/worker_manager.dart';

void main() {
  Executor().warmUp();
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Test App',
        home: SafeArea(
            child: Scaffold(
          body: Body(key: gkey),
        )));
  }
}

class Body extends StatefulWidget {
  const Body({ super.key });

  @override
  State<Body> createState() => _BodyState();
}

class _BodyState extends State<Body> {
  late List<ItemData> currentList;

  @override
  void initState() {
    super.initState();
    currentList = listA;
  }

  void swapList() {
    setState(() {
      if (currentList == listA) {
        currentList = listB;
      } else {
        currentList = listA;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: AutomaticAnimatedListView<ItemData>(
        list: currentList,
        comparator: AnimatedListDiffListComparator<ItemData>(
            sameItem: (a, b) => a.id == b.id,
            sameContent: (a, b) =>
                a.color == b.color && a.fixedHeight == b.fixedHeight),
        itemBuilder: (context, item, data) => data.measuring
            ? Container(
                margin: const EdgeInsets.all(5), height: item.fixedHeight ?? 60)
            : Item(data: item),
        listController: controller,
        addLongPressReorderable: true,
        reorderModel: AutomaticAnimatedListReorderModel(currentList),
      ),
    );
  }
}

class Item extends StatelessWidget {
  final ItemData data;

  const Item({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () => gkey.currentState?.swapList(),
        child: AnimatedContainer(
            height: data.fixedHeight ?? 60,
            duration: const Duration(milliseconds: 500),
            margin: const EdgeInsets.all(5),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: data.color,
                border: Border.all(color: Colors.black12, width: 0)),
            child: Center(
                child: Text(
              'Item ${data.id}',
              style: const TextStyle(fontSize: 16),
            ))));
  }
}

class ItemData {
  final int id;
  final Color color;
  final double? fixedHeight;
  const ItemData(this.id, [this.color = Colors.blue, this.fixedHeight]);
}

final listA = <ItemData>[
  const ItemData(1, Colors.orange),
  const ItemData(2),
  const ItemData(3),
  const ItemData(4),
  const ItemData(5),
  const ItemData(8, Colors.green)
];
final listB = <ItemData>[
  const ItemData(2),
  const ItemData(6),
  const ItemData(5, Colors.pink, 100),
  const ItemData(7),
  const ItemData(8, Colors.yellowAccent)
];

final controller = AnimatedListController();
final gkey = GlobalKey<_BodyState>();
