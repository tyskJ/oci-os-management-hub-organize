# ============================================================
# Network Test
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

# サブネットがすべてプライベートで、設計どおりのCIDRで作られることを検証する。
run "subnets_are_private_with_designed_cidr" {
  command = apply # モックの範囲でapplyし、OCIDなど作成後に決まる値も検証する（実リソースは作成しない）

  # local.subnets の3つのキーでサブネットが作られることを確認する。
  assert {
    condition     = toset(keys(oci_core_subnet.this)) == toset(["bastion", "windows", "linux"]) # 作成単位がBastion・Windows・Linuxの3つであることを確認する
    error_message = "サブネットは bastion / windows / linux の3つを作成する必要があります。"                         # 失敗時の診断内容
  }

  # すべてのサブネットでVNICへのパブリックIP割当が禁止されていることを確認する。
  assert {
    condition     = alltrue([for subnet in oci_core_subnet.this : subnet.prohibit_public_ip_on_vnic]) # 全サブネットで禁止フラグがtrueであることを確認する
    error_message = "すべてのサブネットでパブリックIPの割当を禁止する必要があります。"                                               # 失敗時の診断内容
  }

  # 構成図どおりのCIDRが各サブネットに設定されていることを確認する。
  assert {
    condition = (
      oci_core_subnet.this["bastion"].cidr_block == "10.0.1.0/24" &&
      oci_core_subnet.this["windows"].cidr_block == "10.0.2.0/24" &&
      oci_core_subnet.this["linux"].cidr_block == "10.0.3.0/24"
    )                                          # キーごとのCIDRが構成図の値と一致することを確認する
    error_message = "サブネットのCIDRが構成図の値と一致しません。" # 失敗時の診断内容
  }

  # VCNがIPv4のみで構成されることを確認する。
  assert {
    condition     = oci_core_vcn.this.is_ipv6enabled == false # IPv6が無効であることを確認する
    error_message = "VCNはIPv4のみで構成し、IPv6を無効にする必要があります。"       # 失敗時の診断内容
  }
}

# サブネットに、同じキーのルート表・セキュリティ・リストが関連付けられることを検証する。
run "subnets_use_matching_route_table_and_security_list" {
  command = apply # モックの範囲でapplyし、関連付けたリソースのOCIDを比較する

  # 各サブネットに同じキーのルート表が関連付けられていることを確認する。
  assert {
    condition = (
      oci_core_subnet.this["bastion"].route_table_id == oci_core_route_table.bastion.id &&
      oci_core_subnet.this["windows"].route_table_id == oci_core_route_table.windows.id &&
      oci_core_subnet.this["linux"].route_table_id == oci_core_route_table.linux.id
    )                                              # キーごとのルート表のOCIDが一致することを確認する
    error_message = "サブネットに同じキーのルート表が関連付けられていません。" # 失敗時の診断内容
  }

  # Bastionサブネットには専用のセキュリティ・リストだけが関連付けられていることを確認する。
  assert {
    condition     = oci_core_subnet.this["bastion"].security_list_ids == toset([oci_core_security_list.bastion.id]) # Bastion用のリストだけであることを確認する
    error_message = "BastionサブネットにはBastion用のセキュリティ・リストだけを関連付ける必要があります。"                                             # 失敗時の診断内容
  }

  # インスタンス用サブネットには同じキーの空のセキュリティ・リストだけが関連付けられていることを確認する。
  assert {
    condition = alltrue([
      for key in ["windows", "linux"] :
      oci_core_subnet.this[key].security_list_ids == toset([oci_core_security_list.instance[key].id])
    ])                                                          # Windows・Linuxのサブネットごとに同じキーのリストであることを確認する
    error_message = "インスタンス用サブネットに同じキーのセキュリティ・リストが関連付けられていません。" # 失敗時の診断内容
  }

  # インスタンス用のセキュリティ・リストはルールを持たず、通信をNSGで制御することを確認する。
  assert {
    condition = alltrue([
      for security_list in oci_core_security_list.instance :
      length(security_list.ingress_security_rules) == 0 && length(security_list.egress_security_rules) == 0
    ])                                                    # 受信・送信ともにルールが0件であることを確認する
    error_message = "インスタンス用のセキュリティ・リストはルールを持たない必要があります。" # 失敗時の診断内容
  }
}

# ルート表で、インターネットへ出られるのがWindowsサブネットだけであることを検証する。
run "only_windows_subnet_routes_to_internet" {
  command = apply # モックの範囲でapplyし、ルートのターゲット（ゲートウェイのOCID）を比較する

  # Windowsのルート表に、NAT Gateway経由のインターネット宛て経路があることを確認する。
  assert {
    condition = anytrue([
      for rule in oci_core_route_table.windows.route_rules :
      rule.destination == "0.0.0.0/0" && rule.network_entity_id == oci_core_nat_gateway.this.id
    ])                                                                               # 0.0.0.0/0 の宛先がNAT Gatewayであることを確認する
    error_message = "Windowsのルート表に、NAT Gateway経由のインターネット宛て経路が必要です（Windows Update用）。" # 失敗時の診断内容
  }

  # Windows・Linuxのルート表に、Service Gateway経由のOracle Services Network宛て経路があることを確認する。
  assert {
    condition = alltrue([
      for route_table in [oci_core_route_table.windows, oci_core_route_table.linux] :
      anytrue([
        for rule in route_table.route_rules :
        rule.destination_type == "SERVICE_CIDR_BLOCK" && rule.network_entity_id == oci_core_service_gateway.this.id
      ])
    ])                                                                             # サービスCIDRラベルの宛先がService Gatewayであることを確認する
    error_message = "インスタンス用のルート表に、Service Gateway経由の経路が必要です（OS Management Hub用）。" # 失敗時の診断内容
  }

  # LinuxとBastionのルート表に、インターネット宛ての経路がないことを確認する。
  assert {
    condition = alltrue([
      for route_table in [oci_core_route_table.linux, oci_core_route_table.bastion] :
      alltrue([for rule in route_table.route_rules : rule.destination != "0.0.0.0/0"])
    ])                                                                                # 0.0.0.0/0 を宛先とするルールが存在しないことを確認する
    error_message = "LinuxとBastionのサブネットはインターネットへ出られない設計です。0.0.0.0/0 の経路を追加しないでください。" # 失敗時の診断内容
  }
}

# Bastionからインスタンスへの通信が、接続ポート（RDP / SSH）だけに限定されることを検証する。
run "bastion_traffic_is_limited_to_remote_ports" {
  command = apply # モックの範囲でapplyし、dynamicブロックとfor_eachの展開結果を検証する

  # Bastionのセキュリティ・リストの送信ルールが、各サブネットの接続ポートだけを許可していることを確認する。
  assert {
    condition = toset([
      for rule in oci_core_security_list.bastion.egress_security_rules :
      "${rule.destination}:${rule.tcp_options[0].min}-${rule.tcp_options[0].max}"
    ]) == toset(["10.0.2.0/24:3389-3389", "10.0.3.0/24:22-22"])                       # 宛先とポート範囲の組み合わせを確認する
    error_message = "Bastionの送信ルールは、Windowsサブネットの3389番とLinuxサブネットの22番だけを許可する必要があります。" # 失敗時の診断内容
  }

  # NSGの受信ルールが、Bastionサブネットからの接続ポートだけを許可していることを確認する。
  assert {
    condition = (
      oci_core_network_security_group_security_rule.instance_ingress_from_bastion["windows"].tcp_options[0].destination_port_range[0].min == 3389 &&
      oci_core_network_security_group_security_rule.instance_ingress_from_bastion["windows"].tcp_options[0].destination_port_range[0].max == 3389 &&
      oci_core_network_security_group_security_rule.instance_ingress_from_bastion["linux"].tcp_options[0].destination_port_range[0].min == 22 &&
      oci_core_network_security_group_security_rule.instance_ingress_from_bastion["linux"].tcp_options[0].destination_port_range[0].max == 22
    )                                                        # Windowsは3389番、Linuxは22番だけであることを確認する
    error_message = "NSGの受信ルールのポートが接続ポート（RDP / SSH）と一致しません。" # 失敗時の診断内容
  }

  # NSGの受信ルールの送信元が、BastionサブネットのCIDRに限定されていることを確認する。
  assert {
    condition = alltrue([
      for rule in oci_core_network_security_group_security_rule.instance_ingress_from_bastion :
      rule.source == "10.0.1.0/24" && rule.direction == "INGRESS"
    ])                                                              # すべての受信ルールの送信元がBastionサブネットであることを確認する
    error_message = "NSGの受信ルールの送信元は、BastionサブネットのCIDRに限定する必要があります。" # 失敗時の診断内容
  }
}
