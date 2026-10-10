import gargamelle as s
import gleeunit/should

pub type Entry {
  Entry(String, Float, Bool)
}

pub fn typed_tuple_test() {
  let def =
    s.tuple(fn(name) {
      fn(weight) { fn(enabled) { Entry(name, weight, enabled) } }
    })
    |> s.element(s.text())
    |> s.element(s.number())
    |> s.element(s.boolean())
    |> s.finish_tuple
  let assert Ok(value) = s.parse("[\"x\",1.25,true]")
  s.decode(def, value) |> should.equal(Ok(Entry("x", 1.25, True)))
  let assert Ok(value) = s.parse("[\"x\",\"bad\",true]")
  let assert Error([error]) = s.decode(def, value)
  error.path |> should.equal("/1")
  let assert Ok(value) = s.parse("[]")
  s.decode(s.finish_tuple(s.tuple(Nil)), value) |> should.equal(Ok(Nil))
}
