#!/usr/bin/env bash
set -euo pipefail

# === Variables ===
OUTPUT_DIR="./airgap_bundle_bench"
IMAGES_DIR="$OUTPUT_DIR/images"
SCRIPTS_DIR="$OUTPUT_DIR/scripts"
DEPS_DIR="$OUTPUT_DIR/deployments"
DEPS_DIR_ORI="deployments/bench"
BUNDLE_TGZ="airgap_hpc_eventbus_bench_bundle.tgz"

# Local registry destination in your cluster
LOCAL_REGISTRY="registry.local:5000"


# === Preparation ===
rm -rf "$OUTPUT_DIR"
mkdir -p "$IMAGES_DIR" "$SCRIPTS_DIR" "$DEPS_DIR"

cp -r "$DEPS_DIR_ORI/"* "$DEPS_DIR"

echo "== Building and saving Docker images =="
cat > "${SCRIPTS_DIR}/load_images.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

EOF
chmod +x "${SCRIPTS_DIR}/load_images.sh"

img="eb-bench:latest"
echo "Building $img"
pushd ..
docker build -t eb-bench:latest .
popd
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


echo "== Creating archive =="
tar -czf "$BUNDLE_TGZ" -C "$OUTPUT_DIR" .

echo "== Completed =="
echo "Archive ready: $BUNDLE_TGZ"
