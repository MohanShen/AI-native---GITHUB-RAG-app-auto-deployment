# 🚀 Setup Checklist - GitHub & AWS Configuration

This guide walks you through exactly what you need to set up on AWS and GitHub.

## Prerequisites

Before starting, ensure you have:
- ✅ AWS Account with AWS CLI configured
- ✅ GitHub Account and repository created
- ✅ Terraform installed
- ✅ OpenAI API Key ready
- ✅ Cloudflare account (for custom domain - optional but recommended)

---

## Part 1: AWS Setup (Using Terraform)

### Step 1.1: Prepare Your Values

Gather these values:
- **GitHub Username/Org**: Your GitHub username or organization name
- **GitHub Repo Name**: The name of your repository
- **OpenAI API Key**: Your OpenAI API key (starts with `sk-`)
- **AWS Region**: Default is `us-east-1` (can be changed in `main.tf`)

### Step 1.2: Run Terraform

```bash
# Navigate to the project directory
cd AI-native---GITHUB-RAG-app-auto-deployment

# Set environment variables (replace with your values)
export TF_VAR_github_org_or_user="your-github-username"
export TF_VAR_github_repo_name="your-repo-name"
export TF_VAR_openai_api_key="sk-your-openai-api-key"

# Initialize Terraform
terraform init

# Review what will be created
terraform plan

# Apply the configuration (creates all AWS resources)
terraform apply
```

### Step 1.3: Save Terraform Outputs

After `terraform apply` completes, save these output values (you'll need them for GitHub):

```bash
# Get all outputs
terraform output

# Or get individual values:
terraform output github_actions_role_arn
terraform output ecr_repository_name
terraform output apprunner_service_arn
```

**What Terraform Creates in AWS:**
- ✅ OIDC Identity Provider (for GitHub Actions authentication)
- ✅ IAM Role for GitHub Actions (`github-actions-deploy-role`)
- ✅ IAM Policy with necessary permissions
- ✅ ECR Repository (`bee-edu-rag-app`)
- ✅ Secrets Manager Secret (`bee-edu-openai-key-secret`) with your OpenAI API key
- ✅ IAM Roles for App Runner (access role and instance role)
- ⚠️ **App Runner Service** - NOT created by Terraform (will be created by GitHub Actions on first deployment)

---

## Part 2: GitHub Setup

### Step 2.1: Push Code to GitHub

```bash
# Initialize git if not already done
git init

# Add all files
git add .

# Commit
git commit -m "Initial commit with CI/CD pipeline"

# Add your GitHub remote (replace with your repo URL)
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git

# Push to main branch
git push -u origin main
```

### Step 2.2: Configure GitHub Secrets

Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these **4 secrets**:

| Secret Name | Value | Where to Get It |
|------------|-------|----------------|
| `AWS_REGION` | `us-east-1` (or your AWS region) | From `main.tf` or your preference |
| `ECR_REPOSITORY` | `bee-edu-rag-app` | From `terraform output ecr_repository_name` |
| `APP_RUNNER_ARN` | `arn:aws:apprunner:...` | From `terraform output apprunner_service_arn` (may be `null` initially) |
| `AWS_IAM_ROLE_TO_ASSUME` | `arn:aws:iam::...` | From `terraform output github_actions_role_arn` |

**Important Notes:**
- If `APP_RUNNER_ARN` is `null` (because service doesn't exist yet), you can:
  - Leave it empty or set a placeholder value
  - After first deployment, get it from AWS App Runner console and update the secret
  - The workflow can work without it initially (it will create the service)

### Step 2.3: Verify Workflow File

Ensure `.github/workflows/deploy.yml` exists in your repository. It should be automatically included when you push the code.

---

## Part 3: First Deployment

### Step 3.1: Trigger the Workflow

The workflow automatically triggers when you push to `main` branch. If you've already pushed, you can:

1. Make a small change and push again, OR
2. Go to **Actions** tab → Select the workflow → **Run workflow**

### Step 3.2: Monitor the Deployment

1. Go to **Actions** tab in GitHub
2. Click on the running workflow
3. Watch the logs to see:
   - ✅ Code checkout
   - ✅ AWS authentication (OIDC)
   - ✅ ECR login
   - ✅ Docker build and push
   - ✅ App Runner deployment

### Step 3.3: Get App Runner Service ARN (if needed)

After first successful deployment:

1. Go to **AWS Console** → **App Runner**
2. Find your service (`bee-edu-rag-service`)
3. Copy the **Service ARN**
4. Update the `APP_RUNNER_ARN` secret in GitHub with this value

---

## Part 4: Cloudflare Setup (Optional but Recommended)

### Step 4.1: Get App Runner URL

1. Go to **AWS Console** → **App Runner**
2. Click on your service
3. Copy the **Default domain** (format: `xxxxx.us-east-1.awsapprunner.com`)

### Step 4.2: Configure Cloudflare DNS

1. Log in to **Cloudflare Dashboard**
2. Select your domain
3. Go to **DNS** → **Records**
4. Click **Add record**:
   - **Type**: `CNAME`
   - **Name**: `rag` (or your preferred subdomain)
   - **Target**: `xxxxx.us-east-1.awsapprunner.com` (the App Runner domain)
   - **Proxy status**: Proxied (orange cloud) or DNS only (gray cloud)
5. Click **Save**

### Step 4.3: Test Your Domain

Wait a few minutes for DNS propagation, then visit:
- `https://rag.yourdomain.com` (or your chosen subdomain)

---

## Verification Checklist

After setup, verify everything works:

### AWS Verification:
- [ ] OIDC Provider exists in IAM → Identity providers
- [ ] IAM Role `github-actions-deploy-role` exists
- [ ] ECR Repository `bee-edu-rag-app` exists
- [ ] Secret `bee-edu-openai-key-secret` exists in Secrets Manager
- [ ] App Runner service `bee-edu-rag-service` exists (after first deployment)

### GitHub Verification:
- [ ] All 4 secrets are configured
- [ ] Workflow file exists at `.github/workflows/deploy.yml`
- [ ] Workflow runs successfully when pushing to `main`
- [ ] No errors in workflow logs

### Application Verification:
- [ ] App Runner service is running
- [ ] Can access the default App Runner URL
- [ ] Custom domain works (if configured)
- [ ] Application responds to requests

---

## Troubleshooting

### Issue: Terraform fails with "OIDC provider already exists"
**Solution**: This is normal if you've run Terraform before. The provider is shared across all repos. You can ignore this or import the existing provider.

### Issue: GitHub Actions fails with "Access Denied"
**Solution**: 
- Check that `AWS_IAM_ROLE_TO_ASSUME` secret is correct
- Verify the GitHub repo name matches what you set in Terraform variables
- Ensure you're pushing to the `main` branch (not `master`)

### Issue: Workflow fails at "Get App Runner service details"
**Solution**:
- If service doesn't exist yet, this is expected on first run
- The workflow will create the service automatically
- If it still fails, check IAM permissions include `iam:GetRole`

### Issue: Deployment succeeds but app doesn't work
**Solution**:
- Check App Runner service logs in AWS Console
- Verify the secret `bee-edu-openai-key-secret` exists and has the correct API key
- Check that the Docker image was built correctly

---

## Quick Reference: What Gets Created Where

### AWS Resources (via Terraform):
- OIDC Identity Provider
- IAM Roles (3 total: GitHub Actions, App Runner access, App Runner instance)
- IAM Policies
- ECR Repository
- Secrets Manager Secret

### AWS Resources (via GitHub Actions):
- App Runner Service (created on first deployment)
- Docker Images in ECR (created on each push)

### GitHub Configuration:
- Repository Secrets (4 secrets)
- Workflow file (`.github/workflows/deploy.yml`)

### Cloudflare Configuration:
- CNAME DNS record (manual setup)

---

## Next Steps

After successful setup:
1. ✅ Test the deployment by making a code change and pushing
2. ✅ Monitor costs in AWS (App Runner charges for running time)
3. ✅ Set up monitoring/alerts if needed
4. ✅ Consider adding staging environments
5. ✅ Review and optimize Docker image size

---

## Support

If you encounter issues:
1. Check the workflow logs in GitHub Actions
2. Check AWS CloudWatch logs for App Runner
3. Verify all secrets are correctly set
4. Ensure Terraform outputs match GitHub secrets

