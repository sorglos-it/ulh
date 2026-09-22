#!/bin/bash
# Compatibility: installed copies and the published one-liner start ulh with
#   cd ~/ulh && bash ulh.sh
# The program is apps/cli/ulh.sh. This file can go once that command is no
# longer published anywhere.
exec bash "$(dirname "${BASH_SOURCE[0]}")/apps/cli/ulh.sh" "$@"
