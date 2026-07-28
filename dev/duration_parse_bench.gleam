import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleamy/bench

pub fn main() {
  let inputs =
    [
      "P1W",
      "P1D",
      "PT1H",
      "PT30M",
      "PT1H30M",
      "P1DT2H3M4S",
      "-PT30M",
      "P2H2H",
    ]
    |> list.repeat(100)
    |> list.flatten

  let functions = [
    #("pattern_matching", duration_components),
    #("pattern_matching_ascii", ascii_duration_components),
  ]

  bench.run(
    [bench.Input(list.length(inputs) |> int.to_string, inputs)],
    list.map(functions, fn(fun) { bench.Function(fun.0, parse_all(fun.1)) }),
    [],
  )
  |> bench.table([bench.IPS, bench.Min, bench.P(99)])
  |> io.println()
}

fn parse_all(
  pattern_matching: fn(String) -> Result(List(DurationComponent), Nil),
) -> fn(List(String)) -> Nil {
  fn(input) { list.each(input, pattern_matching) }
}

type DurationComponent {
  Week(Int)
  Day(Int)
  Hour(Int)
  Minute(Int)
  Second(Int)
}

fn duration_components(input: String) -> Result(List(DurationComponent), Nil) {
  do_duration_components_loop(bit_array.from_string(input), 0, False, [])
}

fn do_duration_components_loop(
  input: BitArray,
  acc: Int,
  has_digits: Bool,
  result: List(DurationComponent),
) -> Result(List(DurationComponent), Nil) {
  case input, has_digits {
    // we reached the end but have accumulated a value
    <<>>, True -> Error(Nil)
    <<>>, False -> Ok(list.reverse(result))

    <<"0", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 0, True, result)
    <<"1", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 1, True, result)
    <<"2", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 2, True, result)
    <<"3", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 3, True, result)
    <<"4", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 4, True, result)
    <<"5", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 5, True, result)
    <<"6", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 6, True, result)
    <<"7", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 7, True, result)
    <<"8", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 8, True, result)
    <<"9", rest:bits>>, _ ->
      do_duration_components_loop(rest, acc * 10 + 9, True, result)

    // a duration cannot end with a T
    <<"T">>, _ -> Error(Nil)
    // T cannot follow a number; it is only a separator before time units
    <<"T", _:bits>>, True -> Error(Nil)
    <<"T", rest:bits>>, False ->
      do_duration_components_loop(rest, 0, False, result)

    // ----- handle units
    <<"D", rest:bits>>, True ->
      do_duration_components_loop(rest, 0, False, [Day(acc), ..result])
    <<"H", rest:bits>>, True ->
      do_duration_components_loop(rest, 0, False, [Hour(acc), ..result])
    <<"M", rest:bits>>, True ->
      do_duration_components_loop(rest, 0, False, [Minute(acc), ..result])
    <<"S", rest:bits>>, True ->
      do_duration_components_loop(rest, 0, False, [Second(acc), ..result])
    <<"W", rest:bits>>, True ->
      do_duration_components_loop(rest, 0, False, [Week(acc), ..result])

    _, _ -> Error(Nil)
  }
}

fn ascii_duration_components(
  input: String,
) -> Result(List(DurationComponent), Nil) {
  do_ascii_duration_components_loop(bit_array.from_string(input), 0, False, [])
}

fn do_ascii_duration_components_loop(
  input: BitArray,
  acc: Int,
  has_digits: Bool,
  result: List(DurationComponent),
) -> Result(List(DurationComponent), Nil) {
  case input, has_digits {
    // we reached the end but have accumulated a value
    <<>>, True -> Error(Nil)
    <<>>, False -> Ok(list.reverse(result))

    <<48, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 0, True, result)
    <<49, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 1, True, result)
    <<50, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 2, True, result)
    <<51, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 3, True, result)
    <<52, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 4, True, result)
    <<53, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 5, True, result)
    <<54, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 6, True, result)
    <<55, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 7, True, result)
    <<56, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 8, True, result)
    <<57, rest:bits>>, _ ->
      do_ascii_duration_components_loop(rest, acc * 10 + 9, True, result)

    // a duration cannot end with a T
    <<84>>, _ -> Error(Nil)
    // T cannot follow a number; it is only a separator before time units
    <<84, _:bits>>, True -> Error(Nil)
    <<84, rest:bits>>, False ->
      do_ascii_duration_components_loop(rest, 0, False, result)

    // ----- handle units
    <<68, rest:bits>>, True ->
      do_ascii_duration_components_loop(rest, 0, False, [Day(acc), ..result])
    <<72, rest:bits>>, True ->
      do_ascii_duration_components_loop(rest, 0, False, [Hour(acc), ..result])
    <<77, rest:bits>>, True ->
      do_ascii_duration_components_loop(rest, 0, False, [Minute(acc), ..result])
    <<83, rest:bits>>, True ->
      do_ascii_duration_components_loop(rest, 0, False, [Second(acc), ..result])
    <<87, rest:bits>>, True ->
      do_ascii_duration_components_loop(rest, 0, False, [Week(acc), ..result])

    _, _ -> Error(Nil)
  }
}
