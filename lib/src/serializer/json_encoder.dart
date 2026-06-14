/// Serialises an instance of `T` into a JSON map.
typedef JsonEncoder<T> = Map<String, dynamic> Function(T value);
