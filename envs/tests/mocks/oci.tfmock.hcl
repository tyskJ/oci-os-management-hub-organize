# ============================================================
# OCI Provider Mock
# ============================================================

# mock_provider "oci" の source で読み込む、OCI Providerのモック値を定義する。
# 本構成は data の結果をインデックス（[0]）で参照するため、モックが既定で返す空のリストのままだと参照に失敗する。
# 各テストファイルで共通に使う値をここにまとめる。値はダミーで、実在するOCIDである必要はない。

# ============================================================
# Availability Domain / Fault Domain
# ============================================================

# 可用性ドメインの一覧。インスタンス・FDの検索に先頭のADを使うため、1件返す
mock_data "oci_identity_availability_domains" {
  defaults = {
    availability_domains = [
      { name = "Uocm:AP-TOKYO-1-AD-1" } # AD名。東京リージョンのAD名の形式に合わせる
    ]
  }
}

# フォールト・ドメインの一覧。インスタンスの配置に先頭のFDを使うため、1件返す
mock_data "oci_identity_fault_domains" {
  defaults = {
    fault_domains = [
      { name = "FAULT-DOMAIN-1" } # FD名。OCIのFD名の形式に合わせる
    ]
  }
}

# ============================================================
# Oracle Services Network
# ============================================================

# 「すべてのサービス」。Service Gatewayとルート表の宛先に使うため、1件返す
mock_data "oci_core_services" {
  defaults = {
    services = [
      {
        id         = "ocid1.service.oc1.ap-tokyo-1.mock"           # サービスのOCID。ダミー値とする
        name       = "All NRT Services In Oracle Services Network" # サービス名。data.tf の正規表現に一致する名前とする
        cidr_block = "all-nrt-services-in-oracle-services-network" # サービスCIDRラベル。ルート表の宛先に使う
      }
    ]
  }
}

# ============================================================
# Platform Image
# ============================================================

# プラットフォーム・イメージの一覧。インスタンスの起動に先頭のイメージを使うため、1件返す
mock_data "oci_core_images" {
  defaults = {
    images = [
      { id = "ocid1.image.oc1.ap-tokyo-1.mock" } # イメージのOCID。ダミー値とする
    ]
  }
}

# ============================================================
# OS Management Hub Vendor Software Source
# ============================================================

# ベンダー・ソフトウェア・ソースの検索結果。複製元に先頭の項目を使うため、1件返す
mock_data "oci_os_management_hub_software_sources" {
  defaults = {
    software_source_collection = [
      {
        items = [
          { id = "ocid1.osmhsoftwaresource.oc1.ap-tokyo-1.mock" } # 複製元のOCID。ダミー値とする
        ]
      }
    ]
  }
}

# ============================================================
# Bastion Session
# ============================================================

# Bastionセッションの接続情報。outputs.tf でコマンドのプレースホルダーを置き換えるため、
# OCIが返すコマンドと同じ形式（<privateKey>・<localPort> を含む）の値を返す
mock_resource "oci_bastion_session" {
  defaults = {
    ssh_metadata = {
      command = "ssh -i <privateKey> -N -L <localPort>:10.0.3.10:22 -p 22 ocid1.bastionsession.oc1.ap-tokyo-1.mock@host.bastion.ap-tokyo-1.oci.oraclecloud.com" # OCIが返すポートフォワーディングのコマンド形式
    }
  }
}
