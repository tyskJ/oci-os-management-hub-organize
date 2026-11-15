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
- コンパートメント、Stateバケットなど、即時削除できない／削除を分離すべき対象を把握していること。

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

本プロジェクトでは、**コンパートメント**と**定義済みタグ**について、Terraformでの削除が進行できないケースを想定する。

- 定義済みタグ（タグ・ネームスペース `Common` とタグ・キー `SystemName`・`OSType`）は削除に時間がかかり、`terraform destroy` が長時間待機する場合がある（タグ・キーのTerraform側の削除タイムアウトは最大12時間）。
- リソースが残存するコンパートメントは削除できない。
- コンパートメントをTerraform管理外にする操作は、**OCI上の実リソースの削除とは別作業**である。

### 3.1 管理対象の候補を確認

```bash
terraform state list | grep -E 'oci_identity_compartment'
```

### 3.2 管理対象からの除外（必要な場合のみ）

推奨はTerraformの `removed` ブロック（`lifecycle { destroy = false }`）によって、`plan` で管理対象からの除外を確認する方法。構成内の参照関係も解消してから適用する。

既存の手順で `terraform state rm` を使用する場合は、**事前にアドレスを1件ずつ確認し、実リソースを残す意図が明確な場合に限定する**。

```bash
# 例：対象を確認した上で、実際のリソースアドレスに置き換える
terraform state rm '<コンパートメントの実際のリソースアドレス>'
```

> [!CAUTION]
> `terraform state rm` はStateから追跡情報を外すだけで、実リソースは削除しない。元の `resource` ブロックが構成に残ったままだと、後続の `plan` で再作成が提案され得る。対象のコード・参照・削除順序を必ず整合させること。すべてのコンパートメントを一括で除外しない。

## 4. OS Management Hubの管理対象インスタンスの登録解除

`terraform destroy` の**前に**、OS Management Hubの管理対象インスタンスを登録解除する。

管理対象インスタンスはTerraformで作成したリソースではない（OSMH Agentがインスタンスの起動時に登録する）ため、`terraform destroy` の対象にならない。
コンピュート・インスタンスを削除（terminate）しても自動では削除されず、OS Management Hubが90日間通信のない管理対象インスタンスを自動で削除するまで残り続ける。
検証用コンパートメントと管理対象インスタンス・グループに残ったままだと、次の削除が失敗する可能性があるため、先に登録解除する。

- 管理対象インスタンス・グループ（`oci_os_management_hub_managed_instance_group`）：メンバーのインスタンスが残っている
- 検証用コンパートメント（`oci_identity_compartment`）：コンパートメント内にリソースが残っている

> [!NOTE]
> 管理対象インスタンスのOCIDは、登録元のコンピュート・インスタンスのOCIDと同じ。

検証用コンパートメントの管理対象インスタンスを確認する。

```bash
COMPARTMENT_ID=$(oci iam compartment list \
  --name osmh-organize \
  --query 'data[0].id' \
  --raw-output \
  --profile ADMIN \
  --auth security_token)

oci os-management-hub managed-instance list \
  --compartment-id "${COMPARTMENT_ID}" \
  --all \
  --query 'data.items[].{"display-name":"display-name",status:status,id:id}' \
  --output table \
  --profile ADMIN \
  --auth security_token
```

一覧の `id` が本構成のインスタンスのものであることを確認してから、1件ずつ登録解除する。

```bash
oci os-management-hub managed-instance delete \
  --managed-instance-id <管理対象インスタンスのOCID> \
  --profile ADMIN \
  --auth security_token
```

登録解除中はステータスが Unregistering になる。再度 `managed-instance list` を実行し、一覧から消えたことを確認してから次の手順に進む。

> [!CAUTION]
> 登録解除は元に戻せない。登録解除したインスタンスを再登録するには、インスタンス上での追加作業が必要になる（[トラブルシューティング（OSMH公式）](https://docs.oracle.com/en-us/iaas/osmh/doc/troubleshooting.htm)）。本手順では直後にインスタンスを削除するため問題ないが、対象が本構成のインスタンスであることを必ず確認する。

> [!NOTE]
> 登録解除をせずに `terraform destroy` を実行し、グループやコンパートメントの削除で失敗した場合は、本手順で登録解除してから、再度 [削除計画の確認](#5-削除計画の確認) からやり直す。
> コンピュート・インスタンスの削除後に残った管理対象インスタンスも、同じ手順で登録解除できる。

## 5. 削除計画の確認

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
```

Stateから除外した対象が含まれていないこと、削除対象の一覧に意図しないリソースが存在しないことを確認する。

> [!IMPORTANT]
> `destroy.tfplan` は機密情報を含み得るため、Gitへコミットせず、厳重に保護する。

## 6. 環境の削除

保存した削除計画を適用する。

```bash
terraform apply destroy.tfplan
```

> [!CAUTION]
> 保存したplanの適用は、対象リソースを実際に削除する。Stateと適用するplanの取り違えがないことを最後に確認する。

元の手順の `terraform destroy` を直接使う場合は、新たな削除計画が表示されるため、その内容をすべて確認してから承認する。

## 7. 残存リソースの確認

コンパートメントなど、Terraformの管理外にした対象はOCI上に残る。手動削除の可否・必要な待機期間を確認し、残存しているリソースの担当者と削除予定を記録する。

コンパートメントの削除に失敗する場合は [トラブルシューティング](./troubleshooting.md) を参照する。

## 8. State用バケットの削除（最終工程）

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

## 9. 片付けと記録

- `prevent_destroy` の一時変更を復元する。
- ローカルのplanファイル・機密情報を適切に削除または保護する。
- Terraform管理外となったコンパートメントや、登録解除したOS Management Hubの管理対象インスタンスなどの残存状況を記録する。
- 最終的な削除対象、日時、実施者、承認内容を記録する。

## 参考資料

- [Remove a resource from state](https://developer.hashicorp.com/terraform/language/state/remove)
- [terraform state rm](https://developer.hashicorp.com/terraform/cli/commands/state/rm)
- [OCI CLI: Bucket Delete](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/os/bucket/delete.html)
- [OCI CLI: List Object Versions](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/os/object/list-object-versions.html)
- [OS Management Hub: Overview（データの保持）](https://docs.oracle.com/en-us/iaas/osmh/doc/overview.htm)
- [OS Management Hub: Understanding Instances（ステータス）](https://docs.oracle.com/en-us/iaas/osmh/doc/understand-instances.htm)
