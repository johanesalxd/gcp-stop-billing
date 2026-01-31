# GCP Automatic Billing Disabler

Automatically disable Google Cloud Platform billing when budget thresholds are exceeded using Cloud Run functions and Eventarc.

**WARNING:** Disabling billing will stop all services in your project. Test thoroughly before enabling in production.

## Quick Start

### Prerequisites

- Google Cloud Project with billing enabled
- `gcloud` CLI installed and authenticated
- Billing Account Administrator access

### Step 1: Enable Required APIs

```bash
gcloud services enable run.googleapis.com \
    cloudbuild.googleapis.com \
    eventarc.googleapis.com \
    pubsub.googleapis.com \
    cloudbilling.googleapis.com \
    --project=YOUR_PROJECT_ID
```

### Step 2: Create Budget with Pub/Sub Notifications

1. Go to [Cloud Billing Budgets](https://console.cloud.google.com/billing/budgets)
2. Click **CREATE BUDGET**
3. Set budget amount and thresholds (e.g., 50%, 90%, 100%)
4. Under **Manage notifications**, click **CONNECT A PUB/SUB TOPIC**
5. Create topic named `billing-limit-reached`

### Step 3: Deploy Cloud Run Function

```bash
# Clone and navigate to this repository
cd /path/to/gcp-stop-billing

# Deploy the function
gcloud run deploy billing-limit-reached \
    --source=. \
    --region=YOUR_REGION \
    --project=YOUR_PROJECT_ID \
    --no-allow-unauthenticated
```

### Step 4: Grant Required Permissions

Get your project number:
```bash
PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)')
```

Grant permissions:
```bash
# Pub/Sub service agent - token creator
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountTokenCreator"

# Cloud Run invoker permission
gcloud run services add-iam-policy-binding billing-limit-reached \
    --region=YOUR_REGION \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/run.invoker" \
    --project=YOUR_PROJECT_ID

# Billing Account Administrator (CRITICAL)
gcloud billing accounts add-iam-policy-binding YOUR_BILLING_ACCOUNT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/billing.admin"
```

Find your billing account ID:
```bash
gcloud billing accounts list
```

### Step 5: Create Eventarc Trigger

```bash
gcloud eventarc triggers create billing-trigger \
    --location=YOUR_REGION \
    --destination-run-service=billing-limit-reached \
    --destination-run-region=YOUR_REGION \
    --event-filters="type=google.cloud.pubsub.topic.v1.messagePublished" \
    --transport-topic=billing-limit-reached \
    --service-account=${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
    --project=YOUR_PROJECT_ID
```

**Note:** Eventarc may auto-generate a trigger name (e.g., `trigger-xxxxxxxx`) instead of using your specified name. This is normal and doesn't affect functionality.

## Configuration

### Enable Live Billing Disablement

By default, the function runs in **simulation mode**. To enable actual billing disablement:

1. Edit `main.py` and change:
   ```python
   SIMULATE_DEACTIVATION = False
   ```

2. Redeploy:
   ```bash
   gcloud run deploy billing-limit-reached \
       --source=. \
       --region=YOUR_REGION \
       --project=YOUR_PROJECT_ID
   ```

## Testing

### Manual Test

Publish a test message to trigger the function:

```bash
gcloud pubsub topics publish billing-limit-reached \
    --project=YOUR_PROJECT_ID \
    --message='{"costAmount": 100.01, "budgetAmount": 100.00}'
```

### Check Logs

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=billing-limit-reached" \
    --limit=20 \
    --project=YOUR_PROJECT_ID \
    --format="table(timestamp,textPayload)"
```

### Expected Output (Live Mode)

```
Cost: 100.01 Budget: 100.0
Disabling billing for project 'projects/YOUR_PROJECT_ID'...
Getting billing info for project 'projects/YOUR_PROJECT_ID'...
Billing disabled: name: "projects/YOUR_PROJECT_ID/billingInfo"
```

## Recovery After Billing Disabled

If billing was automatically disabled due to budget exceeded, follow these steps to restore service:

### Step 1: Re-attach Billing

Re-enable billing via Console or CLI:

```bash
gcloud billing projects link YOUR_PROJECT_ID \
    --billing-account=YOUR_BILLING_ACCOUNT_ID
```

Find your billing account ID:
```bash
gcloud billing accounts list
```

### Step 2: Verify Protection is Active

Run the verification script to ensure all components are working:

```bash
./verify-billing-protection.sh
```

Or specify the project explicitly:
```bash
./verify-billing-protection.sh YOUR_PROJECT_ID
```

Expected output:
```
Billing Protection Verification
Project: YOUR_PROJECT_ID
Region: asia-southeast1

Checking Cloud Run service... ✓ PASS
Checking Eventarc trigger... ✓ PASS
Checking Pub/Sub topic... ✓ PASS
Checking Pub/Sub subscription... ✓ PASS
Checking Pub/Sub service agent permissions... ✓ PASS
Checking Cloud Run invoker permission... ✓ PASS

✓ ALL CHECKS PASSED
Billing protection is active and ready.
```

If any checks fail, refer to the setup instructions above to fix the configuration.

## Troubleshooting

### Error: "Failed to find attribute 'app' in 'main'"

**Cause:** Missing `Procfile` for functions-framework.

**Solution:** Ensure `Procfile` exists with:
```
web: functions-framework --target=stop_billing --signature-type=cloudevent
```

### Error: "403 The caller does not have permission"

**Cause:** Service account lacks billing permissions.

**Solution:** Grant Billing Account Administrator role (see Step 4 above).

### Error: "The request was not authenticated"

**Cause:** Eventarc trigger can't invoke Cloud Run.

**Solution:** Grant `roles/run.invoker` permission (see Step 4 above).

### Verify Billing Account Permissions

To verify the service account has billing permissions:

```bash
# List your billing accounts
gcloud billing accounts list

# Check permissions (run from Cloud Shell if needed)
gcloud billing accounts get-iam-policy YOUR_BILLING_ACCOUNT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:${PROJECT_NUMBER}-compute" \
    --format="table(bindings.role,bindings.members)"
```

Expected output should show `roles/billing.admin` for your compute service account.

## Files

- `main.py` - Cloud Run function code
- `requirements.txt` - Python dependencies
- `Procfile` - Functions framework configuration
- `verify-billing-protection.sh` - Verification script for checking system health
- `README.md` - This documentation

## Architecture

```
Budget Alert → Pub/Sub Topic → Eventarc Trigger → Cloud Run Function → Billing API
```

## Security Notes

- Use simulation mode until thoroughly tested
- Monitor Cloud Logging for unexpected invocations
- Set multiple budget thresholds (50%, 90%, 100%) for warnings
- Consider using a dedicated service account with minimal permissions

## References

- [Google Cloud Billing Documentation](https://cloud.google.com/billing/docs/how-to/disable-billing-with-notifications)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Eventarc Documentation](https://cloud.google.com/eventarc/docs)

## License

Based on Google Cloud's official samples. Apache 2.0 License.
