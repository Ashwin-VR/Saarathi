import 'dart:collection';

class MessageCache {
  MessageCache({this.capacity = 100});

  final int capacity;
  final Queue<String> _order = Queue<String>();
  final Set<String> _entries = <String>{};

  bool contains(String id) => _entries.contains(id);

  void add(String id) {
    if (_entries.contains(id)) {
      _order.remove(id);
    } else if (_entries.length >= capacity) {
      final evicted = _order.removeFirst();
      _entries.remove(evicted);
    }

    _entries.add(id);
    _order.addLast(id);
  }

  void clear() {
    _order.clear();
    _entries.clear();
  }
}
