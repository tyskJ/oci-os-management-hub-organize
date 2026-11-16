# フォルダ構成

本書は、本プロジェクトのディレクトリ構成と各ファイルの役割を定める。

- [READMEへ戻る](../README.md)
- [Terraformコーディング規約](./terraform-coding-standards.md)
- [Terraform実行手順](./deployment.md)

> [!NOTE]
> 本プロジェクトのTerraformルートモジュールは **`envs/`** の1つだけで、子モジュールは使用しない。Terraformコマンドは `envs/` で実行する。

## 1. ディレクトリ構成

`（Git管理外）` と記載したファイル・ディレクトリは、利用者が手順に従って各自作成する、または実行時に生成されるもので、リポジトリには含まれない。

```text
oci-os-management-hub-organize/
├── README.md                          # プロジェクトの概要・各ドキュメントへの入口
├── .gitignore                         # Git管理から除外するファイルの定義
├── .terraform-version                 # 使用するTerraformのバージョン（tfenv等で参照）
├── .tflint.hcl                        # TFLintの設定
├── .mcp.json                          # Claude Code用のMCPサーバー設定（Terraform MCP Server）
├── docs/                              # ドキュメント
│   ├── folder.md                      # 本書（フォルダ構成）
│   ├── terraform-coding-standards.md  # Terraformコーディング規約
│   ├── deployment.md                  # Terraform実行手順（初期準備・検証・テスト・デプロイ）
│   ├── linux-userdata.md              # Oracle Linuxのuser_dataによる初期化
│   ├── windows-userdata.md            # Windows Serverのuser_dataによる日本語化
│   ├── cleanup.md                     # 環境削除手順
│   ├── troubleshooting.md             # トラブルシューティング
│   ├── assets/                        # ドキュメント用の画像
│   │   ├── samune.png                 # READMEのサムネイル
│   │   └── drawio/
│   │       └── architecture.drawio.png  # 構成図（draw.ioで編集可能なPNG）
│   └── samples/
│       └── oraclelinux_init.sh        # Oracle Linux初期化処理のシェルスクリプト版（参考用。Terraformからは参照しない）
└── envs/                              # Terraformルートモジュール
    ├── terraform.tf                   # Terraform・Providerのバージョン要件
    ├── providers.tf                   # OCI Providerの設定（認証方式・リージョン）
    ├── backend.tf                     # Backendの種類（OCI Object Storage）
    ├── variables.tf                   # 入力変数の宣言
    ├── locals.tf                      # 複数ファイルで共有するローカル値（サブネット・インスタンスの定義など）
    ├── data.tf                        # 複数の機能で共用するdataソース
    ├── iam.tf                         # コンパートメント・定義済みタグ・動的グループ・IAMポリシー
    ├── network.tf                     # VCN・ゲートウェイ・ルート表・セキュリティ・リスト・サブネット・NSG
    ├── compute.tf                     # Windows Server・Oracle Linuxのインスタンス
    ├── bastion.tf                     # Bastion・Bastionセッション
    ├── osmh.tf                        # OS Management Hub（ソフトウェア・ソース・グループ・プロファイル・動的セット）
    ├── outputs.tf                     # 出力値（接続コマンド・Windowsの初期パスワード）
    ├── userdata/                      # インスタンスの初回起動時に実行するuser_data
    │   ├── oraclelinux_init.yaml      # Oracle Linux用（cloud-config）
    │   └── windows_init.ps1           # Windows Server用（PowerShell）
    ├── tests/                         # Terraformのテスト（terraform test）
    │   ├── network.tftest.hcl         # ネットワーク（サブネット・経路・通信制御）
    │   ├── compute.tftest.hcl         # インスタンス（パブリックIP・メタデータ・Agentプラグイン・タグ）
    │   ├── bastion.tftest.hcl         # Bastion（接続元・セッション・出力コマンド）
    │   ├── osmh.tftest.hcl            # OS Management Hub（ソフトウェア・ソースの割り当て・プロファイル・動的セット）
    │   ├── iam.tftest.hcl             # IAM（動的グループ・ポリシー・タグ）
    │   ├── variables.tftest.hcl       # 入力変数のvalidation（境界値・異常系）
    │   ├── mocks/
    │   │   └── oci.tfmock.hcl         # テストで共通に使うOCI Providerのモック値
    │   └── testdata/
    │       ├── bastion_rsa.pub        # テスト用のダミー公開鍵（Bastion用）
    │       └── instance_ed25519.pub   # テスト用のダミー公開鍵（インスタンス用）
    ├── config.oci.tfbackend           # （Git管理外）Backendの設定値（State保存先のバケット等）
    ├── oci.auto.tfvars                # （Git管理外）利用者・テナンシごとの入力変数の値
    ├── .key/                          # （Git管理外）SSH鍵（Bastion用・インスタンス用）
    ├── .terraform/                    # （Git管理外）terraform initで取得したProvider等
    └── .terraform.lock.hcl            # （Git管理外）Providerのバージョン固定（依存関係ロック）
```

## 2. Terraformファイルの分割方針

[Terraformコーディング規約](./terraform-coding-standards.md) の「3. Terraformファイルの命名と配置」に従い、慣習的な標準名のファイルに加えて、リソースを**論理的なまとまり（サービス）ごと**のファイルに分割する。

| ファイル     | 定義するもの                                                                                            | 主な参照先                           |
| ------------ | ------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `iam.tf`     | 検証用コンパートメント、定義済みタグとタグ・デフォルト、OSMH用の動的グループ・IAMポリシー               | 全ファイル（配置先コンパートメント） |
| `network.tf` | VCN、NAT Gateway、Service Gateway、ルート表、セキュリティ・リスト、サブネット、NSG                      | `compute.tf`、`bastion.tf`           |
| `compute.tf` | OSMHで管理するWindows Server・Oracle Linuxのインスタンス、Windowsの初期認証情報                         | `bastion.tf`、`outputs.tf`           |
| `bastion.tf` | Bastion、インスタンスごとのポートフォワーディング・セッション                                           | `outputs.tf`                         |
| `osmh.tf`    | ベンダー・ソフトウェア・ソースの複製、管理対象インスタンス・グループ、登録プロファイル、動的セット      | `compute.tf`（登録プロファイル）     |
| `data.tf`    | 可用性ドメイン、フォールト・ドメイン、Oracle Services Network、イメージ、ベンダー・ソフトウェア・ソース | 各ファイル                           |
| `locals.tf`  | サブネット・インスタンスの定義（`for_each` のキー）、ソフトウェア・ソースの一覧、タグのキー             | 各ファイル                           |

> [!NOTE]
> `local.subnets` と `local.instances` のキー（`windows` / `linux` など）は、サブネット・NSG・インスタンス・Bastionセッションで共通に使い、同じキーのリソース同士を対応させる。キーはTerraformアドレスになるため、表示名を変える場合もキーは変更しない。

## 3. テスト（`envs/tests/`）

[Terraformコーディング規約](./terraform-coding-standards.md) の「16.4 テストコード」に従い、ルートモジュールの `tests/` ディレクトリに配置する。実行方法は [Terraform実行手順](./deployment.md) の「7. テスト」を参照する。

| ファイル・ディレクトリ | 役割                                                                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `*.tftest.hcl`         | テストの定義。機能ごとに分割する。すべて `mock_provider` を使用し、実際のOCIリソースは作成しない                                                        |
| `mocks/`               | `mock_provider "oci"` の `source` で読み込むモック値。dataの結果をインデックスで参照するため、空のリストにならないよう共通のダミー値を定義する          |
| `testdata/`            | テスト用のダミー公開鍵。実際の鍵（`envs/.key/`）はGit管理外のため、テストはこのダミー鍵を使い、作業端末の鍵がない環境（CIなど）でも実行できるようにする |

> [!CAUTION]
> テストを追加する場合も、`mock_provider` を使用し、実際のOCIへ接続しない構成とする。実環境を使うテストを追加する場合は、ディレクトリを分けるなどしてモックのテストと明確に区別する。

## 4. Git管理外のファイル

以下は `.gitignore` の対象で、利用者・環境ごとに作成する。作成手順は [Terraform実行手順](./deployment.md) を参照する。

| ファイル・ディレクトリ      | 内容                                                                 | 作成方法                                      |
| --------------------------- | -------------------------------------------------------------------- | --------------------------------------------- |
| `envs/config.oci.tfbackend` | Backendの設定値（State保存先のバケット・名前空間など）               | 実行手順「3.2 `config.oci.tfbackend` を作成」 |
| `envs/oci.auto.tfvars`      | テナンシOCID、システムネーム、接続元CIDRなどの入力変数の値           | 実行手順「4.2 `oci.auto.tfvars` の作成」      |
| `envs/.key/`                | Bastionセッション用（RSA）・インスタンスログイン用（ed25519）のSSH鍵 | 実行手順「4.1 SSH鍵の作成」                   |
| `envs/.terraform/`          | `terraform init` で取得したProvider                                  | `terraform init` で自動生成                   |
| `envs/.terraform.lock.hcl`  | Providerのバージョン固定                                             | `terraform init` で自動生成                   |
| `*.tfplan` / `tfplan`       | `terraform plan -out` で保存した実行計画                             | `terraform plan -out` で生成                  |

> [!WARNING]
> `oci.auto.tfvars`、`.key/` の秘密鍵、`*.tfplan` には機密情報が含まれ得るため、Gitに追加しないこと。
