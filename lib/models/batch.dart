// Batch 模型
class Batch {
  final String id; // batch_id = {store_name}_{order_date}
  final String storeName;
  final String orderDate; // YYYY-MM-DD
  final String createdAt; // ISO 8601
  final String? finishedAt; // ISO 8601, nullable

  Batch({
    required this.id,
    required this.storeName,
    required this.orderDate,
    required this.createdAt,
    this.finishedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_name': storeName,
      'order_date': orderDate,
      'created_at': createdAt,
      'finished_at': finishedAt,
    };
  }

  factory Batch.fromMap(Map<String, dynamic> map) {
    return Batch(
      id: map['id'] as String,
      storeName: map['store_name'] as String,
      orderDate: map['order_date'] as String,
      createdAt: map['created_at'] as String,
      finishedAt: map['finished_at'] as String?,
    );
  }

  bool get isFinished => finishedAt != null;

  // 產生 batch_id
  static String generateId(String storeName, String orderDate) {
    return '${storeName}_$orderDate';
  }
}

