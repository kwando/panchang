import birdie
import gleam/option
import global_value
import panchang/ical
import simplifile
import test_utils
import tzif/database

pub fn rfc5545_bastille_day_snapshot_test() {
  snapshot_tree("bastille_day")
}

pub fn rfc5545_bastille_day_calendar_snapshot_test() {
  snapshot_calendar("bastille_day")
}

pub fn rfc5545_meeting_snapshot_test() {
  snapshot_tree("meeting")
}

pub fn rfc5545_meeting_calendar_snapshot_test() {
  snapshot_calendar("meeting")
}

pub fn rfc5545_todo_alarm_snapshot_test() {
  snapshot_tree("todo_alarm")
}

pub fn rfc5545_busytime_snapshot_test() {
  snapshot_tree("busytime")
}

pub fn rfc5545_anniversary_snapshot_test() {
  snapshot_tree("anniversary")
}

pub fn rfc5545_anniversary_calendar_snapshot_test() {
  snapshot_calendar("anniversary")
}

pub fn rfc5545_festival_snapshot_test() {
  snapshot_tree("festival")
}

pub fn rfc5545_festival_calendar_snapshot_test() {
  snapshot_calendar("festival")
}

pub fn rfc5545_todo_quebec_tax_snapshot_test() {
  snapshot_tree("todo_quebec_tax")
}

pub fn rfc5545_freebusy_request_snapshot_test() {
  snapshot_tree("freebusy_request")
}

pub fn rfc5545_freebusy_reply_snapshot_test() {
  snapshot_tree("freebusy_reply")
}

fn snapshot_tree(name: String) {
  let assert Ok(input) =
    simplifile.read("test/fixtures/rfc5545/" <> name <> ".ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_" <> name)
}

fn snapshot_calendar(name: String) {
  let assert Ok(input) =
    simplifile.read("test/fixtures/rfc5545/" <> name <> ".ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, option.None)

  calendar
  |> test_utils.render_calendar
  |> birdie.snap("rfc5545_" <> name <> "_calendar")
}

fn tzdb() {
  global_value.create_with_unique_name("tzdb", fn() {
    let assert Ok(tz_db) = database.load_from_os()
    tz_db
  })
}
