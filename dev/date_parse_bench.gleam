import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import gleamy/bench

pub fn main() {
  let inputs = generate_dates(10_000)

  let functions = [
    #("pattern_matching", pattern_matching),
    #("integer_parsing", integer_parse),
  ]

  check_implementations(inputs, functions)

  bench.run(
    [bench.Input("10000", inputs)],
    list.map(functions, fn(fun) { bench.Function(fun.0, parse_all(fun.1)) }),
    [],
  )
  |> bench.table([bench.IPS, bench.Min, bench.P(99)])
  |> io.println()
}

fn generate_dates(number) -> List(String) {
  let inputs =
    int.range(0, number, [], fn(acc, _) {
      let year = int.random(100) + 1950
      let month = int.random(12) + 1
      let day = int.random(28) + 1

      let date =
        list.map([year, month, day], fn(x) {
          int.to_string(x)
          |> string.pad_start(2, "0")
        })
        |> string.concat
      [date, ..acc]
    })
  inputs
}

fn check_implementations(
  inputs: List(String),
  functions: List(#(String, fn(String) -> Result(timestamp.Timestamp, String))),
) -> Nil {
  list.each(inputs, fn(input) {
    case
      list.map(functions, fn(fun) {
        fun.1(input)
        |> result.map(fn(x) { #(fun.0, x) })
        |> result.map_error(fn(x) { #(fun.0, x) })
      })
      |> result.all
    {
      Ok(_) -> Nil
      Error(errors) -> {
        echo errors as input
        Nil
      }
    }
  })
}

fn integer_parse(string: String) -> Result(timestamp.Timestamp, String) {
  case int.parse(string) {
    Ok(value) -> {
      let year = value / 10_000
      let month = { value % 10_000 } / 100
      let day = value % 100

      case calendar.month_from_int(month) {
        Ok(month_enum) -> {
          let date = calendar.Date(year, month_enum, day)
          case calendar.is_valid_date(date) {
            True ->
              Ok(timestamp.from_calendar(
                date,
                calendar.TimeOfDay(0, 0, 0, 0),
                calendar.utc_offset,
              ))
            False -> Error("Invalid date")
          }
        }
        Error(_) -> Error("Invalid date")
      }
    }

    Error(_) -> Error("Invalid date")
  }
}

fn parse_all(
  pattern_matching: fn(String) -> Result(timestamp.Timestamp, String),
) -> fn(List(String)) -> Nil {
  fn(input) { list.each(input, pattern_matching) }
}

fn pattern_matching(value: String) -> Result(timestamp.Timestamp, String) {
  case bit_array.from_string(value) {
    <<y1, y2, y3, y4, m1, m2, d1, d2>>
      if y1 >= 48
      && y1 <= 57
      && y2 >= 48
      && y2 <= 57
      && y3 >= 48
      && y3 <= 57
      && y4 >= 48
      && y4 <= 57
      && m1 >= 48
      && m1 <= 57
      && m2 >= 48
      && m2 <= 57
      && d1 >= 48
      && d1 <= 57
      && d2 >= 48
      && d2 <= 57
    -> {
      let year =
        { y1 - 48 } * 1000 + { y2 - 48 } * 100 + { y3 - 48 } * 10 + { y4 - 48 }
      let month = { m1 - 48 } * 10 + { m2 - 48 }
      let day = { d1 - 48 } * 10 + { d2 - 48 }

      case calendar.month_from_int(month) {
        Ok(month_enum) -> {
          let date = calendar.Date(year, month_enum, day)
          case calendar.is_valid_date(date) {
            True ->
              Ok(timestamp.from_calendar(
                date,
                calendar.TimeOfDay(0, 0, 0, 0),
                calendar.utc_offset,
              ))
            False -> Error("Invalid date")
          }
        }
        Error(_) -> Error("Invalid month")
      }
    }
    _ -> Error("Invalid date format")
  }
}
