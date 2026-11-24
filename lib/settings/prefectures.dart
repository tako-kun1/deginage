/// 都道府県と県庁所在地の座標、および緊急地震速報の対象地域照合用キーワード
class Prefecture {
  const Prefecture(this.name, this.keywords, this.latitude, this.longitude);

  final String name;

  /// WarnArea.Chiiki と前方一致で照合するキーワード（カンマ区切り）
  final String keywords;
  final double latitude;
  final double longitude;
}

const List<Prefecture> kPrefectures = [
  Prefecture('北海道', '北海道', 43.064, 141.347),
  Prefecture('青森県', '青森', 40.824, 140.740),
  Prefecture('岩手県', '岩手', 39.704, 141.153),
  Prefecture('宮城県', '宮城', 38.269, 140.872),
  Prefecture('秋田県', '秋田', 39.719, 140.102),
  Prefecture('山形県', '山形', 38.240, 140.364),
  Prefecture('福島県', '福島', 37.750, 140.468),
  Prefecture('茨城県', '茨城', 36.342, 140.447),
  Prefecture('栃木県', '栃木', 36.566, 139.884),
  Prefecture('群馬県', '群馬', 36.391, 139.061),
  Prefecture('埼玉県', '埼玉', 35.857, 139.649),
  Prefecture('千葉県', '千葉', 35.605, 140.123),
  Prefecture('東京都', '東京,伊豆諸島,小笠原', 35.690, 139.692),
  Prefecture('神奈川県', '神奈川', 35.448, 139.643),
  Prefecture('新潟県', '新潟', 37.902, 139.023),
  Prefecture('富山県', '富山', 36.695, 137.211),
  Prefecture('石川県', '石川', 36.594, 136.626),
  Prefecture('福井県', '福井', 36.065, 136.222),
  Prefecture('山梨県', '山梨', 35.664, 138.568),
  Prefecture('長野県', '長野', 36.651, 138.181),
  Prefecture('岐阜県', '岐阜', 35.391, 136.722),
  Prefecture('静岡県', '静岡', 34.977, 138.383),
  Prefecture('愛知県', '愛知', 35.180, 136.907),
  Prefecture('三重県', '三重', 34.730, 136.509),
  Prefecture('滋賀県', '滋賀', 35.004, 135.869),
  Prefecture('京都府', '京都', 35.021, 135.756),
  Prefecture('大阪府', '大阪', 34.686, 135.520),
  Prefecture('兵庫県', '兵庫', 34.691, 135.183),
  Prefecture('奈良県', '奈良', 34.685, 135.833),
  Prefecture('和歌山県', '和歌山', 34.226, 135.168),
  Prefecture('鳥取県', '鳥取', 35.504, 134.238),
  Prefecture('島根県', '島根', 35.472, 133.051),
  Prefecture('岡山県', '岡山', 34.662, 133.935),
  Prefecture('広島県', '広島', 34.396, 132.459),
  Prefecture('山口県', '山口', 34.186, 131.471),
  Prefecture('徳島県', '徳島', 34.066, 134.559),
  Prefecture('香川県', '香川', 34.340, 134.043),
  Prefecture('愛媛県', '愛媛', 33.842, 132.766),
  Prefecture('高知県', '高知', 33.560, 133.531),
  Prefecture('福岡県', '福岡', 33.607, 130.418),
  Prefecture('佐賀県', '佐賀', 33.249, 130.299),
  Prefecture('長崎県', '長崎', 32.745, 129.874),
  Prefecture('熊本県', '熊本', 32.790, 130.742),
  Prefecture('大分県', '大分', 33.238, 131.613),
  Prefecture('宮崎県', '宮崎', 31.911, 131.424),
  Prefecture('鹿児島県', '鹿児島,種子島,屋久島,奄美', 31.560, 130.558),
  Prefecture('沖縄県', '沖縄,大東島,宮古島,八重山', 26.212, 127.681),
];
