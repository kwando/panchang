import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
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
    /// The event description. Empty string if not present.
    description: String,
    /// The event location. Empty string if not present.
    location: String,
    /// A URL associated with the event. Empty string if not present.
    url: String,
    /// The start time as an unambiguous timestamp. Returns `unix_epoch` if
    /// missing or unparseable.
    start_time: Timestamp,
    /// The end time as an unambiguous timestamp. Returns `unix_epoch` if
    /// missing or unparseable.
    end_time: Timestamp,
    /// The creation timestamp, if present.
    created: Option(Timestamp),
    /// The last-modified timestamp, if present.
    last_modified: Option(Timestamp),
    /// The data-instance timestamp. UTC time when this iCalendar object was
    /// generated or revised. Required by RFC 5545 but stored as Option.
    generated_at: Option(Timestamp),
    /// The event organizer, if present.
    organizer: Option(Attendee),
    /// All attendees (`ATTENDEE` properties) for the event.
    attendees: List(Attendee),
    /// True when the event uses date-only values (`VALUE=DATE`), indicating
    /// an all-day event.
    all_day: Bool,
    /// All original properties for this event, including DTSTART, DTEND,
    /// LOCATION, DESCRIPTION, ATTENDEE, etc.
    properties: List(Property),
  )
}

/// Participation status of an attendee for a VEVENT, as defined by the
/// `PARTSTAT` parameter in RFC 5545.
///
/// When `PARTSTAT` is missing, `NeedsAction` is used as the default value.
/// Unrecognized or extension values are preserved via the `Other` variant.
///
pub type ParticipationStatus {
  NeedsAction
  Accepted
  Declined
  Tentative
  Delegated
  Other(String)
}

/// Expected participation of an attendee in a calendar component, as defined
/// by the `ROLE` parameter in RFC 5545.
///
/// When `ROLE` is missing, `MustAttend` is used as the default value.
/// Unrecognized or extension values are preserved via the `OtherRole` variant.
///
pub type AttendeeParticipation {
  Chair
  MustAttend
  MayAttend
  InformedOnly
  OtherRole(String)
}

/// A calendar user associated with an event, parsed from an `ATTENDEE` or
/// `ORGANIZER` property.
///
/// The `address` field is the calendar address (typically a `mailto:` URI).
/// Common parameters like common name, role, and participation status are
/// extracted into typed fields. Less common parameters remain available via
/// the original `Property` in `event.properties`.
///
pub type Attendee {
  Attendee(
    /// The calendar address, e.g. `"mailto:jsmith@example.com"`.
    address: String,
    /// The common name (`CN` parameter), if present.
    cn: Option(String),
    /// The expected participation (`ROLE` parameter), e.g. `"REQ-PARTICIPANT"` or `"CHAIR"`.
    participation: AttendeeParticipation,
    /// The participation status (`PARTSTAT` parameter). Defaults to
    /// `NeedsAction` when not present.
    status: ParticipationStatus,
    /// Whether the organizer requests a response from the attendee (`RSVP` parameter).
    response_requested: Option(Bool),
    /// The calendar user type (`CUTYPE` parameter), e.g. `"INDIVIDUAL"`.
    cutype: Option(String),
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

/// Whether a datetime value includes a timezone indicator.
pub type DateTimeKind {
  /// The value has a `Z` suffix, indicating UTC.
  Utc
  /// The value has no timezone indicator and is interpreted as local time
  /// (floating datetime in iCal terminology).
  Floating
}

/// An error that can occur during parsing.
pub type ParseError {
  /// A structural parsing error (missing component, unexpected line, etc.)
  ParseError(message: String)
  /// A date or datetime value could not be parsed.
  DateParseError(message: String, raw: String)
}

/// A raw iCal component, such as `VCALENDAR`, `VEVENT`, or `VTIMEZONE`.
///
/// Components are nested: a `VCALENDAR` contains `VEVENT` children, and each
/// `VEVENT` may contain `VALARM` children. Use `parse_tree` to get the full
/// component tree without it being converted into a `Calendar`.
///
pub type Component {
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
/// import panchang/ical
///
/// let assert Ok(db) = database.load_from_os()
/// let parser = ical.new_parser(db)
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

/// Parse an iCal string into a raw component tree.
///
/// Returns the single root `VCALENDAR` component with all its children, such as
/// `VEVENT`, `VTODO`, `VTIMEZONE`, `VALARM`, etc. This is useful when you need
/// access to components or properties that the higher-level `parse` function
/// does not expose.
///
/// Errors if the input is empty or contains more than one top-level component.
///
pub fn parse_tree(
  parser: Parser,
  input: String,
) -> Result(Component, ParseError) {
  // Strip UTF-8 BOM (U+FEFF) that some Windows applications prepend to .ics files
  let input = string.remove_prefix(input, "\u{FEFF}")
  let lines = unfold_lines(input, parser)
  let non_empty = list.filter(lines, fn(line) { line != "" })

  case parse_all_components(non_empty, []) {
    Ok([root]) -> Ok(root)
    Ok([]) -> Error(ParseError("No VCALENDAR component found"))
    Ok(_) ->
      Error(ParseError("Multiple top-level components are not supported"))
    Error(err) -> Error(err)
  }
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
/// import panchang/ical
/// import gleam/option
/// import tzif/database
///
/// let assert Ok(db) = database.load_from_os()
/// let parser = ical.new_parser(db)
///
/// // Use UTC for floating times
/// let assert Ok(calendar) = ical.parse(parser, ical, option.None)
///
/// // Resolve floating times to a specific timezone
/// let assert Ok(calendar) =
///   ical.parse(parser, ical, option.Some("Europe/Stockholm"))
/// ```
///
pub fn parse(
  parser: Parser,
  input: String,
  timezone: Option(String),
) -> Result(Calendar, ParseError) {
  case parse_tree(parser, input) {
    Ok(root) -> build_calendar([root], timezone, parser)
    Error(err) -> Error(err)
  }
}

// iCal content lines can be folded by starting a continuation line with a
// space or tab. Unfold first so every logical property line is a single string.
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

// Component markers (BEGIN:/END:) are case-insensitive per RFC 5545, so we
// compare the uppercased prefix and preserve the original case for the name.
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

// Recursively consume a component's body until its matching END: line.
// Components can nest (e.g. VCALENDAR -> VEVENT), so child components are
// parsed before returning to the parent.
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

// RFC 5545 allows quoted parameter values to contain ;, = and :, so we cannot
// split property lines on those characters blindly. Track quote state and only
// split on a separator that is outside a quoted string.
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
            _ ->
              do_split_first_unquoted(rest, sep, in_quote, False, [char, ..acc])
          }
        }
      }
    }
  }
}

// Quoted parameter values must have their surrounding quotes removed, and only
// \" and \\ are valid escapes inside quoted strings (unlike text values).
fn unescape_param_value(value: String) -> String {
  let unescaped = case
    string.starts_with(value, "\"") && string.ends_with(value, "\"")
  {
    False -> value
    True -> {
      let inner = string.slice(value, 1, string.length(value) - 2)
      do_unescape_param_text(string.to_graphemes(inner), [])
      |> list.reverse
      |> string.concat
    }
  }
  rfc_6868_unescape(unescaped)
}

/// Apply RFC 6868 parameter value unescaping.
///
/// RFC 6868 defines an escaping mechanism for iCalendar and vCard TEXT
/// parameter values. It uses `^` as the escape character:
///
/// - `^'` (U+005E U+0027) → `"` (U+0022, quotation mark)
/// - `^^` (U+005E U+005E) → `^` (U+005E, circumflex accent)
/// - `^n` (U+005E U+006E) → U+000A (line feed)
///
fn rfc_6868_unescape(value: String) -> String {
  // Order matters: ^' first so ^^' doesn't become "
  value
  |> string.replace("^'", "\"")
  |> string.replace("^^", "^")
  |> string.replace("^n", "\n")
}

fn do_unescape_param_text(
  chars: List(String),
  acc: List(String),
) -> List(String) {
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

fn do_parse_params(input: String, acc: List(Parameter)) -> List(Parameter) {
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

// Single-pass byte processing avoids creating intermediate strings for every
// escape sequence and correctly handles \\ before other escapes (e.g. \\n must
// stay as a literal backslash + n, not become a newline).
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
/// let assert Ok(location_prop) = ical.get_property(event, "LOCATION")
/// location_prop.value
/// ```
///
pub fn get_property(event: Event, name: String) -> Result(Property, Nil) {
  list.find(event.properties, fn(prop) { name_eq(prop.name, name) })
}

// Property, parameter and component names are case-insensitive per RFC 5545.
fn name_eq(a: String, b: String) -> Bool {
  string.uppercase(a) == string.uppercase(b)
}

/// Find a parameter value by name in a property's parameters.
///
/// Returns `Ok(String)` with the parameter value if found, `Error(Nil)`
/// otherwise.
///
/// ```gleam
/// let assert Ok(prop) = ical.get_property(event, "DTSTART")
/// let assert Ok(tzid) = ical.get_parameter(prop, "TZID")
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

fn extract_timestamp(
  props: List(Property),
  name: String,
  parser: Parser,
  fallback_tz: String,
) -> Option(Timestamp) {
  props
  |> list.find(fn(p) { name_eq(p.name, name) })
  |> result.map(fn(p) { parse_timestamp(p, parser, fallback_tz) })
  |> option.from_result
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

fn parse_date_bytes(
  bits: BitArray,
  raw: String,
) -> Result(#(calendar.Date, BitArray), ParseError) {
  case bits {
    <<y1, y2, y3, y4, m1, m2, d1, d2, rest:bits>>
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
            True -> Ok(#(date, rest))
            False -> Error(DateParseError("Invalid date", raw))
          }
        }
        Error(_) -> Error(DateParseError("Invalid month", raw))
      }
    }
    _ -> Error(DateParseError("Invalid date format", raw))
  }
}

/// Parse an iCal date-only value (`YYYYMMDD`) into a `Date`.
///
/// ```gleam
/// ical.parse_date("20230101") // -> Ok(Date(2023, Jan, 1))
/// ```
pub fn parse_date(raw: String) -> Result(calendar.Date, Nil) {
  case parse_date_bytes(bit_array.from_string(raw), raw) {
    Ok(#(date, <<>>)) -> Ok(date)
    _ -> Error(Nil)
  }
}

/// Parse an iCal datetime string into its components and timezone kind.
///
/// Returns the date, time of day, and whether the value was UTC (`Z` suffix)
/// or floating (no timezone indicator).
///
/// ```gleam
/// ical.parse_datetime_string("20230101T100000Z")
/// // -> Ok(#(Date(2023, Jan, 1), TimeOfDay(10, 0, 0, 0), Utc))
/// ```
pub fn parse_datetime(
  raw: String,
) -> Result(#(calendar.Date, calendar.TimeOfDay, DateTimeKind), Nil) {
  use #(date, rest) <- result.try(
    parse_date_bytes(bit_array.from_string(raw), raw)
    |> result.replace_error(Nil),
  )

  case parse_time_bytes(rest) {
    Ok(#(time, <<"Z">>)) | Ok(#(time, <<"z">>)) -> Ok(#(date, time, Utc))
    Ok(#(time, <<>>)) -> Ok(#(date, time, Floating))
    // we got some extra bytes/bits at the end which we dont know hot to handle
    Ok(#(_, _)) | Error(_) -> Error(Nil)
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
/// Explicit `TZID` parameters take precedence over the fallback timezone, which
/// is used for floating datetimes. The calendar's `X-WR-TIMEZONE` is handled by
/// the caller before this function is invoked.
@internal
pub fn parse_timestamp(
  prop: Property,
  parser: Parser,
  fallback_tz: String,
) -> Timestamp {
  let value = prop.value
  use <- bool.guard(when: string.is_empty(value), return: timestamp.unix_epoch)

  case parse_date_bytes(bit_array.from_string(value), value) {
    Ok(#(date, <<>>)) -> {
      use <- bool.guard(
        when: !has_param_value_date(prop.params),
        return: timestamp.unix_epoch,
      )

      timestamp.from_calendar(
        date,
        calendar.TimeOfDay(0, 0, 0, 0),
        calendar.utc_offset,
      )
    }
    Error(_) -> timestamp.unix_epoch

    Ok(#(date, time_bits)) -> {
      case parse_time_bytes(time_bits) {
        Ok(#(time, <<"Z">>)) | Ok(#(time, <<"z">>)) ->
          timestamp.from_calendar(date, time, calendar.utc_offset)
        Ok(#(time, <<>>)) -> {
          let timezone =
            prop.params
            |> get_tzid()
            |> result.unwrap(fallback_tz)

          case tzcalendar.from_calendar(date, time, timezone, parser.db) {
            Ok([ts]) -> ts
            Ok([ts, ..]) -> ts
            Ok([]) | Error(_) ->
              timestamp.from_calendar(date, time, calendar.utc_offset)
          }
        }
        Error(_) | Ok(#(_, _)) -> timestamp.unix_epoch
      }
    }
  }
}

fn parse_time_bytes(
  rest: BitArray,
) -> Result(#(calendar.TimeOfDay, BitArray), Nil) {
  case rest {
    <<t, h1, h2, min1, min2, s1, s2, rest:bits>>
      if { t == 84 || t == 116 }
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
      let hours = { h1 - 48 } * 10 + { h2 - 48 }
      let minutes = { min1 - 48 } * 10 + { min2 - 48 }
      let seconds = { s1 - 48 } * 10 + { s2 - 48 }
      let time = calendar.TimeOfDay(hours, minutes, seconds, 0)

      case calendar.is_valid_time_of_day(time) {
        True -> Ok(#(time, rest))
        False -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

/// Parse an iCal duration string into a signed `Duration`.
///
/// This parser accepts common RFC 5545 duration formats but is intentionally
/// lenient: time units do not require a leading `T`, units may appear in any
/// order, duplicate units are summed, and weeks may be combined with other
/// units.
///
/// Supported examples:
/// - `P1W` (1 week)
/// - `P1D` (1 day)
/// - `PT1H` or `P1H` (1 hour)
/// - `PT30M` (30 minutes)
/// - `PT1H30M` (1 hour 30 minutes)
/// - `P1DT2H3M4S` (1 day, 2 hours, 3 minutes, 4 seconds)
/// - `-PT30M` (negative 30 minutes)
/// - `P2H2H` (duplicate units are added)
///
/// Fractional seconds are rejected and cause a parse error.
///
pub fn parse_duration(value: String) -> Result(Duration, Nil) {
  let value = string.uppercase(string.trim(value))
  use #(value, sign) <- result.try(case bit_array.from_string(value) {
    <<"+P", rest:bits>> | <<"P", rest:bits>> -> Ok(#(rest, 1))
    <<"-P", rest:bits>> -> Ok(#(rest, -1))
    _ -> Error(Nil)
  })

  case duration_components(value, 0, False, []) {
    Ok([]) | Error(_) -> Error(Nil)
    Ok(components) -> duration_from_components(components, sign)
  }
}

type DurationComponent {
  Week(Int)
  Day(Int)
  Hour(Int)
  Minute(Int)
  Second(Int)
}

fn duration_components(
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
      duration_components(rest, acc * 10 + 0, True, result)
    <<"1", rest:bits>>, _ ->
      duration_components(rest, acc * 10 + 1, True, result)
    <<"2", rest:bits>>, _ ->
      duration_components(rest, acc * 10 + 2, True, result)
    <<"3", rest:bits>>, _ ->
      duration_components(rest, acc * 10 + 3, True, result)
    <<"4", rest:bits>>, _ ->
      duration_components(rest, acc * 10 + 4, True, result)
    <<"5", rest:bits>>, _ ->
      duration_components(rest, acc * 10 + 5, True, result)
    <<"6", rest:bits>>, _ ->
      duration_components(rest, acc * 10 + 6, True, result)
    <<"7", rest:bits>>, _ ->
      duration_components(rest, acc * 10 + 7, True, result)
    <<"8", rest:bits>>, _ ->
      duration_components(rest, acc * 10 + 8, True, result)
    <<"9", rest:bits>>, _ ->
      duration_components(rest, acc * 10 + 9, True, result)

    // a duration cannot end with a T
    <<"T">>, _ -> Error(Nil)
    // T cannot follow a number; it is only a separator before time units
    <<"T", _:bits>>, True -> Error(Nil)
    <<"T", rest:bits>>, False -> duration_components(rest, 0, False, result)

    // ----- handle units
    <<"D", rest:bits>>, True ->
      duration_components(rest, 0, False, [Day(acc), ..result])
    <<"H", rest:bits>>, True ->
      duration_components(rest, 0, False, [Hour(acc), ..result])
    <<"M", rest:bits>>, True ->
      duration_components(rest, 0, False, [Minute(acc), ..result])
    <<"S", rest:bits>>, True ->
      duration_components(rest, 0, False, [Second(acc), ..result])
    <<"W", rest:bits>>, True ->
      duration_components(rest, 0, False, [Week(acc), ..result])

    _, _ -> Error(Nil)
  }
}

fn duration_from_components(
  components: List(DurationComponent),
  sign: Int,
) -> Result(Duration, Nil) {
  components
  |> list.fold(0, fn(acc, component) { acc + component_to_seconds(component) })
  |> int.multiply(sign)
  |> duration.seconds
  |> Ok
}

fn component_to_seconds(unit: DurationComponent) -> Int {
  case unit {
    Week(w) -> w * 604_800
    Day(d) -> d * 86_400
    Hour(h) -> h * 3600
    Minute(m) -> m * 60
    Second(s) -> s
  }
}

fn build_event(
  props: List(Property),
  parser: Parser,
  fallback_tz: String,
) -> Event {
  let uid = extract_prop(props, "UID")
  let summary = extract_prop(props, "SUMMARY")
  let description = extract_prop(props, "DESCRIPTION")
  let location = extract_prop(props, "LOCATION")
  let url = extract_prop(props, "URL")

  let dtstart_prop = list.find(props, fn(p) { p.name == "DTSTART" })
  let dtend_prop = list.find(props, fn(p) { p.name == "DTEND" })
  let duration_prop = list.find(props, fn(p) { p.name == "DURATION" })

  let all_day =
    dtstart_prop
    |> result.map(fn(p) { has_param_value_date(p.params) })
    |> result.unwrap(False)

  let start_time =
    dtstart_prop
    |> result.map(fn(p) { parse_timestamp(p, parser, fallback_tz) })
    |> result.unwrap(timestamp.unix_epoch)
  let end_time = case dtend_prop {
    Ok(prop) -> parse_timestamp(prop, parser, fallback_tz)
    Error(_) ->
      case duration_prop {
        Ok(prop) ->
          parse_duration(prop.value)
          |> result.map(fn(d) { timestamp.add(start_time, d) })
          |> result.unwrap(timestamp.unix_epoch)
        Error(_) -> timestamp.unix_epoch
      }
  }

  let created = extract_timestamp(props, "CREATED", parser, fallback_tz)
  let last_modified =
    extract_timestamp(props, "LAST-MODIFIED", parser, fallback_tz)
  let generated_at = extract_timestamp(props, "DTSTAMP", parser, fallback_tz)

  let organizer = extract_organizer(props)
  let attendees = extract_attendees(props)

  Event(
    uid,
    summary,
    description,
    location,
    url,
    start_time,
    end_time,
    created,
    last_modified,
    generated_at,
    organizer,
    attendees,
    all_day,
    props,
  )
}

fn extract_organizer(props: List(Property)) -> Option(Attendee) {
  list.find(props, fn(p) { name_eq(p.name, "ORGANIZER") })
  |> option.from_result
  |> option.map(attendee_from_property)
}

fn extract_attendees(props: List(Property)) -> List(Attendee) {
  use p <- list.filter_map(props)
  case name_eq(p.name, "ATTENDEE") {
    True -> Ok(attendee_from_property(p))
    False -> Error(Nil)
  }
}

fn attendee_from_property(prop: Property) -> Attendee {
  Attendee(
    address: prop.value,
    cn: param_value(prop, "CN"),
    participation: parse_attendee_role(param_value(prop, "ROLE")),
    status: parse_participation_status(param_value(prop, "PARTSTAT")),
    response_requested: param_value(prop, "RSVP") |> option.map(parse_rsvp),
    cutype: param_value(prop, "CUTYPE"),
  )
}

fn parse_participation_status(value: Option(String)) -> ParticipationStatus {
  case value {
    None -> NeedsAction
    Some(raw) ->
      case string.uppercase(raw) {
        "NEEDS-ACTION" -> NeedsAction
        "ACCEPTED" -> Accepted
        "DECLINED" -> Declined
        "TENTATIVE" -> Tentative
        "DELEGATED" -> Delegated
        _ -> Other(raw)
      }
  }
}

fn parse_attendee_role(value: Option(String)) -> AttendeeParticipation {
  case value {
    None -> MustAttend
    Some(raw) ->
      case string.uppercase(raw) {
        "CHAIR" -> Chair
        "REQ-PARTICIPANT" -> MustAttend
        "OPT-PARTICIPANT" -> MayAttend
        "NON-PARTICIPANT" -> InformedOnly
        _ -> OtherRole(raw)
      }
  }
}

fn param_value(prop: Property, name: String) -> Option(String) {
  get_parameter(prop, name) |> option.from_result
}

fn parse_rsvp(value: String) -> Bool {
  string.uppercase(value) == "TRUE"
}

// Flatten the parsed component tree into a Calendar. When the caller does not
// supply a timezone, fall back to the calendar's X-WR-TIMEZONE property.
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
