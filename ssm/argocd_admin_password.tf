resource "aws_ssm_parameter" "argocd_admin_password" {
  name  = "/argocd/admin/password"
  type  = "SecureString"
  value = var.argocd_admin_password
}