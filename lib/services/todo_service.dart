import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_auth_service.dart';
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

  factory Todo.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Todo(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      isDone: data['isDone'] as bool? ?? false,
      remindAt: (data['remindAt'] as Timestamp?)?.toDate(),
      doneAt: (data['doneAt'] as Timestamp?)?.toDate(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class TodoService {
  static final TodoService _instance = TodoService._();
  factory TodoService() => _instance;
  TodoService._();

  final _db = FirebaseFirestore.instance;
  final _reminders = ReminderService();

  CollectionReference<Map<String, dynamic>>? _ref;

  Future<CollectionReference<Map<String, dynamic>>?> _getRef() async {
    if (_ref != null) return _ref;
    String? uid = FirebaseAuthService.instance.stableUid;
    if (uid == null || uid.isEmpty) {
      uid = await FirebaseAuthService.instance.resolveStableUid();
    }
    if (uid == null || uid.isEmpty) return null;
    _ref = _db
        .collection('user_todos')
        .doc(uid)
        .collection('todos');
    return _ref;
  }

  Stream<List<Todo>> todoStream() {
    final uid = FirebaseAuthService.instance.stableUid;
    if (uid == null || uid.isEmpty) return const Stream.empty();
    return _db
        .collection('user_todos')
        .doc(uid)
        .collection('todos')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => Todo.fromDoc(doc)).toList(),
        );
  }

  Future<void> addTodo({
    required String title,
    String description = '',
    DateTime? remindAt,
  }) async {
    final ref = await _getRef();
    if (ref == null) throw StateError('uid unavailable');
    final doc = await ref.add({
      'title': title,
      'description': description,
      'isDone': false,
      'remindAt':
          remindAt != null ? Timestamp.fromDate(remindAt) : null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (remindAt != null) {
      await _reminders.scheduleTodoNotification(
        doc.id,
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
    final ref = await _getRef();
    if (ref == null) throw StateError('uid unavailable');
    await ref.doc(id).update({
      'title': title,
      'description': description,
      'remindAt': clearRemindAt
          ? null
          : (remindAt != null ? Timestamp.fromDate(remindAt) : null),
      'updatedAt': FieldValue.serverTimestamp(),
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
    final ref = await _getRef();
    if (ref == null) return;
    await ref.doc(id).update({
      'isDone': isDone,
      'doneAt': isDone ? FieldValue.serverTimestamp() : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (isDone) {
      await _reminders.cancelTodoNotification(id);
    }
  }

  Future<void> deleteTodo(String id) async {
    final ref = await _getRef();
    if (ref == null) return;
    await ref.doc(id).delete();
    await _reminders.cancelTodoNotification(id);
    debugPrint('[TodoService] deleted $id');
  }

  // Löscht alle erledigten Todos, die vor mehr als 24h abgehakt wurden.
  Future<void> cleanupDoneTodos() async {
    final ref = await _getRef();
    if (ref == null) return;
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 24)),
    );
    try {
      final snap = await ref
          .where('doneAt', isLessThan: cutoff)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
        await _reminders.cancelTodoNotification(doc.id);
        debugPrint('[TodoService] auto-deleted done todo ${doc.id}');
      }
    } catch (e) {
      debugPrint('[TodoService] cleanup error: $e');
    }
  }
}
