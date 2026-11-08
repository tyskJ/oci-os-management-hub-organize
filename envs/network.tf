# ============================================================
# VCN
# ============================================================

# 構成図のVCNを定義する。IPv4のみで構成する。
resource "oci_core_vcn" "this" {
  compartment_id = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  cidr_blocks    = [local.vcn_cidr_block]      # IPv4アドレス範囲。local.vcn_cidr_block を設定する
  display_name   = "vcn"                       # OCIの表示名。役割がわかる名称とする
  dns_label      = "osmhvcn"                   # VCN内DNSのラベル。ホスト名解決を使うため設定する（作成後は変更不可）
  is_ipv6enabled = false                       # IPv6の有効化。本構成はIPv4のみのため無効にする
}

# VCN作成時に自動作成されるデフォルト・セキュリティ・リストを管理する。
# どのサブネットにも関連付けないため、既定で入っているルールを削除して空にする。
resource "oci_core_default_security_list" "this" {
  manage_default_resource_id = oci_core_vcn.this.default_security_list_id # 管理対象。同一構成で作成したVCNのデフォルト・セキュリティ・リストを指定する
  compartment_id             = local.tagged_compartment_id                # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  display_name               = "default-sl"                               # OCIの表示名。役割がわかる名称とする
}

# ============================================================
# NAT Gateway
# ============================================================

# Windows Serverがインターネット上のWindows Updateへ接続するためのNAT Gatewayを定義する。
resource "oci_core_nat_gateway" "this" {
  compartment_id = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  vcn_id         = oci_core_vcn.this.id        # 所属するVCN。同一構成で作成したVCNを使用する
  display_name   = "ngw"                       # OCIの表示名。役割がわかる名称とする
  block_traffic  = false                       # 通信のブロック。Windows Updateに使うため通過を許可する
}

# ============================================================
# Service Gateway
# ============================================================

# OS Management HubなどOracleのサービスへ、インターネットを経由せずに接続するService Gatewayを定義する。
resource "oci_core_service_gateway" "this" {
  compartment_id = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  vcn_id         = oci_core_vcn.this.id        # 所属するVCN。同一構成で作成したVCNを使用する
  display_name   = "sgw"                       # OCIの表示名。役割がわかる名称とする

  # 有効にするサービス。OSMHとObject Storageの両方を使うため「すべてのサービス」を指定する
  services {
    service_id = data.oci_core_services.all.services[0].id # サービスのOCID。data.oci_core_services.all で取得した値を使用する
  }
}

# ============================================================
# Route Table
# ============================================================

# Bastionサブネットのルート表を定義する。
# Bastionのプライベート・エンドポイントはVCN内の通信だけを行うため、ルールは持たない。
resource "oci_core_route_table" "bastion" {
  compartment_id = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  vcn_id         = oci_core_vcn.this.id        # 所属するVCN。同一構成で作成したVCNを使用する
  display_name   = "bastion-rt"                # OCIの表示名。役割がわかる名称とする
}

# Windows Serverサブネットのルート表を定義する。
# Windows UpdateはNAT Gateway、OS Management HubはService Gatewayを経由させる。
resource "oci_core_route_table" "windows" {
  compartment_id = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  vcn_id         = oci_core_vcn.this.id        # 所属するVCN。同一構成で作成したVCNを使用する
  display_name   = "windows-rt"                # OCIの表示名。役割がわかる名称とする

  # インターネット宛ての経路。Windows Update用
  route_rules {
    description       = "Internet via NAT Gateway (Windows Update)" # ルールの説明。用途を示す
    destination       = "0.0.0.0/0"                                 # 宛先。インターネット全体とする
    destination_type  = "CIDR_BLOCK"                                # 宛先の種類。CIDR表記で指定する
    network_entity_id = oci_core_nat_gateway.this.id                # ターゲット。同一構成で作成したNAT Gatewayとする
  }

  # Oracle Services Network宛ての経路。OS Management Hub用
  route_rules {
    description       = "Oracle Services Network via Service Gateway (OS Management Hub)" # ルールの説明。用途を示す
    destination       = data.oci_core_services.all.services[0].cidr_block                 # 宛先。取得した「すべてのサービス」のCIDRラベルを使用する
    destination_type  = "SERVICE_CIDR_BLOCK"                                              # 宛先の種類。サービスCIDRラベルで指定する
    network_entity_id = oci_core_service_gateway.this.id                                  # ターゲット。同一構成で作成したService Gatewayとする
  }
}

# Oracle Linuxサブネットのルート表を定義する。
# パッケージはOSMHのソフトウェア・ソースから取得するため、Service Gatewayへの経路だけを持つ。
resource "oci_core_route_table" "linux" {
  compartment_id = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  vcn_id         = oci_core_vcn.this.id        # 所属するVCN。同一構成で作成したVCNを使用する
  display_name   = "linux-rt"                  # OCIの表示名。役割がわかる名称とする

  # Oracle Services Network宛ての経路。OS Management Hub用
  route_rules {
    description       = "Oracle Services Network via Service Gateway (OS Management Hub)" # ルールの説明。用途を示す
    destination       = data.oci_core_services.all.services[0].cidr_block                 # 宛先。取得した「すべてのサービス」のCIDRラベルを使用する
    destination_type  = "SERVICE_CIDR_BLOCK"                                              # 宛先の種類。サービスCIDRラベルで指定する
    network_entity_id = oci_core_service_gateway.this.id                                  # ターゲット。同一構成で作成したService Gatewayとする
  }
}

# ============================================================
# Security List
# ============================================================

# Bastionサブネットのセキュリティ・リストを定義する。
# BastionはNSGに対応していないため、セキュリティ・リストで接続先のサブネットとポートを限定する。
resource "oci_core_security_list" "bastion" {
  compartment_id = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  vcn_id         = oci_core_vcn.this.id        # 所属するVCN。同一構成で作成したVCNを使用する
  display_name   = "bastion-sl"                # OCIの表示名。役割がわかる名称とする

  # 送信ルール。local.instances の各インスタンスについて、所属サブネットの接続ポートだけを許可する
  dynamic "egress_security_rules" {
    for_each = local.instances # 生成単位。local.instances のキー（windows / linux）ごとに作成する

    content {
      description      = "Bastion session to ${egress_security_rules.key}"   # ルールの説明。接続先のインスタンスを示す
      destination      = local.subnets[egress_security_rules.key].cidr_block # 宛先。インスタンスと同じキーのサブネットのCIDRを使用する
      destination_type = "CIDR_BLOCK"                                        # 宛先の種類。CIDR表記で指定する
      protocol         = "6"                                                 # プロトコル。TCPとする
      stateless        = false                                               # ステートレス。戻り通信を自動で許可するためステートフルとする

      # 宛先ポート。local.instances の remote_port（RDP / SSH）だけを許可する
      tcp_options {
        min = egress_security_rules.value.remote_port # 宛先ポートの下限。接続ポートを設定する
        max = egress_security_rules.value.remote_port # 宛先ポートの上限。接続ポートを設定する
      }
    }
  }
}

# インスタンス用サブネットのセキュリティ・リストを定義する。
# 通信はNSGで制御するため、デフォルト・セキュリティ・リストの代わりに関連付ける空のリストとする。
resource "oci_core_security_list" "instance" {
  for_each = local.instances # 作成単位。local.instances のキー（windows / linux）ごとに作成する

  compartment_id = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  vcn_id         = oci_core_vcn.this.id        # 所属するVCN。同一構成で作成したVCNを使用する
  display_name   = "${each.key}-sl"            # OCIの表示名。キーと種類の略称を組み合わせる
}

# ============================================================
# Subnet
# ============================================================

# 構成図の3つのプライベート・サブネット（リージョナル）を定義する。
# パブリックIPの割当を禁止し、インターネットから直接到達できないようにする。
resource "oci_core_subnet" "this" {
  for_each = local.subnets # 作成単位。local.subnets のキー（bastion / windows / linux）ごとに作成する

  compartment_id             = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  vcn_id                     = oci_core_vcn.this.id        # 所属するVCN。同一構成で作成したVCNを使用する
  cidr_block                 = each.value.cidr_block       # IPv4アドレス範囲。local.subnets の定義値を使用する
  display_name               = "${each.key}-sn"            # OCIの表示名。キーと種類の略称を組み合わせる
  dns_label                  = each.value.dns_label        # VCN内DNSのラベル。local.subnets の定義値を使用する（作成後は変更不可）
  prohibit_public_ip_on_vnic = true                        # VNICへのパブリックIP割当。許可しない
  # 使用するルート表。サブネットと同じキーのルート表を関連付ける
  route_table_id = {
    bastion = oci_core_route_table.bastion.id
    windows = oci_core_route_table.windows.id
    linux   = oci_core_route_table.linux.id
  }[each.key]
  # 使用するセキュリティ・リスト。Bastionは専用のリスト、インスタンス用は空のリストを関連付ける
  security_list_ids = [
    each.key == "bastion" ? oci_core_security_list.bastion.id : oci_core_security_list.instance[each.key].id,
  ]
}

# ============================================================
# Network Security Group
# ============================================================

# インスタンスごとのNSGを定義する。インスタンスのVNICに関連付けて通信を制御する。
resource "oci_core_network_security_group" "instance" {
  for_each = local.instances # 作成単位。local.instances のキー（windows / linux）ごとに作成する

  compartment_id = local.tagged_compartment_id # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  vcn_id         = oci_core_vcn.this.id        # 所属するVCN。同一構成で作成したVCNを使用する
  display_name   = "${each.key}-nsg"           # OCIの表示名。キーと種類の略称を組み合わせる
}

# NSGの受信ルールを定義する。Bastionサブネットからのリモート接続ポートだけを許可する。
resource "oci_core_network_security_group_security_rule" "instance_ingress_from_bastion" {
  for_each = local.instances # 作成単位。local.instances のキー（windows / linux）ごとに作成する

  network_security_group_id = oci_core_network_security_group.instance[each.key].id # 対象のNSG。同じキーのNSGを指定する
  direction                 = "INGRESS"                                             # 通信方向。受信とする
  protocol                  = "6"                                                   # プロトコル。TCPとする
  description               = "Remote access from Bastion private endpoint"         # ルールの説明。用途を示す
  source                    = local.subnets.bastion.cidr_block                      # 送信元。BastionサブネットのCIDRを使用する
  source_type               = "CIDR_BLOCK"                                          # 送信元の種類。CIDR表記で指定する
  stateless                 = false                                                 # ステートレス。戻り通信を自動で許可するためステートフルとする

  # 宛先ポート。local.instances の remote_port（RDP / SSH）だけを許可する
  tcp_options {
    destination_port_range {
      min = each.value.remote_port # 宛先ポートの下限。接続ポートを設定する
      max = each.value.remote_port # 宛先ポートの上限。接続ポートを設定する
    }
  }
}

# NSGの送信ルールを定義する。
# 到達できる宛先はサブネットのルート表で制限するため、NSGでは全宛先を許可する。
resource "oci_core_network_security_group_security_rule" "instance_egress_all" {
  for_each = local.instances # 作成単位。local.instances のキー（windows / linux）ごとに作成する

  network_security_group_id = oci_core_network_security_group.instance[each.key].id # 対象のNSG。同じキーのNSGを指定する
  direction                 = "EGRESS"                                              # 通信方向。送信とする
  protocol                  = "all"                                                 # プロトコル。すべてのプロトコルを許可する
  description               = "Allow all outbound traffic"                          # ルールの説明。用途を示す
  destination               = "0.0.0.0/0"                                           # 宛先。すべてのIPv4アドレスとする
  destination_type          = "CIDR_BLOCK"                                          # 宛先の種類。CIDR表記で指定する
  stateless                 = false                                                 # ステートレス。戻り通信を自動で許可するためステートフルとする
}
