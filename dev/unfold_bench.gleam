import gleam/bit_array
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleamy/bench
import splitter

pub fn main() {
  let inputs = [
    bench.Input("10 folds", folded_property(10)),
    bench.Input("100 folds", folded_property(100)),
    bench.Input("1,000 folds", folded_property(1000)),
    bench.Input("10,000 folds", folded_property(10_000)),
  ]

  list.each(inputs, fn(input) {
    let bench.Input(label, value) = input
    case splitter_unfold(value) == bit_array_unfold(value) {
      True -> Nil
      False -> panic as { "Output mismatch for " <> label }
    }
  })

  let functions = [
    bench.Function("splitter", splitter_unfold),
    bench.Function("bit_array", bit_array_unfold),
  ]
  let results = bench.run(inputs, functions, [bench.Duration(1000)])
  io.println(bench.table(results, [bench.P(50), bench.Mean, bench.IPS]))
}

fn folded_property(folds: Int) -> String {
  "BEGIN:VCALENDAR\r\nDESCRIPTION:"
  <> string.repeat("a\r\n ", folds)
  <> "end\r\nEND:VCALENDAR\r\n"
}

// The previous implementation concatenated the complete logical line for every
// continuation, which becomes quadratic as the number of folds grows.
fn splitter_unfold(input: String) -> String {
  let lines = splitter.new(["\r\n", "\n"])
  let ws = splitter.new([" ", "\t"])
  do_splitter_unfold(input, lines, ws, [])
  |> list.reverse
  |> string.join("\n")
}

fn do_splitter_unfold(
  input: String,
  lines: splitter.Splitter,
  ws: splitter.Splitter,
  acc: List(String),
) -> List(String) {
  case splitter.split(lines, input) {
    #(line, "", "") ->
      case acc {
        [] -> [line]
        [previous, ..rest] ->
          case string.starts_with(line, " ") || string.starts_with(line, "\t") {
            True -> {
              let #(_, continuation) = splitter.split_after(ws, line)
              [previous <> continuation, ..rest]
            }
            False -> [line, previous, ..rest]
          }
      }
    #(line, _, remaining) ->
      case acc {
        [] -> do_splitter_unfold(remaining, lines, ws, [line])
        [previous, ..rest] ->
          case string.starts_with(line, " ") || string.starts_with(line, "\t") {
            True -> {
              let #(_, continuation) = splitter.split_after(ws, line)
              do_splitter_unfold(remaining, lines, ws, [
                previous <> continuation,
                ..rest
              ])
            }
            False ->
              do_splitter_unfold(remaining, lines, ws, [line, previous, ..rest])
          }
      }
  }
}

fn bit_array_unfold(input: String) -> String {
  input
  |> bit_array.from_string
  |> do_bit_array_unfold(<<>>)
  |> bit_array.to_string
  |> result.unwrap("")
}

fn do_bit_array_unfold(input: BitArray, acc: BitArray) -> BitArray {
  case input {
    <<>> -> acc
    <<"\r\n", " ", rest:bytes>> | <<"\r\n", "\t", rest:bytes>> ->
      do_bit_array_unfold(rest, acc)
    <<"\n", " ", rest:bytes>> | <<"\n", "\t", rest:bytes>> ->
      do_bit_array_unfold(rest, acc)
    <<"\r\n", rest:bytes>> | <<"\n", rest:bytes>> ->
      do_bit_array_unfold(rest, <<acc:bits, "\n":utf8>>)
    <<byte:8, rest:bytes>> -> do_bit_array_unfold(rest, <<acc:bits, byte:8>>)
    _ -> <<acc:bits, input:bits>>
  }
}
