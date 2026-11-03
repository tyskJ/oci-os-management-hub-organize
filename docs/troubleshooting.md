# トラブルシューティング

本書は、OCI環境の構築・削除で発生する事象の調査手順を記録する。

- [READMEへ戻る](../README.md)
- [Terraform実行手順](./deployment.md)
- [環境削除手順](./cleanup.md)

## 1. コンパートメントの削除に失敗する場合

### 想定原因

削除対象のコンパートメント内に、OCIリソースが残っている可能性がある。認証局の削除待ち、Terraform管理対象外のリソース、サービス固有の管理リソースなども確認する。

### 1.1 対象コンパートメントのOCIDを取得

以下は名前が `test` のコンパートメントを検索する例。

```bash
COMPARTMENT_NAME="test"
COMPARTMENT_ID=$(oci iam compartment list \
  --lifecycle-state ACTIVE \
  --profile ADMIN \
  --auth security_token \
  --query "data[?name=='${COMPARTMENT_NAME}'].id | [0]" \
  --raw-output)

printf '%s\n' "$COMPARTMENT_ID"
```

> [!NOTE]
> この取得方法は検索範囲・階層によって対象が見つからない場合がある。複数階層のコンパートメントを扱う場合は、親コンパートメントや検索条件を指定し直す。値が空の場合は次のコマンドを実行しない。

### 1.2 残存リソースを検索

```bash
oci search resource structured-search \
  --query-text "query all resources where compartmentId = '${COMPARTMENT_ID}'" \
  --profile ADMIN \
  --auth security_token \
  --query 'data.items[].{identifier:identifier, resource_type:\"resource-type\"}'
```

### 1.3 確認・対応

1. 検索結果のリソース種別・IDを確認する。
2. Terraform State内の管理対象かどうかを確認する。
3. OCIサービス側の削除制約・待機期間・依存関係を確認する。
4. リソースの利用者や削除承認を確認したうえで、必要な削除操作を実施する。
5. 再度検索し、コンパートメント削除を試みる。

> [!WARNING]
> OCI Searchの結果はリソース種別や索引更新タイミングによって網羅的・即時とは限らない。検索結果が空でも完全にリソースが存在しないと断定せず、OCIコンソールやサービス別の一覧APIでも確認する。

## 2. State用バケットが削除できない場合

バージョニング有効時は過去のオブジェクトバージョンが残っている可能性がある。**バケット削除や旧版削除を再実行する前に、Stateのバックアップと他の環境からの参照がないことを確認する。**

```bash
oci os object list-object-versions \
  --bucket-name terraform-working \
  --all \
  --profile ADMIN \
  --auth security_token
```

削除対象の最終確認方法は [環境削除手順](./cleanup.md#7-state用バケットの削除最終工程) を参照する。

## 3. TerraformやOCI CLIの認証に失敗する場合

- OCI CLIの `ADMIN` プロファイルが存在し、正しいテナンシ・リージョンであることを確認する。
- SecurityTokenの有効期限を確認し、必要に応じて再認証する。
- TerraformのOCI ProviderとOCI Backendの双方が、想定した認証方式・プロファイルを使用しているか確認する。
- `terraform init` で読み込む `.tfbackend` の保存先が正しいことを確認する。

## 参考資料

- [OCI CLIコマンドリファレンス](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/)
- [Terraform OCI Backend](https://developer.hashicorp.com/terraform/language/backend/oci)
