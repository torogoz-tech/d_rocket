// .x (absorbed from d_rest): `Decoder<T>`
// is the callback the `RestClient` invokes to turn
// the raw response body into a typed value of `T`.

typedef Decoder<T> = T Function(dynamic data);
