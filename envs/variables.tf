variable "oci_config_profile" {
  type        = string
  description = "OCI CLI の設定ファイル（~/.oci/config）のプロファイル名"
  default     = "ADMIN"
}

variable "tenancy_ocid" {
  type        = string
  description = "テナンシ（ルートコンパートメント）の OCID"
}