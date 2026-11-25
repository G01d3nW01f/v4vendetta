#!/usr/bin/env bash

# ==========================================================
# v4vendetta - Scoped Parameter URL Collector
#
# Usage:
#   ./v4vendetta.sh <targetdomain> [deadshot_alive_file]
#
# Examples:
#   ./v4vendetta.sh www.example.com
#   ./v4vendetta.sh www.example.com ./deadshot_results/example.com/latest_alive_list.txt
#
# Optional:
#   ROOT_DOMAIN=example.co.jp ./v4vendetta.sh www.example.co.jp
#
# Scope:
#   Authorized domains only.
# ==========================================================

set -Eeuo pipefail
umask 077

readonly TOOL_NAME="v4vendetta"
readonly BASE_DIR="./v4vendetta_results"

usage() {
    cat <<EOF
Usage:
  $0 <targetdomain> [deadshot_alive_file]

Examples:
  $0 www.example.com
  $0 www.example.com ./alive_list.txt
  ROOT_DOMAIN=example.co.jp $0 www.example.co.jp

Environment:
  ROOT_DOMAIN   Explicit root domain for scope validation.
EOF
}

log() {
    printf '[%s] %s\n' "$TOOL_NAME" "$*"
}

die() {
    printf '[%s] ERROR: %s\n' "$TOOL_NAME" "$*" >&2
    exit 1
}


# ----------------------------------------------------------
# 1. Argument validation
# ----------------------------------------------------------

[[ $# -ge 1 && $# -le 2 ]] || {
    usage >&2
    exit 1
}

input="${1%/}"
alive_input="${2:-}"

# Require a hostname or HTTP(S) URL.
if [[ "$input" =~ ^https?:// ]]; then
    crawl_url="$input"
else
    crawl_url="https://${input}"
fi

# Separate hostname from URL components.
rest="${crawl_url#*://}"
target="${rest%%[/?#]*}"
target="${target,,}"

# Reject unsupported ports and malformed hostnames.
if [[ "$target" == *:* ]]; then
    die "Ports are not supported in the target URL"
fi

if [[ ! "$target" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; then
    die "Invalid target hostname: $target"
fi


# ----------------------------------------------------------
# 2. Determine the root domain
# ----------------------------------------------------------

if [[ -n "${ROOT_DOMAIN:-}" ]]; then
    root_domain="${ROOT_DOMAIN,,}"

    [[ "$root_domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] ||
        die "Invalid ROOT_DOMAIN: $root_domain"

    # Require an exact hostname match or a subdomain boundary.
    if [[ "$target" != "$root_domain" &&
          "$target" != *".$root_domain" ]]; then
        die "Target '$target' is outside root domain '$root_domain'"
    fi
else
    # Do not guess the registrable domain from the last two labels.
    # Use the exact target hostname as the default scope.
    root_domain="$target"
fi

log "Target URL:  $crawl_url"
log "Target host: $target"
log "Scope root:  $root_domain"


# ----------------------------------------------------------
# 3. Dependency check
# ----------------------------------------------------------

for cmd in katana awk grep sort date mkdir mktemp; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Required command not found: $cmd"
done

# ----------------------------------------------------------
# 4. Input validation
# ----------------------------------------------------------

if [[ -n "$alive_input" && ! -f "$alive_input" ]]; then
    die "Alive-host input file not found: $alive_input"
fi


# ----------------------------------------------------------
# 5. Output setup
# ----------------------------------------------------------

today="$(date '+%Y%m%d')"

# Define the output directory before using it.
outdir="${BASE_DIR}/${root_domain}"
mkdir -p "$outdir"

# Output files
output_file="${outdir}/${today}_params.txt"
dirs_output_file="${outdir}/dirs_${today}.txt"

# Temporary workspace
tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$tmpdir"' EXIT

raw_file="${tmpdir}/katana_raw.txt"
seeds_file="${tmpdir}/seeds.txt"
filtered_file="${tmpdir}/filtered.txt"
dirs_filtered_file="${tmpdir}/dirs_filtered.txt"

: > "$raw_file"
: > "$seeds_file"
: > "$filtered_file"
: > "$dirs_filtered_file"


# ----------------------------------------------------------
# 6. Build crawl seeds
# ----------------------------------------------------------
#
# If a DeadShot alive-host list is supplied, use its hosts as
# crawl seeds after enforcing the root-domain boundary.
#
# Otherwise, crawl the target hostname over HTTP and HTTPS.
# ----------------------------------------------------------

if [[ -n "$alive_input" ]]; then
    log "Loading hosts from: $alive_input"

    while IFS= read -r host || [[ -n "$host" ]]; do
        host="${host,,}"
        host="${host%$'\r'}"

        [[ -n "$host" ]] || continue

        # Reject malformed hostnames.
        [[ "$host" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] ||
            continue

        # Exact root-domain boundary check.
        if [[ "$host" == "$root_domain" ||
              "$host" == *".$root_domain" ]]; then
            printf 'https://%s\n' "$host" >> "$seeds_file"
        fi
    done < "$alive_input"

    [[ -s "$seeds_file" ]] ||
        die "No in-scope hosts found in input file"

else
    printf 'https://%s\n' "$target" >> "$seeds_file"
fi

sort -u "$seeds_file" -o "$seeds_file"

log "Crawl seeds: $(wc -l < "$seeds_file" | tr -d ' ')"

# ----------------------------------------------------------
# 7. Crawl with Katana
# ----------------------------------------------------------

log "Starting Katana crawl"

if ! katana \
    -list "$seeds_file" \
    -silent \
    -no-color \
    -jc \
    -fs rdn \
    -d 3 \
    -c 10 \
    -rl 5 \
    -timeout 10 \
    -retry 1 \
    -f qurl \
    -o "$raw_file"; then
    die "Katana failed; output file was not replaced"
fi

# ----------------------------------------------------------
# 8. Filter parameter URLs and directory URLs
# ----------------------------------------------------------

while IFS= read -r url || [[ -n "$url" ]]; do
    url="${url%$'\r'}"

    [[ -n "$url" ]] || continue

    # Require an HTTP(S) URL.
    [[ "$url" =~ ^https?:// ]] || continue

    # Extract authority (hostname and optional port).
    authority="${url#*://}"
    authority="${authority%%/*}"
    authority="${authority%%\?*}"
    authority="${authority%%\#*}"

    # Reject userinfo and ports.
    [[ "$authority" != *@* ]] || continue
    [[ "$authority" != *:* ]] || continue

    host="${authority,,}"

    # Reject malformed hostnames.
    [[ "$host" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] ||
        continue

    # Enforce the exact root-domain boundary.
    if [[ "$host" != "$root_domain" &&
          "$host" != *".$root_domain" ]]; then
        continue
    fi

    # Separate path, query and fragment.
    remainder="${url#*://}"
    remainder="${remainder#*/}"

    # URLs without a path have no directory to collect.
    [[ "$url" == */* ]] || continue

    path="/${remainder%%\?*}"
    path="${path%%\#*}"

    # Collect parameter URLs independently.
    if [[ "$url" =~ \?[^#]+ ]]; then
        printf '%s\n' "$url" >> "$filtered_file"
    fi

    # Collect directory URLs independently.
    # A directory URL has a path ending in '/'.
    if [[ "$path" == */ ]]; then
        printf '%s\n' "$url" >> "$dirs_filtered_file"
    fi

done < "$raw_file"

# ----------------------------------------------------------
# 9. Deduplicate and save
# ----------------------------------------------------------

sort -u "$filtered_file" > "${tmpdir}/final_params.txt"
sort -u "$dirs_filtered_file" > "${tmpdir}/final_dirs.txt"

# Replace outputs only after the crawl and filtering succeed.
mv "${tmpdir}/final_params.txt" "$output_file"
mv "${tmpdir}/final_dirs.txt" "$dirs_output_file"


# ----------------------------------------------------------
# 10. Summary
# ----------------------------------------------------------

raw_count="$(wc -l < "$raw_file" | tr -d ' ')"
param_count="$(wc -l < "$output_file" | tr -d ' ')"
dirs_count="$(wc -l < "$dirs_output_file" | tr -d ' ')"

echo
log "Crawl completed"
echo "------------------------------------------"
echo "Target        : $target"
echo "Scope root    : $root_domain"
echo "Raw URLs      : $raw_count"
echo "Parameter URLs: $param_count"
echo "Directory URLs: $dirs_count"
echo "Params output : $output_file"
echo "Dirs output   : $dirs_output_file"
echo "------------------------------------------"
