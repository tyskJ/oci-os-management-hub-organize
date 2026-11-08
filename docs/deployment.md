# Terraform実行手順

本書は、本プロジェクトにおける **OCIの初期準備、Terraformの初期化・検証・テスト・デプロイ** の手順を定める。

- [READMEへ戻る](../README.md)
- [環境削除手順](./cleanup.md)
- [トラブルシューティング](./troubleshooting.md)
- [Terraformコーディング規約](./terraform-coding-standards.md)

## 作業ディレクトリ

本プロジェクトでは、`envs/` をTerraformのルートモジュールとして使用する。

TerraformおよびTFLintのコマンドは、原則として `envs/` ディレクトリで実行する。ディレクトリ構成および各ファイルの配置場所については、[フォルダ構成](./folder.md) を参照する。

> [!IMPORTANT]
>
> - 本書のコマンドに含まれる相対パスは、特記がない限り `envs/` を基準とする。
> - OCI CLIによる認証やバケット作成は作業ディレクトリに依存しないが、本書では実行場所を統一する。

リポジトリ直下から、最初に以下を実行する。

```bash
cd envs
```

この移動は本書で1回だけ行う。**以降のコードブロックは、特記がない限り、移動後の `envs/` から実行する。**

## 1. 前提条件

### 1.1 OCI IAM権限

テナンシのルートでIAMポリシーを作成・管理する操作を含むため、対象テナンシおよび各リソースに対する必要権限を持つIAMユーザーで実行する。

IAMユーザーが所属するIAMグループには `manage all-resources in tenancy` を付与する。ただし、これは**非常に広い権限**である。本番運用では最小権限の原則に基づき、必要な操作に応じて権限を限定すること。

### 1.2 OCI CLIの認証

OCI CLIで `ADMIN` プロファイルを作成する。利用リージョンは東京（`ap-tokyo-1`）とする。

```bash
oci session authenticate \
  --region ap-tokyo-1 \
  --profile-name ADMIN
```

以降のOCI CLIコマンドでは `--profile ADMIN --auth security_token` を指定する。セッショントークンには有効期限があるため、期限切れ時は再認証・更新する。

### 1.3 ツールと作業ディレクトリ

Terraformはリポジトリ内の `.terraform-version` に記載されたバージョンを使用する。なお、Terraform CLIがこのファイルを自動で読み込むわけではなく、対応するバージョン管理ツールなどで切り替える。TFLintの設定はリポジトリ直下の `.tflint.hcl` を明示的に指定する。OCI CLI、Terraform、必要に応じてTFLintを事前にインストールする。

> [!IMPORTANT]
> 本書のコマンドはmacOSなどのBash系シェルを想定する。Windows PowerShellで実行する場合は、環境変数・ヒアドキュメント等の構文を置き換える。

## 2. 初期準備（初回のみ）：State用バケット

> [!IMPORTANT]
>
> - 以下はルートコンパートメントへ作成する例。CIS OCI Foundations Benchmarkの該当要件（例：6.2、利用版により確認）や組織のポリシーでルートへのリソース配置が禁止される場合は、State専用のコンパートメントを作成して配置する。
> - 復旧可能性を高めるため、バージョニングを有効化する。
> - バケットのスコープはデフォルトの `NAMESPACE` とする。同一テナンシ・リージョン内でバケット名が一意であればよく、他テナンシ含めたリージョン全体での一意性は必要としない。
> - Stateを格納するバケットはTerraform自身の管理対象に含めない。本プロジェクトのバケット名は `terraform-working` とする。

### 2.1 テナンシOCIDを取得

```bash
TENANCY_ID=$(oci iam compartment list \
  --lifecycle-state ACTIVE \
  --include-root \
  --profile ADMIN \
  --auth security_token \
  --query 'data[?"compartment-id"==null].id | [0]' \
  --raw-output)

printf '%s\n' "$TENANCY_ID"
```

値が取得できない場合は停止し、OCI CLIのプロファイルおよび権限を確認する。

### 2.2 State用バケットを作成

```bash
oci os bucket create \
  --compartment-id "${TENANCY_ID}" \
  --name terraform-working \
  --bucket-scope NAMESPACE \
  --versioning Enabled \
  --public-access-type NoPublicAccess \
  --profile ADMIN \
  --auth security_token
```

既にバケットが存在する場合は重複作成せず、配置コンパートメント、バージョニング、アクセス設定を確認する。

## 3. Backend設定ファイルの作成

### 3.1 Object Storageネームスペースを取得

```bash
NAMESPACE=$(oci os ns get \
  --compartment-id "${TENANCY_ID}" \
  --profile ADMIN \
  --auth security_token \
  --query 'data' \
  --raw-output)

printf '%s\n' "$NAMESPACE"
```

※ `TENANCY_ID` は前節で取得済みとする。新しいシェルを開いた場合は再取得する。

### 3.2 `config.oci.tfbackend` を作成

ルートモジュールの `backend.tf` にはOCI Backendの種類を宣言する。既に定義があれば重複追加しない。

```hcl
terraform {
  backend "oci" {}
}
```

Backendの設定値は、本プロジェクトではルートモジュールの **`envs/config.oci.tfbackend`** に分離する。

```bash
SYSTEM_NAME="oci-os-management-hub-organize"

cat <<EOF > config.oci.tfbackend
bucket              = "terraform-working"
namespace           = "${NAMESPACE}"
key                 = "${SYSTEM_NAME}/terraform.tfstate"
auth                = "SecurityToken"
config_file_profile = "ADMIN"
region              = "ap-tokyo-1"
EOF
```

> [!NOTE]
> Backend設定には `var.xxx` や `local.xxx` は使用できない。`config.oci.tfbackend` は自動読み込みされず、`terraform init -backend-config` で指定する。認証シークレットは設定ファイルへ記載しない。

## 4. 入力変数ファイルの作成

### 4.1 SSH鍵の作成

用途の異なる2本のSSH鍵を `envs/.key/` に作成する。このディレクトリは `.gitignore` の対象とする。

| 鍵                      | 用途                                                  | 種類    |
| ----------------------- | ----------------------------------------------------- | ------- |
| `.key/bastion_rsa`      | Bastionセッション（ポートフォワーディングのトンネル） | RSA     |
| `.key/instance_ed25519` | Oracle Linuxの `opc` ユーザーへのログイン             | ed25519 |

鍵を分けることで、片方の秘密鍵が漏えいしても、Bastionのトンネル確立とOSへのログインの両方を同時に行えないようにする。

```bash
mkdir -p .key
ssh-keygen -t rsa -b 4096 -f .key/bastion_rsa -N ""
ssh-keygen -t ed25519 -f .key/instance_ed25519 -N ""
chmod 600 .key/bastion_rsa .key/instance_ed25519
```

鍵の場所を変える場合は、`oci.auto.tfvars` に `bastion_ssh_public_key_path`・`instance_ssh_public_key_path` を指定する。

### 4.2 `oci.auto.tfvars` の作成

利用者・テナンシごとの値を **`envs/oci.auto.tfvars`** に定義する。このファイルは `.gitignore` の対象とする。

`bastion_client_cidr_blocks` には、Bastionへ接続する作業端末のグローバルIPを指定する。

```bash
MY_GLOBAL_IP=$(curl -s https://checkip.amazonaws.com)

cat <<EOF > oci.auto.tfvars
tenancy_ocid               = "${TENANCY_ID}"
system_name                = "${SYSTEM_NAME}"
bastion_client_cidr_blocks = ["${MY_GLOBAL_IP}/32"]
EOF

chmod 600 oci.auto.tfvars
```

※ `TENANCY_ID` , `SYSTEM_NAME` は前節で取得済みとする。新しいシェルを開いた場合は再取得する。

主な入力変数は以下のとおり。既定値のあるものは必要な場合のみ指定する。

| 変数                             | 既定値                        | 内容                                         |
| -------------------------------- | ----------------------------- | -------------------------------------------- |
| `bastion_client_cidr_blocks`     | なし（必須）                  | Bastionへの接続を許可する接続元CIDR          |
| `bastion_session_ttl_in_seconds` | `10800`                       | Bastionセッションの有効期間（1800〜10800秒） |
| `bastion_ssh_public_key_path`    | `./.key/bastion_rsa.pub`      | Bastionセッション用のSSH公開鍵のパス         |
| `instance_shape`                 | `VM.Standard.E5.Flex`         | Windows Server・Oracle Linux共通のシェイプ   |
| `instance_ocpus`                 | `1`                           | OCPU数                                       |
| `instance_memory_in_gbs`         | `16`                          | メモリ（GB）                                 |
| `instance_ssh_public_key_path`   | `./.key/instance_ed25519.pub` | Oracle Linuxログイン用のSSH公開鍵のパス      |

> [!WARNING]
> 上記は**従来のローカルファイル運用を再現した例**であり、`oci.auto.tfvars` をGitに含めないこと。機密情報がある場合は、可能ならSecret管理基盤や、実行時に安全に渡す `TF_VAR_変数名` 等への切り替えを検討する。入力変数を `sensitive = true` にしてもState内の値が自動的に消えるわけではない。

## 5. Terraformの初期化

```bash
terraform init -backend-config="./config.oci.tfbackend"
```

Backendの設定変更時は再初期化し、State移行の要否を確認する。`-reconfigure` や `-migrate-state` を使用する場合は、その意味を確認してから実行する。

## 6. 静的チェック（Lint）

```bash
# 自動整形（ファイルを書き換える）
terraform fmt -recursive

# 検証のみ実施したい場合はこちら
terraform fmt -check -recursive

# ルートモジュールの構成検証
terraform validate

# .tflint.hcl は1つ上のディレクトリ（リポジトリ直下）にある
tflint --init --config=../.tflint.hcl
tflint --config=../.tflint.hcl
```

| コマンド               | 確認する内容                                                        |
| ---------------------- | ------------------------------------------------------------------- |
| `terraform fmt`        | インデント・属性の配置などの書式を整える                            |
| `terraform fmt -check` | 書式の差分の有無を検査する（ファイルは変更しない）                  |
| `terraform validate`   | Terraform構成の構文・型・参照などの整合性を確認する                 |
| `tflint`               | Terraform言語ルールや、導入プラグインによる追加の静的解析を実施する |

> [!NOTE]
>
> - TFLintはTerraformとは別ツール。インストール方法は [TFLint公式README](https://github.com/terraform-linters/tflint) を参照。
> - `.tflint.hcl` の `plugin "terraform"` に `preset = "recommended"` を指定している場合はその推奨ルールが適用される。
> - `--init` はプラグインの初期化時、または設定更新時に実行する。
> - 今回は `envs/` だけを検査するため、TFLintに `--recursive` は付けない。別の子ディレクトリを独立したモジュールとして検査する場合は、対象ごとに実行する。

- `terraform fmt -recursive` は `envs/` 以下を対象とする。リポジトリの別ディレクトリに `modules/` などがある場合は、それらに対しても別途フォーマット検査する。

## 7. テスト

ルートモジュール直下の `envs/tests/` にある `.tftest.hcl` を実行する。

```bash
terraform test
```

個別のテストファイルを実行する場合：

```bash
terraform test -filter=tests/.tftest.hcl
```

> [!IMPORTANT]
> 本プロジェクトでは `mock_provider` を利用した、実インフラを作成しないテストを想定する。ただし、**全テストがmock providerのみを使用していることを事前に確認すること**。実providerを用いるテストが混在すればOCIへの接続・リソース操作が発生し得る。

## 8. 事前確認（plan）

```bash
terraform plan -out=tfplan
terraform show tfplan
```

> [!IMPORTANT]
> `plan` の結果を確認し、意図しない作成・変更・削除・再作成がないことを確認してから `apply` する。保存した `tfplan` には機密情報が含まれる可能性があるため、Git管理対象から除外し、アクセスを制限する。

## 9. デプロイ（apply）

保存したplanを適用する。

```bash
terraform apply tfplan
```

対象環境・認証プロファイル・Stateの保存先・適用するplanが一致していることを確認する。適用後、リソースの作成状況と想定どおりの設定になっていることを確認する。

## 10. Bastion経由での接続

Bastionセッション（SSHポートフォワーディング）はTerraformで作成する。接続コマンドは出力値で確認する。

```bash
terraform output bastion_session_commands
```

出力されたコマンドの `<privateKey>` を **Bastion用の秘密鍵** `.key/bastion_rsa`、`<localPort>` を任意のローカルポートに置き換え、別ターミナルで実行したままにする。

### 10.1 Oracle Linux（TCP/22）

トンネル経由のログインには **インスタンス用の秘密鍵** `.key/instance_ed25519` を使用する。

```bash
# 例：ローカルの 10022 番をフォワードした場合
ssh -i .key/instance_ed25519 -p 10022 opc@localhost
```

> [!NOTE]
> Oracle Linuxは初回起動時にuser_data（`envs/userdata/oraclelinux_init.yaml`）でタイムゾーン・日本語ロケールの設定とSELinuxの無効化を行い、cloud-init完了後に1回再起動する。`cloud-init status --long` が `done` になってから確認する。仕組みと注意点は [Oracle Linuxのuser_dataによる初期化](./linux-userdata.md) を参照する。

### 10.2 Windows Server（TCP/3389）

初期ユーザー名・パスワードを確認し、RDPクライアントで `localhost:<localPort>`（例：`localhost:13389`）へ接続する。初回ログイン時にパスワードの変更を求められる。

> [!IMPORTANT]
> Windows Serverは初回起動時にuser_data（`envs/userdata/windows_init.ps1`）で日本語の言語パックをインストールし、表示言語・ロケール・キーボード・タイムゾーンを設定してから再起動する。**再起動が完了するまで初回ログインしないこと。** 先にログインすると `opc` のユーザー・プロファイルが英語設定のまま作られ、日本語の設定が反映されない。実行ログは `C:\Windows\Temp\userdata_windows_init.log` で確認できる。仕組みと注意点は [Windows Serverのuser_dataによる日本語化](./windows-userdata.md) を参照する。

```bash
terraform output -json windows_initial_credentials
```

> [!WARNING]
> 初期パスワードはStateにも保存される。出力結果を共有・保存しないこと。

### 10.3 セッションの期限切れ

セッションは `bastion_session_ttl_in_seconds`（既定3時間）を過ぎるとOCI側で削除され、次回の `plan` で再作成の差分が出る。接続し直す場合は対象セッションだけを作り直す。

```bash
terraform apply -replace='oci_bastion_session.this["linux"]'
terraform apply -replace='oci_bastion_session.this["windows"]'
```

## 11. Terraformで管理しないもの

本プロジェクト固有の管理対象外リソースは以下のとおり。

| 対象            | 理由・扱い                                                                                          |
| --------------- | --------------------------------------------------------------------------------------------------- |
| State用バケット | 自身のStateを保持するバケットの削除をTerraformから実行できないよう、初期準備としてOCI CLIで作成する |

> [!NOTE]
> 既定リソースの扱いは、使用するOCI Providerのリソース仕様と現在のStateを必ず確認すること。既定リソースを管理するかどうかは構成・運用要件に依存する。

## 12. 環境削除・障害対応

- 環境の削除：[環境削除手順](./cleanup.md)
- コンパートメントにリソースが残るなどの調査：[トラブルシューティング](./troubleshooting.md)

## 参考資料

- [OCI CLIセッション認証](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/session/authenticate.html)
- [Terraform OCI Backend](https://developer.hashicorp.com/terraform/language/backend/oci)
- [Terraform test: Provider Mocking](https://developer.hashicorp.com/terraform/language/tests/mocking)
- [TFLint: Working Directory](https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/working-directory.md)
