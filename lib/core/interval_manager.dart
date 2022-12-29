part of 'core.dart';

class _IntervalManager with TickerProviderMixin {
  var _disposed = false;

  // This allows to communicate with the child manager.
  final _ListIntervalInterface interface;

  /// Any updates that the child manager has to take into account in the next rebuild
  /// via the [AnimatedSliverMultiBoxAdaptorElement.performRebuild] method.
  final updates = List<_Update>.empty(growable: true);

  /// All animations attached to its intervals.
  final animations = <_ControlledAnimation>{};

  final List<_PopUpList> _listOfPopUps = [];
  List<_PopUpList> get listOfPopUps => List.unmodifiable(_listOfPopUps);

  late _IntervalList list;

  _IntervalManager(this.interface) {
    final initialCount = interface.delegate.initialChildCount;
    list = _IntervalList.normal(this, initialCount);
  }

  /// The [AnimatedListAnimator] instance taken from the [AnimatedSliverChildDelegate].
  AnimatedListAnimator get animator => interface.delegate.animator;

  /// Returns `true` if there are pending updates.
  bool get hasPendingUpdates => updates.isNotEmpty;

  //

  _MovingPopUpList _addMovingPopUpList([_MovingPopUpList? prevPopUpList]) {
    assert(debugAssertNotDisposed());
    final popUpList = _MovingPopUpList();
    if (prevPopUpList == null) {
      _listOfPopUps.add(popUpList);
    } else {
      _listOfPopUps.insert(listOfPopUps.indexOf(prevPopUpList), popUpList);
    }
    return popUpList;
  }

  _ReorderPopUpList _addReorderPopUpList(_IntervalList list) {
    assert(debugAssertNotDisposed());
    final popUpList = _ReorderPopUpList(list);
    assert(listOfPopUps.isEmpty || listOfPopUps.first is! _ReorderPopUpList);
    _listOfPopUps.insert(0, popUpList);
    return popUpList;
  }

  void onResizeTick(_AnimatedSpaceInterval interval, double delta) {
    interface.resizingIntervalUpdated(interval, delta);
  }

  void onMovingTick() {
    interface.markNeedsLayout();
  }

  // --------------------

  // This interval list has notified that a range of the underlying list has been replaced.
  void notifyReplacedRange(int from, int removeCount, int insertCount,
      AnimatedWidgetBuilder? removeItemBuilder) {
    assert(debugAssertNotDisposed());
    assert(removeCount == 0 || removeItemBuilder != null);
    if (!(from >= 0 &&
        removeCount >= 0 &&
        insertCount >= 0 &&
        from + removeCount <= list.itemCount)) {
      throw Exception('Out of range');
    }

    if (removeCount == 0 && insertCount == 0) return;

    _dbgBegin(
        'notifyReplacedRange( from=$from, rem=$removeCount, ins=$insertCount )');
    _dbgPrint('$this');

    if (list.isEmpty) {
      list.newContent(insertCount);
      return;
    }

    list.distributeNotification(
      from,
      removeCount,
      insertCount,
      removeItemBuilder,
      0,
      onReplaceNotification,
    );

    checkMainListChanged();

    _dbgPrint('$this');
    _dbgPrint('$updates');
    _dbgEnd();
  }

  // This interval list has notified that a range of the underlying list has been changed.
  void notifyChangedRange(
      int from, int count, AnimatedWidgetBuilder changeItemBuilder) {
    assert(debugAssertNotDisposed());
    if (!(from >= 0 && count >= 0 && from + count <= list.itemCount)) {
      throw Exception('Out of range');
    }

    _dbgBegin('notifyChangedRange( from=$from, count=$count )');
    _dbgPrint('$this');

    list.distributeNotification(
        from, count, count, changeItemBuilder, 0, onChangeNotification);

    checkMainListChanged();

    _dbgPrint('$this');
    _dbgPrint('$updates');
    _dbgEnd();
  }

  // This interval list has notified that a range of the underlying list has been moved.
  void notifyMovedRange(int from, int count, int to) {
    assert(debugAssertNotDisposed());
    if (!(from >= 0 &&
        count >= 0 &&
        from + count <= list.itemCount &&
        to <= list.itemCount - count)) {
      throw Exception('Out of range');
    }

    if (count == 0 || from == to) return;

    _dbgBegin('notifyMovedRange( from=$from, count=$count, newIndex=$to )');
    _dbgPrint('$this');

    final bundle = _MoveBundle(list);
    list.distributeNotification(
        from, count, count, null, 0, onMoveNotificationPick,
        params: bundle);
    list.distributeNotification(
      to,
      0,
      1, // symbolical
      null,
      0,
      _onMoveNotificationDrop,
      params: (bundle..flush()).execute(),
    );

    checkMainListChanged();

    _dbgPrint('$this');
    _dbgPrint('$updates');
    _dbgEnd();
  }

  // --------------------

  /// It transforms the interval affected by a replacement notification.
  void onReplaceNotification(
      _Interval interval,
      _IntervalList list,
      int removeCount,
      int insertCount,
      int leading,
      int trailing,
      AnimatedWidgetBuilder? offListItemBuilder,
      int offListItemBuilderOffset,
      Object? _) {
    if (removeCount == 0 && insertCount == 0) return;

    if (interval is _AdjustableInterval) {
      final newItemCount = interval.itemCount - removeCount + insertCount;
      if (newItemCount == 0 && interval.buildCount == 0) {
        list.remove(interval.iterable());
      } else {
        final newInterval = interval.clone(newItemCount);
        list.replace(interval.iterable(), newInterval.iterable());
      }
    } else if (interval is _ResizableInterval) {
      list.replace(
          interval.iterable(),
          _ReadyToNewResizingInterval(
                  interval.itemCount - removeCount + insertCount,
                  interval.currentSize.toExactMeasure(),
                  interval.averageCount)
              .iterable());
    } else {
      if (leading == 0 && trailing == interval.itemCount) {
        assert(removeCount == 0 && insertCount > 0);
        list.insertBefore(
            interval, _ReadyToResizingSpawnedInterval(insertCount).iterable());
      } else if (trailing == 0 && leading == interval.itemCount) {
        assert(removeCount == 0 && insertCount > 0);
        list.insertAfter(
            interval, _ReadyToResizingSpawnedInterval(insertCount).iterable());
      } else if (interval is _SubListInterval) {
        interval.subList.distributeNotification(
            leading,
            removeCount,
            insertCount,
            offListItemBuilder,
            offListItemBuilderOffset,
            onReplaceNotification);
        if (interval is _ReorderHolderInterval) {
          assert(removeCount == 1);
          interface.reorderCancel();
        }
      } else if (interval is _NormalInterval) {
        late _Interval middle;
        if (removeCount > 0) {
          middle = _ReadyToRemovalInterval(
              interval.animation,
              _offListBuilder(offListItemBuilder, offListItemBuilderOffset)!,
              removeCount,
              insertCount);
        } else {
          middle = _ReadyToResizingSpawnedInterval(insertCount);
        }
        final result = interval.splitWith(
            leading, trailing, middle.iterable(), _alwaysUpdateCallback);
        performSplit(interval, result);
      } else if (interval is _ReadyToChangingInterval) {
        _Interval middle;
        if (removeCount > 0) {
          middle = _ReadyToRemovalInterval(
              interval.animation,
              offsetIntervalBuilder(interval.builder, leading)!,
              removeCount,
              insertCount);
        } else {
          middle = _ReadyToResizingSpawnedInterval(insertCount);
        }
        final result = interval.splitWith(
            leading, trailing, middle.iterable(), _alwaysUpdateCallback);
        performSplit(interval, result);
      } else {
        throw Exception(
            'The interval $interval was not handled in distribution of replacements');
      }
    }
  }

  /// It transforms the interval affected by a change notification.
  void onChangeNotification(
      _Interval interval,
      _IntervalList list,
      int changeCount,
      int _,
      int leading,
      int trailing,
      AnimatedWidgetBuilder? offListItemBuilder,
      int offListItemBuilderOffset,
      Object? __) {
    if (changeCount == 0) return;

    assert(interval.itemCount > 0);

    if (interval is _NormalInterval) {
      late _Interval middle;
      middle = _ReadyToChangingInterval(
          interval.animation,
          _offListBuilder(offListItemBuilder, offListItemBuilderOffset)!,
          changeCount);
      final result = interval.splitWith(
          leading, trailing, middle.iterable(), _alwaysUpdateCallback);
      performSplit(interval, result);
    } else if (interval is _ReadyToChangingInterval) {
      // already marked to be changed
    } else if (interval is _AdjustableInterval) {
      list.replace(
          interval.iterable(), interval.clone(interval.itemCount).iterable());
    } else if (interval is _ResizableInterval) {
      list.replace(
          interval.iterable(),
          _ReadyToNewResizingInterval(interval.itemCount,
                  interval.currentSize.toExactMeasure(), interval.averageCount)
              .iterable());
    } else if (interval is _SubListInterval) {
      assert(interval is! _WithDropInterval);
      interval.subList.distributeNotification(leading, changeCount, changeCount,
          offListItemBuilder, offListItemBuilderOffset, onChangeNotification);
    } else if (interval is _ReorderHolderInterval) {
      var subList = reorderLayoutData!.openingInterval.subList;
      subList.distributeNotification(leading, changeCount, changeCount,
          offListItemBuilder, offListItemBuilderOffset, onChangeNotification);
    } else {
      throw Exception(
          'The interval $interval was not handled in distribution of changes');
    }
  }

  void onMoveNotificationPick(
      _Interval interval,
      _IntervalList list,
      int count,
      int _,
      int leading,
      int trailing,
      AnimatedWidgetBuilder? offListItemBuilder,
      int offListItemBuilderOffset,
      Object? _bundle) {
    assert(_ == count);

    var bundle = _bundle as _MoveBundle;
    if (count == 0) {
      bundle.flush();
      return;
    }

    if (interval is _DropInterval) {
      bundle.addDropInterval(interval, leading, trailing);
    } else if (interval is _MovingInterval) {
      bundle.addMovingInterval(interval, leading, trailing);
    } else if (interval is _ReorderHolderInterval) {
      bundle.addReoderHolderInterval(interval);
    } else {
      final result = interval.split(leading, trailing);
      performSplit(interval, result);
      bundle.add(result.middle!);
    }
  }

  void _onMoveNotificationDrop(
      _Interval interval,
      _IntervalList list,
      int _,
      int __,
      int leading,
      int trailing,
      AnimatedWidgetBuilder? offListItemBuilder,
      int offListItemBuilderOffset,
      Object? _bundle) {
    // assert(list.debugDirtyConsistency());
    assert(_ == 0 && __ == 1);

    var dropIntervals = _bundle as List<_Interval>;

    assert(dropIntervals.buildCount == 0);

    if (leading == 0 && trailing == interval.itemCount) {
      list.insertBefore(interval, dropIntervals,
          updateCallback: _alwaysUpdateCallback);
    } else if (trailing == 0 && leading == interval.itemCount) {
      list.insertAfter(interval, dropIntervals,
          updateCallback: _alwaysUpdateCallback);
    } else if (interval is _DropInterval) {
      final result = interval.withDropInterval.dropSplit(leading, trailing);
      performSplit(interval.withDropInterval, result);
      list.replace(
          interval.iterable(),
          (_SplitResult? r, Iterable<_Interval> d) sync* {
            if (r?.left != null) {
              yield (result.left!.first as _WithDropInterval).dropInterval;
            }
            yield* d;
            if (r?.right != null) {
              yield (result.right!.first as _WithDropInterval).dropInterval;
            }
          }(result, dropIntervals));
      // } else if (interval is MovingInterval) {
      //   final result = interval.splitWith(
      //       leading, trailing, dropIntervals, alwaysUpdateCallback);
      //   performSplit(interval, result);
    } else {
      final result = interval.splitWith(
          leading, trailing, dropIntervals, _alwaysUpdateCallback);
      performSplit(interval, result);
    }
  }

  //

  /// It converts the builder passed in [notifyReplacedRange] or [notifyChangedRange] in an
  /// interval builder with the specified [offset].
  _IntervalBuilder? _offListBuilder(final AnimatedWidgetBuilder? builder,
      [final int offset = 0]) {
    assert(offset >= 0);
    if (builder == null) return null;
    return (context, index, data) =>
        interface.wrapWidget(builder, index + offset, data, false);
  }

  void _alwaysUpdateCallback(
      _IntervalList list, int index, int oldBuildCount, int newBuildCount) {
    addUpdate(index, oldBuildCount, newBuildCount, popUpList: list.popUpList);
  }

  void performSplit(_Interval i, _SplitResult r) {
    i.list!.replace(
      i.iterable(),
      (_SplitResult r) sync* {
        if (r.left != null) yield* r.left!;
        if (r.middle != null) yield* r.middle!;
        if (r.right != null) yield* r.right!;
      }(r),
      updateCallback: (list, index, oldBuildCount, newBuildCount) {
        r.updateCallback?.call(list, index, oldBuildCount, newBuildCount);
      },
      intermediateCallback: r.subListSplitCallback,
    );
  }

  Iterable<_Interval> get allIntervals =>
      list.followedBy(subIntervalLists.expand((e) => e));

  bool _postponed = false;

  Iterable<_IntervalList> get subIntervalLists =>
      list.whereType<_SubListHolderInterval>().map((e) => e.subList);

  void checkMainListChanged() {
    subIntervalLists.where((l) => l.changed).forEach((l) => onListChanged(l));
    if (list.changed) onListChanged(list);
    assert(debugConsistency());
  }

  void onListChanged(_IntervalList list) {
    optimize(list);

    if (list.holder != null) {
      if (list.isEmpty) {
        final holder = list.holder;
        if (holder is _ReadyToMoveInterval) {
          assert(holder.itemCount == 0 && holder.buildCount == 0);
          holder.list!.changed = true;
          holder.dropInterval._remove();
          holder._remove();
        } else if (holder is _MovingInterval) {
          assert(holder.itemCount == 0);
          holder.list!.changed = true;
          _listOfPopUps.remove(holder.popUpList);
          holder._remove();
        }
      }
    }

    list.changed = false;
  }

  /// It transforms some or all ready-to intervals into a new type of intervals.
  void coordinate() {
    _dbgBegin('coordinate()');
    _dbgPrint('$this');

    _coordinate();

    checkMainListChanged();

    _dbgPrint('$this');
    _dbgEnd();
  }

  void _coordinate() {
    allIntervals
        .whereType<_ReadyToResizing>()
        .where((e) => !e.isMeasured && !e.isMeasuring) // && e.isReadyToMeasure)
        .forEach((interval) {
      final f = interval.startMeasuring(interface);
      if (f is Future<bool>) {
        f.then((v) {
          if (v) coordinate();
        });
      }
    });

    if (!list
        .whereType<_MovingInterval>()
        .any((i) => !i.areAnimationsCompleted)) {
      _unpackCompletedDrop();
    }

    _readyToRemoveToRemoval();

    if (list
        .whereType<_RemovalInterval>()
        .any((i) => !i.areAnimationsCompleted)) {
      return;
    }

    if (list.whereType<_ReadyToResizing>().any((i) => i.isMeasuring)) {
      return;
    }

    _readyToChangeToNormal();

    _readyToResizeToResizing();

    if (_moveit) _readyToMoveToMove();

    if (list
            .whereType<_ResizingInterval>()
            .any((i) => !i.areAnimationsCompleted) ||
        list
            .whereType<_MovingInterval>()
            .any((i) => !i.areAnimationsCompleted)) {
      return;
    }

    _readyToInsertToInsert();
  }

  void _readyToRemoveToRemoval() {
    var rem = allIntervals.whereType<_ReadyToRemovalInterval>();
    if (rem.isNotEmpty) {
      rem.toList().forEach((interval) {
        final animation = interval.isWaitingAtEnd
            ? _createAnimation(animator.dismiss())
            : _createAnimation(
                animator.dismissDuringIncoming(interval.animation.time));
        final newInterval = _RemovalInterval(animation, interval.builder,
            interval.buildCount, interval.itemCount);
        _dbgPrint('->Rm => Rm {$interval}, {$newInterval}');
        interval.list!.replace(interval.iterable(), newInterval.iterable(),
            updateCallback: _alwaysUpdateCallback);
        newInterval.startAnimation();
      });
    }
  }

  void _readyToChangeToNormal() {
    var chg = allIntervals
        .whereType<_ReadyToChangingInterval>()
        .where((e) => e.list!.popUpList == null);
    if (chg.isNotEmpty) {
      chg.toList().forEach((interval) {
        _freezeDropPopUp(interval);
        final newInterval =
            _NormalInterval(interval.animation, interval.itemCount);
        _dbgPrint('->Ch => Nm {$interval}, {$newInterval}');
        interval.list!.replace(interval.iterable(), newInterval.iterable(),
            updateCallback: _alwaysUpdateCallback);
      });
    }
  }

  // TODO: to be rewritten!
  void _freezeDropPopUp(_Interval interval) {
    // se un intervallo di una popup si trasforma in un ResizingInterval, la sua dimensione cambia, e quindi
    // se la popup è in movimento, ovvero appartiene a un Mv, quest'ultimo si dovrà trasformare
    // in un ReadyToMoveSplitInterval e la popup si dovrà fermare in attesa di ricalcolo delle proprie
    // dimensioni e offset finale su cui poggiarsi
    // final dis = list
    //     .whereType<MovingInterval>()
    //     .where((di) => di.popUpList.subLists.single.contains(interval));
    // for (final di in dis) {
    if (interval.list?.holder is _MovingInterval) {
      final di = interval.list?.holder as _MovingInterval;
      final i = _ReadyToPopupMoveInterval(di.popUpList.subLists.single,
          di.popUpList, di.averageCount, di.currentSize);
      list.replace(di.iterable(), () sync* {
        yield i;
        yield i.dropInterval;
      }());
    }
  }

  void _readyToResizeToResizing() {
    var res = allIntervals.whereType<_ReadyToResizing>();
    if (res.isNotEmpty) {
      res.where((e) => e.isMeasured).toList().forEach((interval) {
        // TODO: does not work, because it does not take into condideration the final height of the item changed for
        // because of the animation that deals with the changing
        _freezeDropPopUp(interval);
        final newInterval = _ResizingInterval(
            _createAnimation(animator.resizing(
                interval.fromSize!.value, interval.toSize!.value)),
            interval.fromSize!,
            interval.toSize!,
            interval.fromLength,
            interval.itemCount);
        _dbgPrint('->Rz => Rz {$interval}, {$newInterval}');
        interval.list!.replace(interval.iterable(), newInterval.iterable(),
            updateCallback: (_IntervalList list, int index, int oldBuildCount,
                int newBuildCount) {
          addUpdate(index, oldBuildCount, newBuildCount,
              popUpList: list.popUpList,
              flags: _UpdateFlags(_UpdateFlags.DISCARD_ELEMENT |
                  _UpdateFlags.CLEAR_LAYOUT_OFFSET |
                  (interval.fromSize!.estimated
                      ? 0
                      : _UpdateFlags.KEEP_FIRST_LAYOUT_OFFSET)));
        });
        newInterval.startAnimation();
      });
    }
  }

  void _readyToInsertToInsert() {
    var ins = allIntervals.whereType<_ReadyToInsertionInterval>();
    if (ins.isNotEmpty) {
      ins.toList().forEach((interval) {
        final newInterval = _NormalInterval(
            _createAnimation(animator.incoming()), interval.itemCount);
        _dbgPrint('->In => Nm {$interval}, {$newInterval}');
        interval.list!.replace(interval.iterable(), newInterval.iterable(),
            updateCallback: (_IntervalList list, int index, int oldBuildCount,
                int newBuildCount) {
          addUpdate(index, oldBuildCount, newBuildCount,
              popUpList: list.popUpList,
              flags: _UpdateFlags(_UpdateFlags.DISCARD_ELEMENT |
                  _UpdateFlags.CLEAR_LAYOUT_OFFSET |
                  (interval.size.estimated
                      ? 0
                      : _UpdateFlags.KEEP_FIRST_LAYOUT_OFFSET)));
        });
        newInterval.startAnimation();
      });
    }
  }

  void _readyToMoveToMove() {
    final toMoveIntervals = allIntervals.whereType<_WithDropInterval>();
    if (toMoveIntervals.isNotEmpty) {
      void fn() {
        // assert(_debugConsistency());

        var popUpListToRemove = <_PopUpList>{};

        void transformIntervals(
          _WithDropInterval r2mi,
          _Measure fromStart,
          _Measure fromSize,
          _Measure fromBoxSize,
          _ControlledAnimation resizeAnim,
          _ControlledAnimation moveAnim,
          _Measure toSize,
          _Measure toOffset,
          _MovingPopUpList? oldPopUp,
        ) {
          // assert(_debugConsistency());

          var toIndex = r2mi.dropInterval.itemOffset;
          if (r2mi.itemOffset < toIndex) {
            toIndex -= r2mi.itemCount;
          }

          final movingInterval = _MovingInterval(
              resizeAnim,
              moveAnim,
              r2mi.subList,
              _addMovingPopUpList(oldPopUp),
              toSize,
              fromStart.value);

          final resizeInterval = _ResizingInterval(
            _createAnimation(animator.resizing(fromSize.value, 0.0)),
            fromBoxSize,
            _Measure.zero,
            r2mi.averageCount,
            0,
          );
          final list = r2mi.list!;
          _dbgPrint('->Mv => Mv {${r2mi.dropInterval}}, {$movingInterval}');
          list.replace(r2mi.dropInterval.iterable(), movingInterval.iterable(),
              updateCallback: _alwaysUpdateCallback);
          list.replace(r2mi.iterable(), resizeInterval.iterable(),
              updateCallback: (_IntervalList list, int index, int oldBuildCount,
                  int newBuildCount) {
            if (r2mi is _ReadyToPopupMoveInterval) {
              addUpdate(index, oldBuildCount, newBuildCount); // resize box
              final count = r2mi.subList.buildCount;
              addUpdate(r2mi.popUpList.buildIndexOf(r2mi.subList), count, count,
                  popUpList: r2mi.popUpList,
                  toPopUpList: movingInterval.popUpList,
                  flags: _UpdateFlags(_UpdateFlags.POPUP_PICK));
            } else {
              addUpdate(index, oldBuildCount, newBuildCount,
                  toPopUpList: movingInterval.popUpList,
                  flags: _UpdateFlags(_UpdateFlags.POPUP_PICK));
            }
          });
          resizeInterval.startAnimation();
          movingInterval.startAnimation();

          if (oldPopUp != null) {
            // _listOfPopUps.remove(oldPopUp);
            popUpListToRemove.add(oldPopUp);
          }

          // assert(_debugConsistency());
        } // fn()

        final callbacks = toMoveIntervals.toList().map<void Function()>((r2mi) {
          _MovingPopUpList? oldPopUp;
          _Measure fromStart, fromEnd, fromSize, fromBoxSize;
          if (r2mi is _ReadyToPopupMoveInterval) {
            oldPopUp = r2mi.popUpList;
            final i = r2mi.popUpList.buildIndexOf(r2mi.subList);
            fromStart = interface.estimateLayoutOffset(
                i, r2mi.popUpList.popUpBuildCount,
                popUpList: r2mi.popUpList);
            fromEnd = interface.estimateLayoutOffset(
                i + r2mi.subList.buildCount, r2mi.popUpList.popUpBuildCount,
                popUpList: r2mi.popUpList);

            fromSize = fromEnd - fromStart;

            if (fromSize.value > 50 && fromSize.value < 70 && i == 1) {
              fromStart = interface.estimateLayoutOffset(
                  i, r2mi.popUpList.popUpBuildCount,
                  popUpList: r2mi.popUpList);
              fromEnd = interface.estimateLayoutOffset(
                  i + r2mi.subList.buildCount, r2mi.popUpList.popUpBuildCount,
                  popUpList: r2mi.popUpList);
            }

            fromBoxSize = _Measure(r2mi.currentSize);
          } else {
            fromStart = interface.estimateLayoutOffset(
                r2mi.buildOffset, list.buildCount);
            fromEnd = interface.estimateLayoutOffset(
                r2mi.buildOffset + r2mi.buildCount, list.buildCount);
            fromSize = fromEnd - fromStart;
            fromBoxSize = fromSize;
          }

          // ottimizzazione: se sono tutti ReadyToResizingSpawnedInterval, è inuile creare la popup
          // con soli box ridimenzionabili invisibili, tanto vale metterli direttamente a destinazione
          if (!r2mi.subList.any((e) => e is! _ReadyToResizingSpawnedInterval)) {
            return () {
              final list = r2mi.list!;
              var toIndex = r2mi.dropInterval.itemOffset;
              if (r2mi.itemOffset < toIndex) {
                toIndex -= r2mi.itemCount;
              }
              // movedArray.listMove(r2mi.itemOffset, r2mi.itemCount, toIndex);
              Iterable<_Interval> newList;
              _ResizingInterval? resizeInterval;
              if (r2mi is _ReadyToPopupMoveInterval) {
                resizeInterval = _ResizingInterval(
                  _createAnimation(animator.resizing(r2mi.currentSize, 0.0)),
                  r2mi.currentSize.toExactMeasure(),
                  _Measure.zero,
                  r2mi.averageCount,
                  0,
                );
                newList = resizeInterval.iterable();
              } else {
                newList = const [];
              }
              list.replace(r2mi.iterable(), newList,
                  updateCallback: _alwaysUpdateCallback);
              // note: no callback, because buildCounts are always zero
              list.replace(r2mi.dropInterval.iterable(), r2mi.subList);
              resizeInterval?.startAnimation();
            };
          }

          final moveAnim = _createAnimation(animator.moving());
          final toSize = math
              .max(
                  0.0,
                  (fromSize.value +
                      r2mi.futureDeltaSize(moveAnim.durationInSec)))
              .toExactMeasure();

          final resizeAnim =
              _createAnimation(animator.resizing(0.0, toSize.value));

          final maxDuration = math.max<double>(
              resizeAnim.durationInSec, moveAnim.durationInSec);

          // print("!!! $list --- ${list._leftMostDirtyInterval}");
          var toOffset = interface.estimateLayoutOffset(
              r2mi.dropInterval.buildOffset, list.buildCount,
              time: maxDuration);

          return () => transformIntervals(
              r2mi,
              fromStart,
              fromSize,
              fromBoxSize,
              resizeAnim,
              moveAnim,
              // futureDeltaSize,
              toSize,
              toOffset,
              oldPopUp);
        }).toList();

        callbacks.forEach((e) => e.call());

        popUpListToRemove.forEach((pl) => _listOfPopUps.remove(pl));
      } // fn()

      if (updates.isNotEmpty) {
        if (!_postponed) {
          _postponed = true;

          _dbgPrint('scheduling _readyToMoveToDrop at next frame');

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _postponed = false;

            _dbgBegin('_readyToMoveToDrop postponed');

            _dbgPrint('$this');

            assert(updates.isEmpty);

            fn();

            _dbgPrint('$this');
            _dbgEnd();
          });
        }
      } else {
        fn();
      }
    }
  }

  void _unpackCompletedDrop() {
    allIntervals
        .whereType<_MovingInterval>()
        .where((i) => i.areAnimationsCompleted)
        .toList()
        .forEach((i) {
      _dbgPrint('Mv finished {$i}');
      i.list!.replace(i.iterable(), i.subList, updateCallback:
          (_IntervalList list, int index, int oldBuildCount,
              int newBuildCount) {
        addUpdate(index, oldBuildCount, newBuildCount,
            popUpList: i.popUpList,
            flags: _UpdateFlags(_UpdateFlags.POPUP_DROP));
      });
      _listOfPopUps.remove(i.popUpList);
    });
  }

  /// This is Called when an [interval] has completed its animation.
  /// It could transform that interval into a new type of interval.
  void onIntervalCompleted(_AnimatedIntervalMixin interval) {
    _dbgBegin('_onIntervalCompleted( $interval )');
    _dbgPrint('$this');

    final list = interval.list!;

    if (interval is _RemovalInterval) {
      list.replace(
          interval.iterable(),
          _ReadyToResizingFromRemovalInterval(
                  interval.builder, interval.buildCount, interval.itemCount)
              .iterable());
    } else if (interval is _ReorderClosingInterval) {
      list.remove(interval.iterable(), updateCallback: _alwaysUpdateCallback);
    } else if (interval is _ResizingInterval) {
      if (interval.toLength > 0) {
        list.replace(
            interval.iterable(),
            _ReadyToInsertionInterval(interval.toSize, interval.itemCount)
                .iterable(),
            updateCallback: _alwaysUpdateCallback);
      } else {
        assert(interval.toSize.value == 0.0);
        list.remove(interval.iterable(), updateCallback: _alwaysUpdateCallback);
      }
    }

    checkMainListChanged();

    _dbgPrint('$this');
    _dbgEnd();
  }

  /// It analyzes if there are intervals that can be merged together in order to optimize this list.
  void optimize(_IntervalList list) {
    if (list.isEmpty) return;

    _Interval? interval = list.first;
    _Interval? oldLeftInterval, leftInterval, nextInterval = interval.next;
    while (interval != null) {
      var mergeResult =
          leftInterval != null ? interval.mergeWith(leftInterval) : null;
      if (mergeResult != null) {
        final mergedIntervals = mergeResult.mergedIntervals;
        assert(mergedIntervals.isNotEmpty);
        final newFirstInterval = mergedIntervals.first;
        list.replace([leftInterval!, interval], mergedIntervals,
            updateCallback: mergeResult.callback);
        leftInterval = oldLeftInterval;
        interval = newFirstInterval;
        // oldLeftInterval = oldLeftInterval?.previous;
        oldLeftInterval = leftInterval?.previous;
      } else {
        oldLeftInterval = leftInterval;
        leftInterval = interval;
        interval = nextInterval;
      }
      nextInterval = interval?.next;
    }
  }

  /// Adds a new [_Update] element in the update list of this list interval or pop-up list.
  /// This methods also instructs the child manager to be rebuilt.
  void addUpdate(int index, int oldBuildCount, int newBuildCount,
      {_UpdateFlags flags = const _UpdateFlags(),
      _PopUpList? popUpList,
      _PopUpList? toPopUpList}) {
    assert(debugAssertNotDisposed());
    if (oldBuildCount == 0 && newBuildCount == 0) return;
    final update = _Update(
        index, oldBuildCount, newBuildCount, flags, popUpList, toPopUpList);
    updates.add(update);
    interface.markNeedsBuild();
  }

  _ControlledAnimation _createAnimation(AnimatedListAnimationData data) {
    assert(debugAssertNotDisposed());
    final animation = _ControlledAnimation(
      this,
      data.animation,
      data.duration,
      startTime: data.startTime,
      onDispose: (a) => animations.remove(a),
    );
    animations.add(animation);
    animation.addListener(() {
      // when the animation is complete it notifies all its linked intervals
      if (animation.intervals.isNotEmpty) {
        animation.intervals.toList().forEach((i) {
          if (i.areAnimationsCompleted && !i.isDisposed && i.list != null) {
            onIntervalCompleted(i);
          }
        });
        coordinate();
      }
    });
    return animation;
  }

  @override
  @mustCallSuper
  void dispose() {
    assert(debugAssertNotDisposed());
    list.whereType<_SubListInterval>().forEach((i) => i.subList.dispose());
    listOfPopUps.clear();
    animations.clear();
    updates.clear();
    list.dispose();
    _disposed = true;
    super.dispose();
  }

  bool debugConsistency() {
    assert(() {
      if (list
          .whereType<_SubListInterval>()
          .any((e) => e.subList.whereType<_SubListInterval>().isNotEmpty)) {
        return false;
      }

      final popUpLists = list
          .whereType<_PopUpInterval>()
          .map<_PopUpList>((e) => e.popUpList)
          .toSet();

      if (!setEquals(popUpLists, listOfPopUps.toSet())) {
        return false;
      }

      return true;
    }());
    return true;
  }

  bool debugAssertNotDisposed() {
    assert(() {
      if (_disposed) {
        throw FlutterError(
          'A $runtimeType was used after being disposed.\n'
          'Once you have called dispose() on a $runtimeType, it can no longer be used.',
        );
      }
      return true;
    }());
    return true;
  }

  //
  // Reordering
  //

  _ReorderLayoutData? reorderLayoutData;

  void reorderStart(_ReorderLayoutData rld, _NormalInterval interval,
      int indexOffset, int itemIndex) {
    assert(debugAssertNotDisposed());
    assert(reorderLayoutData == null);
    reorderLayoutData = rld;

    final popUpList = _addReorderPopUpList(_IntervalList.normal(this, 1));

    final itemSize = rld.itemSize;
    final animation =
        _createAnimation(animator.resizingDuringReordering(itemSize, itemSize))
          ..complete();
    final holder = _ReorderHolderInterval();
    final open = _ReorderOpeningInterval(
        holder, animation, itemSize, itemSize, popUpList, interface);

    final updateIndex = interval.buildOffset + indexOffset;
    final result = interval.splitWith(
        indexOffset, interval.buildCount - indexOffset - 1, () sync* {
      yield holder;
      yield open;
    }(), _alwaysUpdateCallback);
    performSplit(interval, result);
    addUpdate(updateIndex, 1, 1,
        toPopUpList: popUpList, flags: _UpdateFlags(_UpdateFlags.POPUP_PICK));

    reorderLayoutData!.openingInterval = open;
    reorderLayoutData!.currentMainAxisOffset = rld.lastMainAxisOffset;

    assert(debugConsistency());
  }

  void reorderUpdateSlot(Object? newSlot) {
    assert(debugAssertNotDisposed());
    if (reorderLayoutData!.slot == newSlot) return;
    reorderLayoutData!.slot = newSlot;
    final popUpList = reorderLayoutData!.openingInterval.popUpList;
    addUpdate(0, 1, 1, popUpList: popUpList);
  }

  void reorderUpdateDropListIndex(
      _NormalInterval interval, int offset, int newDropIndex) {
    assert(debugAssertNotDisposed());
    if (reorderLayoutData!.dropListIndex == newDropIndex) return;
    final oldOpeningInterval = reorderLayoutData!.openingInterval;

    _reorderUpdateAllClosingIntervals();

    final popUpList = oldOpeningInterval.popUpList;
    final fromSize = oldOpeningInterval.currentSize;
    final closingInterval = _ReorderClosingInterval(
        _createAnimation(animator.resizingDuringReordering(fromSize, 0.0)),
        fromSize);
    final holder = oldOpeningInterval.holder;
    list.replace(oldOpeningInterval.iterable(), closingInterval.iterable(),
        updateCallback: _alwaysUpdateCallback);

    final itemSize = reorderLayoutData!.itemSize;
    final newOpeningInterval = _ReorderOpeningInterval(
        holder,
        _createAnimation(animator.resizingDuringReordering(0.0, itemSize)),
        0,
        itemSize,
        popUpList,
        interface);

    final result = interval.splitWith(offset, interval.buildCount - offset,
        newOpeningInterval.iterable(), _alwaysUpdateCallback);
    performSplit(interval, result);

    reorderLayoutData!.openingInterval = newOpeningInterval;
    assert(reorderLayoutData!.dropListIndex == newDropIndex);

    closingInterval.startAnimation();
    newOpeningInterval.startAnimation();

    assert(debugConsistency());
  }

  void reorderStop(bool cancel) {
    assert(debugAssertNotDisposed());
    final openingInterval = reorderLayoutData!.openingInterval;
    final holder = openingInterval.holder;
    final oldPopUpList = openingInterval.popUpList;
    final newPopUpList = _addMovingPopUpList();

    final animation = cancel
        ? (_createAnimation(
            animator.resizingDuringReordering(0, reorderLayoutData!.itemSize))
          ..start()) // we must animate even the smallest movements!
        : openingInterval.animation;
    final movingInterval = _MovingInterval(
        animation,
        _createAnimation(animator.moving())
          ..start(), // we must animate even the smallest movements!
        oldPopUpList.intervalList,
        newPopUpList,
        reorderLayoutData!.itemSize.toExactMeasure(),
        oldPopUpList.currentScrollOffset!);

    if (cancel) {
      final fromSize = openingInterval.currentSize;
      final closingInterval = _ReorderClosingInterval(
          _createAnimation(animator.resizingDuringReordering(fromSize, 0.0))
            ..start(), // we must animate even the smallest movements!
          fromSize);
      list.replace(openingInterval.iterable(), closingInterval.iterable(),
          updateCallback: _alwaysUpdateCallback);
      list.replace(
        holder.iterable(),
        movingInterval.iterable(),
        updateCallback: (_IntervalList list, int index, int oldBuildCount,
            int newBuildCount) {
          addUpdate(index, oldBuildCount, newBuildCount);
          addUpdate(0, 1, 1,
              popUpList: oldPopUpList,
              toPopUpList: newPopUpList,
              flags: _UpdateFlags(_UpdateFlags.POPUP_PICK));
        },
      );
      // closingInterval.startAnimation();
      _reorderUpdateAllClosingIntervals();
    } else {
      list.replace(openingInterval.iterable(), movingInterval.iterable(),
          updateCallback: (_IntervalList list, int index, int oldBuildCount,
              int newBuildCount) {
        addUpdate(0, 1, 1,
            popUpList: oldPopUpList,
            toPopUpList: newPopUpList,
            flags: _UpdateFlags(_UpdateFlags.POPUP_PICK));
        addUpdate(index, oldBuildCount, newBuildCount);
      });
      list.remove(holder.iterable());
    }

    // movingInterval.startAnimation();

    _listOfPopUps.remove(oldPopUpList);

    reorderLayoutData = null;

    assert(debugConsistency());
  }

  void _reorderUpdateAllClosingIntervals() {
    list.whereType<_ReorderClosingInterval>().forEach((oldClosingInterval) {
      final fromSize = oldClosingInterval.currentSize;
      final newClosingInterval = _ReorderClosingInterval(
          _createAnimation(animator.resizingDuringReordering(fromSize, 0.0))
            ..start(), // we must animate even the smallest movements!
          fromSize);
      list.replace(oldClosingInterval.iterable(), newClosingInterval.iterable(),
          updateCallback: _alwaysUpdateCallback);
      // newClosingInterval.startAnimation();
    });
  }

  // TODO: to be removed!!!!!!
  bool _moveit = true;
  void test() {
    _moveit = !_moveit;
    coordinate();
  }

  @override
  String toString() => list.toString();
}

abstract class _ListIntervalInterface extends BuildContext {
  AnimatedSliverChildDelegate get delegate;
  bool get isHorizontal;
  Widget wrapWidget(
      AnimatedWidgetBuilder builder, int index, AnimatedWidgetBuilderData data,
      [bool map = true]);
  void resizingIntervalUpdated(_AnimatedSpaceInterval interval, double delta);
  Future<_Measure> measureItems(
      _Cancelled? cancelled, int count, IndexedWidgetBuilder builder,
      [double startingSize = 0, int startingCount = 0]);
  double measureItem(Widget widget);
  void markNeedsBuild();
  void markNeedsLayout();
  _SizeResult? getItemSizesFromSliverList(int buildFrom, int buildTo);
  _Measure estimateLayoutOffset(int buildIndex, int childCount,
      {double? time, _MovingPopUpList? popUpList});
  void reorderCancel();
}

class _MoveBundle {
  _MoveBundle(this.list);

  final _IntervalList list;

  List<_Interval> moveList = [];

  final callbacks = <_Interval Function()>[];

  void add(Iterable<_Interval> intervals) {
    // assert(!intervals.any((i) => i is SubListInterval));
    moveList.addAll(intervals);
  }

  void addReoderHolderInterval(_ReorderHolderInterval interval) {
    flush();
    callbacks.add(() {
      return interval;
    });
  }

  void addMovingInterval(_MovingInterval interval, int leading, int trailing) {
    flush();
    callbacks.add(() {
      final result = interval.split(leading, trailing);
      list.manager.performSplit(interval, result);
      assert(result.middle!.single is _ReadyToPopupMoveInterval);
      return (result.middle!.single as _WithDropInterval).dropInterval;
    });
  }

  void addDropInterval(_DropInterval interval, int leading, int trailing) {
    flush();
    callbacks.add(() {
      final result = interval.withDropInterval.dropSplit(leading, trailing);
      list.manager.performSplit(interval.withDropInterval, result);
      final withDropInterval = result.middle!.single as _WithDropInterval;
      list.replace(
          interval.iterable(),
          (_SplitResult r) sync* {
            if (r.left != null) {
              yield (r.left!.first as _WithDropInterval).dropInterval;
            }
            if (r.right != null) {
              yield (r.right!.first as _WithDropInterval).dropInterval;
            }
          }(result));
      return withDropInterval.dropInterval;
    });
  }

  void flush() {
    if (moveList.isEmpty) return;

    final finalMoveList = moveList;
    callbacks.add(() {
      final interval = _ReadyToMoveInterval(_IntervalList(list.manager));
      list.replace(finalMoveList, interval.iterable(),
          outSubList: interval.subList);
      return interval.dropInterval;
    });

    moveList = [];
  }

  List<_Interval> execute() {
    final dropIntervals = <_Interval>[];
    for (final cb in callbacks) {
      dropIntervals.add(cb());
    }
    callbacks.clear();
    return dropIntervals;
  }
}
