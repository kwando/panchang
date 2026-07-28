import birdie
import gleam/option
import global_value
import panchang/ical
import simplifile
import test_utils
import tzif/database

pub fn rfc5545_bastille_day_snapshot_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/rfc5545/bastille_day.ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_bastille_day")
}

pub fn rfc5545_bastille_day_calendar_snapshot_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/rfc5545/bastille_day.ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, option.None)

  calendar
  |> test_utils.render_calendar
  |> birdie.snap("rfc5545_bastille_day_calendar")
}

pub fn rfc5545_meeting_snapshot_test() {
  let assert Ok(input) = simplifile.read("test/fixtures/rfc5545/meeting.ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_meeting")
}

pub fn rfc5545_meeting_calendar_snapshot_test() {
  let assert Ok(input) = simplifile.read("test/fixtures/rfc5545/meeting.ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, option.None)

  calendar
  |> test_utils.render_calendar
  |> birdie.snap("rfc5545_meeting_calendar")
}

pub fn rfc5545_todo_alarm_snapshot_test() {
  let assert Ok(input) = simplifile.read("test/fixtures/rfc5545/todo_alarm.ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_todo_alarm")
}

pub fn rfc5545_busytime_snapshot_test() {
  let assert Ok(input) = simplifile.read("test/fixtures/rfc5545/busytime.ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_busytime")
}

pub fn rfc5545_anniversary_snapshot_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/rfc5545/anniversary.ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_anniversary")
}

pub fn rfc5545_anniversary_calendar_snapshot_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/rfc5545/anniversary.ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, option.None)

  calendar
  |> test_utils.render_calendar
  |> birdie.snap("rfc5545_anniversary_calendar")
}

pub fn rfc5545_festival_snapshot_test() {
  let assert Ok(input) = simplifile.read("test/fixtures/rfc5545/festival.ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_festival")
}

pub fn rfc5545_festival_calendar_snapshot_test() {
  let assert Ok(input) = simplifile.read("test/fixtures/rfc5545/festival.ics")
  let assert Ok(calendar) =
    ical.parse(ical.new_parser(tzdb()), input, option.None)

  calendar
  |> test_utils.render_calendar
  |> birdie.snap("rfc5545_festival_calendar")
}

pub fn rfc5545_todo_quebec_tax_snapshot_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/rfc5545/todo_quebec_tax.ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_todo_quebec_tax")
}

pub fn rfc5545_freebusy_request_snapshot_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/rfc5545/freebusy_request.ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_freebusy_request")
}

pub fn rfc5545_freebusy_reply_snapshot_test() {
  let assert Ok(input) =
    simplifile.read("test/fixtures/rfc5545/freebusy_reply.ics")
  let parser = ical.new_parser(tzdb())
  let assert Ok(root) = ical.parse_tree(parser, input)

  root
  |> test_utils.render_tree
  |> birdie.snap("rfc5545_freebusy_reply")
}

fn tzdb() {
  global_value.create_with_unique_name("tzdb", fn() {
    let assert Ok(tz_db) = database.load_from_os()
    tz_db
  })
}
