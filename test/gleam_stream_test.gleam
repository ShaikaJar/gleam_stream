import gleam/bool
import gleam/option.{type Option, Some}
import gleam/stream.{has_next, next}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

fn assert_some(option: Option(t)) {
  let assert Some(x) = option
  x
}

fn assert_none(option: Option(t)) {
  assert option |> option.is_none
}

pub fn empty_has_no_next_test() {
  let empty_stream = stream.empty()
  assert has_next(empty_stream) |> bool.negate
}

pub fn from_list_has_next_test() {
  let stream = stream.from_list([1, 2, 3])

  assert 1 == stream |> next() |> assert_some
  assert 2 == stream |> next() |> assert_some
  assert 3 == stream |> next() |> assert_some
  stream |> next() |> assert_none
}
