#!/usr/bin/env bash
set -euo pipefail
set +x

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (install it with: brew install jq)" >&2
  exit 1
fi

echo "DevBar Vercel API smoke test"
echo "The token is used only for this request and is not saved or printed."
read -r -s -p "Vercel access token: " VERCEL_SMOKE_TOKEN
echo
read -r -p "Team ID (optional, press Return to skip): " VERCEL_SMOKE_TEAM_ID

if [[ -z "$VERCEL_SMOKE_TOKEN" ]]; then
  echo "error: an access token is required" >&2
  exit 1
fi

RESPONSE_FILE="$(mktemp -t devbar-vercel-response)"
trap 'rm -f "$RESPONSE_FILE"; unset VERCEL_SMOKE_TOKEN VERCEL_SMOKE_TEAM_ID' EXIT

CURL_ARGS=(
  --silent
  --show-error
  --output "$RESPONSE_FILE"
  --write-out "%{http_code}"
  --get
  --header "Accept: application/json"
  --data-urlencode "limit=5"
)

if [[ -n "$VERCEL_SMOKE_TEAM_ID" ]]; then
  CURL_ARGS+=(--data-urlencode "teamId=$VERCEL_SMOKE_TEAM_ID")
fi

HTTP_STATUS="$(
  printf 'header = "Authorization: Bearer %s"\n' "$VERCEL_SMOKE_TOKEN" |
    curl "${CURL_ARGS[@]}" --config - "https://api.vercel.com/v7/deployments"
)"
unset VERCEL_SMOKE_TOKEN

if [[ "$HTTP_STATUS" != "200" ]]; then
  MESSAGE="$(jq -r '.error.message // .message // "Unknown API error"' "$RESPONSE_FILE" 2>/dev/null || true)"
  echo "error: Vercel returned HTTP $HTTP_STATUS: $MESSAGE" >&2
  case "$HTTP_STATUS" in
    401) echo "Check that the token is correct and has not expired." >&2 ;;
    403) echo "Check the token scope and the optional Team ID." >&2 ;;
    429) echo "Vercel rate-limited the request; wait and try again." >&2 ;;
  esac
  exit 1
fi

if ! jq -e '.deployments | type == "array"' "$RESPONSE_FILE" >/dev/null; then
  echo "error: Vercel returned an unexpected response shape" >&2
  exit 1
fi

DEPLOYMENT_COUNT="$(jq '.deployments | length' "$RESPONSE_FILE")"
echo
echo "Connection successful. Received $DEPLOYMENT_COUNT recent deployment(s)."

if [[ "$DEPLOYMENT_COUNT" -gt 0 ]]; then
  echo
  printf "%-24s %-14s %-12s %s\n" "PROJECT" "STATE" "TARGET" "CREATED"
  jq -r '.deployments[] | [
    (.name // "unknown"),
    (.readyState // .state // "UNKNOWN"),
    (.target // "preview"),
    (((.created // .createdAt) / 1000) | strftime("%Y-%m-%d %H:%M"))
  ] | @tsv' "$RESPONSE_FILE" |
    while IFS=$'\t' read -r PROJECT STATE TARGET CREATED; do
      printf "%-24.24s %-14.14s %-12.12s %s\n" "$PROJECT" "$STATE" "$TARGET" "$CREATED"
    done

  echo
  echo "State totals:"
  jq -r '[.deployments[] | (.readyState // .state // "UNKNOWN")]
    | group_by(.)
    | map("  \(.[0]): \(length)")
    | .[]' "$RESPONSE_FILE"
fi

echo
echo "PASS: authentication, team scope, endpoint, and response shape are valid."
