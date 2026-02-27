import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/stream.{each, generate_until, map}

pub fn main() {
  let stream =
    generate_until(fn() { 0 }, fn(x) { x + 1 }, fn(x) { x >= 20 })
    |> stream.drop(5)
    |> stream.filter(int.is_odd)
    |> stream.flat_map(fn(x) {
      stream.generate_until(fn() { x }, fn(x) { x * 10 }, fn(x) { x > 100 })
    })
    |> map(fn(x) {
      process.sleep(1000)
      x
    })

  stream |> each(fn(x) { io.println("New value: " <> int.to_string(x)) })
}
