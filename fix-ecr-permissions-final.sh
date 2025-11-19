#!/bin/bash
set -e

echo "=== Final ECR Permissions Fix ==="
echo ""

# Step 1: Get the EXACT ECR repository ARN
echo "1. Getting ECR repository ARN..."
ECR_ARN=$(aws ecr describe-repositories --repository-names bee-edu-rag-app --query 'repositories[0].repositoryArn' --output text 2>/dev/null)

if [ -z "$ECR_ARN" ] || [ "$ECR_ARN" == "None" ]; then
  echo "❌ ECR repository not found!"
  echo "   Run: terraform apply"
  exit 1
fi

echo "   ✅ ECR ARN: $ECR_ARN"

# Step 2: Get the region from ECR ARN
REGION=$(echo $ECR_ARN | cut -d: -f4)
echo "   Region: $REGION"

# Step 3: Get Secret ARN
echo ""
echo "2. Getting Secret ARN..."
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id bee-edu-openai-key-secret --query 'ARN' --output text 2>/dev/null)
if [ -z "$SECRET_ARN" ]; then
  echo "❌ Secret not found!"
  exit 1
fi
echo "   ✅ Secret ARN: $SECRET_ARN"

# Step 4: Get Policy ARN
echo ""
echo "3. Getting Policy ARN..."
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text 2>/dev/null)
if [ -z "$POLICY_ARN" ]; then
  echo "❌ Policy not found!"
  exit 1
fi
echo "   ✅ Policy ARN: $POLICY_ARN"

# Step 5: Check current policy
echo ""
echo "4. Checking current policy..."
VERSION_ID=$(aws iam get-policy --policy-arn $POLICY_ARN --query 'Policy.DefaultVersionId' --output text)
CURRENT_POLICY=$(aws iam get-policy-version --policy-arn $POLICY_ARN --version-id $VERSION_ID --query 'PolicyVersion.Document' --output json)

echo "   Current policy ECR resource:"
echo "$CURRENT_POLICY" | jq -r '.Statement[] | select(.Action[]? | contains("ecr:InitiateLayerUpload")) | .Resource[]?' | grep -v "*" || echo "   (not found)"

# Step 6: Create the CORRECT policy with EXACT ARNs
echo ""
echo "5. Creating updated policy with EXACT ARNs..."

cat > /tmp/policy-final.json << EOF
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
        "arn:aws:iam::280749937789:role/bee-edu-apprunner-instance-role",
        "arn:aws:iam::280749937789:role/bee-edu-apprunner-role"
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

echo "   Policy document created. Contents:"
cat /tmp/policy-final.json | jq '.'

# Step 7: Check for policy version limit
echo ""
echo "6. Checking policy versions..."
VERSION_COUNT=$(aws iam list-policy-versions --policy-arn $POLICY_ARN --query 'length(Versions)' --output text)
echo "   Current versions: $VERSION_COUNT/5"

if [ "$VERSION_COUNT" -ge 5 ]; then
  echo "   ⚠️  Policy version limit reached. Deleting oldest non-default versions..."
  aws iam list-policy-versions --policy-arn $POLICY_ARN --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text | tr '\t' '\n' | head -n -1 | while read version; do
    if [ ! -z "$version" ]; then
      echo "   Deleting version: $version"
      aws iam delete-policy-version --policy-arn $POLICY_ARN --version-id $version 2>/dev/null || true
    fi
  done
fi

# Step 8: Update the policy
echo ""
echo "7. Updating policy..."
aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document file:///tmp/policy-final.json \
  --set-as-default

if [ $? -eq 0 ]; then
  echo "   ✅ Policy updated successfully!"
else
  echo "   ❌ Failed to update policy"
  exit 1
fi

# Step 9: Verify the update
echo ""
echo "8. Verifying update..."
NEW_VERSION_ID=$(aws iam get-policy --policy-arn $POLICY_ARN --query 'Policy.DefaultVersionId' --output text)
UPDATED_POLICY=$(aws iam get-policy-version --policy-arn $POLICY_ARN --version-id $NEW_VERSION_ID --query 'PolicyVersion.Document' --output json)

echo "   Updated policy ECR resource:"
echo "$UPDATED_POLICY" | jq -r '.Statement[] | select(.Action[]? | contains("ecr:InitiateLayerUpload")) | .Resource[]?' | grep -v "*"

# Step 10: Verify policy is attached
echo ""
echo "9. Verifying policy attachment..."
ATTACHED=$(aws iam list-attached-role-policies --role-name github-actions-deploy-role --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN']" --output text)
if [ -z "$ATTACHED" ]; then
  echo "   ⚠️  Policy not attached! Attaching now..."
  aws iam attach-role-policy --role-name github-actions-deploy-role --policy-arn $POLICY_ARN
  echo "   ✅ Policy attached"
else
  echo "   ✅ Policy is attached to role"
fi

echo ""
echo "=== Summary ==="
echo "ECR ARN used in policy: $ECR_ARN"
echo "Policy ARN: $POLICY_ARN"
echo "Policy version: $NEW_VERSION_ID"
echo ""
echo "✅ Done! Wait 30-60 seconds for IAM propagation, then retry GitHub Actions."
echo ""
echo "To verify, run:"
echo "  aws iam get-policy-version --policy-arn $POLICY_ARN --version-id $NEW_VERSION_ID --query 'PolicyVersion.Document' | jq '.'"

