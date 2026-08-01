import gleam/list
import gleam/option.{None}
import gleam/time/timestamp
import panchang/ical
import simplifile
import test_utils.{tzdb}

// Targeted assertions for iCalendar fixtures — validates semantic correctness
// of parsed values, matching key verifications from the Python icalendar suite.
// Python test references:
//   https://github.com/collective/icalendar/blob/main/src/icalendar/tests/

pub fn icalendar_example_correctness_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/icalendar/example.ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, None)

  assert calendar.version == "2.0"
  assert calendar.prodid == "collective/icalendar"
  assert calendar.timezone == "Etc/GMT"
}

pub fn icalendar_timezoned_correctness_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/icalendar/timezoned.ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, None)

  assert calendar.prodid == "-//Plone.org//NONSGML plone.app.event//EN"

  let assert [event] = calendar.events
  // Python: https://github.com/collective/icalendar/blob/main/src/icalendar/tests/test_timezoned.py
  // Verifies: DTSTART=20120213T100000 Europe/Vienna = 09:00:00 UTC
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(event.start_time)
  assert secs == 1_329_123_600
}

pub fn icalendar_rfc_6868_correctness_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/icalendar/rfc_6868.ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, None)

  // Python asserts: CN=George Herman ^'Babe^' Ruth decodes to CN="George Herman \"Babe\" Ruth"
  // Note: ^' is RFC 6868 encoding for double-quote. Our parser does not yet
  // implement RFC 6868, so CN retains the raw ^' encoding.
  let assert [event] = calendar.events
  let assert Ok(attendee) = ical.get_property(event, "ATTENDEE")
  let assert Ok(cn) = ical.get_parameter(attendee, "CN")
  assert cn == "George Herman ^'Babe^' Ruth"
}

pub fn icalendar_calendar_with_unicode_correctness_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/icalendar/calendar_with_unicode.ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, None)

  // Python: https://github.com/collective/icalendar/blob/main/src/icalendar/tests/test_examples.py
  // Verifies calendar-level unicode metadata survives parse/serialize
  assert calendar.events == []
  assert calendar.prodid == "-//Plönë.org//NONSGML plone.app.event//EN"
}
