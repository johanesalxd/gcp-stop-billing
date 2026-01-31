# GCP Automatic Billing Disabler

Automatically disable Google Cloud Platform billing when budget thresholds are exceeded using Cloud Run functions and Eventarc.

## Overview

This Cloud Run function monitors your GCP budget via Pub/Sub notifications and automatically disables billing for your project when costs exceed the budget threshold. This helps prevent unexpected charges.

**WARNING:** Disabling billing will stop all services in your project and may cause outages. Ensure thorough testing before enabling in production.

## Prerequisites

- Google Cloud Project with billing enabled
- `gcloud` CLI installed and authenticated
- Required permissions:
  - `roles/run.admin` - Deploy Cloud Run services
  - `roles/eventarc.admin` - Create Eventarc triggers
  - `roles/iam.serviceAccountAdmin` - Manage service account permissions
  - `roles/billing.admin` - Manage billing settings
  - `roles/pubsub.admin` - Create Pub/Sub topics

## Architecture

```
Budget Alert → Pub/Sub Topic → Eventarc Trigger → Cloud Run Function → Billing API
```

## Setup Instructions

### Step 1: Enable Required APIs

```bash
gcloud services enable run.googleapis.com \
    cloudbuild.googleapis.com \
    eventarc.googleapis.com \
    pubsub.googleapis.com \
    cloudbilling.googleapis.com \
    --project=YOUR_PROJECT_ID
```

### Step 2: Create a Budget with Pub/Sub Notifications

1. Go to [Cloud Billing Budgets](https://console.cloud.google.com/billing/budgets)
2. Click **CREATE BUDGET**
3. Configure budget:
   - **Name:** e.g., "Monthly Budget Alert"
   - **Projects:** Select your project
   - **Budget amount:** Set your threshold
4. Set threshold rules (e.g., 50%, 90%, 100%)
5. **Manage notifications:**
   - Click **CONNECT A PUB/SUB TOPIC TO THIS BUDGET**
   - Create a new topic (e.g., `billing-limit-reached`)
   - Note the topic name for later

### Step 3: Grant Service Account Permissions

Get your project number:
```bash
PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format='value(projectNumber)')
```

Grant Pub/Sub service agent the token creator role:
```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountTokenCreator"
```

### Step 4: Deploy the Cloud Run Function

Clone this repository and navigate to the directory:
```bash
cd /path/to/gcp-stop-billing
```

Deploy the function:
```bash
gcloud run deploy billing-limit-reached \
    --source=. \
    --region=asia-southeast1 \
    --project=YOUR_PROJECT_ID \
    --no-allow-unauthenticated
```

**Note:** The `--no-allow-unauthenticated` flag ensures only authenticated requests (from Eventarc) can invoke the function.

### Step 5: Create Eventarc Trigger

Create a trigger that connects the Pub/Sub topic to your Cloud Run function:

```bash
gcloud eventarc triggers create billing-trigger \
    --location=asia-southeast1 \
    --destination-run-service=billing-limit-reached \
    --destination-run-region=asia-southeast1 \
    --event-filters="type=google.cloud.pubsub.topic.v1.messagePublished" \
    --transport-topic=billing-limit-reached \
    --service-account=YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --project=YOUR_PROJECT_ID
```

Replace:
- `YOUR_PROJECT_ID` with your GCP project ID
- `YOUR_PROJECT_NUMBER` with your project number
- `billing-limit-reached` with your Pub/Sub topic name (if different)

### Step 6: Grant Cloud Run Invoker Permission

The Eventarc trigger's service account needs permission to invoke the Cloud Run function:

```bash
gcloud run services add-iam-policy-binding billing-limit-reached \
    --region=asia-southeast1 \
    --member="serviceAccount:YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/run.invoker" \
    --project=YOUR_PROJECT_ID
```

### Step 7: Verify Deployment

Check that the Cloud Run service is healthy:
```bash
gcloud run services describe billing-limit-reached \
    --region=asia-southeast1 \
    --project=YOUR_PROJECT_ID \
    --format="value(status.conditions[0].status)"
```

Expected output: `True`

Check the Eventarc trigger:
```bash
gcloud eventarc triggers describe billing-trigger \
    --location=asia-southeast1 \
    --project=YOUR_PROJECT_ID
```

## Configuration

### Enable Live Billing Disablement

By default, the function runs in **simulation mode** to prevent accidental billing disablement.

To enable actual billing disablement, edit `main.py`:

```python
# Change this line from True to False
SIMULATE_DEACTIVATION = False
```

Then redeploy:
```bash
gcloud run deploy billing-limit-reached \
    --source=. \
    --region=asia-southeast1 \
    --project=YOUR_PROJECT_ID
```

## Testing

### Test with a Budget Alert

1. Manually trigger a budget notification (if your budget allows)
2. Check Cloud Run logs:
```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=billing-limit-reached" \
    --limit=50 \
    --project=YOUR_PROJECT_ID
```

### Expected Log Output (Simulation Mode)

```
Cost: 150.00 Budget: 100.00
Disabling billing for project 'projects/YOUR_PROJECT_ID'...
Getting billing info for project 'projects/YOUR_PROJECT_ID'...
Billing disabled. (Simulated)
```

## Troubleshooting

### Error: "The request was not authenticated"

**Cause:** The Eventarc trigger's service account doesn't have `roles/run.invoker` permission.

**Solution:**
```bash
gcloud run services add-iam-policy-binding billing-limit-reached \
    --region=asia-southeast1 \
    --member="serviceAccount:YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/run.invoker" \
    --project=YOUR_PROJECT_ID
```

### Error: "Container failed to start"

**Cause:** Missing dependencies in `requirements.txt`.

**Solution:** Ensure `requirements.txt` contains:
```
functions-framework==3.*
cloudevents==1.*
google-cloud-billing==1.*
google-cloud-logging==3.*
```

### Error: "Failed to disable billing, check permissions"

**Cause:** The Cloud Run service account lacks billing permissions.

**Solution:** Grant billing admin role to the service account:
```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/billing.admin"
```

### Pub/Sub Messages Not Triggering Function

**Verify Eventarc trigger:**
```bash
gcloud eventarc triggers list --location=asia-southeast1 --project=YOUR_PROJECT_ID
```

**Check Pub/Sub subscription:**
```bash
gcloud pubsub subscriptions list --project=YOUR_PROJECT_ID
```

You should see a subscription like `eventarc-asia-southeast1-billing-trigger-sub-XXX`.

## Files

- `main.py` - Cloud Run function code
- `requirements.txt` - Python dependencies
- `README.md` - This file

## Security Considerations

- The function runs with the default compute service account. Consider using a dedicated service account with minimal permissions.
- Keep `SIMULATE_DEACTIVATION = True` until thoroughly tested.
- Monitor Cloud Logging for any unauthorized invocation attempts.
- Use budget alerts at multiple thresholds (e.g., 50%, 90%, 100%) to get warnings before automatic disablement.

## References

- [Google Cloud Billing Documentation](https://cloud.google.com/billing/docs/how-to/disable-billing-with-notifications)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Eventarc Documentation](https://cloud.google.com/eventarc/docs)

## License

This code is based on Google Cloud's official samples and follows the Apache 2.0 License.
