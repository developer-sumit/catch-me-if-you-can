#!/usr/bin/env bash
#
# Soul Serve — project control script.
#
# One interactive place for the things this repo otherwise asks you to do by
# hand: provisioning PostgreSQL, wiring .env, running the API and the Flutter
# app together, and producing release artifacts for every target.
#
#   ./soulserve.sh                 open the menu
#   ./soulserve.sh run             API + app, in parallel
#   ./soulserve.sh --help          every non-interactive subcommand
#
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

WORK="$ROOT/.soulserve"      # logs and locally built binaries
DIST="$ROOT/dist"            # release artifacts
ENV_FILE="$ROOT/.env"
ENV_SAMPLE="$ROOT/.env.example"
SCHEMA="$ROOT/backend/schema.sql"

# ---------------------------------------------------------------- appearance

if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'
  RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
  BLU=$'\033[34m'; CYN=$'\033[36m'; INV=$'\033[7m'
else
  B=''; DIM=''; R=''; RED=''; GRN=''; YEL=''; BLU=''; CYN=''; INV=''
fi

say()  { printf '%s\n' "$*"; }
info() { printf '%s\n' "${BLU}::${R} $*"; }
ok()   { printf '%s\n' "${GRN}ok${R} $*"; }
warn() { printf '%s\n' "${YEL}warning${R} $*" >&2; }
err()  { printf '%s\n' "${RED}error${R} $*" >&2; }
step() { printf '\n%s\n' "${B}$*${R}"; }

rule() {
  local w=${COLUMNS:-$(tput cols 2>/dev/null || echo 72)} i
  ((w > 78)) && w=78
  # Built by repetition rather than `tr ' ' '─'`: tr substitutes single bytes
  # and would shred the three-byte box-drawing character.
  printf '%s' "$DIM"
  for ((i = 0; i < w; i++)); do printf '─'; done
  printf '%s\n' "$R"
}

banner() {
  printf '\033[H\033[2J'
  printf '%s\n' "${GRN}${B}  Soul Serve${R} ${DIM}· project control${R}"
  rule
}

die() { err "$*"; exit 1; }

# ------------------------------------------------------------------ TUI menu

# ui_menu "Heading" item... -> sets MENU_INDEX (-1 when cancelled)
MENU_INDEX=-1
ui_menu() {
  local heading=$1; shift
  local -a items=("$@")
  local n=${#items[@]} sel=0 key rest first=1
  MENU_INDEX=-1

  if [[ ! -t 0 || ! -t 1 ]]; then           # piped or CI: plain prompt
    printf '%s\n' "${B}${heading}${R}"
    local i
    for ((i = 0; i < n; i++)); do printf '  %2d) %s\n' $((i + 1)) "${items[i]}"; done
    local pick=''
    read -rp 'Choice (blank to cancel): ' pick || true
    [[ $pick =~ ^[0-9]+$ ]] && ((pick >= 1 && pick <= n)) && MENU_INDEX=$((pick - 1))
    return 0
  fi

  printf '%s\n' "${B}${heading}${R}"
  printf '%s\n' "${DIM}↑↓ or j/k to move · enter to choose · number to jump · q to go back${R}"
  printf '\n'

  tput civis 2>/dev/null || true
  # shellcheck disable=SC2064
  trap "tput cnorm 2>/dev/null || true" RETURN

  while :; do
    if ((first)); then first=0; else printf '\033[%dA' "$n"; fi
    local i
    for ((i = 0; i < n; i++)); do
      printf '\033[2K'
      if ((i == sel)); then
        printf '  %s %2d %s %s\n' "${INV}${GRN}" $((i + 1)) "${R}" "${B}${items[i]}${R}"
      else
        printf '  %s %2d %s %s\n' "$DIM" $((i + 1)) "$R" "${items[i]}"
      fi
    done

    IFS= read -rsn1 key || { MENU_INDEX=-1; return 0; }
    case $key in
      $'\033')
        rest=''
        read -rsn2 -t 0.05 rest || true
        case $rest in
          '[A') ((sel = (sel - 1 + n) % n)) ;;
          '[B') ((sel = (sel + 1) % n)) ;;
          '')   MENU_INDEX=-1; return 0 ;;    # bare Escape
        esac ;;
      k|K) ((sel = (sel - 1 + n) % n)) ;;
      j|J) ((sel = (sel + 1) % n)) ;;
      q|Q) MENU_INDEX=-1; return 0 ;;
      '')  MENU_INDEX=$sel; return 0 ;;
      [1-9])
        local idx=$((key - 1))
        ((idx < n)) && { MENU_INDEX=$idx; return 0; } ;;
    esac
  done
}

pause() {
  [[ -t 0 ]] || return 0
  printf '\n%s' "${DIM}press enter to continue${R}"
  read -r _ || true
}

confirm() { # confirm "question" [default_no]
  local q=$1 reply=''
  read -rp "$q ${DIM}[y/N]${R} " reply || return 1
  [[ $reply == [yY] || $reply == [yY][eE][sS] ]]
}

ask() { # ask VAR "prompt" "default"
  local __var=$1 __prompt=$2 __default=${3:-} __reply=''
  if [[ -n $__default ]]; then
    read -rp "$__prompt ${DIM}[$__default]${R}: " __reply || true
    __reply=${__reply:-$__default}
  else
    read -rp "$__prompt: " __reply || true
  fi
  printf -v "$__var" '%s' "$__reply"
}

ask_secret() { # ask_secret VAR "prompt"
  local __var=$1 __reply=''
  read -rsp "$2: " __reply || true
  printf '\n'
  printf -v "$__var" '%s' "$__reply"
}

# Runs a task without letting a non-zero exit tear down the menu loop.
run_task() {
  local fn=$1; shift
  set +e
  "$fn" "$@"
  local rc=$?
  set -e
  ((rc == 0)) || err "'${fn#task_}' exited with status $rc"
  return 0
}

# ------------------------------------------------------------------- helpers

have() { command -v "$1" >/dev/null 2>&1; }

need() { # need cmd... -> fails with guidance
  local missing=()
  local c
  for c in "$@"; do have "$c" || missing+=("$c"); done
  if ((${#missing[@]})); then
    err "missing required tool(s): ${missing[*]}"
    say "  Run '${B}./soulserve.sh doctor${R}' to see what the project expects."
    return 1
  fi
}

urlencode() { # percent-encode a value for a connection URL
  local s=$1 out='' i c
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [a-zA-Z0-9.~_-]) out+=$c ;;
      *) printf -v c '%%%02X' "'$c"; out+=$c ;;
    esac
  done
  printf '%s' "$out"
}

mask() { # report a secret's length, never any of its characters
  local v=$1
  ((${#v} == 0)) && { printf '(empty)'; return; }
  printf '%s (%d chars)' "$(printf '•%.0s' $(seq 1 8))" "${#v}"
}

random_secret() {
  if have openssl; then openssl rand -hex 32
  elif [[ -r /dev/urandom ]]; then head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  else date +%s%N | sha256sum | cut -c1-64
  fi
}

load_env() { # tolerant .env reader; ignores anything that is not KEY=VALUE
  [[ -f $ENV_FILE ]] || return 1
  local line key value
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
    value=${value%$'\r'}
    [[ $value == \"*\" && $value == *\" ]] && value=${value:1:-1}
    [[ $value == \'*\' && $value == *\' ]] && value=${value:1:-1}
    export "$key=$value"
  done < "$ENV_FILE"
}

require_env() {
  load_env || { err "no .env yet — run 'Environment → Create or update .env' first"; return 1; }
  [[ -n ${DATABASE_URL:-} ]] || { err "DATABASE_URL is not set in .env"; return 1; }
}

api_port() { # HTTP_ADDR is ":8080" or "0.0.0.0:8080"
  local addr=${HTTP_ADDR:-:8080}
  printf '%s' "${addr##*:}"
}

lan_ip() {
  local ip=''
  if have ip; then ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')
  elif have ipconfig; then ip=$(ipconfig getifaddr en0 2>/dev/null || true)
  fi
  printf '%s' "${ip:-127.0.0.1}"
}

# ==================================================================== doctor

task_doctor() {
  step "Toolchain"
  local rows=(
    "go|Go 1.23+|backend build and run"
    "flutter|Flutter 3.24+|app build and run"
    "psql|PostgreSQL client|database setup"
    "pg_isready|PostgreSQL client|health checks"
    "docker|Docker|containerised Postgres and API"
    "adb|Android platform-tools|APK install, device port forwarding"
    "java|JDK 17+|Android builds"
    "curl|curl|API health probing"
  )
  local row name label why version
  for row in "${rows[@]}"; do
    IFS='|' read -r name label why <<< "$row"
    if have "$name"; then
      case $name in
        go)      version=$(go version 2>/dev/null | awk '{print $3}') ;;
        flutter) version=$(flutter --version 2>/dev/null | head -1 | awk '{print $2}') ;;
        psql)    version=$(psql --version 2>/dev/null | awk '{print $3}') ;;
        docker)  version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ,) ;;
        java)    version=$(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/') ;;
        *)       version='' ;;
      esac
      printf '  %sfound%s  %-10s %s\n' "$GRN" "$R" "$name" "${DIM}${version}${R}"
    else
      printf '  %s----%s   %-10s %s\n' "$YEL" "$R" "$name" "${DIM}${label} — ${why}${R}"
    fi
  done

  step "Project"
  [[ -f $ENV_FILE ]] && ok ".env present" || warn ".env missing — Environment → Create or update .env"
  [[ -f $SCHEMA ]] && ok "schema.sql present" || warn "backend/schema.sql missing"

  if load_env && [[ -n ${DATABASE_URL:-} ]]; then
    if have pg_isready && pg_isready -d "$DATABASE_URL" >/dev/null 2>&1; then
      ok "database reachable"
    else
      warn "database not reachable with the configured DATABASE_URL"
    fi
    local secret=${JWT_SECRET:-}
    if ((${#secret} < 32)); then
      warn "JWT_SECRET is ${#secret} characters; the API requires at least 32"
    else
      ok "JWT_SECRET length acceptable"
    fi
  fi
  return 0
}

# =============================================================== environment

task_env_init() {
  step "Environment"
  if [[ -f $ENV_FILE ]]; then
    load_env
    say "An .env already exists. Values you leave blank keep their current setting."
  else
    [[ -f $ENV_SAMPLE ]] || die "neither .env nor .env.example is present"
    say "Creating .env from .env.example."
  fi

  local db user pass host port secret origins addr
  ask db     "Database name"             "${POSTGRES_DB:-soulserve}"
  ask user   "Database user"             "${POSTGRES_USER:-soulserve}"
  ask_secret pass "Database password ${DIM}(blank keeps current)${R}"
  [[ -z $pass ]] && pass=${POSTGRES_PASSWORD:-soulserve}
  ask host   "Database host"             "${PGHOST:-localhost}"
  ask port   "Database port"             "${PGPORT:-5432}"
  ask addr   "API listen address"        "${HTTP_ADDR:-:8080}"
  ask origins "Allowed CORS origins"     "${ALLOWED_ORIGINS:-http://localhost:3000,http://localhost:8081}"

  secret=${JWT_SECRET:-}
  if [[ ${#secret} -lt 32 ]]; then
    secret=$(random_secret)
    info "generated a new 64-character JWT_SECRET"
  elif confirm "Rotate JWT_SECRET? ${DIM}(invalidates every existing session)${R}"; then
    secret=$(random_secret)
    info "rotated JWT_SECRET"
  fi

  local enc; enc=$(urlencode "$pass")
  umask 077
  cat > "$ENV_FILE" <<EOF
# Written by ./soulserve.sh — safe to edit by hand.
POSTGRES_DB=$db
POSTGRES_USER=$user
POSTGRES_PASSWORD=$pass
DATABASE_URL=postgres://$user:$enc@$host:$port/$db?sslmode=disable
JWT_SECRET=$secret
HTTP_ADDR=$addr
ALLOWED_ORIGINS=$origins
EOF
  chmod 600 "$ENV_FILE"
  ok "wrote .env ${DIM}(mode 600, git-ignored)${R}"
}

task_env_show() {
  require_env || return 1
  step "Current environment"
  printf '  %-18s %s\n' 'POSTGRES_DB'      "${POSTGRES_DB:-}"
  printf '  %-18s %s\n' 'POSTGRES_USER'    "${POSTGRES_USER:-}"
  printf '  %-18s %s\n' 'POSTGRES_PASSWORD' "$(mask "${POSTGRES_PASSWORD:-}")"
  printf '  %-18s %s\n' 'DATABASE_URL'     "$(sed 's#://[^:]*:[^@]*@#://***:***@#' <<< "${DATABASE_URL:-}")"
  printf '  %-18s %s\n' 'JWT_SECRET'       "$(mask "${JWT_SECRET:-}")"
  printf '  %-18s %s\n' 'HTTP_ADDR'        "${HTTP_ADDR:-}"
  printf '  %-18s %s\n' 'ALLOWED_ORIGINS'  "${ALLOWED_ORIGINS:-}"
}

# ================================================================== database

task_db_setup() {
  ui_menu "Where should PostgreSQL run?" \
    "Local server — create the role and database with sudo" \
    "Docker — start the postgres service from docker-compose.yml"
  case $MENU_INDEX in
    0) db_setup_local ;;
    1) db_setup_docker ;;
    *) return 0 ;;
  esac
}

db_setup_local() {
  need psql || return 1
  require_env || return 1
  step "Provisioning a local PostgreSQL role and database"

  if have systemctl && ! systemctl is-active --quiet postgresql; then
    info "postgresql service is not running"
    confirm "Start it now with sudo systemctl start postgresql?" && sudo systemctl start postgresql
  fi

  local db=${POSTGRES_DB:-soulserve} user=${POSTGRES_USER:-soulserve} pass=${POSTGRES_PASSWORD:-soulserve}
  say "Creating role ${B}$user${R} and database ${B}$db${R} as the postgres superuser."
  say "${DIM}You will be asked for your sudo password.${R}"

  # The role is created only when absent, and its password is set either way,
  # so re-running this after changing .env repairs the credentials.
  sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -v user="$user" -v pass="$pass" -v db="$db" <<'EOF' || return 1
SELECT format('CREATE ROLE %I LOGIN', :'user')
  WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'user', :'pass') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'user')
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'db', :'user') \gexec
EOF

  ok "role and database ready"
  task_db_schema
}

db_setup_docker() {
  need docker || return 1
  step "Starting the postgres service"
  docker compose up -d postgres || return 1
  info "waiting for the container to report healthy"
  local i
  for ((i = 0; i < 60; i++)); do
    if docker compose exec -T postgres pg_isready -q 2>/dev/null; then ok "postgres is accepting connections"; break; fi
    sleep 1
  done
  task_db_schema
}

task_db_schema() {
  need psql || return 1
  require_env || return 1
  [[ -f $SCHEMA ]] || die "backend/schema.sql not found"
  step "Applying backend/schema.sql"
  # Every statement is CREATE ... IF NOT EXISTS, so this is safe to re-run.
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$SCHEMA" || return 1
  ok "schema applied"
  task_db_status
}

task_db_status() {
  need psql || return 1
  require_env || return 1
  step "Database"
  if ! pg_isready -d "$DATABASE_URL" >/dev/null 2>&1; then
    err "not reachable — check that PostgreSQL is running and DATABASE_URL is correct"
    return 1
  fi
  ok "reachable"
  psql "$DATABASE_URL" -q -X <<'EOF' || true
\pset border 2
SELECT
  (SELECT count(*) FROM users)      AS users,
  (SELECT count(*) FROM waste_logs) AS waste_logs,
  (SELECT count(*) FROM claims)     AS claims;
EOF
}

task_db_shell() {
  need psql || return 1
  require_env || return 1
  info "opening psql — \\q to return to the menu"
  psql "$DATABASE_URL"
}

task_db_reset() {
  need psql || return 1
  require_env || return 1
  local db=${POSTGRES_DB:-soulserve}
  step "Reset database"
  warn "This deletes every row in ${B}$db${R}: accounts, donations, and claims."
  local typed=''
  ask typed "Type the database name to confirm" ""
  [[ $typed == "$db" ]] || { info "cancelled"; return 0; }

  # Dropping the schema is enough and does not need superuser rights, unlike
  # DROP DATABASE.
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q <<'EOF' || return 1
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
EOF
  ok "schema dropped"
  task_db_schema
}

# ======================================================================= run

BACKEND_PID=''      # the API process itself
WRAPPER_PID=''      # the pipeline that prefixes and logs its output

build_api_binary() {
  need go || return 1
  mkdir -p "$WORK/bin"
  info "compiling the API"
  (cd backend && go build -o "$WORK/bin/api" ./cmd/api) || return 1
}

# Starts the API with its output prefixed and teed to a log.
#
# Three traps this avoids, each of which bit during testing:
#   * `go run` execs a child binary that survives a kill aimed at the parent,
#     so the API is compiled first and the binary run directly.
#   * A detached `tail -f` on the log cannot be stopped reliably, because $! on
#     a pipeline names its *last* command; killing that leaves the tail alive
#     holding the terminal open. There is no tail here at all.
#   * `setsid` forks and exits when the caller is already a process group
#     leader — which is what happens under interactive job control — leaving $!
#     pointing at a corpse and the API orphaned. So the API publishes its own
#     PID from inside the pipeline instead.
#
# Killing the API makes tee and awk see EOF and exit by themselves, so one
# signal to one PID takes the whole thing down.
start_api_background() {
  build_api_binary || return 1
  require_env || return 1
  mkdir -p "$WORK"
  local log="$WORK/api.log" pidfile="$WORK/api.pid"
  : > "$log"
  rm -f "$pidfile"

  {
    "$WORK/bin/api" 2>&1 &
    echo $! > "$pidfile"
    wait
  } | tee -a "$log" | awk -v p="${CYN}[api]${R} " '{ print p $0; fflush() }' &
  WRAPPER_PID=$!

  local i
  for ((i = 0; i < 60; i++)); do
    [[ -s $pidfile ]] && break
    sleep 0.05
  done
  BACKEND_PID=$(cat "$pidfile" 2>/dev/null || true)
  if [[ -z $BACKEND_PID ]]; then
    err "could not determine the API process id"
    return 1
  fi
}

stop_background() {
  if [[ -n $BACKEND_PID ]] && kill -0 "$BACKEND_PID" 2>/dev/null; then
    kill -TERM "$BACKEND_PID" 2>/dev/null || true
    local i
    for ((i = 0; i < 30; i++)); do
      kill -0 "$BACKEND_PID" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$BACKEND_PID" 2>/dev/null || true
  fi
  # tee and awk drain and exit once the API's stdout closes.
  if [[ -n $WRAPPER_PID ]]; then wait "$WRAPPER_PID" 2>/dev/null || true; fi
  rm -f "$WORK/api.pid"
  BACKEND_PID=''; WRAPPER_PID=''
}

# An API left behind by a previous run would hold the port and make this one
# look broken for reasons that are not on screen.
reap_stale_api() {
  local pidfile="$WORK/api.pid" stale
  [[ -s $pidfile ]] || return 0
  stale=$(cat "$pidfile" 2>/dev/null || true)
  if [[ -n $stale ]] && kill -0 "$stale" 2>/dev/null; then
    warn "an API from an earlier run is still on port $(api_port) (pid $stale) — stopping it"
    kill -TERM "$stale" 2>/dev/null || true
    sleep 0.5
    kill -KILL "$stale" 2>/dev/null || true
  fi
  rm -f "$pidfile"
}

wait_for_api() { # wait_for_api PORT
  local port=$1 url="http://127.0.0.1:$port/api/health" i
  for ((i = 0; i < 80; i++)); do
    if [[ -n $BACKEND_PID ]] && ! kill -0 "$BACKEND_PID" 2>/dev/null; then
      err "the API exited during startup — see $WORK/api.log"
      return 1
    fi
    if have curl; then
      curl -fsS --max-time 1 "$url" >/dev/null 2>&1 && return 0
    elif (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      exec 3>&- 3<&-; return 0
    fi
    sleep 0.25
  done
  return 1
}

# flutter devices, parsed into "id|description" pairs.
list_devices() {
  flutter devices 2>/dev/null | awk -F'•' '
    NF >= 3 {
      id = $2; desc = $1;
      gsub(/^[ \t]+|[ \t]+$/, "", id);
      gsub(/^[ \t]+|[ \t]+$/, "", desc);
      if (id != "" && desc !~ /^[0-9]+ connected/) print id "|" desc;
    }'
}

pick_device() { # pick_device VAR
  local __var=$1
  need flutter || return 1
  info "querying connected devices"
  local -a __ids=() __labels=()
  local __id __desc
  while IFS='|' read -r __id __desc; do
    [[ -n $__id ]] || continue
    __ids+=("$__id"); __labels+=("$__desc  ${DIM}($__id)${R}")
  done < <(list_devices)

  if ((${#__ids[@]} == 0)); then
    warn "flutter reported no devices"
    local __manual=''
    ask __manual "Device id to use" "chrome"
    printf -v "$__var" '%s' "$__manual"
    return 0
  fi

  ui_menu "Run on which device?" "${__labels[@]}"
  ((MENU_INDEX >= 0)) || return 1
  printf -v "$__var" '%s' "${__ids[MENU_INDEX]}"
}

# Picks the URL the app should call, which is not always localhost: an Android
# emulator reaches the host at 10.0.2.2, and a physical handset needs either an
# adb reverse tunnel or the machine's LAN address.
api_base_for_device() { # api_base_for_device VAR DEVICE PORT
  local __var=$1 __device=$2 __port=$3 __url=''
  case $__device in
    emulator-*|android-*)
      __url="http://10.0.2.2:$__port/api" ;;
    chrome|web-server|linux|macos|windows)
      __url="http://localhost:$__port/api" ;;
    *)
      if have adb && adb devices 2>/dev/null | grep -q "^${__device}[[:space:]]*device$"; then
        if adb -s "$__device" reverse "tcp:$__port" "tcp:$__port" >/dev/null 2>&1; then
          info "adb reverse tcp:$__port — the handset can now reach this machine on localhost"
          __url="http://localhost:$__port/api"
        fi
      fi
      if [[ -z $__url ]]; then
        local __ip; __ip=$(lan_ip)
        ask __url "API base URL the device should call" "http://$__ip:$__port/api"
      fi ;;
  esac
  [[ -n $__url ]] || __url="http://localhost:$__port/api"
  printf -v "$__var" '%s' "$__url"
}

task_run_api() {
  require_env || return 1
  build_api_binary || return 1
  local port; port=$(api_port)
  step "API on port $port"
  info "ctrl-c to stop"
  "$WORK/bin/api"
}

task_run_app() {
  need flutter || return 1
  load_env || true
  local device=''; pick_device device || return 0
  local port; port=$(api_port)
  local url=''; api_base_for_device url "$device" "$port"
  step "App on $device"
  info "API_BASE_URL=$url"
  (cd frontend && flutter run -d "$device" --dart-define=API_BASE_URL="$url")
}

# The headline: API in the background with prefixed output, app in the
# foreground so its hot-reload keys keep working on a real terminal.
task_run_both() {
  need go flutter || return 1
  require_env || return 1
  local device=''; pick_device device || return 0
  local port; port=$(api_port)
  local url=''; api_base_for_device url "$device" "$port"

  step "Starting API and app together"
  reap_stale_api
  trap 'stop_background' INT TERM EXIT

  start_api_background || { stop_background; return 1; }
  if wait_for_api "$port"; then
    ok "API healthy on port $port"
  else
    err "API did not become healthy"
    stop_background
    trap - INT TERM EXIT
    return 1
  fi

  info "API_BASE_URL=$url"
  info "app output follows; ctrl-c stops both"
  rule
  (cd frontend && flutter run -d "$device" --dart-define=API_BASE_URL="$url") || true

  stop_background
  trap - INT TERM EXIT
  ok "both stopped"
}

# ==================================================================== builds

dist_note() {
  rule
  ok "artifacts in ${B}${DIST#"$ROOT"/}${R}"
  have du && du -h "$DIST"/* 2>/dev/null | sed 's/^/  /' || true
}

task_build_api() {
  need go || return 1
  local -a targets=(
    "linux/amd64" "linux/arm64"
    "windows/amd64" "darwin/amd64" "darwin/arm64"
  )
  ui_menu "Build the API for…" "${targets[@]}" "every target above"
  ((MENU_INDEX >= 0)) || return 0

  local -a chosen=()
  if ((MENU_INDEX == ${#targets[@]})); then chosen=("${targets[@]}"); else chosen=("${targets[MENU_INDEX]}"); fi

  mkdir -p "$DIST/backend"
  local t os arch out
  for t in "${chosen[@]}"; do
    os=${t%%/*}; arch=${t##*/}
    out="$DIST/backend/soulserve-api-$os-$arch"
    [[ $os == windows ]] && out+='.exe'
    info "building $t"
    # Static binary: no libc dependency on the target host.
    (cd backend && CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" \
      go build -trimpath -ldflags '-s -w' -o "$out" ./cmd/api) || return 1
  done
  dist_note
}

# Release artifacts are compiled with the API URL baked in, so a localhost
# default would produce an app that works only on the build machine.
ask_api_url() { # ask_api_url VAR
  local __var=$1 __port __url
  __port=$(api_port)
  ask __url "API base URL to compile into the app" "http://$(lan_ip):$__port/api"
  case $__url in
    *localhost*|*127.0.0.1*)
      warn "'$__url' only resolves on this machine — a phone or another host will fail to connect" ;;
  esac
  printf -v "$__var" '%s' "$__url"
}

task_build_apk() {
  need flutter || return 1
  local url=''; ask_api_url url
  local split=''
  confirm "Split per ABI? ${DIM}(smaller downloads, one APK per architecture)${R}" && split='--split-per-abi'

  step "Building release APK"
  warn "signed with the debug key — frontend/android has no release signing config yet"
  (cd frontend && flutter build apk --release $split --dart-define=API_BASE_URL="$url") || return 1

  mkdir -p "$DIST/frontend"
  cp -f frontend/build/app/outputs/flutter-apk/*.apk "$DIST/frontend/" 2>/dev/null || true
  dist_note
}

task_build_aab() {
  need flutter || return 1
  local url=''; ask_api_url url
  step "Building Android App Bundle"
  (cd frontend && flutter build appbundle --release --dart-define=API_BASE_URL="$url") || return 1
  mkdir -p "$DIST/frontend"
  cp -f frontend/build/app/outputs/bundle/release/*.aab "$DIST/frontend/" 2>/dev/null || true
  dist_note
}

task_build_desktop() {
  need flutter || return 1
  local host target
  case ${OSTYPE:-linux} in
    linux*)  host=linux ;;
    darwin*) host=macos ;;
    msys*|cygwin*|win32) host=windows ;;
    *) host=linux ;;
  esac

  ui_menu "Desktop target" "linux" "windows" "macos"
  ((MENU_INDEX >= 0)) || return 0
  target=$(printf '%s' "linux windows macos" | cut -d' ' -f$((MENU_INDEX + 1)))

  if [[ $target != "$host" ]]; then
    err "Flutter cannot cross-compile desktop targets"
    say "  A ${B}$target${R} build has to run on $target. On this $host machine you can still"
    say "  produce the ${B}$target${R} API binary from ${B}Build → API${R}."
    return 1
  fi

  step "Building $target desktop bundle"
  local url=''; ask_api_url url
  (cd frontend && flutter build "$target" --release --dart-define=API_BASE_URL="$url") || return 1

  mkdir -p "$DIST/frontend"
  local src=''
  case $target in
    linux)   src=$(echo frontend/build/linux/*/release/bundle) ;;
    windows) src=$(echo frontend/build/windows/*/runner/Release) ;;
    macos)   src=$(echo frontend/build/macos/Build/Products/Release) ;;
  esac
  if [[ -d $src ]]; then
    local archive="$DIST/frontend/soulserve-$target.tar.gz"
    tar -czf "$archive" -C "$(dirname "$src")" "$(basename "$src")"
    ok "packaged $(basename "$archive")"
  fi
  dist_note
}

task_build_web() {
  need flutter || return 1
  local url=''; ask_api_url url
  step "Building web bundle"
  (cd frontend && flutter build web --release --dart-define=API_BASE_URL="$url") || return 1
  mkdir -p "$DIST/frontend"
  tar -czf "$DIST/frontend/soulserve-web.tar.gz" -C frontend/build web
  dist_note
}

task_build_all() {
  step "Building every artifact this machine can produce"
  local url=''; ask_api_url url
  mkdir -p "$DIST/backend" "$DIST/frontend"

  local t os arch out
  for t in linux/amd64 linux/arm64 windows/amd64 darwin/arm64; do
    os=${t%%/*}; arch=${t##*/}
    out="$DIST/backend/soulserve-api-$os-$arch"
    [[ $os == windows ]] && out+='.exe'
    info "API $t"
    (cd backend && CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" \
      go build -trimpath -ldflags '-s -w' -o "$out" ./cmd/api) || return 1
  done

  info "release APK"
  (cd frontend && flutter build apk --release --dart-define=API_BASE_URL="$url") \
    && cp -f frontend/build/app/outputs/flutter-apk/*.apk "$DIST/frontend/" 2>/dev/null \
    || warn "APK build failed — skipping"

  info "web bundle"
  (cd frontend && flutter build web --release --dart-define=API_BASE_URL="$url") \
    && tar -czf "$DIST/frontend/soulserve-web.tar.gz" -C frontend/build web \
    || warn "web build failed — skipping"

  if [[ ${OSTYPE:-linux} == linux* ]]; then
    info "linux desktop bundle"
    (cd frontend && flutter build linux --release --dart-define=API_BASE_URL="$url") \
      && tar -czf "$DIST/frontend/soulserve-linux.tar.gz" -C frontend/build/linux/x64/release bundle \
      || warn "linux desktop build failed — skipping"
  fi
  dist_note
}

# =================================================================== quality

task_test() {
  local rc=0 ran=0
  if have go; then
    step "Go tests"
    if compgen -G 'backend/**/*_test.go' >/dev/null 2>&1 || \
       find backend -name '*_test.go' -print -quit | grep -q .; then
      (cd backend && go test ./...) || rc=1
      ran=1
    else
      info "no Go test files in backend/"
    fi
  else warn "go not installed — skipping backend tests"; fi

  if have flutter; then
    step "Flutter tests"
    # `flutter test` exits non-zero when test/ is absent, which is not a
    # failing suite — it is no suite.
    if [[ -d frontend/test ]]; then
      (cd frontend && flutter test) || rc=1
      ran=1
    else
      info "no frontend/test directory"
    fi
  else warn "flutter not installed — skipping app tests"; fi

  if ((rc == 0 && ran == 1)); then ok "all suites passed"
  elif ((ran == 0)); then warn "nothing to run"; fi
  return $rc
}

task_lint() {
  local rc=0
  if have go; then
    step "go vet"
    (cd backend && go vet ./...) || rc=1
    step "gofmt"
    local unformatted
    unformatted=$(cd backend && gofmt -l internal cmd 2>/dev/null || true)
    if [[ -n $unformatted ]]; then
      err "not gofmt-clean:"; printf '  %s\n' $unformatted; rc=1
    else ok "gofmt clean"; fi
  fi
  if have flutter; then
    step "flutter analyze"
    (cd frontend && flutter analyze) || rc=1
  fi
  return $rc
}

task_format() {
  have go && { step "gofmt -w"; (cd backend && gofmt -w internal cmd) && ok "backend formatted"; }
  have dart && { step "dart format"; (cd frontend && dart format lib test) && ok "app formatted"; }
  return 0
}

task_deps() {
  have go && { step "Go modules"; (cd backend && go mod download) && ok "downloaded"; }
  have flutter && { step "Dart packages"; (cd frontend && flutter pub get) && ok "resolved"; }
  return 0
}

# ==================================================================== docker

task_docker_up()   { need docker || return 1; step "docker compose up"; docker compose up --build -d && docker compose ps; }
task_docker_down() { need docker || return 1; step "docker compose down"; docker compose down; }
task_docker_logs() { need docker || return 1; info "ctrl-c to stop following"; docker compose logs -f --tail=100; }
task_docker_ps()   { need docker || return 1; docker compose ps; }

task_clean() {
  step "Clean"
  confirm "Remove dist/, .soulserve/, and both build caches?" || { info "cancelled"; return 0; }
  rm -rf "$DIST" "$WORK"
  have flutter && (cd frontend && flutter clean >/dev/null) && ok "flutter clean"
  have go && (cd backend && go clean -cache -testcache >/dev/null 2>&1) && ok "go caches cleared"
  ok "done"
}

# ===================================================================== menus

menu_database() {
  while :; do
    banner
    ui_menu "Database" \
      "Set up PostgreSQL (local or Docker)" \
      "Apply schema.sql" \
      "Status and row counts" \
      "Open a psql shell" \
      "Reset — delete all data and recreate" \
      "Back"
    case $MENU_INDEX in
      0) banner; run_task task_db_setup;  pause ;;
      1) banner; run_task task_db_schema; pause ;;
      2) banner; run_task task_db_status; pause ;;
      3) banner; run_task task_db_shell ;;
      4) banner; run_task task_db_reset;  pause ;;
      *) return 0 ;;
    esac
  done
}

menu_run() {
  while :; do
    banner
    ui_menu "Run" \
      "API and app together" \
      "API only" \
      "App only" \
      "Back"
    case $MENU_INDEX in
      0) banner; run_task task_run_both; pause ;;
      1) banner; run_task task_run_api;  pause ;;
      2) banner; run_task task_run_app;  pause ;;
      *) return 0 ;;
    esac
  done
}

menu_build() {
  while :; do
    banner
    ui_menu "Build" \
      "API binary (Linux, Windows, macOS)" \
      "Android APK" \
      "Android App Bundle (.aab)" \
      "Desktop bundle (Linux / Windows / macOS)" \
      "Web bundle" \
      "Everything this machine can build" \
      "Back"
    case $MENU_INDEX in
      0) banner; run_task task_build_api;     pause ;;
      1) banner; run_task task_build_apk;     pause ;;
      2) banner; run_task task_build_aab;     pause ;;
      3) banner; run_task task_build_desktop; pause ;;
      4) banner; run_task task_build_web;     pause ;;
      5) banner; run_task task_build_all;     pause ;;
      *) return 0 ;;
    esac
  done
}

menu_quality() {
  while :; do
    banner
    ui_menu "Checks" \
      "Run all tests" \
      "Analyze and vet" \
      "Format sources" \
      "Fetch dependencies" \
      "Back"
    case $MENU_INDEX in
      0) banner; run_task task_test;   pause ;;
      1) banner; run_task task_lint;   pause ;;
      2) banner; run_task task_format; pause ;;
      3) banner; run_task task_deps;   pause ;;
      *) return 0 ;;
    esac
  done
}

menu_docker() {
  while :; do
    banner
    ui_menu "Docker" \
      "Up (build and start)" \
      "Down" \
      "Follow logs" \
      "Status" \
      "Back"
    case $MENU_INDEX in
      0) banner; run_task task_docker_up;   pause ;;
      1) banner; run_task task_docker_down; pause ;;
      2) banner; run_task task_docker_logs; pause ;;
      3) banner; run_task task_docker_ps;   pause ;;
      *) return 0 ;;
    esac
  done
}

menu_main() {
  while :; do
    banner
    ui_menu "What would you like to do?" \
      "Run          ${DIM}API and app, together or apart${R}" \
      "Database     ${DIM}provision PostgreSQL, apply the schema${R}" \
      "Build        ${DIM}APK, exe, desktop, web, API binaries${R}" \
      "Checks       ${DIM}tests, analysis, formatting${R}" \
      "Docker       ${DIM}compose stack${R}" \
      "Environment  ${DIM}create or inspect .env${R}" \
      "Doctor       ${DIM}what is installed, what is missing${R}" \
      "Clean        ${DIM}remove build output${R}" \
      "Quit"
    case $MENU_INDEX in
      0) menu_run ;;
      1) menu_database ;;
      2) menu_build ;;
      3) menu_quality ;;
      4) menu_docker ;;
      5) banner
         ui_menu "Environment" "Create or update .env" "Show current values" "Back"
         case $MENU_INDEX in
           0) banner; run_task task_env_init; pause ;;
           1) banner; run_task task_env_show; pause ;;
         esac ;;
      6) banner; run_task task_doctor; pause ;;
      7) banner; run_task task_clean;  pause ;;
      *) printf '\n'; ok "bye"; return 0 ;;
    esac
  done
}

# ================================================================ entrypoint

usage() {
  cat <<EOF
${B}Soul Serve${R} — project control script

  ${B}./soulserve.sh${R}                 open the interactive menu

${B}Run${R}
  run                 API and app together
  run:api             API only
  run:app             Flutter app only

${B}Database${R}
  db:setup            provision PostgreSQL (local or Docker)
  db:schema           apply backend/schema.sql
  db:status           reachability and row counts
  db:shell            open psql
  db:reset            delete all data, then reapply the schema

${B}Build${R}
  build:api           API binaries
  build:apk           release APK
  build:aab           Android App Bundle
  build:desktop       desktop bundle for this host
  build:web           web bundle
  build:all           everything this machine can build

${B}Other${R}
  env                 create or update .env
  env:show            print current settings, secrets masked
  doctor              report the toolchain
  test | lint | fmt   checks
  deps                fetch Go modules and Dart packages
  docker:up | docker:down | docker:logs | docker:ps
  clean               remove build output

Artifacts are written to ${B}dist/${R}.
EOF
}

main() {
  local cmd=${1:-}
  case $cmd in
    ''|menu)        menu_main ;;
    -h|--help|help) usage ;;
    run)            task_run_both ;;
    run:api)        task_run_api ;;
    run:app)        task_run_app ;;
    db:setup)       task_db_setup ;;
    db:schema)      task_db_schema ;;
    db:status)      task_db_status ;;
    db:shell)       task_db_shell ;;
    db:reset)       task_db_reset ;;
    build:api)      task_build_api ;;
    build:apk)      task_build_apk ;;
    build:aab)      task_build_aab ;;
    build:desktop)  task_build_desktop ;;
    build:web)      task_build_web ;;
    build:all)      task_build_all ;;
    env)            task_env_init ;;
    env:show)       task_env_show ;;
    doctor)         task_doctor ;;
    test)           task_test ;;
    lint)           task_lint ;;
    fmt|format)     task_format ;;
    deps)           task_deps ;;
    docker:up)      task_docker_up ;;
    docker:down)    task_docker_down ;;
    docker:logs)    task_docker_logs ;;
    docker:ps)      task_docker_ps ;;
    clean)          task_clean ;;
    *)              err "unknown command: $cmd"; printf '\n'; usage; exit 2 ;;
  esac
}

# Guarded so the file can be sourced in tests without launching the menu.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
