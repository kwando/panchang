import gleam/bit_array
import gleam/io
import gleam/list
import gleam/string
import gleamy/bench

fn replace_unescape(text: String) -> String {
  let backslash_placeholder = "\u{0000}"

  text
  |> string.replace("\\\\", backslash_placeholder)
  |> string.replace("\\n", "\n")
  |> string.replace("\\N", "\n")
  |> string.replace("\\,", ",")
  |> string.replace("\\;", ";")
  |> string.replace("\\:", ":")
  |> string.replace(backslash_placeholder, "\\")
}

fn single_pass_unescape(text: String) -> String {
  case
    text
    |> bit_array.from_string
    |> do_single_pass_unescape(<<>>)
    |> bit_array.to_string
  {
    Ok(result) -> result
    Error(_) -> text
  }
}

fn do_single_pass_unescape(input: BitArray, acc: BitArray) -> BitArray {
  case input {
    <<>> -> acc
    <<"\\":utf8, "n":utf8, rest:bytes>> ->
      do_single_pass_unescape(rest, <<acc:bits, "\n":utf8>>)
    <<"\\":utf8, "N":utf8, rest:bytes>> ->
      do_single_pass_unescape(rest, <<acc:bits, "\n":utf8>>)
    <<"\\":utf8, ",":utf8, rest:bytes>> ->
      do_single_pass_unescape(rest, <<acc:bits, ",":utf8>>)
    <<"\\":utf8, ";":utf8, rest:bytes>> ->
      do_single_pass_unescape(rest, <<acc:bits, ";":utf8>>)
    <<"\\":utf8, ":":utf8, rest:bytes>> ->
      do_single_pass_unescape(rest, <<acc:bits, ":":utf8>>)
    <<"\\":utf8, "\\":utf8, rest:bytes>> ->
      do_single_pass_unescape(rest, <<acc:bits, "\\":utf8>>)
    <<c:8, rest:bytes>> -> do_single_pass_unescape(rest, <<acc:bits, c:8>>)
    _ -> <<acc:bits, input:bits>>
  }
}

fn sample_text(size: Int) -> String {
  let base =
    "Line 1\\nLine 2 with\\, comma\\; and \\: colon \\n \\N and \\ backslash "
  let repeats = size / string.length(base) + 1
  string.slice(string.repeat(base, repeats), 0, size)
}

pub fn main() {
  let inputs = [
    bench.Input("short", sample_text(100)),
    bench.Input("medium", sample_text(1000)),
    bench.Input("long", sample_text(10_000)),
    bench.Input("very_long", sample_text(100_000)),
  ]

  // Sanity check: both implementations produce identical output.
  list.each(inputs, fn(input) {
    let bench.Input(label, value) = input
    let a = replace_unescape(value)
    let b = single_pass_unescape(value)
    case a == b {
      True -> Nil
      False -> panic as { "Output mismatch for " <> label }
    }
  })

  let functions = [
    bench.Function("replace", replace_unescape),
    bench.Function("single_pass", single_pass_unescape),
  ]

  let results = bench.run(inputs, functions, [bench.Duration(1000)])

  io.println(bench.table(results, [bench.P(50), bench.Mean, bench.IPS]))
}
