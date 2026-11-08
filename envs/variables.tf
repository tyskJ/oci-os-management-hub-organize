variable "bastion_client_cidr_blocks" {
  type        = list(string)
  description = "Bastionへの接続を許可する接続元のCIDR（作業端末のグローバルIP/32など）"

  validation {
    condition     = length(var.bastion_client_cidr_blocks) > 0 && alltrue([for cidr in var.bastion_client_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "CIDR形式（例：203.0.113.10/32）で1件以上指定してください。"
  }
}

variable "bastion_session_ttl_in_seconds" {
  type        = number
  description = "Bastionセッションの有効期間（秒）"
  default     = 10800

  validation {
    condition     = var.bastion_session_ttl_in_seconds >= 1800 && var.bastion_session_ttl_in_seconds <= 10800
    error_message = "1800〜10800秒の範囲で指定してください。"
  }
}

variable "bastion_ssh_public_key_path" {
  type        = string
  description = "Bastionセッション（ポートフォワーディングのトンネル）に使うSSH公開鍵（RSA）のパス"
  default     = "./.key/bastion_rsa.pub"
}

variable "instance_memory_in_gbs" {
  type        = number
  description = "インスタンスのメモリ（GB）"
  default     = 16
}

variable "instance_ocpus" {
  type        = number
  description = "インスタンスのOCPU数"
  default     = 1
}

variable "instance_shape" {
  type        = string
  description = "インスタンスのシェイプ（Windows ServerとOracle Linuxで共通）"
  default     = "VM.Standard.E5.Flex"
}

variable "instance_ssh_public_key_path" {
  type        = string
  description = "Oracle Linuxのopcユーザーのログインに使うSSH公開鍵のパス"
  default     = "./.key/instance_ed25519.pub"
}

variable "oci_config_profile" {
  type        = string
  description = "OCI CLI の設定ファイル（~/.oci/config）のプロファイル名"
  default     = "ADMIN"
}

variable "system_name" {
  type        = string
  description = "システムネーム"
}

variable "tenancy_ocid" {
  type        = string
  description = "テナンシ（ルートコンパートメント）の OCID"
}
