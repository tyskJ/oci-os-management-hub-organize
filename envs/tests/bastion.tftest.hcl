# ============================================================
# Bastion Test
# ============================================================

# OCI ProviderのAPI操作をモック化し、実リソースを作成しない。
# Bastionセッションが返す接続コマンドなど、共通のモック値は tests/mocks/ に定義する。
mock_provider "oci" {
  source = "./tests/mocks" # モック値の定義ファイルの場所。envs/ からの相対パスで指定する
}

# time_sleep（タグ・キーの反映待ち）をモック化し、テスト中に待ち時間を発生させない。
mock_provider "time" {}

# 全テストで共通の入力変数。mock_providerを使うため、OCIDは実在する必要がない。
variables {
  tenancy_ocid                 = "ocid1.tenancy.oc1..mock"               # モック用のテナンシOCID
  system_name                  = "osmh-test"                             # モック用のシステムネーム
  bastion_client_cidr_blocks   = ["203.0.113.10/32", "198.51.100.0/24"]  # 接続元CIDR。複数指定がそのまま反映されることを確認するため2件渡す
  bastion_ssh_public_key_path  = "./tests/testdata/bastion_rsa.pub"      # Bastion用のダミー公開鍵。実際の鍵（.key/）に依存しない
  instance_ssh_public_key_path = "./tests/testdata/instance_ed25519.pub" # インスタンス用のダミー公開鍵。実際の鍵（.key/）に依存しない
}

# Bastionの接続元と配置先が設計どおりであることを検証する。
run "bastion_allows_only_client_cidrs" {
  command = apply # モックの範囲でapplyし、配置先サブネットのOCIDも検証する（実リソースは作成しない）

  # 接続を許可する接続元が、入力変数のCIDRだけであることを確認する。
  assert {
    condition     = toset(oci_bastion_bastion.this.client_cidr_block_allow_list) == toset(["203.0.113.10/32", "198.51.100.0/24"]) # テスト入力のCIDRと一致することを確認する
    error_message = "Bastionの接続元は bastion_client_cidr_blocks のCIDRだけに限定する必要があります。"                                                # 失敗時の診断内容
  }

  # プライベート・エンドポイントがBastionサブネットに置かれることを確認する。
  assert {
    condition     = oci_bastion_bastion.this.target_subnet_id == oci_core_subnet.this["bastion"].id # Bastionサブネットのみであることを確認する
    error_message = "Bastionのプライベート・エンドポイントはBastionサブネットに置く必要があります。"                                # 失敗時の診断内容
  }
}

# インスタンスごとのセッションが、Bastion用の鍵とOSごとの接続ポートで作られることを検証する。
run "sessions_forward_remote_port_per_instance" {
  command = apply # モックの範囲でapplyし、接続先インスタンスのOCIDとの対応を検証する

  # 各セッションが、同じキーのインスタンス・OSごとの接続ポートを接続先にしていることを確認する。
  assert {
    condition = (
      oci_bastion_session.this["windows"].target_resource_details[0].target_resource_id == oci_core_instance.this["windows"].id &&
      oci_bastion_session.this["windows"].target_resource_details[0].target_resource_port == 3389 &&
      oci_bastion_session.this["linux"].target_resource_details[0].target_resource_id == oci_core_instance.this["linux"].id &&
      oci_bastion_session.this["linux"].target_resource_details[0].target_resource_port == 22
    )                                                       # WindowsはRDP（3389）、LinuxはSSH（22）であることを確認する
    error_message = "Bastionセッションの接続先インスタンス・ポートが設計と一致しません。" # 失敗時の診断内容
  }

  # すべてのセッションが、Bastionプラグイン不要のポートフォワーディングであることを確認する。
  assert {
    condition = alltrue([
      for session in oci_bastion_session.this : session.target_resource_details[0].session_type == "PORT_FORWARDING"
    ])                                                          # セッションの種類を確認する
    error_message = "BastionセッションはPORT_FORWARDINGで作成する必要があります。" # 失敗時の診断内容
  }

  # セッションの公開鍵に、インスタンスのログイン用とは別のBastion用の鍵が使われることを確認する。
  assert {
    condition = alltrue([
      for session in oci_bastion_session.this : session.key_details[0].public_key_content == file(var.bastion_ssh_public_key_path)
    ])                                                                           # Bastion用の公開鍵の内容と一致することを確認する
    error_message = "Bastionセッションには bastion_ssh_public_key_path の公開鍵を使う必要があります。" # 失敗時の診断内容
  }
}

# 出力する接続コマンドが、プレースホルダーを置き換えたそのまま実行できる形になっていることを検証する。
# 置き換え前のコマンドは tests/mocks/ の mock_resource "oci_bastion_session" で定義している。
run "outputs_are_ready_to_run" {
  command = apply # 出力値はセッション作成後に決まるため、モックの範囲でapplyする

  # セッションのコマンドに、秘密鍵のパス・作業端末側のポート・詳細ログ（-v）が入ることを確認する。
  assert {
    condition = (
      output.bastion_session_commands["windows"] == "ssh -v -i ./tests/testdata/bastion_rsa -N -L 13389:10.0.3.10:22 -p 22 ocid1.bastionsession.oc1.ap-tokyo-1.mock@host.bastion.ap-tokyo-1.oci.oraclecloud.com" &&
      output.bastion_session_commands["linux"] == "ssh -v -i ./tests/testdata/bastion_rsa -N -L 10022:10.0.3.10:22 -p 22 ocid1.bastionsession.oc1.ap-tokyo-1.mock@host.bastion.ap-tokyo-1.oci.oraclecloud.com"
    )                                                        # 秘密鍵は公開鍵のパスから .pub を除いたもの、ポートはWindowsが13389・Linuxが10022であることを確認する
    error_message = "Bastionセッションのコマンドの置き換え結果が期待する値と一致しません。" # 失敗時の診断内容
  }

  # 置き換え漏れのプレースホルダーが残っていないことを確認する。
  assert {
    condition = alltrue([
      for command in values(output.bastion_session_commands) : !strcontains(command, "<privateKey>") && !strcontains(command, "<localPort>")
    ])                                                   # <privateKey>・<localPort> が含まれないことを確認する
    error_message = "Bastionセッションのコマンドにプレースホルダーが残っています。" # 失敗時の診断内容
  }

  # トンネルを張った後の接続先が、インスタンス用の秘密鍵・作業端末側のポートになっていることを確認する。
  assert {
    condition = (
      output.instance_connect_commands["linux"] == "ssh -i ./tests/testdata/instance_ed25519 -p 10022 opc@localhost" &&
      output.instance_connect_commands["windows"] == "localhost:13389"
    )                                                  # LinuxはSSHのコマンド、WindowsはRDPクライアントの接続先であることを確認する
    error_message = "インスタンスへの接続コマンド・接続先が期待する値と一致しません。" # 失敗時の診断内容
  }
}
