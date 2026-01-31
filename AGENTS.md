# Agent Instructions for GCP Stop Billing

This repository contains a Google Cloud Function that automatically disables billing when budget thresholds are exceeded. It uses Cloud Run functions, Eventarc, and Pub/Sub.

## 1. Build, Test, and Deploy Commands

This project is a Python-based Cloud Function and does not have a traditional build process. Deployment is handled via the Google Cloud CLI (`gcloud`).

### Deployment
To deploy the function to Google Cloud Run:
```bash
gcloud run deploy billing-limit-reached \
    --source=. \
    --region=asia-southeast1 \
    --project=YOUR_PROJECT_ID \
    --no-allow-unauthenticated
```
*Note: Refer to `README.md` for full prerequisite setup (APIs, permissions, etc.).*

### Testing
There are currently no unit tests (e.g., `pytest`) in the repository. Testing is performed manually or via infrastructure verification.

**Manual Trigger (Integration Test):**
You can simulate a budget alert by publishing a message to the Pub/Sub topic:
```bash
gcloud pubsub topics publish billing-limit-reached \
    --project=YOUR_PROJECT_ID \
    --message='{"costAmount": 100.01, "budgetAmount": 100.00}'
```

**Infrastructure Verification:**
Run the provided script to verify that Cloud Run, Eventarc, Pub/Sub, and IAM permissions are correctly configured:
```bash
./verify-billing-protection.sh [PROJECT_ID]
```

### Linting
There are no explicit linter configuration files (e.g., `.flake8`, `.pylintrc`) in the root.
- **Recommendation:** Agents should follow PEP 8 standards.
- **Tools:** If available, use `black` for formatting and `flake8` or `pylint` for static analysis before committing changes.

## 2. Code Style & Conventions

### General
- **Language:** Python 3.x
- **Style:** Follow **PEP 8** guidelines.
- **Safety:** This code performs destructive actions (disabling billing).
    - **CRITICAL:** Always ensure `SIMULATE_DEACTIVATION = True` in `main.py` during development and testing unless explicitly instructed to enable live deactivation.

### Imports
Group imports in the following order:
1.  **Standard Library** (e.g., `base64`, `json`, `os`, `urllib`)
2.  **Third-Party Libraries** (e.g., `functions_framework`, `cloudevents`, `google.cloud`)
3.  **Local Application Imports** (if any)

Example:
```python
import base64
import json
import os

import functions_framework
from google.cloud import billing_v1
```

### Typing
- Use **Type Hints** for all function arguments and return values.
- Examples: `def get_project_id() -> str:`, `def stop_billing(cloud_event: CloudEvent) -> None:`

### Naming Conventions
- **Variables & Functions:** `snake_case` (e.g., `stop_billing`, `cost_amount`).
- **Constants:** `UPPER_CASE` (e.g., `SIMULATE_DEACTIVATION`, `PROJECT_ID`).
- **Classes:** `PascalCase` (if any are added).

### Docstrings
- Use **Google Style** docstrings for functions.
- Include `Args`, `Returns`, and `Raises` sections where applicable.

Example:
```python
def _is_billing_enabled(project_name: str) -> bool:
    """Determine whether billing is enabled for a project.

    Args:
        project_name: Name of project to check if billing is enabled.

    Returns:
        Whether project has billing enabled or not.
    """
```

### Error Handling & Logging
- **Logging:** Use `google.cloud.logging` for critical audit logs and standard `print()` for Cloud Run execution logs (which show up in Cloud Logging).
- **Exceptions:** Use `try...except` blocks to handle external API failures (e.g., `billing_client` calls).
- **Graceful Failure:** If the project ID cannot be determined or permissions are missing, raise informative exceptions or log errors clearly without crashing the entire service if possible.

### Project Structure
- `main.py`: Contains the core logic and Cloud Function entry point (`stop_billing`).
- `verify-billing-protection.sh`: Infrastructure validation script.
- `requirements.txt`: Python dependencies.

## 3. Workflow for Agents

1.  **Analyze:** detailedly read `main.py` and `README.md` to understand the flow.
2.  **Safety Check:** Check the `SIMULATE_DEACTIVATION` constant in `main.py`.
3.  **Implement:** specific changes or refactoring. Use the established patterns for Google Cloud client usage.
4.  **Verify:** Since there are no unit tests, review the code logic carefully. If modifying infrastructure, verify against `verify-billing-protection.sh` logic.
5.  **Documentation:** Update `README.md` if deployment steps or prerequisites change.
