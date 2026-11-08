# 環境削除手順

本書は**検証用に構築したOCI環境を削除する場合のみ**参照する。通常の構築・変更は [Terraform実行手順](./deployment.md) に従う。

- [READMEへ戻る](../README.md)
- [Terraform実行手順](./deployment.md)
- [トラブルシューティング](./troubleshooting.md)

> [!CAUTION]
> **本番環境では実行しないこと。** 以下にはリソースの完全削除、Terraform管理対象からの除外、およびState保存先の削除が含まれる。対象のテナンシ、リージョン、コンパートメント、Terraform Workspace、Backend、Stateの保存先を事前に確認する。

> [!NOTE]
> 本プロジェクトのTerraformルートモジュールは **`envs/`**。リポジトリ直下から `cd envs` で移動したうえで、以下のTerraformコマンドを実行する。`envs/config.oci.tfbackend` を使用した `terraform init -backend-config=./config.oci.tfbackend` が済んでいることを確認する。
>
> OCI CLIのコマンドはどちらのディレクトリでも実行できるが、コマンド実行場所は `envs/` に統一する。

```bash
# リポジトリ直下から実行（以降はenvs/で作業）
cd envs
```

## 1. 削除前の確認

- 対象環境が検証用であり、削除承認があること。
- Stateのバックアップ・復旧方法が確認できていること。
- OCI CLIの `ADMIN` プロファイルの向き先が正しいこと。
- 認証局、コンパートメント、Stateバケットなど、即時削除できない／削除を分離すべき対象を把握していること。

```bash
terraform workspace show
terraform state list
```

Stateを含むファイルは機密情報として取り扱う。

## 2. `prevent_destroy` の解除

`lifecycle { prevent_destroy = true }` が設定されているリソースは削除が拒否される。本プロジェクトは検証環境のため、現時点で `prevent_destroy` を設定しているリソースはない。今後追加した場合は以下に従う。

対象が本当に削除可能であることを確認した後、**対象リソースに限って** `prevent_destroy = false` への変更、または当該設定の削除を行う。作業後は元の保護設定を復元し、検証目的の解除をコミットしない。

> [!WARNING]
> `prevent_destroy` はTerraform構成中に当該resourceが存在することを前提とする。保護を外すこと自体が破壊的変更の承認を意味するわけではない。

## 3. 即時削除できないリソースの取り扱い

本プロジェクトでは、**認証局（Certificate Authority）** とその配置先**コンパートメント**について、Terraformでの削除が進行できないケースを想定する。

- 認証局は削除に制約・待機期間があり、すぐに削除できない場合がある。
- 定義済みタグ（タグ・ネームスペース `Common` とタグ・キー `SystemName`）は削除に時間がかかり、`terraform destroy` が長時間待機する場合がある（タグ・キーのTerraform側の削除タイムアウトは最大12時間）。
- リソースが残存するコンパートメントは削除できない。
- 認証局・コンパートメントをTerraform管理外にする操作は、**OCI上の実リソースの削除とは別作業**である。

### 3.1 管理対象の候補を確認

```bash
terraform state list | grep -E 'oci_certificates_management_certificate_authority|oci_identity_compartment'
```

### 3.2 管理対象からの除外（必要な場合のみ）

推奨はTerraformの `removed` ブロック（`lifecycle { destroy = false }`）によって、`plan` で管理対象からの除外を確認する方法。構成内の参照関係も解消してから適用する。

既存の手順で `terraform state rm` を使用する場合は、**事前にアドレスを1件ずつ確認し、実リソースを残す意図が明確な場合に限定する**。

```bash
# 例：対象を確認した上で、実際のリソースアドレスに置き換える
terraform state rm '<認証局の実際のリソースアドレス>'
terraform state rm '<コンパートメントの実際のリソースアドレス>'
```

> [!CAUTION]
> `terraform state rm` はStateから追跡情報を外すだけで、実リソースは削除しない。元の `resource` ブロックが構成に残ったままだと、後続の `plan` で再作成が提案され得る。対象のコード・参照・削除順序を必ず整合させること。すべてのコンパートメントを一括で除外しない。

## 4. 削除計画の確認

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
```

Stateから除外した対象が含まれていないこと、削除対象の一覧に意図しないリソースが存在しないことを確認する。

> [!IMPORTANT]
> `destroy.tfplan` は機密情報を含み得るため、Gitへコミットせず、厳重に保護する。

## 5. 環境の削除

保存した削除計画を適用する。

```bash
terraform apply destroy.tfplan
```

> [!CAUTION]
> 保存したplanの適用は、対象リソースを実際に削除する。Stateと適用するplanの取り違えがないことを最後に確認する。

元の手順の `terraform destroy` を直接使う場合は、新たな削除計画が表示されるため、その内容をすべて確認してから承認する。

## 6. 残存リソースの確認

認証局やコンパートメントなど、Terraformの管理外にした対象はOCI上に残る。手動削除の可否・必要な待機期間を確認し、残存しているリソースの担当者と削除予定を記録する。

コンパートメントの削除に失敗する場合は [トラブルシューティング](./troubleshooting.md) を参照する。

## 7. State用バケットの削除（最終工程）

> [!CAUTION]
> State用バケットの削除は**Terraform Stateと過去のバージョンを失う可能性がある操作**であり、原則として最後に実行する。複数の環境・利用者・Stateが同じバケットを使用していないこと、バックアップがあることを確認する。

削除内容を事前確認する。

```bash
oci os bucket delete \
  --bucket-name terraform-working \
  --empty \
  --dry-run \
  --profile ADMIN \
  --auth security_token
```

対象に問題がないと確認した場合にのみ、削除を実行する。

```bash
oci os bucket delete \
  --bucket-name terraform-working \
  --empty \
  --profile ADMIN \
  --auth security_token
```

> [!NOTE]
> 元の手順には `--force` が含まれていたが、確認プロンプトを省略するため、ここでは付与していない。
>
> バージョニングを有効にしたバケットでは、旧版オブジェクトが残る場合がある。削除に失敗した場合は以下で状態を確認し、対象と復旧要否を確認してから旧版の削除方法を検討する。

```bash
oci os object list-object-versions \
  --bucket-name terraform-working \
  --all \
  --profile ADMIN \
  --auth security_token
```

旧版の一括削除には `oci os object bulk-delete-versions` が利用できるが、復旧手段を失う可能性があるため、事前に `--dry-run` で対象を確認する。削除対象が確定するまでは実行しない。

## 8. 片付けと記録

- `prevent_destroy` の一時変更を復元する。
- ローカルのplanファイル・機密情報を適切に削除または保護する。
- Terraform管理外となった認証局・コンパートメントなどの残存状況を記録する。
- 最終的な削除対象、日時、実施者、承認内容を記録する。

## 参考資料

- [Remove a resource from state](https://developer.hashicorp.com/terraform/language/state/remove)
- [terraform state rm](https://developer.hashicorp.com/terraform/cli/commands/state/rm)
- [OCI CLI: Bucket Delete](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/os/bucket/delete.html)
- [OCI CLI: List Object Versions](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/os/object/list-object-versions.html)
