part of 'great_list_view_lib.dart';

abstract class LiveData<T> extends ChangeNotifier {
  final List<Listenable> _notifiers; // listen to data source

  bool _disposed = false;
  bool _invalidating = false;
  int _invalidatingCount = 0;

  T get data;

  bool get invalidating => _invalidating;
  bool get disposed => _disposed;
  bool get isReady;

  LiveData(this._notifiers) {
    _notifiers.forEach((e) => e.addListener(onDataSourceChanged));
  }

  @override
  void dispose() {
    _notifiers.forEach((e) => e.removeListener(onDataSourceChanged));
    _disposed = true;
    super.dispose();
  }

  Future<void> onDataSourceChanged() async {
    if (_disposed) return;

    _invalidating = true;
    _invalidatingCount++;

    if (await processDataSourceChanged(invalidatedFunction)) {
      _invalidating = false;
    }
  }

  Future<bool> processDataSourceChanged(bool Function() invalidatedFn);

  bool Function() get invalidatedFunction {
    final ic = _invalidatingCount;
    return () => _disposed || _invalidatingCount != ic;
  }
}

class ValueLiveData<T> extends LiveData<T> {
  final Future<T> Function() _getCallback;
  T? _data;

  ValueLiveData(List<Listenable> _notifiers, this._getCallback)
      : super(_notifiers) {
    onDataSourceChanged();
  }

  @override
  T get data => _data!;

  @override
  bool get isReady => _data != null;

  @override
  Future<bool> processDataSourceChanged(bool Function() invalidatedFn) async {
    var newData = await _getCallback();
    if (invalidatedFn()) return false;
    _data = newData;
    notifyListeners();
    return true;
  }
}

class ListLiveData<T> extends ValueLiveData<List<T>> {
  ListLiveData(
      List<Listenable> _notifiers, Future<List<T>> Function() _getCallback)
      : super(_notifiers, _getCallback) {
    onDataSourceChanged();
  }

  @override
  List<T> get data => _data ?? <T>[];
}

class ContiguousPagedListLiveData<T> extends LiveData<PagedList<T>> {
  final Future<int> Function() _countCallback;
  final Future<List<T>> Function(int from, int count) _getCallback;
  final int _initialCount, _pageSize;
  final PaginatorValidator<T>? _validator;

  int? _count;
  int _lastValidatedCount = 0;

  final _pages = <_ContiguousPage<T>>[];

  PagedList<T> _pagedList;

  bool _markReadMore = false, _readingMore = false;

  ContiguousPagedListLiveData(
    List<Listenable> _notifiers,
    this._getCallback,
    this._countCallback,
    this._initialCount,
    this._pageSize, [
    this._validator,
  ])  : _pagedList = PagedList<T>.empty(),
        super(_notifiers) {
    onDataSourceChanged();
  }

  @override
  bool get isReady => _pagedList.isNotEmpty || _pagedList.isFullyLoaded;

  @override
  PagedList<T> get data => _pagedList;

  @override
  Future<bool> processDataSourceChanged(bool Function() invalidatedFn) async {
    final lastValidatedCount = _lastValidatedCount;

    ////////////////////
    _count = await _countCallback.call();
    ////////////////////

    if (invalidatedFn()) return false;

    _pages.clear();

    var validatedCount = 0;

    if (_count! > 0) {
      ////////////////////
      var r = await _addPage(invalidatedFn, validatedCount,
          math.max(_initialCount, lastValidatedCount));
      ////////////////////
      if (r == null) return false;
      validatedCount = r;
    }

    _notify(validatedCount);

    if (_markReadMore && !isFullyLoaded) {
      _markReadMore = false;
      assert(!_readingMore);
      // ignore: unawaited_futures
      readMore();
    }

    return true;
  }

  void _notify(int validatedCount) {
    _lastValidatedCount = validatedCount;
    _markReadMore = false;
    _readingMore = false;
    _pagedList = PagedList._(_pages, validatedCount, isFullyLoaded);
    notifyListeners();
  }

  Future<void> readMore() async {
    if (_count == null || disposed || _readingMore || isFullyLoaded) {
      return;
    }

    if (invalidating) {
      _markReadMore = true;
      return;
    }

    _readingMore = true;

    ////////////////////
    var r = await _addPage(invalidatedFunction, _lastValidatedCount);
    ////////////////////

    if (r == null) {
      _markReadMore = true;
      return;
    }

    _notify(r);
  }

  Future<int?> _addPage(bool Function() invalidatedFn, int validatedCount,
      [int? firstTo]) async {
    assert(!isFullyLoaded);

    var desiredTo =
        (validatedCount == 0 ? _initialCount : validatedCount + _pageSize);
    if (desiredTo > _count!) desiredTo = _count!;

    List<T>? unvalidatedList;

    var to = math.max(firstTo ?? desiredTo, loadedCount + _pageSize);

    do {
      var from = loadedCount;
      if (to > _count!) to = _count!;

      var count = to - from;
      assert(count > 0);

      ////////////////////
      final data = await _getCallback.call(from, count);
      ////////////////////

      if (invalidatedFn()) return null;

      var page = _ContiguousPage(data, from);
      _pages.add(page);

      if (unvalidatedList == null) {
        unvalidatedList = List<T>.from(iterable(from: validatedCount));
      } else {
        unvalidatedList.addAll(page.list);
      }

      late int upTo;
      if (_validator != null) {
        upTo =
            validatedCount + _validator!.call(unvalidatedList, isFullyLoaded);
        assert(upTo >= validatedCount && upTo <= loadedCount);
        assert(!isFullyLoaded || upTo == _count!);
      } else {
        upTo = to;
      }

      if (upTo < desiredTo) {
        unvalidatedList.removeRange(0, upTo - validatedCount);
        to = loadedCount + _pageSize;
      }
      if (validatedCount != upTo) validatedCount = upTo;
    } while (validatedCount < desiredTo);

    return validatedCount;
  }

  int get loadedCount {
    assert(!disposed);
    return _pages.isNotEmpty ? _pages.last.to : 0;
  }

  bool get isFullyLoaded {
    assert(!disposed);
    return _count == null ? false : loadedCount == _count!;
  }

  Iterable<T> iterable({int from = 0, int? to}) sync* {
    assert(!disposed);
    assert(_pages.isNotEmpty);
    assert(from >= 0 && from < loadedCount);
    to ??= loadedCount;
    assert(to > from && to <= loadedCount);
    var i = 0;
    for (var page in _pages) {
      if (from >= page.to) {
        i += page.count;
        continue;
      }
      for (var j = math.max(0, from - page.from); j < page.count; j++) {
        if (i >= to) return;
        yield page.list[j];
      }
    }
  }
}

class PagedList<T> extends ListBase<T> {
  final List<_ContiguousPage<T>> _pages;
  final int _count;
  final bool _fullyLoaded;

  PagedList.empty()
      : _pages = [],
        _count = 0,
        _fullyLoaded = false;

  PagedList._(List<_ContiguousPage> pages, this._count, this._fullyLoaded)
      : _pages = List<_ContiguousPage<T>>.from(pages, growable: false);

  bool get isFullyLoaded => _fullyLoaded;

  @override
  int get length => _count;

  @override
  T operator [](int index) {
    assert(index >= 0 && index < _count);
    for (var page in _pages) {
      if (index >= page.to) continue;
      return page.list[index - page.from];
    }
    throw 'unexpected error';
  }

  @override
  T get first => _pages.first.list.first;

  @override
  T get last => _pages.last.list.last;

  @override
  void forEach(void Function(T element) action) {
    for (var page in _pages) {
      for (var e in page.list) {
        action(e);
      }
    }
  }

  @override
  void operator []=(int index, T value) {
    throw UnsupportedError('Cannot modify an unmodifiable list');
  }

  @override
  set length(int newLength) {
    throw UnsupportedError('Cannot change the length of an unmodifiable list');
  }

  @override
  set first(T element) {
    throw UnsupportedError('Cannot modify an unmodifiable list');
  }

  @override
  set last(T element) {
    throw UnsupportedError('Cannot modify an unmodifiable list');
  }

  @override
  void setAll(int at, Iterable<T> iterable) {
    throw UnsupportedError('Cannot modify an unmodifiable list');
  }

  @override
  void add(T value) {
    throw UnsupportedError('Cannot add to an unmodifiable list');
  }

  @override
  void insert(int index, T element) {
    throw UnsupportedError('Cannot add to an unmodifiable list');
  }

  @override
  void insertAll(int at, Iterable<T> iterable) {
    throw UnsupportedError('Cannot add to an unmodifiable list');
  }

  @override
  void addAll(Iterable<T> iterable) {
    throw UnsupportedError('Cannot add to an unmodifiable list');
  }

  @override
  bool remove(Object? element) {
    throw UnsupportedError('Cannot remove from an unmodifiable list');
  }

  @override
  void removeWhere(bool Function(T element) test) {
    throw UnsupportedError('Cannot remove from an unmodifiable list');
  }

  @override
  void retainWhere(bool Function(T element) test) {
    throw UnsupportedError('Cannot remove from an unmodifiable list');
  }

  @override
  void sort([Comparator<T>? compare]) {
    throw UnsupportedError('Cannot modify an unmodifiable list');
  }

  @override
  void shuffle([math.Random? random]) {
    throw UnsupportedError('Cannot modify an unmodifiable list');
  }

  @override
  void clear() {
    throw UnsupportedError('Cannot clear an unmodifiable list');
  }

  @override
  T removeAt(int index) {
    throw UnsupportedError('Cannot remove from an unmodifiable list');
  }

  @override
  T removeLast() {
    throw UnsupportedError('Cannot remove from an unmodifiable list');
  }

  @override
  void setRange(int start, int end, Iterable<T> iterable, [int skipCount = 0]) {
    throw UnsupportedError('Cannot modify an unmodifiable list');
  }

  @override
  void removeRange(int start, int end) {
    throw UnsupportedError('Cannot remove from an unmodifiable list');
  }

  @override
  void replaceRange(int start, int end, Iterable<T> iterable) {
    throw UnsupportedError('Cannot remove from an unmodifiable list');
  }

  @override
  void fillRange(int start, int end, [T? fillValue]) {
    throw UnsupportedError('Cannot modify an unmodifiable list');
  }
}

class _ContiguousPage<T> {
  final List<T> list;
  final int from;

  int get count => list.length;

  int get to => from + count;

  _ContiguousPage(this.list, this.from) : assert(from >= 0 && list.isNotEmpty);
}

typedef PaginatorValidator<T> = int Function(List<T> list, bool fullyLoaded);
