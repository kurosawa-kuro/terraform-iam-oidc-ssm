以下では、**将来の削除やリソース管理を容易にするために**、一貫した**接頭辞（prefix）**を使ってリソース名とタグを付与する方法をご紹介します。ポイントは下記の 2 点です。

1. **「プロジェクト・環境・用途」などを含む統一的な接頭辞**を定義して、AWS リソース名・タグに反映する。  
2. Terraform と eksctl 双方の設定で同じ接頭辞を使い、AWS コンソールや CLI、課金明細上で見分けやすくする。

---

# 1. Terraform 側での例

## variables.tf

```hcl
variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
  default     = "kuro-dev-cluster"
}

variable "environment" {
  type        = string
  description = "Environment (e.g. dev, stg, prod)"
  default     = "dev"
}

# 接頭辞（prefix）を定義し、全リソースに流用
variable "resource_prefix" {
  type        = string
  description = "Prefix for resource naming"
  default     = "kuro-dev"
}

# リソース全体で使う共通タグ
variable "common_tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default = {
    Project     = "kuro-argocd"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

上記では `resource_prefix` を `kuro-dev` としています（本番なら `kuro-prod` など）。  
**環境名やプロジェクト名**を混ぜることで、どの環境のリソースなのか一目でわかるようになります。

---

## main.tf 例（抜粋）

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "ap-northeast-1"
}
```

Backend や他の設定は環境に合わせて追加してください。

---

## iam/irsa_role_argocd.tf

```hcl
data "aws_iam_policy_document" "oidc_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${aws_iam_openid_connect_provider.eks.url}:sub"
      values   = ["system:serviceaccount:argocd:argocd-service-account"]
    }
  }
}

resource "aws_iam_role" "argocd_irsa" {
  # 接頭辞を使って IAM Role 名を統一的に命名
  name               = "${var.resource_prefix}-iam-role-argocd-irsa"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_role.json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.resource_prefix}-iam-role-argocd-irsa"
    }
  )
}

resource "aws_iam_policy" "argocd_policy" {
  name   = "${var.resource_prefix}-iam-policy-argocd"
  policy = file("${path.module}/policies/argocd_policy.json")

  tags = merge(
    var.common_tags,
    {
      Name = "${var.resource_prefix}-iam-policy-argocd"
    }
  )
}

resource "aws_iam_role_policy_attachment" "argocd_attach" {
  role       = aws_iam_role.argocd_irsa.name
  policy_arn = aws_iam_policy.argocd_policy.arn
  # aws_iam_role_policy_attachment にはタグを直接付けられないため省略
}
```

- IAM Role 名は、 `${var.resource_prefix}-iam-role-argocd-irsa` のように **一貫した命名規則** を採用。
- タグの `Name` に同じ文字列を入れることで、AWS コンソールや Cost Explorer などで絞り込みが容易になります。

---

## oidc/oidc_provider.tf

```hcl
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0afd29c20"]
  url             = data.aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(
    var.common_tags,
    {
      Name = "${var.resource_prefix}-iam-oidc-provider"
    }
  )
}
```

---

## ssm/argocd_admin_password.tf

```hcl
resource "aws_ssm_parameter" "argocd_admin_password" {
  name  = "/argocd/admin/password"
  type  = "SecureString"
  value = var.argocd_admin_password

  tags = merge(
    var.common_tags,
    {
      Name = "${var.resource_prefix}-ssm-argocd-admin-password"
    }
  )
}
```

---

# 2. eksctl 側での例（`eksctl.yaml`）

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: kuro-dev-cluster
  region: ap-northeast-1
  version: "1.29"
  tags:
    Project: "kuro-argocd"
    Environment: "dev"
    ManagedBy: "eksctl"

managedNodeGroups:
  - name: kuro-dev-ng
    instanceType: t3.medium
    desiredCapacity: 1
    minSize: 1
    maxSize: 2
    ssh:
      allow: true
      publicKeyPath: ~/.ssh/id_rsa.pub
    tags:
      Project: "kuro-argocd"
      Environment: "dev"
      ManagedBy: "eksctl"

iam:
  withOIDC: true
```

- `metadata.name` と `managedNodeGroups[].name` も `kuro-dev` などの接頭辞を付けて命名。  
- `tags` にも同じキー・値を付与することで、AWS 上で「Project=**kuro-argocd**」や「Environment=**dev**」等でリソースが一括管理できます。

---

# 3. Makefile 例

```makefile
CLUSTER_NAME=kuro-dev-cluster

create:
	eksctl create cluster -f eksctl/eksctl.yaml

destroy:
	eksctl delete cluster --name $(CLUSTER_NAME)

kubeconfig:
	eksctl utils write-kubeconfig --cluster $(CLUSTER_NAME)
```

- `CLUSTER_NAME` にも同じ接頭辞の名前を使い、**Terraform 側との整合性**を保つと良いでしょう。

---

# 4. 運用イメージ

1. **新しい環境を作るとき**  
   - `resource_prefix` と `environment` を変更 (例: `kuro-stg`, `kuro-prod`)  
   - `eksctl.yaml` も `metadata.name` や `managedNodeGroups` に「kuro-stg」「kuro-prod」などを設定  
   - これにより、**環境ごとに明確に分かれたネーミング/タグ** でリソースが作成される。  

2. **削除したいとき**  
   - AWS コンソールや CLI で `Name` や `Project` タグを基準にフィルタして、不要なリソースを一括で確認・削除できる。  

3. **Cost Explorer や課金レポートで確認する時**  
   - 「Project=○○」「Environment=△△」というタグをベースにコスト配分ができるため、誰がどの環境を使っているか可視化しやすい。  

---

# 5. まとめ

- **接頭辞（prefix）** を活用し、`kuro-dev` や `kuro-stg` のように環境や用途を明示したリソース名にする。  
- **共通タグ** も同じ情報を含めることで、AWS 上でのフィルタやコスト管理がスムーズになる。  
- Terraform と eksctl の両方で同じ接頭辞を使い、命名規則を統一する。  

これにより、**将来の削除やリソース管理が格段に容易** となり、プロジェクト全体の可観測性やコスト管理も改善されます。ぜひご参考にしてみてください。