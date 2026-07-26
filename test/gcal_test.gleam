import gcal
import gleam/io
import gleam/list
import gleam/string
import gleeunit
import simplifile

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_simple_calendar_test() {
  let input = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)

  assert calendar.version == "2.0"
  assert calendar.prodid == "-//Test//EN"
  assert calendar.events == []
}

pub fn parse_calendar_with_one_event_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Meeting\nUID:123@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)

  let assert [event] = calendar.events
  assert gcal.get_event_summary(event) == Ok("Meeting")
  assert gcal.get_event_uid(event) == Ok("123@test")
}

pub fn parse_event_with_location_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Conference\nLOCATION:Stockholm\nUID:456@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events
  assert gcal.get_event_location(event) == Ok("Stockholm")
}

pub fn parse_event_with_parameters_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART;TZID=Europe/Stockholm:20230101T100000\nSUMMARY:Test\nUID:789@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events

  let assert Ok(dtstart) =
    list.find(event.properties, fn(p) { p.name == "DTSTART" })

  let assert [param] = dtstart.params
  assert param.name == "TZID"
  assert param.value == "Europe/Stockholm"
}

pub fn parse_multiple_events_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Event 1\nUID:1@test\nEND:VEVENT\nBEGIN:VEVENT\nSUMMARY:Event 2\nUID:2@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [_, _] = calendar.events
  True
}

pub fn parse_folded_lines_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDESCRIPTION:This is a long des\n cription that spans\n  multiple lines\nUID:fold@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events
  assert gcal.get_event_description(event)
    == Ok("This is a long description that spans multiple lines")
}

pub fn parse_escaped_text_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDESCRIPTION:Line 1\\nLine 2 with\\, comma\nUID:esc@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events
  let assert Ok(desc) = gcal.get_event_description(event)
  assert string.contains(desc, "\n")
  assert string.contains(desc, ",")
}

pub fn parse_empty_summary_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:\nUID:empty@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events
  assert gcal.get_event_summary(event) == Ok("")
}

pub fn parse_real_ical_file_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//caldav.icloud.com//CALDAVJ 2626B756//EN\nX-WR-CALNAME:Privat\nBEGIN:VEVENT\nCREATED:20171104T221935Z\nDTEND;TZID=Europe/Stockholm:20171128T203000\nDTSTAMP:20171125T133010Z\nDTSTART;TZID=Europe/Stockholm:20171128T193000\nLOCATION:Malmö Live\nSUMMARY:Anders och Måns\nUID:001E66D2-7DF8-40A8-B0BC-EBC4E3F9C2FD\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  assert calendar.version == "2.0"
  assert calendar.prodid == "-//caldav.icloud.com//CALDAVJ 2626B756//EN"
  let assert [event] = calendar.events
  assert gcal.get_event_summary(event) == Ok("Anders och Måns")
  assert gcal.get_event_location(event) == Ok("Malmö Live")
}

pub fn get_property_not_found_test() {
  let event = gcal.Event([])
  let assert Error(_) = gcal.get_event_property(event, "NONEXISTENT")
}

pub fn parse_real_calender_test() {
  let assert Ok(data) = simplifile.read("calendar.ical")

  let assert Ok(calendar) = gcal.parse(data)

  calendar.events
  |> list.map(pretty_print_event)
  |> string.join("\n------------------------\n")
  |> io.println_error
}

fn pretty_print_event(event: gcal.Event) {
  list.fold(event.properties, [], fn(acc, prop) {
    let params =
      list.map(prop.params, fn(param) { param.name <> "=" <> param.value })
      |> string.join(", ")
    [prop.name <> " " <> string.inspect(prop.value) <> " " <> params, ..acc]
  })
  |> string.join("\n")
}
