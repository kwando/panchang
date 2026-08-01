import birdie
import gleam/option
import panchang/ical
import simplifile
import test_utils.{tzdb}

pub fn icalendar_example_snapshot_test() {
  snapshot_tree("example")
}

pub fn icalendar_example_calendar_snapshot_test() {
  snapshot_calendar("example")
}

pub fn icalendar_calendar_with_unicode_snapshot_test() {
  snapshot_tree("calendar_with_unicode")
}

pub fn icalendar_calendar_with_unicode_calendar_snapshot_test() {
  snapshot_calendar("calendar_with_unicode")
}

pub fn icalendar_issue_127_categories_with_commas_snapshot_test() {
  snapshot_tree("issue_127_categories_with_commas")
}

pub fn icalendar_issue_127_categories_with_commas_calendar_snapshot_test() {
  snapshot_calendar("issue_127_categories_with_commas")
}

pub fn icalendar_america_new_york_snapshot_test() {
  snapshot_tree("america_new_york")
}

pub fn icalendar_america_new_york_calendar_snapshot_test() {
  snapshot_calendar("america_new_york")
}

pub fn icalendar_multiple_timezones_snapshot_test() {
  snapshot_tree("multiple_timezones")
}

pub fn icalendar_multiple_timezones_calendar_snapshot_test() {
  snapshot_calendar("multiple_timezones")
}

pub fn icalendar_pacific_fiji_snapshot_test() {
  snapshot_tree("pacific_fiji")
}

pub fn icalendar_pacific_fiji_calendar_snapshot_test() {
  snapshot_calendar("pacific_fiji")
}

pub fn icalendar_issue_466_convert_tzid_with_slash_snapshot_test() {
  snapshot_tree("issue_466_convert_tzid_with_slash")
}

pub fn icalendar_issue_466_convert_tzid_with_slash_calendar_snapshot_test() {
  snapshot_calendar("issue_466_convert_tzid_with_slash")
}

pub fn icalendar_issue_722_missing_timezones_snapshot_test() {
  snapshot_tree("issue_722_missing_timezones")
}

pub fn icalendar_issue_722_missing_timezones_calendar_snapshot_test() {
  snapshot_calendar("issue_722_missing_timezones")
}

pub fn icalendar_broken_dtstart_snapshot_test() {
  snapshot_tree("broken_dtstart")
}

pub fn icalendar_broken_dtstart_calendar_snapshot_test() {
  snapshot_calendar("broken_dtstart")
}

pub fn icalendar_empty_snapshot_test() {
  snapshot_tree("empty")
}

pub fn icalendar_rfc_6868_snapshot_test() {
  snapshot_tree("rfc_6868")
}

pub fn icalendar_rfc_6868_calendar_snapshot_test() {
  snapshot_calendar("rfc_6868")
}

pub fn icalendar_issue_1050_calendar_with_events_and_todos_snapshot_test() {
  snapshot_tree("issue_1050_calendar_with_events_and_todos")
}

pub fn icalendar_issue_1050_calendar_with_events_and_todos_calendar_snapshot_test() {
  snapshot_calendar("issue_1050_calendar_with_events_and_todos")
}

pub fn icalendar_property_params_snapshot_test() {
  snapshot_tree("property_params")
}

pub fn icalendar_property_params_calendar_snapshot_test() {
  snapshot_calendar("property_params")
}

pub fn icalendar_issue_1081_event_with_rrule_snapshot_test() {
  snapshot_tree("issue_1081_event_with_rrule")
}

pub fn icalendar_issue_1081_event_with_rrule_calendar_snapshot_test() {
  snapshot_calendar("issue_1081_event_with_rrule")
}

pub fn icalendar_bom_calendar_snapshot_test() {
  snapshot_tree("bom_calendar")
}

pub fn icalendar_bom_calendar_calendar_snapshot_test() {
  snapshot_calendar("bom_calendar")
}

pub fn icalendar_created_calendar_with_unicode_fields_snapshot_test() {
  snapshot_tree("created_calendar_with_unicode_fields")
}

pub fn icalendar_created_calendar_with_unicode_fields_calendar_snapshot_test() {
  snapshot_calendar("created_calendar_with_unicode_fields")
}

pub fn icalendar_issue_351_whitespace_in_property_and_params_snapshot_test() {
  snapshot_tree("issue_351_whitespace_in_property_and_params")
}

pub fn icalendar_issue_351_whitespace_in_property_and_params_calendar_snapshot_test() {
  snapshot_calendar("issue_351_whitespace_in_property_and_params")
}

pub fn icalendar_issue_526_calendar_with_events_snapshot_test() {
  snapshot_tree("issue_526_calendar_with_events")
}

pub fn icalendar_issue_526_calendar_with_events_calendar_snapshot_test() {
  snapshot_calendar("issue_526_calendar_with_events")
}

pub fn icalendar_issue_722_timezone_transition_ambiguity_snapshot_test() {
  snapshot_tree("issue_722_timezone_transition_ambiguity")
}

pub fn icalendar_issue_722_timezone_transition_ambiguity_calendar_snapshot_test() {
  snapshot_calendar("issue_722_timezone_transition_ambiguity")
}

pub fn icalendar_issue_1050_forward_timezone_reference_snapshot_test() {
  snapshot_tree("issue_1050_forward_timezone_reference")
}

pub fn icalendar_issue_1050_forward_timezone_reference_calendar_snapshot_test() {
  snapshot_calendar("issue_1050_forward_timezone_reference")
}

pub fn icalendar_issue_1426_snapshot_test() {
  snapshot_tree("issue_1426")
}

pub fn icalendar_issue_1426_calendar_snapshot_test() {
  snapshot_calendar("issue_1426")
}

pub fn icalendar_rfc_5545_rdate_example_snapshot_test() {
  snapshot_tree("rfc_5545_RDATE_example")
}

pub fn icalendar_rfc_5545_rdate_example_calendar_snapshot_test() {
  snapshot_calendar("rfc_5545_RDATE_example")
}

pub fn icalendar_rfc_7256_multi_value_parameters_snapshot_test() {
  snapshot_tree("rfc_7256_multi_value_parameters")
}

pub fn icalendar_rfc_7256_multi_value_parameters_calendar_snapshot_test() {
  snapshot_calendar("rfc_7256_multi_value_parameters")
}

pub fn icalendar_timezoned_snapshot_test() {
  snapshot_tree("timezoned")
}

pub fn icalendar_timezoned_calendar_snapshot_test() {
  snapshot_calendar("timezoned")
}

pub fn icalendar_america_new_york_forward_reference_snapshot_test() {
  let assert Ok(input) =
    simplifile.read(
      "test/fixtures/icalendar/america_new_york_forward_reference.ics",
    )
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("icalendar_america_new_york_forward_reference")
}

pub fn icalendar_america_new_york_forward_reference_calendar_snapshot_test() {
  snapshot_calendar("america_new_york_forward_reference")
}

fn snapshot_tree(name: String) {
  let assert Ok(input) =
    simplifile.read("test/fixtures/icalendar/" <> name <> ".ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("icalendar_" <> name)
}

fn snapshot_calendar(name: String) {
  let assert Ok(input) =
    simplifile.read("test/fixtures/icalendar/" <> name <> ".ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, option.None)

  calendar
  |> test_utils.render_calendar
  |> birdie.snap("icalendar_" <> name <> "_calendar")
}
