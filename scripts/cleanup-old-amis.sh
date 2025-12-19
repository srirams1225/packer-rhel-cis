#!/bin/bash
# Automated cleanup script for old AMIs and their associated snapshots
# Usage: ./cleanup-old-amis.sh <ami-name-prefix> <days-to-keep>
# Example: ./cleanup-old-amis.sh rhel9-base 7

set -euo pipefail

PREFIX="$1"
DAYS="$2"

if [[ -z "$PREFIX" || -z "$DAYS" ]]; then
  echo "Usage: $0 <ami-name-prefix> <days-to-keep>"
  echo "Example: $0 rhel9-base 7"
  exit 1
fi

# Validate DAYS is a number
if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
  echo "Error: days-to-keep must be a positive number"
  exit 1
fi

DATE_CUTOFF=$(date -d "$DAYS days ago" +%Y-%m-%d)

echo "=========================================="
echo "AMI Cleanup Script"
echo "=========================================="
echo "Prefix: $PREFIX"
echo "Days to keep: $DAYS"
echo "Cutoff date: $DATE_CUTOFF"
echo "=========================================="
echo ""

echo "Searching for AMIs named '$PREFIX*' created before $DATE_CUTOFF..."

# 1. Find AMIs older than cutoff
# We fetch ImageID, CreationDate, Name, and the associated SnapshotID
AMIS_TO_DELETE=$(aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=$PREFIX*" \
  --query "Images[?CreationDate<'$DATE_CUTOFF'].{ID:ImageId, Name:Name, Date:CreationDate, Snap:BlockDeviceMappings[0].Ebs.SnapshotId}" \
  --output text)

if [[ -z "$AMIS_TO_DELETE" ]]; then
  echo "No old AMIs found matching criteria."
  exit 0
fi

# Count AMIs to delete
AMI_COUNT=$(echo "$AMIS_TO_DELETE" | wc -l)
echo "Found $AMI_COUNT AMI(s) to delete:"
echo ""
echo "$AMIS_TO_DELETE" | while read -r AMI_ID AMI_NAME AMI_DATE SNAP_ID; do
  echo "  - $AMI_ID ($AMI_NAME) - Created: $AMI_DATE"
done
echo ""

# Safety confirmation
read -p "Do you want to proceed with deletion? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Deletion cancelled."
  exit 0
fi

# 2. Loop through and delete
DELETED_COUNT=0
FAILED_COUNT=0

echo "$AMIS_TO_DELETE" | while read -r AMI_ID AMI_NAME AMI_DATE SNAP_ID; do
  echo "Processing $AMI_ID ($AMI_NAME)..."
  
  # Step 1: Deregister AMI
  echo "  - Deregistering AMI..."
  if aws ec2 deregister-image --image-id "$AMI_ID" 2>/dev/null; then
    echo "    ✓ AMI deregistered successfully"
  else
    echo "    ✗ Failed to deregister AMI (may already be deregistered)"
    ((FAILED_COUNT++)) || true
    continue
  fi
  
  # Step 2: Delete Snapshot
  if [[ "$SNAP_ID" != "None" && -n "$SNAP_ID" ]]; then
    echo "  - Deleting Snapshot $SNAP_ID..."
    if aws ec2 delete-snapshot --snapshot-id "$SNAP_ID" 2>/dev/null; then
      echo "    ✓ Snapshot deleted successfully"
    else
      echo "    ✗ Failed to delete snapshot (may already be deleted or in use)"
    fi
  else
    echo "  - No snapshot associated with this AMI"
  fi
  
  echo "  ✓ Done."
  ((DELETED_COUNT++)) || true
  echo ""
done

echo "=========================================="
echo "Cleanup completed!"
echo "=========================================="

