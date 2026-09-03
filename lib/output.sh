#!/usr/bin/env bash
# Gedeelde outputfuncties. Alle buildpackoutput loopt hierlangs, zodat de
# opmaak consistent is en tests op een voorspelbaar formaat kunnen matchen.

output::header() {
  echo ""
  echo "-----> ${1:-}"
}

output::info() {
  echo "       ${1:-}"
}

output::warn() {
  local message="${1:-}"
  echo ""
  echo " !     ${message}" | sed '2,$s/^/ !     /'
  echo ""
}

# Print een foutmelding en beëindigt de build met exitcode 1.
output::fail() {
  output::warn "${1:-}"
  exit 1
}

# Voert een stap uit, meet de duur en rapporteert die. Bij falen wordt de
# exitcode doorgegeven zodat `set -e` in de aanroeper zijn werk kan doen.
output::monitor() {
  local name="${1:-}"; shift
  local start end status

  start="$(date +%s)"
  set +e
  "$@"
  status=$?
  set -e
  end="$(date +%s)"

  if [[ ${status} -eq 0 ]]; then
    output::info "${name} klaar in $((end - start))s"
  fi

  return ${status}
}
