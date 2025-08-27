#!/usr/bin/env bash
set -euo pipefail

# === Variables ===
OUTPUT_DIR="./airgap_bundle_kafka"
CHARTS_DIR="$OUTPUT_DIR/charts"
IMAGES_DIR="$OUTPUT_DIR/images"
SCRIPTS_DIR="$OUTPUT_DIR/scripts"
DEPS_DIR="$OUTPUT_DIR/deployments"
DEPS_DIR_ORI="deployments/kafka"
BUNDLE_TGZ="airgap_hpc_eventbus_kafka_bundle.tgz"

# Local registry destination in your cluster
LOCAL_REGISTRY="registry.local:5000"

# List of Helm charts
declare -A CHARTS=(
  # Kafka (Strimzi)
  ["strimzi-kafka-operator"]="strimzi/strimzi-kafka-operator"
)

# List of critical Docker images to preload
IMAGES=(
  # Strimzi Kafka Operator
  "quay.io/strimzi/operator:0.47.0"
  "quay.io/strimzi/kafka:0.47.0-kafka-4.0.0"
)

# === Preparation ===
rm -rf "$OUTPUT_DIR"
mkdir -p "$CHARTS_DIR" "$IMAGES_DIR" "$SCRIPTS_DIR" "$DEPS_DIR"

cp -r "$DEPS_DIR_ORI/"* "$DEPS_DIR"

# Add Helm repositories if not present
echo "== Adding Helm repositories =="
helm repo add strimzi https://strimzi.io/charts/ || true
helm repo update

echo "== Downloading Helm charts =="
for name in "${!CHARTS[@]}"; do
  chart="${CHARTS[$name]}"
  echo "Fetching chart $name from repository $chart"
  helm fetch "$chart" --destination "$CHARTS_DIR"
done

echo "== Downloading and saving Docker images =="
cat > "${SCRIPTS_DIR}/load_images.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

EOF
chmod +x "${SCRIPTS_DIR}/load_images.sh"

for img in "${IMAGES[@]}"; do
  echo "Pulling $img"
  docker pull "$img"
  safe_name=$(echo "$img" | tr '/:' '_')
  echo "Saving $img -> $IMAGES_DIR/${safe_name}.tar"
  docker save "$img" -o "$IMAGES_DIR/${safe_name}.tar"
  img_no_quay="${img##quay.io/}"

  cat >> "${SCRIPTS_DIR}/load_images.sh" << EOF 
echo "Loading $img"
podman load < "../images/${safe_name}.tar"
echo "Tagging $img"
podman tag $img "registry.regionadmin.svc.kube.local:5000/smcx/$img_no_quay"
echo "Pushing $img"
podman push "registry.regionadmin.svc.kube.local:5000/smcx/$img_no_quay"

EOF
done


echo "== Creating archive =="
tar -czf "$BUNDLE_TGZ" -C "$OUTPUT_DIR" .

echo "== Completed =="
echo "Archive ready: $BUNDLE_TGZ"
