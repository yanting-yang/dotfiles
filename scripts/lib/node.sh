#!/usr/bin/env bash

node_major_from_file() {
    local major

    major=$(<"$1") || return 1
    case "$major" in
        '' | 0 | 0* | *[!0-9]*) return 1 ;;
    esac

    printf '%s\n' "$major"
}
