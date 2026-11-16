# ============================================================
# OS Management Hub Test
# ============================================================

# OCI ProviderのAPI操作をモック化し、実リソースを作成しない。
# ベンダー・ソフトウェア・ソースの検索結果など、共通のモック値は tests/mocks/ に定義する。
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

# Oracle Linux 10のグループに、サービス提供のプロファイルと同じベンダー・ソフトウェア・ソースがすべて割り当たることを検証する。
run "ol10_group_gets_all_vendor_software_sources" {
  command = apply # モックの範囲でapplyし、複製したソフトウェア・ソースのOCIDで割り当てを検証する（実リソースは作成しない）

  # サービス提供のプロファイルと同じ7つのベンダー・ソフトウェア・ソースが複製されることを確認する。
  assert {
    condition = toset(keys(oci_os_management_hub_software_source.ol10_x86_64_vendor)) == toset([
      "ol10_baseos_latest-x86_64",
      "ol10_appstream-x86_64",
      "ol10_uekr8-x86_64",
      "ol10_addons-x86_64",
      "ol10_oci_included-x86_64",
      "ol10_ksplice-x86_64",
      "ol10_x86_64_userspace_ksplice-x86_64",
    ])                                                              # 複製するソフトウェア・ソースの表示名の一覧を確認する
    error_message = "複製するベンダー・ソフトウェア・ソースが、サービス提供のプロファイルの構成と一致しません。" # 失敗時の診断内容
  }

  # グループの作成時には、BaseOSだけが割り当てられることを確認する。
  assert {
    condition     = oci_os_management_hub_managed_instance_group.ol10_x86_64.software_source_ids == tolist([oci_os_management_hub_software_source.ol10_x86_64_vendor["ol10_baseos_latest-x86_64"].id]) # BaseOSのOCIDだけであることを確認する
    error_message = "グループの作成時に割り当てるソフトウェア・ソースはBaseOSだけである必要があります。"                                                                                                                                     # 失敗時の診断内容
  }

  # 追加の割り当て（attach）には、BaseOSが含まれないことを確認する。
  assert {
    condition = !contains(
      oci_os_management_hub_managed_instance_group_attach_software_sources_management.ol10_x86_64_software_sources.software_sources,
      oci_os_management_hub_software_source.ol10_x86_64_vendor["ol10_baseos_latest-x86_64"].id,
    )                                                                  # 作成時に割り当て済みのBaseOSを重複して追加しないことを確認する
    error_message = "追加で割り当てるソフトウェア・ソースにBaseOSを含めないでください（作成時に割り当て済み）。" # 失敗時の診断内容
  }

  # 作成時の割り当てと追加の割り当てを合わせると、複製したソフトウェア・ソースがすべて割り当たることを確認する。
  assert {
    condition = toset(concat(
      oci_os_management_hub_managed_instance_group.ol10_x86_64.software_source_ids,
      oci_os_management_hub_managed_instance_group_attach_software_sources_management.ol10_x86_64_software_sources.software_sources,
    )) == toset([for source in oci_os_management_hub_software_source.ol10_x86_64_vendor : source.id]) # 割り当て済みのOCIDの集合が複製した全OCIDと一致することを確認する
    error_message = "グループに割り当て漏れのソフトウェア・ソースがあります。AppStreamなどが欠けると依存関係の解決に失敗します。"                      # 失敗時の診断内容
  }
}

# 登録プロファイルが、OSごとに設計どおりの登録先・種類で作られることを検証する。
run "registration_profiles_match_os" {
  command = apply # モックの範囲でapplyし、参加先グループのOCIDとの対応を検証する

  # Oracle Linux 10用のプロファイルが、グループに参加させるプロファイルであることを確認する。
  assert {
    condition = (
      oci_os_management_hub_profile.ol10_x86_64_group.profile_type == "GROUP" &&
      oci_os_management_hub_profile.ol10_x86_64_group.registration_type == "OCI_LINUX" &&
      oci_os_management_hub_profile.ol10_x86_64_group.managed_instance_group_id == oci_os_management_hub_managed_instance_group.ol10_x86_64.id
    )                                                                                       # プロファイル・タイプ、登録の種類、参加先のグループを確認する
    error_message = "Oracle Linux 10用のプロファイルは、ol10_x86_64 グループに参加させるGROUPプロファイルである必要があります。" # 失敗時の診断内容
  }

  # Windows Server 2025用のプロファイルが、スタンドアロンのプロファイルであることを確認する。
  assert {
    condition = (
      oci_os_management_hub_profile.windows_server_2025_x86_64.profile_type == "WINDOWS_STANDALONE" &&
      oci_os_management_hub_profile.windows_server_2025_x86_64.registration_type == "OCI_WINDOWS" &&
      oci_os_management_hub_profile.windows_server_2025_x86_64.os_family == "WINDOWS_SERVER_2025"
    )                                                                                   # プロファイル・タイプ、登録の種類、OSファミリーを確認する
    error_message = "Windows Server 2025用のプロファイルは、WINDOWS_STANDALONEのプロファイルである必要があります。" # 失敗時の診断内容
  }
}

# Windows Server 2025の動的セットが、検証用コンパートメントの対象OSだけを検索することを検証する。
run "windows_dynamic_set_targets_compartment" {
  command = apply # モックの範囲でapplyし、検索対象のコンパートメントのOCIDを検証する

  # 検索対象が検証用コンパートメントだけであることを確認する。
  assert {
    condition = (
      oci_os_management_hub_dynamic_set.windows_server_2025_x86_64.target_compartments[0].compartment_id == oci_identity_compartment.this.id &&
      oci_os_management_hub_dynamic_set.windows_server_2025_x86_64.target_compartments[0].does_include_children == false
    )                                                      # 検証用コンパートメントのOCIDと、子コンパートメントを含めないことを確認する
    error_message = "動的セットの検索対象は、検証用コンパートメントだけにする必要があります。" # 失敗時の診断内容
  }

  # OSとアーキテクチャの両方に一致するインスタンスだけを対象にすることを確認する。
  assert {
    condition = (
      oci_os_management_hub_dynamic_set.windows_server_2025_x86_64.match_type == "ALL" &&
      oci_os_management_hub_dynamic_set.windows_server_2025_x86_64.matching_rule[0].os_families == tolist(["WINDOWS_SERVER_2025"]) &&
      oci_os_management_hub_dynamic_set.windows_server_2025_x86_64.matching_rule[0].architectures == tolist(["X86_64"])
    )                                                               # 条件の組み合わせとOS・アーキテクチャを確認する
    error_message = "動的セットの条件が、Windows Server 2025（x86_64）と一致しません。" # 失敗時の診断内容
  }
}
