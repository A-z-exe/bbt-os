#!/bin/sh
# Restore a visible default pointer in the VMware X session.
command -v xsetroot >/dev/null 2>&1 && xsetroot -cursor_name left_ptr
command -v xset >/dev/null 2>&1 && xset s off -dpms 2>/dev/null
exit 0
