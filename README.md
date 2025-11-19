# RAG App — GitHub Actions 部署到 AWS App Runner

本项目使用 GitHub Actions 在推送到 `main` 分支时自动构建 Docker 镜像并部署到 AWS App Runner。

## 📋 前置要求

1. AWS 账户并配置好 AWS CLI
2. GitHub 账户和仓库
3. Cloudflare 账户（用于域名配置）
4. Terraform 已安装

## 🚀 部署步骤

### 步骤 1: 使用 Terraform 创建 AWS 基础设施

在项目根目录执行以下命令，创建所需的 AWS 资源（OIDC Role, ECR, Secrets Manager, IAM Roles）：

```bash
# 设置 Terraform 变量（替换为您的实际值）
export TF_VAR_github_org_or_user="your-github-username"
export TF_VAR_github_repo_name="your-repo-name"
export TF_VAR_openai_api_key="sk-your-openai-api-key"

# 初始化 Terraform
terraform init

# 创建基础设施（不创建 App Runner 服务，由 GitHub Actions 创建）
terraform apply
```

**重要说明**：
- `manage_apprunner_via_terraform` 默认为 `false`，这意味着 App Runner 服务将由 GitHub Actions 自动创建
- 如果 App Runner 服务已存在，GitHub Actions 将更新它
- `main.tf` 已配置必要的 IAM 权限（`iam:GetRole` 和 `secretsmanager:DescribeSecret`）以支持工作流动态获取角色 ARN 和 Secret ARN

### 步骤 2: 配置 GitHub Secrets

在 GitHub 仓库中，进入 **Settings > Secrets and variables > Actions**，添加以下 4 个 Secrets：

| Secret 名称 | 值来源 | 示例值 |
|------------|--------|--------|
| `AWS_REGION` | AWS 区域 | `us-east-1` |
| `ECR_REPOSITORY` | Terraform output: `ecr_repository_name` | `bee-edu-rag-app` |
| `APP_RUNNER_ARN` | Terraform output: `apprunner_service_arn` 或首次部署后从 AWS 控制台获取 | `arn:aws:apprunner:us-east-1:123456789012:service/bee-edu-rag-service/...` |
| `AWS_IAM_ROLE_TO_ASSUME` | Terraform output: `github_actions_role_arn` | `arn:aws:iam::123456789012:role/github-actions-deploy-role` |

**获取 Terraform 输出值**：
```bash
terraform output github_actions_role_arn
terraform output ecr_repository_name
terraform output apprunner_service_arn
terraform output apprunner_access_role_arn
terraform output apprunner_instance_role_arn
terraform output openai_secret_arn
```

**注意**：
- 如果 `apprunner_service_arn` 输出为 `null`（因为服务尚未创建），您可以在首次 GitHub Actions 部署完成后，从 AWS App Runner 控制台获取服务 ARN，然后更新 GitHub Secret。
- 工作流会自动处理角色 ARN 的获取：如果服务存在，从服务获取；如果不存在，从 IAM 获取。

### 步骤 3: 推送代码到 main 分支

将代码推送到 `main` 分支，GitHub Actions 将自动触发部署：

```bash
git add .
git commit -m "Initial commit with CI/CD pipeline"
git push origin main
```

### 步骤 4: 配置 Cloudflare 域名

1. 部署完成后，从 AWS App Runner 控制台获取服务的默认域名（格式：`xxxxx.us-east-1.awsapprunner.com`）

2. 登录 Cloudflare 控制台，进入您的域名管理页面

3. 添加 CNAME 记录：
   - **类型**: CNAME
   - **名称**: `rag`（或您想要的子域名）
   - **目标**: `xxxxx.us-east-1.awsapprunner.com`（App Runner 服务域名）
   - **代理状态**: 已代理（橙色云朵）或仅 DNS（灰色云朵）

4. 等待 DNS 传播（通常几分钟）

5. 访问 `https://rag.yourdomain.com` 测试应用

## 🔄 GitHub Actions 工作流说明

工作流文件位于 `.github/workflows/deploy.yml`，包含以下步骤：

1. **Checkout 代码**: 检出仓库代码
2. **Configure AWS Credentials**: 使用 OIDC 方式（无密钥认证）登录 AWS
3. **Log in to ECR**: 登录 Amazon ECR
4. **Build and push Docker image**: 构建 Docker 镜像并使用 GitHub SHA 作为标签推送到 ECR
5. **Get App Runner service details**: 动态获取服务的 `access-role-arn` 和 `instance-role-arn`
6. **Deploy to App Runner**: 使用 `awslabs/amazon-app-runner-deploy@main` 部署到 App Runner

### 工作流触发条件

- 当代码推送到 `main` 分支时自动触发

### 安全特性

- ✅ 使用 OIDC 认证，无需在 GitHub Secrets 中存储永久 AWS Access Key
- ✅ 最小权限原则：GitHub Actions 角色仅具有部署所需的最小权限
- ✅ API Key 存储在 AWS Secrets Manager 中，不会暴露在代码或日志中

## 📝 Terraform 输出说明

执行 `terraform apply` 后，您会看到以下输出：

- `github_actions_role_arn`: 用于配置 GitHub Secret `AWS_IAM_ROLE_TO_ASSUME`
- `ecr_repository_name`: 用于配置 GitHub Secret `ECR_REPOSITORY`
- `ecr_repository_url`: ECR 仓库完整 URL
- `apprunner_service_arn`: 用于配置 GitHub Secret `APP_RUNNER_ARN`（如果服务已存在，否则为 `null`）
- `apprunner_service_name`: App Runner 服务名称
- `apprunner_access_role_arn`: App Runner Access Role ARN（工作流会自动获取，但也可用于参考）
- `apprunner_instance_role_arn`: App Runner Instance Role ARN（工作流会自动获取，但也可用于参考）
- `openai_secret_arn`: OpenAI API Key 在 Secrets Manager 中的 ARN（工作流会自动获取，但也可用于参考）
- `apprunner_url`: App Runner 服务 URL（如果服务已存在，否则为 `null`）

**注意**：工作流会自动处理角色 ARN 和 Secret ARN 的获取，但 Terraform 输出提供了这些值供参考和验证。

## 🔧 故障排查

### 问题 1: GitHub Actions 部署失败，提示无法找到服务

**解决方案**：
- 确保 `APP_RUNNER_ARN` Secret 配置正确
- 如果服务尚未创建，首次部署时 `awslabs/amazon-app-runner-deploy` 会自动创建服务
- 检查 IAM 角色权限是否包含 `apprunner:CreateService`

### 问题 2: 无法拉取 ECR 镜像

**解决方案**：
- 检查 App Runner 服务角色的 ECR 权限
- 确保镜像已成功推送到 ECR
- 检查镜像标签是否正确

### 问题 3: 应用无法访问 Secrets Manager

**解决方案**：
- 检查 App Runner 实例角色的 Secrets Manager 权限
- 确认 Secret ARN 配置正确
- 检查 Secret 名称是否为 `bee-edu-openai-key-secret`

## 📚 相关资源

- [AWS App Runner 文档](https://docs.aws.amazon.com/apprunner/)
- [GitHub Actions OIDC 文档](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [awslabs/amazon-app-runner-deploy Action](https://github.com/awslabs/amazon-app-runner-deploy)
