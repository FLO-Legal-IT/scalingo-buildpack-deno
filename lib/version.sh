#!/usr/bin/env bash
# Bepaalt welke Deno-versie geïnstalleerd wordt. Bewust exact gepind (vX.Y.Z):
# een build die vandaag een andere runtime oplevert dan gisteren is geen
# reproduceerbare build — ranges en 'latest' worden geweigerd.

# De default wanneer een app niets pint. Bewust een vaste waarde in de
# buildpack, geen "nieuwste resolven": een verse Deno-release mag bestaande
# builds niet stilzwijgend veranderen. Bijwerken is een bewuste commit hier.
DEFAULT_DENO_VERSION="v2.9.5"

# Volgorde: .deno-version in de repo wint, dan de env var DENO_VERSION (als
# bestand in ENV_DIR, zoals het platform env-vars aanlevert), dan de default.
#
# Zet het resultaat in DENO_VERSION_RESOLVED in plaats van het te echoën: bij
# een $(…)-capture zou de foutmelding van een geweigerde versie in de variabele
# belanden in plaats van in de buildlog.
# shellcheck disable=SC2034  # gelezen door bin/compile, dat dit bestand sourcet
version::determine() {
  local build_dir="${1}" env_dir="${2}"
  local version=""
  if [[ -f "${build_dir}/.deno-version" ]]; then
    version="$(tr -d '[:space:]' < "${build_dir}/.deno-version")"
  elif [[ -n "${env_dir}" && -f "${env_dir}/DENO_VERSION" ]]; then
    version="$(tr -d '[:space:]' < "${env_dir}/DENO_VERSION")"
  else
    version="${DEFAULT_DENO_VERSION}"
  fi
  if [[ ! "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    failure::invalid_version "${version}"
  fi
  DENO_VERSION_RESOLVED="${version}"
}
