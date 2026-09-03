#!/usr/bin/env bash
# Draait binnen de Scalingo-stackcontainer. De buildpack is gemount op
# /buildpack (read-only), de tests op /test.

BP_DIR="${BP_DIR:-/buildpack}"
TEST_DIR="${TEST_DIR:-/test}"
FIXTURES="${TEST_DIR}/fixtures"

# Kopieert een fixture naar een schrijfbare tijdelijke map, omdat compile in
# BUILD_DIR schrijft en de mount read-only is.
setup_build_dir() {
  local fixture="${1}"
  local dir
  dir="$(mktemp -d)"
  if [[ -d "${FIXTURES}/${fixture}" ]]; then
    cp -r "${FIXTURES}/${fixture}/." "${dir}/"
  fi
  echo "${dir}"
}

# De cache-map is bewust gedeeld over de hele run (en over runs heen, via een
# vast pad in /tmp): compile downloadt Deno anders in elke test opnieuw — dat
# is ~40 MB per aanroep. In de container is /tmp toch per run vers; lokaal
# scheelt het bij herhaald draaien echt.
run_compile() {
  local build_dir="${1}"
  local env_dir
  env_dir="$(mktemp -d)"
  "${BP_DIR}/bin/compile" "${build_dir}" "${BUILDPACK_TEST_CACHE}" "${env_dir}" > "${STD_OUT}" 2> "${STD_ERR}"
}

# Slaat de aanroepende test zichtbaar over op omgevingen zonder unzip (de
# -minimal-stacks): daar kan compile per ontwerp niet slagen — dat éne faalpad
# heeft zijn eigen test. Gebruik: require_unzip || return 0
require_unzip() {
  if command -v unzip > /dev/null; then
    return 0
  fi
  startSkipping
  assertTrue 'overgeslagen: geen unzip op deze stack (zie het open punt in de README)' \
    "${SHUNIT_TRUE}"
  return 1
}

# De slug-simulatie schrijft — en wist — /app, en mag daarom uitsluitend in de
# stackcontainer draaien. De README documenteert dat deze suite ook los op een
# ontwikkelmachine kan draaien; een onbewaakte `rm -rf /app` zou daar een
# bestaande /app-map van de machine zelf raken. Twee voorwaarden, allebei
# vereist: STACK is gezet (doet alleen de makefile, via docker run) én / is
# schrijfbaar (in de container draaien we als root, daarbuiten vrijwel nooit).
in_stack_container() {
  [[ -n "${STACK:-}" && -w / ]]
}

# Slaat de aanroepende test over buiten de stackcontainer, zichtbaar in het
# eindrapport (skipped=N) in plaats van als stilzwijgende pass. Gebruik:
#   require_stack_container || return 0
require_stack_container() {
  if in_stack_container; then
    return 0
  fi
  startSkipping
  assertTrue 'overgeslagen: slug-tests draaien alleen in de stackcontainer' \
    "${SHUNIT_TRUE}"
  return 1
}

# Bootst na wat het platform na een geslaagde compile doet: de inhoud van
# BUILD_DIR verhuist naar /app, en bij het opstarten sourcet een Bash-shell
# alles in .profile.d/ voordat het startcommando draait. Zonder deze stap
# testen we de /app-paden in .profile.d/deno.sh nooit.
simulate_slug() {
  local build_dir="${1}"
  # Eigen guard, los van require_stack_container in de tests: een toekomstige
  # test die de guard vergeet mag nooit alsnog /app van een echte machine wissen.
  if ! in_stack_container; then
    fail "simulate_slug aangeroepen buiten de stackcontainer"
    return 1
  fi
  rm -rf /app
  mkdir -p /app
  cp -r "${build_dir}/." /app/
}

# Sourcet de profile-scripts in een subshell en echoot de gevraagde variabele,
# net zoals de container dat bij het booten doet.
slug_env() {
  local var="${1}"
  bash -c 'for f in /app/.profile.d/*.sh; do . "$f"; done; eval echo "\$'"${var}"'"'
}

# --- detect ---------------------------------------------------------------

test_detect_accepts_deno_project() {
  local dir output
  dir="$(setup_build_dir minimal)"
  output="$("${BP_DIR}/bin/detect" "${dir}")"
  assertEquals "detect moet slagen op een deno.json" 0 $?
  assertEquals "Deno" "${output}"
}

test_detect_rejects_empty_project() {
  local dir
  dir="$(setup_build_dir empty)"
  "${BP_DIR}/bin/detect" "${dir}" > /dev/null 2>&1
  assertEquals "detect moet falen zonder deno.json" 1 $?
}

test_detect_accepts_jsonc() {
  local dir
  dir="$(setup_build_dir empty)"
  echo '{}' > "${dir}/deno.jsonc"
  "${BP_DIR}/bin/detect" "${dir}" > /dev/null 2>&1
  assertEquals "deno.jsonc moet ook tellen" 0 $?
}

# --- release --------------------------------------------------------------

test_release_emits_yaml_without_process_types() {
  local output
  output="$("${BP_DIR}/bin/release" "$(setup_build_dir minimal)")"
  assertContains "${output}" "config_vars"
  assertNotContains "release mag geen startcommando raden" \
    "${output}" "default_process_types"
}

# --- compile --------------------------------------------------------------

test_compile_succeeds_on_minimal_fixture() {
  require_unzip || return 0
  local dir
  dir="$(setup_build_dir minimal)"
  run_compile "${dir}"
  assertEquals "compile moet slagen op de minimale fixture" 0 $?
  # De kern van de installatie: de binary staat er en start echt.
  assertTrue "deno-binary moet bestaan en uitvoerbaar zijn" \
    "[ -x '${dir}/.scalingo/deno/bin/deno' ]"
  assertTrue "deno-binary moet de gepinde versie draaien" \
    "'${dir}/.scalingo/deno/bin/deno' --version | grep -q 'deno 2\.9\.5'"
  # Geen build-task in deze fixture: de buildstap hoort overgeslagen te melden.
  assertFileContains "buildstap overgeslagen" "${STD_OUT}"
}

test_compile_runs_build_task_when_present() {
  require_unzip || return 0
  local dir
  dir="$(setup_build_dir with-build)"
  run_compile "${dir}"
  assertEquals "compile moet slagen op de with-build-fixture" 0 $?
  # De task draaide echt: zijn output staat in de buildlog.
  assertFileContains "build-ran-ok" "${STD_OUT}"
}

test_compile_rejects_invalid_version() {
  # Geen netwerk nodig: de weigering valt vóór elke download. Draait dus ook
  # op de -minimal-stacks.
  local dir
  dir="$(setup_build_dir minimal)"
  echo "latest" > "${dir}/.deno-version"
  run_compile "${dir}"
  assertEquals "een niet-exacte versie moet geweigerd worden" 1 $?
  assertFileContains "Ongeldige Deno-versie" "${STD_OUT}"
}

test_compile_reads_version_from_env_dir() {
  # De v-prefix ontbreekt bewust: de weigering bewijst dat de waarde uit
  # ENV_DIR daadwerkelijk gelezen is, zonder dat er iets gedownload hoeft.
  local dir env_dir
  dir="$(setup_build_dir minimal)"
  rm -f "${dir}/.deno-version"
  env_dir="$(mktemp -d)"
  printf '2.9.5' > "${env_dir}/DENO_VERSION"
  "${BP_DIR}/bin/compile" "${dir}" "${BUILDPACK_TEST_CACHE}" "${env_dir}" \
    > "${STD_OUT}" 2> "${STD_ERR}"
  assertEquals "versie zonder v-prefix moet geweigerd worden" 1 $?
  assertFileContains "Ongeldige Deno-versie" "${STD_OUT}"
  assertFileContains "2.9.5" "${STD_OUT}"
}

test_compile_fails_cleanly_without_unzip() {
  # Het spiegelbeeld van require_unzip: dit faalpad bestaat alleen op stacks
  # zónder unzip (de -minimal-varianten).
  if command -v unzip > /dev/null; then
    startSkipping
    assertTrue 'overgeslagen: unzip aanwezig, dus dit faalpad is hier niet te raken' \
      "${SHUNIT_TRUE}"
    return 0
  fi
  local dir
  dir="$(setup_build_dir minimal)"
  run_compile "${dir}"
  assertEquals "zonder unzip hoort compile netjes te falen" 1 $?
  assertFileContains "unzip ontbreekt" "${STD_OUT}"
}

test_compile_creates_profile_script() {
  require_unzip || return 0
  local dir
  dir="$(setup_build_dir minimal)"
  run_compile "${dir}"
  assertTrue ".profile.d/deno.sh moet bestaan" "[ -f '${dir}/.profile.d/deno.sh' ]"
  assertFileContains "DENO_DIR" "${dir}/.profile.d/deno.sh"
  assertFileContains "/app/.scalingo/deno/bin" "${dir}/.profile.d/deno.sh"
}

test_compile_fails_without_procfile() {
  local dir
  dir="$(setup_build_dir minimal)"
  rm -f "${dir}/Procfile"
  run_compile "${dir}"
  assertEquals "ontbrekende Procfile moet de build breken" 1 $?
  assertFileContains "Procfile" "${STD_OUT}"
}

test_compile_warns_without_lockfile() {
  require_unzip || return 0
  local dir
  dir="$(setup_build_dir minimal)"
  rm -f "${dir}/deno.lock"
  run_compile "${dir}"
  assertEquals "ontbrekende lockfile is een waarschuwing, geen fout" 0 $?
  assertFileContains "deno.lock" "${STD_OUT}"
}

# --- runtime-omgeving na de verhuizing naar /app --------------------------

test_slug_profile_puts_deno_on_path() {
  require_stack_container || return 0
  require_unzip || return 0
  local dir path
  dir="$(setup_build_dir minimal)"
  run_compile "${dir}"
  simulate_slug "${dir}"

  path="$(slug_env PATH)"
  assertTrue "deno-bin moet in PATH staan na booten" \
    "echo '${path}' | grep -q '/app/.scalingo/deno/bin'"

  # En de runtime start ook echt via die omgeving — dit is wat een container
  # bij het booten doet vlak voor het Procfile-commando.
  local version_out
  version_out="$(bash -c 'for f in /app/.profile.d/*.sh; do . "$f"; done; deno --version' 2> /dev/null || true)"
  assertTrue "deno moet draaien via de slug-omgeving (kreeg: '${version_out}')" \
    "echo '${version_out}' | grep -q '^deno'"
}

test_slug_profile_sets_deno_dir_to_existing_path() {
  require_stack_container || return 0
  require_unzip || return 0
  local dir deno_dir
  dir="$(setup_build_dir minimal)"
  run_compile "${dir}"
  simulate_slug "${dir}"

  deno_dir="$(slug_env DENO_DIR)"
  assertEquals "/app/.scalingo/deno-cache" "${deno_dir}"
  assertTrue "DENO_DIR moet bestaan na de verhuizing" "[ -d '${deno_dir}' ]"
}

test_slug_profile_does_not_clobber_existing_path() {
  require_stack_container || return 0
  require_unzip || return 0
  local dir path
  dir="$(setup_build_dir minimal)"
  run_compile "${dir}"
  simulate_slug "${dir}"

  path="$(slug_env PATH)"
  # Eerst bewijzen dat het profiel echt gesourced is. Zonder die stap slaagt
  # de /usr/bin-assert ook op de omgevings-PATH van de testshell — dan bewaakt
  # deze test niets (dat gebeurde daadwerkelijk toen de simulatie faalde).
  assertTrue "profiel niet gesourced: deno-bin ontbreekt in PATH" \
    "echo '${path}' | grep -q '/app/.scalingo/deno/bin'"
  assertTrue "de bestaande PATH moet behouden blijven" \
    "echo '${path}' | grep -q '/usr/bin'"
}

# --- hulpassertions -------------------------------------------------------

assertFileContains() {
  local needle="${1}" file="${2}"
  assertTrue "'${needle}' niet gevonden in ${file}" "grep -q -- '${needle}' '${file}'"
}

assertContains() {
  local haystack="${1}" needle="${2}"
  assertTrue "'${needle}' niet gevonden in output" \
    "echo '${haystack}' | grep -q -- '${needle}'"
}

assertNotContains() {
  local message="${1}" haystack="${2}" needle="${3}"
  assertFalse "${message}" "echo '${haystack}' | grep -q -- '${needle}'"
}

oneTimeSetUp() {
  STD_OUT="$(mktemp)"
  STD_ERR="$(mktemp)"
  BUILDPACK_TEST_CACHE="${TMPDIR:-/tmp}/scalingo-buildpack-deno-testcache"
  mkdir -p "${BUILDPACK_TEST_CACHE}"
  export STD_OUT STD_ERR BUILDPACK_TEST_CACHE
  echo "Stack: ${STACK:-onbekend}"
}

setUp() {
  : > "${STD_OUT}"
  : > "${STD_ERR}"
  # Deze shunit2 (2.1.9pre) reset de skip-vlag NIET tussen tests: een
  # startSkipping uit een overgeslagen slug-test zou anders doorlekken en elke
  # volgende test stilzwijgend tot skip maken.
  endSkipping
}

# shellcheck source=/dev/null
source "${TEST_DIR}/shunit2"
