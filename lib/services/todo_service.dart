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

  Stream<List<Todo>> todoStream() {
    if (_username == null) return const Stream.empty();

    final controller = StreamController<List<Todo>>();
    bool active = true;

    Future<void> fetch() async {
      if (!active || controller.isClosed) return;
      try {
        final todos = await _fetchTodos();
        if (!controller.isClosed) controller.add(todos);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    fetch();
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => fetch());

    controller.onCancel = () {
      active = false;
      timer.cancel();
    };

    return controller.stream;
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

    if (remindAt != null) {
      await _reminders.scheduleTodoNotification(
        result['id'] as String,
        title,
        description.isEmpty ? null : description,
        remindAt,
      );
    }
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
    await _api.patch('/users/$username/todos/$id', {
      'title': title,
      'details': description,
      'dueAt': clearRemindAt
          ? null
          : remindAt?.toUtc().toIso8601String(),
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
  }

  Future<void> toggleDone(String id, bool isDone) async {
    final username = _username;
    if (username == null) return;
    await _api.patch('/users/$username/todos/$id', {
      'done': isDone,
      'doneAt': isDone ? DateTime.now().toUtc().toIso8601String() : null,
    });
    if (isDone) {
      await _reminders.cancelTodoNotification(id);
    }
  }

  Future<void> deleteTodo(String id) async {
    final username = _username;
    if (username == null) return;
    await _api.delete('/users/$username/todos/$id');
    await _reminders.cancelTodoNotification(id);
    debugPrint('[TodoService] deleted $id');
  }

  Future<void> cleanupDoneTodos() async {
    final username = _username;
    if (username == null) return;
    try {
      final todos = await _fetchTodos();
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      for (final todo in todos) {
        if (todo.isDone && todo.doneAt != null && todo.doneAt!.isBefore(cutoff)) {
          await _api.delete('/users/$username/todos/${todo.id}');
          await _reminders.cancelTodoNotification(todo.id);
          debugPrint('[TodoService] auto-deleted done todo ${todo.id}');
        }
      }
    } catch (e) {
      debugPrint('[TodoService] cleanup error: $e');
    }
  }
}
