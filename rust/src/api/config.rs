//! 設定ファイルの読み書きと変更監視。

use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use anyhow::Context;
use flutter_rust_bridge::frb;

use super::models::AppConfig;
use crate::frb_generated::StreamSink;

/// 設定ディレクトリ（なければ作成）
fn config_dir() -> PathBuf {
    let base = dirs::config_dir().unwrap_or_else(std::env::temp_dir);
    let dir = base.join("deginage");
    let _ = std::fs::create_dir_all(&dir);
    dir
}

fn config_file() -> PathBuf {
    config_dir().join("config.json")
}

fn eew_test_file() -> PathBuf {
    config_dir().join("eew_test.flag")
}

fn signage_pid_file() -> PathBuf {
    config_dir().join("signage.pid")
}

/// 設定ディレクトリのパス
#[frb(sync)]
pub fn config_directory() -> String {
    config_dir().to_string_lossy().into_owned()
}

/// 新しい一意な ID を生成する
#[frb(sync)]
pub fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

/// 既定の設定を生成する
#[frb(sync)]
pub fn default_config() -> AppConfig {
    AppConfig::default()
}

/// 設定を読み込み、整合性を補正して返す。ファイルがなければ既定値を保存して返す。
#[frb(sync)]
pub fn load_config() -> AppConfig {
    let path = config_file();
    match std::fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str::<AppConfig>(&s).ok())
    {
        Some(cfg) => normalize(cfg),
        None => {
            let cfg = AppConfig::default();
            let _ = write_config(&cfg);
            cfg
        }
    }
}

/// 設定を保存する
#[frb(sync)]
pub fn save_config(config: AppConfig) -> anyhow::Result<()> {
    write_config(&normalize(config))
}

fn write_config(cfg: &AppConfig) -> anyhow::Result<()> {
    let path = config_file();
    let tmp = path.with_extension("json.tmp");
    let json = serde_json::to_string_pretty(cfg)?;
    std::fs::write(&tmp, json).context("設定ファイルの書き込みに失敗しました")?;
    std::fs::rename(&tmp, &path).context("設定ファイルの置き換えに失敗しました")?;
    Ok(())
}

/// 設定の整合性を補正する（ID の欠落、存在しないデフォルトデータセットなど）
pub(crate) fn normalize(mut cfg: AppConfig) -> AppConfig {
    if cfg.datasets.is_empty() {
        cfg.datasets = AppConfig::default().datasets;
    }
    for ds in cfg.datasets.iter_mut() {
        if ds.id.is_empty() {
            ds.id = new_id();
        }
        for item in ds.items.iter_mut() {
            if item.id.is_empty() {
                item.id = new_id();
            }
            if item.duration_sec <= 0.0 {
                item.duration_sec = 1.0;
            }
        }
    }
    for rule in cfg.rules.iter_mut() {
        if rule.id.is_empty() {
            rule.id = new_id();
        }
    }
    if !cfg.datasets.iter().any(|d| d.id == cfg.default_dataset_id) {
        cfg.default_dataset_id = cfg.datasets[0].id.clone();
    }
    cfg
}

fn modified(path: &PathBuf) -> Option<SystemTime> {
    std::fs::metadata(path).and_then(|m| m.modified()).ok()
}

/// 設定ファイルの変更を監視し、変更があれば新しい設定を通知する
pub fn watch_config(sink: StreamSink<AppConfig>) {
    std::thread::spawn(move || {
        let path = config_file();
        let mut last = modified(&path);
        loop {
            std::thread::sleep(Duration::from_millis(800));
            let now = modified(&path);
            if now != last {
                last = now;
                if sink.add(load_config()).is_err() {
                    break;
                }
            }
        }
    });
}

/// サイネージ側に地震速報のテスト表示を要求する
#[frb(sync)]
pub fn request_eew_test() -> anyhow::Result<()> {
    let ms = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)?
        .as_millis();
    std::fs::write(eew_test_file(), ms.to_string())?;
    Ok(())
}

/// テスト表示要求を監視する（サイネージ側で使用）
pub fn watch_eew_test(sink: StreamSink<bool>) {
    std::thread::spawn(move || {
        let path = eew_test_file();
        let mut last = modified(&path);
        loop {
            std::thread::sleep(Duration::from_millis(500));
            let now = modified(&path);
            if now != last {
                last = now;
                if sink.add(true).is_err() {
                    break;
                }
            }
        }
    });
}

/// サイネージプロセスの PID を記録する
#[frb(sync)]
pub fn write_signage_pid(pid: i32) {
    let _ = std::fs::write(signage_pid_file(), pid.to_string());
}

/// 記録されたサイネージプロセスの PID
#[frb(sync)]
pub fn read_signage_pid() -> Option<i32> {
    std::fs::read_to_string(signage_pid_file())
        .ok()
        .and_then(|s| s.trim().parse().ok())
}

/// サイネージプロセスの PID 記録を削除する
#[frb(sync)]
pub fn clear_signage_pid() {
    let _ = std::fs::remove_file(signage_pid_file());
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::models::*;

    #[test]
    fn normalize_fixes_missing_ids_and_default() {
        let cfg = AppConfig {
            datasets: vec![Dataset {
                id: String::new(),
                name: "a".into(),
                items: vec![ContentItem::default()],
            }],
            default_dataset_id: "missing".into(),
            ..AppConfig::default()
        };
        let n = normalize(cfg);
        assert!(!n.datasets[0].id.is_empty());
        assert!(!n.datasets[0].items[0].id.is_empty());
        assert_eq!(n.default_dataset_id, n.datasets[0].id);
    }

    #[test]
    fn config_roundtrip_json() {
        let cfg = AppConfig::default();
        let json = serde_json::to_string(&cfg).unwrap();
        let back: AppConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(cfg, back);
        // 欠けたフィールドは既定値で補完される
        let partial: AppConfig = serde_json::from_str(r#"{"version":1}"#).unwrap();
        assert_eq!(partial.eew.intensity_threshold, "4");
    }
}
