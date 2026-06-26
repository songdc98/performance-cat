# Third-Party Notices

性能猫猫 (Performance Cat) bundles the following third-party component.

## macmon

- Project: https://github.com/vladkens/macmon
- Version: v0.7.2
- License: MIT
- Copyright (c) 2024 vladkens
- Bundled at: `bin/macmon` (copied into the app at `Contents/Resources/macmon`)
- Full license text: `bin/macmon-LICENSE.txt`

`macmon` is a small, read-only command-line tool that reports Apple Silicon
power and temperature counters. Performance Cat launches it as a child process
and parses its JSON output. It is used purely to read sensor values for display.
