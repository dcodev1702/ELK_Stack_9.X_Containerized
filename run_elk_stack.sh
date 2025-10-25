#!/bin/bash

# ELK Stack Control Script
# Actions:
#   start   - start stack, wait for ES health (green/yellow), then clean up exited one-shot containers
#   stop    - stop containers and remove volumes
#   destroy - stop containers, remove volumes, remove images, prune dangling resources AND anonymous volumes

set -o errexit
set -o nounset
set -o pipefail

# -------------------------------
# Host IP detection (runs on host)
# -------------------------------
get_host_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    local iface
    iface="$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')"
    if [[ -n "${iface:-}" ]]; then
      ip="$(ip -4 addr show "$iface" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
    fi
  fi
  if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\./){print $i; exit}}')"
  fi
  [[ -z "$ip" ]] && ip="127.0.0.1"
  echo "$ip"
}

HOST_IP="$(get_host_ip)"

# Elasticsearch connection details
ELASTIC_URL="http://${HOST_IP}:9200"
ELASTIC_USER="elastic"
ELASTIC_PASS="elastic_password_123"

print_header() {
  echo "================================"
  echo "$1"
  echo "================================"
}

# Wait for a given container to exit, then remove it
wait_for_container_exit() {
  local TARGET_CONTAINER="$1"

  if docker ps -a --format '{{.Names}}' | grep -q "^${TARGET_CONTAINER}$"; then
    echo ""
    echo "Monitoring container: ${TARGET_CONTAINER}"
    echo "Waiting for it to reach 'Exited' state..."

    while true; do
      local STATUS
      STATUS=$(docker inspect -f '{{.State.Status}}' "$TARGET_CONTAINER" 2>/dev/null || true)
      if [[ "$STATUS" == "exited" ]]; then
        echo "✅ Container '$TARGET_CONTAINER' has exited. Proceeding with removal."
        docker rm "$TARGET_CONTAINER" >/dev/null
        break
      elif [[ -z "$STATUS" ]]; then
        echo "⚠️  Container '$TARGET_CONTAINER' not found. Skipping removal."
        break
      else
        echo "⏳ Current status: $STATUS (checking again in 5s)"
        sleep 5
      fi
    done
  else
    echo ""
    echo "ℹ️  No container named '${TARGET_CONTAINER}' found. Skipping exit check."
  fi
}

# Find exited containers that belong to *this* compose project and remove them
remove_exited_compose_containers() {
  # Requires docker compose v2 and jq (already used elsewhere)
  # Compose-scoped view ensures we only look at containers from the current project.
  # The -s (slurp) flag tells jq to read multiple JSON objects and treat them as an array
  local EXITED_CONTAINERS
  EXITED_CONTAINERS=$(docker compose ps -a --format json | jq -r -s '.[] | select(.State=="exited") | .Name')

  if [[ -z "$EXITED_CONTAINERS" ]]; then
    echo "ℹ️  No exited containers found for this compose project."
    return 0
  fi

  echo "Found exited containers:"
  echo "$EXITED_CONTAINERS" | sed 's/^/  - /'

  # Option A: Remove immediately (they are already exited)
  while IFS= read -r cname; do
    [[ -z "$cname" ]] && continue
    echo "🗑️  Removing exited container: $cname"
    docker rm "$cname" >/dev/null || true
  done <<< "$EXITED_CONTAINERS"

  # If you prefer to *verify* (belt-and-suspenders), you could instead call:
  # while IFS= read -r cname; do
  #   [[ -z "$cname" ]] && continue
  #   wait_for_container_exit "$cname"
  # done <<< "$EXITED_CONTAINERS"
}

wait_for_elasticsearch_health() {
  echo ""
  echo "Waiting for Elasticsearch cluster to reach a healthy state (green/yellow)..."

  local MAX_RETRIES=30
  local RETRY_INTERVAL=10
  local COUNTER=0

  while true; do
    local STATUS
    STATUS=$(curl -s -u "${ELASTIC_USER}:${ELASTIC_PASS}" "${ELASTIC_URL}/_cluster/health" | jq -r '.status' 2>/dev/null || true)

    if [[ "$STATUS" == "green" || "$STATUS" == "yellow" ]]; then
      echo "✅ Elasticsearch cluster is healthy (status: $STATUS)"
      break
    fi

    ((COUNTER++))
    if [[ $COUNTER -ge $MAX_RETRIES ]]; then
      echo "❌ Elasticsearch did not reach a healthy state after $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
      exit 1
    fi

    echo "⏳ Current status: ${STATUS:-unknown} (retry $COUNTER/$MAX_RETRIES) — waiting ${RETRY_INTERVAL}s..."
    sleep "$RETRY_INTERVAL"
  done
}

start_stack() {
  print_header "Starting ELK Stack v9.2.0..."

  docker compose up -d

  echo ""
  echo "Waiting for services to be healthy..."
  sleep 10

  echo ""
  echo "Checking service status:"
  docker compose ps

  echo ""
  print_header "ELK Stack should be starting up!"
  echo "Access points:"
  echo "  - Elasticsearch: ${ELASTIC_URL}"
  echo "  - Kibana:        http://${HOST_IP}:5601"
  echo ""
  echo "Credentials:"
  echo "  - Username: ${ELASTIC_USER}"
  echo "  - Password: ${ELASTIC_PASS}"
  echo ""
  echo "Note: It may take 1-2 minutes for all services to be fully ready."
  echo "Check logs with: docker compose logs -f"
  echo "================================"

  # Gate on ES health
  wait_for_elasticsearch_health

  # Dynamically find and remove any exited one-shot containers from this project
  remove_exited_compose_containers
}

stop_stack() {
  print_header "Stopping ELK Stack (containers + volumes)"
  docker compose down -v
  echo "✅ Stopped containers and removed named volumes."
}

destroy_stack() {
  print_header "Destroying ELK Stack (containers + volumes + images)"
  docker compose down -v --rmi all
  echo "🧹 Pruning dangling resources (images/containers/networks/build cache)..."
  docker system prune -f
  echo "🧽 Pruning unnamed/anonymous volumes (dangling volumes across the host)..."
  docker volume prune -f
  echo "✅ Destroy complete."
}

# --- CLI handling ---
ACTION="${1:-}"

if [[ -z "$ACTION" ]]; then
  echo "No action provided."
  while true; do
    read -r -p "Choose action [start/stop/destroy]: " ACTION
    ACTION=$(echo "$ACTION" | tr '[:upper:]' '[:lower:]')
    case "$ACTION" in
      start|stop|destroy) break ;;
      *) echo "Invalid choice. Please enter 'start', 'stop', or 'destroy'." ;;
    esac
  done
else
  ACTION=$(echo "$ACTION" | tr '[:upper:]' '[:lower:]')
  case "$ACTION" in
    start|stop|destroy) ;;
    *)
      echo "Invalid argument: '$ACTION'"
      echo "Usage: $0 [start|stop|destroy]"
      exit 2
      ;;
  esac
fi

case "$ACTION" in
  start)   start_stack ;;
  stop)    stop_stack ;;
  destroy) destroy_stack ;;
esac
