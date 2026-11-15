# Bastionが返すコマンドの <privateKey> と <localPort> を置き換え、そのまま実行できる形で出力する。
# 秘密鍵は中身ではなくパスだけを入れる（中身をStateに残さないため）。パスは envs/ からの相対パス。
# 接続の失敗やトンネルの切断を確認できるよう、先頭の ssh に詳細ログ（-v）を付ける
output "bastion_session_commands" {
  description = "各セッションのSSHポートフォワーディング・コマンド（envs/ で実行する）"
  value = {
    for key, session in oci_bastion_session.this : key => replace(
      replace(
        replace(
          session.ssh_metadata["command"],
          "<privateKey>",
          trimsuffix(var.bastion_ssh_public_key_path, ".pub"), # 秘密鍵のパス。公開鍵のパスから拡張子 .pub を除いて求める
        ),
        "<localPort>",
        tostring(local.instances[key].local_port), # 作業端末側のポート。local.instances の定義値を使用する
      ),
      "/^ssh /", # 置き換え対象。正規表現で先頭の ssh だけに一致させる
      "ssh -v ", # 詳細ログ（-v）を付ける
    )
  }
}

# bastion_session_commands でトンネルを張った後に、各インスタンスへ接続する方法を出力する。
# ＜Oracle Linux＞作業端末側のポートへSSHするコマンド。秘密鍵はBastion用とは別のインスタンス用の鍵を使う
# ＜Windows Server＞RDPはコマンドではなくクライアントで接続するため、接続先（localhost:<作業端末側のポート>）を出力する
output "instance_connect_commands" {
  description = "トンネルを張った後に、各インスタンスへ接続するコマンド・接続先（envs/ で実行する）"
  value = {
    linux = format(
      "ssh -i %s -p %d opc@localhost",
      trimsuffix(var.instance_ssh_public_key_path, ".pub"), # 秘密鍵のパス。公開鍵のパスから拡張子 .pub を除いて求める
      local.instances["linux"].local_port,                  # 作業端末側のポート。local.instances の定義値を使用する
    )
    windows = format(
      "localhost:%d",                        # RDPクライアントの接続先
      local.instances["windows"].local_port, # 作業端末側のポート。local.instances の定義値を使用する
    )
  }
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
