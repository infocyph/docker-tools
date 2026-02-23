#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}
warn() { echo "Warning: $*" >&2; }
note() { echo "$*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# Editor UX
# ─────────────────────────────────────────────────────────────────────────────
export VISUAL="${VISUAL:-nano}"
export EDITOR="${EDITOR:-nano}"

# ─────────────────────────────────────────────────────────────────────────────
# Colors (TTY-safe)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
  C_MAGENTA=$'\033[35m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_MAGENTA=''
fi

_ok() { printf "%s%s%s" "$C_GREEN" "$*" "$C_RESET"; }
_bad() { printf "%s%s%s" "$C_RED" "$*" "$C_RESET"; }
_mid() { printf "%s%s%s" "$C_YELLOW""$*" "$C_RESET"; }
_inf() { printf "%s%s%s" "$C_CYAN" "$*" "$C_RESET"; }
_dim() { printf "%s%s%s" "$C_DIM" "$*" "$C_RESET"; }
_bold() { printf "%s%s%s" "$C_BOLD" "$*" "$C_RESET"; }
_tag() { printf "%s[%s]%s" "$C_MAGENTA" "$*" "$C_RESET"; }

# ─────────────────────────────────────────────────────────────────────────────
# Defaults / Mounts (Model B)
# ─────────────────────────────────────────────────────────────────────────────
SOPS_BASE_DIR="${SOPS_BASE_DIR:-/etc/share/sops}"
SOPS_KEYS_DIR="${SOPS_KEYS_DIR:-$SOPS_BASE_DIR/keys}"
SOPS_CFG_DIR="${SOPS_CFG_DIR:-$SOPS_BASE_DIR/config}"
SOPS_GLOBAL_DIR="${SOPS_GLOBAL_DIR:-$SOPS_BASE_DIR/global}"

# Encrypted-env “repo mount” (your mounted repo directory)
SOPS_REPO_DIR="${SOPS_REPO_DIR:-/etc/share/vhosts/sops}"

# Repo-local config
REPO_LOCAL_YAML="./.sops.yaml"

# Preferred global defaults (new layout)
DEFAULT_GLOBAL_KEY="$SOPS_GLOBAL_DIR/age.keys"
DEFAULT_FALLBACK_YAML="$SOPS_GLOBAL_DIR/.sops.yaml"

# Back-compat (old layout)
OLD_GLOBAL_KEY="$SOPS_BASE_DIR/age.keys"
OLD_FALLBACK_YAML="$SOPS_BASE_DIR/.sops.yaml"

safe_mkdir_p() { mkdir -p "$1" 2>/dev/null || true; }

is_root() { [[ "$(id -u 2>/dev/null || echo 1)" == "0" ]]; }

can_write_path() {
  local p="$1"
  if [[ -e "$p" ]]; then [[ -w "$p" ]]; else [[ -w "$(dirname "$p")" ]]; fi
}

trimmed_file_nonempty() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local stripped
  stripped="$(tr -d ' \t\r\n' <"$f" 2>/dev/null || true)"
  [[ -n "$stripped" ]]
}

status_present() { [[ -f "$1" ]] && _ok "present" || _bad "missing"; }
status_key() { trimmed_file_nonempty "$1" && _ok "ready" || _bad "missing/empty"; }

# ─────────────────────────────────────────────────────────────────────────────
# Project auto-detect (from git root basename)
# ─────────────────────────────────────────────────────────────────────────────
find_git_root() {
  local d="$PWD" i=0
  while [[ $i -lt 8 ]]; do
    [[ -d "$d/.git" ]] && {
      echo "$d"
      return 0
    }
    [[ "$d" == "/" ]] && break
    d="$(dirname "$d")"
    i=$((i + 1))
  done
  return 1
}

derive_project_from_git() {
  local root
  root="$(find_git_root 2>/dev/null || true)"
  [[ -n "$root" ]] || return 1
  basename "$root"
}

# ─────────────────────────────────────────────────────────────────────────────
# Path helpers
# ─────────────────────────────────────────────────────────────────────────────
resolve_alias_path() {
  local p="${1:-}"
  [[ -z "$p" ]] && echo "" && return 0
  if [[ "$p" == /* || "$p" == ./* || "$p" == ../* ]]; then
    echo "$p"
  else
    echo "$SOPS_REPO_DIR/$p"
  fi
}

abspath() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "$p" 2>/dev/null || true
    return 0
  fi
  if command -v readlink >/dev/null 2>&1; then
    local rp
    rp="$(readlink -f -- "$p" 2>/dev/null || true)"
    [[ -n "$rp" ]] && {
      echo "$rp"
      return 0
    }
  fi
  [[ "$p" == /* ]] && echo "$p" || echo "$PWD/$p"
}

is_under() {
  local base="$1" target="$2"
  base="$(abspath "$base")"
  target="$(abspath "$target")"
  [[ "$target" == "$base" || "$target" == "$base/"* ]]
}

ensure_safe_path_or_die() {
  local path="$1" kind="$2"
  [[ "${SENV_UNSAFE:-0}" == "1" ]] && return 0

  local okp=0
  is_under "$PWD" "$path" && okp=1
  is_under "$SOPS_REPO_DIR" "$path" && okp=1
  is_under "$SOPS_BASE_DIR" "$path" && okp=1

  [[ "$okp" == "1" ]] && return 0

  die "$kind path is outside safe roots: $path
Safe roots:
  - $PWD
  - $SOPS_REPO_DIR
  - $SOPS_BASE_DIR
Use --unsafe to override."
}

default_out_for_dec() {
  local in="$1" base
  base="$(basename "$in")"
  if [[ "$base" == ".env.enc" || "$base" == "env.enc" || "$base" == *.env.enc ]]; then
    echo "./.env"
  else
    echo "./${base}.dec"
  fi
}

default_out_for_enc() {
  local in="$1" base
  base="$(basename "$in")"
  if [[ "$base" == ".env" || "$base" == "env" ]]; then
    echo "./.env.enc"
  else
    echo "./${base}.enc"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# YAML template helpers
# ─────────────────────────────────────────────────────────────────────────────
write_yaml_template() {
  local out="$1" pub="${2:-AGE_PUBLIC_KEY_HERE}"
  cat >"$out" <<YAML
creation_rules:
  - path_regex: \\.env(\\..+)?\\.enc\$
    age:
      - "$pub"
YAML
}

update_yaml_placeholder_if_writable() {
  local yaml="$1" pub="$2"
  [[ -f "$yaml" && -w "$yaml" ]] || return 0
  grep -q 'AGE_PUBLIC_KEY_HERE' "$yaml" 2>/dev/null || return 0
  local tmp
  tmp="$(mktemp)"
  sed "s/AGE_PUBLIC_KEY_HERE/${pub//\//\\/}/g" "$yaml" >"$tmp"
  mv -f "$tmp" "$yaml"
}

extract_age_pubkey_from_private() {
  local priv="$1"
  trimmed_file_nonempty "$priv" || return 1
  age-keygen -y "$priv" 2>/dev/null || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Invocation flags (NO word-splitting)
# ─────────────────────────────────────────────────────────────────────────────
SENV_PROJECT="${SENV_PROJECT:-}"
SENV_KEY_FILE="${SENV_KEY_FILE:-}"
SENV_IN=""
SENV_OUT=""
SENV_UNSAFE=0
POS_ARGS=()

parse_flags() {
  POS_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --project=*)
      SENV_PROJECT="${1#*=}"
      shift
      ;;
    --project)
      SENV_PROJECT="${2:-}"
      shift 2
      ;;
    --key=*)
      SENV_KEY_FILE="${1#*=}"
      shift
      ;;
    --key)
      SENV_KEY_FILE="${2:-}"
      shift 2
      ;;
    --in=*)
      SENV_IN="${1#*=}"
      shift
      ;;
    --in)
      SENV_IN="${2:-}"
      shift 2
      ;;
    --out=*)
      SENV_OUT="${1#*=}"
      shift
      ;;
    --out)
      SENV_OUT="${2:-}"
      shift 2
      ;;
    --unsafe)
      SENV_UNSAFE=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      POS_ARGS+=("$1")
      shift
      ;;
    esac
  done
  while [[ $# -gt 0 ]]; do
    POS_ARGS+=("$1")
    shift
  done
}

ensure_project_default() {
  if [[ -z "${SENV_PROJECT:-}" ]]; then
    local inferred
    inferred="$(derive_project_from_git 2>/dev/null || true)"
    [[ -n "$inferred" ]] && SENV_PROJECT="$inferred"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Choose key / choose config (with new global/ + back-compat)
# ─────────────────────────────────────────────────────────────────────────────
choose_key_file() {
  if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
    echo "$SOPS_AGE_KEY_FILE"
    return
  fi
  if [[ -n "${SENV_KEY_FILE:-}" ]]; then
    echo "$SENV_KEY_FILE"
    return
  fi
  if [[ -n "${SENV_PROJECT:-}" ]]; then
    echo "$SOPS_KEYS_DIR/${SENV_PROJECT}.age.keys"
    return
  fi

  [[ -f "$DEFAULT_GLOBAL_KEY" ]] && {
    echo "$DEFAULT_GLOBAL_KEY"
    return
  }
  [[ -f "$OLD_GLOBAL_KEY" ]] && {
    echo "$OLD_GLOBAL_KEY"
    return
  }
  echo "$DEFAULT_GLOBAL_KEY"
}

choose_global_fallback_yaml_path() {
  if [[ -n "${SOPS_CONFIG_FILE:-}" ]]; then
    echo "$SOPS_CONFIG_FILE"
    return
  fi

  [[ -f "$DEFAULT_FALLBACK_YAML" ]] && {
    echo "$DEFAULT_FALLBACK_YAML"
    return
  }
  [[ -f "$OLD_FALLBACK_YAML" ]] && {
    echo "$OLD_FALLBACK_YAML"
    return
  }
  echo "$DEFAULT_FALLBACK_YAML"
}

choose_sops_yaml() {
  if [[ -f "$REPO_LOCAL_YAML" ]]; then
    echo "$REPO_LOCAL_YAML"
    return
  fi

  if [[ -n "${SENV_PROJECT:-}" ]]; then
    local py="$SOPS_CFG_DIR/${SENV_PROJECT}.sops.yaml"
    [[ -f "$py" ]] && {
      echo "$py"
      return
    }
  fi

  choose_global_fallback_yaml_path
}

# ─────────────────────────────────────────────────────────────────────────────
# Ensure defaults (init behavior)
# ─────────────────────────────────────────────────────────────────────────────
ensure_global_fallback_yaml() {
  local target
  target="$(choose_global_fallback_yaml_path)"

  if is_under "$SOPS_BASE_DIR" "$target" && ! is_root; then
    return 1
  fi

  safe_mkdir_p "$(dirname "$target")"

  if [[ -e "$target" && ! -f "$target" ]]; then
    warn "Global config exists but is not a regular file: $target"
    return 1
  fi
  [[ -f "$target" ]] && return 0
  can_write_path "$target" || return 1

  local keyf pub
  keyf="$(choose_key_file)"
  pub="AGE_PUBLIC_KEY_HERE"
  if pub_out="$(extract_age_pubkey_from_private "$keyf" 2>/dev/null)"; then
    pub="${pub_out//$'\n'/}"
  fi

  write_yaml_template "$target" "$pub"
  chmod 644 "$target" 2>/dev/null || true
  return 0
}

ensure_project_yaml_optional() {
  [[ -n "${SENV_PROJECT:-}" ]] || return 0
  local py="$SOPS_CFG_DIR/${SENV_PROJECT}.sops.yaml"

  if is_under "$SOPS_BASE_DIR" "$py" && ! is_root; then
    return 1
  fi

  safe_mkdir_p "$SOPS_CFG_DIR"

  if [[ -e "$py" && ! -f "$py" ]]; then
    warn "Project config exists but is not a regular file: $py"
    return 1
  fi
  [[ -f "$py" ]] && return 0
  can_write_path "$py" || return 1

  local keyf pub
  keyf="$(choose_key_file)"
  pub="AGE_PUBLIC_KEY_HERE"
  if pub_out="$(extract_age_pubkey_from_private "$keyf" 2>/dev/null)"; then
    pub="${pub_out//$'\n'/}"
  fi

  write_yaml_template "$py" "$pub"
  chmod 644 "$py" 2>/dev/null || true
  return 0
}

ensure_key_if_missing_or_empty() {
  local keyf
  keyf="$(choose_key_file)"

  if is_under "$SOPS_BASE_DIR" "$keyf" && ! is_root; then
    return 1
  fi

  safe_mkdir_p "$(dirname "$keyf")"

  if trimmed_file_nonempty "$keyf"; then
    return 0
  fi

  can_write_path "$keyf" || return 1

  local tmpkey
  tmpkey="$(mktemp "${keyf}.tmp.XXXXXX")"
  rm -f "$tmpkey" 2>/dev/null || true
  age-keygen -o "$tmpkey"
  chmod 600 "$tmpkey" 2>/dev/null || true
  mv -f "$tmpkey" "$keyf"
  chmod 600 "$keyf" 2>/dev/null || true
  return 0
}

ensure_defaults_global() {
  ensure_project_default

  ensure_global_fallback_yaml || true
  ensure_project_yaml_optional || true
  ensure_key_if_missing_or_empty || true

  local keyf pub gf
  keyf="$(choose_key_file)"
  gf="$(choose_global_fallback_yaml_path)"

  if trimmed_file_nonempty "$keyf"; then
    pub="$(age-keygen -y "$keyf")"
    update_yaml_placeholder_if_writable "$gf" "$pub"
    update_yaml_placeholder_if_writable "$REPO_LOCAL_YAML" "$pub"
    if [[ -n "${SENV_PROJECT:-}" ]]; then
      update_yaml_placeholder_if_writable "$SOPS_CFG_DIR/${SENV_PROJECT}.sops.yaml" "$pub"
    fi
  fi
}

ensure_local_yaml_only() {
  ensure_project_default

  if [[ -e "$REPO_LOCAL_YAML" && ! -f "$REPO_LOCAL_YAML" ]]; then
    die "Local config path exists but is not a regular file: $REPO_LOCAL_YAML"
  fi
  [[ -f "$REPO_LOCAL_YAML" ]] && return 0

  can_write_path "$REPO_LOCAL_YAML" || die "cannot write local ./.sops.yaml (directory not writable)"

  write_yaml_template "$REPO_LOCAL_YAML" "AGE_PUBLIC_KEY_HERE"
  chmod 644 "$REPO_LOCAL_YAML" 2>/dev/null || true
}

need_key() {
  local keyf
  keyf="$(choose_key_file)"
  trimmed_file_nonempty "$keyf" || die "AGE key missing/empty: $keyf
Fix:
  - Mount an existing key there, OR
  - Run: senv keygen --project <id> (requires writable key path), OR
  - Run: senv init --project <id> (if writable)."
}

ensure_config_available_or_fail() {
  local yaml
  yaml="$(choose_sops_yaml)"
  [[ -f "$yaml" ]] && return 0
  die "No SOPS config found for this run.
Selected: $yaml

Fix:
  - Create local config: senv init --local-only
  - Or create global config: senv init (requires writable and root under $SOPS_BASE_DIR)
  - Or provide SOPS_CONFIG_FILE to an existing config."
}

do_keygen() {
  ensure_project_default
  local keyf
  keyf="$(choose_key_file)"

  if is_under "$SOPS_BASE_DIR" "$keyf" && ! is_root; then
    die "Keygen requires root when writing under $SOPS_BASE_DIR (current user is not root)."
  fi

  safe_mkdir_p "$(dirname "$keyf")"

  if trimmed_file_nonempty "$keyf"; then
    warn "Key already exists and is not empty (refusing to overwrite): $keyf"
    warn "If you intended a different key, use: senv keygen --key <path>  OR  --project <id>"
    return 1
  fi

  can_write_path "$keyf" || die "Cannot write key file: $keyf"

  local tmpkey
  tmpkey="$(mktemp "${keyf}.tmp.XXXXXX")"
  rm -f "$tmpkey" 2>/dev/null || true
  age-keygen -o "$tmpkey"
  chmod 600 "$tmpkey" 2>/dev/null || true
  mv -f "$tmpkey" "$keyf"
  chmod 600 "$keyf" 2>/dev/null || true

  printf "%s %s\n" "$(_tag keygen)" "$(_ok "generated")"
  printf "%s %s\n" "$(_inf "Key file   :")" "$keyf"
  printf "%s %s\n" "$(_inf "Public key :")" "$(age-keygen -y "$keyf")"
}

do_config() {
  ensure_defaults_global
  ensure_config_available_or_fail
  local yaml
  yaml="$(choose_sops_yaml)"
  printf "%s %s %s\n" "$(_tag config)" "$(_inf "opening:")" "$yaml"
  "$EDITOR" "$yaml"
}

do_enc() {
  ensure_defaults_global
  ensure_config_available_or_fail
  need_key

  local in_raw="${SENV_IN:-${1:-${POS_ARGS[0]:-.env}}}"
  local out_raw="${SENV_OUT:-${2:-${POS_ARGS[1]:-}}}"

  local in
  in="$(resolve_alias_path "$in_raw")"
  ensure_safe_path_or_die "$in" "Input"
  [[ -f "$in" ]] || die "Missing input: $in (from --in=$in_raw)"

  local out
  if [[ -z "$out_raw" ]]; then
    out="$(default_out_for_enc "$in")"
  else
    out="$(resolve_alias_path "$out_raw")"
  fi
  ensure_safe_path_or_die "$out" "Output"

  local keyf yaml
  keyf="$(choose_key_file)"
  yaml="$(choose_sops_yaml)"

  SOPS_AGE_KEY_FILE="$keyf" sops --config "$yaml" -e "$in" >"$out"
  chmod 600 "$out" 2>/dev/null || true

  printf "%s %s\n" "$(_tag enc)" "$(_ok "ok")"
  printf "%s %s\n" "$(_inf "Input   :")" "$in"
  printf "%s %s\n" "$(_inf "Output  :")" "$out"
}

do_dec() {
  ensure_defaults_global
  ensure_config_available_or_fail
  need_key

  local in_raw="${SENV_IN:-${1:-${POS_ARGS[0]:-.env.enc}}}"
  local out_raw="${SENV_OUT:-${2:-${POS_ARGS[1]:-}}}"

  local in
  in="$(resolve_alias_path "$in_raw")"
  ensure_safe_path_or_die "$in" "Input"
  [[ -f "$in" ]] || die "Missing input: $in (from --in=$in_raw)"

  local out
  if [[ -z "$out_raw" ]]; then
    out="$(default_out_for_dec "$in")"
  else
    out="$(resolve_alias_path "$out_raw")"
  fi
  ensure_safe_path_or_die "$out" "Output"

  local keyf yaml
  keyf="$(choose_key_file)"
  yaml="$(choose_sops_yaml)"

  local tmp
  tmp="$(mktemp "${out}.tmp.XXXXXX")"
  SOPS_AGE_KEY_FILE="$keyf" sops --config "$yaml" -d "$in" >"$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$out"

  printf "%s %s\n" "$(_tag dec)" "$(_ok "ok")"
  printf "%s %s\n" "$(_inf "Input   :")" "$in"
  printf "%s %s\n" "$(_inf "Output  :")" "$out"
}

do_edit() {
  ensure_defaults_global
  ensure_config_available_or_fail
  need_key

  local file_raw="${SENV_IN:-${1:-${POS_ARGS[0]:-.env.enc}}}"
  local file
  file="$(resolve_alias_path "$file_raw")"
  ensure_safe_path_or_die "$file" "Input"
  [[ -f "$file" ]] || die "Missing file: $file (from --in=$file_raw)"

  local keyf yaml
  keyf="$(choose_key_file)"
  yaml="$(choose_sops_yaml)"

  printf "%s %s %s\n" "$(_tag edit)" "$(_inf "editor=$EDITOR")" "$(_mid "(Ctrl+X to exit nano)")"
  SOPS_AGE_KEY_FILE="$keyf" sops --config "$yaml" "$file"
}

do_pull() {
  ensure_project_default
  [[ -n "${SENV_PROJECT:-}" ]] || die "pull requires --project <id> (or run inside a git repo for auto-detect)"
  [[ -z "${SENV_IN:-}" ]] && SENV_IN="${SENV_PROJECT}/.env.enc"
  [[ -z "${SENV_OUT:-}" ]] && SENV_OUT="./.env"
  do_dec
}

do_push() {
  ensure_project_default
  [[ -n "${SENV_PROJECT:-}" ]] || die "push requires --project <id> (or run inside a git repo for auto-detect)"
  [[ -z "${SENV_IN:-}" ]] && SENV_IN="./.env"
  [[ -z "${SENV_OUT:-}" ]] && SENV_OUT="${SENV_PROJECT}/.env.enc"
  do_enc
}

print_info() {
  ensure_project_default
  local keyf yaml gf
  keyf="$(choose_key_file)"
  yaml="$(choose_sops_yaml)"
  gf="$(choose_global_fallback_yaml_path)"

  local proj_cfg=""
  [[ -n "${SENV_PROJECT:-}" ]] && proj_cfg="$SOPS_CFG_DIR/${SENV_PROJECT}.sops.yaml"

  printf "%s %s\n" "$(_tag info)" "$([[ "$SENV_UNSAFE" == "1" ]] && _mid "safe-paths=off" || _ok "safe-paths=on")"
  printf "%s %s\n" "$(_inf "Project      :")" "${SENV_PROJECT:-<none>}"
  printf "%s %s\n" "$(_inf "Secrets repo :")" "$SOPS_REPO_DIR"
  printf "%s %s\n" "$(_inf "Base dir     :")" "$SOPS_BASE_DIR"
  printf "%s %s\n" "$(_inf "Keys dir     :")" "$SOPS_KEYS_DIR"
  printf "%s %s\n" "$(_inf "Config dir   :")" "$SOPS_CFG_DIR"
  printf "%s %s\n" "$(_inf "Global dir   :")" "$SOPS_GLOBAL_DIR"

  printf "%s %s (%s)\n" "$(_inf "Key file     :")" "$keyf" "$(status_key "$keyf")"
  if trimmed_file_nonempty "$keyf"; then
    printf "%s %s\n" "$(_inf "Public key   :")" "$(age-keygen -y "$keyf")"
  fi

  printf "%s %s (%s)\n" "$(_inf "Local config :")" "$REPO_LOCAL_YAML" "$(status_present "$REPO_LOCAL_YAML")"
  if [[ -n "$proj_cfg" ]]; then
    printf "%s %s (%s)\n" "$(_inf "Project config:")" "$proj_cfg" "$(status_present "$proj_cfg")"
  fi
  printf "%s %s (%s)\n" "$(_inf "Global config:")" "$gf" "$(status_present "$gf")"
  printf "%s %s\n" "$(_inf "Using config :")" "$yaml"
}

print_init_summary() {
  local mode="$1"
  ensure_project_default

  local keyf yaml gf
  keyf="$(choose_key_file)"
  yaml="$(choose_sops_yaml)"
  gf="$(choose_global_fallback_yaml_path)"

  local proj_cfg=""
  [[ -n "${SENV_PROJECT:-}" ]] && proj_cfg="$SOPS_CFG_DIR/${SENV_PROJECT}.sops.yaml"

  printf "%s %s\n" "$(_tag init)" "$(_ok "done")"
  printf "%s %s\n" "$(_inf "Mode         :")" "$mode"
  printf "%s %s\n" "$(_inf "Project      :")" "${SENV_PROJECT:-<none>}"
  printf "%s %s\n" "$(_inf "Secrets repo :")" "$SOPS_REPO_DIR"

  printf "%s %s (%s)\n" "$(_inf "Key file     :")" "$keyf" "$(status_key "$keyf")"
  printf "%s %s (%s)\n" "$(_inf "Local config :")" "$REPO_LOCAL_YAML" "$(status_present "$REPO_LOCAL_YAML")"

  if [[ "$mode" != "local-only" ]]; then
    if [[ -n "$proj_cfg" ]]; then
      printf "%s %s (%s)\n" "$(_inf "Project config:")" "$proj_cfg" "$(status_present "$proj_cfg")"
    fi
    printf "%s %s (%s)\n" "$(_inf "Global config:")" "$gf" "$(status_present "$gf")"
  fi

  printf "%s %s\n" "$(_inf "Using config :")" "$yaml"
  if trimmed_file_nonempty "$keyf"; then
    printf "%s %s\n" "$(_inf "Public key   :")" "$(age-keygen -y "$keyf")"
  else
    printf "%s %s\n" "$(_mid "Key status   :")" "$(_bad "missing/empty")"
  fi

  if [[ "$mode" == "local-only" ]]; then
    printf "%s %s\n" "$(_mid "Note:")" "local-only does not create keys/configs under $SOPS_BASE_DIR."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
cmd="${1:-}"
shift || true

case "$cmd" in
init)
  mode="global"
  if [[ "${1:-}" == "--local" ]]; then
    mode="local"
    shift || true
  fi
  if [[ "${1:-}" == "--local-only" ]]; then
    mode="local-only"
    shift || true
  fi

  parse_flags "$@"

  if [[ "$mode" == "local-only" ]]; then
    ensure_local_yaml_only
    print_init_summary "local-only"
    exit 0
  fi

  ensure_defaults_global
  if [[ "$mode" == "local" ]]; then
    [[ -f "$REPO_LOCAL_YAML" ]] || ensure_local_yaml_only
  fi
  print_init_summary "$mode"
  ;;

info)
  parse_flags "$@"
  print_info
  ;;

keygen)
  parse_flags "$@"
  do_keygen
  ;;

config)
  parse_flags "$@"
  do_config
  ;;

enc)
  parse_flags "$@"
  do_enc
  ;;

dec)
  parse_flags "$@"
  do_dec
  ;;

edit)
  parse_flags "$@"
  do_edit
  ;;

pull)
  parse_flags "$@"
  do_pull
  ;;

push)
  parse_flags "$@"
  do_push
  ;;

*)
  cat >&2 <<USAGE
Usage:
  senv init [--project <id>] [--key <path>] [--unsafe]
  senv init --local [--project <id>] [--key <path>] [--unsafe]
  senv init --local-only [--project <id>] [--key <path>] [--unsafe]

  senv info [--project <id>] [--key <path>] [--unsafe]
  senv keygen [--project <id>] [--key <path>] [--unsafe]
  senv config [--project <id>] [--key <path>] [--unsafe]

  senv enc  [--project <id>] [--key <path>] [--in <file>] [--out <file>] [in] [out] [--unsafe]
  senv dec  [--project <id>] [--key <path>] [--in <file>] [--out <file>] [in] [out] [--unsafe]
  senv edit [--project <id>] [--key <path>] [--in <file>] [file] [--unsafe]

  senv push --project <id> [--in <file>] [--out <file>] [--unsafe]
  senv pull --project <id> [--in <file>] [--out <file>] [--unsafe]

Flags:
  --project <id>   Select project key/config under global dirs (Model B)
  --key <path>     Explicit key file path (overrides project/global)
  --in <file>      Input file (alias rules apply)
  --out <file>     Output file (alias rules apply)
  --unsafe         Disable safe-path restrictions

Modes:
  init
    - Ensures missing keys/configs under /etc/share/sops if writable AND running as root.
    - Never overwrites a real (non-empty-after-trim) key.
  init --local
    - Runs normal init AND creates repo-local ./.sops.yaml if missing (only in current repo dir).
  init --local-only
    - Only creates repo-local ./.sops.yaml (no writes under /etc/share/sops).

keys selection order:
  1) Explicit override:
       --key <path> OR SOPS_AGE_KEY_FILE=<path>
  2) Per-project key:
       $SOPS_KEYS_DIR/<project>.age.keys
  3) Global fallback (preferred):
       $SOPS_GLOBAL_DIR/age.keys
  4) Back-compat global key (if present):
       $SOPS_BASE_DIR/age.keys

Config selection order:
  1) Local config (repo):
       ./.sops.yaml
  2) Project config (optional):
       $SOPS_CFG_DIR/<project>.sops.yaml
  3) Global config (preferred):
       $SOPS_GLOBAL_DIR/.sops.yaml
  4) Back-compat global config (if present):
       $SOPS_BASE_DIR/.sops.yaml
  Override global config path with:
       SOPS_CONFIG_FILE=/path/to/.sops.yaml

IO alias rules:
  If --in/--out is:
    - Absolute:           /x/y/file
    - CWD-relative:       ./x/y/file or ../x/y/file
  then it is used as-is.
  Otherwise it is treated as a secrets-repo alias:
    $SOPS_REPO_DIR/<value>

Defaults when --out is omitted:
  enc:
    - if input looks like ".env" / "env"  -> writes ./.env.enc
    - otherwise                           -> writes ./<basename>.enc
  dec:
    - if input looks like ".env.enc"      -> writes ./.env
    - otherwise                           -> writes ./<basename>.dec

push / pull convenience:
  push (encrypt current env to secrets repo):
    - default --in  : ./.env
    - default --out : <project>/.env.enc   (in secrets repo mount)
  pull (decrypt from secrets repo to current repo):
    - default --in  : <project>/.env.enc   (in secrets repo mount)
    - default --out : ./.env

Safety:
  By default, senv restricts input/output paths to stay inside:
    - current working directory
    - $SOPS_REPO_DIR
    - $SOPS_BASE_DIR
  Use --unsafe to bypass.

System create rule:
  senv only creates keys/configs under $SOPS_BASE_DIR when:
    - running as root, AND
    - the target path is writable (not read-only mount).

Environment overrides:
  SOPS_BASE_DIR     (default /etc/share/sops)
  SOPS_KEYS_DIR     (default /etc/share/sops/keys)
  SOPS_CFG_DIR      (default /etc/share/sops/config)
  SOPS_GLOBAL_DIR   (default /etc/share/sops/global)
  SOPS_REPO_DIR     (default /etc/share/vhosts/sops)
  SENV_PROJECT      (auto-detects from git root basename when possible)

Examples:
  # Initialize global defaults (needs root + writable /etc/share/sops):
  senv init

  # Create repo-local config too:
  senv init --local

  # Only create ./ .sops.yaml (no system writes):
  senv init --local-only

  # Generate per-project key:
  senv keygen --project demo

  # Encrypt a local .env -> local .env.enc:
  senv enc

  # Encrypt from secrets repo alias -> current dir output:
  senv enc --in demo/.env --out ./.env.enc

  # Decrypt from secrets repo alias -> current dir:
  senv dec --in demo/.env.enc --out ./.env

  # Quick pull/push:
  senv pull --project demo
  senv push --project demo

Parsing note:
  This script does not use word-splitting for args; SC2206 is resolved properly.
USAGE
  exit 2
  ;;
esac
