#!/bin/sh
set -eu

fail() {
  printf '[health] %s\n' "$1" >&2
  exit 1
}

curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:17000/ready \
  || fail 'private supervisor readiness failed'
[ "$(redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null)" = "PONG" ] \
  || fail 'Redis semantic PING failed'
curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:7880/ \
  || fail 'LiveKit signaling health failed'
node /code/scripts/health/egress-semantic-health.mjs \
  || fail 'Egress semantic health/template probes failed'

for port in 7980 7981; do
  ss -H -lntp 2>/dev/null | awk -v port=":${port}$" '
    $4 ~ port && /users:\(\("egress"/ && ($4 ~ /^127\.0\.0\.1:/ || $4 ~ /^\[::1\]:/) { found=1 }
    END { exit(found ? 0 : 1) }
  ' || fail "Egress TCP $port is not loopback-bound and owned by egress"
  if ss -H -lntp 2>/dev/null | awk -v port=":${port}$" '
    $4 ~ port && !($4 ~ /^127\.0\.0\.1:/ || $4 ~ /^\[::1\]:/) { found=1 }
    END { exit(found ? 0 : 1) }
  '; then
    fail "Egress TCP $port has a non-loopback listener"
  fi
done

ss -H -lunp 2>/dev/null | awk '$4 ~ /:7882$/ && /livekit-server/ { found=1 } END { exit(found ? 0 : 1) }' \
  || fail 'LiveKit does not own 7882/udp'

if ss -H -lnt 2>/dev/null | awk '$4 ~ /:(80|443|3478|5349|7881)$/ { found=1 } END { exit(found ? 0 : 1) }'; then
  fail 'forbidden TCP listener detected'
fi
if ss -H -lun 2>/dev/null | awk '$4 ~ /:(3478|5349|7883|7884|7885|7886|7887|7888|7889|7890|7891|7892)$/ { found=1 } END { exit(found ? 0 : 1) }'; then
  fail 'forbidden UDP listener detected'
fi

printf 'ok\n'
