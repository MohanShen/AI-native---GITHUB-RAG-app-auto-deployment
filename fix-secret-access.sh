#!/bin/bash
set -e

REGION="us-east-1"
echo "=== Fixing Secret Access for App Runner ==="
echo ""

# Step 1: Check if secret exists in us-east-1
echo "1. Checking Secret in $REGION..."
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id bee-edu-openai-key-secret --region $REGION --query 'ARN' --output text 2>&1)

if echo "$SECRET_ARN" | grep -q "ResourceNotFoundException"; then
  echo "❌ Secret not found in $REGION!"
  echo "   You may need to create it or it's in a different region"
  exit 1
fi

echo "   ✅ Secret ARN: $SECRET_ARN"

# Step 2: Check instance role permissions
echo ""
echo "2. Checking App Runner instance role permissions..."
INSTANCE_ROLE_ARN=$(aws iam get-role --role-name bee-edu-apprunner-instance-role --query 'Role.Arn' --output text 2>&1)

if echo "$INSTANCE_ROLE_ARN" | grep -q "NoSuchEntity"; then
  echo "❌ Instance role not found!"
  exit 1
fi

echo "   ✅ Instance Role ARN: $INSTANCE_ROLE_ARN"

# Step 3: Check current policy
echo ""
echo "3. Checking instance role policy..."
POLICY_DOC=$(aws iam get-role-policy --role-name bee-edu-apprunner-instance-role --policy-name apprunner-secrets-policy --query 'PolicyDocument' --output json 2>&1)

if echo "$POLICY_DOC" | grep -q "NoSuchEntity"; then
  echo "❌ Policy not found! Creating it..."
  
  # Create the policy
  cat > /tmp/instance-role-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "${SECRET_ARN}"
  }]
}
EOF
  
  aws iam put-role-policy \
    --role-name bee-edu-apprunner-instance-role \
    --policy-name apprunner-secrets-policy \
    --policy-document file:///tmp/instance-role-policy.json
  
  echo "   ✅ Policy created"
else
  echo "   ✅ Policy exists"
  echo "   Current policy:"
  echo "$POLICY_DOC" | jq '.'
  
  # Check if it has the correct secret ARN
  POLICY_SECRET=$(echo "$POLICY_DOC" | jq -r '.Statement[0].Resource' 2>/dev/null || echo "")
  if [ "$POLICY_SECRET" != "$SECRET_ARN" ]; then
    echo "   ⚠️  Policy has different secret ARN, updating..."
    cat > /tmp/instance-role-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "${SECRET_ARN}"
  }]
}
EOF
    
    aws iam put-role-policy \
      --role-name bee-edu-apprunner-instance-role \
      --policy-name apprunner-secrets-policy \
      --policy-document file:///tmp/instance-role-policy.json
    
    echo "   ✅ Policy updated"
  fi
fi

# Step 4: Check App Runner service configuration
echo ""
echo "4. Checking App Runner service configuration..."
SERVICE_ARN="arn:aws:apprunner:us-east-1:280749937789:service/bee-edu-rag-service/5ff04f32a958429eaafdb7b6a046afc7"

SERVICE_CONFIG=$(aws apprunner describe-service --service-arn "$SERVICE_ARN" --region $REGION --query 'Service.InstanceConfiguration' --output json 2>&1)

if echo "$SERVICE_CONFIG" | grep -q "NoSuchEntity"; then
  echo "❌ Service not found!"
  exit 1
fi

echo "   Service instance role:"
echo "$SERVICE_CONFIG" | jq '.InstanceRoleArn'

SERVICE_ROLE=$(echo "$SERVICE_CONFIG" | jq -r '.InstanceRoleArn' 2>/dev/null || echo "")
if [ "$SERVICE_ROLE" != "$INSTANCE_ROLE_ARN" ]; then
  echo "   ⚠️  Service is using different instance role!"
  echo "   Expected: $INSTANCE_ROLE_ARN"
  echo "   Actual: $SERVICE_ROLE"
fi

# Step 5: Check runtime environment secrets
echo ""
echo "5. Checking runtime environment secrets..."
SOURCE_CONFIG=$(aws apprunner describe-service --service-arn "$SERVICE_ARN" --region $REGION --query 'Service.SourceConfiguration.ImageRepository.ImageConfiguration.RuntimeEnvironmentSecrets' --output json 2>&1)

echo "   Runtime secrets configured:"
echo "$SOURCE_CONFIG" | jq '.'

if echo "$SOURCE_CONFIG" | jq -e 'has("OPENAI_API_KEY")' > /dev/null 2>&1; then
  CONFIGURED_SECRET=$(echo "$SOURCE_CONFIG" | jq -r '.OPENAI_API_KEY' 2>/dev/null || echo "")
  echo "   ✅ OPENAI_API_KEY is configured"
  echo "   Configured secret ARN: $CONFIGURED_SECRET"
  
  if [ "$CONFIGURED_SECRET" != "$SECRET_ARN" ]; then
    echo "   ⚠️  Secret ARN mismatch!"
    echo "   Expected: $SECRET_ARN"
    echo "   Configured: $CONFIGURED_SECRET"
    echo ""
    echo "   You need to redeploy the service with the correct secret ARN"
  fi
else
  echo "   ❌ OPENAI_API_KEY is NOT configured in the service!"
  echo "   You need to redeploy the service with the secret configured"
fi

echo ""
echo "=== Summary ==="
echo "Secret ARN: $SECRET_ARN"
echo "Instance Role ARN: $INSTANCE_ROLE_ARN"
echo ""
echo "If the secret is not configured in the service, you need to:"
echo "1. Update the GitHub Actions workflow to use the correct secret ARN"
echo "2. Redeploy the service (push to main branch or re-run workflow)"
echo ""
echo "Or manually update the service configuration via AWS Console:"
echo "  App Runner → bee-edu-rag-service → Configuration → Edit → Runtime environment secrets"

