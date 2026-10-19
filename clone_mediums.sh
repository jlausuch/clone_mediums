#!/usr/bin/env bash
# Print openqa-cli commands that clone openQA mediums (products) to a new version.
#
# Usage: clone_mediums.sh [-H host] OLD_VERSION NEW_VERSION [key=value ...]
#   e.g. clone_mediums.sh 16.1 16.2 distri=opensuse
#        clone_mediums.sh -H https://openqa.opensuse.org 16.1 16.2 distri=opensuse flavor=DVD
#
# All mediums matching version=OLD_VERSION and every key=value filter (matched
# against distri, flavor, arch, ...) are printed as POST commands with
# version=NEW_VERSION. Every occurrence of OLD_VERSION in setting values is
# replaced by NEW_VERSION. Nothing is created; review and run the output.
#
# APIKEY and APISECRET must be set in the environment; the printed commands
# reference them as "$APIKEY"/"$APISECRET" so the secrets are not printed.
set -euo pipefail

host=https://openqa.opensuse.org

usage() {
    sed -n '4,7p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
}

while getopts 'H:h' opt; do
    case $opt in
        H) host=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -ge 2 ]] || usage

old=$1 new=$2
shift 2

for var in APIKEY APISECRET; do
    [[ -n ${!var:-} ]] || { echo "Error: environment variable $var is not set" >&2; exit 1; }
done

# Build a JSON object of filters; the API ignores query parameters, so filter with jq
filters=$(jq -n --arg version "$old" '{version: $version}')
for f in "$@"; do
    [[ $f == *=* ]] || { echo "Invalid filter '$f', expected key=value" >&2; exit 1; }
    filters=$(jq --arg k "${f%%=*}" --arg v "${f#*=}" '. + {($k): $v}' <<< "$filters")
done

curl -sSf "$host/api/v1/products" | jq -r \
    --argjson filters "$filters" --arg old "$old" --arg new "$new" --arg host "$host" '
    def repl: split($old) | join($new);
    .Products[]
    | select(. as $p | $filters | to_entries | all(($p[.key] | tostring) == .value))
    | "openqa-cli api --apikey \"$APIKEY\" --apisecret \"$APISECRET\" " + ([
        "--host", $host, "-X", "POST", "products",
        "distri=\(.distri)", "version=\($new)", "flavor=\(.flavor)", "arch=\(.arch)"
      ]
      + [.settings[] | "settings[\(.key)]=\(.value | repl)"]
      | @sh)'
