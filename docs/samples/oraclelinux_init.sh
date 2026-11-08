#!/bin/bash

# ============================================================
# 参考用サンプル（Terraformからは参照しない）
# ============================================================
# Oracle Linuxの初期化処理をシェルスクリプト形式で書いた例。
# 実際にuser_dataとして使っているのは envs/userdata/oraclelinux_init.yaml（cloud-config形式）で、
# 再起動を cloud-init の power_state で行うためにYAMLへ書き換えた。
# 本スクリプトとYAMLの処理内容は同じ（タイムゾーン、日本語ロケール、SELinux無効化、再起動）。

# Shell Options
# e : エラーがあったら直ちにシェルを終了
# u : 未定義変数を使用したときにエラーとする
# o : シェルオプションを有効にする
# pipefail : パイプラインの返り値を最後のエラー終了値にする (エラー終了値がない場合は0を返す)
set -euo pipefail

# Timezone
timedatectl set-timezone Asia/Tokyo
# rsyslogが動いている場合のみ再起動し、ログのタイムスタンプに新しいタイムゾーンを反映する
systemctl try-restart rsyslog

# Locale
# 初回起動時はOS Management Hub Agentの登録と並行して動くため、リポジトリ切り替えのタイミングで
# dnfが失敗する可能性がある。失敗してもスクリプト全体は止めず、警告を出してロケール設定だけ省略する
if dnf install -y glibc-langpack-ja; then
  localectl set-locale LANG=ja_JP.utf8
else
  echo "WARN: glibc-langpack-ja のインストールに失敗したため、ロケール設定を省略しました" >&2
fi

# SELinux disable（検証用途。本番環境では無効化しない）
# Oracle Linux 9以降は /etc/selinux/config の SELINUX=disabled では完全に無効化されないため、
# カーネル引数 selinux=0 で無効化する。反映には再起動が必要
grubby --update-kernel ALL --args selinux=0
# 再起動までの間はpermissiveにしておく（既にdisabledの場合はエラーになるため無視する）
setenforce 0 || true

# firewalldは変更しない（通信制御はNSG・セキュリティ・リストで行う前提だが、OS既定の設定のまま確認する）

# Reboot
# shutdown -r now だとcloud-initの最終段階やOS Management Hub Agentの初期登録が途中で切れるため、
# 1分後に予約してcloud-initを完了させてから再起動する
shutdown -r +1
