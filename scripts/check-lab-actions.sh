#!/usr/bin/env bash
# Read-only prerequisites for the GitHub runner. Never prints credential values.
set -euo pipefail
for task_key in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  if [[ -z "${!task_key:-}" ]]; then
    echo "::error::Missing $task_key. Update all three repository secrets from the active Lab session."
    exit 1
  fi
done

TASK_IDENTITY="$(aws sts get-caller-identity --output json --no-cli-pager)"
python3 - "$TASK_IDENTITY" <<'PY'
import json
import sys

identity = json.loads(sys.argv[1])
if identity.get("Account") != "425959969184":
    sys.exit("::error::Wrong AWS account; use credentials from this Learner Lab.")
if not identity.get("Arn", "").startswith("arn:aws:sts::425959969184:assumed-role/voclabs/"):
    sys.exit("::error::Use the same voclabs role as CloudShell. A different IAM principal may not have EKS access.")
print("Active Learner Lab session: account 425959969184, role voclabs.")
PY

command -v terraform >/dev/null
command -v kubectl >/dev/null
command -v python3 >/dev/null
