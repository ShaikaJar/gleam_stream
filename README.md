# stream

[![Package Version](https://img.shields.io/hexpm/v/stream)](https://hex.pm/packages/gleam_stream)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gleam_stream/)

```sh
gleam add stream@1
```
```gleam
import stream.{from_list,map,to_list,each}

pub fn main() -> Nil {
  let stream = from_list([1,2,3,4,5,6,7])
  |> map(fn(x){x+10})
  |>to_list
  use x <- each(stream)
  io.println("Value "<>int.to_string(x))
}
```

Further documentation can be found at <https://hexdocs.pm/stream>.

## Development

```sh
gleam test  # Run the tests
```
