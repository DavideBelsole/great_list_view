# great_list_view

## Overview

A Flutter package that includes a powerful, animated and reorderable list view. Just notify the list view of changes in your underlying list and the list view will automatically animate. You can also change the entire list and automatically dispatch the differences detected by the Myers alghoritm. 
You can also reorder the items of your list, by simply long-tapping the item you want to move or otherwise, for example via a drag handle.

Compared to the `AnimatedList`, `ReorderableListView` material widgets or other thid-party libraries, this library offers:

- it can be both animated and reordered at the same time;
- it works without necessarily specifying a `List` object, but simply using index-based `builder` callbacks;
- all changes to list view items are gathered and grouped into intervals, so for example you can remove a whole interval of a thousand items with a single remove change without losing in performance;
- it also works well even with a very long list;
- the library doesn't use additional widget for items, like `Stack`, `Offstage` or `Overlay`.
- it is not mandatory to provide a key for each item, because everything works using only indexes;

![Example 1](https://github.com/DavideBelsole/great_list_view/raw/master/images/example1.gif)

This package also provides a tree adapter to create a tree view without defining a new widget for it, but simply by converting your tree data into a linear list view, animated or not. Your tree data can be any data type, just describe it using a model based on a bunch of callbacks.

![Example 2](https://github.com/DavideBelsole/great_list_view/raw/master/images/example2.gif)

<b>IMPORTANT!!!
This is still an alpha version! This library is constantly evolving and bug fixing, so it may change very often at the moment, sorry.

This library lacks of a bunch of features at the moment:
- Lack of a feature to create a separated list view (like ListView.separated construtor);
- No semantics are currently supported;
- No infinite lists are supported.

I am developing this library in my spare time just for pleasure. Although it may seem on the surface to be an easy library to develop, I assure you that it is instead quite complex. Therefore the time required for development is becoming more and more demanding.
Anyone who likes this library can support me by making a donation at will. This will definitely motivate me and push me to bring this library to its completion. I will greatly appreciate your contribution.
</b>

[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/donate?hosted_button_id=EJLUKSHKXMTNQ)


## Installing

Add this to your `pubspec.yaml` file:

```yaml
dependencies:
  great_list_view: ^0.2.3
```

and run;

```sh
flutter packages get
```

## Automatic Animated List View

The simplest way to create an animated list view that automatically animates to fit the contents of a `List` is to use the `AutomaticAnimatedListView` widget.
A list of data must be passed to the widget via the `list` attribute.
This widget uses an `AnimatedListDiffListDispatcher` internally. This class uses the Meyes algorithm that dispatches the differences to the list view after comparing the new `list` object with the old one.
In this regard, it is necessary to pass to the `comparator` attribute an `AnimatedListDiffListBaseComparator` object which takes care of comparing an item of the old list with an item of the new list via two methods:
- `sameItem` must return `true` if the two compared items are the same (if the items have their own ID, just check the two IDs are equal);
- `sameContent` is called only if `sameItem` has returned `true`, and must return `true` if the item has changed in content (if `false` is returned, this dispatches a change notification to the list view).
You can also use the callback function-based `AnimatedListDiffListComparator` version, saving you from creating a new derived class.

The list view needs an `AnimatedListController` object to be controlled. Just instantiate it and pass it to the `listController` attribute of the `AutomaticAnimatedListView` widget.
The `AutomaticAnimatedListView` widget uses the controller to notify the changes identified by the Meyes algorithm.

Finally, you have to pass a delegate to the `itemBuilder` attribute in order to build all item widgets of the list view.
The delegate has three parameters:
- the `BuildContext` to use to build items;
- the item of the `List`, which could be taken from either the old or the new list;
- an `AnimatedWidgetBuilderData` object, which provide further interesting information.

The most important attributes of the `AnimatedWidgetBuilderData` object to consider for sure are:
- `measuring` is a flag, and indicates to build an item not in order to be rendered on the screen, but only to measure its extent. This flag must certainly be taken into consideration for performance purposes if the item is a complex widget, as it will certainly be faster to measure an equivalent but simplified widget having the same extent. Furthermore, it is important that the widget does not have animation widgets inside, because the measurement performed must refer to its final state;
- `animation`, provides an `Animation` object to be used to animate the incoming and outcoming effects (which occur when the item is removed or inserted); the value `1` indicates that the item has completely entered the list view, whereas `0` indicates that the item is completely dismissed.
Unless you want to customize these animations, you can ignore this attribute.

By default, all animations are automatically wrapped around the item built by the `itemBuilder`, with the exception of animation which deals with modifying the content of a item, which must be implicit to the widget itself.
For example, if the content of the item reflects its size, margins or color, simply wrap the item in an `AnimatedContainer`: this widget will take care of implicitly animating the item when one of the above attributes changes value.

The `itemExtent` attribute can be used to set a fixed extent for all items.

If the `detectMoves` attribute is set to `true`, the dispatcher will also calculate if there are items that can be moved, rather than removing and inserting them from scratch.
I do not recommend enabling this attribute for lists that are too large, as the algorithm used by `AnimatedListDiffListDispatcher` to determine which items are moved is rather slow.

### Example 1 (Automatic Animated List View)

```dart
import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  Executor().warmUp();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
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
  Body({Key? key}) : super(key: key);

  @override
  _BodyState createState() => _BodyState();
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
      controller: scrollController,
      child: AutomaticAnimatedListView<ItemData>(
        list: currentList,
        comparator: AnimatedListDiffListComparator<ItemData>(
            sameItem: (a, b) => a.id == b.id,
            sameContent: (a, b) =>
                a.color == b.color && a.fixedHeight == b.fixedHeight),
        itemBuilder: (context, item, data) => data.measuring
            ? Container(
                margin: EdgeInsets.all(5), height: item.fixedHeight ?? 60)
            : Item(data: item),
        listController: controller,
        scrollController: scrollController,
        detectMoves: true,
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
            margin: EdgeInsets.all(5),
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: data.color,
                border: Border.all(color: Colors.black12, width: 0)),
            child: Center(
                child: Text(
              'Item ${data.id}',
              style: TextStyle(fontSize: 16),
            ))));
  }
}

class ItemData {
  final int id;
  final Color color;
  final double? fixedHeight;
  const ItemData(this.id, [this.color = Colors.blue, this.fixedHeight]);
}

List<ItemData> listA = [
  ItemData(1, Colors.orange),
  ItemData(2),
  ItemData(3),
  ItemData(4, Colors.cyan),
  ItemData(5),
  ItemData(8, Colors.green)
];
List<ItemData> listB = [
  ItemData(4, Colors.cyan),
  ItemData(2),
  ItemData(6),
  ItemData(5, Colors.pink, 100),
  ItemData(7),
  ItemData(8, Colors.yellowAccent),
];

final scrollController = ScrollController();
final controller = AnimatedListController();
final gkey = GlobalKey<_BodyState>();
```

However, if the changing content cannot be implicitly animated using implicit animations, such as animating a text that is changing, this library also provides the `MorphTransition` widget, which performs a cross-fade effect between an old widget and the new one.
The `MorphTransition` widget uses a delegate to be passed to the `comparator` attribute which takes care of comparing the old widget with the new one. This delegate has to return `false` if the two widgets are different, in order to trigger the cross-fade effect. 
This comparator needs to be well implemented, because returning `false` even when not necessary will lead to a drop in performance as this effect would also be applied to two completely identical widgets, thus wasting precious resources to perform an animation that is not actually necessary and that is not even perceptible to the human eye.

More simply, you can pass the delegate directly to the `morphComparator` attribute of the `AutomaticAnimatedListView` widget, in this way all items will automatically be wrapped with a `MorphTransition` widget.

For more features please read the documentation of the `AutomaticAnimatedListView` class.

### Example 2 (Automatic Animated List View with MorphTransition)

```dart
import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  Executor().warmUp();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
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
  Body({Key? key}) : super(key: key);

  @override
  _BodyState createState() => _BodyState();
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
      controller: scrollController,
      child: AutomaticAnimatedListView<ItemData>(
        list: currentList,
        comparator: AnimatedListDiffListComparator<ItemData>(
            sameItem: (a, b) => a.id == b.id,
            sameContent: (a, b) =>
                a.text == b.text &&
                a.color == b.color &&
                a.fixedHeight == b.fixedHeight),
        itemBuilder: (context, item, data) => data.measuring
            ? Container(
                margin: EdgeInsets.all(5), height: item.fixedHeight ?? 60)
            : Item(data: item),
        listController: controller,
        morphComparator: (a, b) {
          if (a is Item && b is Item) {
            return a.data.text == b.data.text &&
                a.data.color == b.data.color &&
                a.data.fixedHeight == b.data.fixedHeight;
          }
          return false;
        },
        scrollController: scrollController,
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
        child: Container(
            height: data.fixedHeight ?? 60,
            margin: EdgeInsets.all(5),
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: data.color,
                border: Border.all(color: Colors.black12, width: 0)),
            child: Center(
                child: Text(
              data.text,
              style: TextStyle(fontSize: 16),
            ))));
  }
}

class ItemData {
  final int id;
  final String text;
  final Color color;
  final double? fixedHeight;
  const ItemData(this.text, this.id,
      [this.color = Colors.blue, this.fixedHeight]);
}

List<ItemData> listA = [
  ItemData('Text 1', 1, Colors.orange),
  ItemData('Text 2', 2),
  ItemData('Text 3', 3),
  ItemData('Text 4', 4),
  ItemData('Text 5', 5),
  ItemData('Text 8', 8, Colors.green)
];
List<ItemData> listB = [
  ItemData('Text 2', 2),
  ItemData('Text 6', 6),
  ItemData('Other text 5', 5, Colors.pink, 100),
  ItemData('Text 7', 7),
  ItemData('Other text 8', 8, Colors.yellowAccent)
];

final scrollController = ScrollController();
final controller = AnimatedListController();
final gkey = GlobalKey<_BodyState>();
```

## Animated List View

If you want to have more control over the list view, or if your data is not just items of a `List` object, I suggest using the more flexible `AnimatedListView` widget.

Unlike the `AutomaticAnimatedListView` widget, the `AnimatedListView` does not use the Meyes algorithm internally, so all change notifications have to be manually notified to the list view.

As with the `AutomaticAnimatedListView` widget, you need to pass an `AnimatedListController` object to the `listController` attribute.

The widget also needs the initial count of the items, via `initialItemCount` attribute.
This attribute is only used in the very early stage of creating the widget, since the item count will then be automatically derived based on the notifications sent.

The delegate to pass to the `itemBuilder` attribute has the same purpose as the `AutomaticAnimatedListView`, however it differs in the second parameter. While the item itself of a `List` object was passed for the `AutomaticAnimatedListView`, an index is passed for the `AnimatedListView` instead.
The index of this builder will always refer to the final underlying list, i.e. the list already modified after all the notifications.

Removed or changed items will instead use another builder that will need to be passed to the controller.
For example, to notify the list view that the first three items have been removed, you need to call the controller's `notifyRemovedRange` method with `from = 0` and `count = 3`, and pass it a new builder that only builds the three removed items. The index, which ranges from `0` and `2`, will refer in this case only to the three removed items.
The other methods `notifyChangedRange`,` notifyInsertedRange`, `notifyReplacedRange` and `notifyMovedRange` can be used instead to respectfully notify a range of items that have been modified, inserted, replaced or moved.

If you need to send multiple notifications in sequence, it is recommended for performance purposes to invoke the `batch` method instead, which takes a parameterless delegate as input, and then send all the notifications within it.

### Example 3 (Animated List View)

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  Executor().warmUp();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Test App',
        home: SafeArea(
            child: Scaffold(
          floatingActionButton: FloatingActionButton.extended(
              label: Text('Random Change'), onPressed: randomChange),
          body: Body(),
        )));
  }
}

class Body extends StatelessWidget {
  Body({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      child: AnimatedListView(
        initialItemCount: list.length,
        itemBuilder: (context, index, data) => data.measuring
            ? Container(margin: EdgeInsets.all(5), height: 60)
            : Item(data: list[index]),
        listController: controller,
        scrollController: scrollController,
      ),
    );
  }
}

class Item extends StatelessWidget {
  final ItemData data;

  const Item({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        height: 60,
        margin: EdgeInsets.all(5),
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: kColors[data.color],
            border: Border.all(color: Colors.black12, width: 0)),
        child: Center(
            child: Text(
          'Item ${data.id}',
          style: TextStyle(fontSize: 16),
        )));
  }
}

final kColors = const <Color>[
  Colors.teal,
  Colors.lightGreen,
  Colors.redAccent,
  Colors.pink
];

class ItemData {
  final int id;
  final int color;
  const ItemData(this.id, [int color = 0]) : color = color % 4;
}

int id = 0;
List<ItemData> list = [for (var i = 1; i <= 10; i++) ItemData(++id)];

var r = Random();

void randomChange() {
  var activity = list.isEmpty ? 1 : r.nextInt(5);
  switch (activity) {
    case 0: // remove
      final from = r.nextInt(list.length);
      final to = from + 1 + r.nextInt(list.length - from);
      final subList = list.sublist(from, to);
      list.removeRange(from, to);
      controller.notifyRemovedRange(from, to - from,
          (context, index, data) => Item(data: subList[index]));
      break;
    case 1: // insert
      final from = r.nextInt(list.length + 1);
      final count = 1 + r.nextInt(5);
      list.insertAll(from, [for (var i = 0; i < count; i++) ItemData(++id)]);
      controller.notifyInsertedRange(from, count);
      break;
    case 2: // replace
      final from = r.nextInt(list.length);
      final to = from + 1 + r.nextInt(list.length - from);
      final count = 1 + r.nextInt(5);
      final subList = list.sublist(from, to);
      list.replaceRange(
          from, to, [for (var i = 0; i < count; i++) ItemData(++id)]);
      controller.notifyReplacedRange(from, to - from, count,
          (context, index, data) => Item(data: subList[index]));
      break;
    case 3: // change
      final from = r.nextInt(list.length);
      final to = from + 1 + r.nextInt(list.length - from);
      final subList = list.sublist(from, to);
      list.replaceRange(from, to, [
        for (var i = 0; i < to - from; i++)
          ItemData(subList[i].id, subList[i].color + 1)
      ]);
      controller.notifyChangedRange(from, to - from,
          (context, index, data) => Item(data: subList[index]));
      break;
    case 4: // move
      var from = r.nextInt(list.length);
      var count = 1 + r.nextInt(list.length - from);
      var newIndex = r.nextInt(list.length - count + 1);
      var to = from + count;
      final moveList = list.sublist(from, to);
      list.removeRange(from, to);
      list.insertAll(newIndex, moveList);
      controller.notifyMovedRange(from, count, newIndex);
      break;
  }
}

final scrollController = ScrollController();
final controller = AnimatedListController();
```

It is always possible to manually integrate the Meyes algorithm using an `AnimatedListDiffListDispatcher` or a more generic `AnimatedListDiffDispatcher` (if your data are not formed from elements of a `List` object).

For more features please read the documentation of the `AnimatedListView` class.

### Example 4 (Animated List View with a dispatcher)

```dart
import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  Executor().warmUp();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
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
  Body({Key? key}) : super(key: key);

  @override
  _BodyState createState() => _BodyState();
}

class _BodyState extends State<Body> {
  late AnimatedListDiffListDispatcher<ItemData> dispatcher;

  @override
  void initState() {
    super.initState();

    dispatcher = AnimatedListDiffListDispatcher<ItemData>(
      controller: controller,
      itemBuilder: itemBuilder,
      currentList: listA,
      comparator: AnimatedListDiffListComparator<ItemData>(
          sameItem: (a, b) => a.id == b.id,
          sameContent: (a, b) =>
              a.color == b.color && a.fixedHeight == b.fixedHeight),
    );
  }

  void swapList() {
    setState(() {
      if (dispatcher.currentList == listA) {
        dispatcher.dispatchNewList(listB, detectMoves: true);
      } else {
        dispatcher.dispatchNewList(listA, detectMoves: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      child: AnimatedListView(
        initialItemCount: dispatcher.currentList.length,
        itemBuilder: (context, index, data) =>
            itemBuilder(context, dispatcher.currentList[index], data),
        listController: controller,
        scrollController: scrollController,
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
            margin: EdgeInsets.all(5),
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: data.color,
                border: Border.all(color: Colors.black12, width: 0)),
            child: Center(
                child: Text(
              'Item ${data.id}',
              style: TextStyle(fontSize: 16),
            ))));
  }
}

Widget itemBuilder(
    BuildContext context, ItemData item, AnimatedWidgetBuilderData data) {
  if (data.measuring) {
    return Container(margin: EdgeInsets.all(5), height: item.fixedHeight ?? 60);
  }
  return Item(data: item);
}

class ItemData {
  final int id;
  final Color color;
  final double? fixedHeight;
  const ItemData(this.id, [this.color = Colors.blue, this.fixedHeight]);
}

List<ItemData> listA = [
  ItemData(1, Colors.orange),
  ItemData(2),
  ItemData(3),
  ItemData(4, Colors.cyan),
  ItemData(5),
  ItemData(8, Colors.green)
];
List<ItemData> listB = [
  ItemData(4, Colors.cyan),
  ItemData(2),
  ItemData(6),
  ItemData(5, Colors.pink, 100),
  ItemData(7),
  ItemData(8, Colors.yellowAccent),
];

final scrollController = ScrollController();
final controller = AnimatedListController();
final gkey = GlobalKey<_BodyState>();
```

## Animated Sliver List 

If the list view consists of multiple slivers, you will need to use the `AnimatedSliverList` (or `AnimatedSliverFixedExtentList` if the items all have a fixed extent) class within a `CustomScrollView` widget.

The `AnimatedSliverList` only needs two parameters, the usual `listController` and a delegate.

The `AutomaticAnimatedListView` and `AnimatedListView` widgets automatically use these slivers internally with the help of a default delegate implementation offered by the `AnimatedSliverChildBuilderDelegate` class.

The `AnimatedSliverChildBuilderDelegate` delegate is more than enough to cover most needs, however, if you need more control, you can always create a new one by extending the `AnimatedSliverChildDelegate` class. However, I don't recommend extending this class directly unless strictly necessary.

### Example 5 (Animated List using slivers)

```dart
import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  Executor().warmUp();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
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
  Body({Key? key}) : super(key: key);

  @override
  _BodyState createState() => _BodyState();
}

class _BodyState extends State<Body> {
  late AnimatedListDiffListDispatcher<ItemData> dispatcher;

  @override
  void initState() {
    super.initState();

    dispatcher = AnimatedListDiffListDispatcher<ItemData>(
      controller: controller,
      itemBuilder: itemBuilder,
      currentList: listA,
      comparator: AnimatedListDiffListComparator<ItemData>(
          sameItem: (a, b) => a.id == b.id,
          sameContent: (a, b) =>
              a.color == b.color && a.fixedHeight == b.fixedHeight),
    );
  }

  void swapList() {
    setState(() {
      if (dispatcher.currentList == listA) {
        dispatcher.dispatchNewList(listB);
      } else {
        dispatcher.dispatchNewList(listA);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverList(
              delegate: SliverChildBuilderDelegate(
            (BuildContext context, int itemIndex) {
              return Container(
                  alignment: Alignment.center,
                  height: 200,
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.red, width: 4)),
                  child: ListTile(title: Text('This is another sliver')));
            },
            childCount: 1,
          )),
          AnimatedSliverList(
              controller: controller,
              delegate: AnimatedSliverChildBuilderDelegate(
                  (context, index, data) =>
                      itemBuilder(context, dispatcher.currentList[index], data),
                  dispatcher.currentList.length))
        ],
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
            margin: EdgeInsets.all(5),
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: data.color,
                border: Border.all(color: Colors.black12, width: 0)),
            child: Center(
                child: Text(
              'Item ${data.id}',
              style: TextStyle(fontSize: 16),
            ))));
  }
}

Widget itemBuilder(
    BuildContext context, ItemData item, AnimatedWidgetBuilderData data) {
  if (data.measuring) {
    return Container(margin: EdgeInsets.all(5), height: item.fixedHeight ?? 60);
  }
  return Item(data: item);
}

class ItemData {
  final int id;
  final Color color;
  final double? fixedHeight;
  const ItemData(this.id, [this.color = Colors.blue, this.fixedHeight]);
}

List<ItemData> listA = [
  ItemData(1, Colors.orange),
  ItemData(2),
  ItemData(3),
  ItemData(4),
  ItemData(5),
  ItemData(8, Colors.green)
];
List<ItemData> listB = [
  ItemData(2),
  ItemData(6),
  ItemData(5, Colors.pink, 100),
  ItemData(7),
  ItemData(8, Colors.yellowAccent)
];

final scrollController = ScrollController();
final controller = AnimatedListController();
final gkey = GlobalKey<_BodyState>();
```

## Reordering

The list view can also be reordered on demand, even while it is animating.
You can enable the automatic reordering feature, which is activated by long pressing on the item you want to reorder, setting the `addLongPressReorderable` attribute to `true` (this attribute can also be found in the `AutomaticAnimatedListView`, `AnimatedListView` and` AnimatedSliverChildBuilderDelegate` classes).

In addition you have to pass a model to the `reorderModel` attribute by extending the `AnimatedListBaseReorderModel` class.
You can also use the callback function-based `AnimatedListReorderModel` version, saving you from creating a new derived class.

The fastest way to add support for reordering for all items is to use a `AutomaticAnimatedListView` widget and pass an instance of the `AutomaticAnimatedListReorderModel` class (it requires as input the same list you pass to the list view via the `list` attribute).

### Example 6 (Reorderable Automatic Animated List View)

```dart
import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  Executor().warmUp();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
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
  Body({Key? key}) : super(key: key);

  @override
  _BodyState createState() => _BodyState();
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
      controller: scrollController,
      child: AutomaticAnimatedListView<ItemData>(
        list: currentList,
        comparator: AnimatedListDiffListComparator<ItemData>(
            sameItem: (a, b) => a.id == b.id,
            sameContent: (a, b) =>
                a.color == b.color && a.fixedHeight == b.fixedHeight),
        itemBuilder: (context, item, data) => data.measuring
            ? Container(
                margin: EdgeInsets.all(5), height: item.fixedHeight ?? 60)
            : Item(data: item),
        listController: controller,
        addLongPressReorderable: true,
        reorderModel: AutomaticAnimatedListReorderModel(currentList),
        scrollController: scrollController,
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
            margin: EdgeInsets.all(5),
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: data.color,
                border: Border.all(color: Colors.black12, width: 0)),
            child: Center(
                child: Text(
              'Item ${data.id}',
              style: TextStyle(fontSize: 16),
            ))));
  }
}

class ItemData {
  final int id;
  final Color color;
  final double? fixedHeight;
  const ItemData(this.id, [this.color = Colors.blue, this.fixedHeight]);
}

List<ItemData> listA = [
  ItemData(1, Colors.orange),
  ItemData(2),
  ItemData(3),
  ItemData(4),
  ItemData(5),
  ItemData(8, Colors.green)
];
List<ItemData> listB = [
  ItemData(2),
  ItemData(6),
  ItemData(5, Colors.pink, 100),
  ItemData(7),
  ItemData(8, Colors.yellowAccent)
];

final scrollController = ScrollController();
final controller = AnimatedListController();
final gkey = GlobalKey<_BodyState>();
```

If you need more control, or if you are not using the `AutomaticAnimatedListView` widget, you will need to implement the reorder model manually.

The model requires the implementation of four methods.

In order to enable reordering of all items, simply have the `onReorderStart` callback return `true`. The function is called with the index of the item to be dragged for reordering, and the coordinates of the exact point touched. The function must return a flag indicating whether the item can be dragged/reordered or not.

To allow the dragged item to be dropped in the new moved position, simply have the `onReorderMove` callback return `true`. The function is called with the index of the item being dragged and the index that the item would assume. The function must return a flag indicating whether or not the item can be moved in that new position.

Finally you have to implement the `onReorderComplete` function to actually move the dragged item. As the `onReorderMove` method, the function is called by passing it the two indices, and must return `true` to confirm the swap. If the function returns `false`, the swap will fail, and the dragged item will return to its original position.
The `onReorderComplete` function is also responsible for actually swapping the two items in the underlying data list when it returns `true`.

For more details about the model read the documentation of the `AnimatedListBaseReorderModel` class.

### Example 7 (Reorderable Animated List View with custom reorder model)

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  Executor().warmUp();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Test App',
        home: SafeArea(
            child: Scaffold(
          floatingActionButton: FloatingActionButton.extended(
              label: Text('Random Change'), onPressed: randomChange),
          body: Body(),
        )));
  }
}

class Body extends StatelessWidget {
  Body({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      child: AnimatedListView(
        initialItemCount: list.length,
        itemBuilder: (context, index, data) => data.measuring
            ? Container(margin: EdgeInsets.all(5), height: 60)
            : Item(data: list[index]),
        listController: controller,
        addLongPressReorderable: true,
        reorderModel: AnimatedListReorderModel(
          onReorderStart: (index, dx, dy) {
            // only teal-colored items can be reordered
            return list[index].color == 0;
          },
          onReorderMove: (index, dropIndex) {
            // pink-colored items cannot be swapped
            return list[dropIndex].color != 3;
          },
          onReorderComplete: (index, dropIndex, slot) {
            list.insert(dropIndex, list.removeAt(index));
            return true;
          },
        ),
        scrollController: scrollController,
      ),
    );
  }
}

class Item extends StatelessWidget {
  final ItemData data;

  const Item({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        height: 60,
        margin: EdgeInsets.all(5),
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: kColors[data.color],
            border: Border.all(color: Colors.black12, width: 0)),
        child: Center(
            child: Text(
          'Item ${data.id}',
          style: TextStyle(fontSize: 16),
        )));
  }
}

final kColors = const <Color>[
  Colors.teal,
  Colors.lightGreen,
  Colors.redAccent,
  Colors.pink
];

class ItemData {
  final int id;
  final int color;
  const ItemData(this.id, [int color = 0]) : color = color % 4;
}

int id = 0;
List<ItemData> list = [
  for (var i = 1; i <= 10; i++) ItemData(++id, (id - 1) % 4)
];

var r = Random();

void randomChange() {
  var activity = list.isEmpty ? 1 : r.nextInt(4);
  switch (activity) {
    case 0: // remove
      final from = r.nextInt(list.length);
      final to = from + 1 + r.nextInt(list.length - from);
      final subList = list.sublist(from, to);
      list.removeRange(from, to);
      controller.notifyRemovedRange(from, to - from,
          (context, index, data) => Item(data: subList[index]));
      break;
    case 1: // insert
      final from = r.nextInt(list.length + 1);
      final count = 1 + r.nextInt(5);
      list.insertAll(from, [for (var i = 0; i < count; i++) ItemData(++id)]);
      controller.notifyInsertedRange(from, count);
      break;
    case 2: // replace
      final from = r.nextInt(list.length);
      final to = from + 1 + r.nextInt(list.length - from);
      final count = 1 + r.nextInt(5);
      final subList = list.sublist(from, to);
      list.replaceRange(
          from, to, [for (var i = 0; i < count; i++) ItemData(++id)]);
      controller.notifyReplacedRange(from, to - from, count,
          (context, index, data) => Item(data: subList[index]));
      break;
    case 3: // change
      final from = r.nextInt(list.length);
      final to = from + 1 + r.nextInt(list.length - from);
      final subList = list.sublist(from, to);
      list.replaceRange(from, to, [
        for (var i = 0; i < to - from; i++)
          ItemData(subList[i].id, subList[i].color + 1)
      ]);
      controller.notifyChangedRange(from, to - from,
          (context, index, data) => Item(data: subList[index]));
      break;
  }
}

final scrollController = ScrollController();
final controller = AnimatedListController();
```

If you want to implement a custom reordering, for example based on dragging an handle instead of long pressing the item, you will have to use the controller again to notify the various steps of the reordering process, calling the `notifyStartReorder`, `notifyUpdateReorder` and `notifyStopReorder` methods.

The `notifyStartReorder` method must be called first, by passing it as a parameter the build context of the item to be dragged, as well as the coordinates of the point that will be used as the origin point for the translation.
In order to translate the item to the new position you have to call the `notifyUpdateReorder` method, passing it the coordinates of the new point.
Finally, to finish the reordering you have to call the `notifyStopReorder` method.

### Example 8 (Reorderable Automatic Animated List View with a handle)

```dart
import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  Executor().warmUp();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
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
  Body({Key? key}) : super(key: key);

  @override
  _BodyState createState() => _BodyState();
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
      controller: scrollController,
      child: AutomaticAnimatedListView<ItemData>(
        list: currentList,
        comparator: AnimatedListDiffListComparator<ItemData>(
            sameItem: (a, b) => a.id == b.id,
            sameContent: (a, b) =>
                a.color == b.color && a.fixedHeight == b.fixedHeight),
        itemBuilder: (context, item, data) => data.measuring
            ? Container(
                margin: EdgeInsets.all(5), height: item.fixedHeight ?? 60)
            : Item(data: item),
        listController: controller,
        reorderModel: AutomaticAnimatedListReorderModel(currentList),
        addLongPressReorderable: false,
        scrollController: scrollController,
      ),
    );
  }
}

class Item extends StatelessWidget {
  final ItemData data;

  const Item({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: GestureDetector(
              onTap: () => gkey.currentState?.swapList(),
              child: AnimatedContainer(
                  height: data.fixedHeight ?? 60,
                  duration: const Duration(milliseconds: 500),
                  margin: EdgeInsets.all(5),
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: data.color,
                      border: Border.all(color: Colors.black12, width: 0)),
                  child: Center(
                      child: Text(
                    'Item ${data.id}',
                    style: TextStyle(fontSize: 16),
                  ))))),
      GestureDetector(
        onVerticalDragStart: (dd) {
          controller.notifyStartReorder(
              context, dd.localPosition.dx, dd.localPosition.dy);
        },
        onVerticalDragUpdate: (dd) {
          controller.notifyUpdateReorder(
              dd.localPosition.dx, dd.localPosition.dy);
        },
        onVerticalDragEnd: (dd) {
          controller.notifyStopReorder(false);
        },
        onVerticalDragCancel: () {
          controller.notifyStopReorder(true);
        },
        child: Icon(Icons.drag_handle),
      )
    ]);
  }
}

class ItemData {
  final int id;
  final Color color;
  final double? fixedHeight;
  const ItemData(this.id, [this.color = Colors.blue, this.fixedHeight]);
}

List<ItemData> listA = [
  ItemData(1, Colors.orange),
  ItemData(2),
  ItemData(3),
  ItemData(4),
  ItemData(5),
  ItemData(8, Colors.green)
];
List<ItemData> listB = [
  ItemData(2),
  ItemData(6),
  ItemData(5, Colors.pink, 100),
  ItemData(7),
  ItemData(8, Colors.yellowAccent)
];

final scrollController = ScrollController();
final controller = AnimatedListController();
final gkey = GlobalKey<_BodyState>();
```

The model also provides the `onReorderFeedback` method which can be implemented to gain more control over the drag phase.
The method is continuously called every time the dragged item is moved not only along the main axis of the list view, but also along the cross axis, passing the delta of the deviation from the origin point.
The method have to return an instance of any object (or null) each time.
If the object instance is different from the one returned in the previous call, the dragged item will be rebuilded.
The last instance returned from the `onReorderFeedback` method will eventually be passed as the last argument to the `onReorderComplete` method.

An example of the use of the feedback is shown in the tree list adapter example in order to implement a horizontal drag feature (cross axis), used to change the parent of the node being dragged.

## Tree List Adapter

Does you data consist of nodes in a hierarchical tree and you need a tree view to show them? No problem, you can use the `TreeistAdapter` class to convert the nodes to a linear list.
Each node will therefore be an item of a list view corresponding to a specific index.
The `nodeToIndex` and `indexToNode` methods can be used the former to determine the list index of a particular node and the latter to determine the node corresponding to a given index.
The class internally uses a window that shows only a part of the tree properly converted into a linear list. Each time the index of a new node is requested, the window will be moved to contain that node.

In order to perform this conversion, the adapter needs a model that describes the tree.
The model is nothing more than a bunch of callback functions that you have to implement. These are:
- `parentOf` returns the parent of a node;
- `childrenCount` returns the count of the children belonging to a node;
- `childAt` returns the child node of a parent node at a specific position;
- `isNodeExpanded` returns `true` if the node is expanded, `false` if it is collapsed;
- `indexOfChild` returns the position of a child node with respect to the parent node;
- `equals` returns `true` if two nodes are equal.

To notify when a particular node is expanded or collapsed, the `notifyNodeExpanding` and `notifyNodeCollapsing` methods must be called respectively. It will be necessary to pass the involved node and a callback function that updates the status of the node (expanded / collapsed).

To notify when a particular node is removed from or inserted into the tree, the `notifyNodeRemoving` and `notifyNodeInserting` methods must be called respectively. It will be necessary to pass the involved node and a callback function that updates the tree, performing the actual removal or insertion of the node.

Instead, to notify when a node is moved from a certain position to a new one, use the `notifyNodeMoving` method (see documentation for more details).

This adapter works well also with a normal `ListView`. However, the adapter also offers the ability to automatically notify changes to an animated list view by simply passing the controller of your list view in the constructor.

### Example 9 (Reorderable Tree View)

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:great_list_view/great_list_view.dart';
import 'package:great_list_view/tree_list_adapter.dart';
import 'package:great_list_view/other_widgets.dart';

void main() {
  buildTree(rnd, root, 5, 3);
  Executor().warmUp();
  runApp(App());
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Test App',
        home: SafeArea(
            child: Scaffold(
          body: Body(),
        )));
  }
}

class Body extends StatefulWidget {
  @override
  _BodyState createState() => _BodyState();
}

class _BodyState extends State<Body> {
  @override
  Widget build(BuildContext context) {
    return AnimatedListView(
      listController: controller,
      itemBuilder: (context, index, data) =>
          itemBuilder(context, adapter, index, data),
      initialItemCount: adapter.count,
      reorderModel: AnimatedListReorderModel(
        onReorderStart: (index, dx, dy) {
          if (adapter.includeRoot && index == 0) return false;
          var node = adapter.indexToNode(index);
          if (!adapter.isLeaf(node) && adapter.isNodeExpanded(node)) {
            // cannot reorder an open node! the long click must first collapse it
            adapter.notifyNodeCollapsing(node, () {
              collapsedMap.add(node);
            }, index: index, updateNode: true);
            return false;
          }
          return true;
        },
        onReorderFeedback: (fromIndex, toIndex, offset, dx, dy) {
          var level =
              adapter.levelOf(adapter.indexToNode(fromIndex)) + dx ~/ 15.0;
          var levels = adapter.getPossibleLevelsOfMove(fromIndex, toIndex);
          return level.clamp(levels.from, levels.to - 1);
        },
        onReorderMove: (fromIndex, toIndex) {
          return !adapter.includeRoot || toIndex != 0;
        },
        onReorderComplete: (fromIndex, toIndex, slot) {
          var levels = adapter.getPossibleLevelsOfMove(fromIndex, toIndex);
          if (!levels.isIn(slot as int)) return false;
          adapter.notifyNodeMoving(
            fromIndex,
            toIndex,
            slot,
            (pNode, node) => pNode.children.remove(node),
            (pNode, node, pos) => pNode.add(node, pos),
            updateParentNodes: true,
          );
          return true;
        },
      ),
    );
  }
}

class NodeData {
  final String text;
  List<NodeData> children = [];
  NodeData? parent;

  NodeData(this.text);

  void add(NodeData n, [int? index]) {
    (index == null) ? children.add(n) : children.insert(index, n);
    n.parent = this;
  }

  @override
  String toString() => text;
}

class TreeNode extends StatelessWidget {
  final NodeData node;
  final int level;
  final bool? expanded;
  final void Function(bool expanded) onExpandCollapseTap;
  final void Function() onRemoveTap;
  final void Function() onInsertTap;
  TreeNode({
    Key? key,
    required this.node,
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
        duration: const Duration(milliseconds: 250),
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
        onTap: onExpandCollapseTap);
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

Widget itemBuilder(BuildContext context, TreeListAdapter<NodeData> adapter,
    int index, AnimatedWidgetBuilderData data) {
  final node = adapter.indexToNode(index);
  return TreeNode(
    node: node,
    level: (data.dragging && data.slot != null)
        ? data.slot as int
        : adapter.levelOf(node),
    expanded: adapter.isLeaf(node) ? null : adapter.isNodeExpanded(node),
    onExpandCollapseTap: (expanded) {
      if (expanded) {
        adapter.notifyNodeExpanding(node, () {
          collapsedMap.remove(node);
        }, updateNode: true);
      } else {
        adapter.notifyNodeCollapsing(node, () {
          collapsedMap.add(node);
        }, updateNode: true);
      }
    },
    onRemoveTap: () {
      adapter.notifyNodeRemoving(node, () {
        node.parent!.children.remove(node);
      }, updateParentNode: true);
    },
    onInsertTap: () {
      var newTree = NodeData(kNames[rnd.nextInt(kNames.length)]);
      adapter.notifyNodeInserting(newTree, node, 0, () {
        node.add(newTree, 0);
      }, updateParentNode: true);
    },
  );
}

void buildTree(Random r, NodeData node, int maxChildren, [int? startWith]) {
  var n = startWith ?? (maxChildren > 0 ? r.nextInt(maxChildren) : 0);
  if (n == 0) return;
  for (var i = 0; i < n; i++) {
    var child = NodeData(kNames[r.nextInt(kNames.length)]);
    buildTree(r, child, maxChildren - 1);
    node.add(child);
  }
}

TreeListAdapter<NodeData> adapter = TreeListAdapter<NodeData>(
  childAt: (node, index) => node.children[index],
  childrenCount: (node) => node.children.length,
  parentOf: (node) => node.parent!,
  indexOfChild: (parent, node) => parent.children.indexOf(node),
  isNodeExpanded: (node) => !collapsedMap.contains(node),
  includeRoot: true,
  root: root,
  controller: controller,
  builder: itemBuilder,
);

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

final root = NodeData('Me');
final rnd = Random();
final collapsedMap = <NodeData>{};
final controller = AnimatedListController();
```

## Additional useful methods

The `AnimatedListController` object provides other useful methods for obtaining information about the placement of the items.

Another useful method is `computeItemBox` which allows you to retrieve the box (position and size) of an item. This method is often used in conjunction with the `jumpTo` and` animateTo` methods of a `ScrollController` to scroll to a certain item.

It is also possible to position at a certain scroll offset when the list view is built for the first time using
the `initialScrollOffsetCallback` attribute of the `AnimatedSliverChildDelegate`, `AnimatedListView` and `AutomaticAnimatedListView` classes; a callback function has to be passed that is invoked at the first layout of the list view, and it has to return the offset to be positioned at the beginning.

### Example 10 (Scroll To Index)

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  Executor().warmUp();
  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Test App',
        home: SafeArea(
            child: Scaffold(
          body: Body(),
        )));
  }
}

class Body extends StatelessWidget {
  Body({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      child: AutomaticAnimatedListView<ItemData>(
        list: myList,
        listController: controller,
        comparator: AnimatedListDiffListComparator<ItemData>(
            sameItem: (a, b) => a.id == b.id,
            sameContent: (a, b) =>
                a.color == b.color && a.fixedHeight == b.fixedHeight),
        itemBuilder: (context, item, data) => data.measuring
            ? Container(
                margin: EdgeInsets.all(5), height: item.fixedHeight ?? 60)
            : Item(data: item),
        initialScrollOffsetCallback: (c) {
          final i = rnd.nextInt(myList.length);
          final box = controller.computeItemBox(i, true)!;
          print('scrolled to item ${myList[i]}');
          return max(
              0.0, box.top - (c.viewportMainAxisExtent - box.height) / 2.0);
        },
        scrollController: scrollController,
      ),
    );
  }
}

final rnd = Random();

class Item extends StatelessWidget {
  final ItemData data;

  const Item({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () {
          final listIndex = rnd.nextInt(myList.length);
          final box = controller.computeItemBox(listIndex, true);
          if (box == null) return;
          print('scrolled to item ${myList[listIndex]}');
          final c = context
              .findAncestorRenderObjectOfType<RenderSliver>()!
              .constraints;
          final r = box.top - (c.viewportMainAxisExtent - box.height) / 2.0;
          scrollController.animateTo(r,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeIn);
        },
        child: AnimatedContainer(
            height: data.fixedHeight ?? 60,
            duration: const Duration(milliseconds: 500),
            margin: EdgeInsets.all(5),
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: data.color,
                border: Border.all(color: Colors.black12, width: 0)),
            child: Center(
                child: Text(
              'Item ${data.id}',
              style: TextStyle(fontSize: 16),
            ))));
  }
}

class ItemData {
  final int id;
  final Color color;
  final double? fixedHeight;
  const ItemData(this.id, [this.color = Colors.blue, this.fixedHeight]);
  @override
  String toString() => '$id';
}

int n = 0;

List<ItemData> myList = [
  for (n = 1; n <= 10; n++) ItemData(n, Colors.blue, 60),
  for (; n <= 20; n++) ItemData(n, Colors.orange, 80),
  for (; n <= 30; n++) ItemData(n, Colors.yellow, 50),
  for (; n <= 40; n++) ItemData(n, Colors.red, 120),
];

final scrollController = ScrollController();
final controller = AnimatedListController();
```

<b>
Anyone who likes this library can support me by making a donation at will. This will definitely motivate me and push me to bring this library to its completion. I will greatly appreciate your contribution.
</b>

[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/donate?hosted_button_id=EJLUKSHKXMTNQ)
