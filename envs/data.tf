# ============================================================
# Availability Domain
# ============================================================

# リージョン内の可用性ドメインを取得する。
# 構成図は単一ADのため、インスタンスの配置先として先頭のADを使用する。
data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid # 検索対象。ADはテナンシ単位の情報のため、入力変数のテナンシOCIDを指定する
}

# ============================================================
# Fault Domain
# ============================================================

# インスタンスを配置するADのフォールト・ドメインを取得する。
# 構成図は単一FDのため、インスタンスの配置先として先頭のFDを使用する。
data "oci_identity_fault_domains" "this" {
  availability_domain = data.oci_identity_availability_domains.this.availability_domains[0].name # 対象AD。インスタンスと同じく、取得したADの先頭を指定する
  compartment_id      = var.tenancy_ocid                                                         # 検索対象。FDはテナンシ単位の情報のため、入力変数のテナンシOCIDを指定する
}

# ============================================================
# Oracle Services Network
# ============================================================

# Oracle Services Networkの「すべてのサービス」を取得する。
# Service Gatewayの有効化対象と、ルート表の宛先（サービスCIDRラベル）に使用する。
data "oci_core_services" "all" {
  # Object Storageのみのサービスと区別するため、名前で「All ... Services」を特定する
  filter {
    name   = "name"                                         # フィルタ対象の属性。サービス名で絞り込む
    values = ["All .* Services In Oracle Services Network"] # 照合する値。リージョン名部分を正規表現で吸収する
    regex  = true                                           # 正規表現での照合。有効にする
  }
}

# ============================================================
# Platform Image
# ============================================================

# 各インスタンスの起動に使うプラットフォーム・イメージを取得する。
# 新しいイメージが公開されると結果が変わるため、作成後の差分は compute.tf の ignore_changes で抑止する。
data "oci_core_images" "this" {
  for_each = local.instances # 取得単位。local.instances のキー（windows / linux）ごとに取得する

  compartment_id           = var.tenancy_ocid                    # 検索対象。プラットフォーム・イメージはテナンシから参照できる
  operating_system         = each.value.operating_system         # OS名。local.instances の定義値を使用する
  operating_system_version = each.value.operating_system_version # OSバージョン。local.instances の定義値を使用する
  shape                    = var.instance_shape                  # シェイプ。入力変数のシェイプに対応したイメージだけに絞る
  state                    = "AVAILABLE"                         # ライフサイクル状態。利用可能なイメージだけに絞る
  sort_by                  = "TIMECREATED"                       # 並び替えキー。作成日時で並べる
  sort_order               = "DESC"                              # 並び順。新しい順にし、先頭を最新イメージとして使う
}

# ============================================================
# OS Management Hub Vendor Software Source
# ============================================================

# ルート・コンパートメントにあるOracle Linux 10（x86_64）BaseOSのベンダー・ソフトウェア・ソースを取得する。
# 検証用コンパートメントへ複製する際の複製元（osmh.tf の origin_software_source_id）に使用する。
data "oci_os_management_hub_software_sources" "ol10_baseos_latest_x86_64" {
  compartment_id       = var.tenancy_ocid            # 検索対象。ベンダー・ソフトウェア・ソースは常にルート・コンパートメントにある
  software_source_type = ["VENDOR"]                  # ソフトウェア・ソースの種類。ベンダー提供のソースに絞る
  vendor_name          = "ORACLE"                    # ベンダー名。Oracle提供のソースに絞る
  arch_type            = ["X86_64"]                  # アーキテクチャ。インスタンスのシェイプ（E5.Flex）に合わせx86_64に絞る
  display_name         = "ol10_baseos_latest-x86_64" # 表示名。ベンダーが定義するリポジトリ名と完全一致で絞る
}
