import 'auth_service.dart';
import 'api_client.dart';

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

  factory DishRating.fromJson(Map<String, dynamic> d) {
    final ratings = (d['ratings'] as Map<String, dynamic>?) ?? {};
    final voteCount = ratings.length;
    final total = ratings.values.fold(
      0.0,
      (sum, v) => sum + (v as num).toDouble(),
    );
    final avgRating = voteCount > 0 ? total / voteCount : 0.0;
    final myRating = (d['myRating'] as num?)?.toDouble();
    return DishRating(
      userRating: myRating,
      avgRating: avgRating,
      voteCount: voteCount,
    );
  }
}

class RatingService {
  static final RatingService _instance = RatingService._();
  RatingService._();
  static RatingService get instance => _instance;

  final _api = ApiClient.instance;

  String _safeId(String dishId) =>
      dishId.replaceAll('/', '_').replaceAll('.', '_');

  Future<DishRating> getRating(String dishId) async {
    if (!AuthService.instance.isSignedIn) {
      return const DishRating(avgRating: 0, voteCount: 0);
    }
    final safeId = _safeId(dishId);
    try {
      final data = await _api.get('/dish-ratings/$safeId') as Map<String, dynamic>;
      return DishRating.fromJson(data);
    } catch (_) {
      return const DishRating(avgRating: 0, voteCount: 0);
    }
  }

  Future<Map<String, DishRating>> getRatingsBatch(List<String> dishIds) async {
    if (!AuthService.instance.isSignedIn || dishIds.isEmpty) return {};
    final safeIds = dishIds.map(_safeId).toList();
    try {
      final data = await _api.post('/dish-ratings/batch', {
        'dishIds': safeIds,
      }) as Map<String, dynamic>;
      return {
        for (final entry in data.entries)
          entry.key: DishRating.fromJson(entry.value as Map<String, dynamic>),
      };
    } catch (_) {
      return {};
    }
  }

  Future<DishRating> submitRating(
    String dishId,
    double rating, {
    required String username,
  }) async {
    if (!AuthService.instance.isSignedIn) {
      throw Exception('Not authenticated');
    }
    final safeId = _safeId(dishId);
    final stars = rating.round().clamp(1, 5);
    final data = await _api.post('/dish-ratings/$safeId', {
      'stars': stars,
    }) as Map<String, dynamic>;
    return DishRating.fromJson(data);
  }
}
