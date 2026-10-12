# Ferrous command loop

Build with `make ferrous`. Press Enter once to get the `what? ` prompt.
Commands are case-sensitive. Spaces separate parameters; double quotes preserve
spaces or an empty value. Quotes are removed, and adjacent quoted/unquoted text
forms one value. Backslashes and single quotes are literal characters. The line
editor accepts up to 255 characters, with up to 15 parameters per command.
Blank lines prompt again; unknown commands and malformed input report an error.

The example `echo` command itemizes the parsed parameter values:

```text
what? echo hello "two words" 42
  [1] hello
  [2] two words
  [3] 42
what?
```

`echo` without parameters prints a newline. `echo ""` prints an empty item.

To add a command in `lib/command.inc`, define a NUL-terminated name and an
`RTS`-terminated handler, then add `.word name_label, handler_label` before the
zero sentinel in `command_table`. The dispatcher calls the matching handler.
Handlers may clobber A/X/Y and flags and must balance the stack.

`command_argc` counts the command name plus its parameters. `command_argv` stores
byte offsets into `command_buffer`, whose values are NUL-terminated. Index 0 is
the name; parameters start at index 1. Load a valid index into A and call
`command_argument` to get the string address in A (low) and X (high), ready for
`print_text`. The parsed values last until the next command is read and parsed.
The original `input_buffer` is preserved for error messages.

After building, run the emulator console tests with:

```sh
python3 tests/console.py ../joshua/build/ucrt64/joshua.exe
```

Use the corresponding Joshua executable path for other build configurations.
