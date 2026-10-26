part of '../app_state.dart';

extension AppFlow on AppState {
  void go(Stage next) {
    if (next == Stage.idle && users.isEmpty) next = Stage.welcome; // 멤버가 없으면 첫 시작 화면
    if (next == Stage.idle || next == Stage.welcome) _endSession();
    stage = next;
    _armScreenOff(); // 화면이 바뀌면 안 건드린 시간을 처음부터 센다
    _changed();
    if (next == Stage.checklist || next == Stage.returning) {
      refreshCalendar();
      refreshWeather();
      refreshFamily();
    }
    if (next == Stage.returning && onBoard) voiceMemo.warmUp().ignore();
  }

  void _endSession() {
    auth = null;
    _farewellTimer?.cancel();
    _returnTimer?.cancel();
    userId = null;
    engaged.clear();
    _askedThisVisit.clear();
    activeQuestion = null;
    trayPeek = false;
    prompt = Prompt.none;
    group.clear();
    groupPick.clear();
    homecoming = false;
    returnDone = false;
    _resetReturnCheck();
  }

  void _enter(String id) {
    userId = id;
    if (!engaged.contains(id)) engaged.add(id);
    prompt = Prompt.none;
  }

  bool cameHome(String id) {
    final at = departedAt[id];
    return at != null && clock().difference(at) >= returnGrace;
  }

  void _enterIdentified(String id) {
    final back = (homecoming && cameHome(id)) || (AppClock.shifted && returnTimeOf(id));
    _enter(id);
    if (!back) _maybeAsk(id);
    back ? _arriveHome(id) : go(Stage.checklist);
  }

  void _arriveHome(String id) {
    final fresh = freshReturn(id);
    departedAt.remove(id);
    if (fresh) _recordReturn(id);
    _resetReturnCheck();
    returnCheckDone = !fresh && returnAnswered(id);
    // 화면을 바꾸기 전에 열어야 첫 화면부터 창이 덮여 있다
    if (fresh && returnCheckOn(id) && takenTodayOf(id).isNotEmpty) returnCheckOpen = true;
    go(Stage.returning);
  }

  void motion() {
    if (stage == Stage.idle) go(users.isEmpty ? Stage.welcome : Stage.identifying);
  }

  void faceSucceeded(String id) {
    if (stage != Stage.identifying) return;
    greetingUserId = id;
    _changed();
    _greetTimer?.cancel();
    _greetTimer = Timer(nameFlash, () {
      greetingUserId = null;
      // PIN 이 없는 사람은 얼굴로 확인됐으니 이번에 정한다
      if (hasPin(id)) return _enterIdentified(id);
      requestAuth(id, AuthPurpose.create, () => _enterIdentified(id));
    });
  }

  void faceFailed() {
    if (stage == Stage.identifying) go(Stage.userSelect);
  }

  void selectUser(String id) {
    requestAuth(id, AuthPurpose.pick, () => _enterIdentified(id));
  }

  void switchUser(String id) {
    if (id == userId) return;
    requestAuth(id, AuthPurpose.switchTo, () => _switchTo(id));
  }

  void _switchTo(String id) {
    if (stage == Stage.returning) return _enterIdentified(id);
    _enter(id);
    _changed();
    refreshCalendar();
  }

  void leaving() => go(Stage.idle);

  void returning() {
    if (stage != Stage.idle) return;
    homecoming = true;
    go(Stage.identifying);
  }

  void finishReturn() {
    if (stage != Stage.returning || returnDone || returnCheckOpen) return;
    prompt = Prompt.none;
    returnDone = true;
    final id = userId;
    if (id != null && returnedTodayAt(id) == null) _recordReturn(id);
    _changed();
    _returnTimer?.cancel();
    _returnTimer = Timer(returnDoneHold, () {
      if (stage == Stage.returning) go(Stage.idle);
    });
  }

  void entranceEmpty() {
    if (const [Stage.checklist, Stage.settings, Stage.returning].contains(stage)) go(Stage.idle);
  }

  void openSettings([SettingsPane pane = SettingsPane.belongings, bool fromChecklistCalendar = false]) {
    settingsPane = pane;
    calendarFromChecklist = fromChecklistCalendar;
    go(Stage.settings);
  }

  void showPane(SettingsPane pane) {
    settingsPane = pane;
    calendarFromChecklist = false;
    _changed();
  }

  void startOnboarding(Stage from) {
    onboardingFrom = from;
    onboardingHost = from == Stage.settings ? userId : null;
    go(Stage.onboarding);
  }

  void leaveOnboarding() {
    final host = onboardingHost;
    onboardingHost = null;
    if (host != null && userOf(host) != null) {
      _enter(host);
      return go(Stage.checklist);
    }
    // go(Stage.idle) 은 멤버가 없으면 첫 시작 화면으로 바꾸므로 직접 끈다
    _endSession();
    stage = Stage.idle;
    _armScreenOff();
    _changed();
  }

  void finishOnboarding(User user) {
    onboardingHost = null;
    completeMember(user);
    _enter(user.id);
    go(Stage.checklist);
  }
}
