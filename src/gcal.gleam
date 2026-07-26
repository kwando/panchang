import gleam/list
import gleam/result
import gleam/string
import splitter

pub type Calendar {
  Calendar(version: String, prodid: String, events: List(Event))
}

pub type Event {
  Event(
    uid: String,
    summary: String,
    dtstart: String,
    dtend: String,
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

type Splitters {
  Splitters(
    lines: splitter.Splitter,
    begin: splitter.Splitter,
    colon: splitter.Splitter,
    semi: splitter.Splitter,
    eq: splitter.Splitter,
  )
}

pub fn parse(input: String) -> Result(Calendar, Error) {
  let splitters =
    Splitters(
      lines: splitter.new(["\r\n", "\n"]),
      begin: splitter.new(["BEGIN:"]),
      colon: splitter.new([":"]),
      semi: splitter.new([";"]),
      eq: splitter.new(["="]),
    )

  let lines = unfold_lines(input, splitters.lines)
  let non_empty = list.filter(lines, fn(line) { line != "" })

  case parse_all_components(non_empty, [], splitters) {
    Ok(components) -> build_calendar(components)
    Error(err) -> Error(err)
  }
}

fn unfold_lines(
  input: String,
  line_splitter: splitter.Splitter,
) -> List(String) {
  do_unfold_lines(input, line_splitter, [])
  |> list.reverse
}

fn do_unfold_lines(
  input: String,
  line_splitter: splitter.Splitter,
  acc: List(String),
) -> List(String) {
  case splitter.split(line_splitter, input) {
    #(line, "", "") ->
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
    #(line, _, remaining) ->
      case acc {
        [] -> do_unfold_lines(remaining, line_splitter, [line])
        [prev, ..rest] ->
          case string.starts_with(line, " ") || string.starts_with(line, "\t") {
            True ->
              case string.pop_grapheme(line) {
                Ok(#(_, remaining_line)) ->
                  do_unfold_lines(remaining, line_splitter, [
                    prev <> remaining_line,
                    ..rest
                  ])
                Error(_) ->
                  do_unfold_lines(remaining, line_splitter, [prev, ..acc])
              }
            False ->
              do_unfold_lines(remaining, line_splitter, [line, prev, ..rest])
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
              parse_all_components(remaining, [component, ..acc], splitters)
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
            Component(kind, list.reverse(props), list.reverse(children)),
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

fn parse_params(params_str: String, splitters: Splitters) -> List(Parameter) {
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

fn build_event(props: List(Property)) -> Event {
  let uid = extract_prop(props, "UID")
  let summary = extract_prop(props, "SUMMARY")
  let dtstart = extract_prop(props, "DTSTART")
  let dtend = extract_prop(props, "DTEND")

  Event(uid, summary, dtstart, dtend, props)
}

fn build_calendar(components: List(Component)) -> Result(Calendar, Error) {
  let flat =
    components
    |> list.map(fn(c) { #(c.kind, c.properties, c.children) })

  case list.find(flat, fn(c) { c.0 == "VCALENDAR" }) {
    Ok(#(_, cal_props, cal_children)) -> {
      let version = extract_prop(cal_props, "VERSION")
      let prodid = extract_prop(cal_props, "PRODID")

      let events =
        cal_children
        |> list.filter_map(fn(c) {
          case c.kind {
            "VEVENT" -> Ok(build_event(c.properties))
            _ -> Error(Nil)
          }
        })

      Ok(Calendar(version, prodid, events))
    }
    Error(_) -> Error(ParseError("No VCALENDAR component found"))
  }
}
