import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleamy/bench

type ParseResult =
  Result(#(calendar.Date, calendar.TimeOfDay), String)

pub fn main() {
  let inputs = make_test_inputs()

  bench.run(
    [bench.Input("mixed", inputs)],
    [
      bench.Function("string_slice", parse_all(parse_string_slice)),
      bench.Function("bit_array", parse_all(parse_bit_array)),
      bench.Function("pop_grapheme", parse_all(parse_pop_grapheme)),
    ],
    [bench.Duration(1000), bench.Warmup(100)],
  )
  |> bench.table([bench.IPS, bench.Min, bench.P(99)])
  |> io.println()
}

fn parse_all(parser) {
  fn(inputs) { list.map(inputs, parser) }
}

fn make_test_inputs() -> List(String) {
  [
    "20230101T100000",
    "20230615T143022",
    "20231231T235959",
    "20230228T120000",
    "20240229T120000",
    "20230101t100000",
    "20231301T100000",
    "20230132T100000",
    "20230101T250000",
    "20230101T106000",
    "20230101T100060",
    "not-a-datetime",
    "20230101",
    "20230101T1000",
    "20230101T10000",
    "",
    "20230101T1000000",
    "20230101X100000",
    "abcdefghijklmno",
    "123456789012345",
  ]
}

fn parse_string_slice(value: String) -> ParseResult {
  case string.length(value) {
    15 -> {
      let year =
        int.parse(string.slice(value, 0, 4))
        |> result.replace_error(Error("invalid year"))
      let month =
        int.parse(string.slice(value, 4, 2))
        |> result.replace_error(Error("invalid month"))
      let day =
        int.parse(string.slice(value, 6, 2))
        |> result.replace_error(Error("invalid day"))
      let hours =
        int.parse(string.slice(value, 9, 2))
        |> result.replace_error(Error("invalid hours"))
      let minutes =
        int.parse(string.slice(value, 11, 2))
        |> result.replace_error(Error("invalid minutes"))
      let seconds =
        int.parse(string.slice(value, 13, 2))
        |> result.replace_error(Error("invalid seconds"))

      case year, month, day, hours, minutes, seconds {
        Ok(y), Ok(m), Ok(d), Ok(h), Ok(min), Ok(s) -> {
          case calendar.month_from_int(m) {
            Ok(month_enum) -> {
              let date = calendar.Date(y, month_enum, d)
              case calendar.is_valid_date(date) {
                True -> {
                  let time = calendar.TimeOfDay(h, min, s, 0)
                  case calendar.is_valid_time_of_day(time) {
                    True -> Ok(#(date, time))
                    False -> Error("invalid time of day")
                  }
                }
                False -> Error("invalid date")
              }
            }
            Error(_) -> Error("invalid month")
          }
        }
        _, _, _, _, _, _ -> Error("invalid component")
      }
    }
    _ -> Error("wrong length")
  }
}

fn parse_bit_array(value: String) -> ParseResult {
  case bit_array.from_string(value) {
    <<y1, y2, y3, y4, m1, m2, d1, d2, t, h1, h2, min1, min2, s1, s2>>
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
      && t >= 48
      && h1 >= 48
      && h1 <= 57
      && h2 >= 48
      && h2 <= 57
      && min1 >= 48
      && min1 <= 57
      && min2 >= 48
      && min2 <= 57
      && s1 >= 48
      && s1 <= 57
      && s2 >= 48
      && s2 <= 57
    -> {
      case t == 84 || t == 116 {
        False -> Error("invalid separator")
        True -> {
          let y1v = y1 - 48
          let y2v = y2 - 48
          let y3v = y3 - 48
          let y4v = y4 - 48
          let m1v = m1 - 48
          let m2v = m2 - 48
          let d1v = d1 - 48
          let d2v = d2 - 48
          let h1v = h1 - 48
          let h2v = h2 - 48
          let min1v = min1 - 48
          let min2v = min2 - 48
          let s1v = s1 - 48
          let s2v = s2 - 48
          let year = y1v * 1000 + y2v * 100 + y3v * 10 + y4v
          let month = m1v * 10 + m2v
          let day = d1v * 10 + d2v
          let hours = h1v * 10 + h2v
          let minutes = min1v * 10 + min2v
          let seconds = s1v * 10 + s2v

          case calendar.month_from_int(month) {
            Ok(month_enum) -> {
              let date = calendar.Date(year, month_enum, day)
              case calendar.is_valid_date(date) {
                True -> {
                  let time = calendar.TimeOfDay(hours, minutes, seconds, 0)
                  case calendar.is_valid_time_of_day(time) {
                    True -> Ok(#(date, time))
                    False -> Error("invalid time of day")
                  }
                }
                False -> Error("invalid date")
              }
            }
            Error(_) -> Error("invalid month")
          }
        }
      }
    }
    _ -> Error("invalid format")
  }
}

fn parse_pop_grapheme(value: String) -> ParseResult {
  case string.pop_grapheme(value) {
    Ok(#(y1s, rest1)) -> pop1(rest1, y1s)
    Error(_) -> Error("empty")
  }
}

fn pop1(rest: String, y1s: String) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(y2s, rest)) -> pop2(rest, y1s, y2s)
    Error(_) -> Error("too short")
  }
}

fn pop2(rest: String, y1s: String, y2s: String) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(y3s, rest)) -> pop3(rest, y1s, y2s, y3s)
    Error(_) -> Error("too short")
  }
}

fn pop3(rest: String, y1s: String, y2s: String, y3s: String) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(y4s, rest)) -> pop4(rest, y1s, y2s, y3s, y4s)
    Error(_) -> Error("too short")
  }
}

fn pop4(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(m1s, rest)) -> pop5(rest, y1s, y2s, y3s, y4s, m1s)
    Error(_) -> Error("too short")
  }
}

fn pop5(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(m2s, rest)) -> pop6(rest, y1s, y2s, y3s, y4s, m1s, m2s)
    Error(_) -> Error("too short")
  }
}

fn pop6(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(d1s, rest)) -> pop7(rest, y1s, y2s, y3s, y4s, m1s, m2s, d1s)
    Error(_) -> Error("too short")
  }
}

fn pop7(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
  d1s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(d2s, rest)) -> pop8(rest, y1s, y2s, y3s, y4s, m1s, m2s, d1s, d2s)
    Error(_) -> Error("too short")
  }
}

fn pop8(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
  d1s: String,
  d2s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(sep, rest)) -> pop9(rest, y1s, y2s, y3s, y4s, m1s, m2s, d1s, d2s, sep)
    Error(_) -> Error("too short")
  }
}

fn pop9(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
  d1s: String,
  d2s: String,
  sep: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(h1s, rest)) ->
      pop10(rest, y1s, y2s, y3s, y4s, m1s, m2s, d1s, d2s, sep, h1s)
    Error(_) -> Error("too short")
  }
}

fn pop10(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
  d1s: String,
  d2s: String,
  sep: String,
  h1s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(h2s, rest)) ->
      pop11(rest, y1s, y2s, y3s, y4s, m1s, m2s, d1s, d2s, sep, h1s, h2s)
    Error(_) -> Error("too short")
  }
}

fn pop11(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
  d1s: String,
  d2s: String,
  sep: String,
  h1s: String,
  h2s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(min1s, rest)) ->
      pop12(rest, y1s, y2s, y3s, y4s, m1s, m2s, d1s, d2s, sep, h1s, h2s, min1s)
    Error(_) -> Error("too short")
  }
}

fn pop12(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
  d1s: String,
  d2s: String,
  sep: String,
  h1s: String,
  h2s: String,
  min1s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(min2s, rest)) ->
      pop13(
        rest,
        y1s,
        y2s,
        y3s,
        y4s,
        m1s,
        m2s,
        d1s,
        d2s,
        sep,
        h1s,
        h2s,
        min1s,
        min2s,
      )
    Error(_) -> Error("too short")
  }
}

fn pop13(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
  d1s: String,
  d2s: String,
  sep: String,
  h1s: String,
  h2s: String,
  min1s: String,
  min2s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(s1s, rest)) ->
      pop14(
        rest,
        y1s,
        y2s,
        y3s,
        y4s,
        m1s,
        m2s,
        d1s,
        d2s,
        sep,
        h1s,
        h2s,
        min1s,
        min2s,
        s1s,
      )
    Error(_) -> Error("too short")
  }
}

fn pop14(
  rest: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
  d1s: String,
  d2s: String,
  sep: String,
  h1s: String,
  h2s: String,
  min1s: String,
  min2s: String,
  s1s: String,
) -> ParseResult {
  case string.pop_grapheme(rest) {
    Ok(#(s2s, rest15)) ->
      build_result(
        rest15,
        y1s,
        y2s,
        y3s,
        y4s,
        m1s,
        m2s,
        d1s,
        d2s,
        sep,
        h1s,
        h2s,
        min1s,
        min2s,
        s1s,
        s2s,
      )
    Error(_) -> Error("too short")
  }
}

fn build_result(
  rest15: String,
  y1s: String,
  y2s: String,
  y3s: String,
  y4s: String,
  m1s: String,
  m2s: String,
  d1s: String,
  d2s: String,
  sep: String,
  h1s: String,
  h2s: String,
  min1s: String,
  min2s: String,
  s1s: String,
  s2s: String,
) -> ParseResult {
  case rest15 == "" {
    True -> {
      case sep == "T" || sep == "t" {
        True -> {
          let y1 = char_to_int(y1s)
          let y2 = char_to_int(y2s)
          let y3 = char_to_int(y3s)
          let y4 = char_to_int(y4s)
          let m1 = char_to_int(m1s)
          let m2 = char_to_int(m2s)
          let d1 = char_to_int(d1s)
          let d2 = char_to_int(d2s)
          let h1 = char_to_int(h1s)
          let h2 = char_to_int(h2s)
          let min1 = char_to_int(min1s)
          let min2 = char_to_int(min2s)
          let s1 = char_to_int(s1s)
          let s2 = char_to_int(s2s)

          let year = y1 * 1000 + y2 * 100 + y3 * 10 + y4
          let month = m1 * 10 + m2
          let day = d1 * 10 + d2
          let hours = h1 * 10 + h2
          let minutes = min1 * 10 + min2
          let seconds = s1 * 10 + s2

          case calendar.month_from_int(month) {
            Ok(month_enum) -> {
              let date = calendar.Date(year, month_enum, day)
              case calendar.is_valid_date(date) {
                True -> {
                  let time = calendar.TimeOfDay(hours, minutes, seconds, 0)
                  case calendar.is_valid_time_of_day(time) {
                    True -> Ok(#(date, time))
                    False -> Error("invalid time of day")
                  }
                }
                False -> Error("invalid date")
              }
            }
            Error(_) -> Error("invalid month")
          }
        }
        False -> Error("invalid separator")
      }
    }
    False -> Error("trailing content")
  }
}

fn char_to_int(s: String) -> Int {
  case string.pop_grapheme(s) {
    Ok(#(c, _)) ->
      case string.to_utf_codepoints(c) {
        [cp] -> string.utf_codepoint_to_int(cp) - 48
        _ -> 0
      }
    Error(_) -> 0
  }
}
