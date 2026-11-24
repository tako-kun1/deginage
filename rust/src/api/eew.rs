//! Wolfx Open API (JMA 緊急地震速報) の受信と、所在地への影響判定。
//!
//! - WebSocket: `wss://ws-api.wolfx.jp/jma_eew`
//! - ドキュメント: <https://wolfx.jp/docs/open-api>

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use chrono::{FixedOffset, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Utc};
use flutter_rust_bridge::frb;
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio_tungstenite::tungstenite::Message;

use super::intensity::{
    estimate_intensity, haversine_km, intensity_class, intensity_rank, normalize_intensity,
};
use super::models::EewSettings;
use crate::frb_generated::StreamSink;

const WS_URL: &str = "wss://ws-api.wolfx.jp/jma_eew";
/// S 波の平均速度 (km/s)
const S_WAVE_VELOCITY: f64 = 3.5;

/// 予報・警報対象地域
#[derive(Debug, Clone, PartialEq)]
pub struct WarnAreaInfo {
    pub chiiki: String,
    /// 地域の最大予測震度（正規化済み: "5-" など）
    pub shindo1: String,
    /// 地域の最小予測震度（正規化済み）
    pub shindo2: String,
    /// 主要動到達予測時刻 (HHMMSS、不明は空)
    pub time: String,
    /// "予報" / "警報"
    pub kind: String,
    pub arrive: String,
}

/// 受信した緊急地震速報
#[derive(Debug, Clone, PartialEq)]
pub struct EewReport {
    pub title: String,
    pub code_type: String,
    pub event_id: String,
    pub serial: i32,
    pub announced_time: String,
    /// 発表時刻 (UNIX ミリ秒)
    pub announced_epoch_ms: Option<i64>,
    pub origin_time: String,
    /// 発生時刻 (UNIX ミリ秒)
    pub origin_epoch_ms: Option<i64>,
    pub hypocenter: String,
    pub latitude: f64,
    pub longitude: f64,
    pub magnitude: f64,
    pub depth: f64,
    /// 最大予測震度（正規化済み）
    pub max_intensity: String,
    pub is_sea: bool,
    pub is_training: bool,
    pub is_assumption: bool,
    pub is_warn: bool,
    pub is_final: bool,
    pub is_cancel: bool,
    /// アプリ内のテスト表示用データか
    pub is_test: bool,
    pub warn_areas: Vec<WarnAreaInfo>,
}

/// 所在地への影響判定の結果
#[derive(Debug, Clone, PartialEq)]
pub struct EewEvaluation {
    /// 警告画面を表示すべきか
    pub affects: bool,
    /// 判定理由（表示・ログ用）
    pub reason: String,
    /// 所在地の推定計測震度
    pub local_intensity: Option<f64>,
    /// 所在地の予測震度階級（正規化済み）。不明なら空
    pub local_intensity_class: String,
    /// 震源距離 (km)
    pub distance_km: Option<f64>,
    /// 主要動 (S 波) 到達予測時刻 (UNIX ミリ秒)
    pub s_arrival_epoch_ms: Option<i64>,
    /// 一致した警報対象地域
    pub matched_area: Option<String>,
}

/// 接続状態
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EewConnectionStatus {
    Connecting,
    Connected,
    Disconnected,
}

/// リスナーから通知されるイベント
#[derive(Debug, Clone)]
pub struct EewEvent {
    pub status: EewConnectionStatus,
    pub message: String,
    pub report: Option<EewReport>,
}

static GENERATION: AtomicU64 = AtomicU64::new(0);

/// WebSocket による緊急地震速報の受信を開始する。
/// 呼び出すたびに以前のリスナーは停止する。切断時は自動で再接続する。
pub fn start_eew_listener(sink: StreamSink<EewEvent>) {
    let gen = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    std::thread::spawn(move || {
        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                let _ = sink.add(EewEvent {
                    status: EewConnectionStatus::Disconnected,
                    message: format!("ランタイム初期化失敗: {e}"),
                    report: None,
                });
                return;
            }
        };
        rt.block_on(listen_loop(gen, sink));
    });
}

/// リスナーを停止する
#[frb(sync)]
pub fn stop_eew_listener() {
    GENERATION.fetch_add(1, Ordering::SeqCst);
}

fn alive(gen: u64) -> bool {
    GENERATION.load(Ordering::SeqCst) == gen
}

async fn listen_loop(gen: u64, sink: StreamSink<EewEvent>) {
    let mut backoff = 2u64;
    while alive(gen) {
        let send = |status, message: String, report| {
            sink.add(EewEvent {
                status,
                message,
                report,
            })
            .is_ok()
        };
        if !send(EewConnectionStatus::Connecting, "接続中…".into(), None) {
            return;
        }
        match tokio_tungstenite::connect_async(WS_URL).await {
            Ok((ws, _)) => {
                backoff = 2;
                if !send(EewConnectionStatus::Connected, "接続しました".into(), None) {
                    return;
                }
                let (mut tx, mut rx) = ws.split();
                let mut ping = tokio::time::interval(Duration::from_secs(45));
                ping.tick().await;
                let mut check = tokio::time::interval(Duration::from_secs(1));
                let mut last_rx = tokio::time::Instant::now();
                let reason = loop {
                    tokio::select! {
                        msg = rx.next() => {
                            last_rx = tokio::time::Instant::now();
                            match msg {
                                Some(Ok(Message::Text(text))) => {
                                    if let Ok(report) = parse_eew_json(text.as_str().to_owned()) {
                                        if !send(EewConnectionStatus::Connected, "受信しました".into(), Some(report)) {
                                            return;
                                        }
                                    }
                                }
                                Some(Ok(Message::Ping(p))) => { let _ = tx.send(Message::Pong(p)).await; }
                                Some(Ok(Message::Close(_))) | None => break "サーバーから切断されました".to_string(),
                                Some(Ok(_)) => {}
                                Some(Err(e)) => break format!("通信エラー: {e}"),
                            }
                        }
                        _ = ping.tick() => {
                            if tx.send(Message::Text("ping".into())).await.is_err() {
                                break "送信エラー".to_string();
                            }
                        }
                        _ = check.tick() => {
                            if !alive(gen) {
                                let _ = tx.send(Message::Close(None)).await;
                                return;
                            }
                            // ハートビートは毎分届くため、150 秒無通信なら再接続
                            if last_rx.elapsed() > Duration::from_secs(150) {
                                break "応答がないため再接続します".to_string();
                            }
                        }
                    }
                };
                if !send(EewConnectionStatus::Disconnected, reason, None) {
                    return;
                }
            }
            Err(e) => {
                if !send(EewConnectionStatus::Disconnected, format!("接続失敗: {e}"), None) {
                    return;
                }
            }
        }
        // 再接続待ち（停止要求は 1 秒ごとに確認）
        for _ in 0..backoff {
            if !alive(gen) {
                return;
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        backoff = (backoff * 2).min(60);
    }
}

fn jst() -> FixedOffset {
    FixedOffset::east_opt(9 * 3600).unwrap()
}

/// "YYYY/MM/DD HH:MM:SS" (JST) を UNIX ミリ秒に変換
fn parse_jst(s: &str) -> Option<i64> {
    let dt = NaiveDateTime::parse_from_str(s.trim(), "%Y/%m/%d %H:%M:%S").ok()?;
    jst()
        .from_local_datetime(&dt)
        .single()
        .map(|d| d.timestamp_millis())
}

fn s(v: &Value, key: &str) -> String {
    match v.get(key) {
        Some(Value::String(x)) => x.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    }
}

fn f(v: &Value, key: &str) -> f64 {
    match v.get(key) {
        Some(Value::Number(n)) => n.as_f64().unwrap_or(0.0),
        Some(Value::String(x)) => x.parse().unwrap_or(0.0),
        _ => 0.0,
    }
}

fn b(v: &Value, key: &str) -> bool {
    v.get(key).and_then(Value::as_bool).unwrap_or(false)
}

/// Wolfx の JMA EEW JSON を解析する。緊急地震速報以外（heartbeat など）はエラー。
#[frb(sync)]
pub fn parse_eew_json(json: String) -> anyhow::Result<EewReport> {
    let v: Value = serde_json::from_str(&json)?;
    if let Some(t) = v.get("type").and_then(Value::as_str) {
        if t != "jma_eew" {
            anyhow::bail!("緊急地震速報ではありません: {t}");
        }
    }
    if v.get("EventID").is_none() {
        anyhow::bail!("EventID がありません");
    }
    let warn_areas = v
        .get("WarnArea")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .map(|a| WarnAreaInfo {
                    chiiki: s(a, "Chiiki"),
                    shindo1: normalize_intensity(&s(a, "Shindo1")),
                    shindo2: normalize_intensity(&s(a, "Shindo2")),
                    time: {
                        let t = s(a, "Time");
                        if t.chars().all(|c| c.is_ascii_digit()) { t } else { String::new() }
                    },
                    kind: s(a, "Type"),
                    arrive: s(a, "Arrive"),
                })
                .collect()
        })
        .unwrap_or_default();
    let magnitude = match v.get("Magnitude") {
        Some(_) => f(&v, "Magnitude"),
        None => f(&v, "Magunitude"),
    };
    let announced_time = s(&v, "AnnouncedTime");
    let origin_time = s(&v, "OriginTime");
    let issue = v.get("Issue").cloned().unwrap_or(Value::Null);
    let status = s(&issue, "Status");
    Ok(EewReport {
        title: s(&v, "Title"),
        code_type: s(&v, "CodeType"),
        event_id: s(&v, "EventID"),
        serial: f(&v, "Serial") as i32,
        announced_epoch_ms: parse_jst(&announced_time),
        announced_time,
        origin_epoch_ms: parse_jst(&origin_time),
        origin_time,
        hypocenter: s(&v, "Hypocenter"),
        latitude: f(&v, "Latitude"),
        longitude: f(&v, "Longitude"),
        magnitude,
        depth: f(&v, "Depth"),
        max_intensity: normalize_intensity(&s(&v, "MaxIntensity")),
        is_sea: b(&v, "isSea"),
        is_training: b(&v, "isTraining") || status.contains("訓練"),
        is_assumption: b(&v, "isAssumption"),
        is_warn: b(&v, "isWarn"),
        is_final: b(&v, "isFinal"),
        is_cancel: b(&v, "isCancel"),
        is_test: false,
        warn_areas,
    })
}

fn keywords(settings: &EewSettings) -> Vec<String> {
    settings
        .area_keywords
        .split([',', '、', '，'])
        .map(|k| k.trim().to_string())
        .filter(|k| !k.is_empty())
        .collect()
}

/// 地域の主要動到達予測時刻 (HHMMSS) を UNIX ミリ秒に変換する
fn area_time_epoch(report: &EewReport, hhmmss: &str) -> Option<i64> {
    if hhmmss.len() != 6 {
        return None;
    }
    let t = NaiveTime::parse_from_str(hhmmss, "%H%M%S").ok()?;
    let base = report.origin_epoch_ms.or(report.announced_epoch_ms)?;
    let base_dt = Utc.timestamp_millis_opt(base).single()?.with_timezone(&jst());
    let date: NaiveDate = base_dt.date_naive();
    let mut ms = jst()
        .from_local_datetime(&date.and_time(t))
        .single()?
        .timestamp_millis();
    // 日付をまたぐ場合の補正
    if ms < base - 12 * 3600 * 1000 {
        ms += 24 * 3600 * 1000;
    }
    Some(ms)
}

/// 受信した緊急地震速報が所在地に影響するかを判定する
#[frb(sync)]
pub fn evaluate_eew(report: EewReport, settings: EewSettings) -> EewEvaluation {
    let threshold = intensity_rank(&settings.intensity_threshold).unwrap_or(4);
    let mut eval = EewEvaluation {
        affects: false,
        reason: String::new(),
        local_intensity: None,
        local_intensity_class: String::new(),
        distance_km: None,
        s_arrival_epoch_ms: None,
        matched_area: None,
    };

    // 震源の推定値が使えるか（仮定震源要素・レベル法・不明値は除外）
    let reliable_hypocenter = !report.is_assumption
        && report.magnitude > 1.0
        && !(report.latitude == 0.0 && report.longitude == 0.0);

    if reliable_hypocenter {
        let epi = haversine_km(
            settings.latitude,
            settings.longitude,
            report.latitude,
            report.longitude,
        );
        let hypo = (epi * epi + report.depth * report.depth).sqrt();
        eval.distance_km = Some(hypo);
        let i = estimate_intensity(
            report.magnitude,
            report.depth,
            epi,
            settings.site_amplification,
        );
        eval.local_intensity = Some(i);
        eval.local_intensity_class = intensity_class(i);
        if let Some(origin) = report.origin_epoch_ms {
            eval.s_arrival_epoch_ms = Some(origin + (hypo / S_WAVE_VELOCITY * 1000.0) as i64);
        }
    }

    // 警報対象地域との照合
    let kws = keywords(&settings);
    let matched = report.warn_areas.iter().find(|a| {
        kws.iter().any(|k| a.chiiki.starts_with(k.as_str()))
    });
    if let Some(area) = matched {
        eval.matched_area = Some(area.chiiki.clone());
        // 地域の到達予測時刻があれば優先
        if let Some(ms) = area_time_epoch(&report, &area.time) {
            eval.s_arrival_epoch_ms = Some(ms);
        }
        if eval.local_intensity_class.is_empty() {
            eval.local_intensity_class = area.shindo1.clone();
        }
    }

    if report.is_cancel {
        eval.reason = "取消報".into();
        return eval;
    }
    if report.is_training && !settings.show_training && !report.is_test {
        eval.reason = "訓練報のため表示しません".into();
        return eval;
    }

    if settings.use_warn_area {
        if let Some(area) = matched {
            let rank = intensity_rank(&area.shindo1);
            if rank.map_or(report.is_warn, |r| r >= threshold) {
                eval.affects = true;
                eval.reason = format!("対象地域「{}」(予測震度 {})", area.chiiki, area.shindo1);
                return eval;
            }
        }
    }
    if settings.use_estimation {
        if let Some(i) = eval.local_intensity {
            if intensity_rank(&intensity_class(i)).unwrap_or(0) >= threshold {
                eval.affects = true;
                eval.reason = format!("推定震度 {} (計測震度 {:.1})", intensity_class(i), i);
                return eval;
            }
        }
    }
    eval.reason = "所在地への影響はしきい値未満".into();
    eval
}

/// テスト表示用の緊急地震速報を生成する（所在地の西 40km、M6.8）
#[frb(sync)]
pub fn sample_eew_report(settings: EewSettings) -> EewReport {
    let now = Utc::now().with_timezone(&jst());
    let origin = now - chrono::Duration::seconds(3);
    let fmt = |d: chrono::DateTime<FixedOffset>| d.format("%Y/%m/%d %H:%M:%S").to_string();
    let lon_offset = 40.0 / (111.32 * settings.latitude.to_radians().cos().max(0.1));
    let area = keywords(&settings)
        .first()
        .cloned()
        .unwrap_or_else(|| settings.prefecture.clone());
    let arrival = origin + chrono::Duration::seconds(15);
    EewReport {
        title: "緊急地震速報（警報）".into(),
        code_type: "テスト".into(),
        event_id: format!("TEST{}", now.timestamp()),
        serial: 1,
        announced_time: fmt(now),
        announced_epoch_ms: Some(now.timestamp_millis()),
        origin_time: fmt(origin),
        origin_epoch_ms: Some(origin.timestamp_millis()),
        hypocenter: "テスト震源".into(),
        latitude: settings.latitude,
        longitude: settings.longitude - lon_offset,
        magnitude: 6.8,
        depth: 20.0,
        max_intensity: "6-".into(),
        is_sea: false,
        is_training: false,
        is_assumption: false,
        is_warn: true,
        is_final: false,
        is_cancel: false,
        is_test: true,
        warn_areas: vec![WarnAreaInfo {
            chiiki: format!("{area}（テスト）"),
            shindo1: "6-".into(),
            shindo2: "5+".into(),
            time: arrival.format("%H%M%S").to_string(),
            kind: "警報".into(),
            arrive: "未到達".into(),
        }],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{"type":"jma_eew","Title":"緊急地震速報（警報）","CodeType":"Ｍ、最大予測震度及び主要動到達予測時刻の緊急地震速報","Issue":{"Source":"東京","Status":"通常"},"EventID":"20240101161010","Serial":5,"AnnouncedTime":"2024/01/01 16:10:40","OriginTime":"2024/01/01 16:10:09","Hypocenter":"石川県能登地方","Latitude":37.5,"Longitude":137.2,"Magunitude":7.4,"Magnitude":7.4,"Depth":10,"MaxIntensity":"7","Accuracy":{"Epicenter":"","Depth":"","Magnitude":""},"MaxIntChange":{"String":"","Reason":""},"WarnArea":[{"Chiiki":"石川県能登","Shindo1":"7","Shindo2":"6強","Time":"161025","Type":"警報","Arrive":"未到達"},{"Chiiki":"新潟県上越","Shindo1":"5強","Shindo2":"5弱","Time":"161030","Type":"警報","Arrive":"未到達"}],"isSea":false,"isTraining":false,"isAssumption":false,"isWarn":true,"isFinal":false,"isCancel":false,"OriginalText":"","Pond":"0"}"#;

    fn settings(pref_kw: &str, lat: f64, lon: f64) -> EewSettings {
        EewSettings {
            area_keywords: pref_kw.into(),
            latitude: lat,
            longitude: lon,
            ..EewSettings::default()
        }
    }

    #[test]
    fn parse_sample() {
        let r = parse_eew_json(SAMPLE.into()).unwrap();
        assert_eq!(r.hypocenter, "石川県能登地方");
        assert_eq!(r.magnitude, 7.4);
        assert_eq!(r.warn_areas.len(), 2);
        assert_eq!(r.warn_areas[1].shindo1, "5+");
        assert!(r.is_warn);
        assert!(r.origin_epoch_ms.is_some());
    }

    #[test]
    fn heartbeat_is_rejected() {
        assert!(parse_eew_json(r#"{"type":"heartbeat","ver":18}"#.into()).is_err());
    }

    #[test]
    fn warn_area_match() {
        let r = parse_eew_json(SAMPLE.into()).unwrap();
        // 金沢市
        let e = evaluate_eew(r.clone(), settings("石川", 36.594, 136.626));
        assert!(e.affects, "{}", e.reason);
        assert_eq!(e.matched_area.as_deref(), Some("石川県能登"));
        // 到達時刻は地域の Time (16:10:25 JST) が使われる
        let expect = parse_jst("2024/01/01 16:10:25").unwrap();
        assert_eq!(e.s_arrival_epoch_ms, Some(expect));
    }

    #[test]
    fn far_location_not_affected() {
        let r = parse_eew_json(SAMPLE.into()).unwrap();
        // 那覇市
        let e = evaluate_eew(r, settings("沖縄", 26.212, 127.681));
        assert!(!e.affects, "{}", e.reason);
    }

    #[test]
    fn estimation_triggers_without_area() {
        let r = parse_eew_json(SAMPLE.into()).unwrap();
        // 富山市（WarnArea に含まれないが近い）
        let e = evaluate_eew(r, settings("富山", 36.695, 137.211));
        assert!(e.affects, "{}", e.reason);
        assert!(e.local_intensity.unwrap() >= 4.5);
    }

    #[test]
    fn training_is_ignored_by_default() {
        let mut r = parse_eew_json(SAMPLE.into()).unwrap();
        r.is_training = true;
        let e = evaluate_eew(r, settings("石川", 36.594, 136.626));
        assert!(!e.affects);
    }

    #[test]
    fn sample_report_affects() {
        let s = EewSettings::default();
        let r = sample_eew_report(s.clone());
        let e = evaluate_eew(r, s);
        assert!(e.affects, "{}", e.reason);
        assert!(e.s_arrival_epoch_ms.is_some());
    }
}
