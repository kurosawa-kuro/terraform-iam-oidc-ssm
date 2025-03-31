以下は、文構成や表現をわかりやすく整理したリファクタリング例です。内容やディレクトリ構成、コードはそのままに、説明の流れを自然にしつつ表記ゆれを整えています。必要に応じて調整してご利用ください。

---

# terraform-iam-oidc-ssm

## ✅ なぜ EKS は手動、IAM/OIDC/SSM は Terraform で管理するのか？

EKS はクラスタ構築に時間がかかるうえ、初期フェーズでは壊して再作成することが多いため、CLI ベースの `eksctl` で高速に構築する方が便利です。

一方、IAM / OIDC / SSM は **クラスタ再作成後も再利用したい構成** かつ、**セキュリティポリシーや権限管理のレビュー対象** となるため、Terraform でコード化しておくと以下のメリットが得られます。

- **再現性**  
- **レビュー性**  
- **監査性**

したがって、本リポジトリでは「EKS クラスタは `eksctl`」「IAM / OIDC / SSM は Terraform」という方針を採用しています。

---

## 📁 ディレクトリ構成

```bash
terraform-iam-oidc-ssm/
├── main.tf
├── variables.tf
├── outputs.tf
├── iam/
│   ├── irsa_role_argocd.tf
│   └── policies/
│       └── argocd_policy.json
├── oidc/
│   └── oidc_provider.tf
├── ssm/
│   └── argocd_admin_password.tf
├── eksctl/
│   ├── eksctl.yaml
│   └── Makefile
└── README.md
```

---

## ✨ 内容概要

### iam/irsa_role_argocd.tf

```hcl
resource "aws_iam_role" "argocd_irsa" {
  name               = "argocd-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_role.json
}

resource "aws_iam_policy" "argocd_policy" {
  name   = "argocd-policy"
  policy = file("${path.module}/policies/argocd_policy.json")
}

resource "aws_iam_role_policy_attachment" "argocd_attach" {
  role       = aws_iam_role.argocd_irsa.name
  policy_arn = aws_iam_policy.argocd_policy.arn
}
```

### iam/policies/argocd_policy.json

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/argocd/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-argocd-bucket",
        "arn:aws:s3:::your-argocd-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:argocd/*"
    }
  ]
}
```

### oidc/oidc_provider.tf

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
}
```

### ssm/argocd_admin_password.tf

```hcl
resource "aws_ssm_parameter" "argocd_admin_password" {
  name  = "/argocd/admin/password"
  type  = "SecureString"
  value = var.argocd_admin_password
}
```

---

## 🔧 eksctl.yaml（クラスタ定義）

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: kuro-cluster
  region: ap-northeast-1
  version: "1.29"

managedNodeGroups:
  - name: ng-kuro
    instanceType: t3.medium
    desiredCapacity: 1
    minSize: 1
    maxSize: 2
    ssh:
      allow: true
      publicKeyPath: ~/.ssh/id_rsa.pub

iam:
  withOIDC: true
```

---

## 🛠️ Makefile（簡易オペレーション）

```makefile
CLUSTER_NAME=kuro-cluster

create:
	eksctl create cluster -f eksctl/eksctl.yaml

destroy:
	eksctl delete cluster --name $(CLUSTER_NAME)

kubeconfig:
	eksctl utils write-kubeconfig --cluster $(CLUSTER_NAME)
```

---

## 🚀 実行手順

```bash
# EKSクラスタ作成（初回のみ）
make create

# TerraformでIAM/OIDC/SSM構成を反映
cd terraform-iam-oidc-ssm && terraform init && terraform apply

# ArgoCDのServiceAccountにIRSAをアタッチ
kubectl apply -f serviceaccount-argocd.yaml
```

---

## ✅ 最終成果

- EKS クラスタは `eksctl` で素早く立ち上がる  
- IAM / OIDC / SSM などの永続的なセキュリティ構成は Terraform でコード化  
- ArgoCD や各種 Operator が使う IRSA Role を明示的に管理  
- GitHub Actions や Secrets 管理にも SSM パラメータを活用  
- ECR / S3 / Secrets Manager など、**現場で必要な実用的権限を網羅**

これにより、EKS + GitOps インフラが設計面でも強固なものになります。💪

---

## ✅ `eksctl.yaml` の `~/.ssh/id_rsa.pub` について

> **Q.** `~/.ssh/id_rsa.pub` とは何ですか？  

**A.** EKS のノード（EC2）に SSH 接続するための **公開鍵** です。  
クラスタで稼働する EC2 にログインできるようにするには、**公開鍵 / 秘密鍵ペア** を事前に生成しておき、`eksctl.yaml` 側で公開鍵を指定します。

---

## ✅ SSH 鍵の生成方法（Mac / Linux / WSL 共通）

```bash
ssh-keygen -t rsa -b 4096 -C "kuro@example.com"
```

実行すると以下のように尋ねられます。

```
Enter file in which to save the key (/home/yourname/.ssh/id_rsa): [Enter]
Enter passphrase (empty for no passphrase): [Enter]
```

これで下記のファイルが生成されます。

| ファイル              | 役割                                   |
|-----------------------|----------------------------------------|
| `~/.ssh/id_rsa`       | 秘密鍵（絶対に公開しない）             |
| `~/.ssh/id_rsa.pub`   | 公開鍵（EKSノードなどに配布する）      |

---

## ✅ `eksctl.yaml` での指定例

```yaml
ssh:
  allow: true
  publicKeyPath: ~/.ssh/id_rsa.pub
```

この設定により、EKS ノード（EC2）に SSH アクセスが許可されるようになります。

---

## ✅ ログイン例（クラスタ作成後）

EKS の Node にログインしたい場合は、まず以下のコマンドでパブリック IP を確認します。

```bash
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=kuro-cluster" \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output text
```

取得した IP アドレスに対して SSH でログインします。

```bash
ssh ec2-user@<IPアドレス> -i ~/.ssh/id_rsa
```

---

## ✅ 注意点

- `id_rsa.pub`（公開鍵）が存在しないと `eksctl create cluster` は失敗します
- 秘密鍵（`id_rsa`）は **絶対に公開しない**（GitHub などにプッシュしない）
- パーミッションは `chmod 600 ~/.ssh/id_rsa` などで適切に保護してください

---

### README.md への反映について

今回の SSH 鍵生成手順などは、README.md の「補足：SSH キーの生成方法」などのセクションにまとめておくと、利用者にとっても分かりやすいです。必要に応じてコピペしてお使いください。