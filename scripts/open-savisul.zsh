#!/bin/zsh
# Installs SAVISUL after macOS refuses to open the downloaded file.
# Double-click runs it from the disk image. Pasting it into Terminal also works:
# Gatekeeper does not apply to a command a person typed themselves.
set -euo pipefail

install_app() {
  local src="$1"
  local dest="${SAVISUL_DEST:-}"
  if [[ -z "$dest" ]]; then
    if [[ -w /Applications ]]; then
      dest="/Applications/SAVISUL.app"
    else
      mkdir -p "$HOME/Applications"
      dest="$HOME/Applications/SAVISUL.app"
    fi
  else
    mkdir -p "$(dirname "$dest")"
  fi
  if [[ -z "${SAVISUL_DEST:-}" ]] && /usr/bin/pgrep -x SAVISUL >/dev/null 2>&1; then
    osascript -e 'tell application "SAVISUL" to quit' >/dev/null 2>&1 || true
    local _
    for _ in {1..30}; do
      /usr/bin/pgrep -x SAVISUL >/dev/null 2>&1 || break
      sleep 0.1
    done
    /usr/bin/pkill -x SAVISUL >/dev/null 2>&1 || true
  fi
  /usr/bin/xattr -cr "$src" 2>/dev/null || true
  if [[ "$src" != "$dest" ]]; then
    rm -rf "$dest"
    /usr/bin/ditto "$src" "$dest"
  fi
  /usr/bin/xattr -cr "$dest"
  chmod +x "$dest/Contents/MacOS/SAVISUL"
  open "$dest"
  print -r -- "Открыто: $dest"
}

app_from() {
  local item="$1"
  case "$item" in
    *.app)
      [[ -d "$item" ]] && print -r -- "$item"
      ;;
    *.dmg)
      /usr/bin/xattr -cr "$item" 2>/dev/null || true
      local out mount
      out=$(/usr/bin/hdiutil attach -nobrowse -readonly "$item" 2>/dev/null || true)
      mount=$(print -r -- "$out" | /usr/bin/awk -F'\t' '/\/Volumes\//{print $NF; exit}')
      if [[ -z "$mount" && -d /Volumes/SAVISUL/SAVISUL.app ]]; then
        mount="/Volumes/SAVISUL"
      fi
      [[ -n "$mount" && -d "$mount/SAVISUL.app" ]] && print -r -- "$mount/SAVISUL.app"
      ;;
    *.zip)
      /usr/bin/xattr -cr "$item" 2>/dev/null || true
      local tmp nested
      tmp=$(mktemp -d)
      /usr/bin/ditto -x -k "$item" "$tmp"
      nested=$(/usr/bin/find "$tmp" -maxdepth 4 -name 'SAVISUL.app' -print 2>/dev/null | /usr/bin/head -1)
      [[ -n "$nested" ]] && print -r -- "$nested"
      ;;
  esac
}

here="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "$here/SAVISUL.app" ]]; then
  install_app "$here/SAVISUL.app"
  exit 0
fi

setopt NULL_GLOB
typeset -a candidates
if [[ -n "${SAVISUL_SEARCH:-}" ]]; then
  candidates=("${SAVISUL_SEARCH}"/SAVISUL*.dmg "${SAVISUL_SEARCH}"/SAVISUL*.zip "${SAVISUL_SEARCH}"/SAVISUL.app)
else
  candidates=(
    "$HOME/Downloads"/SAVISUL*.dmg
    "$HOME/Downloads"/SAVISUL*.zip
    "$HOME/Downloads/Telegram Desktop"/SAVISUL*.dmg
    "$HOME/Downloads/Telegram Desktop"/SAVISUL*.zip
    "$HOME/Desktop"/SAVISUL*.dmg
    "$HOME/Desktop"/SAVISUL*.zip
    "$HOME/Desktop"/SAVISUL.app
    "$HOME/Downloads"/SAVISUL.app
    /Volumes/SAVISUL/SAVISUL.app
  )
fi

newest=""
newest_m=0
for item in $candidates; do
  [[ -e "$item" ]] || continue
  m=$(/usr/bin/stat -f '%m' "$item")
  if (( m > newest_m )); then
    newest_m=$m
    newest=$item
  fi
done

if [[ -z "$newest" ]]; then
  print -r -- "SAVISUL не найден. Положите образ SAVISUL (.dmg) в папку «Загрузки» и вставьте команду ещё раз."
  exit 1
fi

src="$(app_from "$newest")"
if [[ -z "$src" || ! -d "$src" ]]; then
  print -r -- "В файле нет SAVISUL.app: $newest"
  exit 1
fi
install_app "$src"
