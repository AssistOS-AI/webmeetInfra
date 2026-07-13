#!/usr/bin/env bash
set -euo pipefail

umask 077

workspace_root="${PLOINKY_WORKSPACE_ROOT:?PLOINKY_WORKSPACE_ROOT is required}"
profile="${PLOINKY_PROFILE:-default}"
tls_parent_dir="${workspace_root}/.ploinky/data/webmeetTls"
tls_host_dir="${tls_parent_dir}/turn"
tls_container_prefix="/etc/turnserver/tls"
secret_parent_dir="${workspace_root}/.ploinky/data/webmeetSecrets"
secret_host_dir="${secret_parent_dir}/turn"
secret_host_file="${secret_host_dir}/auth-secret"

log() {
    printf '[turnServerAgent] %s\n' "$1"
}

fail() {
    printf '[turnServerAgent] ERROR: %s\n' "$1" >&2
    exit 1
}

ensure_confined_directory() {
    local root="$1" target="$2" label="$3" relative current part old_ifs root_real target_real
    case "$target" in
        "$root"/*)
            relative="${target#"$root"/}"
            ;;
        *)
            fail "$label must remain below PLOINKY_WORKSPACE_ROOT."
            ;;
    esac
    current="$root"
    if [ -L "$current" ]; then
        fail "$label cannot use a symlinked workspace root."
    fi
    old_ifs="$IFS"
    IFS='/'
    # shellcheck disable=SC2086
    set -- $relative
    IFS="$old_ifs"
    for part in "$@"; do
        current="${current}/${part}"
        if [ -L "$current" ]; then
            fail "$label cannot contain symlinked path components ('$current')."
        fi
    done
    mkdir -p "$target"
    root_real="$(cd "$root" && pwd -P)" || fail "could not resolve PLOINKY_WORKSPACE_ROOT."
    target_real="$(cd "$target" && pwd -P)" || fail "could not resolve $label."
    case "$target_real" in
        "$root_real"/*)
            ;;
        *)
            fail "$label resolved outside PLOINKY_WORKSPACE_ROOT."
            ;;
    esac
}

assert_confined_regular_file() {
    local root="$1" file="$2" label="$3" relative current part old_ifs root_real parent_real
    case "$file" in
        "$root"/*)
            relative="${file#"$root"/}"
            ;;
        *)
            fail "$label must remain below the TURN TLS directory."
            ;;
    esac
    current="$root"
    old_ifs="$IFS"
    IFS='/'
    # shellcheck disable=SC2086
    set -- $relative
    IFS="$old_ifs"
    for part in "$@"; do
        current="${current}/${part}"
        if [ -L "$current" ]; then
            fail "$label cannot contain symlinked path components ('$current')."
        fi
    done
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        fail "$label must be a readable regular file at '$file'."
    fi
    root_real="$(cd "$root" && pwd -P)" || fail "could not resolve the TURN TLS directory."
    parent_real="$(cd "$(dirname "$file")" && pwd -P)" || fail "could not resolve the parent of $label."
    case "${parent_real}/$(basename "$file")" in
        "$root_real"/*)
            ;;
        *)
            fail "$label resolved outside the TURN TLS directory."
            ;;
    esac
}

ensure_confined_directory "$workspace_root" "$tls_host_dir" "TURN TLS directory"
ensure_confined_directory "$workspace_root" "$secret_host_dir" "TURN secret directory"

is_valid_ipv4_strict() {
    local ip="$1" old_ifs octet
    old_ifs="$IFS"
    IFS='.'
    # shellcheck disable=SC2086
    set -- $ip
    IFS="$old_ifs"
    if [ "$#" -ne 4 ]; then
        return 1
    fi
    for octet in "$1" "$2" "$3" "$4"; do
        case "$octet" in
            ''|*[!0-9]*)
                return 1
                ;;
            0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9])
                ;;
            *)
                return 1
                ;;
        esac
        if [ "$octet" -gt 255 ]; then
            return 1
        fi
    done
    return 0
}

is_valid_unicast_ipv4() {
    local ip="$1" first second old_ifs
    is_valid_ipv4_strict "$ip" || return 1
    old_ifs="$IFS"
    IFS='.'
    # shellcheck disable=SC2086
    set -- $ip
    IFS="$old_ifs"
    first="$1"
    second="$2"
    [ "$first" -ne 0 ] || return 1
    [ "$first" -ne 127 ] || return 1
    [ "$first" -lt 224 ] || return 1
    if [ "$first" -eq 169 ] && [ "$second" -eq 254 ]; then
        return 1
    fi
}

is_valid_dns_hostname() {
    local value="$1"
    [ "${#value}" -le 253 ] || return 1
    printf '%s' "$value" \
        | grep -Eq '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
}

is_valid_public_dns_hostname() {
    local value="$1" lower
    is_valid_dns_hostname "$value" || return 1
    case "$value" in
        *.*)
            ;;
        *)
            return 1
            ;;
    esac
    case "$value" in
        *[!0-9.]* )
            ;;
        *)
            return 1
            ;;
    esac
    lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        localhost|*.localhost|*.local)
            return 1
            ;;
    esac
}

validate_generated_hex_secret() {
    local name="$1" value="$2"
    if [ "${#value}" -ne 64 ] || ! printf '%s' "$value" | grep -Eq '^[0-9a-f]{64}$'; then
        fail "$name must be the 64-character lowercase hexadecimal value generated by Ploinky."
    fi
}

validate_bounded_positive_int() {
    local name="$1" value="$2" maximum="$3"
    case "$value" in
        ''|*[!0-9]*)
            fail "$name must be a positive integer (got '$value')."
            ;;
    esac
    if [ "${#value}" -gt "${#maximum}" ]; then
        fail "$name must not exceed $maximum (got '$value')."
    fi
    if [ "$value" -le 0 ]; then
        fail "$name must be greater than zero (got '$value')."
    fi
    if [ "$value" -gt "$maximum" ]; then
        fail "$name must not exceed $maximum (got '$value')."
    fi
}

normalize_exact_peer_ipv4() {
    local raw="$1" ip prefix
    case "$raw" in
        *,*)
            fail "WEBMEET_TURN_ALLOWED_PEER_IPS must contain exactly one IPv4 address matching WEBMEET_LIVEKIT_NODE_IP."
            ;;
        */*)
            ip="${raw%%/*}"
            prefix="${raw#*/}"
            if [ "$prefix" != "32" ]; then
                fail "WEBMEET_TURN_ALLOWED_PEER_IPS must be an exact IPv4 host (/32), not '$raw'."
            fi
            ;;
        *)
            ip="$raw"
            ;;
    esac
    if ! is_valid_ipv4_strict "$ip"; then
        fail "WEBMEET_TURN_ALLOWED_PEER_IPS must contain one exact IPv4 address; got '$raw'."
    fi
    printf '%s\n' "$ip"
}

validate_limits() {
    local user_quota total_quota max_bps bps_capacity unauthorized_rps max_allocate_lifetime nonce_lifetime
    user_quota="${WEBMEET_TURN_USER_QUOTA:-4}"
    total_quota="${WEBMEET_TURN_TOTAL_QUOTA:-100}"
    max_bps="${WEBMEET_TURN_MAX_BPS:-2000000}"
    bps_capacity="${WEBMEET_TURN_BPS_CAPACITY:-50000000}"
    unauthorized_rps="${WEBMEET_TURN_UNAUTHORIZED_RPS:-10}"
    max_allocate_lifetime="${WEBMEET_TURN_MAX_ALLOCATION_LIFETIME_SECONDS:-3600}"
    nonce_lifetime="${WEBMEET_TURN_NONCE_LIFETIME_SECONDS:-600}"

    validate_bounded_positive_int WEBMEET_TURN_USER_QUOTA "$user_quota" 10000
    validate_bounded_positive_int WEBMEET_TURN_TOTAL_QUOTA "$total_quota" 100000
    validate_bounded_positive_int WEBMEET_TURN_MAX_BPS "$max_bps" 1000000000
    validate_bounded_positive_int WEBMEET_TURN_BPS_CAPACITY "$bps_capacity" 2000000000
    validate_bounded_positive_int WEBMEET_TURN_UNAUTHORIZED_RPS "$unauthorized_rps" 100000
    validate_bounded_positive_int WEBMEET_TURN_MAX_ALLOCATION_LIFETIME_SECONDS "$max_allocate_lifetime" 86400
    validate_bounded_positive_int WEBMEET_TURN_NONCE_LIFETIME_SECONDS "$nonce_lifetime" 86400

    if [ "$total_quota" -lt "$user_quota" ]; then
        fail "WEBMEET_TURN_TOTAL_QUOTA must be greater than or equal to WEBMEET_TURN_USER_QUOTA."
    fi
    if [ "$bps_capacity" -lt "$max_bps" ]; then
        fail "WEBMEET_TURN_BPS_CAPACITY must be greater than or equal to WEBMEET_TURN_MAX_BPS."
    fi
}

container_path_to_host_path() {
    local name="$1" container_path="$2" relative_path
    case "$container_path" in
        "${tls_container_prefix}"/*)
            relative_path="${container_path#"${tls_container_prefix}"/}"
            ;;
        *)
            fail "$name must live under ${tls_container_prefix}; got '$container_path'."
            ;;
    esac
    case "$relative_path" in
        ''|.|..|../*|*/../*|*/..)
            fail "$name must identify a file below ${tls_container_prefix}; got '$container_path'."
            ;;
    esac
    printf '%s/%s\n' "$tls_host_dir" "$relative_path"
}

validate_limits
validate_generated_hex_secret WEBMEET_TURN_AUTH_SECRET "${WEBMEET_TURN_AUTH_SECRET:?WEBMEET_TURN_AUTH_SECRET is required}"

case "$profile" in
    default|dev)
        peer_host="${WEBMEET_LIVEKIT_PEER_HOST:-livekitserveragent}"
        if ! is_valid_dns_hostname "$peer_host"; then
            fail "WEBMEET_LIVEKIT_PEER_HOST must be a DNS hostname on the shared agent network; got '$peer_host'."
        fi
        ;;
    prod)
        turn_host="${WEBMEET_TURN_HOST:?WEBMEET_TURN_HOST is required in the prod profile}"
        node_ip="${WEBMEET_LIVEKIT_NODE_IP:?WEBMEET_LIVEKIT_NODE_IP is required in the prod profile}"
        allowed_peer_ips="${WEBMEET_TURN_ALLOWED_PEER_IPS:?WEBMEET_TURN_ALLOWED_PEER_IPS is required in the prod profile}"
        external_ip="${WEBMEET_TURN_EXTERNAL_IP:?WEBMEET_TURN_EXTERNAL_IP is required in the prod profile}"
        cert_container_path="${WEBMEET_TURN_TLS_CERT_PATH:-/etc/turnserver/tls/fullchain.pem}"
        key_container_path="${WEBMEET_TURN_TLS_KEY_PATH:-/etc/turnserver/tls/privkey.pem}"

        if ! is_valid_public_dns_hostname "$turn_host"; then
            fail "WEBMEET_TURN_HOST must be a public multi-label DNS hostname (not an IP literal, localhost, or .local name); got '$turn_host'."
        fi
        if ! is_valid_unicast_ipv4 "$node_ip"; then
            fail "WEBMEET_LIVEKIT_NODE_IP must be a unicast IPv4 address (not unspecified, loopback, link-local, or multicast); got '$node_ip'."
        fi
        allowed_peer_ip="$(normalize_exact_peer_ipv4 "$allowed_peer_ips")"
        if [ "$allowed_peer_ip" != "$node_ip" ]; then
            fail "WEBMEET_TURN_ALLOWED_PEER_IPS must equal WEBMEET_LIVEKIT_NODE_IP exactly; got '$allowed_peer_ip' and '$node_ip'."
        fi
        if ! is_valid_unicast_ipv4 "$external_ip"; then
            fail "WEBMEET_TURN_EXTERNAL_IP must be a unicast IPv4 address (not unspecified, loopback, link-local, or multicast); got '$external_ip'."
        fi

        cert_host_path="$(container_path_to_host_path WEBMEET_TURN_TLS_CERT_PATH "$cert_container_path")"
        key_host_path="$(container_path_to_host_path WEBMEET_TURN_TLS_KEY_PATH "$key_container_path")"

        assert_confined_regular_file "$tls_host_dir" "$cert_host_path" "TLS certificate"
        assert_confined_regular_file "$tls_host_dir" "$key_host_path" "TLS private key"
        if ! command -v openssl >/dev/null 2>&1; then
            fail "openssl is required on the host to validate production TURN TLS material."
        fi
        if ! openssl x509 -in "$cert_host_path" -noout -checkend 0 >/dev/null 2>&1; then
            fail "TLS certificate at '$cert_host_path' is invalid or expired."
        fi
        if ! openssl x509 -in "$cert_host_path" -noout -checkhost "$turn_host" >/dev/null 2>&1; then
            fail "TLS certificate at '$cert_host_path' does not cover '$turn_host'."
        fi
        if ! openssl pkey -in "$key_host_path" -noout -check >/dev/null 2>&1; then
            fail "TLS private key at '$key_host_path' is invalid."
        fi
        if ! cert_public_key="$(openssl x509 -in "$cert_host_path" -pubkey -noout \
            | openssl pkey -pubin -outform DER 2>/dev/null \
            | openssl dgst -sha256 2>/dev/null)"; then
            fail "Could not derive the TLS certificate public key."
        fi
        if ! private_public_key="$(openssl pkey -in "$key_host_path" -pubout -outform DER 2>/dev/null \
            | openssl dgst -sha256 2>/dev/null)"; then
            fail "Could not derive the TLS private-key public key."
        fi
        if [ -z "$cert_public_key" ] || [ "$cert_public_key" != "$private_public_key" ]; then
            fail "TLS certificate and private key do not match."
        fi

        # The source is owner-confined on the host, while the mounted leaf is
        # readable by Coturn's fixed nobody:nogroup UID and read-only in the
        # container. Host confidentiality comes from the 0700 parent, not from
        # an unreadable leaf that would also block the container.
        chmod 0700 "$tls_parent_dir"
        chmod 0755 "$tls_host_dir"
        chmod 0444 "$cert_host_path" "$key_host_path"
        log "validated production TURN hostname, media address, public address, and matching TLS material"
        ;;
    *)
        fail "unknown PLOINKY_PROFILE '$profile'."
        ;;
esac

if [ -L "$secret_host_file" ]; then
    fail "TURN secret file cannot be a symlink."
fi
secret_tmp="$(mktemp "${secret_host_dir}/.auth-secret.XXXXXX")" \
    || fail "could not create a private TURN secret file."
cleanup_secret_tmp() {
    rm -f "${secret_tmp:-}"
}
trap cleanup_secret_tmp EXIT
printf '%s\n' "$WEBMEET_TURN_AUTH_SECRET" > "$secret_tmp"
chmod 0444 "$secret_tmp"
mv -f "$secret_tmp" "$secret_host_file"
secret_tmp=""

# The parent remains owner-confined on the host. The mounted leaf is readable
# by Coturn's fixed nobody:nogroup UID and mounted read-only by Ploinky.
chmod 0700 "$secret_parent_dir"
chmod 0755 "$secret_host_dir"
chmod 0444 "$secret_host_file"
unset WEBMEET_TURN_AUTH_SECRET

log "preinstall validation complete for profile '$profile'"
