#!/bin/bash
set -euo pipefail

# === Configuration ===
INSTANCE_NAME="wireguard-vpn"
AVAILABILITY_ZONE="us-east-1a"
USER_DATA_FILE="startup.sh"
BLUEPRINT_ID="ubuntu_24_04"
BUNDLE_ID="nano_2_0"

# === Supported regions (no AZ suffix) ===
SUPPORTED_REGIONS=(
  eu-central-1  # Frankfurt
  eu-west-3     # Paris
  eu-west-2     # London
  eu-west-1     # Ireland
  eu-north-1    # Stockholm
  ap-south-1    # Mumbai
  ca-central-1  # Montreal
  us-east-1     # Virginia
  us-east-2     # Ohio
  ap-southeast-1 # Singapore
  ap-southeast-3 # Jakarta
  ap-northeast-2 # Seoul
  ap-northeast-1 # Tokyo
  us-west-2      # Oregon
  ap-southeast-2 # Sydney
)

# === Extract region part from AZ (e.g., us-east-1 from us-east-1a) ===
REGION="${AVAILABILITY_ZONE::-1}"

# === Validate region ===
if [[ ! " ${SUPPORTED_REGIONS[*]} " =~ ${REGION} ]]; then
  echo "❌ Error: Region '${REGION}' (from AZ '${AVAILABILITY_ZONE}') is not supported by AWS Lightsail."
  echo "Supported regions are:"
  for r in "${SUPPORTED_REGIONS[@]}"; do echo " - $r"; done
  exit 1
fi

echo "✅ Using region '${REGION}' and availability zone '${AVAILABILITY_ZONE}'."

# === Create instance ===
aws lightsail create-instances \
  --instance-names "${INSTANCE_NAME}" \
  --availability-zone "${AVAILABILITY_ZONE}" \
  --blueprint-id "${BLUEPRINT_ID}" \
  --bundle-id "${BUNDLE_ID}" \
  --user-data "file://${USER_DATA_FILE}"

echo "🕓 Waiting for instance to become available..."
aws lightsail wait instance-running --instance-name "${INSTANCE_NAME}"

echo "🌐 Enabling IPv6 (dual-stack)..."
aws lightsail enable-instance-ipv6 --instance-name "${INSTANCE_NAME}"

echo "🎉 Instance '${INSTANCE_NAME}' creation initiated successfully in ${AVAILABILITY_ZONE}."

aws lightsail get-instance --instance-name "${INSTANCE_NAME}" \
  --query "instance.{Name:name,PublicIPv4:publicIpAddress,PublicIPv6:ipv6Addresses}" \
  --output table
