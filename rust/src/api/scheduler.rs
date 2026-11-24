//! 曜日・時刻・期間の条件から表示するデータセットを決定するスケジューラ。

use chrono::{Datelike, Duration, Local, NaiveDate, NaiveDateTime, NaiveTime};
use flutter_rust_bridge::frb;

use super::models::{AppConfig, ScheduleRule};

/// 現在のローカル時刻で有効なデータセット ID を返す
#[frb(sync)]
pub fn resolve_active_dataset(config: AppConfig) -> String {
    resolve_at(&config, Local::now().naive_local())
}

/// 現在のローカル時刻で一致しているルール ID（なければ None）
#[frb(sync)]
pub fn resolve_active_rule(config: AppConfig) -> Option<String> {
    active_rule_at(&config, Local::now().naive_local()).map(|r| r.id.clone())
}

/// "HH:MM" 形式の時刻の妥当性をチェックする
#[frb(sync)]
pub fn is_valid_time(text: String) -> bool {
    parse_time(&text).is_some()
}

/// "YYYY-MM-DD" 形式の日付の妥当性をチェックする
#[frb(sync)]
pub fn is_valid_date(text: String) -> bool {
    parse_date(&text).is_some()
}

pub(crate) fn resolve_at(config: &AppConfig, now: NaiveDateTime) -> String {
    match active_rule_at(config, now) {
        Some(rule) => rule.dataset_id.clone(),
        None => config.default_dataset_id.clone(),
    }
}

fn active_rule_at(config: &AppConfig, now: NaiveDateTime) -> Option<&ScheduleRule> {
    let mut best: Option<&ScheduleRule> = None;
    for rule in &config.rules {
        if !rule.enabled || !config.datasets.iter().any(|d| d.id == rule.dataset_id) {
            continue;
        }
        if !rule_matches(rule, now) {
            continue;
        }
        // 優先度が高いものを採用。同じ優先度ならリストの先頭を優先
        if best.map_or(true, |b| rule.priority > b.priority) {
            best = Some(rule);
        }
    }
    best
}

fn parse_time(s: &str) -> Option<NaiveTime> {
    NaiveTime::parse_from_str(s.trim(), "%H:%M").ok()
}

fn parse_date(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(s.trim(), "%Y-%m-%d").ok()
}

fn weekday_ok(mask: u32, date: NaiveDate) -> bool {
    mask & 0x7F == 0 || mask & (1 << date.weekday().num_days_from_monday()) != 0
}

fn date_ok(rule: &ScheduleRule, date: NaiveDate) -> bool {
    if let Some(start) = rule.start_date.as_deref().and_then(parse_date) {
        if date < start {
            return false;
        }
    }
    if let Some(end) = rule.end_date.as_deref().and_then(parse_date) {
        if date > end {
            return false;
        }
    }
    true
}

/// ルールが指定時刻に一致するか。
/// 日をまたぐ時間帯（例: 22:00〜02:00）は、開始した日の曜日・日付で判定する。
pub(crate) fn rule_matches(rule: &ScheduleRule, now: NaiveDateTime) -> bool {
    let (Some(start), Some(end)) = (parse_time(&rule.start_time), parse_time(&rule.end_time))
    else {
        return false;
    };
    let today = now.date();
    let t = now.time();
    let day_ok = |d: NaiveDate| weekday_ok(rule.weekday_mask, d) && date_ok(rule, d);

    if start == end {
        // 終日
        day_ok(today)
    } else if start < end {
        t >= start && t < end && day_ok(today)
    } else if t >= start {
        // 日をまたぐ: 当日の開始以降
        day_ok(today)
    } else if t < end {
        // 日をまたぐ: 翌日の終了前 → 前日の条件で判定
        day_ok(today - Duration::days(1))
    } else {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::models::*;

    fn dt(s: &str) -> NaiveDateTime {
        NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M").unwrap()
    }

    fn config_with(rules: Vec<ScheduleRule>) -> AppConfig {
        let mk = |id: &str| Dataset {
            id: id.into(),
            name: id.into(),
            items: vec![],
        };
        AppConfig {
            datasets: vec![mk("default"), mk("a"), mk("b")],
            default_dataset_id: "default".into(),
            rules,
            ..AppConfig::default()
        }
    }

    fn rule(ds: &str, mask: u32, s: &str, e: &str, prio: i32) -> ScheduleRule {
        ScheduleRule {
            id: ds.into(),
            dataset_id: ds.into(),
            weekday_mask: mask,
            start_time: s.into(),
            end_time: e.into(),
            priority: prio,
            ..ScheduleRule::default()
        }
    }

    #[test]
    fn falls_back_to_default() {
        let cfg = config_with(vec![rule("a", 0, "09:00", "10:00", 0)]);
        // 2026-11-23 は月曜日
        assert_eq!(resolve_at(&cfg, dt("2026-11-23 08:59")), "default");
        assert_eq!(resolve_at(&cfg, dt("2026-11-23 09:00")), "a");
        assert_eq!(resolve_at(&cfg, dt("2026-11-23 10:00")), "default");
    }

    #[test]
    fn weekday_mask_works() {
        // 土日 (bit5, bit6)
        let cfg = config_with(vec![rule("a", 0b110_0000, "00:00", "00:00", 0)]);
        assert_eq!(resolve_at(&cfg, dt("2026-11-23 12:00")), "default"); // 月
        assert_eq!(resolve_at(&cfg, dt("2026-11-28 12:00")), "a"); // 土
        assert_eq!(resolve_at(&cfg, dt("2026-11-29 12:00")), "a"); // 日
    }

    #[test]
    fn overnight_uses_start_day() {
        // 金曜 (bit4) の 22:00〜02:00
        let cfg = config_with(vec![rule("a", 0b1_0000, "22:00", "02:00", 0)]);
        assert_eq!(resolve_at(&cfg, dt("2026-11-27 23:00")), "a"); // 金 23時
        assert_eq!(resolve_at(&cfg, dt("2026-11-28 01:30")), "a"); // 土 1時半（金曜の延長）
        assert_eq!(resolve_at(&cfg, dt("2026-11-28 23:00")), "default"); // 土 23時
        assert_eq!(resolve_at(&cfg, dt("2026-11-27 01:00")), "default"); // 金 1時（木曜の延長）
    }

    #[test]
    fn priority_and_dates() {
        let mut special = rule("b", 0, "00:00", "00:00", 10);
        special.start_date = Some("2026-12-24".into());
        special.end_date = Some("2026-12-25".into());
        let cfg = config_with(vec![rule("a", 0, "00:00", "00:00", 0), special]);
        assert_eq!(resolve_at(&cfg, dt("2026-12-23 12:00")), "a");
        assert_eq!(resolve_at(&cfg, dt("2026-12-24 12:00")), "b");
        assert_eq!(resolve_at(&cfg, dt("2026-12-25 23:59")), "b");
        assert_eq!(resolve_at(&cfg, dt("2026-12-26 00:00")), "a");
    }

    #[test]
    fn disabled_or_missing_dataset_is_ignored() {
        let mut r = rule("a", 0, "00:00", "00:00", 0);
        r.enabled = false;
        let cfg = config_with(vec![r, rule("zzz", 0, "00:00", "00:00", 5)]);
        assert_eq!(resolve_at(&cfg, dt("2026-11-23 12:00")), "default");
    }
}
