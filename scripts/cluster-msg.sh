#!/bin/bash
# cluster-msg.sh — real-time inter-node messaging via Nomad variables
#
# Usage:
#   cluster-msg.sh send <to> <subject> <body>     — send a message
#   cluster-msg.sh check [node]                    — check inbox (default: this node)
#   cluster-msg.sh read <msg-id>                   — read a specific message
#   cluster-msg.sh reply <msg-id> <body>           — reply to a message
#   cluster-msg.sh broadcast <subject> <body>      — send to all nodes
#   cluster-msg.sh list                            — list all messages
#
# Messages are stored as Nomad variables at monad/messages/<id>.
# Each node checks its inbox by listing variables where "to" matches.
set -uo pipefail

NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"
export NOMAD_ADDR
MY_NODE="${HOSTNAME:-$(hostname)}"
CMD="${1:-help}"
shift 2>/dev/null || true

msg_id() {
  echo "msg-$(date +%s)-$RANDOM"
}

case "$CMD" in
  send)
    TO="${1:?Usage: cluster-msg.sh send <to> <subject> <body>}"
    SUBJECT="${2:?}"
    BODY="${3:?}"
    ID=$(msg_id)
    nomad var put -force "monad/messages/$ID" \
      id="$ID" \
      from="$MY_NODE" \
      to="$TO" \
      subject="$SUBJECT" \
      body="$BODY" \
      timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      read="false" 2>/dev/null
    echo "[msg] sent $ID → $TO: $SUBJECT"
    ;;

  check)
    TARGET="${1:-$MY_NODE}"
    echo "[msg] inbox for $TARGET:"
    nomad var list -prefix "monad/messages/" -json 2>/dev/null | python3 -c "
import sys, json
try:
    variables = json.load(sys.stdin)
    for v in variables:
        path = v.get('Path', '')
        # Need to fetch each variable to check 'to' field
        print(path)
except:
    pass
" 2>/dev/null | while read -r path; do
      DATA=$(nomad var get -json "$path" 2>/dev/null || continue)
      TO=$(echo "$DATA" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Items',{}).get('to',''))" 2>/dev/null)
      if [ "$TO" = "$TARGET" ] || [ "$TO" = "all" ]; then
        echo "$DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin).get('Items', {})
read_flag = '  ' if d.get('read','false') == 'true' else '* '
print(f\"{read_flag}{d.get('id','?'):25s} from={d.get('from','?'):15s} {d.get('subject','(no subject)')}\")
" 2>/dev/null
      fi
    done
    ;;

  read)
    MSG_ID="${1:?Usage: cluster-msg.sh read <msg-id>}"
    DATA=$(nomad var get -json "monad/messages/$MSG_ID" 2>/dev/null)
    echo "$DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin).get('Items', {})
print(f\"From: {d.get('from','?')}\")
print(f\"To: {d.get('to','?')}\")
print(f\"Time: {d.get('timestamp','?')}\")
print(f\"Subject: {d.get('subject','?')}\")
print()
print(d.get('body','(empty)'))
" 2>/dev/null
    # Mark as read
    nomad var put -force "monad/messages/$MSG_ID" \
      $(echo "$DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin).get('Items', {})
d['read'] = 'true'
for k,v in d.items():
    print(f'{k}=\"{v}\"', end=' ')
" 2>/dev/null) 2>/dev/null || true
    ;;

  reply)
    MSG_ID="${1:?Usage: cluster-msg.sh reply <msg-id> <body>}"
    BODY="${2:?}"
    ORIG=$(nomad var get -json "monad/messages/$MSG_ID" 2>/dev/null)
    ORIG_FROM=$(echo "$ORIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Items',{}).get('from',''))" 2>/dev/null)
    ORIG_SUBJ=$(echo "$ORIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Items',{}).get('subject',''))" 2>/dev/null)
    ID=$(msg_id)
    nomad var put -force "monad/messages/$ID" \
      id="$ID" \
      from="$MY_NODE" \
      to="$ORIG_FROM" \
      subject="Re: $ORIG_SUBJ" \
      body="$BODY" \
      in_reply_to="$MSG_ID" \
      timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      read="false" 2>/dev/null
    echo "[msg] replied $ID → $ORIG_FROM: Re: $ORIG_SUBJ"
    ;;

  broadcast)
    SUBJECT="${1:?Usage: cluster-msg.sh broadcast <subject> <body>}"
    BODY="${2:?}"
    ID=$(msg_id)
    nomad var put -force "monad/messages/$ID" \
      id="$ID" \
      from="$MY_NODE" \
      to="all" \
      subject="$SUBJECT" \
      body="$BODY" \
      timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      read="false" 2>/dev/null
    echo "[msg] broadcast $ID: $SUBJECT"
    ;;

  list)
    echo "[msg] all messages:"
    nomad var list -prefix "monad/messages/" -json 2>/dev/null | python3 -c "
import sys, json
try:
    variables = json.load(sys.stdin)
    for v in variables:
        print(v.get('Path', ''))
except:
    pass
" 2>/dev/null | while read -r path; do
      DATA=$(nomad var get -json "$path" 2>/dev/null || continue)
      echo "$DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin).get('Items', {})
print(f\"{d.get('id','?'):25s} {d.get('from','?'):12s} → {d.get('to','?'):12s} {d.get('subject','')}\")
" 2>/dev/null
    done
    ;;

  *)
    echo "Usage: cluster-msg.sh <send|check|read|reply|broadcast|list>"
    echo ""
    echo "Commands:"
    echo "  send <to> <subject> <body>     Send a message to a node"
    echo "  check [node]                   Check inbox (default: this node)"
    echo "  read <msg-id>                  Read a specific message"
    echo "  reply <msg-id> <body>          Reply to a message"
    echo "  broadcast <subject> <body>     Send to all nodes"
    echo "  list                           List all messages"
    ;;
esac
