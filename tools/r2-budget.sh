#!/usr/bin/env bash
# R2 budget watchdog: R2 has no spending cap, so this is ours. Estimates the
# month's R2 bill from Cloudflare's analytics (all buckets), alerts via ntfy
# from ALERT_EUR, and from OFFLINE_EUR takes the public mesh-agents cache
# offline (disables its custom domain). The cache is the only bucket strangers
# can read from; with it offline, users just build locally.
#
# Bring it back after checking the cause: `r2-budget.sh --online`, or the
# r2-budget workflow run by hand with "online" ticked.
#
# Env: CLOUDFLARE_ACCOUNT_ID, R2_BUDGET_TOKEN (Account Analytics Read +
# Workers R2 Storage Write), NTFY_ALERT_TOPIC (optional), DRY_RUN=1 to only
# report.
set -euo pipefail

ALERT_EUR=${ALERT_EUR:-5}
OFFLINE_EUR=${OFFLINE_EUR:-15}
bucket=mesh-agents-cache
domain=mesh-agents-cache.kleinbem.dev

# R2 list prices in USD (https://developers.cloudflare.com/r2/pricing/);
# counted 1:1 in euro, which errs on the safe side.
free_gb=10 free_a=1000000 free_b=10000000
usd_gb=0.015 usd_a_per_m=4.50 usd_b_per_m=0.36

api=https://api.cloudflare.com/client/v4
auth=(-H "Authorization: Bearer $R2_BUDGET_TOKEN" -H "Content-Type: application/json")
domain_api="$api/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/$bucket/domains/custom"

if [ "${1:-}" = --online ]; then
  curl -fsS -X PUT "${auth[@]}" "$domain_api/$domain" --data '{"enabled": true}' | jq -e .success >/dev/null
  echo "$domain is online again"
  exit 0
fi
start=$(date -u +%Y-%m-01)
today=$(date -u +%Y-%m-%d)

# shellcheck disable=SC2016 # GraphQL variables, not shell
query='query($acct: string!, $start: Date!, $end: Date!) {
  viewer { accounts(filter: {accountTag: $acct}) {
    ops: r2OperationsAdaptiveGroups(limit: 10000, filter: {date_geq: $start, date_leq: $end}) {
      sum { requests }
      dimensions { actionType }
    }
    storage: r2StorageAdaptiveGroups(limit: 10000, filter: {date_geq: $start, date_leq: $end}) {
      max { payloadSize metadataSize }
      dimensions { bucketName date }
    }
  } }
}'

usage=$(jq -n --arg q "$query" --arg acct "$CLOUDFLARE_ACCOUNT_ID" --arg s "$start" --arg e "$today" \
  '{query: $q, variables: {acct: $acct, start: $s, end: $e}}' |
  curl -fsS "${auth[@]}" "$api/graphql" --data @-)
if [ "$(jq '.errors | length' <<<"$usage")" != "0" ]; then
  jq -c .errors <<<"$usage" >&2
  exit 1
fi

# Class B is reads and heads; everything else (writes, lists, multipart,
# config) is billed as Class A, which also counts anything unknown here on the
# expensive side.
read -r ops_a ops_b gb < <(jq -r '
  .data.viewer.accounts[0] as $a
  | ($a.ops | map(select(.dimensions.actionType | test("^(Get|Head)Object$|^HeadBucket$|^(Get|List)BucketCors$|^GetBucketLocation$|^GetBucketEncryption$|^ListMultipartUploads$|^ListParts$")))
      | map(.sum.requests) | add // 0) as $b
  | ($a.ops | map(.sum.requests) | add // 0) as $all
  | ($a.storage | group_by(.dimensions.bucketName)
      | map(max_by(.dimensions.date) | .max.payloadSize + .max.metadataSize) | add // 0) as $bytes
  | "\($all - $b) \($b) \($bytes / 1e9)"' <<<"$usage")

eur=$(awk -v a="$ops_a" -v b="$ops_b" -v gb="$gb" \
  -v fa="$free_a" -v fb="$free_b" -v fgb="$free_gb" \
  -v pa="$usd_a_per_m" -v pb="$usd_b_per_m" -v pgb="$usd_gb" 'BEGIN {
    c = (a > fa ? (a - fa) / 1e6 * pa : 0) + (b > fb ? (b - fb) / 1e6 * pb : 0) + (gb > fgb ? (gb - fgb) * pgb : 0)
    printf "%.2f", c }')
summary="R2 this month: ${ops_a} Class A, ${ops_b} Class B, $(printf '%.2f' "$gb") GB stored → ≈ €${eur}"
echo "$summary"

over() { awk -v x="$eur" -v t="$1" 'BEGIN { exit !(x >= t) }'; }

notify() {
  [ -n "${NTFY_ALERT_TOPIC:-}" ] || return 0
  curl -fsS --max-time 15 -H "Title: $1" -H "Tags: money_with_wings" -H "Priority: high" \
    -d "$2" "https://ntfy.kleinbem.dev/$NTFY_ALERT_TOPIC" >/dev/null || true
}

if over "$OFFLINE_EUR"; then
  enabled=$(curl -fsS "${auth[@]}" "$domain_api" |
    jq -r --arg d "$domain" '.result.domains[] | select(.domain == $d) | .enabled')
  if [ "$enabled" = "true" ]; then
    if [ "${DRY_RUN:-}" = 1 ]; then
      echo "DRY_RUN: would take $domain offline"
    else
      curl -fsS -X PUT "${auth[@]}" "$domain_api/$domain" --data '{"enabled": false}' |
        jq -e .success >/dev/null
      notify "R2 over €${OFFLINE_EUR}: mesh-agents cache OFFLINE" \
        "$summary. $domain is disabled; users build locally. Find the cause, then run the r2-budget workflow with online ticked."
      echo "took $domain offline"
    fi
  fi
elif over "$ALERT_EUR"; then
  # Once a day is enough for a warning; the offline step above always reports.
  if [ "$(date -u +%H)" -lt 6 ] || [ -n "${FORCE_ALERT:-}" ]; then
    notify "R2 over €${ALERT_EUR} this month" "$summary. The cache goes offline at €${OFFLINE_EUR}."
  fi
fi

