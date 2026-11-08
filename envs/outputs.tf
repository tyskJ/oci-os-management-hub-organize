output "bastion_session_commands" {
  description = "各セッションのSSHポートフォワーディング・コマンド（<privateKey>と<localPort>を置き換えて使う）"
  value       = { for key, session in oci_bastion_session.this : key => session.ssh_metadata["command"] }
}

# Windowsのパスワードは、セキュリティ上の理由でTerraform（user_data）では変更しない（詳細は compute.tf）。
# この初期パスワードでログインし、初回ログイン時にOS上で変更する
output "windows_initial_credentials" {
  description = "Windows Serverの初期ユーザー名とパスワード（初回ログイン時に変更を求められる）"
  value = {
    username = data.oci_core_instance_credentials.windows.username
    password = data.oci_core_instance_credentials.windows.password
  }
  sensitive = true
}
