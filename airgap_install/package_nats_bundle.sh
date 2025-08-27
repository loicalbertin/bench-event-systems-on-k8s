#!/usr/bin/env bash
set -euo pipefail

# === Variables ===
OUTPUT_DIR="./airgap_bundle_nats"
CHARTS_DIR="$OUTPUT_DIR/charts"
IMAGES_DIR="$OUTPUT_DIR/images"
SCRIPTS_DIR="$OUTPUT_DIR/scripts"
DEPS_DIR="$OUTPUT_DIR/deployments"
DEPS_DIR_ORI="deployments/nats"
BUNDLE_TGZ="airgap_hpc_eventbus_nats_bundle.tgz"

# Local registry destination in your cluster
LOCAL_REGISTRY="registry.local:5000"

# List of Helm charts
declare -A CHARTS=(
  # NATS
  ["nats"]="nats/nats"
)

# List of critical Docker images to preload
IMAGES=(
  # NATS
  "natsio/nats-box:0.18.0"
  "nats:2.11.8-alpine"
  "natsio/nats-server-config-reloader:0.19.1"
  "natsio/prometheus-nats-exporter:0.17.3"
)

# === Preparation ===
rm -rf "$OUTPUT_DIR"
mkdir -p "$CHARTS_DIR" "$IMAGES_DIR" "$SCRIPTS_DIR" "$DEPS_DIR"

cp -r "$DEPS_DIR_ORI/"* "$DEPS_DIR"

# Add Helm repositories if not present
echo "== Adding Helm repositories =="
helm repo add nats https://nats-io.github.io/k8s/helm/charts/ || true
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

  cat >> "${SCRIPTS_DIR}/load_images.sh" << EOF 
echo "Loading $img"
podman load < "../images/${safe_name}.tar"
echo "Tagging $img"
podman tag $img "registry.regionadmin.svc.kube.local:5000/smcx/$img"
echo "Pushing $img"
podman push "registry.regionadmin.svc.kube.local:5000/smcx/$img"

EOF
done


echo "== Creating archive =="
tar -czf "$BUNDLE_TGZ" -C "$OUTPUT_DIR" .

echo "== Completed =="
echo "Archive ready: $BUNDLE_TGZ"
