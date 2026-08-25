# Codex BLE Remote PoC

iPhoneをBLE Peripheral、MacをBLE Centralとして、ローカルのCodex app-serverを操作するPoCです。LANやインターネット上の端末間通信は使いません（Codex自身のモデル通信は別です）。

## 構成

```text
iPhone SwiftUI/CoreBluetooth Peripheral
  command characteristic: Notify (iPhone -> Mac)
  status characteristic:  Write  (Mac -> iPhone)
        |
       BLE
        |
Mac CodexBridge/CoreBluetooth Central
        |
  JSON-RPC over loopback WebSocket (Mac内だけ)
        |
Codex app-server <- codex --remote ws://127.0.0.1:4500
```

Codex Desktopを操作する実験構成では、DesktopとBridgeが同じUnix-domain app-serverを共有します。Mac内にもTCP listenerを作りません。

```text
iPhone -- BLE --> CodexBridge -- WebSocket/Unix socket --> shared app-server <-- Codex Desktop
```

BLE UUIDと1-byte commandはiOS/Macで共通です。状態packetは `[status, reasoning, model, executionMode]` の4 byteです。

iPhoneアプリの画面外周はCodexの状態に連動します。処理中および通常のユーザー入力待ちは青、承認待ちは黄、ターン完了後は緑です。

| Command | Byte | app-server操作 |
|---|---:|---|
| Fast On | `0x01` | `thread/settings/update` の `serviceTier = "priority"` |
| Deep On | `0x03` | `effort = "high"` |
| Fast Off | `0x04` | `serviceTier = null` |
| Deep Off | `0x05` | `effort = "medium"` |
| Sol | `0x20` | `model = "gpt-5.6-sol"` |
| Terra | `0x21` | `model = "gpt-5.6-terra"` |
| Luna | `0x22` | `model = "gpt-5.6-luna"` |

## 実行

1. Xcodeで `CodexController.xcodeproj` を実機iPhoneへ実行し、Bluetoothを許可します。
2. Macブリッジを起動します。

   ```sh
   cd mac/CodexBridge
   swift run CodexBridge
   ```

3. 別ターミナルで、同じローカルdaemonにつながるCodex CLIを起動します。

   ```sh
   codex --remote ws://127.0.0.1:4500
   ```

4. CLIでタスクを開いた状態でiPhoneのFast/Deepまたはモデルボタンを押します。ブリッジは現在ロード済みのthreadを選び、次のturn以降へ設定を反映します。

複数threadを同時にロードしている場合は、誤操作を避けるため対象を固定できます。

```sh
CODEX_BRIDGE_THREAD_ID=019... swift run CodexBridge
```

Finderやlaunchdから起動する場合、`CODEX_BIN=/opt/homebrew/bin/codex` でCLIパスを明示できます。初回はmacOSのBluetooth権限を許可してください。

`127.0.0.1` はMac内部のloopbackだけを使い、LANへbindしません。iPhoneとMacの間はBLEだけです。既に別のapp-serverを起動している場合は `CODEX_APP_SERVER_URL` で接続先を指定できます。

## Codex Desktop共有モード（実験機能）

Codex Desktopを `CODEX_APP_SERVER_USE_LOCAL_DAEMON=1` 付きで起動すると、BridgeとDesktopが `~/.codex/app-server-control/app-server-control.sock` を共有できます。これは現行Desktopに存在する非公開の接続経路で、公開APIではありません。

先にBridgeを共有モードで起動します。

```sh
./mac/run-codex-bridge-shared.command
```

BridgeはsocketがなければDesktop同梱のCodexで共有app-serverを起動します。その後、Codex Desktopを完全に終了し、環境変数付きで起動します。

```sh
CODEX_APP_SERVER_USE_LOCAL_DAEMON=1 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
```

Desktopを通常起動へ戻す場合は、DesktopとBridgeを終了してからFinder/DockでDesktopを起動し直します。共有モードではDesktopとBridgeの起動順が重要で、Bridge（共有app-server）を先に起動します。

Desktopの再起動だけを行う補助スクリプトもあります（共有app-serverとBridgeが起動済みであることが前提です）。

```sh
./mac/relaunch-codex-desktop-shared.command
```

このスクリプトはTerminalから直接1回だけ実行してください。`launchctl submit` へ登録してはいけません。macOSが短時間で終了するsubmitted jobを再実行し続け、Desktopの再起動ループになるためです。スクリプト自体もその起動方法を検出して拒否します。
引数を省略した場合は8秒待ってから、Desktopを1回だけ再起動します。

共有モードを解除して通常起動へ戻す場合は、次をTerminalから実行します。

```sh
./mac/restore-codex-desktop.command
```

## PoCの境界

- `thread/settings/update` とapp-server transportは現行CLIではexperimentalです。CLI更新時は `codex app-server generate-json-schema --experimental` で再確認してください。
- Codex Desktop appが独自にspawnしたapp-server processのthreadへ、別processから接続する公開手段は確認できません。Desktop共有モードはアプリ内部の非公開フラグを利用するため、Desktop更新で動かなくなる可能性があります。
- Fastはモデルcatalogが公開するtier IDを使います。現在の `gpt-5.6-sol` では `priority` がFastです。契約・容量によってバックエンドがstandardへフォールバックする可能性があります。
- iOSアプリがバックグラウンドでもPeripheralとして動き続ける対応は次段階です。その場合はBackground Modesの `bluetooth-peripheral`、再広告、state restorationを追加します。
