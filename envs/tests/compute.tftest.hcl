# ============================================================
# Compute Instance Test
# ============================================================

# OCI ProviderのAPI操作をモック化し、実リソースを作成しない。
# data の戻り値など共通のモック値は tests/mocks/ に定義する。
mock_provider "oci" {
  source = "./tests/mocks" # モック値の定義ファイルの場所。envs/ からの相対パスで指定する
}

# time_sleep（タグ・キーの反映待ち）をモック化し、テスト中に待ち時間を発生させない。
mock_provider "time" {}

# 全テストで共通の入力変数。mock_providerを使うため、OCIDは実在する必要がない。
variables {
  tenancy_ocid                 = "ocid1.tenancy.oc1..mock"               # モック用のテナンシOCID
  system_name                  = "osmh-test"                             # モック用のシステムネーム
  bastion_client_cidr_blocks   = ["203.0.113.10/32"]                     # 接続元CIDR。ドキュメント用アドレス（TEST-NET-3）を使う
  bastion_ssh_public_key_path  = "./tests/testdata/bastion_rsa.pub"      # Bastion用のダミー公開鍵。実際の鍵（.key/）に依存しない
  instance_ssh_public_key_path = "./tests/testdata/instance_ed25519.pub" # インスタンス用のダミー公開鍵。実際の鍵（.key/）に依存しない
}

# インスタンスがパブリックIPを持たず、旧IMDSを使わない設定で作られることを検証する。
run "instances_are_private_and_use_imds_v2" {
  command = apply # モックの範囲でapplyし、関連付けたサブネット・NSGのOCIDも検証する（実リソースは作成しない）

  # local.instances の2つのキーでインスタンスが作られることを確認する。
  assert {
    condition     = toset(keys(oci_core_instance.this)) == toset(["windows", "linux"]) # 作成単位がWindows・Linuxの2つであることを確認する
    error_message = "インスタンスは windows / linux の2つを作成する必要があります。"                         # 失敗時の診断内容
  }

  # すべてのインスタンスでパブリックIPを割り当てないことを確認する。
  assert {
    condition = alltrue([
      for instance in oci_core_instance.this : tostring(instance.create_vnic_details[0].assign_public_ip) == "false"
    ])                                              # Providerは文字列で保持するため、文字列に揃えて比較する
    error_message = "インスタンスにパブリックIPを割り当てない必要があります。" # 失敗時の診断内容
  }

  # すべてのインスタンスで旧IMDS（v1）エンドポイントが無効化されていることを確認する。
  assert {
    condition = alltrue([
      for instance in oci_core_instance.this : instance.instance_options[0].are_legacy_imds_endpoints_disabled
    ])                                                         # 無効化フラグがtrueであることを確認する
    error_message = "セキュリティのため、旧IMDS（v1）エンドポイントを無効化する必要があります。" # 失敗時の診断内容
  }

  # 各インスタンスが同じキーのサブネット・NSGに配置されることを確認する。
  assert {
    condition = alltrue([
      for key, instance in oci_core_instance.this :
      instance.create_vnic_details[0].subnet_id == oci_core_subnet.this[key].id &&
      instance.create_vnic_details[0].nsg_ids == toset([oci_core_network_security_group.instance[key].id])
    ])                                                   # キーごとのサブネット・NSGのOCIDが一致することを確認する
    error_message = "インスタンスは同じキーのサブネット・NSGに配置する必要があります。" # 失敗時の診断内容
  }
}

# OSごとにメタデータ（SSH公開鍵・user_data）が切り替わることを検証する。
run "metadata_is_switched_by_os" {
  command = apply # モックの範囲でapplyし、条件式で組み立てたメタデータを検証する

  # Oracle Linuxには、インスタンス用の公開鍵がopcに登録されることを確認する。
  assert {
    condition     = oci_core_instance.this["linux"].metadata["ssh_authorized_keys"] == file(var.instance_ssh_public_key_path) # インスタンス用の公開鍵の内容と一致することを確認する
    error_message = "Oracle Linuxには instance_ssh_public_key_path の公開鍵を登録する必要があります。"                                           # 失敗時の診断内容
  }

  # Oracle Linuxのuser_dataに、cloud-configの初期化スクリプトが設定されることを確認する。
  assert {
    condition     = oci_core_instance.this["linux"].metadata["user_data"] == base64encode(file("./userdata/oraclelinux_init.yaml")) # Base64化したcloud-configと一致することを確認する
    error_message = "Oracle Linuxのuser_dataには userdata/oraclelinux_init.yaml を設定する必要があります。"                                         # 失敗時の診断内容
  }

  # Windows Serverには、SSH公開鍵を設定しないことを確認する。
  assert {
    condition     = !contains(keys(oci_core_instance.this["windows"].metadata), "ssh_authorized_keys") # メタデータにSSH公開鍵のキーがないことを確認する
    error_message = "Windows ServerにはSSH公開鍵を設定しない必要があります。"                                             # 失敗時の診断内容
  }

  # Windows Serverのuser_dataに、PowerShellの初期化スクリプトが設定されることを確認する。
  assert {
    condition     = oci_core_instance.this["windows"].metadata["user_data"] == base64encode(file("./userdata/windows_init.ps1")) # Base64化したPowerShellスクリプトと一致することを確認する
    error_message = "Windows Serverのuser_dataには userdata/windows_init.ps1 を設定する必要があります。"                                         # 失敗時の診断内容
  }
}

# Oracle Cloud Agentのプラグインのうち、OS Management Hub Agentだけが有効になることを検証する。
run "only_osmh_agent_plugin_is_enabled" {
  command = apply # モックの範囲でapplyし、dynamicブロックで展開したプラグイン設定を検証する

  # 有効なプラグインが、各インスタンスで OS Management Hub Agent の1つだけであることを確認する。
  assert {
    condition = alltrue([
      for instance in oci_core_instance.this : [
        for plugin in instance.agent_config[0].plugins_config : plugin.name if plugin.desired_state == "ENABLED"
      ] == ["OS Management Hub Agent"]
    ])                                                                  # ENABLEDのプラグイン名の一覧を確認する
    error_message = "有効にするプラグインは OS Management Hub Agent だけである必要があります。" # 失敗時の診断内容
  }

  # プラグインを分類ごとに止める親スイッチが、すべて無効化されていないことを確認する。
  assert {
    condition = alltrue([
      for instance in oci_core_instance.this :
      !instance.agent_config[0].are_all_plugins_disabled &&
      !instance.agent_config[0].is_management_disabled &&
      !instance.agent_config[0].is_monitoring_disabled
    ])                                                                   # 親スイッチがtrueだと plugins_config のENABLEDが効かなくなるため、すべてfalseであることを確認する
    error_message = "Agentの親スイッチを無効化すると、OS Management Hub Agentが動作しません。" # 失敗時の診断内容
  }
}

# インスタンスがOS Management Hubの登録プロファイルとOS種別のタグを持つことを検証する。
run "instances_are_tagged_for_osmh_registration" {
  command = apply # モックの範囲でapplyし、プロファイルのOCIDとの対応を検証する

  # 各インスタンスの OsmhProfile タグに、OSに対応する登録プロファイルのOCIDが入ることを確認する。
  assert {
    condition = (
      oci_core_instance.this["linux"].freeform_tags["OsmhProfile"] == oci_os_management_hub_profile.ol10_x86_64_group.id &&
      oci_core_instance.this["windows"].freeform_tags["OsmhProfile"] == oci_os_management_hub_profile.windows_server_2025_x86_64.id
    )                                                                   # Linuxはグループ用、Windowsはスタンドアロン用のプロファイルであることを確認する
    error_message = "OsmhProfile タグに、OSに対応する登録プロファイルのOCIDを設定する必要があります。" # 失敗時の診断内容
  }

  # Windows Serverに、OS種別の定義済みタグが付くことを確認する。
  assert {
    condition     = oci_core_instance.this["windows"].defined_tags["Common.OSType"] == "WindowsServer" # タグ・キーと値を確認する
    error_message = "Windows Serverには定義済みタグ Common.OSType = WindowsServer を付ける必要があります。"                # 失敗時の診断内容
  }
}
