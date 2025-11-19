#!/bin/bash
set -e

echo "=== Finding ECR Repository and Fixing Permissions ==="
echo ""

# Step 1: Try to find the ECR repository in different regions
echo "1. Searching for ECR repository..."
REGIONS=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1")

ECR_ARN=""
ECR_REGION=""

for region in "${REGIONS[@]}"; do
  echo "   Checking region: $region"
  ARN=$(aws ecr describe-repositories --repository-names bee-edu-rag-app --region $region --query 'repositories[0].repositoryArn' --output text 2>/dev/null)
  if [ ! -z "$ARN" ] && [ "$ARN" != "None" ]; then
    ECR_ARN="$ARN"
    ECR_REGION="$region"
    echo "   ✅ Found in region: $region"
    break
  fi
done

# If not found, try listing all repositories
if [ -z "$ECR_ARN" ]; then
  echo "   Trying to list all repositories..."
  for region in "${REGIONS[@]}"; do
    REPOS=$(aws ecr describe-repositories --region $region --query 'repositories[?repositoryName==`bee-edu-rag-app`].[repositoryArn]' --output text 2>/dev/null)
    if [ ! -z "$REPOS" ]; then
      ECR_ARN="$REPOS"
      ECR_REGION="$region"
      echo "   ✅ Found in region: $region"
      break
    fi
  done
fi

if [ -z "$ECR_ARN" ]; then
  echo "❌ Could not find ECR repository!"
  echo "   Try: aws ecr describe-repositories --region us-east-1"
  exit 1
fi

echo "   ✅ ECR ARN: $ECR_ARN"
echo "   ✅ Region: $ECR_REGION"

# Step 2: Get Secret ARN
echo ""
echo "2. Getting Secret ARN..."
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id bee-edu-openai-key-secret --region $ECR_REGION --query 'ARN' --output text 2>&1)
if echo "$SECRET_ARN" | grep -q "ResourceNotFoundException"; then
  # Try default region
  SECRET_ARN=$(aws secretsmanager describe-secret --secret-id bee-edu-openai-key-secret --query 'ARN' --output text 2>&1)
fi
if echo "$SECRET_ARN" | grep -q "ResourceNotFoundException"; then
  echo "❌ Secret not found!"
  exit 1
fi
echo "   ✅ Secret ARN: $SECRET_ARN"

# Step 3: Get Policy ARN
echo ""
echo "3. Getting Policy ARN..."
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text 2>&1)
if echo "$POLICY_ARN" | grep -q "NoSuchEntity"; then
  echo "❌ Policy not found!"
  exit 1
fi
echo "   ✅ Policy ARN: $POLICY_ARN"

# Step 4: Create the policy with EXACT ARN
echo ""
echo "4. Creating updated policy with EXACT ECR ARN..."
cat > /tmp/policy-final.json << EOF
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

echo "   Policy document:"
cat /tmp/policy-final.json | jq '.'

# Step 5: Update policy
echo ""
echo "5. Updating policy..."
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

# Step 7: Verify the update
echo ""
echo "7. Verifying update..."
NEW_VERSION_ID=$(aws iam get-policy --policy-arn $POLICY_ARN --query 'Policy.DefaultVersionId' --output text)
UPDATED_POLICY=$(aws iam get-policy-version --policy-arn $POLICY_ARN --version-id $NEW_VERSION_ID --query 'PolicyVersion.Document' --output json)

echo "   ECR ARN in updated policy:"
echo "$UPDATED_POLICY" | jq -r '.Statement[] | select(.Action[]? | contains("ecr:InitiateLayerUpload")) | .Resource[]?' | grep -v "*"

echo ""
echo "=== Summary ==="
echo "ECR Repository ARN: $ECR_ARN"
echo "ECR Region: $ECR_REGION"
echo "Policy ARN: $POLICY_ARN"
echo "Policy Version: $NEW_VERSION_ID"
echo ""
echo "✅ Done! Wait 30-60 seconds for IAM propagation, then retry GitHub Actions."
echo ""
echo "IMPORTANT: Make sure your GitHub Secret AWS_REGION is set to: $ECR_REGION"

