#!/bin/sh
case "$(tail -n 1 "$0")" in
'#M:A') sed '$ s/#M:A/#M:B/' "$0" ;;
*) sed '$ s/#M:B/#M:A/' "$0" ;;
esac
#M:A
