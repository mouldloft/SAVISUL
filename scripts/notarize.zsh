#!/bin/zsh
# notarize <file>: sends a zip, disk image or package to Apple's notary service with the keychain profile in
# $NOTARY_PROFILE (made once with `xcrun notarytool store-credentials`), waits, and stops with Apple's log if it isn't
# accepted. Sourced by scripts/release.sh and scripts/make-installer.sh.
notarize() {
  local out id state
  out="$(xcrun notarytool submit "$1" --keychain-profile "${NOTARY_PROFILE:-savisul-notary}" --wait --output-format json)"
  id="$(print -r -- "$out" | /usr/bin/plutil -extract id raw -o - -)"
  state="$(print -r -- "$out" | /usr/bin/plutil -extract status raw -o - -)"
  print "Notarization of ${1:t}: $state ($id)"
  if [[ "$state" != Accepted ]]; then
    xcrun notarytool log "$id" --keychain-profile "${NOTARY_PROFILE:-savisul-notary}" >&2 || true
    return 1
  fi
}
