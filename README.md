# panchang/ical

An iCal (`.ics`) parser for Gleam. Parses `VCALENDAR` and `VEVENT` components
with support for folded lines, escaped text, property parameters,
timezone-aware datetimes, and case-insensitive property names.

```sh
gleam add panchang
```

```gleam
import panchang/ical
import gleam/option
import gleam/time/timestamp
import tzif/database

pub fn main() {
  let ical = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\n"
    <> "BEGIN:VEVENT\nSUMMARY:Meeting\n"
    <> "DTSTART:20230101T100000Z\nDTEND:20230101T110000Z\n"
    <> "UID:123@test\nEND:VEVENT\nEND:VCALENDAR"

  let assert Ok(db) = database.load_from_os()
  let parser = ical.new_parser(db)
  let assert Ok(calendar) = ical.parse(parser, ical, option.None)

  calendar.timezone
  // -> "UTC"

  let assert [event] = calendar.events
  event.summary
  // -> "Meeting"
  event.all_day
  // -> False
  timestamp.to_unix_seconds(event.start_time)
  // -> 1672567200.0
}
```

## What it does

- Parses `VCALENDAR` and `VEVENT` components.
- Handles folded content lines (`\r\n ` / `\n ` continuations).
- Unescapes text values (`\n`, `\N`, `\,`, `\;`, `\:`, `\\`).
- Parses property parameters, including quoted values that contain `;`, `=`, or `:`.
- Treats property, parameter, and component names as case-insensitive.
- Resolves datetimes using the IANA timezone database via `tzif`.
- Extracts common event fields: `uid`, `summary`, `description`, `location`,
  `url`, `start_time`, `end_time`, `created`, `last_modified`, `generated_at`,
  `all_day`.
- Preserves all original properties in `event.properties` for access to anything
  not explicitly parsed.
- Exposes a generic `parse_tree` function for full access to the component tree.

## Out of scope

This library is a parser, not a full calendar runtime. It does **not**:

- **Generate or write** iCal files.
- **Expand recurring events** (`RRULE`, `RDATE`, `EXDATE`, `RECURRENCE-ID`).
  `dtstart`/`dtend` are the original values; recurrence instances are not
  computed.
- **Model every iCal component** as a typed record. `VTODO`, `VJOURNAL`,
  `VFREEBUSY`, `VTIMEZONE`, and `VALARM` are available as raw components via
  `parse_tree`, but are not converted into dedicated Gleam types.
- **Parse embedded `VTIMEZONE` definitions**. Datetimes are resolved using the
  IANA timezone database via `tzif`, which covers all standard timezone
  identifiers (e.g. `America/New_York`, `Europe/Stockholm`). Embedded
  VTIMEZONEs in `.ics` files effectively duplicate the same data, so parsing
  them would add complexity without changing behavior for the vast majority of
  real-world calendars. Calendars using non-standard or custom `TZID` values
  (instead of IANA identifiers) may not resolve correctly.
- **Handle scheduling semantics** such as iTIP/iMIP invitations, attendee
  responses, or conflict detection.
- **Execute alarms**. `VALARM` components can be read via `parse_tree`, but the
  library does not trigger or manage them.
- **Fetch calendars from the network** or manage subscriptions.

## Test fixtures

The `test/fixtures/` directory is intended to hold third-party `.ics` test
calendars used for interoperability testing. Files are not bundled in the
published package; they are only used during development.

- `test/fixtures/rfc5545/` — examples extracted from RFC 5545, licensed under
  the IETF Trust Code Components License (Simplified BSD License).
  See `test/fixtures/rfc5545/LICENSE`.
- `test/fixtures/icalendar/` — fixtures from the Python `icalendar` project,
  licensed under the BSD-2-Clause License.
  See `test/fixtures/icalendar/LICENSE`.
  Source: https://github.com/collective/icalendar

## Development

```sh
gleam test  # Run the tests
```
