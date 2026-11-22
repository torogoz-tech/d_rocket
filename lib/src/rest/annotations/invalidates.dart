/// Marks a successful REST mutation as invalidating query [tags].
class Invalidates {
  const Invalidates(this.tags);

  final List<String> tags;
}
