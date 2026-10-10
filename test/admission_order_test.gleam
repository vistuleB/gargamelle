import gargamelle as s
import gleam/list
import gleeunit/should

pub fn admitted_object_order_preserves_duplicate_positions_and_index_keys_test() {
  let assert Ok(input) =
    s.parse("{\"z\":\"first\",\"a\":\"middle\",\"z\":\"last\"}")
  s.decode(s.dictionary(s.text()), input)
  |> should.equal(Ok([#("z", "last"), #("a", "middle")]))
  let assert Ok(input) =
    s.parse(
      "{\"4294967295\":\"max\",\"01\":\"leading\",\"10\":\"ten\",\"2\":\"two\",\"0\":\"zero\",\"4294967294\":\"lastindex\",\"b\":\"b\",\"a\":\"a\"}",
    )
  let expected = ["0", "2", "10", "4294967294", "4294967295", "01", "b", "a"]
  let assert Ok(pairs) = s.decode(s.dictionary(s.text()), input)
  list.map(pairs, fn(pair) { pair.0 }) |> should.equal(expected)
  let assert Error(errors) =
    s.validate(s.finish(s.record(Nil), s.Closed), input)
  list.map(errors, fn(error) { error.path })
  |> should.equal(list.map(expected, fn(key) { "/" <> key }))
  let assert Ok(input) =
    s.parse("{\"outer\":{\"z\":\"old\",\"a\":\"middle\",\"z\":\"new\"}}")
  s.decode(s.dictionary(s.dictionary(s.text())), input)
  |> should.equal(Ok([#("outer", [#("z", "new"), #("a", "middle")])]))
}
