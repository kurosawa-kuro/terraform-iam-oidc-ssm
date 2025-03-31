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