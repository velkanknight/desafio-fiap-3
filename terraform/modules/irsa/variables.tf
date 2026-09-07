variable "role_name" { type = string } # nome da IAM Role criada

# Os dois campos abaixo vêm do módulo eks/ (outputs oidc_provider_arn
# e oidc_issuer_url) — identificam O CLUSTER de onde o token confiável vem.
variable "oidc_provider_arn" { type = string }
variable "oidc_issuer"       { type = string }

variable "namespace"            { type = string } # namespace do Kubernetes onde a ServiceAccount/Pod vive
variable "service_account_name" { type = string } # nome exato da ServiceAccount (gitops/service-accounts.yaml)
variable "policy_json"          { type = string } # permissão (JSON de IAM policy) específica desta Role
