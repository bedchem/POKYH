import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'api_client.dart';
import 'reminder_service.dart';

class Todo {
  final String id;
  final String title;
  final String description;
  final bool isDone;
  final DateTime? remindAt;
  final DateTime? doneAt;
  final DateTime createdAt;

  const Todo({
    required this.id,
    required this.title,
    this.description = '',
    this.isDone = false,
    this.remindAt,
    this.doneAt,
    required this.createdAt,
  });

  factory Todo.fromJson(Map<String, dynamic> d) {
    return Todo(
      id: d['id'] as String,
      title: d['title'] as String? ?? '',
      description: d['details'] as String? ?? '',
      isDone: d['done'] as bool? ?? false,
      remindAt: d['dueAt'] != null ? DateTime.tryParse(d['dueAt'] as String) : null,
      doneAt: d['doneAt'] != null ? DateTime.tryParse(d['doneAt'] as String) : null,
      createdAt: d['createdAt'] != null
          ? DateTime.tryParse(d['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class TodoService {
  static final TodoService _instance = TodoService._();
  factory TodoService() => _instance;
  TodoService._();

  final _api = ApiClient.instance;
  final _reminders = ReminderService();

  String? get _username => AuthService.instance.username;

  StreamController<List<Todo>>? _ctrl;
  Timer? _timer;
  List<Todo>? _cache;

  Stream<List<Todo>> todoStream() {
    if (_username == null) return const Stream.empty();
    _ensureStream();
    // Emit cached list immediately so UI shows instantly, then refresh.
    final cached = _cache;
    if (cached != null) {
      Future.microtask(() {
        if (_ctrl != null && !_ctrl!.isClosed) _ctrl!.add(cached);
      });
    }
    _refresh();
    return _ctrl!.stream;
  }

  void _ensureStream() {
    if (_ctrl != null && !_ctrl!.isClosed) return;
    _ctrl = StreamController<List<Todo>>.broadcast();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final ctrl = _ctrl;
    if (ctrl == null || ctrl.isClosed) return;
    try {
      final todos = await _fetchTodos();
      _cache = todos;
      if (!ctrl.isClosed) ctrl.add(todos);
    } catch (e) {
      if (!ctrl.isClosed) ctrl.addError(e);
    }
  }

  // Optimistic local update — push immediately without waiting for network.
  void _pushOptimistic(List<Todo> todos) {
    _cache = todos;
    final ctrl = _ctrl;
    if (ctrl != null && !ctrl.isClosed) ctrl.add(todos);
  }

  Future<List<Todo>> _fetchTodos() async {
    final username = _username;
    if (username == null) return [];
    final data = await _api.get('/users/$username/todos') as List<dynamic>?;
    return (data ?? [])
        .cast<Map<String, dynamic>>()
        .map(Todo.fromJson)
        .toList();
  }

  Future<void> addTodo({
    required String title,
    String description = '',
    DateTime? remindAt,
  }) async {
    final username = _username;
    if (username == null) throw StateError('uid unavailable');
    final result = await _api.post('/users/$username/todos', {
      'title': title,
      'details': description,
      if (remindAt != null) 'dueAt': remindAt.toUtc().toIso8601String(),
    }) as Map<String, dynamic>;

    // Optimistic: add the new todo immediately to the cached list.
    final newTodo = Todo.fromJson(result);
    final updated = <Todo>[newTodo, ...(_cache ?? <Todo>[])];
    _pushOptimistic(updated);

    if (remindAt != null) {
      await _reminders.scheduleTodoNotification(
        result['id'] as String,
        title,
        description.isEmpty ? null : description,
        remindAt,
      );
    }
    // Background re-fetch to sync with server truth.
    _refresh();
  }

  Future<void> updateTodo(
    String id, {
    required String title,
    required String description,
    DateTime? remindAt,
    bool clearRemindAt = false,
  }) async {
    final username = _username;
    if (username == null) throw StateError('uid unavailable');

    // Optimistic update.
    if (_cache != null) {
      _pushOptimistic(_cache!.map((t) {
        if (t.id != id) return t;
        return Todo(
          id: t.id,
          title: title,
          description: description,
          isDone: t.isDone,
          remindAt: clearRemindAt ? null : (remindAt ?? t.remindAt),
          doneAt: t.doneAt,
          createdAt: t.createdAt,
        );
      }).toList());
    }

    await _api.patch('/users/$username/todos/$id', {
      'title': title,
      'details': description,
      'dueAt': clearRemindAt ? null : remindAt?.toUtc().toIso8601String(),
    });
    if (clearRemindAt) {
      await _reminders.cancelTodoNotification(id);
    } else if (remindAt != null) {
      await _reminders.scheduleTodoNotification(
        id,
        title,
        description.isEmpty ? null : description,
        remindAt,
      );
    }
    _refresh();
  }

  Future<void> toggleDone(String id, bool isDone) async {
    final username = _username;
    if (username == null) return;

    // Optimistic update.
    if (_cache != null) {
      _pushOptimistic(_cache!.map((t) {
        if (t.id != id) return t;
        return Todo(
          id: t.id,
          title: t.title,
          description: t.description,
          isDone: isDone,
          remindAt: t.remindAt,
          doneAt: isDone ? DateTime.now() : null,
          createdAt: t.createdAt,
        );
      }).toList());
    }

    await _api.patch('/users/$username/todos/$id', {
      'done': isDone,
      'doneAt': isDone ? DateTime.now().toUtc().toIso8601String() : null,
    });
    if (isDone) await _reminders.cancelTodoNotification(id);
    _refresh();
  }

  Future<void> deleteTodo(String id) async {
    final username = _username;
    if (username == null) return;

    // Optimistic: remove immediately from cache.
    if (_cache != null) {
      _pushOptimistic(_cache!.where((t) => t.id != id).toList());
    }

    await _api.delete('/users/$username/todos/$id');
    await _reminders.cancelTodoNotification(id);
    debugPrint('[TodoService] deleted $id');
    _refresh();
  }

  Future<void> cleanupDoneTodos() async {
    final username = _username;
    if (username == null) return;
    try {
      final todos = await _fetchTodos();
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final toDelete = todos.where(
        (t) => t.isDone && t.doneAt != null && t.doneAt!.isBefore(cutoff),
      ).toList();

      if (toDelete.isEmpty) {
        _cache = todos;
        return;
      }

      await Future.wait(toDelete.map((t) async {
        await _api.delete('/users/$username/todos/${t.id}');
        await _reminders.cancelTodoNotification(t.id);
        debugPrint('[TodoService] auto-deleted done todo ${t.id}');
      }));

      await _refresh();
    } catch (e) {
      debugPrint('[TodoService] cleanup error: $e');
    }
  }
}
