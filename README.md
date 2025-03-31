# terraform-iam-oidc-ssm

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
# EKSクラスタ作成（OIDCも有効化される）
make create

# TerraformでIAM / OIDC / SSM構成を反映
cd terraform-iam-oidc-ssm && terraform init && terraform apply

# ServiceAccountにIRSAアノテーションを追加して使用開始
kubectl apply -f serviceaccount-argocd.yaml
```

---

## ✅ 最終成果

- EKSクラスタは `eksctl` で素早く立ち上がる
- IAM, OIDC, SSM などの永続セキュリティ設定は Terraform でコード化
- ArgoCD や Operator が使う IRSA Role を明示的に管理
- GitHub Actions や Secrets管理にも SSM パラメータを活用

---

これで黒澤さんのEKS + GitOpsインフラは "設計としても" 強靭になります💪
