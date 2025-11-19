# 🖥️ How to Access AWS Terminal & Run Terraform

You have several options to run Terraform commands. Choose the one that works best for you.

---

## Option 1: AWS CloudShell (Easiest - No Installation Required) ⭐ Recommended

AWS CloudShell is a browser-based terminal that comes pre-configured with AWS CLI and many tools.

### Steps:

1. **Log in to AWS Console**
   - Go to https://console.aws.amazon.com
   - Sign in with your AWS account

2. **Open CloudShell**
   - Click the CloudShell icon in the top navigation bar (looks like `>_`)
   - Or search for "CloudShell" in the AWS Console search bar
   - Wait for CloudShell to initialize (first time may take 1-2 minutes)

3. **Upload Your Code to CloudShell**
   
   **Option A: Clone from GitHub (Recommended)**
   ```bash
   # If your code is already on GitHub
   git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
   cd YOUR_REPO_NAME/AI-native---GITHUB-RAG-app-auto-deployment
   ```

   **Option B: Upload Files**
   - Click the "Actions" menu (three dots) in CloudShell
   - Select "Upload file"
   - Upload your `main.tf` file and other project files
   - Or use `wget`/`curl` to download files

4. **Install Terraform in CloudShell**
   ```bash
   # Download Terraform
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   
   # Unzip
   unzip terraform_1.6.0_linux_amd64.zip
   
   # Make executable and move to PATH
   chmod +x terraform
   sudo mv terraform /usr/local/bin/
   
   # Verify installation
   terraform version
   ```

5. **Run Terraform Commands**
   ```bash
   # Set variables
   export TF_VAR_github_org_or_user="your-github-username"
   export TF_VAR_github_repo_name="your-repo-name"
   export TF_VAR_openai_api_key="sk-your-openai-api-key"
   
   # Initialize and apply
   terraform init
   terraform apply
   ```

**Pros:**
- ✅ No local installation needed
- ✅ Already authenticated with your AWS account
- ✅ Works from any computer with a browser
- ✅ Free to use

**Cons:**
- ⚠️ Limited storage (1GB home directory)
- ⚠️ Session timeout after 20 minutes of inactivity
- ⚠️ Need to re-upload files if session ends

---

## Option 2: Local Terminal (Your Computer)

Set up AWS CLI and Terraform on your local machine.

### Step 1: Install AWS CLI

**On macOS:**
```bash
# Using Homebrew (recommended)
brew install awscli

# Or download from AWS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

**On Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**On Windows:**
- Download MSI installer from: https://awscli.amazonaws.com/AWSCLIV2.msi
- Run the installer and follow prompts

### Step 2: Configure AWS Credentials

```bash
# Configure AWS CLI
aws configure
```

You'll be prompted for:
- **AWS Access Key ID**: Get from AWS Console → IAM → Users → Your User → Security credentials → Create access key
- **AWS Secret Access Key**: Shown only once when creating access key
- **Default region**: `us-east-1` (or your preferred region)
- **Default output format**: `json`

**Alternative: Using AWS SSO or IAM Roles**
```bash
# If using AWS SSO
aws configure sso

# If using IAM roles (for EC2 instances)
# Credentials are automatically provided via instance metadata
```

### Step 3: Install Terraform

**On macOS:**
```bash
brew install terraform
```

**On Linux:**
```bash
# Download and install
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

**On Windows:**
- Download from: https://releases.hashicorp.com/terraform/
- Extract and add to PATH

### Step 4: Verify Installation

```bash
# Check AWS CLI
aws --version

# Check Terraform
terraform version

# Test AWS connection
aws sts get-caller-identity
```

### Step 5: Run Terraform

```bash
# Navigate to project directory
cd AI-native---GITHUB-RAG-app-auto-deployment

# Set variables
export TF_VAR_github_org_or_user="your-github-username"
export TF_VAR_github_repo_name="your-repo-name"
export TF_VAR_openai_api_key="sk-your-openai-api-key"

# Run Terraform
terraform init
terraform apply
```

**Pros:**
- ✅ Full control and persistence
- ✅ Can use your favorite editor
- ✅ No session timeouts
- ✅ Better for development

**Cons:**
- ⚠️ Requires installation
- ⚠️ Need to manage AWS credentials

---

## Option 3: EC2 Instance (Linux Server)

Launch an EC2 instance and use it as your terminal.

### Step 1: Launch EC2 Instance

1. Go to AWS Console → EC2 → Launch Instance
2. Choose Amazon Linux 2023 or Ubuntu
3. Select instance type (t2.micro is free tier eligible)
4. Configure security group (allow SSH from your IP)
5. Launch and create/download key pair

### Step 2: Connect to EC2

**Using SSH:**
```bash
# On macOS/Linux
chmod 400 your-key.pem
ssh -i your-key.pem ec2-user@your-instance-ip

# On Windows (using PowerShell or WSL)
ssh -i your-key.pem ec2-user@your-instance-ip
```

**Using AWS Systems Manager Session Manager:**
- No SSH key needed
- Connect directly from AWS Console → EC2 → Connect → Session Manager

### Step 3: Install Tools on EC2

```bash
# Update system
sudo yum update -y  # Amazon Linux
# OR
sudo apt update && sudo apt upgrade -y  # Ubuntu

# Install AWS CLI (usually pre-installed, but update if needed)
aws --version

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version

# Install Git
sudo yum install git -y  # Amazon Linux
# OR
sudo apt install git -y  # Ubuntu
```

### Step 4: Clone Your Repository

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
cd YOUR_REPO_NAME/AI-native---GITHUB-RAG-app-auto-deployment
```

### Step 5: Run Terraform

```bash
# Set variables
export TF_VAR_github_org_or_user="your-github-username"
export TF_VAR_github_repo_name="your-repo-name"
export TF_VAR_openai_api_key="sk-your-openai-api-key"

# Run Terraform (EC2 instance has IAM role, no need to configure credentials)
terraform init
terraform apply
```

**Note:** EC2 instances can use IAM roles, so you don't need to configure AWS credentials manually.

**Pros:**
- ✅ Persistent environment
- ✅ Can leave it running
- ✅ Good for long-running tasks

**Cons:**
- ⚠️ Costs money (though t2.micro is free tier)
- ⚠️ Need to manage the instance

---

## Option 4: GitHub Codespaces / GitPod (Cloud IDE)

Use a cloud-based development environment.

### GitHub Codespaces:

1. Go to your GitHub repository
2. Click "Code" → "Codespaces" → "Create codespace"
3. Install Terraform in the terminal:
   ```bash
   # Install Terraform
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   
   # Configure AWS CLI
   aws configure
   ```

4. Run Terraform commands

**Pros:**
- ✅ Integrated with GitHub
- ✅ Pre-configured environment
- ✅ Can use VS Code in browser

**Cons:**
- ⚠️ Requires GitHub subscription for private repos
- ⚠️ Limited free hours

---

## Quick Comparison

| Option | Easiest | Cost | Best For |
|--------|---------|------|----------|
| **AWS CloudShell** | ⭐⭐⭐⭐⭐ | Free | Quick setup, one-time tasks |
| **Local Terminal** | ⭐⭐⭐ | Free | Regular development |
| **EC2 Instance** | ⭐⭐ | ~$5-10/month | Long-term projects |
| **Codespaces** | ⭐⭐⭐⭐ | Free/Paid | GitHub-integrated workflow |

---

## Recommended Approach

**For First-Time Setup:**
1. Use **AWS CloudShell** (easiest, no installation)
2. Clone your repo from GitHub
3. Install Terraform in CloudShell
4. Run `terraform apply`

**For Ongoing Development:**
1. Set up **Local Terminal** with AWS CLI and Terraform
2. Work from your computer
3. Push changes to GitHub, which triggers deployment

---

## Getting AWS Access Keys (For Local Setup)

If you need AWS credentials for local setup:

1. **Log in to AWS Console**
2. **Go to IAM** → **Users** → Select your user (or create one)
3. **Security credentials** tab
4. **Create access key**
5. **Choose use case**: "Command Line Interface (CLI)"
6. **Download or copy** the Access Key ID and Secret Access Key
7. **Run `aws configure`** and paste the credentials

**Security Best Practice:**
- Don't share your access keys
- Use IAM roles when possible (EC2, CloudShell)
- Rotate keys regularly
- Use least privilege principle

---

## Troubleshooting

### "aws: command not found"
- Install AWS CLI (see Option 2, Step 1)

### "terraform: command not found"
- Install Terraform (see installation steps above)

### "Access Denied" errors
- Check your AWS credentials: `aws sts get-caller-identity`
- Verify IAM permissions (you need permissions to create IAM roles, ECR, etc.)
- Check if your access key is active

### "Region not configured"
- Run `aws configure` and set default region
- Or set `AWS_DEFAULT_REGION` environment variable

---

## Next Steps

Once you have terminal access:

1. ✅ Verify AWS CLI works: `aws sts get-caller-identity`
2. ✅ Verify Terraform works: `terraform version`
3. ✅ Navigate to project directory
4. ✅ Set environment variables
5. ✅ Run `terraform init` and `terraform apply`

