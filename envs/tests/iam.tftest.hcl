# ============================================================
# IAM Test
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

# 動的グループとポリシーで、OSMHの権限が検証用コンパートメントに限定されることを検証する。
run "osmh_permissions_are_scoped_to_compartment" {
  command = apply # モックの範囲でapplyし、作成後に決まるコンパートメントのOCIDを含めて検証する（実リソースは作成しない）

  # 動的グループの一致ルールが、検証用コンパートメント内のインスタンスだけを対象にすることを確認する。
  assert {
    condition     = oci_identity_dynamic_group.osmh_instances.matching_rule == "ALL {instance.compartment.id = '${oci_identity_compartment.this.id}'}" # 検証用コンパートメントのOCIDが埋め込まれていることを確認する
    error_message = "動的グループの一致ルールは、検証用コンパートメント内のインスタンスだけを対象にする必要があります。"                                                                                # 失敗時の診断内容
  }

  # Agent用のポリシー文が、自身に対応する管理対象インスタンスへのアクセスだけを許可することを確認する。
  assert {
    condition = oci_identity_policy.osmh_agent.statements == tolist([
      "Allow dynamic-group Default/osmh-instances to {OSMH_MANAGED_INSTANCE_ACCESS} in compartment osmh-organize where request.principal.id = target.managed-instance.id",
    ])                                                # ドメイン名・動的グループ名・コンパートメント名を埋め込んだポリシー文を確認する
    error_message = "OSMH Agent用のポリシー文が期待する値と一致しません。" # 失敗時の診断内容
  }

  # 動的セット用のポリシー文が、主体を動的セットに限定した参照権限であることを確認する。
  assert {
    condition = oci_identity_policy.osmh_dynamic_sets.statements == tolist([
      "Allow any-user to read instances in compartment osmh-organize where request.principal.type = 'osmh-dynamic-sets'",
    ])                                                                               # where句で主体を動的セットに限定していることを確認する
    error_message = "動的セット用のポリシー文が期待する値と一致しません。any-user を使う場合は where 句で主体を限定してください。" # 失敗時の診断内容
  }
}

# タグ・デフォルトとOS種別のタグが、設計どおりに定義されることを検証する。
run "tags_are_defined_as_designed" {
  command = apply # モックの範囲でapplyし、タグ・デフォルトを経由した参照を検証する

  # タグ・デフォルトが、入力変数のシステムネームを検証用コンパートメントに設定することを確認する。
  assert {
    condition = (
      oci_identity_tag_default.system_name.value == "osmh-test" &&
      oci_identity_tag_default.system_name.compartment_id == oci_identity_compartment.this.id
    )                                                                   # 値と適用先コンパートメントを確認する
    error_message = "タグ・デフォルトは、system_name の値を検証用コンパートメントに設定する必要があります。" # 失敗時の診断内容
  }

  # タグ・デフォルト経由で参照したコンパートメントに、リソースが作られることを確認する。
  assert {
    condition     = oci_core_vcn.this.compartment_id == oci_identity_compartment.this.id # local.tagged_compartment_id が検証用コンパートメントを指すことを確認する
    error_message = "リソースは、タグ・デフォルトを設定した検証用コンパートメントに作成する必要があります。"                        # 失敗時の診断内容
  }

  # 反映待ちを経由して参照するタグ・キーが「<ネームスペース>.<タグ・キー>」の形式であることを確認する。
  assert {
    condition     = time_sleep.os_type_tag_propagation.triggers["tag_key"] == "Common.OSType" # ネームスペース名とタグ・キー名の組み立て結果を確認する
    error_message = "OS種別のタグ・キーは Common.OSType である必要があります。"                                   # 失敗時の診断内容
  }

  # OS種別のタグの値が、本構成のOSの種別に限定されることを確認する。
  assert {
    condition = (
      oci_identity_tag.os_type.validator[0].validator_type == "ENUM" &&
      toset(oci_identity_tag.os_type.validator[0].values) == toset(["Linux", "WindowsServer"])
    )                                                                  # 検証の種類と指定できる値を確認する
    error_message = "OS種別のタグは、Linux / WindowsServer の列挙値に限定する必要があります。" # 失敗時の診断内容
  }
}
