#!/bin/bash
set -e

echo "=== Checking and Fixing ECR Permissions ==="
echo ""

# Step 1: Check if ECR repository exists
echo "1. Checking ECR repository..."
ECR_ARN=$(aws ecr describe-repositories --repository-names bee-edu-rag-app --query 'repositories[0].repositoryArn' --output text 2>&1)

if echo "$ECR_ARN" | grep -q "RepositoryNotFoundException"; then
  echo "❌ ECR repository does NOT exist!"
  echo ""
  echo "You need to create it first. Options:"
  echo ""
  echo "Option A: Run Terraform (recommended)"
  echo "  export TF_VAR_github_org_or_user=\"your-github-username\""
  echo "  export TF_VAR_github_repo_name=\"your-repo-name\""
  echo "  export TF_VAR_openai_api_key=\"sk-your-key\""
  echo "  terraform apply"
  echo ""
  echo "Option B: Create ECR repository manually"
  echo "  aws ecr create-repository --repository-name bee-edu-rag-app --region us-east-1"
  exit 1
fi

if [ -z "$ECR_ARN" ] || [ "$ECR_ARN" == "None" ]; then
  echo "❌ Could not get ECR ARN"
  exit 1
fi

echo "   ✅ ECR ARN: $ECR_ARN"

# Step 2: Get Secret ARN
echo ""
echo "2. Getting Secret ARN..."
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id bee-edu-openai-key-secret --query 'ARN' --output text 2>&1)
if echo "$SECRET_ARN" | grep -q "ResourceNotFoundException"; then
  echo "❌ Secret not found! Run terraform apply first."
  exit 1
fi
echo "   ✅ Secret ARN: $SECRET_ARN"

# Step 3: Get Policy ARN
echo ""
echo "3. Getting Policy ARN..."
POLICY_ARN=$(aws iam get-policy --policy-name github-actions-deploy-policy --query 'Policy.Arn' --output text 2>&1)
if echo "$POLICY_ARN" | grep -q "NoSuchEntity"; then
  echo "❌ Policy not found! Run terraform apply first."
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

# Step 5: Update policy
echo "5. Updating policy..."
aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document file:///tmp/policy-update.json \
  --set-as-default

echo "   ✅ Policy updated!"

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
echo "=== Done ==="
echo "ECR ARN in policy: $ECR_ARN"
echo "Wait 30-60 seconds, then retry GitHub Actions."

