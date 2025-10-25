#!/bin/bash

# ELK Stack Control Script
# Actions:
#   start   - start stack, wait for ES health (green/yellow), then clean up a finished one-shot container
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
  # Preferred: default route interface -> IPv4
  if command -v ip >/dev/null 2>&1; then
    local iface
    iface="$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')"
    if [[ -n "${iface:-}" ]]; then
      ip="$(ip -4 addr show "$iface" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
    fi
  fi

  # Fallback 1: hostname -I (first IPv4)
  if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\./){print $i; exit}}')"
  fi

  # Fallback 2: localhost (last resort)
  if [[ -z "$ip" ]]; then
    ip="127.0.0.1"
  fi

  echo "$ip"
}

HOST_IP="$(get_host_ip)"

# Elasticsearch connection details
ELASTIC_URL="http://${HOST_IP}:9200"
ELASTIC_USER="elastic"
ELASTIC_PASS="elastic_password_123"

# One-shot/temporary container to remove when done
TEMP_CONTAINER_NAME="elk_920-setup-kibana-user-1"

print_header() {
  echo "================================"
  echo "$1"
  echo "================================"
}

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
        docker rm "$TARGET_CONTAINER"
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

  wait_for_elasticsearch_health
  wait_for_container_exit "${TEMP_CONTAINER_NAME}"
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
