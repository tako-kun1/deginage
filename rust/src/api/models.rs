//! Deginage の設定データモデル。
//!
//! Dart 側から直接編集できるよう、各フィールドに `#[frb(non_final)]` を付与している。

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

/// コンテンツの種類
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum MediaKind {
    #[default]
    Image,
    Video,
}

/// コンテンツの表示方法（画面へのフィット方法）
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum FitMode {
    /// アスペクト比を保って全体を表示（余白あり）
    #[default]
    Contain,
    /// アスペクト比を保って画面を埋める（はみ出しは切り取り）
    Cover,
    /// 画面サイズに引き伸ばす
    Fill,
}

/// トランジションの種類
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum TransitionKind {
    /// 切り替え効果なし
    None,
    /// クロスフェード
    #[default]
    CrossFade,
    /// 黒を経由したフェード
    FadeThroughBlack,
    /// 左へスライド
    SlideLeft,
    /// 右へスライド
    SlideRight,
    /// 上へスライド
    SlideUp,
    /// 下へスライド
    SlideDown,
    /// ズームイン
    ZoomIn,
    /// ズームアウト
    ZoomOut,
    /// 左からワイプ
    Wipe,
}

/// コンテンツ間のトランジション設定
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct TransitionSetting {
    #[frb(non_final)]
    pub kind: TransitionKind,
    /// トランジション時間（ミリ秒）
    #[frb(non_final)]
    pub duration_ms: u32,
}

impl Default for TransitionSetting {
    fn default() -> Self {
        Self {
            kind: TransitionKind::CrossFade,
            duration_ms: 800,
        }
    }
}

/// サイネージに表示する 1 つのコンテンツ
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct ContentItem {
    #[frb(non_final)]
    pub id: String,
    /// ファイルの絶対パス
    #[frb(non_final)]
    pub path: String,
    #[frb(non_final)]
    pub kind: MediaKind,
    /// 表示時間（秒）。動画で `play_full_video` が true の場合は無視される
    #[frb(non_final)]
    pub duration_sec: f64,
    /// 動画を最後まで再生してから次へ進むか
    #[frb(non_final)]
    pub play_full_video: bool,
    /// 音量 (0.0 - 100.0)
    #[frb(non_final)]
    pub volume: f64,
    #[frb(non_final)]
    pub muted: bool,
    #[frb(non_final)]
    pub fit: FitMode,
    /// このコンテンツから「次のコンテンツ」へ切り替わる際のトランジション
    #[frb(non_final)]
    pub transition: TransitionSetting,
}

impl Default for ContentItem {
    fn default() -> Self {
        Self {
            id: String::new(),
            path: String::new(),
            kind: MediaKind::Image,
            duration_sec: 10.0,
            play_full_video: true,
            volume: 100.0,
            muted: false,
            fit: FitMode::Contain,
            transition: TransitionSetting::default(),
        }
    }
}

/// コンテンツの塊（プレイリスト）
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct Dataset {
    #[frb(non_final)]
    pub id: String,
    #[frb(non_final)]
    pub name: String,
    #[frb(non_final)]
    pub items: Vec<ContentItem>,
}

/// 表示データセットを切り替えるスケジュールルール
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct ScheduleRule {
    #[frb(non_final)]
    pub id: String,
    #[frb(non_final)]
    pub name: String,
    #[frb(non_final)]
    pub enabled: bool,
    /// 表示するデータセットの ID
    #[frb(non_final)]
    pub dataset_id: String,
    /// 曜日のビットマスク (bit0 = 月曜 ... bit6 = 日曜)。0 の場合は毎日
    #[frb(non_final)]
    pub weekday_mask: u32,
    /// 開始時刻 "HH:MM"
    #[frb(non_final)]
    pub start_time: String,
    /// 終了時刻 "HH:MM"（開始より前の場合は日をまたぐ）。開始と同じなら終日
    #[frb(non_final)]
    pub end_time: String,
    /// 有効期間の開始日 "YYYY-MM-DD"（任意）
    #[frb(non_final)]
    pub start_date: Option<String>,
    /// 有効期間の終了日 "YYYY-MM-DD"（任意、当日を含む）
    #[frb(non_final)]
    pub end_date: Option<String>,
    /// 優先度（大きいほど優先）
    #[frb(non_final)]
    pub priority: i32,
}

impl Default for ScheduleRule {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: "新しいルール".into(),
            enabled: true,
            dataset_id: String::new(),
            weekday_mask: 0,
            start_time: "09:00".into(),
            end_time: "18:00".into(),
            start_date: None,
            end_date: None,
            priority: 0,
        }
    }
}

/// 表示・音声出力の設定
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct DisplaySettings {
    /// 表示モニターの ID（screen_retriever の Display.id）
    #[frb(non_final)]
    pub monitor_id: String,
    /// 表示モニターの名前（ID が見つからない場合のフォールバック）
    #[frb(non_final)]
    pub monitor_name: String,
    /// 音声出力デバイス名（mpv の audio-device 名）。"auto" で既定デバイス
    #[frb(non_final)]
    pub audio_device: String,
    /// 背景色 (ARGB)
    #[frb(non_final)]
    pub background_color: u32,
}

impl Default for DisplaySettings {
    fn default() -> Self {
        Self {
            monitor_id: String::new(),
            monitor_name: String::new(),
            audio_device: "auto".into(),
            background_color: 0xFF000000,
        }
    }
}

/// 地震速報（緊急地震速報）連携の設定
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct EewSettings {
    #[frb(non_final)]
    pub enabled: bool,
    /// 所在地の都道府県名
    #[frb(non_final)]
    pub prefecture: String,
    /// 所在地の緯度
    #[frb(non_final)]
    pub latitude: f64,
    /// 所在地の経度
    #[frb(non_final)]
    pub longitude: f64,
    /// 警報対象地域と照合するキーワード（カンマ区切り、前方一致）
    #[frb(non_final)]
    pub area_keywords: String,
    /// 警告画面を表示する震度のしきい値 ("1"〜"7", "5-", "5+", "6-", "6+")
    #[frb(non_final)]
    pub intensity_threshold: String,
    /// 緊急地震速報の対象地域 (WarnArea) で判定する
    #[frb(non_final)]
    pub use_warn_area: bool,
    /// 震源・規模から所在地の震度を推定して判定する
    #[frb(non_final)]
    pub use_estimation: bool,
    /// 地盤増幅率（推定震度計算用、標準 1.4）
    #[frb(non_final)]
    pub site_amplification: f64,
    /// 訓練報も表示する
    #[frb(non_final)]
    pub show_training: bool,
    /// 最後の受信から警告画面を表示し続ける秒数
    #[frb(non_final)]
    pub alert_duration_sec: u32,
}

impl Default for EewSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            prefecture: "東京都".into(),
            latitude: 35.690,
            longitude: 139.692,
            area_keywords: "東京".into(),
            intensity_threshold: "4".into(),
            use_warn_area: true,
            use_estimation: true,
            site_amplification: 1.4,
            show_training: false,
            alert_duration_sec: 180,
        }
    }
}

/// アプリ全体の設定
#[frb(non_opaque)]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct AppConfig {
    #[frb(non_final)]
    pub version: u32,
    #[frb(non_final)]
    pub datasets: Vec<Dataset>,
    /// どのルールにも該当しない時に表示するデータセット
    #[frb(non_final)]
    pub default_dataset_id: String,
    #[frb(non_final)]
    pub rules: Vec<ScheduleRule>,
    #[frb(non_final)]
    pub display: DisplaySettings,
    #[frb(non_final)]
    pub eew: EewSettings,
}

impl Default for AppConfig {
    fn default() -> Self {
        let id = uuid::Uuid::new_v4().to_string();
        Self {
            version: 1,
            datasets: vec![Dataset {
                id: id.clone(),
                name: "デフォルト".into(),
                items: vec![],
            }],
            default_dataset_id: id,
            rules: vec![],
            display: DisplaySettings::default(),
            eew: EewSettings::default(),
        }
    }
}
