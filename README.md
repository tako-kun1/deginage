# Deginage

Windows / Linux 向けのデジタルサイネージソフトウェアです。  
UI に **Flutter**、設定管理・スケジューラ・地震速報（Wolfx Open API）連携などのバックエンド処理に **Rust** を使用しています。

## 主な機能

- **コンテンツ設定・データセット管理**
  - 動画（MP4 / WebM / MKV / MOV 等）および画像（PNG / JPG / WebP / GIF 等）をファイル選択で追加・並べ替え
  - 画像の表示秒数、動画の「最後まで再生」／秒数指定、音量・ミュート、画面フィット方法（全体表示・埋める・引き伸ばし）を設定
  - コンテンツの塊を「データセット」として複数保存・複製・削除
- **トランジション設定**
  - コンテンツ間ごとにトランジションの種類（なし・クロスフェード・黒フェード・スライド上下左右・ズームイン/アウト・ワイプ）と時間を個別設定
  - データセット内すべてのコンテンツへ一括適用
- **スケジュール切り替え**
  - 曜日・時間帯（日またぎ対応）・有効期間・優先度に応じたデータセットの自動切り替え
  - どのルールにも該当しない場合のデフォルトデータセット設定
- **表示モニター・音声出力先の選択**
  - 接続中のモニターからサイネージ表示先を選択してフルスクリーン表示
  - 動画再生時の音声出力デバイスを選択（`media_kit` / libmpv）
- **緊急地震速報（Wolfx Open API）連携**
  - `wss://ws-api.wolfx.jp/jma_eew` へ常時接続（自動再接続対応）
  - 設定した所在地（都道府県・緯度経度・対象地域キーワード）と予測震度しきい値に基づき影響判定
  - 影響する場合はサイネージ画面を地震警告画面（主要動到達カウントダウン・日英避難案内・震源/震度情報）へ自動切り替え、裏の動画再生は一時停止
  - 取消報の受信または一定時間経過で通常表示へ復帰

## 動作要件

- **Windows**: Windows 10 以降の 64bit OS（Windows 10 / 11）
- **Linux**: GUI 環境（X11 / Wayland）を備えた 64bit Linux

## ビルド方法

### 共通の前提ツール

- Flutter SDK（3.50.1 以降推奨）
- Rust ツールチェイン（`rustc`, `cargo`）
- `flutter_rust_bridge_codegen`（Rust 側 API を変更した場合のみ）

### Windows

Visual Studio（C++ によるデスクトップ開発ワークロード）をインストールした状態で以下を実行します。  
※ Flutter の Windows リリースビルドツールの仕様上、プロジェクトの配置パスに日本語などの非 ASCII 文字が含まれるとビルドに失敗するため、半角英数字のみのパスに配置してビルドしてください。

```powershell
flutter pub get
flutter build windows --release
```

生成物: `build/windows/x64/runner/Release/deginage.exe`

### Linux

事前に必要なシステムパッケージ（GTK / libmpv 等）をインストールしてください（Ubuntu / Debian 系の例）。

```bash
sudo apt-get update
sudo apt-get install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev \
  libmpv-dev mpv
```

その後、ビルドを実行します。

```bash
flutter pub get
flutter build linux --release
```

生成物: `build/linux/x64/release/bundle/deginage`

## 使い方

1. 通常起動すると **設定画面** が開きます。
   - **コンテンツ**: データセットの作成、動画・画像の追加、表示時間・トランジションの設定
   - **スケジュール**: 曜日・時間帯・期間ごとのデータセット切り替えルール設定
   - **表示・音声**: 表示モニターと音声出力デバイス、背景色の選択
   - **地震速報**: 所在地としきい値の設定、プレビュー／テスト表示
2. 設定画面右上の **「サイネージ開始」** ボタンで、指定モニターにフルスクリーンでサイネージを起動します。
3. サイネージ画面を終了するには `Ctrl + Q` を押すか、設定画面の **「サイネージ停止」** ボタンを押します。
4. PC 起動時に直接サイネージを表示したい場合は、`--signage` 引数を付けて起動してください。
   - Windows: `deginage.exe --signage`
   - Linux: `./deginage --signage`

## テスト

```bash
# Rust コアの単体テスト
cd rust && cargo test

# Flutter の静的解析・ウィジェットテスト
flutter analyze
flutter test
```

## 注意事項

- 緊急地震速報機能は非公式の [Wolfx Open API](https://wolfx.jp/docs/open-api) を利用した参考情報です。公式の緊急地震速報や防災情報を代替するものではありません。
