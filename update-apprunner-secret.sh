#!/bin/bash
set -e

REGION="us-east-1"
SERVICE_ARN="arn:aws:apprunner:us-east-1:280749937789:service/bee-edu-rag-service/5ff04f32a958429eaafdb7b6a046afc7"

echo "=== Updating App Runner Service with Secret ==="
echo ""

# Step 1: Get the secret ARN
echo "1. Getting Secret ARN..."
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id bee-edu-openai-key-secret --region $REGION --query 'ARN' --output text)
echo "   ✅ Secret ARN: $SECRET_ARN"

# Step 2: Get current service configuration
echo ""
echo "2. Getting current service configuration..."
SERVICE_INFO=$(aws apprunner describe-service --service-arn "$SERVICE_ARN" --region $REGION --output json)

# Extract current configuration
ACCESS_ROLE_ARN=$(echo "$SERVICE_INFO" | jq -r '.Service.SourceConfiguration.AuthenticationConfiguration.AccessRoleArn')
INSTANCE_ROLE_ARN=$(echo "$SERVICE_INFO" | jq -r '.Service.InstanceConfiguration.InstanceRoleArn')
IMAGE_IDENTIFIER=$(echo "$SERVICE_INFO" | jq -r '.Service.SourceConfiguration.ImageRepository.ImageIdentifier')
PORT=$(echo "$SERVICE_INFO" | jq -r '.Service.SourceConfiguration.ImageRepository.ImageConfiguration.Port // "8080"')
CPU=$(echo "$SERVICE_INFO" | jq -r '.Service.InstanceConfiguration.Cpu // "1024"')
MEMORY=$(echo "$SERVICE_INFO" | jq -r '.Service.InstanceConfiguration.Memory // "2048"')

echo "   Access Role: $ACCESS_ROLE_ARN"
echo "   Instance Role: $INSTANCE_ROLE_ARN"
echo "   Image: $IMAGE_IDENTIFIER"
echo "   Port: $PORT"
echo "   CPU: $CPU"
echo "   Memory: $MEMORY"

# Step 3: Create update configuration
echo ""
echo "3. Creating update configuration with secret..."
cat > /tmp/apprunner-update.json << EOF
{
  "SourceConfiguration": {
    "AuthenticationConfiguration": {
      "AccessRoleArn": "${ACCESS_ROLE_ARN}"
    },
    "ImageRepository": {
      "ImageIdentifier": "${IMAGE_IDENTIFIER}",
      "ImageRepositoryType": "ECR",
      "ImageConfiguration": {
        "Port": "${PORT}",
        "RuntimeEnvironmentSecrets": {
          "OPENAI_API_KEY": "${SECRET_ARN}"
        }
      }
    },
    "AutoDeploymentsEnabled": false
  },
  "InstanceConfiguration": {
    "Cpu": "${CPU}",
    "Memory": "${MEMORY}",
    "InstanceRoleArn": "${INSTANCE_ROLE_ARN}"
  }
}
EOF

echo "   Update configuration created"

# Step 4: Update the service
echo ""
echo "4. Updating App Runner service..."
aws apprunner update-service \
  --service-arn "$SERVICE_ARN" \
  --region $REGION \
  --source-configuration file:///tmp/apprunner-update.json \
  --instance-configuration file:///tmp/apprunner-update.json \
  --output json

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Service update initiated!"
  echo ""
  echo "The service will redeploy with the secret configured."
  echo "This may take a few minutes. Check the App Runner console for status."
else
  echo "❌ Failed to update service"
  exit 1
fi

