# panchang/ical

An iCal (`.ics`) parser for Gleam. Parses VCALENDAR and VEVENT components with full support for folded lines, escaped text, property parameters, and timezone-aware datetime resolution.

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
  event.is_all_day
  // -> False
  timestamp.to_unix_seconds(event.dtstart)
  // -> 1672567200.0
}
```

## API

- `ical.new_parser(tz_db: TzDatabase) -> Parser` — create a parser with a timezone database.
- `ical.parse(parser: Parser, input: String, timezone: Option(String)) -> Result(Calendar, ParseError)` — parse an iCal string. Pass `Some(tz)` to resolve floating times to a specific timezone, or `None` to use `X-WR-TIMEZONE` or UTC.

## Development

```sh
gleam test  # Run the tests
```
