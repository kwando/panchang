import gleam/list
import gleam/result
import gleam/string

pub type Calendar {
  Calendar(
    version: String,
    prodid: String,
    properties: List(Property),
    events: List(Event),
  )
}

pub type Event {
  Event(properties: List(Property))
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

pub fn parse(input: String) -> Result(Calendar, Error) {
  let lines =
    input
    |> string.replace("\r\n", "\n")
    |> string.replace("\r", "\n")
    |> string.split("\n")
    |> unfold_lines
    |> list.filter(fn(line) { line != "" })

  case parse_all_components(lines, []) {
    Ok(components) -> build_calendar(components)
    Error(err) -> Error(err)
  }
}

fn unfold_lines(lines: List(String)) -> List(String) {
  lines
  |> list.fold([], fn(acc: List(String), line: String) {
    case acc {
      [] -> [line]
      [prev, ..rest] ->
        case string.starts_with(line, " ") || string.starts_with(line, "\t") {
          True ->
            case string.pop_grapheme(line) {
              Ok(#(_, remaining)) -> [prev <> remaining, ..rest]
              Error(_) -> [prev, ..acc]
            }
          False -> [line, prev, ..rest]
        }
    }
  })
  |> list.reverse
}

fn parse_all_components(
  lines: List(String),
  acc: List(Component),
) -> Result(List(Component), Error) {
  case lines {
    [] -> Ok(list.reverse(acc))
    ["BEGIN:" <> kind, ..rest] ->
      case parse_component(kind, rest, [], []) {
        Ok(#(component, remaining)) ->
          parse_all_components(remaining, [component, ..acc])
        Error(err) -> Error(err)
      }
    [line, ..] -> Error(ParseError("Unexpected line: " <> line))
  }
}

fn parse_component(
  kind: String,
  lines: List(String),
  props: List(Property),
  children: List(Component),
) -> Result(#(Component, List(String)), Error) {
  let end_marker = "END:" <> kind
  case lines {
    [] -> Error(ParseError("Unexpected end of input, missing END:" <> kind))
    [line, ..rest] ->
      case line == end_marker {
        True ->
          Ok(#(
            Component(kind, list.reverse(props), list.reverse(children)),
            rest,
          ))
        False ->
          case string.starts_with(line, "BEGIN:") {
            True -> {
              let subkind =
                case string.split_once(line, "BEGIN:") {
                  Ok(#(_, k)) -> k
                  Error(_) -> ""
                }
              case parse_component(subkind, rest, [], []) {
                Ok(#(child, remaining)) ->
                  parse_component(kind, remaining, props, [child, ..children])
                Error(err) -> Error(err)
              }
            }
            False ->
              case parse_property(line) {
                Ok(prop) ->
                  parse_component(kind, rest, [prop, ..props], children)
                Error(err) -> Error(err)
              }
          }
      }
  }
}

fn parse_property(line: String) -> Result(Property, Error) {
  case string.split_once(line, ":") {
    Ok(#(name_part, value)) -> {
      let #(name, params) = parse_name_and_params(name_part)
      Ok(Property(name, params, unescape_text(value)))
    }
    Error(_) -> Error(ParseError("Invalid property line: " <> line))
  }
}

fn parse_name_and_params(part: String) -> #(String, List(Parameter)) {
  case string.split_once(part, ";") {
    Ok(#(name, params_str)) -> #(name, parse_params(params_str))
    Error(_) -> #(part, [])
  }
}

fn parse_params(params_str: String) -> List(Parameter) {
  params_str
  |> string.split(";")
  |> list.filter_map(fn(param) {
    case string.split_once(param, "=") {
      Ok(#(name, value)) -> Ok(Parameter(name, value))
      Error(_) -> Error(Nil)
    }
  })
}

fn unescape_text(text: String) -> String {
  text
  |> string.replace("\\n", "\n")
  |> string.replace("\\,", ",")
  |> string.replace("\\;", ";")
  |> string.replace("\\\\", "\\")
}

fn flatten_components(
  components: List(Component),
) -> List(#(String, List(Property), List(Component))) {
  components
  |> list.map(fn(c) { #(c.kind, c.properties, c.children) })
}

fn build_calendar(
  components: List(Component),
) -> Result(Calendar, Error) {
  let flat = flatten_components(components)
  case list.find(flat, fn(c) { c.0 == "VCALENDAR" }) {
    Ok(#(_, cal_props, cal_children)) -> {
      let version =
        cal_props
        |> list.find(fn(p) { p.name == "VERSION" })
        |> result.map(fn(p) { p.value })
        |> result.unwrap("")

      let prodid =
        cal_props
        |> list.find(fn(p) { p.name == "PRODID" })
        |> result.map(fn(p) { p.value })
        |> result.unwrap("")

      let events =
        cal_children
        |> list.filter_map(fn(c) {
          case c.kind {
            "VEVENT" -> Ok(Event(c.properties))
            _ -> Error(Nil)
          }
        })

      Ok(Calendar(version, prodid, cal_props, events))
    }
    Error(_) -> Error(ParseError("No VCALENDAR component found"))
  }
}

pub fn get_event_property(event: Event, name: String) -> Result(String, Error) {
  case list.find(event.properties, fn(p) { p.name == name }) {
    Ok(prop) -> Ok(prop.value)
    Error(_) -> Error(ParseError("Property not found: " <> name))
  }
}

pub fn get_event_summary(event: Event) -> Result(String, Error) {
  get_event_property(event, "SUMMARY")
}

pub fn get_event_uid(event: Event) -> Result(String, Error) {
  get_event_property(event, "UID")
}

pub fn get_event_location(event: Event) -> Result(String, Error) {
  get_event_property(event, "LOCATION")
}

pub fn get_event_description(event: Event) -> Result(String, Error) {
  get_event_property(event, "DESCRIPTION")
}
