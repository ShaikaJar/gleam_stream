import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleeunit
import stream.{has_next, next}

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

pub fn to_list_test() {
  let original_list = [1, 2, 3, 4]
  assert original_list
    == original_list |> stream.from_list() |> stream.to_list()
}

pub fn flat_map_test() {
  let original_list = [1, 2, 3, 4]
  let by = fn(x) {
    stream.generate_until(fn() { x }, fn(x) { x * 10 }, fn(x) { x > 1000 })
  }

  let list_flatten: List(Int) =
    original_list |> list.map(by) |> list.map(stream.to_list) |> list.flatten()
  let stream_map_flatten: List(Int) =
    original_list
    |> stream.from_list()
    |> stream.map(by)
    |> stream.flatten()
    |> stream.to_list()
  let stream_flatmap: List(Int) =
    original_list
    |> stream.from_list()
    |> stream.flat_map(by)
    |> stream.to_list()
  assert list_flatten == stream_map_flatten
  assert stream_map_flatten == stream_flatmap
}

pub fn map_test() {
  let original_list = [1, 2, 3, 4]
  let by = fn(x) { x * 10 }
  assert original_list |> list.map(by)
    == stream.from_list(original_list) |> stream.map(by) |> stream.to_list()
}

pub fn drop_test() {
  let original_list = [1, 2, 3, 4, 6, 7, 8, 9, 10]
  assert original_list |> list.drop(5)
    == original_list |> stream.from_list() |> stream.drop(5) |> stream.to_list()
}

pub fn generate_test() {
  assert stream.generate_until(fn() { 0 }, fn(x) { x + 1 }, fn(x) { x >= 10 })
    |> stream.to_list()
    == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
}

pub fn fold_test() {
  let original_list = [1, 2, 3, 4, 6, 7, 8, 9, 10]
  let seed = 0
  let with = int.add

  assert original_list |> list.fold(seed, with)
    == stream.from_list(original_list) |> stream.fold(seed, with)
}

pub fn filter_test() {
  let original_list = [1, 2, 3, 4, 6, 7, 8, 9, 10]
  let keep = int.is_even
  assert original_list |> list.filter(keep)
    == stream.from_list(original_list)
    |> stream.filter(keep)
    |> stream.to_list()
}

pub fn window_test() {
  let original_list = [1, 2, 3, 4, 6, 7, 8, 9, 10]
  let by = 3

  assert original_list |> list.window(by)
    == original_list
    |> stream.from_list()
    |> stream.window(by)
    |> stream.to_list()
}

pub fn window_by_2_test() {
  let original_list = [1, 2, 3, 4, 6, 7, 8, 9, 10]

  assert original_list |> list.window_by_2()
    == original_list
    |> stream.from_list()
    |> stream.window_by_2()
    |> stream.to_list()
}

pub fn filter_next_test() {
  let original_list = [1, 2, 3, 4, 6, 7, 8, 9, 10]
  let next =
    original_list
    |> stream.from_list()
    |> stream.filter(int.is_even)
    |> stream.next()
  assert Some(2) == next
}
