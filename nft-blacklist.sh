#!/usr/bin/env bash
#
# usage nft-blacklist.sh <configuration file>
# eg: nft-blacklist.sh /etc/nft-blacklist/nft-blacklist.conf
#

# can be executable name or custom path of either `iprange`
# (not IPv6 support: https://github.com/firehol/iprange/issues/14)
# * or `cidr-merger` (https://github.com/zhanhb/cidr-merger)
# * or `aggregate-prefixes` (Python)
DEFAULT_CIDR_MERGER=cidr-merger
NFT=nft  # can be "sudo /sbin/nft" or whatever to apply the ruleset
SET_NAME_PREFIX=blacklist
SET_NAME_V4="${SET_NAME_PREFIX}_v4"
SET_NAME_V6="${SET_NAME_PREFIX}_v6"
IPV4_REGEX="(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/[0-9]{2})?"
IPV6_REGEX="(?:(?:[0-9a-f]{1,4}:){7,7}[0-9a-f]{1,4}|\
(?:[0-9a-f]{1,4}:){1,7}:|\
(?:[0-9a-f]{1,4}:){1,6}:[0-9a-f]{1,4}|\
(?:[0-9a-f]{1,4}:){1,5}(?::[0-9a-f]{1,4}){1,2}|\
(?:[0-9a-f]{1,4}:){1,4}(?::[0-9a-f]{1,4}){1,3}|\
(?:[0-9a-f]{1,4}:){1,3}(?::[0-9a-f]{1,4}){1,4}|\
(?:[0-9a-f]{1,4}:){1,2}(?::[0-9a-f]{1,4}){1,5}|\
[0-9a-f]{1,4}:(?:(?::[0-9a-f]{1,4}){1,6})|\
:(?:(?::[0-9a-f]{1,4}){1,7}|:)|\
::(?:[f]{4}(?::0{1,4})?:)?\
(?:(25[0-5]|(?:2[0-4]|1?[0-9])?[0-9])\.){3,3}\
(?:25[0-5]|(?:2[0-4]|1?[0-9])?[0-9])|\
(?:[0-9a-f]{1,4}:){1,4}:\
(?:(?:25[0-5]|(?:2[0-4]|1?[0-9])?[0-9])\.){3,3}\
(?:25[0-5]|(?:2[0-4]|1?[0-9])?[0-9]))\
(?:/[0-9]{1,3})?"

function exists() { command -v "$1" >/dev/null 2>&1 ; }
function count_entries() { wc -l "$1" | cut -d' ' -f1 ; }

if [[ -z "$1" ]]; then
  echo "Error: please specify a configuration file, e.g. $0 /etc/nft-blacklist/nft-blacklist.conf"
  exit 1
fi

# shellcheck source=nft-blacklist.conf
if ! source "$1"; then
  echo "Error: can't load configuration file $1"
  exit 1
fi

if ! type -P curl grep sed sort wc date &>/dev/null; then
  echo >&2 "Error: searching PATH fails to find executables among: curl grep sed sort wc date"
  exit 1
fi

[[ ${VERBOSE:-no} =~ ^1|on|true|yes$ ]] && let VERBOSE=1 || let VERBOSE=0
[[ ${DRY_RUN:-no} =~ ^1|on|true|yes$ ]] && let DRY_RUN=1 || let DRY_RUN=0
[[ ${DO_OPTIMIZE_CIDR:-yes} =~ ^1|on|true|yes$ ]] && let OPTIMIZE_CIDR=1 || let OPTIMIZE_CIDR=0
[[ ${KEEP_TMP_FILES:-no} =~ ^1|on|true|yes$ ]] && let KEEP_TMP_FILES=1 || let KEEP_TMP_FILES=0
CIDR_MERGER="${CIDR_MERGER:-DEFAULT_CIDR_MERGER}"

if exists $CIDR_MERGER && (( $OPTIMIZE_CIDR )); then
  let OPTIMIZE_CIDR=1
elif (( $OPTIMIZE_CIDR )); then
  let OPTIMIZE_CIDR=0
  echo >&2 "Warning: $CIDR_MERGER is not available"
fi

if [[ ! -d $(dirname "$IP_BLACKLIST_FILE") || ! -d $(dirname "$IP6_BLACKLIST_FILE") || ! -d $(dirname "$RULESET_FILE") ]]; then
  echo >&2 "Error: missing directory(s): $(dirname "$IP_BLACKLIST_FILE" "$IP6_BLACKLIST_FILE" "$RULESET_FILE" | sort -u)"
  exit 1
fi

(( $VERBOSE )) && echo -n "Processing ${#BLACKLISTS[@]} sources of blacklist: "

IP_BLACKLIST_TMP_FILE=$(mktemp -t nft-blacklist-ip-XXX)
IP6_BLACKLIST_TMP_FILE=$(mktemp -t nft-blacklist-ip6-XXX)
for url in "${BLACKLISTS[@]}"; do
  IP_TMP_FILE=$(mktemp -t nft-blacklist-source-XXX)
  HTTP_RC=$(curl -L -A "nft-blacklist/1.0 (https://github.com/leshniak/nft-blacklist)" --connect-timeout 10 --max-time 10 -o "$IP_TMP_FILE" -s -w "%{http_code}" "$url")
  # On file:// protocol, curl returns "000" per-file (file:///tmp/[1-3].txt would return "000000000" whether the 3 files exist or not)
  # A sequence of 3 resources would return "200200200"
  if (( HTTP_RC == 200 || HTTP_RC == 302 )) || [[ $HTTP_RC =~ ^(000|200){1,}$ ]]; then
    command grep -Po "^$IPV4_REGEX" "$IP_TMP_FILE" | sed -r 's/^0*([0-9]+)\.0*([0-9]+)\.0*([0-9]+)\.0*([0-9]+)$/\1.\2.\3.\4/' >> "$IP_BLACKLIST_TMP_FILE"
    command grep -Pio "^$IPV6_REGEX" "$IP_TMP_FILE" >> "$IP6_BLACKLIST_TMP_FILE"
    (( $VERBOSE )) && echo -n "."
  elif (( HTTP_RC == 503 )); then
    echo -e "\\nUnavailable (${HTTP_RC}): $url"
  else
    echo >&2 -e "\\nWarning: curl returned HTTP response code $HTTP_RC for URL $url"
  fi
  (( $KEEP_TMP_FILES )) || rm -f "$IP_TMP_FILE"
done

(( $VERBOSE )) && echo -e "\\n"

# sort -nu does not work as expected
sed -r -e '/^(0\.0\.0\.0|10\.|127\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.|192\.168\.|22[4-9]\.|23[0-9]\.)/d' "$IP_BLACKLIST_TMP_FILE" | sort -n | sort -mu >| "$IP_BLACKLIST_FILE"
sed -r -e '/^([0:]+\/0|fe80:)/Id' "$IP6_BLACKLIST_TMP_FILE" | sort -d | sort -mu >| "$IP6_BLACKLIST_FILE"
if (( $OPTIMIZE_CIDR )); then
  (( $VERBOSE )) && echo -e "Optimizing entries...\\nFound: $(count_entries "$IP_BLACKLIST_FILE") IPv4, $(count_entries "$IP6_BLACKLIST_FILE") IPv6"
  if [[ $CIDR_MERGER =~ merger ]]; then
      $CIDR_MERGER -o "$IP_BLACKLIST_TMP_FILE" -o "$IP6_BLACKLIST_TMP_FILE" "$IP_BLACKLIST_FILE" "$IP6_BLACKLIST_FILE"
  elif [[ $CIDR_MERGER =~ iprange ]]; then
      $CIDR_MERGER --optimize "$IP_BLACKLIST_FILE" > "$IP_BLACKLIST_TMP_FILE"
      $CIDR_MERGER --optimize "$IP6_BLACKLIST_FILE" > "$IP6_BLACKLIST_TMP_FILE"
  elif [[ $CIDR_MERGER =~ aggregate-prefixes ]]; then
      $CIDR_MERGER -s "$IP_BLACKLIST_FILE" > "$IP_BLACKLIST_TMP_FILE"
      $CIDR_MERGER -s "$IP6_BLACKLIST_FILE" > "$IP6_BLACKLIST_TMP_FILE"
  fi
  (( $VERBOSE )) && echo -e "Saved: $(count_entries "$IP_BLACKLIST_TMP_FILE") IPv4, $(count_entries "$IP6_BLACKLIST_TMP_FILE") IPv6\\n"
  cp "$IP_BLACKLIST_TMP_FILE" "$IP_BLACKLIST_FILE"
  cp "$IP6_BLACKLIST_TMP_FILE" "$IP6_BLACKLIST_FILE"
fi

(( $KEEP_TMP_FILES )) || rm -f "$IP_BLACKLIST_TMP_FILE" "$IP6_BLACKLIST_TMP_FILE"

cat >| "$RULESET_FILE" <<EOF
#
# Created by nft-blacklist (modified) at $(date -uIseconds)
# Loading IP blacklist into existing table 'vyos_filter' and set 'N_blackhole'
#

flush set ip vyos_filter N_blackhole

EOF

ip_lines=""

# add IPv4 addresses
if [[ -s "$IP_BLACKLIST_FILE" ]]; then
    ip_lines=$(sed -rn '/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?)/{ s//  \1,/p }' "$IP_BLACKLIST_FILE")
    #echo "DEBUG: ip_lines extracted:" >&2
    #echo "$ip_lines" >&2
fi

if [[ -n "$ip_lines" ]]; then
    echo "add element ip vyos_filter N_blackhole {" >> "$RULESET_FILE"
    [[ -n "$ip_lines" ]] && echo "$ip_lines" >> "$RULESET_FILE"
    echo "}" >> "$RULESET_FILE"
else
    echo "DEBUG: No IPs extracted, set will be flushed empty" >&2
fi
#
# ToDo: add ipv6 support
#
if (( ! $DRY_RUN )); then
  $NFT -f "$RULESET_FILE" || { echo >&2 "Failed to apply the ruleset"; exit 1; }
fi

(( $VERBOSE )) && echo "Done!"

exit 0
