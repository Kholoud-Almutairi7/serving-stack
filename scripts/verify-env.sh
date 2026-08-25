#!/usr/bin/env bash
# verify-env.sh - the prep-week gate for the SDA AI Data Center bootcamp.
#
# Checks that this machine can do everything week 2 day 1 assumes, writes
# verify-env-report.json into the current directory, and prints exactly one of:
#
#   VERIFY-ENV: PASS
#   VERIFY-ENV: PASS WITH WARNINGS
#   VERIFY-ENV: FAIL (<n> blocking)
#
# Usage:   ./week-01-prep/verify-env.sh
#          bash week-01-prep/verify-env.sh          (if the exec bit is missing)
#
# Portable to Linux, WSL2 and macOS. Written for bash 3.2, which is what macOS
# ships, so no associative arrays and no ${var,,}.

set -u

REPORT="${REPORT:-verify-env-report.json}"
NEED_PY_MINOR=10          # python 3.10 or newer
NEED_DISK_GB=15           # blocking below this
WANT_DISK_GB=30           # warn below this
NEED_MEM_GB=4             # blocking below this
WANT_MEM_GB=8             # warn below this
SERVICE_PORT="${SERVICE_PORT:-8000}"

BLOCKING=0
WARNINGS=0
ROWS=""                   # accumulated JSON objects

# ANSI, disabled when not a terminal so logs stay readable.
if [ -t 1 ]; then
  G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; B=$'\033[1m'; N=$'\033[0m'
else
  G=""; Y=""; R=""; B=""; N=""
fi

# json_escape <string>
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
                         -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

# record <status: pass|warn|fail> <name> <detail>
record() {
  status="$1"; name="$2"; detail="$3"
  case "$status" in
    pass) printf '  %s[ ok ]%s %-22s %s\n'   "$G" "$N" "$name" "$detail" ;;
    warn) printf '  %s[warn]%s %-22s %s\n'   "$Y" "$N" "$name" "$detail"
          WARNINGS=$((WARNINGS + 1)) ;;
    fail) printf '  %s[FAIL]%s %-22s %s\n'   "$R" "$N" "$name" "$detail"
          BLOCKING=$((BLOCKING + 1)) ;;
  esac
  ROWS="${ROWS}    {\"check\": \"$(json_escape "$name")\", \"status\": \"${status}\", \"detail\": \"$(json_escape "$detail")\"},
"
}

section() { printf '\n%s%s%s\n' "$B" "$1" "$N"; }

have() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------------------- #
printf '%sAIDC prep-week environment check%s\n' "$B" "$N"
printf 'Report will be written to: %s\n' "$REPORT"

# --------------------------------------------------------------------------- #
section "Machine"

OS="$(uname -s)"
ARCH="$(uname -m)"
PLATFORM="$OS"
if [ "$OS" = "Linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
  PLATFORM="WSL2"
fi
record pass "platform" "$PLATFORM $ARCH"

case "$ARCH" in
  arm64|aarch64)
    if [ "$OS" = "Darwin" ]; then
      record warn "cpu architecture" \
        "Apple Silicon (arm64). Images you build are arm64; push amd64 with: docker buildx build --platform linux/amd64"
    else
      record warn "cpu architecture" \
        "arm64. Course images and graders are amd64; build with --platform linux/amd64 before pushing."
    fi
    ;;
  x86_64|amd64) record pass "cpu architecture" "$ARCH" ;;
  *)            record warn "cpu architecture" "$ARCH is unusual for this course; expect image compatibility work" ;;
esac

# Memory
MEM_GB=""
if [ -r /proc/meminfo ]; then
  MEM_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  MEM_GB="$(awk -v k="$MEM_KB" 'BEGIN{printf "%.1f", k/1048576}')"
elif have sysctl && [ "$OS" = "Darwin" ]; then
  MEM_B="$(sysctl -n hw.memsize 2>/dev/null)"
  MEM_GB="$(awk -v b="$MEM_B" 'BEGIN{printf "%.1f", b/1073741824}')"
fi
if [ -z "$MEM_GB" ]; then
  record warn "memory" "could not determine total RAM"
else
  if awk -v m="$MEM_GB" -v n="$NEED_MEM_GB" 'BEGIN{exit !(m < n)}'; then
    record fail "memory" "${MEM_GB} GB total; below ${NEED_MEM_GB} GB, Docker plus a model will not fit"
  elif awk -v m="$MEM_GB" -v w="$WANT_MEM_GB" 'BEGIN{exit !(m < w)}'; then
    record warn "memory" "${MEM_GB} GB total; ${WANT_MEM_GB} GB is comfortable, expect slow CPU labs"
  else
    record pass "memory" "${MEM_GB} GB total"
  fi
fi

# Disk, on the current filesystem
DISK_KB="$(df -Pk . 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -z "${DISK_KB:-}" ]; then
  record warn "disk space" "could not determine free space"
else
  DISK_GB="$(awk -v k="$DISK_KB" 'BEGIN{printf "%.1f", k/1048576}')"
  if awk -v d="$DISK_GB" -v n="$NEED_DISK_GB" 'BEGIN{exit !(d < n)}'; then
    record fail "disk space" "${DISK_GB} GB free here; need at least ${NEED_DISK_GB} GB for images and weights"
  elif awk -v d="$DISK_GB" -v w="$WANT_DISK_GB" 'BEGIN{exit !(d < w)}'; then
    record warn "disk space" "${DISK_GB} GB free here; ${WANT_DISK_GB} GB is comfortable through week 4"
  else
    record pass "disk space" "${DISK_GB} GB free here"
  fi
fi

# --------------------------------------------------------------------------- #
section "Command line tools"

if have curl; then
  record pass "curl" "$(curl --version 2>/dev/null | head -1 | cut -d' ' -f1-2)"
else
  record fail "curl" "not installed; every green check in this course uses it"
fi

if have git; then
  GIT_V="$(git --version 2>/dev/null | awk '{print $3}')"
  record pass "git" "$GIT_V"
  GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
  GIT_MAIL="$(git config --global user.email 2>/dev/null || true)"
  if [ -n "$GIT_NAME" ] && [ -n "$GIT_MAIL" ]; then
    record pass "git identity" "$GIT_NAME <$GIT_MAIL>"
  else
    record warn "git identity" "user.name or user.email unset; your commits will not be attributed to you"
  fi
else
  record fail "git" "not installed; every lab is a commit on your fork"
fi

if have ssh; then
  if [ -f "$HOME/.ssh/id_ed25519.pub" ] || [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    record pass "ssh key" "a public key exists in ~/.ssh"
  else
    record warn "ssh key" "no key in ~/.ssh; fine if you use HTTPS with a token for GitHub"
  fi
else
  record warn "ssh" "not installed; needed only for the SSH route to GitHub and week-4 pods"
fi

# --------------------------------------------------------------------------- #
section "Python"

PY=""
for cand in python3 python; do
  if have "$cand"; then
    if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' 2>/dev/null; then
      PY="$cand"; break
    fi
  fi
done

if [ -z "$PY" ]; then
  record fail "python 3" "no python 3 interpreter found"
else
  PY_V="$("$PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"
  PY_MINOR="$("$PY" -c 'import sys; print(sys.version_info[1])' 2>/dev/null)"
  if [ "${PY_MINOR:-0}" -ge "$NEED_PY_MINOR" ]; then
    record pass "python 3" "$PY_V at $(command -v "$PY")"
  else
    record fail "python 3" "$PY_V found; the course needs 3.${NEED_PY_MINOR} or newer"
  fi

  # venv actually works. On Debian and Ubuntu this needs the python3-venv
  # package, and its absence is the single most common prep-week failure.
  VENV_TMP="$(mktemp -d 2>/dev/null || echo "/tmp/aidc-venv-$$")"
  if "$PY" -m venv "$VENV_TMP/v" >/dev/null 2>&1 && [ -x "$VENV_TMP/v/bin/python" ]; then
    if "$VENV_TMP/v/bin/python" -m pip --version >/dev/null 2>&1; then
      record pass "venv and pip" "a virtual environment was created and pip works inside it"
    else
      record fail "venv and pip" "venv created but pip is missing inside it; install python3-pip"
    fi
  else
    record fail "venv and pip" "$PY -m venv failed; on Ubuntu or WSL: sudo apt install python3-venv"
  fi
  rm -rf "$VENV_TMP" 2>/dev/null || true
fi

# --------------------------------------------------------------------------- #
section "Docker"

DOCKER_OK=0
if have docker; then
  record pass "docker client" "$(docker --version 2>/dev/null | sed 's/,.*//')"

  if docker info >/dev/null 2>&1; then
    DOCKER_OK=1
    SERVER_V="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown)"
    record pass "docker daemon" "reachable, server $SERVER_V"
  else
    ERR="$(docker info 2>&1 | head -1)"
    case "$ERR" in
      *permission*denied*)
        record fail "docker daemon" "permission denied on the socket; add yourself to the docker group and log out and back in" ;;
      *)
        record fail "docker daemon" "not reachable; start Docker Desktop, or: sudo systemctl start docker" ;;
    esac
  fi
else
  record fail "docker client" "not installed; module 3 part 2 covers your platform"
fi

if [ "$DOCKER_OK" = "1" ]; then
  # compose v2, needed from week 2 day 5
  if docker compose version >/dev/null 2>&1; then
    record pass "docker compose" "$(docker compose version --short 2>/dev/null || echo v2)"
  elif have docker-compose; then
    record warn "docker compose" "only the old standalone docker-compose found; labs are written for 'docker compose' (v2)"
  else
    record fail "docker compose" "not available; week 2 day 5 needs it"
  fi

  # can it actually run a container
  if docker run --rm hello-world >/dev/null 2>&1; then
    record pass "docker run" "hello-world ran and exited cleanly"
  else
    record fail "docker run" "could not run hello-world; check the daemon and your network"
  fi

  # logged in to Hub: without this the lab room shares one rate-limited IP
  HUB_USER="$(docker info 2>/dev/null | sed -n 's/^ *Username: *//p' | head -1)"
  if [ -n "$HUB_USER" ]; then
    record pass "docker hub login" "logged in as $HUB_USER"
  elif [ -f "$HOME/.docker/config.json" ] && grep -q '"auths"[^}]*[^{}]' "$HOME/.docker/config.json" 2>/dev/null; then
    record warn "docker hub login" "credentials found but the daemon did not report a username; run: docker login"
  else
    record fail "docker hub login" "not logged in; anonymous pulls are rate limited per IP and the lab room shares one. Run: docker login"
  fi

  # pre-seeded base images
  if docker image inspect python:3.11-slim >/dev/null 2>&1; then
    record pass "base image (cpu)" "python:3.11-slim is local"
  else
    record warn "base image (cpu)" "not pulled yet; run: docker pull python:3.11-slim"
  fi
  if docker image inspect nvidia/cuda:12.4.1-runtime-ubuntu22.04 >/dev/null 2>&1; then
    record pass "base image (cuda)" "nvidia/cuda:12.4.1-runtime-ubuntu22.04 is local"
  else
    record warn "base image (cuda)" "about 2 GB, needed on week 2 day 4; run: docker pull nvidia/cuda:12.4.1-runtime-ubuntu22.04"
  fi
fi

# --------------------------------------------------------------------------- #
section "Network"

PORT_HOLDER=""
if have ss; then
  PORT_HOLDER="$(ss -tlnp 2>/dev/null | awk -v p=":$SERVICE_PORT\$" '$4 ~ p {print; exit}')"
elif have lsof; then
  PORT_HOLDER="$(lsof -nP -iTCP:"$SERVICE_PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1" (pid "$2")"; exit}')"
fi
if [ -n "$PORT_HOLDER" ]; then
  record warn "port $SERVICE_PORT" "already in use by: $PORT_HOLDER. Free it, or set HOST_PORT to something else in week 2."
else
  record pass "port $SERVICE_PORT" "free"
fi

if have curl; then
  if curl -sSf -o /dev/null --max-time 15 https://registry-1.docker.io/v2/ >/dev/null 2>&1 \
     || curl -sS -o /dev/null -w '%{http_code}' --max-time 15 https://registry-1.docker.io/v2/ 2>/dev/null | grep -q '^[24]'; then
    record pass "reach docker hub" "registry-1.docker.io answered"
  else
    record warn "reach docker hub" "no answer from registry-1.docker.io; a proxy or firewall may be in the way"
  fi
  if curl -sS -o /dev/null -w '%{http_code}' --max-time 15 https://huggingface.co/api/models/Qwen/Qwen2.5-0.5B-Instruct 2>/dev/null | grep -q '^200'; then
    record pass "reach hugging face" "the week-2 model is reachable"
  else
    record warn "reach hugging face" "huggingface.co did not answer 200; model downloads will fail on day 1"
  fi
fi

# --------------------------------------------------------------------------- #
# Report
# --------------------------------------------------------------------------- #
if [ "$BLOCKING" -gt 0 ]; then
  RESULT="FAIL"
elif [ "$WARNINGS" -gt 0 ]; then
  RESULT="PASS WITH WARNINGS"
else
  RESULT="PASS"
fi

{
  printf '{\n'
  printf '  "tool": "aidc-verify-env",\n'
  printf '  "version": "1.0",\n'
  printf '  "generated_utc": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "student": "%s",\n' "$(json_escape "${USER:-${LOGNAME:-unknown}}")"
  printf '  "platform": "%s",\n' "$(json_escape "$PLATFORM $ARCH")"
  printf '  "result": "%s",\n' "$RESULT"
  printf '  "blocking": %d,\n' "$BLOCKING"
  printf '  "warnings": %d,\n' "$WARNINGS"
  printf '  "checks": [\n'
  printf '%s' "$ROWS" | sed '$ s/,$//'
  printf '  ]\n'
  printf '}\n'
} > "$REPORT"

printf '\n%sReport:%s %s\n' "$B" "$N" "$REPORT"

if [ "$BLOCKING" -gt 0 ]; then
  printf '\n%s%d blocking problem(s).%s Each one breaks something in the labs. Fix them, or\n' "$R" "$BLOCKING" "$N"
  printf 'submit this report anyway and say what you tried. A machine flagged now gets\n'
  printf 'fixed; one discovered mid-lab does not.\n'
  printf '\nVERIFY-ENV: FAIL (%d blocking)\n' "$BLOCKING"
  exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
  printf '\n%d warning(s). None of these stop a lab, and all of them are worth clearing.\n' "$WARNINGS"
  printf '\nVERIFY-ENV: PASS WITH WARNINGS\n'
  exit 0
fi

printf '\nVERIFY-ENV: PASS\n'
exit 0
