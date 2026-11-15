#ps1_sysnative

# ============================================================
# Windows Server 初期化（cloudbase-init が専用のローカル管理者ユーザー cloudbase-init で初回起動時に実行する）
# ============================================================
# ロケール・キーボード・タイムゾーンを日本向けに設定する（表示言語の日本語化は言語パックのインストールに時間がかかるため無効化中）。
# パスワードはセキュリティ上の理由で変更しない（詳細は compute.tf）。
#
# 注意：
# - Windows PowerShell 5.1 はBOMなしUTF-8を正しく読めない場合があるため、
#   日本語はコメントのみに使い、出力する文字列は英語にする
# - 地域・書式・キーボード・表示言語はユーザーごとの設定のため、実行ユーザー（cloudbase-init）上で設定した後、
#   Copy-UserInternationalSettingsToSystem でようこそ画面と新規ユーザー（初回ログイン前のopc）の既定値にコピーする

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\userdata_windows_init.log" -Append

try {
  # Language Pack（無効化中）
  # 日本語の言語パック（表示言語）をWindows Update経由でインストールする。NAT Gateway経由で取得する。
  # インストールに数十分以上かかり、OS Management Hub AgentのWindows Updateの処理とも重なるため、コメントアウトしている。
  # 表示言語を日本語にする場合は、以下の3行（Write-Output・Install-Language・Set-SystemPreferredUILanguage）と Set-WinUILanguageOverride のコメントを外す
  # （Set-SystemPreferredUILanguage・Set-WinUILanguageOverride は言語パックがないと使えないため、あわせて無効化する）
  # Write-Output "Installing ja-JP language pack"
  # Install-Language -Language ja-JP
  # システム全体の既定の表示言語を日本語にする
  # Set-SystemPreferredUILanguage -Language ja-JP

  # Timezone（システム全体）
  Write-Output "Setting timezone"
  Set-TimeZone -Id "Tokyo Standard Time"

  # System Locale（非Unicodeプログラムの言語。システム全体、再起動後に有効）
  Write-Output "Setting system locale"
  Set-WinSystemLocale -SystemLocale ja-JP

  # 以下はユーザーごとの設定。実行ユーザー（cloudbase-init）上で設定し、最後に既定値へコピーする
  # 表示言語（言語パックが必要なため無効化中。Language Pack の項を参照）
  # Set-WinUILanguageOverride -Language ja-JP
  # 地域・書式（日付・数値の形式）
  Set-Culture -CultureInfo ja-JP
  # 場所（122 = 日本）
  Set-WinHomeLocation -GeoId 122
  # 言語一覧とキーボード（0411:00000411 = 日本語キーボード）
  $languageList = New-WinUserLanguageList -Language ja-JP
  $languageList[0].InputMethodTips.Clear()
  $languageList[0].InputMethodTips.Add("0411:00000411")
  Set-WinUserLanguageList -LanguageList $languageList -Force

  # ようこそ画面と新規ユーザーの既定値にコピーする
  Write-Output "Copying international settings to welcome screen and new users"
  Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

  Write-Output "Completed. Rebooting to apply settings"
}
finally {
  Stop-Transcript
}

# Reboot
# Restart-Computer を使うと次回起動時にuser_dataが再実行される可能性があるため、
# cloudbase-initの終了コード 1001（再起動し、次回起動時は本スクリプトを再実行しない）で再起動を要求する
exit 1001
