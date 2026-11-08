locals {
  # VCN全体のIPアドレス範囲。構成図のVCN（10.0.0.0/16）に合わせる
  vcn_cidr_block = "10.0.0.0/16"

  # サブネットの定義。キーはTerraformアドレスに使うため、表示名を変えても変更しない
  subnets = {
    bastion = {
      cidr_block = "10.0.1.0/24" # Bastionのプライベート・エンドポイントを置くサブネット
      dns_label  = "bastion"     # VCN内DNSのサブネット名
    }
    windows = {
      cidr_block = "10.0.2.0/24" # Windows Serverを置くサブネット
      dns_label  = "windows"     # VCN内DNSのサブネット名
    }
    linux = {
      cidr_block = "10.0.3.0/24" # Oracle Linuxを置くサブネット
      dns_label  = "linux"       # VCN内DNSのサブネット名
    }
  }

  # インスタンスの定義。キーは同名のサブネット・NSG・Bastionセッションと対応させる
  instances = {
    windows = {
      operating_system         = "Windows"              # イメージ検索に使うOS名
      operating_system_version = "Server 2025 Standard" # イメージ検索に使うOSバージョン
      hostname_label           = "win"                  # VCN内DNSのホスト名
      boot_volume_size_in_gbs  = 256                    # ブートボリューム容量。Windowsイメージの既定サイズに合わせる
      remote_port              = 3389                   # Bastion経由で接続するポート（RDP）
      # Oracle Cloud Agentのプラグイン。Windowsで提供されるプラグインすべての状態を明示する
      agent_plugins = [
        { name = "Custom Logs Monitoring", desired_state = "DISABLED" },               # Loggingへのカスタムログ収集。使用しない
        { name = "Compute Instance Monitoring", desired_state = "DISABLED" },          # CPU・メモリなどのメトリクス収集。OSMHの挙動確認には不要なため使用しない
        { name = "Compute Instance Run Command", desired_state = "DISABLED" },         # コンソールからのコマンド実行。使用しない
        { name = "Cloud Guard Workload Protection", desired_state = "DISABLED" },      # Cloud Guardのワークロード保護。使用しない
        { name = "Block Volume Management", desired_state = "DISABLED" },              # ブロック・ボリュームの自動接続。追加ボリュームがないため使用しない
        { name = "Vulnerability Scanning", desired_state = "DISABLED" },               # 脆弱性スキャン。使用しない
        { name = "OS Management Hub Agent", desired_state = "ENABLED" },               # OS Management Hubへの登録・管理。必須のため有効
        { name = "Fleet Application Management Service", desired_state = "DISABLED" }, # Fleet Application Management。使用しない
      ]
    }
    linux = {
      operating_system         = "Oracle Linux" # イメージ検索に使うOS名
      operating_system_version = "10"           # イメージ検索に使うOSバージョン
      hostname_label           = "ol"           # VCN内DNSのホスト名
      boot_volume_size_in_gbs  = 50             # ブートボリューム容量。最小値の50GBとする
      remote_port              = 22             # Bastion経由で接続するポート（SSH）
      # Oracle Cloud Agentのプラグイン。Oracle Linuxで提供されるプラグインすべての状態を明示する
      agent_plugins = [
        { name = "Custom Logs Monitoring", desired_state = "DISABLED" },               # Loggingへのカスタムログ収集。使用しない
        { name = "Compute Instance Monitoring", desired_state = "DISABLED" },          # CPU・メモリなどのメトリクス収集。OSMHの挙動確認には不要なため使用しない
        { name = "Compute Instance Run Command", desired_state = "DISABLED" },         # コンソールからのコマンド実行。使用しない
        { name = "Cloud Guard Workload Protection", desired_state = "DISABLED" },      # Cloud Guardのワークロード保護。使用しない
        { name = "Block Volume Management", desired_state = "DISABLED" },              # ブロック・ボリュームの自動接続。追加ボリュームがないため使用しない
        { name = "Bastion", desired_state = "DISABLED" },                              # マネージドSSHセッション用。ポートフォワーディングのみのため使用しない
        { name = "WebLogic Management Service", desired_state = "DISABLED" },          # WebLogicの管理。使用しない
        { name = "Vulnerability Scanning", desired_state = "DISABLED" },               # 脆弱性スキャン。使用しない
        { name = "Oracle Java Management Service", desired_state = "DISABLED" },       # Javaの管理。使用しない
        { name = "OS Management Hub Agent", desired_state = "ENABLED" },               # OS Management Hubへの登録・管理。必須のため有効
        { name = "Management Agent", desired_state = "DISABLED" },                     # Management Agentサービス。使用しない
        { name = "Fleet Application Management Service", desired_state = "DISABLED" }, # Fleet Application Management。使用しない
        { name = "Compute RDMA GPU Monitoring", desired_state = "DISABLED" },          # RDMA・GPUシェイプの監視。対象シェイプではないため使用しない
        { name = "Compute HPC RDMA Auto-Configuration", desired_state = "DISABLED" },  # HPCシェイプのRDMA自動設定。対象シェイプではないため使用しない
        { name = "Compute HPC RDMA Authentication", desired_state = "DISABLED" },      # HPCシェイプのRDMA認証。対象シェイプではないため使用しない
      ]
    }
  }

  # 検証用コンパートメント内に作るリソースの配置先。
  # タグ・デフォルトは作成後に作られたリソースにだけ付くため、タグ・デフォルト経由で参照し、
  # タグ・デフォルトの作成完了後にリソースが作られるようにする。
  tagged_compartment_id = oci_identity_tag_default.system_name.compartment_id
}
