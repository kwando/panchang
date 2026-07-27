project_name := "panchang"

download:
    curl "${CALENDAR_URL}" > examples/calendar.ical
    curl "${PUBLIC_CALENDAR_URL}" > examples/public.ical

watch_docs:
    watchexec --clear --debounce 5s -w src gleam docs build

watch_tests:
    watchexec --clear -w src -w test gleam test

serve_docs:
    caddy file-server --root build/dev/docs/{{ project_name }}
