import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import panchang/ical
import test_utils.{tzdb}

fn ical_parse(input: String) -> Result(ical.Calendar, ical.ParseError) {
  ical.new_parser(tzdb())
  |> ical.parse(input, None)
}

pub fn parse_simple_calendar_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)

  assert calendar.version == "2.0"
  assert calendar.prodid == "-//Test//EN"
  assert calendar.timezone == "UTC"
  assert calendar.events == []
}

pub fn parse_calendar_with_one_event_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      SUMMARY:Meeting
      DTSTART:20230101T100000Z
      DTEND:20230101T110000Z
      UID:123@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.summary == "Meeting"
  assert event.uid == "123@test"
  assert event.description == ""
  assert event.location == ""
  assert event.url == ""
  assert event.created == None
  assert event.last_modified == None
  assert event.dtstamp == None
}

pub fn parse_event_with_location_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      SUMMARY:Conference
      LOCATION:Stockholm
      UID:456@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.summary == "Conference"

  let assert Ok(loc) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "LOCATION" })
  assert loc.value == "Stockholm"
}

pub fn parse_event_with_parameters_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DTSTART;TZID=Europe/Stockholm:20230101T100000
      DTEND;TZID=Europe/Stockholm:20230101T110000
      SUMMARY:Test
      UID:789@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  assert event.dtstart != timestamp.unix_epoch
  assert event.dtend != timestamp.unix_epoch

  let assert Ok(dtstart_prop) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "DTSTART" })

  let assert [param] = dtstart_prop.params
  assert param.name == "TZID"
  assert param.value == "Europe/Stockholm"
}

pub fn parse_event_with_dtstart_dtend_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DTSTART:20230101T100000Z
      DTEND:20230101T110000Z
      SUMMARY:Timed
      UID:timed@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let #(start_secs, _) =
    timestamp.to_unix_seconds_and_nanoseconds(event.dtstart)
  assert start_secs == 1_672_567_200
  assert event.is_all_day == False
}

// verify multiple VEVENT components are all parsed into events
pub fn parse_multiple_events_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      SUMMARY:Event 1
      UID:1@test
      END:VEVENT
      BEGIN:VEVENT
      SUMMARY:Event 2
      UID:2@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [e1, e2] = calendar.events

  assert e1.summary == "Event 1"
  assert e2.summary == "Event 2"
}

// verify RFC 5545 line folding (continuation lines starting with space) is unfolded correctly
pub fn parse_folded_lines_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DESCRIPTION:This is a long des
       cription that spans
        multiple lines
      UID:fold@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(desc) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "DESCRIPTION" })
  assert desc.value == "This is a long description that spans multiple lines"
}

// verify escape sequences: \\n, \\N (newline), \\: (colon), \\\\n (literal \\n not newline)
pub fn parse_escaped_text_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DESCRIPTION:Line 1\\nLine 2 with\\, comma
      UID:esc@test
      END:VEVENT
      BEGIN:VEVENT
      DESCRIPTION:Line 1\\NLine 2
      UID:esc-capital@test
      END:VEVENT
      BEGIN:VEVENT
      DESCRIPTION:Time\\: 10
      UID:esc-colon@test
      END:VEVENT
      BEGIN:VEVENT
      DESCRIPTION:literal backslash and n\\\\n not a newline
      UID:esc-backslash-n@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let events = calendar.events

  let get_desc = fn(uid) {
    let assert Ok(event) = list.find(events, fn(e) { e.uid == uid })
    let assert Ok(prop) =
      list.find(event.raw, fn(p: ical.Property) { p.name == "DESCRIPTION" })
    prop.value
  }

  assert string.contains(get_desc("esc@test"), "\n")
  assert string.contains(get_desc("esc@test"), ",")
  assert string.contains(get_desc("esc-capital@test"), "\n")
  assert string.contains(get_desc("esc-colon@test"), "Time: 10")
  assert string.contains(get_desc("esc-backslash-n@test"), "\\n")
  assert False
    == string.contains(
      get_desc("esc-backslash-n@test"),
      "literal backslash and n\n",
    )
}

// verify empty SUMMARY value is preserved as empty string
pub fn parse_empty_summary_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      SUMMARY:
      UID:empty@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.summary == ""
}

// parse a real-world iCloud Calendar export, verify version, prodid, summary, uid
pub fn parse_real_ical_file_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//caldav.icloud.com//CALDAVJ 2626B756//EN
      X-WR-CALNAME:Privat
      BEGIN:VEVENT
      CREATED:20171104T221935Z
      DTEND;TZID=Europe/Stockholm:20171128T203000
      DTSTAMP:20171125T133010Z
      DTSTART;TZID=Europe/Stockholm:20171128T193000
      LOCATION:Malmö Live
      SUMMARY:Anders och Måns
      UID:001E66D2-7DF8-40A8-B0BC-EBC4E3F9C2FD
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  assert calendar.version == "2.0"
  assert calendar.prodid == "-//caldav.icloud.com//CALDAVJ 2626B756//EN"
  let assert [event] = calendar.events
  assert event.summary == "Anders och Måns"
  assert event.uid == "001E66D2-7DF8-40A8-B0BC-EBC4E3F9C2FD"
}

// verify properties with parameters (e.g. FMTTYPE) are available in raw properties
pub fn parse_property_with_params_in_raw_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      LOCATION;FMTTYPE=text/html:Conference Room
      SUMMARY:Test
      UID:params@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(loc_prop) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "LOCATION" })

  let assert [fmt] = loc_prop.params
  assert fmt.name == "FMTTYPE"
  assert fmt.value == "text/html"
  assert loc_prop.value == "Conference Room"
}

// parse a UTC datetime string (ending in Z)
pub fn parse_datetime_utc_test() {
  let prop = ical.Property("DTSTART", [], "20230101T100000Z")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_567_200
}

// parse a datetime with TZID=Europe/Stockholm in winter (CET, UTC+1)
pub fn parse_datetime_tzid_winter_test() {
  let param = ical.Parameter("TZID", "Europe/Stockholm")
  let prop = ical.Property("DTSTART", [param], "20230101T100000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_563_600
}

// parse a datetime with TZID=Europe/Stockholm in summer (CEST, UTC+2)
pub fn parse_datetime_tzid_summer_test() {
  let param = ical.Parameter("TZID", "Europe/Stockholm")
  let prop = ical.Property("DTSTART", [param], "20230601T100000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_685_606_400
}

// parse a DATE-only value (no time component, VALUE=DATE)
pub fn parse_datetime_date_only_test() {
  let param = ical.Parameter("VALUE", "DATE")
  let prop = ical.Property("DTSTART", [param], "20230101")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_531_200
}

// parse a floating datetime (no Z, no TZID) with an explicit timezone override (Europe/Stockholm)
pub fn parse_datetime_floating_with_tz_test() {
  let prop = ical.Property("DTSTART", [], "20230101T100000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "Europe/Stockholm")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_563_600
}

// parse a floating datetime treated as UTC (no timezone override)
pub fn parse_datetime_floating_as_utc_test() {
  let prop = ical.Property("DTSTART", [], "20230101T100000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_567_200
}

// parse an invalid datetime string returns unix_epoch
pub fn parse_datetime_invalid_test() {
  let prop = ical.Property("DTSTART", [], "not-a-date")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  assert ts == timestamp.unix_epoch
}

// parse an empty datetime string returns unix_epoch
pub fn parse_datetime_empty_test() {
  let prop = ical.Property("DTSTART", [], "")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  assert ts == timestamp.unix_epoch
}

// parse a UTC datetime with lowercase "z" suffix
pub fn parse_datetime_lowercase_z_test() {
  let prop = ical.Property("DTSTART", [], "20230101t100000z")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_567_200
}

// parse a datetime that falls in a DST gap (spring forward) — America/New_York
pub fn parse_datetime_dst_gap_test() {
  let param = ical.Parameter("TZID", "America/New_York")
  let prop = ical.Property("DTSTART", [param], "20240310T033000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_710_055_800
}

// parse a datetime that falls in a DST overlap (fall back) — Europe/Stockholm
pub fn parse_datetime_dst_overlap_test() {
  let param = ical.Parameter("TZID", "Europe/Stockholm")
  let prop = ical.Property("DTSTART", [param], "20241027T023000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_729_989_000
}

// parse a calendar with floating datetime using Europe/Stockholm timezone override
pub fn parse_calendar_with_timezone_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DTSTART:20230101T100000
      SUMMARY:Floating
      UID:float@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, Some("Europe/Stockholm"))

  assert calendar.timezone == "Europe/Stockholm"

  let assert [event] = calendar.events
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(event.dtstart)
  assert secs == 1_672_563_600
}

// parse a calendar with floating datetime using America/New_York timezone override
pub fn parse_with_timezone_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DTSTART:20230101T100000
      SUMMARY:Floating
      UID:float@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, Some("America/New_York"))

  assert calendar.timezone == "America/New_York"

  let assert [event] = calendar.events
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(event.dtstart)
  assert secs == 1_672_585_200
}

// verify all-day detection with VALUE=DATE (uppercase and lowercase parameter)
pub fn event_is_all_day_test() {
  let parse = fn(raw) {
    let assert Ok(calendar) = ical_parse(raw)
    let assert [event] = calendar.events
    event
  }

  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DTSTART;VALUE=DATE:20230101
      DTEND;VALUE=DATE:20230102
      SUMMARY:All day
      UID:allday@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  assert parse(input).is_all_day == True

  let input_lower =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DTSTART;value=date:20230101
      DTEND;value=date:20230102
      SUMMARY:All day
      UID:allday@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  assert parse(input_lower).is_all_day == True
}

// verify a timed event with TZID is not marked as all-day
pub fn event_not_all_day_with_tzid_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DTSTART;TZID=Europe/Stockholm:20230101T100000
      DTEND;TZID=Europe/Stockholm:20230101T110000
      SUMMARY:Timed
      UID:timed@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.is_all_day == False
}

// verify description, location, url, created, last-modified, and dtstamp fields
pub fn parse_event_details_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      SUMMARY:Team Offsite
      DESCRIPTION:Annual planning session
      LOCATION:Stockholm
      URL:https://example.com/offsite
      DTSTART:20230101T100000Z
      DTEND:20230101T110000Z
      UID:details@test
      END:VEVENT
      BEGIN:VEVENT
      SUMMARY:Meeting
      CREATED:20230101T080000Z
      LAST-MODIFIED:20230102T090000Z
      DTSTART:20230101T100000Z
      DTEND:20230101T110000Z
      UID:timestamps@test
      END:VEVENT
      BEGIN:VEVENT
      SUMMARY:Meeting
      DTSTAMP:20230101T120000Z
      DTSTART:20230101T100000Z
      DTEND:20230101T110000Z
      UID:dtstamp@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let events = calendar.events

  let assert Ok(details) = list.find(events, fn(e) { e.uid == "details@test" })
  assert details.summary == "Team Offsite"
  assert details.description == "Annual planning session"
  assert details.location == "Stockholm"
  assert details.url == "https://example.com/offsite"

  let assert Ok(ts) = list.find(events, fn(e) { e.uid == "timestamps@test" })
  let assert Some(created) = ts.created
  let #(created_secs, _) = timestamp.to_unix_seconds_and_nanoseconds(created)
  assert created_secs == 1_672_560_000
  let assert Some(last_modified) = ts.last_modified
  let #(modified_secs, _) =
    timestamp.to_unix_seconds_and_nanoseconds(last_modified)
  assert modified_secs == 1_672_650_000

  let assert Ok(dstamp) = list.find(events, fn(e) { e.uid == "dtstamp@test" })
  let assert Some(dtstamp) = dstamp.dtstamp
  let #(dtstamp_secs, _) = timestamp.to_unix_seconds_and_nanoseconds(dtstamp)
  assert dtstamp_secs == 1_672_574_400
}

// parse a calendar as a tree, verify root component kind and properties
pub fn parse_tree_root_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(root) = ical.parse_tree(ical.new_parser(tzdb()), input)

  assert root.kind == "VCALENDAR"
  assert root.children == []

  let assert Ok(version_prop) =
    list.find(root.properties, fn(p) { p.name == "VERSION" })
  assert version_prop.value == "2.0"

  let assert Ok(prodid_prop) =
    list.find(root.properties, fn(p) { p.name == "PRODID" })
  assert prodid_prop.value == "-//Test//EN"
}

// parse a tree with a VEVENT child, verify child kind and properties
pub fn parse_tree_events_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      SUMMARY:Meeting
      UID:meeting@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(root) = ical.parse_tree(ical.new_parser(tzdb()), input)

  assert root.kind == "VCALENDAR"

  let assert [event] = root.children
  assert event.kind == "VEVENT"
  assert event.children == []

  let assert Ok(summary_prop) =
    list.find(event.properties, fn(p) { p.name == "SUMMARY" })
  assert summary_prop.value == "Meeting"
}

// parse a tree with a nested VALARM inside VEVENT, verify nested component structure
pub fn parse_tree_nested_alarm_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      SUMMARY:Meeting
      UID:alarm@test
      BEGIN:VALARM
      ACTION:DISPLAY
      DESCRIPTION:Reminder
      END:VALARM
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(root) = ical.parse_tree(ical.new_parser(tzdb()), input)

  let assert [event] = root.children
  assert event.kind == "VEVENT"

  let assert [alarm] = event.children
  assert alarm.kind == "VALARM"

  let assert Ok(action) =
    list.find(alarm.properties, fn(p) { p.name == "ACTION" })
  assert action.value == "DISPLAY"
}

// parse_tree rejects input with multiple root components
pub fn parse_tree_multiple_roots_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      END:VCALENDAR
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Error(_) = ical.parse_tree(ical.new_parser(tzdb()), input)
}

// parse_tree rejects empty input
pub fn parse_tree_empty_test() {
  let input = ""
  let assert Error(_) = ical.parse_tree(ical.new_parser(tzdb()), input)
}

// -------- duration parsing
// PT1H = 1 hour
pub fn parse_duration_hour_test() {
  let assert Ok(dur) = ical.parse_duration("PT1H")
  assert duration.to_seconds(dur) == 3600.0
}

// PT30M = 30 minutes
pub fn parse_duration_minute_test() {
  let assert Ok(dur) = ical.parse_duration("PT30M")
  assert duration.to_seconds(dur) == 1800.0
}

// P1D = 1 day
pub fn parse_duration_day_test() {
  let assert Ok(dur) = ical.parse_duration("P1D")
  assert duration.to_seconds(dur) == 86_400.0
}

// P1W = 1 week
pub fn parse_duration_week_test() {
  let assert Ok(dur) = ical.parse_duration("P1W")
  assert duration.to_seconds(dur) == 604_800.0
}

// P1DT2H3M4S = 1 day + 2 hours + 3 minutes + 4 seconds
pub fn parse_duration_combined_test() {
  let assert Ok(dur) = ical.parse_duration("P1DT2H3M4S")
  assert duration.to_seconds(dur) == 93_784.0
}

// PT1H30M = 1 hour 30 minutes
pub fn parse_duration_hour_minute_test() {
  let assert Ok(dur) = ical.parse_duration("PT1H30M")
  assert duration.to_seconds(dur) == 5400.0
}

// PT1H30M10S = 1 hour 30 minutes 10 seconds
pub fn parse_duration_hour_minute_second_test() {
  let assert Ok(dur) = ical.parse_duration("PT1H30M10S")
  assert duration.to_seconds(dur) == 5410.0
}

// -PT30M = negative 30 minutes
pub fn parse_duration_negative_test() {
  let assert Ok(dur) = ical.parse_duration("-PT30M")
  assert duration.to_seconds(dur) == -1800.0
}

// +PT1H = positive 1 hour with explicit sign
pub fn parse_duration_positive_sign_test() {
  let assert Ok(dur) = ical.parse_duration("+PT1H")
  assert duration.to_seconds(dur) == 3600.0
}

// PT1.5S — fractional seconds should error
pub fn parse_duration_fractional_seconds_error_test() {
  let assert Error(_) = ical.parse_duration("PT1.5S")
}

// pt1h — lowercase duration designator is accepted
pub fn parse_duration_lowercase_test() {
  let assert Ok(dur) = ical.parse_duration("pt1h")
  assert duration.to_seconds(dur) == 3600.0
}

// T1H — missing P prefix should error
pub fn parse_duration_missing_p_test() {
  let assert Error(_) = ical.parse_duration("T1H")
}

// P1X — invalid unit should error
pub fn parse_duration_invalid_unit_test() {
  let assert Error(_) = ical.parse_duration("P1X")
}

// P1DT — empty time section after T should error
pub fn parse_duration_empty_time_after_t_test() {
  let assert Error(_) = ical.parse_duration("P1DT")
}

// PTM — missing number before M should error
pub fn parse_duration_missing_number_test() {
  let assert Error(_) = ical.parse_duration("PTM")
}

// P2H — hours without T designator are accepted as duration suffix
pub fn parse_duration_no_t_required_test() {
  let assert Ok(dur) = ical.parse_duration("P2H")
  assert duration.to_seconds(dur) == 7200.0
}

// P2H2H — duplicate unit accumulates (2 hours + 2 hours = 4 hours)
pub fn parse_duration_duplicate_units_test() {
  let assert Ok(dur) = ical.parse_duration("P2H2H")
  assert duration.to_seconds(dur) == 14_400.0
}

// P30S2M — out-of-order units (seconds before minutes) are accepted
pub fn parse_duration_out_of_order_test() {
  let assert Ok(dur) = ical.parse_duration("P30S2M")
  assert duration.to_seconds(dur) == 150.0
}

// get_property finds a property by name from raw, returns Error for missing names
pub fn get_property_test() {
  let event =
    ical.Event(
      uid: "123@test",
      summary: "Meeting",
      description: "",
      location: "",
      url: "",
      dtstart: timestamp.unix_epoch,
      dtend: timestamp.unix_epoch,
      created: None,
      last_modified: None,
      dtstamp: None,
      organizer: None,
      attendees: [],
      is_all_day: False,
      raw: [
        ical.Property(
          "DTSTART",
          [ical.Parameter("TZID", "Europe/Stockholm")],
          "20230101T100000",
        ),
        ical.Property("SUMMARY", [], "Meeting"),
        ical.Property("UID", [], "123@test"),
      ],
    )

  let assert Ok(prop) = ical.get_property(event, "DTSTART")
  assert prop.name == "DTSTART"
  assert prop.value == "20230101T100000"
  assert list.length(prop.params) == 1

  let assert Error(Nil) = ical.get_property(event, "LOCATION")
}

// get_parameter finds a parameter by name from a property, returns Error for missing
pub fn get_parameter_test() {
  let prop =
    ical.Property(
      "DTSTART",
      [
        ical.Parameter("TZID", "Europe/Stockholm"),
        ical.Parameter("VALUE", "DATE-TIME"),
      ],
      "20230101T100000",
    )

  let assert Ok("Europe/Stockholm") = ical.get_parameter(prop, "TZID")
  let assert Ok("DATE-TIME") = ical.get_parameter(prop, "VALUE")
  let assert Error(Nil) = ical.get_parameter(prop, "NONEXISTENT")
  let empty_prop = ical.Property("SUMMARY", [], "Meeting")
  let assert Error(Nil) = ical.get_parameter(empty_prop, "TZID")
}

// ATTENDEE with CN and RSVP parameters — get_property + get_parameter combined
pub fn get_property_and_parameter_combined_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      ATTENDEE;CN=John;RSVP=TRUE:mailto:john@example.com
      SUMMARY:Meeting
      UID:123@test
      END:VEVENT
      END:VCALENDAR"
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(attendee) = ical.get_property(event, "ATTENDEE")
  assert attendee.value == "mailto:john@example.com"

  let assert Ok("John") = ical.get_parameter(attendee, "CN")
  let assert Ok("TRUE") = ical.get_parameter(attendee, "RSVP")
  let assert Error(Nil) = ical.get_parameter(attendee, "EMAIL")
}

// lowercase begin/end component names (begin:vcalendar, end:vevent) are accepted
pub fn parse_lowercase_component_names_test() {
  let input =
    "
      begin:vcalendar
      VERSION:2.0
      PRODID:-//Test//EN
      begin:vevent
      SUMMARY:Lowercase
      UID:lowercase@test
      end:vevent
      end:vcalendar
      "
    |> test_utils.trim_margin

  let assert Ok(calendar) = ical_parse(input)

  assert calendar.version == "2.0"
  assert calendar.prodid == "-//Test//EN"

  let assert [event] = calendar.events
  assert event.summary == "Lowercase"
  assert event.uid == "lowercase@test"
}

// lowercase property names and parameter names are accepted
pub fn parse_lowercase_property_names_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      summary:Lowercase Summary
      uid:lowercase-prop@test
      END:VEVENT
      BEGIN:VEVENT
      DTSTART;tzid=Europe/Stockholm:20230101T100000
      SUMMARY:Timed
      UID:lowercase-param@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let events = calendar.events

  let assert Ok(prop_event) =
    list.find(events, fn(e) { e.uid == "lowercase-prop@test" })
  assert prop_event.summary == "Lowercase Summary"
  assert prop_event.uid == "lowercase-prop@test"

  let assert Ok(param_event) =
    list.find(events, fn(e) { e.uid == "lowercase-param@test" })
  let assert Ok(dtstart_prop) =
    list.find(param_event.raw, fn(p: ical.Property) { p.name == "DTSTART" })
  let assert [p] = dtstart_prop.params
  assert p.name == "TZID"
  assert p.value == "Europe/Stockholm"
  let assert #(1_672_563_600, _) =
    timestamp.to_unix_seconds_and_nanoseconds(param_event.dtstart)
}

// get_property is case-insensitive when searching by name
pub fn get_property_lowercase_search_test() {
  let event =
    ical.Event(
      uid: "123@test",
      summary: "Meeting",
      description: "",
      location: "",
      url: "",
      dtstart: timestamp.unix_epoch,
      dtend: timestamp.unix_epoch,
      created: None,
      last_modified: None,
      dtstamp: None,
      organizer: None,
      attendees: [],
      is_all_day: False,
      raw: [ical.Property("DTSTART", [], "20230101T100000Z")],
    )

  let assert Ok(prop) = ical.get_property(event, "dtstart")
  assert prop.name == "DTSTART"
  assert prop.value == "20230101T100000Z"
}

// get_parameter is case-insensitive when searching by name
pub fn get_parameter_lowercase_search_test() {
  let prop =
    ical.Property(
      "DTSTART",
      [ical.Parameter("TZID", "Europe/Stockholm")],
      "20230101T100000",
    )

  let assert Ok("Europe/Stockholm") = ical.get_parameter(prop, "tzid")
}

// quoted parameter values preserving semicolons, colons, equals, escaped quotes, and backslashes
pub fn parse_quoted_params_test() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      ATTENDEE;CN=\"Doe; John\":mailto:john@example.com
      SUMMARY:Meeting
      UID:quoted-semi@test
      END:VEVENT
      BEGIN:VEVENT
      ATTENDEE;CN=\"Doe: John\":mailto:john@example.com
      SUMMARY:Meeting
      UID:quoted-colon@test
      END:VEVENT
      BEGIN:VEVENT
      ATTENDEE;CN=\"Doe=John\":mailto:john@example.com
      SUMMARY:Meeting
      UID:quoted-eq@test
      END:VEVENT
      BEGIN:VEVENT
      ATTENDEE;CN=\"Doe\\\"John\":mailto:john@example.com
      SUMMARY:Meeting
      UID:quoted-escquote@test
      END:VEVENT
      BEGIN:VEVENT
      ATTENDEE;CN=\"Doe\\\\John\":mailto:john@example.com
      SUMMARY:Meeting
      UID:quoted-escback@test
      END:VEVENT
      BEGIN:VEVENT
      ATTENDEE;CN=\"Doe; John\";ROLE=\"REQ-PARTICIPANT\":mailto:john@example.com
      SUMMARY:Meeting
      UID:quoted-multi@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let events = calendar.events

  let check = fn(uid, expected_cn, expected_role) {
    let assert Ok(event) = list.find(events, fn(e) { e.uid == uid })
    let assert Ok(att) = ical.get_property(event, "ATTENDEE")
    assert att.value == "mailto:john@example.com"
    let assert Ok(cn) = ical.get_parameter(att, "CN")
    assert cn == expected_cn
    case expected_role {
      Some(role) -> {
        let assert Ok(r) = ical.get_parameter(att, "ROLE")
        assert r == role
      }
      None -> Nil
    }
  }

  check("quoted-semi@test", "Doe; John", None)
  check("quoted-colon@test", "Doe: John", None)
  check("quoted-eq@test", "Doe=John", None)
  check("quoted-escquote@test", "Doe\"John", None)
  check("quoted-escback@test", "Doe\\John", None)
  check("quoted-multi@test", "Doe; John", Some("REQ-PARTICIPANT"))
}

fn make_test_parser() -> ical.Parser {
  ical.new_parser(tzdb())
}

// DURATION fallback when DTEND is missing; DTEND takes priority over DURATION; unix_epoch when both are missing
pub fn event_dtend_tests() {
  let input =
    "
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Test//EN
      BEGIN:VEVENT
      DTSTART:20230101T100000Z
      DURATION:PT1H
      SUMMARY:Duration event
      UID:duration@test
      END:VEVENT
      BEGIN:VEVENT
      DTSTART:20230101T100000Z
      DTEND:20230101T120000Z
      DURATION:PT30M
      SUMMARY:Both dtend and duration
      UID:both@test
      END:VEVENT
      BEGIN:VEVENT
      DTSTART:20230101T100000Z
      SUMMARY:No dtend no duration
      UID:no-end@test
      END:VEVENT
      END:VCALENDAR
      "
    |> test_utils.trim_margin
  let assert Ok(calendar) = ical_parse(input)
  let events = calendar.events

  let assert Ok(dur) = list.find(events, fn(e) { e.uid == "duration@test" })
  let #(dur_end, _) = timestamp.to_unix_seconds_and_nanoseconds(dur.dtend)
  assert dur_end == 1_672_570_800

  let assert Ok(both) = list.find(events, fn(e) { e.uid == "both@test" })
  let #(both_end, _) = timestamp.to_unix_seconds_and_nanoseconds(both.dtend)
  assert both_end == 1_672_574_400

  let assert Ok(no_end) = list.find(events, fn(e) { e.uid == "no-end@test" })
  assert no_end.dtend == timestamp.unix_epoch
}
