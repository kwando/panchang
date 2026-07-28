import gleam/bool
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
  |> string.trim_end
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
    calendar.events
    |> list.map(render_event(_, 1))
    |> string.join("\n")
  header <> version <> prodid <> timezone <> events
}

fn render_event(event: ical.Event, depth: Int) -> String {
  let indent = indent_for(depth)
  let header = indent <> "Event\n"
  let body =
    [
      render_field(indent, "uid", event.uid, quote),
      render_field(indent, "summary", event.summary, quote),
      render_field(indent, "description", event.description, quote),
      render_field(indent, "location", event.location, quote),
      render_field(indent, "url", event.url, quote),
      render_field(indent, "dtstart", Some(event.dtstart), render_timestamp),
      render_field(indent, "dtend", Some(event.dtend), render_timestamp),
      render_field(indent, "created", event.created, render_timestamp),
      render_field(
        indent,
        "last_modified",
        event.last_modified,
        render_timestamp,
      ),
      render_field(indent, "dtstamp", event.dtstamp, render_timestamp),
      render_organizer_block(indent, event.organizer),
      render_attendees_block(indent, event.attendees),
      render_field(indent, "is_all_day", event.is_all_day, bool.to_string),
    ]
    |> string.join("\n")
  header <> body
}

fn render_field(
  indent: String,
  key: String,
  value: a,
  mapper: fn(a) -> String,
) -> String {
  indent <> "  " <> key <> ": " <> mapper(value)
}

fn render_organizer_block(
  indent: String,
  organizer: Option(ical.Attendee),
) -> String {
  let field_indent = indent <> "  "
  case organizer {
    None -> field_indent <> "organizer: -"
    Some(attendee) ->
      field_indent
      <> "organizer:\n"
      <> render_attendee_properties(attendee, field_indent <> "  ")
      |> string.trim_end
  }
}

fn render_attendees_block(
  indent: String,
  attendees: List(ical.Attendee),
) -> String {
  let field_indent = indent <> "  "
  case attendees {
    [] -> field_indent <> "attendees: []"
    _ -> {
      let items =
        list.map(attendees, fn(attendee) {
          let item_indent = field_indent <> "  "
          let props = attendee_properties(attendee)
          case props {
            [] -> item_indent <> "-\n"
            [#(key, value), ..rest] -> {
              let first = item_indent <> "- " <> key <> ": " <> value <> "\n"
              let rest_lines =
                list.map(rest, fn(prop) {
                  item_indent <> "  " <> prop.0 <> ": " <> prop.1 <> "\n"
                })
                |> string.concat
              first <> rest_lines
            }
          }
        })
        |> string.concat
        |> string.trim_end
      field_indent <> "attendees:\n" <> items
    }
  }
}

fn attendee_properties(attendee: ical.Attendee) -> List(#(String, String)) {
  [
    #("address", Some(quote(attendee.address))),
    #("role", attendee.role |> option.map(quote)),
    #("status", Some(participation_status_to_string(attendee.status))),
    #("rsvp", attendee.rsvp |> option.map(bool.to_string)),
    #("cutype", attendee.cutype |> option.map(quote)),
  ]
  |> list.filter_map(fn(entry) {
    case entry.1 {
      Some(value) -> Ok(#(entry.0, value))
      None -> Error(Nil)
    }
  })
}

fn render_attendee_properties(
  attendee: ical.Attendee,
  prop_indent: String,
) -> String {
  attendee_properties(attendee)
  |> list.map(fn(prop) { render_attendee_property(prop_indent, prop.0, prop.1) })
  |> string.concat
}

fn render_attendee_property(
  indent: String,
  key: String,
  value: String,
) -> String {
  indent <> key <> ": " <> value <> "\n"
}

fn participation_status_to_string(status: ical.ParticipationStatus) -> String {
  case status {
    ical.NeedsAction -> "NeedsAction"
    ical.Accepted -> "Accepted"
    ical.Declined -> "Declined"
    ical.Tentative -> "Tentative"
    ical.Delegated -> "Delegated"
    ical.Other(raw) -> "Other(" <> quote(raw) <> ")"
  }
}

fn render_timestamp(ts: Option(timestamp.Timestamp)) -> String {
  case ts {
    Some(t) -> quote(timestamp.to_rfc3339(t, calendar.utc_offset))
    None -> "-"
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
