# terraform-iam-oidc-ssm

## ✅ なぜEKSは手動、IAM/OIDC/SSMはTerraformで管理するのか？

EKSはクラスタ構築に時間がかかり、壊して再作成することも多いため、
初期フェーズでは `eksctl` によるCLI構築で高速化する。

一方、IAM / OIDC / SSM は **クラスタ再作成後も再利用したい構成**かつ、
**セキュリティポリシーや権限管理のレビュー対象**になるため、
Terraformでコード化しておくことで、
- 再現性
- レビュー性
- 監査性
を確保できる。

そのため、以下の構成では "EKSはeksctl"、"Identity周りはTerraform" を原則とする。

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
  name = "argocd-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_role.json
}

resource "aws_iam_policy" "argocd_policy" {
  name = "argocd-policy"
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

- EKSクラスタは `eksctl` で素早く立ち上がる
- IAM, OIDC, SSM などの永続セキュリティ設定は Terraform でコード化
- ArgoCD や Operator が使う IRSA Role を明示的に管理
- GitHub Actions や Secrets管理にも SSM パラメータを活用
- ECR / S3 / SecretsManager など、**現場で必要な実用権限も網羅**

---

これで黒澤さんのEKS + GitOpsインフラは "設計としても" 強靭になります💪



いい質問です！  
`~/.ssh/id_rsa.pub` は、**EC2ノードにSSHでアクセスするための公開鍵**です。  
EKSクラスタのノード（EC2）に SSH ログインできるようにするには、事前にローカルに **公開鍵 / 秘密鍵ペア** を生成しておく必要があります。

---

## ✅ 生成方法（Mac / Linux / WSL 共通）

```bash
ssh-keygen -t rsa -b 4096 -C "kuro@example.com"
```

### ↳ 実行結果で聞かれる内容

```
Enter file in which to save the key (/home/yourname/.ssh/id_rsa): [Enter]
Enter passphrase (empty for no passphrase): [Enter]
```

これで以下が生成されます：

| ファイル | 役割 |
|---------|------|
| `~/.ssh/id_rsa` | 秘密鍵（絶対に公開しない） |
| `~/.ssh/id_rsa.pub` | 公開鍵（EKSノードに配布する） |

---

## ✅ `eksctl.yaml` ではこう使われる

```yaml
ssh:
  allow: true
  publicKeyPath: ~/.ssh/id_rsa.pub
```

この設定により、**EKSのノード（EC2）にSSHアクセスが許可される**ようになります。

---

## ✅ ログイン例（クラスタ作成後）

EKSのNodeにログインしたい場合：

```bash
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=kuro-cluster" \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output text
```

取得したIPを使って：

```bash
ssh ec2-user@<IPアドレス> -i ~/.ssh/id_rsa
```

---

## ✅ 注意点

- `id_rsa.pub` が存在しないと `eksctl create cluster` で失敗します
- GitHubなどに **絶対に `id_rsa` をpushしないこと**
- パーミッションに注意：`chmod 600 ~/.ssh/id_rsa`

---

Canvasにこの手順、`README.md` の「補足：SSH鍵の生成方法」に追記しておきましょうか？