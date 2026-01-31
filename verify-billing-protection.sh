#!/bin/bash

# Billing Protection Verification Script
# Verifies that Cloud Run, Eventarc, and Pub/Sub components are properly configured
# to automatically disable billing when budget thresholds are exceeded.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null)}"
REGION="asia-southeast1"
SERVICE_NAME="billing-limit-reached"
TOPIC_NAME="billing-limit-reached"

# Validation
if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}ERROR: No project specified and no default gcloud project found${NC}"
  echo "Usage: $0 [PROJECT_ID]"
  exit 1
fi

echo "=========================================="
echo "Billing Protection Verification"
echo "=========================================="
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Get project number
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
PUBSUB_SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"

FAILED_CHECKS=0

# Check 1: Cloud Run Service
echo -n "Checking Cloud Run service... "
if gcloud run services describe "$SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(status.conditions[0].status)' 2>/dev/null | grep -q "True"; then
  echo -e "${GREEN}✓ PASS${NC}"
else
  echo -e "${RED}✗ FAIL${NC}"
  echo "  Service '$SERVICE_NAME' is not ready or doesn't exist"
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 2: Eventarc Trigger
echo -n "Checking Eventarc trigger... "
TRIGGER_NAME=$(gcloud eventarc triggers list \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --filter="destination.cloudRun.service:$SERVICE_NAME" \
    --format='value(name)' 2>/dev/null | head -n1)

if [[ -n "$TRIGGER_NAME" ]]; then
  echo -e "${GREEN}✓ PASS${NC}"
  echo "  Trigger: $(basename "$TRIGGER_NAME")"
else
  echo -e "${RED}✗ FAIL${NC}"
  echo "  No Eventarc trigger found for service '$SERVICE_NAME'"
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 3: Pub/Sub Topic
echo -n "Checking Pub/Sub topic... "
if gcloud pubsub topics describe "$TOPIC_NAME" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo -e "${GREEN}✓ PASS${NC}"
else
  echo -e "${RED}✗ FAIL${NC}"
  echo "  Topic '$TOPIC_NAME' doesn't exist"
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 4: Pub/Sub Subscription
echo -n "Checking Pub/Sub subscription... "
SUBSCRIPTION=$(gcloud pubsub subscriptions list \
    --filter="topic:$TOPIC_NAME" \
    --project="$PROJECT_ID" \
    --format='value(name)' 2>/dev/null | head -n1)

if [[ -n "$SUBSCRIPTION" ]]; then
  echo -e "${GREEN}✓ PASS${NC}"
  echo "  Subscription: $(basename "$SUBSCRIPTION")"
else
  echo -e "${RED}✗ FAIL${NC}"
  echo "  No subscription found for topic '$TOPIC_NAME'"
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 5: Pub/Sub Service Agent Token Creator Role
echo -n "Checking Pub/Sub service agent permissions... "
if gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:$PUBSUB_SA AND bindings.role:roles/iam.serviceAccountTokenCreator" \
    --format='value(bindings.role)' 2>/dev/null | grep -q "serviceAccountTokenCreator"; then
  echo -e "${GREEN}✓ PASS${NC}"
else
  echo -e "${RED}✗ FAIL${NC}"
  echo "  Service account '$PUBSUB_SA' missing 'roles/iam.serviceAccountTokenCreator'"
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 6: Cloud Run Invoker Permission
echo -n "Checking Cloud Run invoker permission... "
if gcloud run services get-iam-policy "$SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:$COMPUTE_SA AND bindings.role:roles/run.invoker" \
    --format='value(bindings.role)' 2>/dev/null | grep -q "run.invoker"; then
  echo -e "${GREEN}✓ PASS${NC}"
else
  echo -e "${RED}✗ FAIL${NC}"
  echo "  Service account '$COMPUTE_SA' missing 'roles/run.invoker' on Cloud Run service"
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Summary
echo ""
echo "=========================================="
if [[ $FAILED_CHECKS -eq 0 ]]; then
  echo -e "${GREEN}✓ ALL CHECKS PASSED${NC}"
  echo "Billing protection is active and ready."
  exit 0
else
  echo -e "${RED}✗ $FAILED_CHECKS CHECK(S) FAILED${NC}"
  echo "Billing protection may not work correctly."
  echo ""
  echo "To fix issues, refer to the README.md setup instructions."
  exit 1
fi
