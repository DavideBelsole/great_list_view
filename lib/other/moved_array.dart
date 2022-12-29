part of 'dispatcher.dart';

class _MovedReplace {
  final int from, length, count, startOffset;
  final bool? left;

  _MovedReplace(
      this.from, this.length, this.count, this.startOffset, this.left);

  @override
  String toString() {
    return '[from: $from, length: $length, count: $count, startOffset: $startOffset, left: $left]';
  }
}

class _MovedRange {
  int _from, _length;

  _MovedRange(this._from, this._length) : assert(_from >= 0 && _length >= 0);

  // _MovedRange.from(_MovedRange m)
  //     : _from = m._from,
  //       _length = m._length;

  int get from => _from;
  int get length => _length;
  int get to => _from + _length;

  @override
  String toString() {
    return '[$_from-$_length]';
  }
}

class _MovedArray {
  final List<_MovedRange> data;

  _MovedArray(int length)
      : assert(length >= 0),
        data = [_MovedRange(0, length)];

  // _MovedArray.from(_MovedArray m)
  //     : data = [for (var i in m.data) _MovedRange.from(i)];

  int get length => data.fold<int>(0, (pv, n) => pv + n._length);

  int map(int i) {
    var r = 0;
    var o = 0;
    for (final d in data) {
      final no = o + d._length;
      if (i < no) {
        return d._from + i - o;
      }
      o = no;
    }
    return r;
  }

  void dataMove(int from, int len, int to) {
    if (from == to) return;

    late _MovedRange n;
    int j;
    for (j = 0; j < data.length; j++) {
      n = data[j];
      if (from >= n._from && from < n.to) {
        break;
      }
    }
    assert(j < data.length);
    if (from + len > n.to) {
      final l = n.to - from;
      if (to <= from) {
        dataMove(from, l, to);
        dataMove(from + l, len - l, to + l);
      } else {
        dataMove(from + l, len - l, to + l);
        dataMove(from, l, to);
      }
      return;
    }

    void r(int from, int to, int len, bool swap) {
      var changed = false;
      var subList = <_MovedRange>[];

      void build(int from, int len) {
        if (len <= 0) return;
        if (subList.isNotEmpty && subList.last.to == from) {
          subList.last._length += len;
        } else {
          subList.add(_MovedRange(from, len));
        }
      }

      _MovedRange? o;
      var lz = swap ? len : 0;
      for (var j = data.length - 1; j >= 0; j--) {
        var n = data[j];
        if (to < n.to && (from + len - 1) >= n._from) {
          build(n._from, to - n._from);

          final a = n.to - from;
          final b = math.max(to, n._from - lz);

          if (swap) {
            if (to >= n._from && to < n.to) {
              build(from, len);
            }

            build(b, from - b + math.min(0, a - lz));
          } else {
            build(b + len, from - b + math.min(0, a - lz));

            if (from >= n._from && from < n.to) {
              build(to, len);
            }
          }

          build(from + len, a - len);

          assert(subList.isNotEmpty);

          if (o != null && o._from == subList.last.to) {
            final t = data.removeAt(j + 1);
            subList.last._length += t._length;
          }

          data.replaceRange(j, j + 1, subList);
          o = subList.first;
          subList.clear();

          changed = true;
        } else {
          if (changed) {
            if (o != null && o._from == n.to) {
              final t = data.removeAt(j + 1);
              n._length += t._length;
            }
            changed = false;
          }
          o = n;
        }
      }
    }

    if (to <= from) {
      r(from, to, len, false);
    } else {
      r(to, from, len, true);
    }
  }

  List<_MovedReplace> dataReplaceOrChange(int from, int length, int count) {
    assert(length >= 0 && count >= 0);
    var list = SplayTreeMap<int, _MovedReplace>();
    var o = 0;
    final to = from + length;
    _MovedRange? pn;
    for (var j = 0; j < data.length; j++) {
      var n = data[j];
      final leftLength = math.max(0, math.min(length, n.from - from));
      final leftCount =
          (from < n.from && to <= n.from) ? count : math.min(leftLength, count);
      if (from < n.to || (from == n.to && from == this.length)) {
        final innerLength = math.max<int>(
          0,
          math.min(n.to, to) - math.max(n.from, from),
        );
        final remainingCount = count - leftCount;
        final innerCount = (to <= n.to)
            ? remainingCount
            : math.min(innerLength, remainingCount);
        n._length += innerCount - innerLength;

        if (to > n.from || from >= n.from) {
          final f = math.max(0, from - n._from);
          bool? left;
          if (f == 0) {
            left = false;
          } else if (to == n.to) {
            left = false;
          } else {
            left = null;
          }
          list.putIfAbsent(
              n.from,
              () => _MovedReplace(
                  o + f, innerLength, innerCount, leftCount, left));
        }
      }
      o += n._length;
      n._from += leftCount - leftLength;
      if (n._length == 0) {
        data.removeAt(j--);
      } else if (pn != null && pn.to == n._from) {
        pn._length += n._length;
        data.removeAt(j--);
      } else {
        pn = n;
      }
    }
    if (data.isEmpty) data.add(_MovedRange(0, 0));
    return list.values.toList();
  }

  // MovedReplace dataInsertPoint(int from) {
  //   assert(length >= 0);
  //   var o = 0;
  //   final to = from + length;
  //   MovedRange? pn;
  //   for (var j = 0; j < data.length; j++) {
  //     var n = data[j];
  //     final leftLength = math.max(0, math.min(length, n.from - from));
  //     final leftCount =
  //         (from < n.from && to <= n.from) ? count : math.min(leftLength, count);
  //     if (from < n.to || (from == n.to && from == this.length)) {
  //       final innerLength = math.max<int>(
  //         0,
  //         math.min(n.to, to) - math.max(n.from, from),
  //       );
  //       final remainingCount = count - leftCount;
  //       final innerCount = (to <= n.to)
  //           ? remainingCount
  //           : math.min(innerLength, remainingCount);
  //       n._length += innerCount - innerLength;

  //       if (to > n.from || from >= n.from) {
  //         final f = math.max(0, from - n._from);
  //         bool? left;
  //         if (f == 0) {
  //           left = false;
  //         } else if (to == n.to) {
  //           left = false;
  //         } else {
  //           left = null;
  //         }
  //         return MovedReplace(o + f, innerLength, innerCount, leftCount, left));
  //       }
  //     }
  //     o += n._length;
  //     n._from += leftCount - leftLength;
  //     if (n._length == 0) {
  //       data.removeAt(j--);
  //     } else if (pn != null && pn.to == n._from) {
  //       pn._length += n._length;
  //       data.removeAt(j--);
  //     } else {
  //       pn = n;
  //     }
  //   }
  //       throw Exception('this point should never have been reached');
  // }

  void listMove(int from, int len, int to) {
    int r(int from, int len, int to) {
      assert(from != to);

      void shrinkAndOptimize(int index, int amount) {
        if (amount == 0) return;

        final n = data[index];
        assert(n._length >= amount);
        n._from += amount;
        n._length -= amount;
        if (n._length == 0) {
          data.removeAt(index);
          if (index > 0 && index < data.length) {
            final p = data[index - 1];
            final s = data[index];
            if (p.from + p.length == s.from) {
              p._length += s.length;
              data.removeAt(index);
            }
          }
        }
      }

      void insertAndOptimize(int index, int from, int len) {
        if (len == 0) return;

        late _MovedRange b;
        if (index == data.length) {
          b = _MovedRange(from, len);
          data.add(b);
        } else {
          b = data[index];
          if (from + len == b._from) {
            b._from = from;
            b._length += len;
          } else {
            b = _MovedRange(from, len);
            data.insert(index, b);
          }
        }

        if (index > 0) {
          final p = data[index - 1];
          if (p._from + p._length == b._from) {
            b._from = p._from;
            b._length += p._length;
            data.removeAt(index - 1);
          }
        }
      }

      late int newFrom;
      for (var i = 0, o = 0; i < data.length; i++) {
        final d = data[i];
        var dl = d.length;
        if (from < o + dl) {
          final nl = from - o;
          if (d.length - nl < len) {
            final nlen = d.length - nl;
            if (from < to) {
              to += len - nlen;
            }
            len = nlen;
          }
          newFrom = d.from + nl;
          if (nl > 0) {
            data.insert(i++, _MovedRange(d.from, nl));
          }
          shrinkAndOptimize(i, nl + len);
          break;
        }
        o += dl;
      }

      void f(int j, _MovedRange m, int i) {
        if (j > 0) {
          i++;
          if (m.length >= j) {
            data.insert(i - 1, _MovedRange(m.from, j));
            m._from += j;
            m._length -= j;
            if (m.length == 0) {
              data.removeAt(i);
            }
          }
        }
        insertAndOptimize(i, newFrom, len);
      }

      for (var i = 0, o = 0; i < data.length; i++) {
        final d = data[i];
        var l = d.length;
        if (to < o + l) {
          f(to - o, d, i);
          return len;
        }
        o += l;
      }
      f(data.last.length, data.last, data.length - 1);
      return len;
    }

    if (from < to) {
      while (len > 0) {
        final count = r(from, len, to);
        len -= count;
        to += count;
      }
    } else if (from > to) {
      while (len > 0) {
        final count = r(from, len, to);
        from += count;
        to += count;
        len -= count;
      }
    }
  }

  @override
  String toString() {
    return data.join(', ');
  }
}
