#!/bin/bash
# Type text into the running QEMU guest via the monitor socket. Usage: qemu-type.sh [--sock S] "text\n" ...
# "\n" at end of an argument sends Return. Supports ASCII letters, digits and common punctuation.
set -u
SOCK="${QEMU_MON:-$(dirname "$0")/../build/qemu-mon.sock}"
[ "${1:-}" = "--sock" ] && { SOCK="$2"; shift 2; }
key() { case "$1" in
  ' ') echo spc;; '-') echo minus;; '=') echo equal;; '.') echo dot;; ',') echo comma;; '/') echo slash;;
  ';') echo semicolon;; "'") echo apostrophe;; '[') echo bracket_left;; ']') echo bracket_right;; '\') echo backslash;;
  '`') echo grave_accent;; '_') echo shift-minus;; '+') echo shift-equal;; '>') echo shift-dot;; '<') echo shift-comma;;
  '?') echo shift-slash;; ':') echo shift-semicolon;; '"') echo shift-apostrophe;; '{') echo shift-bracket_left;;
  '}') echo shift-bracket_right;; '|') echo shift-backslash;; '~') echo shift-grave_accent;; '!') echo shift-1;;
  '@') echo shift-2;; '#') echo shift-3;; '$') echo shift-4;; '%') echo shift-5;; '^') echo shift-6;; '&') echo shift-7;;
  '*') echo shift-8;; '(') echo shift-9;; ')') echo shift-0;;
  [A-Z]) echo "shift-$(tr 'A-Z' 'a-z' <<<"$1")";; [a-z0-9]) echo "$1";; *) echo "";; esac; }
{
for arg in "$@"; do
  nl=0; [[ "$arg" == *'\n' ]] && { nl=1; arg="${arg%\\n}"; }
  for ((i=0;i<${#arg};i++)); do k=$(key "${arg:$i:1}"); [ -n "$k" ] && echo "sendkey $k"; done
  [ $nl = 1 ] && echo "sendkey ret"
done
} | while read -r line; do echo "$line" | socat - "UNIX-CONNECT:$SOCK" >/dev/null; sleep 0.04; done
