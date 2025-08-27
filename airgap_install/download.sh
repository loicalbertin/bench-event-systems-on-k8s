#!/usr/bin/env bash
set -euo pipefail

# === Variables ===
OUTPUT_DIR="./airgap_bundle"
CHARTS_DIR="$OUTPUT_DIR/charts"
IMAGES_DIR="$OUTPUT_DIR/images"
BUNDLE_TGZ="airgap_hpc_eventbus_bundle.tgz"

# Local registry destination in your cluster
LOCAL_REGISTRY="registry.local:5000"

# List of Helm charts
declare -A CHARTS=(
  # NATS
  ["nats"]="nats/nats"
  ["nats-operator"]="nats/nats-operator"

  # Kafka (Strimzi)
  ["strimzi-kafka-operator"]="strimzi/strimzi-kafka-operator"

  # Pulsar
  ["pulsar"]="apache/pulsar"
)

# List of critical Docker images to preload
IMAGES=(
  # NATS
  "nats:2.10.18-alpine"
  #"natsio/nats-box:0.14.0"
  "connecteverything/nats-server-config-reloader:0.2.2-v1alpha2"
  "synadia/prometheus-nats-exporter:0.6.2"

  # Strimzi Kafka Operator
  "quay.io/strimzi/operator:0.47.0"
  "quay.io/strimzi/kafka:0.47.0-kafka-4.0.0"

  # Pulsar (versions linked to chart pulsar-3.1.0)
  "apachepulsar/pulsar:3.1.2"
  "apachepulsar/pulsar-all:3.1.2"
  "busybox:1.36"
)

# === Preparation ===
rm -rf "$OUTPUT_DIR"
mkdir -p "$CHARTS_DIR" "$IMAGES_DIR"

# Add Helm repositories if not present
echo "== Adding Helm repositories =="
helm repo add nats https://nats-io.github.io/k8s/helm/charts/ || true
helm repo add strimzi https://strimzi.io/charts/ || true
helm repo add apache https://pulsar.apache.org/charts/ || true
helm repo update

echo "== Downloading Helm charts =="
for name in "${!CHARTS[@]}"; do
  chart="${CHARTS[$name]}"
  echo "Fetching chart $name from repository $chart"
  helm fetch "$chart" --destination "$CHARTS_DIR"
done

echo "== Downloading and saving Docker images =="
for img in "${IMAGES[@]}"; do
  echo "Pulling $img"
  docker pull "$img"
  safe_name=$(echo "$img" | tr '/:' '_')
  echo "Saving $img -> $IMAGES_DIR/${safe_name}.tar"
  docker save "$img" -o "$IMAGES_DIR/${safe_name}.tar"
done

echo "== Creating archive =="
tar -czf "$BUNDLE_TGZ" -C "$OUTPUT_DIR" .

echo "== Completed =="
echo "Archive ready: $BUNDLE_TGZ"
