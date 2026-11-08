# ============================================================
# Compartment
# ============================================================

# 本構成のリソースをまとめて配置する検証用コンパートメントを定義する。
# 検証後に環境ごと削除できるよう、destroy時にコンパートメントも削除する。
resource "oci_identity_compartment" "this" {
  compartment_id = var.tenancy_ocid                  # 親コンパートメント。入力変数のテナンシ直下に作成する
  name           = "osmh-organize"                   # コンパートメント名。テナンシ直下で一意の、用途がわかる名称とする
  description    = "${var.system_name} の検証用コンパートメント" # 説明。システムネームを含めて用途を示す
  enable_delete  = true                              # destroy時の削除。有効にし、同名コンパートメントの暗黙importも防ぐ
}

# ============================================================
# Tagging (Defined Tag)
# ============================================================

# 複数システムで共通に使う定義済みタグのネームスペースを定義する。
# 注意：検証用コンパートメントに置いているため、本構成をdestroyするとネームスペースも削除される。
# 他システムからも使う場合は、配置先をテナンシなど本構成の外へ移すことを検討する。
resource "oci_identity_tag_namespace" "this" {
  compartment_id = oci_identity_compartment.this.id # 作成先。同一構成で作成した検証用コンパートメントに置く
  name           = "Common"                         # ネームスペース名。定義済みタグ「<ネームスペース>.<キー>」の接頭辞になる（テナンシ内で一意、作成後は変更不可）
  description    = "複数システム共通の定義済みタグ"                # 説明。共通タグであることを示す
  is_retired     = false                            # 廃止状態。使用中のため廃止しない
}

# システムネームを値に持つタグ・キーを定義する。
# 値はタグ・デフォルトから入れるため、値の候補（validator）は設けない。
resource "oci_identity_tag" "system_name" {
  tag_namespace_id = oci_identity_tag_namespace.this.id # 所属するネームスペース。同一構成で作成したネームスペースを使用する
  name             = "SystemName"                       # タグ・キー名。システムネームを表す名前とする（作成後は変更不可）
  description      = "システムネーム"                          # 説明。キーの意味を示す
  is_cost_tracking = false                              # コスト追跡タグ。テナンシ内の上限数があるため使用しない
  is_retired       = false                              # 廃止状態。使用中のため廃止しない
}

# 検証用コンパートメントにタグ・デフォルトを設定する。
# コンパートメント内で新しく作るリソースに、定義済みタグ「Common.SystemName」が自動で付く。
resource "oci_identity_tag_default" "system_name" {
  compartment_id    = oci_identity_compartment.this.id # 適用先コンパートメント。同一構成で作成した検証用コンパートメントとする
  tag_definition_id = oci_identity_tag.system_name.id  # 付与するタグ・キー。SystemName を指定する
  value             = var.system_name                  # 付与する値。入力変数のシステムネームを使用する
  is_required       = false                            # 値の入力必須化。既定値を自動で付けるだけのため必須にしない
}

# ============================================================
# Dynamic Group
# ============================================================

# OS Management Hub Agentプラグインがインスタンス・プリンシパルで認証するための動的グループを定義する。
# 検証用コンパートメント内のインスタンスをすべて対象とする。
resource "oci_identity_dynamic_group" "osmh_instances" {
  compartment_id = var.tenancy_ocid                              # 作成先。動的グループはテナンシにのみ作成できる
  name           = "osmh-instances"                              # 動的グループ名。テナンシ内で一意の、用途がわかる名称とする
  description    = "${var.system_name} コンパートメント内のOSMH管理対象インスタンス" # 説明。対象範囲を示す
  # 一致ルール。%s に同一構成で作成した検証用コンパートメントのOCIDを入れ、その中のインスタンスに一致させる
  matching_rule = format(
    "ALL {instance.compartment.id = '%s'}",
    oci_identity_compartment.this.id,
  )
}

# ============================================================
# IAM Policy
# ============================================================

# OS Management Hub Agentがインスタンスを登録・管理するための権限を定義する。
# 権限の範囲は検証用コンパートメントに限定する（OSMH公式のコンパートメント単位の記述）。
resource "oci_identity_policy" "osmh_agent" {
  compartment_id = var.tenancy_ocid                              # 作成先。動的グループを参照するためテナンシに作成する
  name           = "osmh-agent"                                  # ポリシー名。テナンシ内で一意の、用途がわかる名称とする
  description    = "OS Management Hub Agentがインスタンスを登録・管理するための権限" # 説明。ポリシーの用途を示す
  # ポリシー文。動的グループのインスタンスに、自身に対応する管理対象インスタンスへのアクセスだけを許可する。
  # 1つ目の %s に同一構成で作成した動的グループ名、2つ目の %s に検証用コンパートメント名を入れる
  statements = [
    format(
      "Allow dynamic-group %s to {OSMH_MANAGED_INSTANCE_ACCESS} in compartment %s where request.principal.id = target.managed-instance.id",
      oci_identity_dynamic_group.osmh_instances.name,
      oci_identity_compartment.this.name,
    ),
  ]
}
