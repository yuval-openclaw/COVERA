#!/bin/sh
# Guards the legal pages.
#
#   ./check.sh           before publishing: no [[BLANK]] may remain. A policy
#                        that names "[[OWNER FULL LEGAL NAME]]" names nobody.
#   ./check.sh --launch  before the app is released: also no "prelaunch"
#                        statement may remain (hosting provider, EU/UK
#                        representatives), since those promise to be filled in.
cd "$(dirname "$0")" || exit 1
status=0

blanks=$(grep -o '\[\[[^]]*\]\]' ./*.html | sort | uniq -c)
if [ -n "$blanks" ]; then
  echo "Not ready to publish. Fill these in first:"
  echo "$blanks"
  status=1
fi

if [ "$1" = "--launch" ]; then
  pending=$(grep -c 'class="prelaunch"' ./*.html | grep -v ':0$')
  if [ -n "$pending" ]; then
    echo "Not ready to launch. Replace the pre-release statements in:"
    echo "$pending"
    status=1
  fi
fi

[ $status -eq 0 ] && echo "Checks passed."
exit $status
