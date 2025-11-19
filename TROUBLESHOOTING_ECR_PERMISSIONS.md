# Troubleshooting ECR Permissions for GitHub Actions

## Step-by-Step Troubleshooting

### Step 1: Verify the Policy Document

Check what's actually in the policy:

```bash
# Get the policy ARN
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text)

# Get the current default version
VERSION_ID=$(aws iam get-policy --policy-arn $POLICY_ARN --query 'Policy.DefaultVersionId' --output text)

# View the actual policy document
aws iam get-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id $VERSION_ID \
  --query 'PolicyVersion.Document' | jq '.'
```

**What to check:**
- ✅ Does it include `ecr:InitiateLayerUpload`?
- ✅ Is the ECR repository ARN correct?
- ✅ Are all ECR actions present?

### Step 2: Verify Policy is Attached to Role

```bash
# Check if policy is attached to the role
aws iam list-attached-role-policies --role-name github-actions-deploy-role

# Should show:
# {
#   "AttachedPolicies": [
#     {
#       "PolicyName": "github-actions-deploy-policy",
#       "PolicyArn": "arn:aws:iam::280749937789:policy/github-actions-deploy-policy"
#     }
#   ]
# }
```

If it's NOT attached:
```bash
# Attach the policy
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text)
aws iam attach-role-policy \
  --role-name github-actions-deploy-role \
  --policy-arn $POLICY_ARN
```

### Step 3: Verify ECR Repository ARN Matches

```bash
# Get the actual ECR repository ARN
ECR_ARN=$(aws ecr describe-repositories --repository-names bee-edu-rag-app --query 'repositories[0].repositoryArn' --output text)
echo "ECR Repository ARN: $ECR_ARN"

# Check what's in the policy
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text)
VERSION_ID=$(aws iam get-policy --policy-arn $POLICY_ARN --query 'Policy.DefaultVersionId' --output text)
aws iam get-policy-version --policy-arn $POLICY_ARN --version-id $VERSION_ID --query 'PolicyVersion.Document' | jq '.Statement[] | select(.Action[] | contains("InitiateLayerUpload")) | .Resource'
```

**The ARNs must match exactly!** The error message shows the repository ARN - compare it with what's in the policy.

### Step 4: Check for Policy Version Limit

AWS IAM has a limit of 5 policy versions. If you've hit the limit, delete old versions:

```bash
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text)

# List all versions
aws iam list-policy-versions --policy-arn $POLICY_ARN

# Delete old versions (keep only the default)
# Replace <VERSION_ID> with old version IDs
aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id <VERSION_ID>
```

### Step 5: Force Policy Update with Exact ARN

If the ARN doesn't match, update the policy with the exact ARN from the error:

```bash
# The error shows: arn:aws:ecr:***:280749937789:repository/***
# Replace *** with your actual region (probably us-east-1)
# Replace the last *** with your actual repository name (probably bee-edu-rag-app)

# Get the exact ARN from the error or from ECR
ECR_ARN=$(aws ecr describe-repositories --repository-names bee-edu-rag-app --query 'repositories[0].repositoryArn' --output text)
echo "Using ECR ARN: $ECR_ARN"

# Get other ARNs
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id bee-edu-openai-key-secret --query 'ARN' --output text)
INSTANCE_ROLE_ARN=$(aws iam get-role --role-name bee-edu-apprunner-instance-role --query 'Role.Arn' --output text)
SERVICE_ROLE_ARN=$(aws iam get-role --role-name bee-edu-apprunner-role --query 'Role.Arn' --output text)

# Create updated policy
cat > /tmp/github-actions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ],
      "Resource": "${ECR_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "apprunner:StartDeployment",
        "apprunner:DescribeService",
        "apprunner:UpdateService",
        "apprunner:ListOperations",
        "apprunner:ListServices",
        "apprunner:CreateService"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole",
        "iam:GetRole"
      ],
      "Resource": [
        "${INSTANCE_ROLE_ARN}",
        "${SERVICE_ROLE_ARN}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "${SECRET_ARN}"
    }
  ]
}
EOF

# Update the policy
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text)
aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document file:///tmp/github-actions-policy.json \
  --set-as-default

# Verify it was updated
VERSION_ID=$(aws iam get-policy --policy-arn $POLICY_ARN --query 'Policy.DefaultVersionId' --output text)
aws iam get-policy-version --policy-arn $POLICY_ARN --version-id $VERSION_ID --query 'PolicyVersion.Document' | jq '.'
```

### Step 6: Test the Permissions Directly

Simulate what GitHub Actions is doing:

```bash
# Assume the role (if you have permission)
# Get temporary credentials as the role
aws sts assume-role \
  --role-arn arn:aws:iam::280749937789:role/github-actions-deploy-role \
  --role-session-name test-session

# Use the credentials to test ECR access
# (This is complex, so skip if not needed)
```

### Step 7: Check IAM Propagation

IAM changes can take up to a few minutes to propagate. After updating:

1. Wait 30-60 seconds
2. Verify the policy again (Step 1)
3. Re-run GitHub Actions

### Step 8: Check for Conflicting Policies

Check if there are any other policies attached that might be denying access:

```bash
# List all attached policies
aws iam list-attached-role-policies --role-name github-actions-deploy-role

# List inline policies
aws iam list-role-policies --role-name github-actions-deploy-role

# Check for any deny statements in the role's trust policy
aws iam get-role --role-name github-actions-deploy-role --query 'Role.AssumeRolePolicyDocument'
```

### Step 9: Verify OIDC Trust Relationship

Make sure the role can be assumed by GitHub Actions:

```bash
aws iam get-role --role-name github-actions-deploy-role --query 'Role.AssumeRolePolicyDocument' | jq '.'
```

Should show:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::280749937789:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USER/YOUR_REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

## Common Issues and Solutions

### Issue 1: Policy ARN doesn't match ECR ARN
**Solution:** Use the exact ARN from the error message or get it from ECR:
```bash
aws ecr describe-repositories --repository-names bee-edu-rag-app --query 'repositories[0].repositoryArn' --output text
```

### Issue 2: Policy not attached to role
**Solution:** Attach it:
```bash
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text)
aws iam attach-role-policy --role-name github-actions-deploy-role --policy-arn $POLICY_ARN
```

### Issue 3: IAM propagation delay
**Solution:** Wait 30-60 seconds after updating, then retry

### Issue 4: Policy version limit reached
**Solution:** Delete old versions (see Step 4)

### Issue 5: Wrong region in ARN
**Solution:** Make sure the region in the ECR ARN matches your actual region (us-east-1, etc.)

## Quick Diagnostic Script

Run this to check everything at once:

```bash
#!/bin/bash
echo "=== Checking GitHub Actions Role Permissions ==="
echo ""

# Check policy exists
echo "1. Checking if policy exists..."
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text 2>/dev/null)
if [ -z "$POLICY_ARN" ]; then
  echo "❌ Policy not found!"
  exit 1
else
  echo "✅ Policy found: $POLICY_ARN"
fi

# Check policy is attached
echo ""
echo "2. Checking if policy is attached to role..."
ATTACHED=$(aws iam list-attached-role-policies --role-name github-actions-deploy-role --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN']" --output text)
if [ -z "$ATTACHED" ]; then
  echo "❌ Policy NOT attached to role!"
  echo "   Run: aws iam attach-role-policy --role-name github-actions-deploy-role --policy-arn $POLICY_ARN"
else
  echo "✅ Policy is attached to role"
fi

# Check policy content
echo ""
echo "3. Checking policy content..."
VERSION_ID=$(aws iam get-policy --policy-arn $POLICY_ARN --query 'Policy.DefaultVersionId' --output text)
POLICY_DOC=$(aws iam get-policy-version --policy-arn $POLICY_ARN --version-id $VERSION_ID --query 'PolicyVersion.Document' --output json)

if echo "$POLICY_DOC" | jq -e '.Statement[] | select(.Action[]? | contains("ecr:InitiateLayerUpload"))' > /dev/null; then
  echo "✅ Policy contains ecr:InitiateLayerUpload"
else
  echo "❌ Policy does NOT contain ecr:InitiateLayerUpload"
fi

# Check ECR ARN
echo ""
echo "4. Checking ECR repository ARN..."
ECR_ARN=$(aws ecr describe-repositories --repository-names bee-edu-rag-app --query 'repositories[0].repositoryArn' --output text 2>/dev/null)
if [ -z "$ECR_ARN" ]; then
  echo "❌ ECR repository not found!"
else
  echo "✅ ECR Repository ARN: $ECR_ARN"
  
  # Check if policy uses this ARN
  if echo "$POLICY_DOC" | jq -e ".Statement[] | select(.Resource[]? | contains(\"$ECR_ARN\"))" > /dev/null; then
    echo "✅ Policy references correct ECR ARN"
  else
    echo "❌ Policy does NOT reference the correct ECR ARN"
    echo "   Policy should use: $ECR_ARN"
  fi
fi

echo ""
echo "=== Diagnostic Complete ==="
```

Save this as `check-permissions.sh`, make it executable (`chmod +x check-permissions.sh`), and run it.

