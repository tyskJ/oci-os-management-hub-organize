provider "oci" {
  auth                = "SecurityToken"
  config_file_profile = var.oci_config_profile
  region              = "ap-tokyo-1"
  ignore_defined_tags = [
    "Oracle-Tags.CreatedBy",
    "Oracle-Tags.CreatedOn"
  ]
}