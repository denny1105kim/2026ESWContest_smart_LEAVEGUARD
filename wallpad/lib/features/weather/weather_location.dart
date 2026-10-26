/// 날씨 지역: 기상청 격자(nx, ny)와 미세먼지 측정소를 찾을 시·도, 시·군·구.
class WeatherLocation {
  final String name;
  final int nx;
  final int ny;
  final String sido;
  final String sigungu;

  const WeatherLocation(this.name, this.nx, this.ny, {required this.sido, required this.sigungu});

  static const seoul = WeatherLocation('서울', 60, 127, sido: '서울특별시', sigungu: '중구');
}
