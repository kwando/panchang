import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import splitter
import tzif/database
import tzif/tzcalendar

/// A parsed iCal calendar.
///
/// Contains the calendar version, producer ID, the timezone used for
/// resolving floating-time events, and a list of parsed events.
///
pub type Calendar {
  Calendar(
    /// The iCal version, typically `"2.0"`.
    version: String,
    /// The producer identifier, e.g. `"-//Apple Inc.//macOS 14.0//EN"`.
    prodid: String,
    /// The timezone used for resolving floating-time events. Either the
    /// value passed to `parse`, or `"UTC"` if `None` was provided.
    timezone: String,
    /// All parsed VEVENT components.
    events: List(Event),
  )
}

/// A single calendar event (VEVENT).
///
/// Common properties are extracted into named fields. All original properties
/// are preserved in `raw` for access to anything not explicitly parsed.
///
pub type Event {
  Event(
    /// The globally unique identifier for this event.
    uid: String,
    /// The event title. Empty string if not present.
    summary: String,
    /// The start time as an unambiguous timestamp. Returns `unix_epoch` if
    /// missing or unparseable.
    dtstart: timestamp.Timestamp,
    /// The end time as an unambiguous timestamp. Returns `unix_epoch` if
    /// missing or unparseable.
    dtend: timestamp.Timestamp,
    /// True when the event uses date-only values (`VALUE=DATE`), indicating
    /// an all-day event.
    is_all_day: Bool,
    /// All original properties for this event, including DTSTART, DTEND,
    /// LOCATION, DESCRIPTION, ATTENDEE, etc.
    raw: List(Property),
  )
}

/// A single iCal property line, consisting of a name, optional parameters,
/// and a value.
///
/// For example: `DTSTART;TZID=Europe/Stockholm:20230101T100000` becomes:
/// `Property("DTSTART", [Parameter("TZID", "Europe/Stockholm")], "20230101T100000")`
///
pub type Property {
  Property(name: String, params: List(Parameter), value: String)
}

/// A key-value parameter attached to a property.
///
/// Parameters appear before the colon in a property line, separated by
/// semicolons. For example, `TZID=Europe/Stockholm` in:
/// `DTSTART;TZID=Europe/Stockholm:20230101T100000`
///
pub type Parameter {
  Parameter(name: String, value: String)
}

/// An error that can occur during parsing.
pub type ParseError {
  /// The input could not be parsed. The string contains a description of
  /// what went wrong.
  ParseError(String)
}

type Component {
  Component(kind: String, properties: List(Property), children: List(Component))
}

/// A parser for iCal strings. Holds pre-built splitters for efficient
/// string parsing and a timezone database for resolving datetime values.
///
/// Create one with `new_parser` and reuse it across multiple parse calls.
///
pub opaque type Parser {
  Parser(
    lines: splitter.Splitter,
    ws: splitter.Splitter,
    t_sep: splitter.Splitter,
    db: database.TzDatabase,
  )
}

/// Create a new parser with the given timezone database.
///
/// ```gleam
/// import tzif/database
/// import gcal
///
/// let assert Ok(db) = database.load_from_os()
/// let parser = gcal.new_parser(db)
/// ```
///
pub fn new_parser(tz_db: database.TzDatabase) {
  Parser(
    lines: splitter.new(["\r\n", "\n"]),
    ws: splitter.new([" ", "\t"]),
    t_sep: splitter.new(["T", "t"]),
    db: tz_db,
  )
}

/// Parse an iCal string into a `Calendar`.
///
/// Floating-time events (those without a `Z` suffix or `TZID` parameter) are
/// resolved using the provided `timezone`, otherwise UTC.
///
/// Events with an explicit `TZID` parameter are always resolved using that
/// timezone, regardless of this argument.
///
/// ```gleam
/// import gcal
/// import gleam/option
/// import tzif/database
///
/// let assert Ok(db) = database.load_from_os()
/// let parser = gcal.new_parser(db)
///
/// // Use UTC for floating times
/// let assert Ok(calendar) = gcal.parse(parser, ical, option.None)
///
/// // Resolve floating times to a specific timezone
/// let assert Ok(calendar) =
///   gcal.parse(parser, ical, option.Some("Europe/Stockholm"))
/// ```
///
pub fn parse(
  parser: Parser,
  input: String,
  timezone: Option(String),
) -> Result(Calendar, ParseError) {
  let lines = unfold_lines(input, parser)
  let non_empty = list.filter(lines, fn(line) { line != "" })

  case parse_all_components(non_empty, []) {
    Ok(components) -> build_calendar(components, timezone, parser)
    Error(err) -> Error(err)
  }
}

fn unfold_lines(input: String, parser: Parser) -> List(String) {
  do_unfold_lines(input, parser, [])
  |> list.reverse
}

fn do_unfold_lines(
  input: String,
  parser: Parser,
  acc: List(String),
) -> List(String) {
  case splitter.split(parser.lines, input) {
    #(line, "", "") ->
      case acc {
        [] -> [line]
        [prev, ..rest] ->
          case string.starts_with(line, " ") || string.starts_with(line, "\t") {
            True -> {
              let #(_, remaining) = splitter.split_after(parser.ws, line)
              [prev <> remaining, ..rest]
            }
            False -> [line, prev, ..rest]
          }
      }
    #(line, _, remaining) ->
      case acc {
        [] -> do_unfold_lines(remaining, parser, [line])
        [prev, ..rest] ->
          case string.starts_with(line, " ") || string.starts_with(line, "\t") {
            True -> {
              let #(_, remaining_line) = splitter.split_after(parser.ws, line)
              do_unfold_lines(remaining, parser, [
                prev <> remaining_line,
                ..rest
              ])
            }
            False -> do_unfold_lines(remaining, parser, [line, prev, ..rest])
          }
      }
  }
}

fn parse_component_marker(line: String, prefix: String) -> Result(String, Nil) {
  case string.starts_with(string.uppercase(line), prefix) {
    True -> {
      let prefix_length = string.length(prefix)
      Ok(string.trim(string.drop_start(line, prefix_length)))
    }
    False -> Error(Nil)
  }
}

fn parse_begin_component(line: String) -> Result(String, Nil) {
  parse_component_marker(line, "BEGIN:")
}

fn parse_end_component(line: String) -> Result(String, Nil) {
  parse_component_marker(line, "END:")
}

fn parse_all_components(
  lines: List(String),
  acc: List(Component),
) -> Result(List(Component), ParseError) {
  case lines {
    [] -> Ok(list.reverse(acc))
    [line, ..rest] ->
      case parse_begin_component(line) {
        Ok(kind) ->
          case parse_component(string.uppercase(kind), rest, [], []) {
            Ok(#(component, remaining)) ->
              parse_all_components(remaining, [component, ..acc])
            Error(err) -> Error(err)
          }
        Error(_) -> Error(ParseError("Unexpected line: " <> line))
      }
  }
}

fn parse_component(
  kind: String,
  lines: List(String),
  props: List(Property),
  children: List(Component),
) -> Result(#(Component, List(String)), ParseError) {
  let kind = string.uppercase(kind)
  case lines {
    [] -> Error(ParseError("Unexpected end of input, missing END:" <> kind))
    [line, ..rest] ->
      case parse_end_component(line) {
        Ok(end_kind) ->
          case string.uppercase(end_kind) == kind {
            True ->
              Ok(#(
                Component(kind, list.reverse(props), list.reverse(children)),
                rest,
              ))
            False -> Error(ParseError("Unexpected END:" <> end_kind))
          }
        Error(_) ->
          case parse_begin_component(line) {
            Ok(subkind) ->
              case parse_component(string.uppercase(subkind), rest, [], []) {
                Ok(#(child, remaining)) ->
                  parse_component(kind, remaining, props, [child, ..children])
                Error(err) -> Error(err)
              }
            Error(_) ->
              case parse_property(line) {
                Ok(prop) ->
                  parse_component(kind, rest, [prop, ..props], children)
                Error(err) -> Error(err)
              }
          }
      }
  }
}

fn split_first_unquoted(
  line: String,
  sep: String,
) -> Result(#(String, String), Nil) {
  do_split_first_unquoted(string.to_graphemes(line), sep, False, False, [])
}

fn do_split_first_unquoted(
  chars: List(String),
  sep: String,
  in_quote: Bool,
  escaped: Bool,
  acc: List(String),
) -> Result(#(String, String), Nil) {
  case chars {
    [] -> Error(Nil)
    [char, ..rest] -> {
      case escaped {
        True ->
          do_split_first_unquoted(rest, sep, in_quote, False, [char, ..acc])
        False -> {
          case char {
            "\"" ->
              do_split_first_unquoted(rest, sep, !in_quote, False, [char, ..acc])
            "\\" if in_quote ->
              do_split_first_unquoted(rest, sep, in_quote, True, [char, ..acc])
            _ if char == sep && !in_quote -> {
              let before = list.reverse(acc) |> string.concat
              let after = string.concat(rest)
              Ok(#(before, after))
            }
            _ -> do_split_first_unquoted(rest, sep, in_quote, False, [char, ..acc])
          }
        }
      }
    }
  }
}

fn unescape_param_value(value: String) -> String {
  case string.starts_with(value, "\"") && string.ends_with(value, "\"") {
    False -> value
    True -> {
      let inner = string.slice(value, 1, string.length(value) - 2)
      do_unescape_param_text(string.to_graphemes(inner), [])
      |> list.reverse
      |> string.concat
    }
  }
}

fn do_unescape_param_text(chars: List(String), acc: List(String)) -> List(String) {
  case chars {
    [] -> acc
    ["\\", "\"", ..rest] -> do_unescape_param_text(rest, ["\"", ..acc])
    ["\\", "\\", ..rest] -> do_unescape_param_text(rest, ["\\", ..acc])
    [c, ..rest] -> do_unescape_param_text(rest, [c, ..acc])
  }
}

fn parse_property(line: String) -> Result(Property, ParseError) {
  case split_first_unquoted(line, ":") {
    Ok(#(name_part, value)) -> {
      let #(name, params) = parse_name_and_params(name_part)
      Ok(Property(string.uppercase(name), params, unescape_text(value)))
    }
    Error(_) -> Error(ParseError("Invalid property line: " <> line))
  }
}

fn parse_name_and_params(part: String) -> #(String, List(Parameter)) {
  case split_first_unquoted(part, ";") {
    Ok(#(name, params_str)) -> #(name, parse_params(params_str))
    Error(_) -> #(part, [])
  }
}

fn parse_params(params_str: String) -> List(Parameter) {
  do_parse_params(params_str, [])
}

fn do_parse_params(
  input: String,
  acc: List(Parameter),
) -> List(Parameter) {
  case split_first_unquoted(input, ";") {
    Ok(#(param, remaining)) ->
      case parse_single_param(param) {
        Ok(p) -> do_parse_params(remaining, [p, ..acc])
        Error(_) -> do_parse_params(remaining, acc)
      }
    Error(_) ->
      case parse_single_param(input) {
        Ok(p) -> list.reverse([p, ..acc])
        Error(_) -> list.reverse(acc)
      }
  }
}

fn parse_single_param(param: String) -> Result(Parameter, ParseError) {
  case split_first_unquoted(param, "=") {
    Ok(#(name, value)) ->
      Ok(Parameter(string.uppercase(name), unescape_param_value(value)))
    Error(_) -> Error(ParseError("Invalid parameter: " <> param))
  }
}

fn unescape_text(text: String) -> String {
  case
    text
    |> bit_array.from_string
    |> do_unescape_text(<<>>)
    |> bit_array.to_string
  {
    Ok(result) -> result
    Error(_) -> text
  }
}

fn do_unescape_text(input: BitArray, acc: BitArray) -> BitArray {
  case input {
    <<>> -> acc
    <<"\\":utf8, "n":utf8, rest:bytes>> ->
      do_unescape_text(rest, <<acc:bits, "\n":utf8>>)
    <<"\\":utf8, "N":utf8, rest:bytes>> ->
      do_unescape_text(rest, <<acc:bits, "\n":utf8>>)
    <<"\\":utf8, ",":utf8, rest:bytes>> ->
      do_unescape_text(rest, <<acc:bits, ",":utf8>>)
    <<"\\":utf8, ";":utf8, rest:bytes>> ->
      do_unescape_text(rest, <<acc:bits, ";":utf8>>)
    <<"\\":utf8, ":":utf8, rest:bytes>> ->
      do_unescape_text(rest, <<acc:bits, ":":utf8>>)
    <<"\\":utf8, "\\":utf8, rest:bytes>> ->
      do_unescape_text(rest, <<acc:bits, "\\":utf8>>)
    <<c:8, rest:bytes>> -> do_unescape_text(rest, <<acc:bits, c:8>>)
    _ -> <<acc:bits, input:bits>>
  }
}

/// Find a property by name in an event's raw properties.
///
/// Returns `Ok(Property)` if found, `Error(Nil)` otherwise.
///
/// ```gleam
/// let assert Ok(location_prop) = gcal.get_property(event, "LOCATION")
/// location_prop.value
/// ```
///
pub fn get_property(event: Event, name: String) -> Result(Property, Nil) {
  list.find(event.raw, fn(prop) { name_eq(prop.name, name) })
}

fn name_eq(a: String, b: String) -> Bool {
  string.uppercase(a) == string.uppercase(b)
}

/// Find a parameter value by name in a property's parameters.
///
/// Returns `Ok(String)` with the parameter value if found, `Error(Nil)`
/// otherwise.
///
/// ```gleam
/// let assert Ok(prop) = gcal.get_property(event, "DTSTART")
/// let assert Ok(tzid) = gcal.get_parameter(prop, "TZID")
/// ```
///
pub fn get_parameter(prop: Property, name: String) -> Result(String, Nil) {
  list.find_map(prop.params, fn(param) {
    case name_eq(param.name, name) {
      True -> Ok(param.value)
      False -> Error(Nil)
    }
  })
}

fn extract_prop(props: List(Property), name: String) -> String {
  props
  |> list.find(fn(p) { name_eq(p.name, name) })
  |> result.map(fn(p) { p.value })
  |> result.unwrap("")
}

fn has_param_value_date(params: List(Parameter)) -> Bool {
  list.any(params, fn(p) {
    name_eq(p.name, "VALUE") && string.uppercase(p.value) == "DATE"
  })
}

fn get_tzid(params: List(Parameter)) -> Result(String, ParseError) {
  case list.find(params, fn(p) { name_eq(p.name, "TZID") }) {
    Ok(p) -> Ok(p.value)
    Error(_) -> Error(ParseError("No TZID parameter"))
  }
}

fn parse_int(s: String) -> Result(Int, ParseError) {
  case int.parse(s) {
    Ok(n) -> Ok(n)
    Error(_) -> Error(ParseError("Not an integer: " <> s))
  }
}

fn parse_date_only(value: String) -> Result(timestamp.Timestamp, ParseError) {
  case string.length(value) {
    8 -> {
      let year = parse_int(string.slice(value, 0, 4))
      let month = parse_int(string.slice(value, 4, 2))
      let day = parse_int(string.slice(value, 6, 2))

      case year, month, day {
        Ok(y), Ok(m), Ok(d) -> {
          case calendar.month_from_int(m) {
            Ok(month_enum) -> {
              let date = calendar.Date(y, month_enum, d)
              case calendar.is_valid_date(date) {
                True ->
                  Ok(timestamp.from_calendar(
                    date,
                    calendar.TimeOfDay(0, 0, 0, 0),
                    calendar.utc_offset,
                  ))
                False -> Error(ParseError("Invalid date"))
              }
            }
            Error(_) -> Error(ParseError("Invalid month"))
          }
        }
        _, _, _ -> Error(ParseError("Invalid date components"))
      }
    }
    _ -> Error(ParseError("Date must be 8 characters"))
  }
}

fn parse_datetime_value(
  _parser: Parser,
  value: String,
) -> Result(#(calendar.Date, calendar.TimeOfDay), ParseError) {
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
        False -> Error(ParseError("Invalid T separator"))
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
                    False -> Error(ParseError("Invalid time"))
                  }
                }
                False -> Error(ParseError("Invalid date"))
              }
            }
            Error(_) -> Error(ParseError("Invalid month"))
          }
        }
      }
    }
    _ -> Error(ParseError("Invalid datetime format"))
  }
}

/// Parse a datetime property value into a `Timestamp`.
///
/// Handles these iCal datetime formats:
/// - UTC: `20230101T100000Z`
/// - Timezone-aware: `20230101T100000` with `TZID=Europe/Stockholm` parameter
/// - Date-only: `VALUE=DATE:20230101` (treated as midnight UTC)
/// - Floating: `20230101T100000` (resolved using `fallback_tz`, or UTC)
///
/// Returns `timestamp.unix_epoch` for empty or unparseable values.
///
@internal
pub fn parse_datetime(
  prop: Property,
  parser: Parser,
  fallback_tz: String,
) -> timestamp.Timestamp {
  let value = prop.value

  case value == "" {
    True -> timestamp.unix_epoch
    False -> {
      let is_date = has_param_value_date(prop.params)

      case is_date {
        True ->
          case parse_date_only(value) {
            Ok(ts) -> ts
            Error(_) -> timestamp.unix_epoch
          }
        False -> {
          let is_utc =
            string.ends_with(value, "Z") || string.ends_with(value, "z")

          let clean_value = case is_utc {
            True -> string.slice(value, 0, string.length(value) - 1)
            False -> value
          }

          case parse_datetime_value(parser, clean_value) {
            Ok(#(date, time)) -> {
              let tzid = case is_utc {
                True -> Error(ParseError("UTC"))
                False -> get_tzid(prop.params)
              }

              let tz_name = case tzid {
                Ok(tz) -> tz
                Error(_) ->
                  case fallback_tz == "" {
                    True -> "UTC"
                    False -> fallback_tz
                  }
              }

              case tz_name == "UTC" {
                True -> timestamp.from_calendar(date, time, calendar.utc_offset)
                False ->
                  case
                    tzcalendar.from_calendar(date, time, tz_name, parser.db)
                  {
                    Ok([ts]) -> ts
                    Ok([ts, ..]) -> ts
                    Ok([]) | Error(_) ->
                      timestamp.from_calendar(date, time, calendar.utc_offset)
                  }
              }
            }
            Error(_) -> timestamp.unix_epoch
          }
        }
      }
    }
  }
}

fn build_event(
  props: List(Property),
  parser: Parser,
  fallback_tz: String,
) -> Event {
  let uid = extract_prop(props, "UID")
  let summary = extract_prop(props, "SUMMARY")
  let dtstart_prop = list.find(props, fn(p) { p.name == "DTSTART" })
  let dtend_prop = list.find(props, fn(p) { p.name == "DTEND" })

  let is_all_day =
    dtstart_prop
    |> result.map(fn(p) { has_param_value_date(p.params) })
    |> result.unwrap(False)

  let dtstart =
    dtstart_prop
    |> result.map(fn(p) { parse_datetime(p, parser, fallback_tz) })
    |> result.unwrap(timestamp.unix_epoch)
  let dtend =
    dtend_prop
    |> result.map(fn(p) { parse_datetime(p, parser, fallback_tz) })
    |> result.unwrap(timestamp.unix_epoch)

  Event(uid, summary, dtstart, dtend, is_all_day, props)
}

fn build_calendar(
  components: List(Component),
  tz_override: Option(String),
  parser: Parser,
) -> Result(Calendar, ParseError) {
  let flat =
    components
    |> list.map(fn(c) { #(c.kind, c.properties, c.children) })

  case list.find(flat, fn(c) { c.0 == "VCALENDAR" }) {
    Ok(#(_, cal_props, cal_children)) -> {
      let version = extract_prop(cal_props, "VERSION")
      let prodid = extract_prop(cal_props, "PRODID")

      let detected_tz = case tz_override {
        Some("") | None -> {
          case extract_prop(cal_props, "X-WR-TIMEZONE") {
            "" -> "UTC"
            tz -> tz
          }
        }
        Some(tz) -> tz
      }

      let events =
        cal_children
        |> list.filter_map(fn(c) {
          case c.kind {
            "VEVENT" -> Ok(build_event(c.properties, parser, detected_tz))
            _ -> Error(Nil)
          }
        })

      Ok(Calendar(version, prodid, detected_tz, events))
    }
    Error(_) -> Error(ParseError("No VCALENDAR component found"))
  }
}
