#!/bin/sh

# Give panes a short callsign. Herdr runs this both for the startup hook
# (no event JSON, so every pane without one) and for pane.created (one pane).
# Never overwrites an existing callsign.

set -eu

cd "${HERDR_PLUGIN_ROOT:-.}"

herdr_bin="${HERDR_BIN_PATH:-herdr}"
default_words_file="assets/words.txt"
words_file="${HERDR_CALLSIGNS_WORDS_FILE:-$default_words_file}"

if [ ! -f "$words_file" ] || [ ! -r "$words_file" ] || [ ! -s "$words_file" ]; then
  if [ "$words_file" != "$default_words_file" ]; then
    echo "callsigns: words file not readable ($words_file), falling back to $default_words_file" >&2
    words_file="$default_words_file"
  fi
fi

if [ ! -f "$words_file" ] || [ ! -r "$words_file" ] || [ ! -s "$words_file" ]; then
  echo "callsigns: words file not readable ($words_file), skipping naming" >&2
  exit 0
fi

command -v jq >/dev/null 2>&1 || {
  echo "callsigns: jq not found, skipping naming" >&2
  exit 0
}

used_names() {
  {
    "$herdr_bin" pane list 2>/dev/null | jq -r '.result.panes[]? | .label // empty'
    "$herdr_bin" agent list 2>/dev/null | jq -r '.result.agents[]? | .name // empty'
  } 2>/dev/null | tr '\n' ' '
}

pane_label() {
  "$herdr_bin" pane get "$1" 2>/dev/null | jq -r '.result.pane.label // empty'
}

word_at() {
  sed -n "$1p" "$words_file" | tr -d '\r'
}

random_index() {
  n="$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ')" || n=$$
  case "$n" in '' | *[!0-9]*) n=$$ ;; esac
  echo $((n % $1 + 1))
}

pick_name() {
  used=" $1 "
  count="$(grep -c '' "$words_file")" || return 1
  [ "$count" -gt 0 ] || return 1

  start="$(random_index "$count")"
  i=0
  while [ "$i" -lt "$count" ]; do
    candidate="$(word_at $(((start + i - 1) % count + 1)))"
    i=$((i + 1))
    [ -n "$candidate" ] || continue
    case "$used" in *" $candidate "*) continue ;; esac
    printf '%s' "$candidate"
    return 0
  done

  # Single words are all taken, so pair two of them. Give up after a few
  # tries rather than searching; an unnamed pane beats a stalled hook.
  [ "$count" -ge 2 ] || return 1
  tries=0
  while [ "$tries" -lt 20 ]; do
    tries=$((tries + 1))
    first="$(word_at "$(random_index "$count")")"
    second="$(word_at "$(random_index "$count")")"
    [ -n "$first" ] || continue
    [ -n "$second" ] || continue
    [ "$first" != "$second" ] || continue
    candidate="$first-$second"
    case "$used" in *" $candidate "*) continue ;; esac
    printf '%s' "$candidate"
    return 0
  done
  return 1
}

_lock_file="/tmp/herdr-callsigns.lock"
_lock_dir="/tmp/herdr-callsigns.lock.dir"
_lock_fd_open=0
_lock_mkdir=0

acquire_lock() {
  tries=0
  if command -v flock >/dev/null 2>&1; then
    if [ "$_lock_fd_open" -ne 1 ]; then
      eval 'exec 9>"$_lock_file"' 2>/dev/null && _lock_fd_open=1
    fi
    if [ "$_lock_fd_open" -eq 1 ]; then
      while [ "$tries" -lt 50 ]; do
        if flock -n 9 2>/dev/null; then
          return 0
        fi
        tries=$((tries + 1))
        sleep 0.1 2>/dev/null || sleep 1
      done
      return 1
    fi
  fi
  tries=0
  while [ "$tries" -lt 50 ]; do
    if mkdir "$_lock_dir" 2>/dev/null; then
      _lock_mkdir=1
      return 0
    fi
    tries=$((tries + 1))
    sleep 0.1 2>/dev/null || sleep 1
  done
  return 1
}

release_lock() {
  if [ "${_lock_fd_open:-0}" -eq 1 ]; then
    eval 'exec 9>&-' 2>/dev/null || true
    _lock_fd_open=0
  fi
  if [ "${_lock_mkdir:-0}" -eq 1 ]; then
    rmdir "$_lock_dir" 2>/dev/null || true
    _lock_mkdir=0
  fi
}

label_count() {
  "$herdr_bin" pane list 2>/dev/null |
    jq -r --arg l "$1" '[.result.panes[]? | select((.label // empty) == $l)] | length' 2>/dev/null
}

trap 'release_lock' INT TERM EXIT

name_pane() {
  target="$1"
  attempts=0
  assigned=""
  tried=" "
  while [ "$attempts" -lt 5 ]; do
    current="$(pane_label "$target")" || current=""
    if [ -n "$current" ] && [ "$current" != "$assigned" ]; then
      case "$tried" in
      *" $current "*) ;;
      *)
        count="$(label_count "$current")" || count=""
        case "$count" in '' | *[!0-9]*) return 0 ;; esac
        if [ "$count" -le 1 ]; then
          return 0
        fi
        tried="$tried$current "
        ;;
      esac
    fi
    if [ -n "$assigned" ] && [ "$current" = "$assigned" ]; then
      count="$(label_count "$assigned")" || count=""
      case "$count" in '' | *[!0-9]*) return 0 ;; esac
      if [ "$count" -le 1 ]; then
        return 0
      fi
      tried="$tried$assigned "
      assigned=""
    fi
    locked=0
    if acquire_lock; then
      locked=1
    fi
    fresh="$(pane_label "$target")" || fresh=""
    case "$tried" in
    *" $fresh "*) ;;
    *)
      if [ -n "$fresh" ] && [ "$fresh" != "$assigned" ]; then
        count="$(label_count "$fresh")" || count=""
        case "$count" in '' | *[!0-9]*)
          [ "$locked" -eq 1 ] && release_lock
          return 0
          ;;
        esac
        if [ "$count" -le 1 ]; then
          [ "$locked" -eq 1 ] && release_lock
          return 0
        fi
        tried="$tried$fresh "
      fi
      ;;
    esac
    candidate="$(pick_name "$(used_names)$tried")" || {
      [ "$locked" -eq 1 ] && release_lock
      return 1
    }
    [ -n "$candidate" ] || {
      [ "$locked" -eq 1 ] && release_lock
      return 1
    }
    if "$herdr_bin" pane rename "$target" "$candidate" >/dev/null 2>&1; then
      assigned="$candidate"
    else
      tried="$tried$candidate "
    fi
    [ "$locked" -eq 1 ] && release_lock
    attempts=$((attempts + 1))
  done
  echo "callsigns: failed to name pane $target after $attempts attempts" >&2
  return 1
}

event_pane="$(
  printf '%s' "${HERDR_PLUGIN_EVENT_JSON:-{}}" | jq -r '
    .pane.pane_id // .data.pane.pane_id // .pane_id // empty
  ' 2>/dev/null || true
)"

if [ -n "$event_pane" ]; then
  name_pane "$event_pane" || true
  exit 0
fi

"$herdr_bin" api snapshot 2>/dev/null |
  jq -r '.result.snapshot.panes[]? | select((.label // "") == "") | .pane_id' |
  while IFS= read -r unlabeled; do
    [ -n "$unlabeled" ] || continue
    name_pane "$unlabeled" || true
  done
