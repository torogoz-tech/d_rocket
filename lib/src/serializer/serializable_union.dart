/// Marks a base type as a polymorphic union root.
///
/// Use with `sealed class` to enable discriminated
/// union serialisation.
///
/// Example:
/// ```dart
/// @SerializableUnion(typeField: 'type')
/// sealed class PaymentMethod {}
///
/// @Serializable(discriminator: 'card')
/// class CardPayment extends PaymentMethod {
/// final String last4;
/// CardPayment({required this.last4});
/// }
/// ```
class SerializableUnion {
  /// JSON field name that stores the discriminator
  /// value. Defaults to 'type' if not specified.
  final String typeField;

  const SerializableUnion({this.typeField = 'type'});
}
