# gcal

An iCal (`.ics`) parser for Gleam. Parses VCALENDAR and VEVENT components with full support for folded lines, escaped text, property parameters, and timezone-aware datetime resolution.

```sh
gleam add gcal
```

```gleam
import gcal
import gleam/time/timestamp

pub fn main() {
  let ical = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\n"
    <> "BEGIN:VEVENT\nSUMMARY:Meeting\n"
    <> "DTSTART:20230101T100000Z\nDTEND:20230101T110000Z\n"
    <> "UID:123@test\nEND:VEVENT\nEND:VCALENDAR"

  let assert Ok(calendar) = gcal.parse(ical)

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

- `parse(input: String) -> Result(Calendar, Error)` — parse an iCal string. Floating times resolve to `X-WR-TIMEZONE` or UTC.
- `parse_with_timezone(input: String, tz: String) -> Result(Calendar, Error)` — override the timezone for floating times.

## Development

```sh
gleam test  # Run the tests
```
