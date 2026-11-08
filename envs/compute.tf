# ============================================================
# Compute Instance
# ============================================================

# OS Management Hubで管理するWindows ServerとOracle Linuxのインスタンスを定義する。
# どちらもプライベート・サブネットに置き、Bastion経由でのみ接続する。
resource "oci_core_instance" "this" {
  for_each = local.instances # 作成単位。local.instances のキー（windows / linux）ごとに作成する

  compartment_id                      = local.tagged_compartment_id                                              # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  availability_domain                 = data.oci_identity_availability_domains.this.availability_domains[0].name # 配置先AD。取得したADの先頭を使用する
  fault_domain                        = data.oci_identity_fault_domains.this.fault_domains[0].name               # 配置先FD。構成図に合わせ、取得したFDの先頭に2台とも置く
  display_name                        = each.key                                                                 # OCIの表示名。キー（windows / linux）を使用する
  shape                               = var.instance_shape                                                       # シェイプ。入力変数で指定したFlexシェイプを使用する
  is_pv_encryption_in_transit_enabled = true                                                                     # ブートボリュームの転送中暗号化。有効にする
  preserve_boot_volume                = false                                                                    # 削除時のブートボリューム保持。検証環境のため保持しない
  # インスタンスのメタデータ。OSごとに設定する。
  # ＜Oracle Linux＞
  # ssh_authorized_keys：instance_ssh_public_key_path の公開鍵をopcに登録する。
  #   Bastionセッション用の鍵とは分け、片方の鍵が漏えいしてもOSへはログインできないようにする
  # user_data：userdata/oraclelinux_init.yaml（cloud-config）を初回起動時に実行し、タイムゾーン・日本語ロケールの設定と
  #   SELinuxの無効化（検証用途）を行い、cloud-init完了後に power_state で再起動する
  # ＜Windows Server＞
  # user_data：userdata/windows_init.ps1 をcloudbase-initが初回起動時に実行し、表示言語・ロケール・キーボード・
  #   タイムゾーンを日本向けに設定して再起動する
  #
  # Windowsはuser_dataでパスワードを変更しない（セキュリティ対応）。
  # Terraformでパスワードを変更すれば初回ログイン時の変更は不要になるが、user_dataはインスタンスの
  # メタデータとして平文で保存され、OS上のメタデータ・サービス、OCIのコンソール・API、Terraform Stateから
  # パスワードを読み取れてしまう。そのため初期パスワード（windows_initial_credentials）でログインし、
  # 初回ログイン時にOS上でパスワードを変更する
  metadata = each.key == "linux" ? {
    ssh_authorized_keys = file(var.instance_ssh_public_key_path)
    user_data           = base64encode(file("${path.module}/userdata/oraclelinux_init.yaml"))
    } : {
    user_data = base64encode(file("${path.module}/userdata/windows_init.ps1"))
  }

  # Oracle Cloud Agentの設定。OS Management Hub Agentなど、必要なプラグインだけを有効にする
  agent_config {
    # 以下3つはプラグインを分類ごとに止める親スイッチ。trueにすると plugins_config のENABLEDが効かなくなる。
    # 個別の有効・無効は plugins_config で管理するため、親スイッチはすべて無効化しない（既定値もfalse）
    are_all_plugins_disabled = false # 全プラグインの一括無効化。個別設定を効かせるため無効化しない
    is_management_disabled   = false # 管理系（OS Management Service Agent・Run Command）の一括無効化。個別設定に任せるため無効化しない
    is_monitoring_disabled   = false # 監視系（Compute Instance Monitoring・Custom Logs Monitoring）の一括無効化。個別設定に任せるため無効化しない

    # 各プラグインの状態。OSごとに提供されるプラグインが異なるため、local.instances の agent_plugins を展開する
    dynamic "plugins_config" {
      for_each = each.value.agent_plugins # 生成単位。local.instances に定義したプラグインごとに作成する

      content {
        name          = plugins_config.value.name          # プラグイン名。agent_plugins の定義値を使用する
        desired_state = plugins_config.value.desired_state # プラグインの状態。agent_plugins の定義値（ENABLED / DISABLED）を使用する
      }
    }
  }

  # 保守イベント時の可用性設定
  availability_config {
    # false：再起動を伴う移行になる（通知後、期限までに自分で再起動するか、期限にOracleが再起動する）
    # 省略（null）：Oracleが移行方法を選ぶ
    is_live_migration_preferred = true # ライブ・マイグレーションの優先。停止を避けるため優先する
    # ハードウェア障害などでライブ・マイグレーションできず、インスタンスを復旧した場合に適用される
    # STOP_INSTANCE：保守前の状態にかかわらず、停止状態で復旧する
    recovery_action = "RESTORE_INSTANCE" # 保守後の状態。保守前の状態（起動中なら起動、停止中なら停止のまま）に戻す
  }

  # プライマリVNICの設定
  create_vnic_details {
    subnet_id        = oci_core_subnet.this[each.key].id                       # 所属サブネット。同じキーのサブネットを使用する
    nsg_ids          = [oci_core_network_security_group.instance[each.key].id] # 関連付けるNSG。同じキーのNSGを使用する
    assign_public_ip = false                                                   # パブリックIPの割当。プライベート・サブネットのため割り当てない
    # 最大63文字 (Windowsは15文字)
    # 英数字、ハイフンは使用可
    # ピリオドは使用不可
    # 先頭 or 末尾にハイフンは使用不可
    # 数字のみになることは不可
    # RFC952 及び RFC1123 に準拠する必要有
    # 後から変更可
    hostname_label            = each.value.hostname_label # VCN内DNSのホスト名。local.instances の定義値を使用する
    assign_private_dns_record = true                      # プライベートDNSレコードの登録。ホスト名で名前解決できるよう登録する
  }

  # インスタンス・メタデータ・サービスの設定
  instance_options {
    are_legacy_imds_endpoints_disabled = true # 旧IMDS（v1）エンドポイントの無効化。セキュリティのためv2のみとする
  }

  # Flexシェイプのリソース量
  shape_config {
    ocpus         = var.instance_ocpus         # OCPU数。入力変数の値を使用する。ocpus×2=vcpu
    memory_in_gbs = var.instance_memory_in_gbs # メモリ（GB）。入力変数の値を使用する
  }

  # 起動ソース（ブートボリューム）
  source_details {
    source_type             = "image"                                          # ソースの種類。プラットフォーム・イメージから起動する
    source_id               = data.oci_core_images.this[each.key].images[0].id # イメージのOCID。同じキーで取得した最新イメージを使用する
    boot_volume_size_in_gbs = each.value.boot_volume_size_in_gbs               # ブートボリューム容量。local.instances の定義値を使用する
    boot_volume_vpus_per_gb = 10                                               # ブートボリュームの性能。標準の「バランス」とする
  }

  lifecycle {
    # 新しいプラットフォーム・イメージの公開でインスタンスが再作成されないよう、イメージの変更を無視する
    ignore_changes = [source_details[0].source_id]
  }

  # OSMH Agentは起動直後に登録を試みる。参照関係がないため、ポリシーの作成完了を明示的に待つ
  depends_on = [oci_identity_policy.osmh_agent]
}

# ============================================================
# Instance Credentials
# ============================================================

# Windows Serverの初期ユーザー名・パスワードを取得する。
# Bastion経由でRDP接続する際の初回ログインに使用する（初回ログイン時に変更を求められる）。
data "oci_core_instance_credentials" "windows" {
  instance_id = oci_core_instance.this["windows"].id # 対象インスタンス。同一構成で作成したWindows Serverを指定する
}
