# ============================================================
# Bastion
# ============================================================

# プライベート・サブネットのインスタンスへ接続するためのBastionを定義する。
# 接続元は入力変数で指定したCIDRに限定する。
resource "oci_bastion_bastion" "this" {
  bastion_type                 = "standard"                         # Bastionの種類。標準のBastionとする
  compartment_id               = local.tagged_compartment_id        # 配置先コンパートメント。タグ・デフォルト設定済みの検証用コンパートメントを使用する
  target_subnet_id             = oci_core_subnet.this["bastion"].id # プライベート・エンドポイントを置くサブネット。Bastionサブネットを使用する
  name                         = "osmhbastion"                      # Bastion名。英数字のみ使えるため記号を含めない（作成後は変更不可）
  client_cidr_block_allow_list = var.bastion_client_cidr_blocks     # 接続を許可する接続元。入力変数で指定した作業端末のCIDRとする
  dns_proxy_status             = "DISABLED"                         # FQDN・SOCKS5プロキシ対応。IPアドレス指定のポートフォワーディングのみのため無効にする
  max_session_ttl_in_seconds   = 10800                              # セッションの最大有効期間。上限の3時間とする
}

# ============================================================
# Bastion Session
# ============================================================

# 各インスタンスへのSSHポートフォワーディング・セッションを定義する。
# セッションはTTL経過後にOCI側で削除されるため、期限切れ後は
# terraform apply -replace='oci_bastion_session.this["<key>"]' で作り直す。
resource "oci_bastion_session" "this" {
  for_each = local.instances # 作成単位。local.instances のキー（windows / linux）ごとに作成する

  bastion_id             = oci_bastion_bastion.this.id        # 使用するBastion。同一構成で作成したBastionを指定する
  display_name           = "${each.key}-session"              # セッション名。キーを使い接続先がわかる名称とする
  key_type               = "PUB"                              # 鍵の種類。OpenSSH形式の公開鍵とする
  session_ttl_in_seconds = var.bastion_session_ttl_in_seconds # セッションの有効期間。入力変数の値を使用する

  # セッション接続に使う公開鍵。入力変数で指定したファイルから読み込む
  key_details {
    public_key_content = file(var.bastion_ssh_public_key_path) # 公開鍵の内容。インスタンスのログイン用とは別の bastion_ssh_public_key_path を読み込む
  }

  # 接続先の設定
  target_resource_details {
    session_type                       = "PORT_FORWARDING"                           # セッションの種類。Bastionプラグイン不要のポートフォワーディングとする
    target_resource_id                 = oci_core_instance.this[each.key].id         # 接続先インスタンス。同じキーのインスタンスを指定する
    target_resource_private_ip_address = oci_core_instance.this[each.key].private_ip # 接続先IP。同じキーのインスタンスのプライベートIPを使用する
    target_resource_port               = each.value.remote_port                      # 接続先ポート。local.instances の remote_port（RDP / SSH）を使用する
  }
}
