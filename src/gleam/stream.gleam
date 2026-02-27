import gleam/bool
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

type Message(t) {
  GetNext(reply_to: process.Subject(Option(t)))
  HasNext(reply_to: process.Subject(Bool))
}

type State(t) {
  Finished
  UnInitialized(fn() -> t)
  Generating(t)
}

pub opaque type Stream(t) {
  TrueGenerator(
    subject: process.Subject(Message(t)),
    pid: process.Pid,
    handle: fn(State(t), Message(t)) -> actor.Next(State(t), Message(t)),
    seed: fn() -> t,
  )
  EmptyGenerator
}

fn try_if_alive(
  generator: Stream(t),
  fallback: r,
  if_alive: fn(process.Subject(Message(t)), process.Pid) -> r,
) -> r {
  case generator {
    EmptyGenerator -> fallback
    TrueGenerator(_, pid, _, _) -> {
      case process.is_alive(pid) {
        False -> fallback
        True -> if_alive(generator.subject, generator.pid)
      }
    }
  }
}

pub fn has_next(generator: Stream(t)) -> Bool {
  try_if_alive(generator, False, fn(subject, _) {
    process.call_forever(subject, HasNext)
  })
}

pub fn next(generator: Stream(t)) -> Option(t) {
  try_if_alive(generator, None, fn(subject, _) {
    process.call_forever(subject, GetNext)
  })
}

fn handle_message(
  generator: fn(t) -> t,
  until: fn(t) -> Bool,
  state: State(t),
  message: Message(t),
) {
  let new_state: State(t) = case state, message {
    Finished, GetNext(return_to) -> {
      process.send(return_to, None)
      Finished
    }
    Generating(cur), GetNext(return_to) -> {
      let next = generator(cur)

      process.send(return_to, Some(next))
      case until(next) {
        True -> Finished
        False -> Generating(next)
      }
    }
    UnInitialized(init), GetNext(return_to) -> {
      let first = init()
      process.send(return_to, Some(first))
      case until(first) {
        True -> Finished
        False -> Generating(first)
      }
    }
    Finished, HasNext(return_to) -> {
      process.send(return_to, False)
      Finished
    }
    UnInitialized(x), HasNext(return_to) -> {
      process.send(return_to, True)
      UnInitialized(x)
    }
    Generating(x), HasNext(return_to) -> {
      process.send(return_to, True)
      Generating(x)
    }
  }

  case new_state {
    // Finished -> actor.stop()
    _ -> actor.continue(new_state)
  }
}

fn create(
  handle: fn(State(t), Message(t)) -> actor.Next(State(t), Message(t)),
  seed: fn() -> t,
) {
  let assert Ok(my_actor) =
    actor.new(UnInitialized(seed))
    |> actor.on_message(handle)
    |> actor.start
  TrueGenerator(
    subject: my_actor.data,
    pid: my_actor.pid,
    handle: handle,
    seed: seed,
  )
}

// Helper-Function

pub fn generate_until(
  seed: fn() -> t,
  generate: fn(t) -> t,
  until: fn(t) -> Bool,
) -> Stream(t) {
  let handle = fn(x, y) { handle_message(generate, until, x, y) }
  create(handle, seed)
}

pub fn each(from: Stream(t), do: fn(t) -> Nil) -> Nil {
  case next(from) {
    None -> Nil
    Some(val) -> {
      do(val)
      each(from, do)
    }
  }
}

// Java Stream api

pub fn generate(seed: fn() -> t, by: fn(t) -> t) -> Stream(t) {
  generate_until(seed, by, fn(_) { False })
}

pub fn from_list(values: List(t)) -> Stream(t) {
  let gen: Stream(#(List(t), t)) = case values {
    [] -> EmptyGenerator
    [first, ..res] ->
      generate_until(
        fn() { #(res, first) },
        fn(x) {
          let #(values, _) = x
          let assert [next, ..res] = values
          #(res, next)
        },
        fn(x) {
          let #(values, _) = x
          case values {
            [_, ..] -> True
            _ -> False
          }
        },
      )
  }

  gen
  |> map(fn(x) {
    let #(_, cur) = x
    cur
  })
}

pub fn map(from: Stream(t), by: fn(t) -> r) -> Stream(r) {
  case has_next(from) {
    False -> EmptyGenerator
    True -> {
      generate_until(
        fn() {
          let assert Some(first) = next(from)
          first |> by()
        },
        fn(_) {
          let assert Some(val) = next(from)
          val |> by()
        },
        fn(_) { has_next(from) |> bool.negate() },
      )
    }
  }
}

pub fn empty() -> Stream(t) {
  EmptyGenerator
}

pub fn until(from: Stream(t), until: fn(t) -> Bool) {
  case has_next(from) {
    False -> EmptyGenerator
    True -> {
      generate_until(
        fn() {
          let assert Some(first) = next(from)
          first
        },
        fn(_) {
          let assert Some(val) = next(from)
          val
        },
        until,
      )
    }
  }
}

pub fn copy(original: Stream(t)) -> Stream(t) {
  case original {
    EmptyGenerator -> EmptyGenerator
    TrueGenerator(_, _, handle, seed) -> {
      create(handle, seed)
    }
  }
}

fn next_match(from: Stream(t), keeping predicate: fn(t) -> Bool) -> Option(t) {
  case next(from) {
    None -> None
    Some(x) -> {
      case predicate(x) {
        True -> Some(x)
        False -> next_match(from, predicate)
      }
    }
  }
}

pub fn filter(from: Stream(t), keeping predicate: fn(t) -> Bool) {
  case next_match(from, predicate) {
    None -> EmptyGenerator
    Some(first) ->
      generate_until(
        fn() { #(first, next_match(from, predicate)) },
        fn(a) {
          let assert #(_, Some(cur)) = a
          #(cur, next_match(from, predicate))
        },
        fn(a) {
          let #(_, cur) = a
          option.is_none(cur)
        },
      )
  }
  |> map(fn(a) {
    let #(cur, _) = a
    cur
  })
}

pub fn fold(
  over stream: Stream(t),
  from initial: acc,
  with fun: fn(acc, t) -> acc,
) -> acc {
  case next(stream) {
    None -> initial
    Some(x) -> fun(initial, x)
  }
}

pub fn to_list(from: Stream(t)) -> List(t) {
  from |> fold([], list.prepend) |> list.reverse
}

fn indexed(stream: Stream(a)) -> Stream(#(a, Int)) {
  case has_next(stream) {
    False -> EmptyGenerator
    True -> {
      generate_until(
        fn() {
          let assert Some(first) = next(stream)
          #(first, 0)
        },
        fn(a) {
          let #(_, last_index) = a
          let assert Some(val) = next(stream)
          #(val, last_index + 1)
        },
        fn(_) { has_next(stream) |> bool.negate() },
      )
    }
  }
}

pub fn drop_while(
  in stream: Stream(a),
  satisfying predicate: fn(a) -> Bool,
) -> Stream(a) {
  case next_match(stream, fn(x) { x |> predicate() |> bool.negate() }) {
    None -> EmptyGenerator
    Some(first) -> {
      generate_until(
        fn() { first },
        fn(_) {
          let assert Some(val) = next(stream)
          val
        },
        fn(_) { has_next(stream) |> bool.negate() },
      )
    }
  }
}

pub fn drop(from stream: Stream(a), up_to n: Int) -> Stream(a) {
  indexed(stream)
  |> drop_while(fn(a) {
    let #(_, index) = a
    case index {
      i if i < n -> True
      _ -> False
    }
  })
  |> map(fn(a) {
    let #(val, _) = a
    val
  })
}

pub fn flat_map(
  from stream: Stream(Int),
  by fun: fn(Int) -> Stream(Int),
) -> Stream(Int) {
  stream |> map(fun) |> flatten()
}

pub fn flatten(streams: Stream(Stream(Int))) -> Stream(Int) {
  let next_stream = fn() { next_match(streams, has_next) }

  let ib: Stream(#(Int, Stream(Int), Option(Stream(Int)))) = case
    next_stream()
  {
    None -> EmptyGenerator
    Some(first_generator) ->
      generate_until(
        fn() {
          let assert Some(first_val) = next(first_generator)
          #(first_val, first_generator, next_stream())
        },
        fn(x) {
          let #(_, cur_stream, next_maybe) = x
          case next(cur_stream) {
            Some(val) -> {
              #(val, cur_stream, next_maybe)
            }
            None -> {
              let assert Some(cur_stream) = next_maybe
              let assert Some(val) = next(cur_stream)
              let next_maybe = next_stream()
              #(val, cur_stream, next_maybe)
            }
          }
        },
        fn(x) {
          let #(_, cur_stream, next_maybe) = x
          let has_some =
            has_next(cur_stream)
            || next_maybe |> option.map(has_next) |> option.unwrap(False)
          has_some |> bool.negate
        },
      )
  }

  ib
  |> map(fn(x) {
    let #(val, _, _) = x
    val
  })
}
