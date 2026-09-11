class PerformanceReviewInput {
  const PerformanceReviewInput({
    required this.assignmentId,
    required this.stars,
    this.tags = const [],
    this.notes,
  });

  final String assignmentId;
  final int stars;
  final List<String> tags;
  final String? notes;

  Map<String, dynamic> toRpcParams() => {
    'p_assignment_id': assignmentId,
    'p_stars': stars,
    'p_tags': tags,
    'p_notes': notes,
  };
}

class PerformanceReviewResult {
  const PerformanceReviewResult({
    required this.reviewId,
    required this.eventId,
    required this.assignmentId,
    required this.workerId,
    required this.reviewerId,
    required this.reviewerRole,
    required this.stars,
    required this.tags,
    required this.updatedAt,
    this.notes,
  });

  final String reviewId;
  final String eventId;
  final String assignmentId;
  final String workerId;
  final String reviewerId;
  final String reviewerRole;
  final int stars;
  final List<String> tags;
  final String? notes;
  final DateTime updatedAt;

  static PerformanceReviewResult fromJson(Map<String, dynamic> json) {
    return PerformanceReviewResult(
      reviewId: json['review_id'] as String,
      eventId: json['event_id'] as String,
      assignmentId: json['assignment_id'] as String,
      workerId: json['worker_id'] as String,
      reviewerId: json['reviewer_id'] as String,
      reviewerRole: json['reviewer_role'] as String,
      stars: (json['stars'] as num).toInt(),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      notes: json['notes'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
