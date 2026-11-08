# Oracle Linuxのuser_dataによる初期化

本書は、Oracle Linuxの初回起動時に **user_data（`envs/userdata/oraclelinux_init.yaml`）でタイムゾーン・日本語ロケールの設定とSELinuxの無効化を行う仕組み** と、その注意点をまとめる。

- [READMEへ戻る](../README.md)
- [Terraform実行手順](./deployment.md)
- [Windows Serverのuser_dataによる日本語化](./windows-userdata.md)

> [!NOTE]
> 本書の内容のうち「未確認」と記した事項は、実機での動作確認が済んでいない。確認後に本書を更新する。

## 1. 実行ユーザー

Oracle Linuxでは、user_dataは **cloud-init** が処理する。「cloud-initユーザー」というアカウントは存在せず、cloud-initはsystemdのサービスとして**rootで実行**される。

| 段階（systemdサービス） | 主な処理                                | 本構成で実行される項目  |
| ----------------------- | --------------------------------------- | ----------------------- |
| `cloud-init-local`      | ネットワーク設定前の初期化              | －                      |
| `cloud-init`            | ネットワーク設定、ユーザー作成（`opc`） | －                      |
| `cloud-config`          | 設定系モジュールの実行                  | `timezone`              |
| `cloud-final`           | ユーザー指定スクリプトの実行、最終処理  | `runcmd`、`power_state` |

`opc` ユーザーも、OCIのOracle Linuxイメージではcloud-initの既定ユーザーとして `cloud-init` の段階で作成される。

## 2. 設定の適用範囲

本構成の設定はいずれも**システム全体**のファイルへ書き込むため、rootで実行しても `opc` を含む全ユーザーに適用される。Windowsのように「実行アカウント自身にだけ設定される」問題は起きにくい。

| 設定         | 実行方法                                      | 書き込み先（システム全体）   |
| ------------ | --------------------------------------------- | ---------------------------- |
| タイムゾーン | `timezone` モジュール                         | `/etc/localtime`             |
| ロケール     | `localectl set-locale LANG=ja_JP.utf8`        | `/etc/locale.conf`           |
| SELinux      | `grubby --update-kernel ALL --args selinux=0` | ブートローダーのカーネル引数 |

ユーザーごとの設定（`~/.bashrc`、`~/.config/` 配下など）を変更する場合は、`runcmd` で `su - opc -c '...'` のように対象ユーザーとして実行する必要がある。

## 3. cloud-configの構成

user_dataはシェルスクリプトではなく **cloud-config（YAML）形式** で記述する。

| 項目          | 内容                                                                 |
| ------------- | -------------------------------------------------------------------- |
| `timezone`    | `Asia/Tokyo` に設定する                                              |
| `runcmd`      | rsyslogの再起動、日本語ロケールの設定、SELinuxの無効化を順に実行する |
| `power_state` | cloud-initの全モジュール完了後に再起動し、SELinuxの無効化を反映する  |

シェルスクリプト形式で記述した同等の処理は、参考として [docs/samples/oraclelinux_init.sh](./samples/oraclelinux_init.sh) に残している（Terraformからは参照しない）。

## 4. 実装上の注意点

### 4.1 再起動は `power_state` で行う

`runcmd` やシェルスクリプト内で `shutdown -r now` を実行すると、cloud-initの最終段階が途中で中断され、完了状態が正しく記録されない。同時に動作しているOracle Cloud AgentやOS Management Hub Agentの初期登録も中断する。

`power_state` はcloud-initの全モジュールの完了を待ってから再起動するため、タイミングを推測する必要がない（`timeout` は完了を待つ最大秒数）。

### 4.2 SELinuxはカーネル引数で無効化する

Oracle Linux 9以降は、`/etc/selinux/config` に `SELINUX=disabled` と記述しても完全には無効化されない。カーネル引数 `selinux=0` を `grubby` で設定し、再起動で反映する。再起動までの間は `setenforce 0` でpermissiveにしておく。

> [!WARNING]
> SELinuxの無効化は検証用途に限る。本番環境では無効化しない。

### 4.3 dnfの失敗に備える

初回起動時は、cloud-initとOS Management Hub Agentの登録が並行して動く。Agentの登録でリポジトリ設定が切り替わるタイミングと重なると、`dnf install` が失敗する可能性がある。

- 日本語ロケールのパッケージ（`glibc-langpack-ja`）のインストールに失敗した場合は、警告を出してロケール設定だけを省略する。
- `runcmd` には `set -e` 相当の動作がないため、1つのコマンドが失敗しても後続のコマンド（SELinuxの無効化など）は実行される。

### 4.4 SSH接続時のロケール

macOSなどのSSHクライアントは、既定で接続元の `LANG`・`LC_*` をサーバーへ送信する（`SendEnv LANG LC_*`）。Oracle Linux側のsshdがこれを受け入れる設定（`AcceptEnv`）の場合、`/etc/locale.conf` を `ja_JP.utf8` にしても、**SSHで入ったシェルでは接続元のロケールで上書きされる**ことがある。

システムの設定と現在のシェルの値を両方確認すると、どちらが効いているかを判別できる。

```bash
localectl status   # システムの設定（/etc/locale.conf）
echo "$LANG"       # 現在のシェルで有効な値
```

## 5. 動作確認

| 確認項目         | 確認方法                                                                |
| ---------------- | ----------------------------------------------------------------------- |
| cloud-initの完了 | `cloud-init status --long` が `done` であること                         |
| 実行ログ         | `/var/log/cloud-init-output.log`、`/var/log/cloud-init.log`             |
| タイムゾーン     | `timedatectl` の Time zone が `Asia/Tokyo` であること                   |
| ロケール         | `localectl status` の System Locale が `LANG=ja_JP.utf8` であること     |
| SELinux          | `getenforce` が `Disabled` であること                                   |
| カーネル引数     | `cat /proc/cmdline` に `selinux=0` が含まれること                       |
| OSMHへの登録     | OS Management Hubのコンソールで管理対象インスタンスとして表示されること |

## 6. 未確認事項

- `glibc-langpack-ja` がOracle Linux 10のリポジトリで提供されていること。
- 初回起動時に、OS Management Hub Agentの登録と `dnf install` が競合するかどうか。
- `power_state` による再起動後、OS Management Hubへの登録が正常に完了していること。
- user_dataの内容を後から変更した場合に、インスタンスが再作成されるかどうか（`terraform plan` で確認する）。

## 参考資料

- [cloud-init: Boot stages](https://cloudinit.readthedocs.io/en/latest/explanation/boot.html)
- [cloud-init: Module reference（timezone / runcmd / power_state）](https://cloudinit.readthedocs.io/en/latest/reference/modules.html)
