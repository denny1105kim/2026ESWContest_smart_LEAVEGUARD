part of '../app_state.dart';

extension AppWeather on AppState {
  Future<void> refreshWeather({bool force = false}) async {
    refreshAir(force: force);
    refreshUv(force: force);
    if (_weatherLoading) return;
    final at = weatherAt;
    if (!force && at != null && DateTime.now().difference(at) < weatherRefresh) return;
    const loc = WeatherLocation.seoul;
    _weatherLoading = true;
    try {
      final key = (await DeviceConfig.load())?['weather_key'];
      if (key is! String || key.trim().isEmpty) {
        weatherNotice = '설정 파일에 날씨 키(weather_key)가 없어요';
        return;
      }
      final (t, next) = await KmaWeather(key.trim()).fetchDays(loc.nx, loc.ny);
      if (!devTomorrowRain) weatherTomorrow = next == null ? null : _weatherOf(loc.name, next);
      if (devBigGap) return; // 개발용으로 꾸민 일교차를 덮어쓰지 않게
      weather = _weatherOf(loc.name, t);
      weatherAt = DateTime.now();
      weatherNotice = null;
    } catch (e) {
      debugPrint('LeaveGuard: 날씨를 받지 못함 ($e)');
      if (weather == null) weatherNotice = '날씨를 불러오지 못했어요';
    } finally {
      _weatherLoading = false;
      _changed();
    }
  }

  Future<void> refreshAir({bool force = false}) async {
    if (_airLoading) return;
    final at = airAt;
    if (!force && at != null && DateTime.now().difference(at) < weatherRefresh) return;
    _airLoading = true;
    try {
      final key = (await DeviceConfig.load())?['weather_key'];
      if (key is! String || key.trim().isEmpty) return;
      const loc = WeatherLocation.seoul;
      final fresh = await AirKorea(key.trim()).fetch(sido: loc.sido, sigungu: loc.sigungu);
      if (devAirBad) return;
      final before = at != null && DateUtils.isSameDay(at, DateTime.now()) ? air : null;
      air = AirQuality(now: fresh.now ?? before?.now, forecast: fresh.forecast ?? before?.forecast, tomorrow: fresh.tomorrow ?? before?.tomorrow);
      airAt = DateTime.now();
    } catch (e) {
      debugPrint('LeaveGuard: 미세먼지를 받지 못함 ($e)');
    } finally {
      _airLoading = false;
      _changed();
    }
  }

  Future<void> refreshUv({bool force = false}) async {
    if (_uvLoading) return;
    final at = uvAt;
    if (!force && at != null && DateTime.now().difference(at) < weatherRefresh) return;
    _uvLoading = true;
    try {
      final key = (await DeviceConfig.load())?['weather_key'];
      if (key is! String || key.trim().isEmpty) return;
      final (fresh, next) = await KmaUv(key.trim()).fetchDays(AirKorea.sidoShort(WeatherLocation.seoul.sido));
      if (devUvHigh) return;
      final sameDay = at != null && DateUtils.isSameDay(at, DateTime.now());
      uv = fresh ?? (sameDay ? uv : null);
      uvTomorrow = next ?? (sameDay ? uvTomorrow : null);
      uvAt = DateTime.now();
    } catch (e) {
      debugPrint('LeaveGuard: 자외선을 받지 못함 ($e)');
    } finally {
      _uvLoading = false;
      _changed();
    }
  }

  static Weather _weatherOf(String location, TodayWeather t) => Weather(
        location: location,
        tempC: t.tempC.round(),
        highC: t.highC.round(),
        lowC: t.lowC.round(),
        precipProb: t.pop,
        icon: _weatherIcon(t.sky),
        label: t.sky.label,
        hours: [for (final h in t.hours) WeatherHour(at: h.at, tempC: h.tempC.round(), precipProb: h.pop, icon: _weatherIcon(h.sky))],
      );

  static IconData _weatherIcon(WeatherSky s) => switch (s) {
        WeatherSky.clear => Icons.wb_sunny_rounded,
        WeatherSky.partlyCloudy => Icons.wb_cloudy_rounded,
        WeatherSky.cloudy => Icons.cloud_rounded,
        WeatherSky.rain || WeatherSky.shower => Icons.water_drop_rounded,
        WeatherSky.rainSnow || WeatherSky.snow => Icons.ac_unit_rounded,
      };
}
