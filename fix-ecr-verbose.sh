#!/bin/bash
set -e

REGION="ap-southeast-2"
echo "=== Fixing ECR Permissions for region: $REGION ==="
echo ""

# Step 1: Get ECR ARN with error handling
echo "1. Getting ECR repository ARN..."
ECR_OUTPUT=$(aws ecr describe-repositories --repository-names bee-edu-rag-app --region $REGION 2>&1)

if echo "$ECR_OUTPUT" | grep -q "RepositoryNotFoundException"; then
  echo "❌ ECR repository not found in $REGION!"
  echo ""
  echo "Let's check what repositories exist:"
  aws ecr describe-repositories --region $REGION --query 'repositories[*].[repositoryName,repositoryUri]' --output table
  exit 1
fi

ECR_ARN=$(echo "$ECR_OUTPUT" | jq -r '.repositories[0].repositoryArn' 2>/dev/null || echo "")

if [ -z "$ECR_ARN" ] || [ "$ECR_ARN" == "null" ]; then
  echo "❌ Could not extract ECR ARN from output:"
  echo "$ECR_OUTPUT"
  exit 1
fi

echo "   ✅ ECR ARN: $ECR_ARN"

# Step 2: Get Secret ARN
echo ""
echo "2. Getting Secret ARN..."
SECRET_OUTPUT=$(aws secretsmanager describe-secret --secret-id bee-edu-openai-key-secret --region $REGION 2>&1)

if echo "$SECRET_OUTPUT" | grep -q "ResourceNotFoundException"; then
  echo "❌ Secret not found in $REGION!"
  echo "   Output: $SECRET_OUTPUT"
  exit 1
fi

SECRET_ARN=$(echo "$SECRET_OUTPUT" | jq -r '.ARN' 2>/dev/null || echo "")
if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" == "null" ]; then
  echo "❌ Could not extract Secret ARN"
  exit 1
fi
echo "   ✅ Secret ARN: $SECRET_ARN"

# Step 3: Get Policy ARN
echo ""
echo "3. Getting Policy ARN..."
POLICY_OUTPUT=$(aws iam get-policy --policy-name github-actions-deploy-policy 2>&1)

if echo "$POLICY_OUTPUT" | grep -q "NoSuchEntity"; then
  echo "❌ Policy not found!"
  echo "   Output: $POLICY_OUTPUT"
  exit 1
fi

POLICY_ARN=$(echo "$POLICY_OUTPUT" | jq -r '.Policy.Arn' 2>/dev/null || echo "")
if [ -z "$POLICY_ARN" ] || [ "$POLICY_ARN" == "null" ]; then
  echo "❌ Could not extract Policy ARN"
  exit 1
fi
echo "   ✅ Policy ARN: $POLICY_ARN"

# Step 4: Create the policy
echo ""
echo "4. Creating updated policy..."
cat > /tmp/policy-update.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
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
      "Action": ["iam:PassRole", "iam:GetRole"],
      "Resource": [
        "arn:aws:iam::280749937789:role/bee-edu-apprunner-instance-role",
        "arn:aws:iam::280749937789:role/bee-edu-apprunner-role"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"],
      "Resource": "${SECRET_ARN}"
    }
  ]
}
EOF

echo "   Policy document created"
echo "   ECR ARN in policy: $ECR_ARN"

# Step 5: Update policy
echo ""
echo "5. Updating policy..."
UPDATE_OUTPUT=$(aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document file:///tmp/policy-update.json \
  --set-as-default 2>&1)

if [ $? -eq 0 ]; then
  echo "   ✅ Policy updated successfully!"
else
  echo "   ❌ Failed to update policy:"
  echo "$UPDATE_OUTPUT"
  exit 1
fi

# Step 6: Verify attachment
echo ""
echo "6. Verifying policy attachment..."
ATTACHED=$(aws iam list-attached-role-policies --role-name github-actions-deploy-role --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN']" --output text 2>&1)
if [ -z "$ATTACHED" ]; then
  echo "   ⚠️  Not attached, attaching now..."
  aws iam attach-role-policy --role-name github-actions-deploy-role --policy-arn $POLICY_ARN
  echo "   ✅ Attached"
else
  echo "   ✅ Already attached"
fi

echo ""
echo "=== Summary ==="
echo "ECR Repository ARN: $ECR_ARN"
echo "Region: $REGION"
echo "Policy ARN: $POLICY_ARN"
echo ""
echo "✅ Done! Wait 30-60 seconds, then retry GitHub Actions."
echo ""
echo "⚠️  Make sure GitHub Secret AWS_REGION = $REGION"

