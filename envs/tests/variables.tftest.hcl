# ============================================================
# Input Variable Validation Test
# ============================================================

# OCI ProviderのAPI操作をモック化し、実リソースを作成しない。
# data の戻り値など共通のモック値は tests/mocks/ に定義する。
mock_provider "oci" {
  source = "./tests/mocks" # モック値の定義ファイルの場所。envs/ からの相対パスで指定する
}

# time_sleep（タグ・キーの反映待ち）をモック化し、テスト中に待ち時間を発生させない。
mock_provider "time" {}

# 全テストで共通の入力変数。各runでは、検証する変数だけを上書きする。
variables {
  tenancy_ocid                 = "ocid1.tenancy.oc1..mock"               # モック用のテナンシOCID
  system_name                  = "osmh-test"                             # モック用のシステムネーム
  bastion_client_cidr_blocks   = ["203.0.113.10/32"]                     # 接続元CIDR。ドキュメント用アドレス（TEST-NET-3）を使う
  bastion_ssh_public_key_path  = "./tests/testdata/bastion_rsa.pub"      # Bastion用のダミー公開鍵。実際の鍵（.key/）に依存しない
  instance_ssh_public_key_path = "./tests/testdata/instance_ed25519.pub" # インスタンス用のダミー公開鍵。実際の鍵（.key/）に依存しない
}

# ============================================================
# bastion_session_ttl_in_seconds
# ============================================================

# セッションの有効期間の下限（1800秒）は受け付けることを検証する。
run "session_ttl_accepts_lower_bound" {
  command = plan # 入力変数の検証だけを行うため、applyしない

  variables {
    bastion_session_ttl_in_seconds = 1800 # 境界値。許可範囲の下限とする
  }

  # 下限の値がそのままセッションに設定されることを確認する。
  assert {
    condition     = alltrue([for session in oci_bastion_session.this : session.session_ttl_in_seconds == 1800]) # 全セッションの有効期間を確認する
    error_message = "下限の1800秒がセッションの有効期間に設定されていません。"                                                            # 失敗時の診断内容
  }
}

# セッションの有効期間の上限（10800秒）は受け付けることを検証する。
run "session_ttl_accepts_upper_bound" {
  command = plan # 入力変数の検証だけを行うため、applyしない

  variables {
    bastion_session_ttl_in_seconds = 10800 # 境界値。許可範囲の上限とする
  }

  # 上限の値がそのままセッションに設定されることを確認する。
  assert {
    condition     = alltrue([for session in oci_bastion_session.this : session.session_ttl_in_seconds == 10800]) # 全セッションの有効期間を確認する
    error_message = "上限の10800秒がセッションの有効期間に設定されていません。"                                                            # 失敗時の診断内容
  }
}

# セッションの有効期間が下限未満の場合に、入力値の検証で拒否されることを検証する。
run "session_ttl_rejects_below_lower_bound" {
  command = plan # 入力変数の検証だけを行うため、applyしない

  variables {
    bastion_session_ttl_in_seconds = 1799 # 異常値。下限より1秒短い値とする
  }

  expect_failures = [var.bastion_session_ttl_in_seconds] # 期待する失敗。入力変数のvalidationで拒否されることを確認する
}

# セッションの有効期間が上限超過の場合に、入力値の検証で拒否されることを検証する。
run "session_ttl_rejects_above_upper_bound" {
  command = plan # 入力変数の検証だけを行うため、applyしない

  variables {
    bastion_session_ttl_in_seconds = 10801 # 異常値。上限より1秒長い値とする
  }

  expect_failures = [var.bastion_session_ttl_in_seconds] # 期待する失敗。入力変数のvalidationで拒否されることを確認する
}

# ============================================================
# bastion_client_cidr_blocks
# ============================================================

# 接続元CIDRが空の場合に、入力値の検証で拒否されることを検証する。
# 空のままだとBastionへ誰も接続できないため、1件以上の指定を必須とする。
run "client_cidr_rejects_empty_list" {
  command = plan # 入力変数の検証だけを行うため、applyしない

  variables {
    bastion_client_cidr_blocks = [] # 異常値。接続元を1件も指定しない
  }

  expect_failures = [var.bastion_client_cidr_blocks] # 期待する失敗。入力変数のvalidationで拒否されることを確認する
}

# 接続元にプレフィックス長のないIPアドレスを指定した場合に、入力値の検証で拒否されることを検証する。
run "client_cidr_rejects_address_without_prefix" {
  command = plan # 入力変数の検証だけを行うため、applyしない

  variables {
    bastion_client_cidr_blocks = ["203.0.113.10"] # 異常値。作業端末のIPアドレスに /32 を付け忘れた場合を想定する
  }

  expect_failures = [var.bastion_client_cidr_blocks] # 期待する失敗。入力変数のvalidationで拒否されることを確認する
}

# 複数の接続元のうち1件でもCIDR形式でない場合に、入力値の検証で拒否されることを検証する。
run "client_cidr_rejects_partially_invalid_list" {
  command = plan # 入力変数の検証だけを行うため、applyしない

  variables {
    bastion_client_cidr_blocks = ["203.0.113.10/32", "invalid"] # 異常値。正しいCIDRと不正な文字列を混在させる
  }

  expect_failures = [var.bastion_client_cidr_blocks] # 期待する失敗。入力変数のvalidationで拒否されることを確認する
}
