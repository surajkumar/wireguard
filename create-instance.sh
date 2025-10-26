#!/bin/bash
set -euo pipefail

aws configure set cli_pager ""

# === Configuration ===
INSTANCE_NAME="wireguard-vpn-$(date +%Y%m%d-%H%M%S)"
REGION="eu-west-2"
USER_DATA_FILE="startup.sh"
BLUEPRINT_ID="ubuntu_24_04"
BUNDLE_ID="nano_3_0"

# Fetch all AZs for the region
AVAILABLE_AZS=$(aws lightsail get-regions --region=${REGION} --include-availability-zones --query "regions[?name=='${REGION}'].availabilityZones[].zoneName" --output text)

if [[ -z "$AVAILABLE_AZS" ]]; then
    echo "❌ No availability zones found for region '${REGION}'"
    exit 1
fi

# === Validate region ===
AVAILABLE_REGIONS=$(aws lightsail get-regions --query "regions[].name" --output text)

# Pick the first AZ
AVAILABILITY_ZONE=$(echo "$AVAILABLE_AZS" | awk '{print $1}')

if ! echo "$AVAILABLE_REGIONS" | grep -qw "${REGION}"; then
    echo "❌ Error: Region '${REGION}' (from AZ '${AVAILABILITY_ZONE}') is not supported by AWS Lightsail."
    echo "Supported regions are:"
    echo "$AVAILABLE_REGIONS" | tr '\t' '\n'
    exit 1
fi

echo "✅ Using region '${REGION}' and availability zone '${AVAILABILITY_ZONE}'."

# === Validate bundle ===
AVAILABLE_BUNDLES=$(aws lightsail get-bundles \
    --query "bundles[].bundleId" \
    --output text)

if ! echo "$AVAILABLE_BUNDLES" | grep -qw "${BUNDLE_ID}"; then
    echo "❌ Error: Bundle ID '${BUNDLE_ID}' is not supported."
    echo "Supported bundles are:"
    aws lightsail get-bundles --query "bundles[].{ID:bundleId,Specs:bundleType,Price:price,Memory:memoryInGb}" --output table
    exit 1
fi

BUNDLE_INFO=$(aws lightsail get-bundles --query "bundles[?bundleId=='${BUNDLE_ID}'] | [0]" --output json)
echo "✅ Selected bundle '${BUNDLE_ID}':"
echo "$BUNDLE_INFO" | jq

# === Create instance ===
aws lightsail create-instances \
  --instance-names "${INSTANCE_NAME}" \
  --availability-zone "${AVAILABILITY_ZONE}" \
  --blueprint-id "${BLUEPRINT_ID}" \
  --bundle-id "${BUNDLE_ID}" \
  --user-data "file://${USER_DATA_FILE}"

echo "🕓 Waiting for instance to become available..."
while true; do
    STATE=$(aws lightsail get-instance \
        --instance-name "${INSTANCE_NAME}" \
        --query "instance.state.name" \
        --output text)
    echo "   → Current state: ${STATE}"
    [[ "${STATE}" == "running" ]] && break
    sleep 5
done

echo "🔓 Configuring firewall rules..."

# Allow HTTPS (TCP 443)
aws lightsail open-instance-public-ports \
  --instance-name "${INSTANCE_NAME}" \
  --port-info fromPort=443,toPort=443,protocol=TCP

# Allow WireGuard (UDP 51820)
aws lightsail open-instance-public-ports \
  --instance-name "${INSTANCE_NAME}" \
  --port-info fromPort=51820,toPort=51820,protocol=UDP

# Allow WireGuard (TCP 8000)
aws lightsail open-instance-public-ports \
  --instance-name "${INSTANCE_NAME}" \
  --port-info fromPort=8000,toPort=8000,protocol=TCP

echo "✅ Firewall ports 443/TCP and 51820/UDP are now open to the public."

echo "🎉 Instance '${INSTANCE_NAME}' created successfully!"

echo "🌐 Configuring static IP address"
STATIC_IP_NAME="wireguard-vpn-static-ip-$(date +%Y%m%d-%H%M%S)"

aws lightsail allocate-static-ip \
    --static-ip-name "$STATIC_IP_NAME"

aws lightsail attach-static-ip \
    --static-ip-name "$STATIC_IP_NAME" \
    --instance-name "$INSTANCE_NAME"

echo "✅ ${STATIC_IP_NAME} has been attached to ${INSTANCE_NAME}"

aws lightsail get-instance --instance-name "${INSTANCE_NAME}" \
  --query "instance.{Name:name,PublicIPv4:publicIpAddress,PublicIPv6:ipv6Addresses}" \
  --output table

# Get the public IPv4
PUBLIC_IPV4=$(aws lightsail get-instance \
  --instance-name "${INSTANCE_NAME}" \
  --query "instance.publicIpAddress" \
  --output text)

echo "🌐 Public IPv4: ${PUBLIC_IPV4}"

# Wait for service on port 8000 to respond with HTTP 200
echo "⏳ Waiting for WireGuard web interface to be ready at http://${PUBLIC_IPV4}:8000/signin..."

TIMEOUT=300 # 5 minutes
INTERVAL=5
ELAPSED=0

while true; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$PUBLIC_IPV4:8000/signin" || echo "000")

    if [[ "$HTTP_STATUS" == "200" ]]; then
        echo "✅ Web interface is ready!"
        break
    else
        echo "   → Current HTTP status: $HTTP_STATUS (waiting...)"
    fi

    sleep $INTERVAL

    ELAPSED=$((ELAPSED+INTERVAL))

    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        echo "❌ Timeout waiting for web interface to become ready."
        exit 1
    fi
done