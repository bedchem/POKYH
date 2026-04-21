import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_auth_service.dart';

class DishRating {
  final double? userRating;
  final double avgRating;
  final int voteCount;

  const DishRating({
    this.userRating,
    required this.avgRating,
    required this.voteCount,
  });

  String get userRatingLabel {
    if (userRating == null) return '';
    final v = userRating!;
    return v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
  }
}

class _LegacyRating {
  final int voteCount;
  final double total;
  final double? userRating;

  const _LegacyRating({
    required this.voteCount,
    required this.total,
    this.userRating,
  });
}

class RatingService {
  static final RatingService _instance = RatingService._();
  RatingService._();
  static RatingService get instance => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _safeId(String dishId) =>
      dishId.replaceAll('/', '_').replaceAll('.', '_');

  /// Stable vote key: stableUid if available, otherwise Firebase UID.
  /// This ensures the same vote is shared across all devices of a user.
  String? get _voteKey =>
      FirebaseAuthService.instance.stableUid ??
      FirebaseAuthService.instance.userId;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _findLegacyRatingDocs(String safeId) async {
    final startId = '${safeId}_';
    final endId = '${safeId}_\uf8ff';
    final snapshot = await _db
        .collection('dish_ratings')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startId)
        .where(FieldPath.documentId, isLessThan: endId)
        .get();
    return snapshot.docs;
  }

  Future<double?> _findLegacyUserRating(String safeId, String voteKey) async {
    for (final legacyDoc in await _findLegacyRatingDocs(safeId)) {
      final voteSnap = await _db
          .collection('dish_ratings')
          .doc(legacyDoc.id)
          .collection('votes')
          .doc(voteKey)
          .get();
      if (voteSnap.exists) {
        return (voteSnap.data()?['rating'] as num?)?.toDouble();
      }
    }
    return null;
  }

  Future<_LegacyRating?> _getLegacyRating(
    String safeId,
    String? voteKey,
  ) async {
    final legacyDocs = await _findLegacyRatingDocs(safeId);
    if (legacyDocs.isEmpty) return null;

    int voteCount = 0;
    double total = 0;
    double? userRating;

    for (final legacyDoc in legacyDocs) {
      final avg = (legacyDoc.data()['averageRating'] as num?)?.toDouble() ?? 0;
      final count = (legacyDoc.data()['voteCount'] as num?)?.toInt() ?? 0;
      voteCount += count;
      total += avg * count;
      if (voteKey != null && userRating == null) {
        final voteSnap = await _db
            .collection('dish_ratings')
            .doc(legacyDoc.id)
            .collection('votes')
            .doc(voteKey)
            .get();
        if (voteSnap.exists) {
          userRating = (voteSnap.data()?['rating'] as num?)?.toDouble();
        }
      }
    }

    return _LegacyRating(
      voteCount: voteCount,
      total: total,
      userRating: userRating,
    );
  }

  Future<DishRating> getRating(String dishId) async {
    final safeId = _safeId(dishId);
    final voteKey = _voteKey;

    final dishDoc = await _db.collection('dish_ratings').doc(safeId).get();
    double avgRating = 0;
    int voteCount = 0;
    if (dishDoc.exists) {
      avgRating = (dishDoc.data()?['averageRating'] as num?)?.toDouble() ?? 0;
      voteCount = (dishDoc.data()?['voteCount'] as num?)?.toInt() ?? 0;
    }

    double? userRating;
    if (voteKey != null) {
      final voteDoc = await _db
          .collection('dish_ratings')
          .doc(safeId)
          .collection('votes')
          .doc(voteKey)
          .get();
      if (voteDoc.exists) {
        userRating = (voteDoc.data()?['rating'] as num?)?.toDouble();
      } else {
        userRating = await _findLegacyUserRating(safeId, voteKey);
      }
    }

    if (!dishDoc.exists) {
      final legacy = await _getLegacyRating(safeId, voteKey);
      if (legacy != null) {
        return DishRating(
          userRating: userRating ?? legacy.userRating,
          avgRating: legacy.voteCount > 0 ? legacy.total / legacy.voteCount : 0,
          voteCount: legacy.voteCount,
        );
      }
    }

    return DishRating(
      userRating: userRating,
      avgRating: avgRating,
      voteCount: voteCount,
    );
  }

  Future<DishRating> submitRating(
    String dishId,
    double rating, {
    required String username,
  }) async {
    final safeId = _safeId(dishId);
    final voteKey = _voteKey;
    if (voteKey == null) throw Exception('Not authenticated');

    final legacy = await _getLegacyRating(safeId, voteKey);
    final dishRef = _db.collection('dish_ratings').doc(safeId);
    final voteRef = dishRef.collection('votes').doc(voteKey);

    late DishRating result;

    await _db.runTransaction((transaction) async {
      final dishSnap = await transaction.get(dishRef);
      final voteSnap = await transaction.get(voteRef);

      double oldRating = 0;
      bool hadVote = voteSnap.exists;
      if (hadVote) {
        oldRating = (voteSnap.data()?['rating'] as num?)?.toDouble() ?? 0;
      }

      int currentVoteCount = 0;
      double currentTotal = 0;
      if (dishSnap.exists) {
        currentVoteCount =
            (dishSnap.data()?['voteCount'] as num?)?.toInt() ?? 0;
        final avg =
            (dishSnap.data()?['averageRating'] as num?)?.toDouble() ?? 0;
        currentTotal = avg * currentVoteCount;
      } else if (legacy != null) {
        currentVoteCount = legacy.voteCount;
        currentTotal = legacy.total;
        if (!hadVote && legacy.userRating != null) {
          oldRating = legacy.userRating!;
          // The previous vote is merged into the new base rating document.
          hadVote = true;
        }
      }

      final int newVoteCount = hadVote
          ? currentVoteCount
          : currentVoteCount + 1;
      final double newTotal = hadVote
          ? currentTotal - oldRating + rating
          : currentTotal + rating;
      final double newAvg = newVoteCount > 0 ? newTotal / newVoteCount : 0.0;

      transaction.set(dishRef, {
        'averageRating': newAvg,
        'voteCount': newVoteCount,
        'lastVotedBy': username,
        'lastVotedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(voteRef, {
        'rating': rating,
        'username': username,
        'timestamp': FieldValue.serverTimestamp(),
      });

      result = DishRating(
        userRating: rating.toDouble(),
        avgRating: newAvg,
        voteCount: newVoteCount,
      );
    });

    return result;
  }
}
