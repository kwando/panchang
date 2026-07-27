import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/timestamp
import global_value
import panchang/ical
import tzif/database

fn ical_parse(input: String) -> Result(ical.Calendar, ical.ParseError) {
  ical.new_parser(tzdb())
  |> ical.parse(input, None)
}

pub fn parse_simple_calendar_test() {
  let input = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)

  assert calendar.version == "2.0"
  assert calendar.prodid == "-//Test//EN"
  assert calendar.timezone == "UTC"
  assert calendar.events == []
}

pub fn parse_calendar_with_one_event_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Meeting\nUID:123@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)

  let assert [event] = calendar.events
  assert event.summary == "Meeting"
  assert event.uid == "123@test"
}

pub fn parse_event_with_location_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Conference\nLOCATION:Stockholm\nUID:456@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.summary == "Conference"

  let assert Ok(loc) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "LOCATION" })
  assert loc.value == "Stockholm"
}

pub fn parse_event_with_parameters_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART;TZID=Europe/Stockholm:20230101T100000\nDTEND;TZID=Europe/Stockholm:20230101T110000\nSUMMARY:Test\nUID:789@test\nEND:VEVENT\nEND:VCALENDAR"
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
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART:20230101T100000Z\nDTEND:20230101T110000Z\nSUMMARY:Timed\nUID:timed@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let #(start_secs, _) =
    timestamp.to_unix_seconds_and_nanoseconds(event.dtstart)
  assert start_secs == 1_672_567_200
}

pub fn parse_multiple_events_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Event 1\nUID:1@test\nEND:VEVENT\nBEGIN:VEVENT\nSUMMARY:Event 2\nUID:2@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [e1, e2] = calendar.events

  assert e1.summary == "Event 1"
  assert e2.summary == "Event 2"
}

pub fn parse_folded_lines_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDESCRIPTION:This is a long des\n cription that spans\n  multiple lines\nUID:fold@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(desc) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "DESCRIPTION" })
  assert desc.value == "This is a long description that spans multiple lines"
}

pub fn parse_escaped_text_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDESCRIPTION:Line 1\\nLine 2 with\\, comma\nUID:esc@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(desc) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "DESCRIPTION" })
  assert string.contains(desc.value, "\n")
  assert string.contains(desc.value, ",")
}

pub fn parse_escaped_capital_newline_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDESCRIPTION:Line 1\\NLine 2\nUID:esc-capital@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(desc) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "DESCRIPTION" })
  assert string.contains(desc.value, "\n")
}

pub fn parse_escaped_colon_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDESCRIPTION:Time\\: 10\nUID:esc-colon@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(desc) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "DESCRIPTION" })
  assert string.contains(desc.value, "Time: 10")
}

pub fn parse_escaped_backslash_before_newline_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDESCRIPTION:literal backslash and n\\\\n not a newline\nUID:esc-backslash-n@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(desc) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "DESCRIPTION" })
  assert string.contains(desc.value, "\\n")
  assert False == string.contains(desc.value, "literal backslash and n\n")
}

pub fn parse_empty_summary_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:\nUID:empty@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.summary == ""
}

pub fn parse_real_ical_file_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//caldav.icloud.com//CALDAVJ 2626B756//EN\nX-WR-CALNAME:Privat\nBEGIN:VEVENT\nCREATED:20171104T221935Z\nDTEND;TZID=Europe/Stockholm:20171128T203000\nDTSTAMP:20171125T133010Z\nDTSTART;TZID=Europe/Stockholm:20171128T193000\nLOCATION:Malmö Live\nSUMMARY:Anders och Måns\nUID:001E66D2-7DF8-40A8-B0BC-EBC4E3F9C2FD\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  assert calendar.version == "2.0"
  assert calendar.prodid == "-//caldav.icloud.com//CALDAVJ 2626B756//EN"
  let assert [event] = calendar.events
  assert event.summary == "Anders och Måns"
  assert event.uid == "001E66D2-7DF8-40A8-B0BC-EBC4E3F9C2FD"
}

pub fn parse_property_with_params_in_raw_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nLOCATION;FMTTYPE=text/html:Conference Room\nSUMMARY:Test\nUID:params@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(loc_prop) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "LOCATION" })

  let assert [fmt] = loc_prop.params
  assert fmt.name == "FMTTYPE"
  assert fmt.value == "text/html"
  assert loc_prop.value == "Conference Room"
}

pub fn parse_datetime_utc_test() {
  let prop = ical.Property("DTSTART", [], "20230101T100000Z")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_567_200
}

pub fn parse_datetime_tzid_winter_test() {
  let param = ical.Parameter("TZID", "Europe/Stockholm")
  let prop = ical.Property("DTSTART", [param], "20230101T100000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_563_600
}

pub fn parse_datetime_tzid_summer_test() {
  let param = ical.Parameter("TZID", "Europe/Stockholm")
  let prop = ical.Property("DTSTART", [param], "20230601T100000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_685_606_400
}

pub fn parse_datetime_date_only_test() {
  let param = ical.Parameter("VALUE", "DATE")
  let prop = ical.Property("DTSTART", [param], "20230101")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_531_200
}

pub fn parse_datetime_floating_with_tz_test() {
  let prop = ical.Property("DTSTART", [], "20230101T100000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "Europe/Stockholm")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_563_600
}

pub fn parse_datetime_floating_as_utc_test() {
  let prop = ical.Property("DTSTART", [], "20230101T100000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_567_200
}

pub fn parse_datetime_invalid_test() {
  let prop = ical.Property("DTSTART", [], "not-a-date")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  assert ts == timestamp.unix_epoch
}

pub fn parse_datetime_empty_test() {
  let prop = ical.Property("DTSTART", [], "")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  assert ts == timestamp.unix_epoch
}

pub fn parse_datetime_lowercase_z_test() {
  let prop = ical.Property("DTSTART", [], "20230101t100000z")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_672_567_200
}

pub fn parse_datetime_dst_gap_test() {
  let param = ical.Parameter("TZID", "America/New_York")
  let prop = ical.Property("DTSTART", [param], "20240310T033000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_710_055_800
}

pub fn parse_datetime_dst_overlap_test() {
  let param = ical.Parameter("TZID", "Europe/Stockholm")
  let prop = ical.Property("DTSTART", [param], "20241027T023000")
  let parser = make_test_parser()
  let ts = ical.parse_datetime(prop, parser, "UTC")
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  assert secs == 1_729_989_000
}

pub fn parse_calendar_with_timezone_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART:20230101T100000\nSUMMARY:Floating\nUID:float@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, Some("Europe/Stockholm"))

  assert calendar.timezone == "Europe/Stockholm"

  let assert [event] = calendar.events
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(event.dtstart)
  assert secs == 1_672_563_600
}

pub fn parse_with_timezone_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART:20230101T100000\nSUMMARY:Floating\nUID:float@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, Some("America/New_York"))

  assert calendar.timezone == "America/New_York"

  let assert [event] = calendar.events
  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(event.dtstart)
  assert secs == 1_672_585_200
}

pub fn event_is_all_day_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART;VALUE=DATE:20230101\nDTEND;VALUE=DATE:20230102\nSUMMARY:All day\nUID:allday@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.is_all_day == True
}

pub fn event_not_all_day_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART:20230101T100000Z\nDTEND:20230101T110000Z\nSUMMARY:Timed\nUID:timed@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.is_all_day == False
}

pub fn event_not_all_day_with_tzid_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART;TZID=Europe/Stockholm:20230101T100000\nDTEND;TZID=Europe/Stockholm:20230101T110000\nSUMMARY:Timed\nUID:timed@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.is_all_day == False
}

pub fn parse_event_description_location_url_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Team Offsite\nDESCRIPTION:Annual planning session\nLOCATION:Stockholm\nURL:https://example.com/offsite\nDTSTART:20230101T100000Z\nDTEND:20230101T110000Z\nUID:details@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  assert event.summary == "Team Offsite"
  assert event.description == "Annual planning session"
  assert event.location == "Stockholm"
  assert event.url == "https://example.com/offsite"
}

pub fn parse_event_created_last_modified_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Meeting\nCREATED:20230101T080000Z\nLAST-MODIFIED:20230102T090000Z\nDTSTART:20230101T100000Z\nDTEND:20230101T110000Z\nUID:timestamps@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Some(created) = event.created
  let #(created_secs, _) = timestamp.to_unix_seconds_and_nanoseconds(created)
  assert created_secs == 1_672_560_000

  let assert Some(last_modified) = event.last_modified
  let #(modified_secs, _) =
    timestamp.to_unix_seconds_and_nanoseconds(last_modified)
  assert modified_secs == 1_672_650_000
}

pub fn parse_event_dtstamp_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Meeting\nDTSTAMP:20230101T120000Z\nDTSTART:20230101T100000Z\nDTEND:20230101T110000Z\nUID:dtstamp@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Some(dtstamp) = event.dtstamp
  let #(dtstamp_secs, _) = timestamp.to_unix_seconds_and_nanoseconds(dtstamp)
  assert dtstamp_secs == 1_672_574_400
}

pub fn parse_event_missing_optional_fields_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Minimal\nDTSTART:20230101T100000Z\nDTEND:20230101T110000Z\nUID:minimal@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  assert event.description == ""
  assert event.location == ""
  assert event.url == ""
  assert event.created == None
  assert event.last_modified == None
  assert event.dtstamp == None
}

pub fn parse_tree_root_test() {
  let input = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nEND:VCALENDAR"
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

pub fn parse_tree_events_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Meeting\nUID:meeting@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(root) = ical.parse_tree(ical.new_parser(tzdb()), input)

  assert root.kind == "VCALENDAR"

  let assert [event] = root.children
  assert event.kind == "VEVENT"
  assert event.children == []

  let assert Ok(summary_prop) =
    list.find(event.properties, fn(p) { p.name == "SUMMARY" })
  assert summary_prop.value == "Meeting"
}

pub fn parse_tree_nested_alarm_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nSUMMARY:Meeting\nUID:alarm@test\nBEGIN:VALARM\nACTION:DISPLAY\nDESCRIPTION:Reminder\nEND:VALARM\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(root) = ical.parse_tree(ical.new_parser(tzdb()), input)

  let assert [event] = root.children
  assert event.kind == "VEVENT"

  let assert [alarm] = event.children
  assert alarm.kind == "VALARM"

  let assert Ok(action) =
    list.find(alarm.properties, fn(p) { p.name == "ACTION" })
  assert action.value == "DISPLAY"
}

pub fn parse_tree_multiple_roots_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nEND:VCALENDAR\nBEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nEND:VCALENDAR"
  let assert Error(_) = ical.parse_tree(ical.new_parser(tzdb()), input)
}

pub fn parse_tree_empty_test() {
  let input = ""
  let assert Error(_) = ical.parse_tree(ical.new_parser(tzdb()), input)
}

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

  let assert Ok(tz) = ical.get_parameter(prop, "TZID")
  assert tz == "Europe/Stockholm"

  let assert Ok(val) = ical.get_parameter(prop, "VALUE")
  assert val == "DATE-TIME"

  let assert Error(Nil) = ical.get_parameter(prop, "NONEXISTENT")

  let empty_prop = ical.Property("SUMMARY", [], "Meeting")
  let assert Error(Nil) = ical.get_parameter(empty_prop, "TZID")
}

pub fn get_property_and_parameter_combined_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nATTENDEE;CN=John;RSVP=TRUE:mailto:john@example.com\nSUMMARY:Meeting\nUID:123@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(attendee) = ical.get_property(event, "ATTENDEE")
  assert attendee.value == "mailto:john@example.com"

  let assert Ok(cn) = ical.get_parameter(attendee, "CN")
  assert cn == "John"

  let assert Ok(rsvp) = ical.get_parameter(attendee, "RSVP")
  assert rsvp == "TRUE"

  let assert Error(Nil) = ical.get_parameter(attendee, "EMAIL")
}

pub fn parse_lowercase_component_names_test() {
  let input =
    "begin:vcalendar\nVERSION:2.0\nPRODID:-//Test//EN\nbegin:vevent\nSUMMARY:Lowercase\nUID:lowercase@test\nend:vevent\nend:vcalendar"
  let assert Ok(calendar) = ical_parse(input)

  assert calendar.version == "2.0"
  assert calendar.prodid == "-//Test//EN"

  let assert [event] = calendar.events
  assert event.summary == "Lowercase"
  assert event.uid == "lowercase@test"
}

pub fn parse_lowercase_property_names_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nsummary:Lowercase Summary\nuid:lowercase@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)

  let assert [event] = calendar.events
  assert event.summary == "Lowercase Summary"
  assert event.uid == "lowercase@test"
}

pub fn parse_lowercase_parameter_name_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART;tzid=Europe/Stockholm:20230101T100000\nSUMMARY:Timed\nUID:timed@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)

  let assert [event] = calendar.events
  let assert Ok(dtstart_prop) =
    list.find(event.raw, fn(p: ical.Property) { p.name == "DTSTART" })
  let assert [param] = dtstart_prop.params
  assert param.name == "TZID"
  assert param.value == "Europe/Stockholm"

  let #(secs, _) = timestamp.to_unix_seconds_and_nanoseconds(event.dtstart)
  assert secs == 1_672_563_600
}

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
      is_all_day: False,
      raw: [ical.Property("DTSTART", [], "20230101T100000Z")],
    )

  let assert Ok(prop) = ical.get_property(event, "dtstart")
  assert prop.name == "DTSTART"
  assert prop.value == "20230101T100000Z"
}

pub fn get_parameter_lowercase_search_test() {
  let prop =
    ical.Property(
      "DTSTART",
      [ical.Parameter("TZID", "Europe/Stockholm")],
      "20230101T100000",
    )

  let assert Ok(tz) = ical.get_parameter(prop, "tzid")
  assert tz == "Europe/Stockholm"
}

pub fn parse_lowercase_value_date_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nDTSTART;value=date:20230101\nDTEND;value=date:20230102\nSUMMARY:All day\nUID:allday@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events
  assert event.is_all_day == True
}

pub fn parse_quoted_param_with_semicolon_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nATTENDEE;CN=\"Doe; John\":mailto:john@example.com\nSUMMARY:Meeting\nUID:quoted-semi@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(attendee) = ical.get_property(event, "ATTENDEE")
  assert attendee.value == "mailto:john@example.com"

  let assert Ok(cn) = ical.get_parameter(attendee, "CN")
  assert cn == "Doe; John"
}

pub fn parse_quoted_param_with_colon_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nATTENDEE;CN=\"Doe: John\":mailto:john@example.com\nSUMMARY:Meeting\nUID:quoted-colon@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(attendee) = ical.get_property(event, "ATTENDEE")
  assert attendee.value == "mailto:john@example.com"

  let assert Ok(cn) = ical.get_parameter(attendee, "CN")
  assert cn == "Doe: John"
}

pub fn parse_quoted_param_with_equals_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nATTENDEE;CN=\"Doe=John\":mailto:john@example.com\nSUMMARY:Meeting\nUID:quoted-eq@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(attendee) = ical.get_property(event, "ATTENDEE")
  assert attendee.value == "mailto:john@example.com"

  let assert Ok(cn) = ical.get_parameter(attendee, "CN")
  assert cn == "Doe=John"
}

pub fn parse_quoted_param_with_escaped_quote_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nATTENDEE;CN=\"Doe\\\"John\":mailto:john@example.com\nSUMMARY:Meeting\nUID:quoted-escquote@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(attendee) = ical.get_property(event, "ATTENDEE")
  assert attendee.value == "mailto:john@example.com"

  let assert Ok(cn) = ical.get_parameter(attendee, "CN")
  assert cn == "Doe\"John"
}

pub fn parse_quoted_param_with_escaped_backslash_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nATTENDEE;CN=\"Doe\\\\John\":mailto:john@example.com\nSUMMARY:Meeting\nUID:quoted-escback@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(attendee) = ical.get_property(event, "ATTENDEE")
  assert attendee.value == "mailto:john@example.com"

  let assert Ok(cn) = ical.get_parameter(attendee, "CN")
  assert cn == "Doe\\John"
}

pub fn parse_multiple_quoted_params_test() {
  let input =
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Test//EN\nBEGIN:VEVENT\nATTENDEE;CN=\"Doe; John\";ROLE=\"REQ-PARTICIPANT\":mailto:john@example.com\nSUMMARY:Meeting\nUID:quoted-multi@test\nEND:VEVENT\nEND:VCALENDAR"
  let assert Ok(calendar) = ical_parse(input)
  let assert [event] = calendar.events

  let assert Ok(attendee) = ical.get_property(event, "ATTENDEE")

  let assert Ok(cn) = ical.get_parameter(attendee, "CN")
  assert cn == "Doe; John"

  let assert Ok(role) = ical.get_parameter(attendee, "ROLE")
  assert role == "REQ-PARTICIPANT"
}

fn make_test_parser() -> ical.Parser {
  ical.new_parser(tzdb())
}

fn tzdb() {
  global_value.create_with_unique_name("tzdb", fn() {
    let assert Ok(tz_db) = database.load_from_os()
    tz_db
  })
}
