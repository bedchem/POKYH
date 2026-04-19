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

  Future<DishRating> getRating(String dishId) async {
    final safeId = _safeId(dishId);
    final voteKey = _voteKey;

    final dishDoc =
        await _db.collection('dish_ratings').doc(safeId).get();
    double avgRating = 0;
    int voteCount = 0;
    if (dishDoc.exists) {
      avgRating =
          (dishDoc.data()?['averageRating'] as num?)?.toDouble() ?? 0;
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

    final dishRef = _db.collection('dish_ratings').doc(safeId);
    final voteRef = dishRef.collection('votes').doc(voteKey);

    late DishRating result;

    await _db.runTransaction((transaction) async {
      final dishSnap = await transaction.get(dishRef);
      final voteSnap = await transaction.get(voteRef);

      double oldRating = 0;
      final hadVote = voteSnap.exists;
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
      }

      final int newVoteCount =
          hadVote ? currentVoteCount : currentVoteCount + 1;
      final double newTotal =
          hadVote ? currentTotal - oldRating + rating : currentTotal + rating;
      final double newAvg =
          newVoteCount > 0 ? newTotal / newVoteCount : 0.0;

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
