import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import gtz
import splitter

pub type Calendar {
  Calendar(
    version: String,
    prodid: String,
    timezone: String,
    events: List(Event),
  )
}

pub type Event {
  Event(
    uid: String,
    summary: String,
    dtstart: timestamp.Timestamp,
    dtend: timestamp.Timestamp,
    is_all_day: Bool,
    raw: List(Property),
  )
}

pub type Property {
  Property(name: String, params: List(Parameter), value: String)
}

pub type Parameter {
  Parameter(name: String, value: String)
}

pub type Error {
  ParseError(String)
}

type Component {
  Component(kind: String, properties: List(Property), children: List(Component))
}

pub type Splitters {
  Splitters(
    lines: splitter.Splitter,
    begin: splitter.Splitter,
    colon: splitter.Splitter,
    semi: splitter.Splitter,
    eq: splitter.Splitter,
    ws: splitter.Splitter,
    t_sep: splitter.Splitter,
  )
}

pub fn parse(input: String) -> Result(Calendar, Error) {
  parse_with_timezone(input, "")
}

pub fn parse_with_timezone(
  input: String,
  tz: String,
) -> Result(Calendar, Error) {
  let splitters =
    Splitters(
      lines: splitter.new(["\r\n", "\n"]),
      begin: splitter.new(["BEGIN:"]),
      colon: splitter.new([":"]),
      semi: splitter.new([";"]),
      eq: splitter.new(["="]),
      ws: splitter.new([" ", "\t"]),
      t_sep: splitter.new(["T", "t"]),
    )

  let lines = unfold_lines(input, splitters)
  let non_empty = list.filter(lines, fn(line) { line != "" })

  case parse_all_components(non_empty, [], splitters) {
    Ok(components) -> build_calendar(components, tz, splitters)
    Error(err) -> Error(err)
  }
}

fn unfold_lines(input: String, splitters: Splitters) -> List(String) {
  do_unfold_lines(input, splitters, [])
  |> list.reverse
}

fn do_unfold_lines(
  input: String,
  splitters: Splitters,
  acc: List(String),
) -> List(String) {
  case splitter.split(splitters.lines, input) {
    #(line, "", "") ->
      case acc {
        [] -> [line]
        [prev, ..rest] ->
          case string.starts_with(line, " ")
            || string.starts_with(line, "\t")
          {
            True -> {
              let #(_, remaining) =
                splitter.split_after(splitters.ws, line)
              [prev <> remaining, ..rest]
            }
            False -> [line, prev, ..rest]
          }
      }
    #(line, _, remaining) ->
      case acc {
        [] -> do_unfold_lines(remaining, splitters, [line])
        [prev, ..rest] ->
          case string.starts_with(line, " ")
            || string.starts_with(line, "\t")
          {
            True -> {
              let #(_, remaining_line) =
                splitter.split_after(splitters.ws, line)
              do_unfold_lines(remaining, splitters, [
                prev <> remaining_line,
                ..rest,
              ])
            }
            False ->
              do_unfold_lines(remaining, splitters, [line, prev, ..rest])
          }
      }
  }
}

fn parse_all_components(
  lines: List(String),
  acc: List(Component),
  splitters: Splitters,
) -> Result(List(Component), Error) {
  case lines {
    [] -> Ok(list.reverse(acc))
    [line, ..rest] ->
      case splitter.split(splitters.begin, line) {
        #("", "BEGIN:", kind) ->
          case parse_component(kind, rest, [], [], splitters) {
            Ok(#(component, remaining)) ->
              parse_all_components(
                remaining,
                [component, ..acc],
                splitters,
              )
            Error(err) -> Error(err)
          }
        _ -> Error(ParseError("Unexpected line: " <> line))
      }
  }
}

fn parse_component(
  kind: String,
  lines: List(String),
  props: List(Property),
  children: List(Component),
  splitters: Splitters,
) -> Result(#(Component, List(String)), Error) {
  let end_marker = "END:" <> kind
  case lines {
    [] -> Error(ParseError("Unexpected end of input, missing END:" <> kind))
    [line, ..rest] ->
      case line == end_marker {
        True ->
          Ok(#(
            Component(
              kind,
              list.reverse(props),
              list.reverse(children),
            ),
            rest,
          ))
        False ->
          case splitter.split(splitters.begin, line) {
            #("", "BEGIN:", subkind) ->
              case parse_component(subkind, rest, [], [], splitters) {
                Ok(#(child, remaining)) ->
                  parse_component(
                    kind,
                    remaining,
                    props,
                    [child, ..children],
                    splitters,
                  )
                Error(err) -> Error(err)
              }
            _ ->
              case parse_property(line, splitters) {
                Ok(prop) ->
                  parse_component(
                    kind,
                    rest,
                    [prop, ..props],
                    children,
                    splitters,
                  )
                Error(err) -> Error(err)
              }
          }
      }
  }
}

fn parse_property(
  line: String,
  splitters: Splitters,
) -> Result(Property, Error) {
  case splitter.split(splitters.colon, line) {
    #(name_part, ":", value) -> {
      let #(name, params) = parse_name_and_params(name_part, splitters)
      Ok(Property(name, params, unescape_text(value)))
    }
    _ -> Error(ParseError("Invalid property line: " <> line))
  }
}

fn parse_name_and_params(
  part: String,
  splitters: Splitters,
) -> #(String, List(Parameter)) {
  case splitter.split(splitters.semi, part) {
    #(name, ";", params_str) -> #(name, parse_params(params_str, splitters))
    _ -> #(part, [])
  }
}

fn parse_params(
  params_str: String,
  splitters: Splitters,
) -> List(Parameter) {
  do_parse_params(params_str, [], splitters)
}

fn do_parse_params(
  input: String,
  acc: List(Parameter),
  splitters: Splitters,
) -> List(Parameter) {
  case splitter.split(splitters.semi, input) {
    #(param, ";", remaining) ->
      case parse_single_param(param, splitters) {
        Ok(p) -> do_parse_params(remaining, [p, ..acc], splitters)
        Error(_) -> do_parse_params(remaining, acc, splitters)
      }
    #(param, "", "") ->
      case parse_single_param(param, splitters) {
        Ok(p) -> list.reverse([p, ..acc])
        Error(_) -> list.reverse(acc)
      }
    _ -> list.reverse(acc)
  }
}

fn parse_single_param(
  param: String,
  splitters: Splitters,
) -> Result(Parameter, Error) {
  case splitter.split(splitters.eq, param) {
    #(name, "=", value) -> Ok(Parameter(name, value))
    _ -> Error(ParseError("Invalid parameter: " <> param))
  }
}

fn unescape_text(text: String) -> String {
  text
  |> string.replace("\\n", "\n")
  |> string.replace("\\,", ",")
  |> string.replace("\\;", ";")
  |> string.replace("\\\\", "\\")
}

fn extract_prop(props: List(Property), name: String) -> String {
  props
  |> list.find(fn(p) { p.name == name })
  |> result.map(fn(p) { p.value })
  |> result.unwrap("")
}

fn has_param_value_date(params: List(Parameter)) -> Bool {
  params
  |> list.find(fn(p) { p.name == "VALUE" })
  |> result.map(fn(p) { p.value == "DATE" })
  |> result.unwrap(False)
}

fn get_tzid(params: List(Parameter)) -> Result(String, Error) {
  case list.find(params, fn(p) { p.name == "TZID" }) {
    Ok(p) -> Ok(p.value)
    Error(_) -> Error(ParseError("No TZID parameter"))
  }
}

fn parse_int(s: String) -> Result(Int, Error) {
  case int.parse(s) {
    Ok(n) -> Ok(n)
    Error(_) -> Error(ParseError("Not an integer: " <> s))
  }
}

fn parse_date_only(value: String) -> Result(timestamp.Timestamp, Error) {
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
                  Ok(
                    timestamp.from_calendar(
                      date,
                      calendar.TimeOfDay(0, 0, 0, 0),
                      calendar.utc_offset,
                    ),
                  )
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
  value: String,
  splitters: Splitters,
) -> Result(#(calendar.Date, calendar.TimeOfDay, Bool), Error) {
  case splitter.split(splitters.t_sep, value) {
    #(date_str, sep, time_str) ->
      case sep == "T" || sep == "t" {
        True -> {
          let year = parse_int(string.slice(date_str, 0, 4))
          let month = parse_int(string.slice(date_str, 4, 2))
          let day = parse_int(string.slice(date_str, 6, 2))

          let hours = parse_int(string.slice(time_str, 0, 2))
          let minutes = parse_int(string.slice(time_str, 2, 2))
          let seconds_raw =
            string.slice(time_str, 4, string.length(time_str) - 4)
          let seconds = parse_int(seconds_raw)

          case year, month, day, hours, minutes, seconds {
            Ok(y), Ok(m), Ok(d), Ok(h), Ok(min), Ok(s) -> {
              case calendar.month_from_int(m) {
                Ok(month_enum) -> {
                  let date = calendar.Date(y, month_enum, d)
                  case calendar.is_valid_date(date) {
                    True -> {
                      let time = calendar.TimeOfDay(h, min, s, 0)
                      case calendar.is_valid_time_of_day(time) {
                        True -> Ok(#(date, time, False))
                        False -> Error(ParseError("Invalid time"))
                      }
                    }
                    False -> Error(ParseError("Invalid date"))
                  }
                }
                Error(_) -> Error(ParseError("Invalid month"))
              }
            }
            _, _, _, _, _, _ ->
              Error(ParseError("Invalid datetime components"))
          }
        }
        False -> Error(ParseError("Missing T separator"))
      }
  }
}

@internal
pub fn parse_datetime(
  prop: Property,
  splitters: Splitters,
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
          let is_utc = string.ends_with(value, "Z") || string.ends_with(value, "z")

          let clean_value =
            case is_utc {
              True -> string.slice(value, 0, string.length(value) - 1)
              False -> value
            }

          case parse_datetime_value(clean_value, splitters) {
            Ok(#(date, time, _)) -> {
              let tzid =
                case is_utc {
                  True -> Error(ParseError("UTC"))
                  False -> get_tzid(prop.params)
                }

              case tzid {
                Ok(tz) -> {
                  let naive_ts =
                    timestamp.from_calendar(
                      date,
                      time,
                      calendar.utc_offset,
                    )
                  case gtz.calculate_offset(naive_ts, in: tz) {
                    Ok(offset) ->
                      timestamp.from_calendar(date, time, offset)
                    Error(_) ->
                      timestamp.from_calendar(
                        date,
                        time,
                        calendar.utc_offset,
                      )
                  }
                }
                Error(_) -> {
                  let tz_to_use =
                    case fallback_tz == "" {
                      True -> "UTC"
                      False -> fallback_tz
                    }
                  case tz_to_use == "UTC" {
                    True ->
                      timestamp.from_calendar(
                        date,
                        time,
                        calendar.utc_offset,
                      )
                    False -> {
                      let naive_ts =
                        timestamp.from_calendar(
                          date,
                          time,
                          calendar.utc_offset,
                        )
                      case gtz.calculate_offset(naive_ts, in: tz_to_use) {
                        Ok(offset) ->
                          timestamp.from_calendar(date, time, offset)
                        Error(_) ->
                          timestamp.from_calendar(
                            date,
                            time,
                            calendar.utc_offset,
                          )
                      }
                    }
                  }
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
  splitters: Splitters,
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
    |> result.map(fn(p) { parse_datetime(p, splitters, fallback_tz) })
    |> result.unwrap(timestamp.unix_epoch)
  let dtend =
    dtend_prop
    |> result.map(fn(p) { parse_datetime(p, splitters, fallback_tz) })
    |> result.unwrap(timestamp.unix_epoch)

  Event(uid, summary, dtstart, dtend, is_all_day, props)
}

fn build_calendar(
  components: List(Component),
  tz_override: String,
  splitters: Splitters,
) -> Result(Calendar, Error) {
  let flat =
    components
    |> list.map(fn(c) { #(c.kind, c.properties, c.children) })

  case list.find(flat, fn(c) { c.0 == "VCALENDAR" }) {
    Ok(#(_, cal_props, cal_children)) -> {
      let version = extract_prop(cal_props, "VERSION")
      let prodid = extract_prop(cal_props, "PRODID")

      let detected_tz =
        case tz_override == "" {
          True ->
            extract_prop(cal_props, "X-WR-TIMEZONE")
            |> fn(tz) {
              case tz == "" {
                True -> "UTC"
                False -> tz
              }
            }
          False -> tz_override
        }

      let events =
        cal_children
        |> list.filter_map(fn(c) {
          case c.kind {
            "VEVENT" -> Ok(build_event(c.properties, splitters, detected_tz))
            _ -> Error(Nil)
          }
        })

      Ok(Calendar(version, prodid, detected_tz, events))
    }
    Error(_) -> Error(ParseError("No VCALENDAR component found"))
  }
}
