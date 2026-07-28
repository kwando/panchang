import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import global_value
import panchang/ical
import tzif/database

/// Render a parsed iCal component tree to a stable, human-readable string.
///
/// This is intended for snapshot tests and debugging, not for generating
/// valid iCal output. Property order and component nesting are preserved.
///
pub fn render_tree(component: ical.Component) -> String {
  render_component(component, 0)
}

fn render_component(component: ical.Component, depth: Int) -> String {
  let indent = indent_for(depth)
  let header = indent <> component.kind <> "\n"
  let props = render_properties(component.properties, depth + 1)
  let children = render_children(component.children, depth + 1)
  header <> props <> children
}

fn render_children(children: List(ical.Component), depth: Int) -> String {
  list.map(children, render_child(_, depth))
  |> string.concat
}

fn render_child(child: ical.Component, depth: Int) -> String {
  let indent = indent_for(depth)
  indent
  <> "BEGIN:"
  <> child.kind
  <> "\n"
  <> render_component_body(child, depth + 1)
  <> indent
  <> "END:"
  <> child.kind
  <> "\n"
}

fn render_component_body(component: ical.Component, depth: Int) -> String {
  render_properties(component.properties, depth)
  <> render_children(component.children, depth)
}

fn render_properties(properties: List(ical.Property), depth: Int) -> String {
  list.map(properties, render_property(_, depth))
  |> string.concat
}

fn render_property(property: ical.Property, depth: Int) -> String {
  let indent = indent_for(depth)
  case property.params {
    [] -> indent <> property.name <> ": " <> quote(property.value) <> "\n"
    _ -> {
      let header = indent <> property.name <> "\n"
      let params =
        list.map(property.params, fn(param) {
          indent <> "  " <> param.name <> ": " <> quote(param.value) <> "\n"
        })
        |> string.concat
      let value = indent <> "  value: " <> quote(property.value) <> "\n"
      header <> params <> value
    }
  }
}

fn quote(value: String) -> String {
  "\"" <> value <> "\""
}

fn indent_for(depth: Int) -> String {
  string.repeat("  ", depth)
}

/// Render a parsed `Calendar` to a stable, human-readable string.
///
/// Timestamps are rendered as RFC 3339 strings in UTC. Missing optional
/// timestamps are rendered as `-`. This is intended for snapshot tests and
/// debugging, not for generating valid iCal output.
///
pub fn render_calendar(calendar: ical.Calendar) -> String {
  let header = "Calendar\n"
  let version = "  version: " <> quote(calendar.version) <> "\n"
  let prodid = "  prodid: " <> quote(calendar.prodid) <> "\n"
  let timezone = "  timezone: " <> quote(calendar.timezone) <> "\n"
  let events =
    list.map(calendar.events, render_event(_, 1))
    |> string.concat
  header <> version <> prodid <> timezone <> events
}

fn render_event(event: ical.Event, depth: Int) -> String {
  let indent = indent_for(depth)
  let header = indent <> "Event\n"
  let fields = [
    #("uid", quote(event.uid)),
    #("summary", quote(event.summary)),
    #("description", quote(event.description)),
    #("location", quote(event.location)),
    #("url", quote(event.url)),
    #("dtstart", render_timestamp(Some(event.dtstart))),
    #("dtend", render_timestamp(Some(event.dtend))),
    #("created", render_timestamp(event.created)),
    #("last_modified", render_timestamp(event.last_modified)),
    #("dtstamp", render_timestamp(event.dtstamp)),
    #("is_all_day", bool_to_string(event.is_all_day)),
  ]
  let body =
    list.map(fields, fn(field) {
      indent <> "  " <> field.0 <> ": " <> field.1 <> "\n"
    })
    |> string.concat
  header <> body
}

fn render_timestamp(ts: Option(timestamp.Timestamp)) -> String {
  case ts {
    Some(t) -> quote(timestamp.to_rfc3339(t, calendar.utc_offset))
    None -> "-"
  }
}

fn bool_to_string(value: Bool) -> String {
  case value {
    True -> "True"
    False -> "False"
  }
}

/// Returns a shared, lazily-initialized timezone database for tests.
///
/// The database is loaded once from the operating system and cached under a
/// unique name so it can be reused across test functions.
///
pub fn tzdb() {
  global_value.create_with_unique_name("tzdb", fn() {
    let assert Ok(tz_db) = database.load_from_os()
    tz_db
  })
}
