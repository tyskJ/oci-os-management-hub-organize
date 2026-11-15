# ============================================================
# OS Management Hub Software Source（Vendor）
# ============================================================

# Oracle Linux 10（x86_64）のベンダー・ソフトウェア・ソースを、検証用コンパートメントへ複製して定義する。
# 管理対象インスタンス・グループに割り当て、所属インスタンスのパッケージ取得元として使用する。
# VENDORで指定できるのは複製元だけで、表示名・URL・OSファミリー・アーキテクチャなどは複製元から引き継がれる。
resource "oci_os_management_hub_software_source" "ol10_x86_64_vendor" {
  for_each = local.ol10_x86_64_vendor_software_sources # 作成単位。local.ol10_x86_64_vendor_software_sources の表示名ごとに作成する

  compartment_id       = local.tagged_compartment_id # 複製先。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  software_source_type = "VENDOR"                    # ソフトウェア・ソースの種類。ベンダー提供のソースの複製とする
  # 複製元。data.tf で同じ表示名で取得したルート・コンパートメントのベンダー・ソフトウェア・ソースを指定する（作成後は変更不可）
  origin_software_source_id = data.oci_os_management_hub_software_sources.ol10_x86_64_vendor[each.key].software_source_collection[0].items[0].id
}

# ============================================================
# OS Management Hub Managed Instance Group
# ============================================================

# Oracle Linux 10（x86_64）の管理対象インスタンスをまとめるグループを定義する。
# グループに割り当てたソフトウェア・ソースを所属インスタンスで共通に使い、ジョブもグループ単位で実行する。
# 所属するインスタンスは、登録プロファイルなどでインスタンスの登録時に追加するため、ここでは指定しない。
resource "oci_os_management_hub_managed_instance_group" "ol10_x86_64" {
  compartment_id = local.tagged_compartment_id               # 作成先。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  display_name   = "ol10-x86_64"                             # グループ名。OSとアーキテクチャがわかる名称とする
  description    = "Oracle Linux 10（x86_64）の管理対象インスタンスのグループ" # 説明。グループの対象を示す
  vendor_name    = "ORACLE"                                  # OSのベンダー。Oracle Linuxのため Oracle とする（作成後は変更不可）
  os_family      = "ORACLE_LINUX_10"                         # OSファミリー。Oracle Linux 10とする（作成後は変更不可）
  arch_type      = "X86_64"                                  # アーキテクチャ。インスタンスのシェイプ（E5.Flex）に合わせx86_64とする（作成後は変更不可）
  location       = "OCI_COMPUTE"                             # インスタンスの場所。省略するとオンプレミスになるため、OCIのコンピュートとする（作成後は変更不可）
  # 作成時に割り当てるソフトウェア・ソース。BaseOSだけを指定し、それ以外は下の attach リソースで追加する
  software_source_ids = [oci_os_management_hub_software_source.ol10_x86_64_vendor["ol10_baseos_latest-x86_64"].id]

  lifecycle {
    # software_source_ids は作成時にだけ反映され、作成後に変更してもグループの更新APIでは割り当てが変わらない。
    # 作成後の追加は attach リソース（ol10_x86_64_software_sources）で行い、
    # 追加後に software_source_ids の値が変わって差分が出ないよう、変更を無視する
    ignore_changes = [software_source_ids]
  }
}

# グループにBaseOS以外のベンダー・ソフトウェア・ソースを追加で割り当てる。
# グループの software_source_ids は作成後に変更しても反映されないため、割り当て用のAPI（AttachSoftwareSources）を使う。
# 注意：本リソースは追加（アタッチ）だけを行う。一覧から外しても、destroyしても、グループからは外れない（外す場合はコンソールなどで行う）。
resource "oci_os_management_hub_managed_instance_group_attach_software_sources_management" "ol10_x86_64_software_sources" {
  managed_instance_group_id = oci_os_management_hub_managed_instance_group.ol10_x86_64.id # 割り当て先。同一構成で作成したOracle Linux 10用のグループを指定する
  # 追加するソフトウェア・ソース。作成時に割り当て済みのBaseOSを除く、同一構成で複製したベンダー・ソフトウェア・ソースを指定する
  software_sources = [
    for name, source in oci_os_management_hub_software_source.ol10_x86_64_vendor : source.id
    if name != "ol10_baseos_latest-x86_64"
  ]
}

# ============================================================
# OS Management Hub Registration Profile
# ============================================================

# Oracle Linux 10（x86_64）のインスタンスを登録するためのプロファイルを定義する。
# プロファイル・タイプをグループとし、登録したインスタンスを ol10_x86_64 グループに参加させる。
# OS・アーキテクチャ・ソフトウェア・ソースはグループの設定を引き継ぐため、ここでは指定しない。
resource "oci_os_management_hub_profile" "ol10_x86_64_group" {
  compartment_id            = local.tagged_compartment_id                                 # 作成先。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  display_name              = "ol10-x86_64-group"                                         # プロファイル名。対象OSとプロファイル・タイプがわかる名称とする（一意である必要がある）
  description               = "Oracle Linux 10（x86_64）をグループに登録するプロファイル"                   # 説明。プロファイルの用途を示す
  profile_type              = "GROUP"                                                     # プロファイル・タイプ。グループに参加させるためグループとする（作成後は変更不可）
  registration_type         = "OCI_LINUX"                                                 # 登録するインスタンスの種類。OCIのLinuxインスタンスとする（作成後は変更不可）
  managed_instance_group_id = oci_os_management_hub_managed_instance_group.ol10_x86_64.id # 参加先のグループ。同一構成で作成したOracle Linux 10用のグループを指定する

  # 参照関係がないため、グループへのソフトウェア・ソースの追加（attach）完了後に作成する。
  # 本プロファイルで登録したインスタンスが、登録直後から全ソフトウェア・ソースを使えるようにする
  depends_on = [oci_os_management_hub_managed_instance_group_attach_software_sources_management.ol10_x86_64_software_sources]
}

# Windows Server 2025（x86_64）のインスタンスを登録するためのプロファイルを定義する。
# Windowsはソフトウェア・ソースを使わず、Windows Updateから更新を取得するため、プロファイル・タイプをスタンドアロンとする。
resource "oci_os_management_hub_profile" "windows_server_2025_x86_64" {
  compartment_id    = local.tagged_compartment_id              # 作成先。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  display_name      = "windows-server-2025-x86_64"             # プロファイル名。対象OSとアーキテクチャがわかる名称とする（一意である必要がある）
  description       = "Windows Server 2025（x86_64）を登録するプロファイル" # 説明。プロファイルの用途を示す
  profile_type      = "WINDOWS_STANDALONE"                     # プロファイル・タイプ。Windowsのスタンドアロンとする（作成後は変更不可）
  registration_type = "OCI_WINDOWS"                            # 登録するインスタンスの種類。OCIのWindowsインスタンスとする（作成後は変更不可）
  vendor_name       = "MICROSOFT"                              # OSのベンダー。Microsoftとする（作成後は変更不可）
  os_family         = "WINDOWS_SERVER_2025"                    # OSファミリー。Windows Server 2025とする（作成後は変更不可）
  arch_type         = "X86_64"                                 # アーキテクチャ。インスタンスのシェイプ（E5.Flex）に合わせx86_64とする（作成後は変更不可）

  lifecycle {
    # software_source_ids は値を省略するとサービス側で決まり、変更すると再作成になる属性。
    # スタンドアロンではソフトウェア・ソースを使わず、Stateに値が入らないため、
    # plan のたびに「apply後に決まる値」と判定されて再作成になる。これを防ぐため変更を無視する。
    # software_sources・lifecycle_environment・lifecycle_stage・managed_instance_group もStateに値が入らず、
    # plan のたびに実際には何も変わらない更新が出るため、あわせて無視する。
    # この4つは入力できない属性のため「Redundant ignore_changes element」の警告が出るが、
    # 外すと更新が出るため、警告は許容する
    ignore_changes = [
      software_source_ids,
      software_sources,
      lifecycle_environment,
      lifecycle_stage,
      managed_instance_group,
    ]
  }
}

# ============================================================
# OS Management Hub Dynamic Set
# ============================================================

# Windows Server 2025（x86_64）の管理対象インスタンスを、条件で動的にまとめる動的セットを定義する。
# Windowsはグループを使わないため、動的セットを対象にジョブ（更新のインストールなど）を実行する。
# 条件に一致するインスタンスはジョブの実行時に検索されるため、所属インスタンスは指定しない。
resource "oci_os_management_hub_dynamic_set" "windows_server_2025_x86_64" {
  compartment_id = local.tagged_compartment_id                    # 作成先。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  display_name   = "windows-server-2025-x86_64"                   # 動的セット名。対象OSとアーキテクチャがわかる名称とする
  description    = "Windows Server 2025（x86_64）の管理対象インスタンスの動的セット" # 説明。動的セットの対象を示す
  match_type     = "ALL"                                          # 条件の組み合わせ。OSとアーキテクチャの両方に一致するインスタンスだけを対象にする

  # 対象インスタンスの条件。OSのバージョンとアーキテクチャで絞り込む
  matching_rule {
    os_families   = ["WINDOWS_SERVER_2025"] # OSのバージョン。Windows Server 2025とする（OSファミリーはバージョン単位の値）
    architectures = ["X86_64"]              # アーキテクチャ。インスタンスのシェイプ（E5.Flex）に合わせx86_64とする
  }

  # インスタンスを検索するコンパートメント
  target_compartments {
    compartment_id        = local.tagged_compartment_id # 検索対象。インスタンスを置く検証用コンパートメントとする
    does_include_children = false                       # 子コンパートメントの検索。子コンパートメントを作らないため含めない
  }
}
