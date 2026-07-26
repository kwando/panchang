import gcal
import gleam/list
import gleam/string
import gleeunit

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
  assert event.summary == "Meeting"
  assert event.uid == "123@test"
}

pub fn parse_event_with_location_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Conference\nLOCATION:Stockholm\nUID:456@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events
  assert event.summary == "Conference"

  let assert Ok(loc) = list.find(event.raw, fn(p) { p.name == "LOCATION" })
  assert loc.value == "Stockholm"
}

pub fn parse_event_with_parameters_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART;TZID=Europe/Stockholm:20230101T100000\nDTEND;TZID=Europe/Stockholm:20230101T110000\nSUMMARY:Test\nUID:789@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events

  assert event.dtstart == "20230101T100000"
  assert event.dtend == "20230101T110000"

  let assert Ok(dtstart_prop) =
    list.find(event.raw, fn(p: gcal.Property) { p.name == "DTSTART" })

  let assert [param] = dtstart_prop.params
  assert param.name == "TZID"
  assert param.value == "Europe/Stockholm"
}

pub fn parse_property_with_params_in_raw_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nLOCATION;FMTTYPE=text/html:Conference Room\nSUMMARY:Test\nUID:params@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events

  let assert Ok(loc_prop) =
    list.find(event.raw, fn(p: gcal.Property) { p.name == "LOCATION" })

  let assert [fmt] = loc_prop.params
  assert fmt.name == "FMTTYPE"
  assert fmt.value == "text/html"
  assert loc_prop.value == "Conference Room"
}

pub fn parse_event_with_dtstart_dtend_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART:20230101T100000Z\nDTEND:20230101T110000Z\nSUMMARY:Timed\nUID:timed@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events

  assert event.dtstart == "20230101T100000Z"
  assert event.dtend == "20230101T110000Z"
}

pub fn parse_multiple_events_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Event 1\nUID:1@test\nEND:VEVENT\nBEGIN:VEVENT\nSUMMARY:Event 2\nUID:2@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [e1, e2] = calendar.events

  assert e1.summary == "Event 1"
  assert e2.summary == "Event 2"
}

pub fn parse_folded_lines_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDESCRIPTION:This is a long des\n cription that spans\n  multiple lines\nUID:fold@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events

  let assert Ok(desc) = list.find(event.raw, fn(p) { p.name == "DESCRIPTION" })
  assert desc.value == "This is a long description that spans multiple lines"
}

pub fn parse_escaped_text_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDESCRIPTION:Line 1\\nLine 2 with\\, comma\nUID:esc@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events

  let assert Ok(desc) = list.find(event.raw, fn(p) { p.name == "DESCRIPTION" })
  assert string.contains(desc.value, "\n")
  assert string.contains(desc.value, ",")
}

pub fn parse_empty_summary_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:\nUID:empty@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  let assert [event] = calendar.events
  assert event.summary == ""
}

pub fn parse_real_ical_file_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//caldav.icloud.com//CALDAVJ 2626B756//EN\nX-WR-CALNAME:Privat\nBEGIN:VEVENT\nCREATED:20171104T221935Z\nDTEND;TZID=Europe/Stockholm:20171128T203000\nDTSTAMP:20171125T133010Z\nDTSTART;TZID=Europe/Stockholm:20171128T193000\nLOCATION:Malmö Live\nSUMMARY:Anders och Måns\nUID:001E66D2-7DF8-40A8-B0BC-EBC4E3F9C2FD\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = gcal.parse(input)
  assert calendar.version == "2.0"
  assert calendar.prodid == "-//caldav.icloud.com//CALDAVJ 2626B756//EN"
  let assert [event] = calendar.events
  assert event.summary == "Anders och Måns"
  assert event.uid == "001E66D2-7DF8-40A8-B0BC-EBC4E3F9C2FD"
}
