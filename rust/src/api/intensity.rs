//! 震度の正規化・推定計算。
//!
//! 推定震度は司・翠川 (1999) の最大速度距離減衰式と、
//! 翠川ほか (1999) の計測震度換算式による簡易推定。

use flutter_rust_bridge::frb;

const LEVELS: [&str; 10] = ["0", "1", "2", "3", "4", "5-", "5+", "6-", "6+", "7"];

/// 震度表記を正規化する ("5弱" → "5-", "6強" → "6+", "不明" → "")
pub(crate) fn normalize_intensity(raw: &str) -> String {
    let s = raw
        .trim()
        .replace("震度", "")
        .replace("程度以上", "")
        .replace("以上", "")
        .replace('弱', "-")
        .replace('強', "+")
        .replace('－', "-")
        .replace('＋', "+");
    let s: String = s
        .chars()
        .map(|c| match c {
            '０'..='９' => char::from_u32(c as u32 - '０' as u32 + '0' as u32).unwrap(),
            _ => c,
        })
        .collect();
    let s = s.trim().to_string();
    match s.as_str() {
        "5" => "5-".into(),
        "6" => "6-".into(),
        x if LEVELS.contains(&x) => x.into(),
        _ => String::new(),
    }
}

/// 震度階級の順位 (0〜9)。不明な場合は None
pub(crate) fn intensity_rank(raw: &str) -> Option<i32> {
    let n = normalize_intensity(raw);
    LEVELS.iter().position(|l| *l == n).map(|p| p as i32)
}

/// 計測震度から震度階級（正規化表記）を求める
pub(crate) fn intensity_class(i: f64) -> String {
    let c = if i < 0.5 {
        "0"
    } else if i < 1.5 {
        "1"
    } else if i < 2.5 {
        "2"
    } else if i < 3.5 {
        "3"
    } else if i < 4.5 {
        "4"
    } else if i < 5.0 {
        "5-"
    } else if i < 5.5 {
        "5+"
    } else if i < 6.0 {
        "6-"
    } else if i < 6.5 {
        "6+"
    } else {
        "7"
    };
    c.into()
}

/// 震度の表示用文字列 ("5-" → "5弱")
#[frb(sync)]
pub fn intensity_label(raw: String) -> String {
    let n = normalize_intensity(&raw);
    if n.is_empty() {
        return "不明".into();
    }
    n.replace('-', "弱").replace('+', "強")
}

/// 選択可能な震度階級の一覧（正規化表記）
#[frb(sync)]
pub fn intensity_levels() -> Vec<String> {
    LEVELS[1..].iter().map(|s| s.to_string()).collect()
}

/// 2 点間の大円距離 (km)
pub(crate) fn haversine_km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let r = 6371.0;
    let d_lat = (lat2 - lat1).to_radians();
    let d_lon = (lon2 - lon1).to_radians();
    let a = (d_lat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (d_lon / 2.0).sin().powi(2);
    2.0 * r * a.sqrt().asin()
}

/// 所在地の計測震度を推定する
///
/// * `mj` - 気象庁マグニチュード
/// * `depth` - 震源の深さ (km)
/// * `epicentral_km` - 震央距離 (km)
/// * `amp` - 地盤増幅率 (工学的基盤 → 地表)
pub(crate) fn estimate_intensity(mj: f64, depth: f64, epicentral_km: f64, amp: f64) -> f64 {
    let mw = mj - 0.171;
    let depth = depth.clamp(1.0, 200.0);
    let hypo = (epicentral_km.powi(2) + depth.powi(2)).sqrt();
    // 断層長の半分を差し引いて断層最短距離を近似
    let fault_len = 10f64.powf(0.5 * mw - 1.85);
    let x = (hypo - fault_len / 2.0).max(3.0);
    let log_pgv600 = 0.58 * mw + 0.0038 * depth - 1.29
        - (x + 0.0028 * 10f64.powf(0.5 * mw)).log10()
        - 0.002 * x;
    // Vs600 → Vs400 への換算 (×1.31) と地盤増幅
    let pgv = 10f64.powf(log_pgv600) * 1.31 * amp.max(0.1);
    let lp = pgv.log10();
    let i = 2.68 + 1.72 * lp;
    let i = if i < 4.0 { 2.165 + 2.262 * lp } else { i };
    i.clamp(0.0, 7.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize() {
        assert_eq!(normalize_intensity("5弱"), "5-");
        assert_eq!(normalize_intensity("６強"), "6+");
        assert_eq!(normalize_intensity("4"), "4");
        assert_eq!(normalize_intensity("5弱以上"), "5-");
        assert_eq!(normalize_intensity("不明"), "");
        assert_eq!(intensity_rank("5+"), Some(6));
        assert_eq!(intensity_label("6-".into()), "6弱");
    }

    #[test]
    fn classes() {
        assert_eq!(intensity_class(4.4), "4");
        assert_eq!(intensity_class(4.6), "5-");
        assert_eq!(intensity_class(6.7), "7");
    }

    #[test]
    fn distance() {
        // 東京 - 大阪 ≒ 400km
        let d = haversine_km(35.690, 139.692, 34.686, 135.520);
        assert!((390.0..410.0).contains(&d), "{d}");
    }

    #[test]
    fn estimation_is_reasonable() {
        // M7.0, 深さ10km, 震央距離30km → 震度5強〜6弱程度
        let i = estimate_intensity(7.0, 10.0, 30.0, 1.4);
        assert!((5.0..6.0).contains(&i), "{i}");
        // 遠方ほど小さくなる
        assert!(estimate_intensity(7.0, 10.0, 300.0, 1.4) < i);
        // 小さい地震の遠方は震度0〜2
        assert!(estimate_intensity(3.5, 10.0, 200.0, 1.4) < 2.5);
    }
}
