import argv
import gcal
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import gleam_community/ansi
import simplifile
import tzif/database

pub type Error {
  InvalidArguments(String)
  CannotReadFile(simplifile.FileError)
  CannotParseCalendar(gcal.ParseError)
  CannotReadTimezoneDatabase
}

pub fn main() {
  let args = argv.load()

  let result = case args.arguments {
    [path] -> {
      use data <- result.try(
        simplifile.read(path) |> result.map_error(CannotReadFile),
      )
      use tzdata <- result.try(
        database.load_from_os()
        |> result.replace_error(CannotReadTimezoneDatabase),
      )

      let parser = gcal.new_parser(tzdata)

      use calendar <- result.try(
        gcal.parse(parser, data) |> result.map_error(CannotParseCalendar),
      )
      prettify_calendar(calendar)
    }
    _ -> Error(InvalidArguments("one calendar file name is expected"))
  }

  case result {
    Ok(data) -> io.println(data)
    Error(error) -> io.println_error(ansi.red(error_to_string(error)))
  }
}

fn error_to_string(error: Error) {
  case error {
    InvalidArguments(msg) -> msg
    CannotReadFile(error) -> "failed to read file: " <> string.inspect(error)
    CannotParseCalendar(gcal.ParseError(msg)) -> "cant parse calendar: " <> msg
    CannotReadTimezoneDatabase -> "failed to initalize timezone database"
  }
}

fn prettify_calendar(calendar: gcal.Calendar) -> Result(String, Error) {
  let events =
    calendar.events
    |> list.sort(fn(a, b) { timestamp.compare(a.dtstart, b.dtstart) })
  list.map(events, format_event)
  |> string.join("\n--------------------------------------\n")
  |> Ok
}

pub fn format_event(event: gcal.Event) -> String {
  let header =
    event.summary
    |> ansi.yellow
    |> ansi.bold
    <> "\n"

  let times =
    timestamp.to_rfc3339(event.dtstart, calendar.utc_offset)
    <> " -> "
    <> timestamp.to_rfc3339(event.dtend, calendar.utc_offset)

  let all_day_flag = case event.is_all_day {
    True -> " (all day)" |> ansi.dim
    False -> ""
  }

  let props_header = "\n" <> "Properties:" |> ansi.dim <> "\n"

  let props =
    event.raw
    |> list.map(format_property)
    |> string.join("\n")

  header <> times <> all_day_flag <> props_header <> props
}

fn format_property(prop: gcal.Property) -> String {
  let name = prop.name |> ansi.green |> ansi.bold

  let params = case prop.params {
    [] -> ""
    params ->
      params
      |> list.map(fn(p) { p.name <> "=" <> p.value })
      |> string.join("; ")
      |> fn(s) { " [" <> s |> ansi.cyan <> "]" }
  }

  let value = case prop.value == "" {
    True -> "(empty)" |> ansi.dim
    False -> prop.value
  }

  name <> params <> ": " <> value
}
