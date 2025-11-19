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
  echo ""
  echo "   ECR Actions in policy:"
  echo "$POLICY_DOC" | jq '.Statement[] | select(.Action[]? | contains("ecr:")) | {Action: .Action, Resource: .Resource}'
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
  POLICY_ECR_ARN=$(echo "$POLICY_DOC" | jq -r '.Statement[] | select(.Action[]? | contains("ecr:InitiateLayerUpload")) | .Resource[]?' | grep -v "*" | head -1)
  if [ "$ECR_ARN" == "$POLICY_ECR_ARN" ]; then
    echo "✅ Policy uses correct ECR ARN"
  else
    echo "❌ Policy ARN mismatch!"
    echo "   Actual ECR ARN:  $ECR_ARN"
    echo "   Policy uses:     $POLICY_ECR_ARN"
    echo ""
    echo "   This is likely the problem! Update the policy with the correct ARN."
  fi
fi

# Show full policy for debugging
echo ""
echo "5. Full policy document:"
echo "$POLICY_DOC" | jq '.'

echo ""
echo "=== Diagnostic Complete ==="

