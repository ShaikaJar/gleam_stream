import gleam/bool
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

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

fn save_call(
  subject: process.Subject(Message(t)),
  message: fn(process.Subject(r)) -> Message(t),
) {
  let reply_to = process.new_subject()
  process.send(subject, message(reply_to))
  process.receive(reply_to, 1000)
}

fn try_if_alive(
  generator: Stream(t),
  fallback: r,
  if_alive: fn(process.Subject(Message(t)), process.Pid) -> Result(r, Nil),
) -> r {
  case generator {
    EmptyGenerator -> fallback
    TrueGenerator(_, pid, _, _) -> {
      use <- bool.guard(process.is_alive(pid) |> bool.negate, fallback)
      if_alive(generator.subject, generator.pid) |> result.unwrap(fallback)
    }
  }
}

pub fn has_next(generator: Stream(t)) -> Bool {
  use subject, _ <- try_if_alive(generator, False)
  save_call(subject, HasNext)
}

pub fn next(generator: Stream(t)) -> Option(t) {
  use subject, _ <- try_if_alive(generator, None)
  save_call(subject, GetNext)
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
    Finished -> actor.stop()
    _ -> actor.continue(new_state)
  }
}

fn create(
  seed: fn() -> t,
  handle: fn(State(t), Message(t)) -> actor.Next(State(t), Message(t)),
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

fn id(x: t) -> fn() -> t {
  fn() { x }
}

pub fn generate_until(
  seed seed: fn() -> t,
  by generate: fn(t) -> t,
  until until: fn(t) -> Bool,
) -> Stream(t) {
  use state, message <- create(seed)
  handle_message(generate, until, state, message)
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
  use state, message <- create(seed)
  handle_message(by, fn(_) { True }, state, message)
}

pub fn from_list(values: List(t)) -> Stream(t) {
  let gen: Stream(#(List(t), t)) = case values {
    [] -> EmptyGenerator
    [first, ..res] ->
      generate_until(
        id(#(res, first)),
        fn(x) {
          let #(values, _) = x
          let assert [next, ..res] = values
          #(res, next)
        },
        fn(x) {
          let #(values, _) = x
          case values {
            [_, ..] -> False
            _ -> True
          }
        },
      )
  }

  use #(_, cur) <- map(gen)
  cur
}

fn assert_some(item: Option(t)) -> t {
  let assert Some(item) = item
  item
}

pub fn map(from: Stream(t), by: fn(t) -> r) -> Stream(r) {
  case has_next(from) {
    False -> EmptyGenerator
    True -> {
      generate_until(
        next(from) |> assert_some() |> by() |> id(),
        fn(_) { next(from) |> assert_some() |> by() },
        fn(_) { has_next(from) |> bool.negate() },
      )
    }
  }
}

pub fn empty() -> Stream(t) {
  EmptyGenerator
}

pub fn until(from: Stream(t), until: fn(t) -> Bool) {
  use first <- map_unwrap(next(from), id(EmptyGenerator))
  generate_until(id(first), fn(_) { next(from) |> assert_some() }, until)
}

pub fn copy(original: Stream(t)) -> Stream(t) {
  case original {
    EmptyGenerator -> EmptyGenerator
    TrueGenerator(_, _, handle, seed) -> {
      create(seed, handle)
    }
  }
}

fn next_match(from: Stream(t), keeping predicate: fn(t) -> Bool) -> Option(t) {
  use x <- map_unwrap(next(from), id(None))
  case predicate(x) {
    True -> Some(x)
    False -> next_match(from, predicate)
  }
}

pub fn filter(from: Stream(t), keeping predicate: fn(t) -> Bool) {
  let next_val = fn() { next_match(from, predicate) }
  let intermediate = {
    use first <- map_unwrap(next_val(), id(EmptyGenerator))
    generate_until(
      fn() { #(first, next_val()) },
      fn(a) {
        let assert #(_, Some(cur)) = a
        #(cur, next_val())
      },
      fn(a) {
        let #(_, next) = a
        option.is_none(next)
      },
    )
  }

  use #(cur, _) <- map(intermediate)
  cur
}

pub fn fold(
  over stream: Stream(t),
  from initial: acc,
  with fun: fn(acc, t) -> acc,
) -> acc {
  stream
  |> next()
  |> option.map(fun(initial, _))
  |> option.map(fold(stream, _, fun))
  |> option.unwrap(initial)
}

pub fn to_list(from: Stream(t)) -> List(t) {
  from |> fold([], list.prepend) |> list.reverse
}

fn map_unwrap(option: Option(t), or or: fn() -> r, by by: fn(t) -> r) -> r {
  option
  |> option.map(by)
  |> option.lazy_unwrap(or)
}

fn indexed(stream: Stream(a)) -> Stream(#(a, Int)) {
  use first <- map_unwrap(next(stream), empty)
  use #(_, last_index) <- generate_until(fn() { #(first, 0) }, until: fn(_) {
    has_next(stream) |> bool.negate()
  })
  let assert Some(val) = next(stream)
  #(val, last_index + 1)
}

pub fn drop_while(
  in stream: Stream(a),
  satisfying predicate: fn(a) -> Bool,
) -> Stream(a) {
  use first <- map_unwrap(
    next_match(stream, fn(x) { x |> predicate() |> bool.negate() }),
    empty,
  )
  use _ <- generate_until(seed: id(first), until: fn(_) {
    has_next(stream) |> bool.negate()
  })
  let assert Some(val) = next(stream)
  val
}

pub fn drop(from stream: Stream(a), up_to n: Int) -> Stream(a) {
  let intermediate = {
    use #(_, index) <- drop_while(indexed(stream))
    index < n
  }
  use #(val, _) <- map(intermediate)
  val
}

pub fn flat_map(
  from stream: Stream(Int),
  by fun: fn(Int) -> Stream(Int),
) -> Stream(Int) {
  stream |> map(fun) |> flatten()
}

pub fn flatten(streams: Stream(Stream(Int))) -> Stream(Int) {
  let next_stream = fn() { next_match(streams, has_next) }
  use first_generator <- map_unwrap(next_stream(), empty)

  let intermediate =
    generate_until(
      fn() {
        let assert Some(first_val) = next(first_generator)
        #(first_val, first_generator, next_stream())
      },
      fn(x) {
        let #(_, cur_stream, next_maybe) = x

        use <- map_unwrap(next(cur_stream), by: fn(val) {
          #(val, cur_stream, next_maybe)
        })
        let assert Some(cur_stream) = next_maybe
        let assert Some(val) = next(cur_stream)
        #(val, cur_stream, next_stream())
      },
      fn(x) {
        let #(_, cur_stream, next_maybe) = x
        let has_some =
          has_next(cur_stream)
          || next_maybe |> option.map(has_next) |> option.unwrap(False)
        has_some |> bool.negate
      },
    )
  use #(val, _, _) <- map(intermediate)
  val
}
