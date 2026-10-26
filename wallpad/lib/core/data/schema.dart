const String createSchemaSql = '''
-- pin_hash · pin_salt : PIN 해시 (숫자는 저장하지 않는다). 아직 안 정했으면 NULL
-- return_check : 귀가 소지품 확인 창 (1 띄움 · 0 안 띄움)
-- onboarding   : 1 = 온보딩 중인 임시 멤버. 앱을 켤 때 남아 있으면 지운다
CREATE TABLE IF NOT EXISTS members (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT    NOT NULL,
    pin_hash      TEXT,
    pin_salt      TEXT,
    return_check  INTEGER NOT NULL DEFAULT 1,
    onboarding    INTEGER NOT NULL DEFAULT 0
);

-- 얼굴 임베딩 : 사람당 한 행, 방향마다 컬럼 (float32 128개 = 512바이트, 미등록은 NULL)
CREATE TABLE IF NOT EXISTS face_embeddings (
    member_id   INTEGER PRIMARY KEY REFERENCES members(id) ON DELETE CASCADE,
    front       BLOB,
    left        BLOB,
    right       BLOB
);

-- 상황 : 외출 목적
CREATE TABLE IF NOT EXISTS situation (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    name  TEXT    NOT NULL UNIQUE
);

-- 상황 판단 규칙 : 외출 목적을 추정하는 요일·시간 조건
CREATE TABLE IF NOT EXISTS situation_rule (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id     INTEGER NOT NULL REFERENCES members(id)   ON DELETE CASCADE,
    situation_id  INTEGER NOT NULL REFERENCES situation(id) ON DELETE CASCADE,
    day_of_week   INTEGER CHECK (day_of_week BETWEEN 0 AND 6),
    start_time    TEXT,
    end_time      TEXT
);

CREATE INDEX IF NOT EXISTS idx_rule_member ON situation_rule(member_id);

-- 물건 : 트레이에 올려두고 객체탐지로 확인하는 물건
CREATE TABLE IF NOT EXISTS items (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    label         TEXT    NOT NULL UNIQUE,
    display_name  TEXT    NOT NULL
);

-- 사용자별 상황에 챙겨야 할 물건
CREATE TABLE IF NOT EXISTS member_checklist_items (
    member_id     INTEGER NOT NULL REFERENCES members(id)   ON DELETE CASCADE,
    situation_id  INTEGER NOT NULL REFERENCES situation(id) ON DELETE CASCADE,
    item_id       INTEGER NOT NULL REFERENCES items(id)     ON DELETE CASCADE,
    PRIMARY KEY (member_id, situation_id, item_id)
);

-- 소지품 : 트레이 카메라로 알아보는 사람별 물건 (items 와는 별개)
-- thumbnail : 등록할 때 잘라 둔 JPEG. hard_to_detect : 자동 박스가 못 잡아 직접 그려 등록했다
CREATE TABLE IF NOT EXISTS belongings (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id       INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    name            TEXT    NOT NULL,
    thumbnail       BLOB,
    hard_to_detect  INTEGER NOT NULL DEFAULT 0,
    watch_box       TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- 소지품 사진의 특징 : 사진마다 한 행, 물건당 최대 6장 (등록 1 + 확인 5).
-- source : register(등록 화면) · redbox(빨간 박스) · confirm(확인 질문에 "맞아요") · turn(등록 사진을 90 · 180 · 270 도 돌린 것, 6장에 안 셈).
--          space_id 가 다른 특징끼리는 비교하지 않는다
CREATE TABLE IF NOT EXISTS belonging_views (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    belonging_id  INTEGER NOT NULL REFERENCES belongings(id) ON DELETE CASCADE,
    space_id      TEXT    NOT NULL,
    vector        BLOB    NOT NULL,
    source        TEXT    NOT NULL DEFAULT 'register',
    created_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- 확인 질문 : 점수가 애매하게 나온 트레이 물건. 물건마다 기다리는 질문은 하나
-- status : pending · yes · no
CREATE TABLE IF NOT EXISTS belonging_questions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    belonging_id  INTEGER NOT NULL REFERENCES belongings(id) ON DELETE CASCADE,
    space_id      TEXT    NOT NULL,
    vector        BLOB    NOT NULL,
    crop          BLOB,
    score         REAL    NOT NULL,
    seen_at       TEXT    NOT NULL,
    status        TEXT    NOT NULL DEFAULT 'pending',
    answered_at   TEXT
);

-- "아니에요" 라고 한 모습 : 이것과 아주 비슷하면(0.9 이상) 같은 물건으로 다시 묻지 않는다
CREATE TABLE IF NOT EXISTS belonging_rejects (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    belonging_id  INTEGER NOT NULL REFERENCES belongings(id) ON DELETE CASCADE,
    space_id      TEXT    NOT NULL,
    vector        BLOB    NOT NULL,
    created_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_belonging_member ON belongings(member_id);
CREATE INDEX IF NOT EXISTS idx_view_belonging ON belonging_views(belonging_id);
CREATE INDEX IF NOT EXISTS idx_question_belonging ON belonging_questions(belonging_id);
CREATE INDEX IF NOT EXISTS idx_reject_belonging ON belonging_rejects(belonging_id);

-- 소지품 주인. 여러 명이면 공용. belongings.member_id 는 첫 주인
CREATE TABLE IF NOT EXISTS belonging_owners (
    belonging_id  INTEGER NOT NULL REFERENCES belongings(id) ON DELETE CASCADE,
    member_id     INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    PRIMARY KEY (belonging_id, member_id)
);

-- 물건이 트레이에 있던 구간. 보이는 중이면 seen_until 이 NULL
-- closed_by : left(트레이에서 사라짐) · offline(카메라 끊김) · restart(앱 재시작) — "챙김" 은 left 로 닫힌 구간만 뜻한다
-- taken_by  : 사라진 순간 월패드 앞에 있던 사람 (얼굴로 들어온 사람). 아무도 없었으면 NULL
CREATE TABLE IF NOT EXISTS belonging_presence (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    belonging_id  INTEGER NOT NULL REFERENCES belongings(id) ON DELETE CASCADE,
    seen_from     TEXT    NOT NULL,
    seen_until    TEXT,
    closed_by     TEXT    CHECK (closed_by IN ('left', 'offline', 'restart')),
    taken_by      INTEGER REFERENCES members(id) ON DELETE SET NULL
);

-- 사람의 출발·귀가 시각. 마지막 귀가가 "어제부터 없었어요" 판정의 기준점이다
CREATE TABLE IF NOT EXISTS member_events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id  INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    kind       TEXT    NOT NULL CHECK (kind IN ('departed', 'returned')),
    at         TEXT    NOT NULL
);

-- 사람별 하루 기록. 앱이 다시 떠도 오늘 체크 · 두고 온 소지품 · 내일 메모가 남는다
-- kind : checked(오늘 챙길 것 항목 id) · left_out(소지품 id) · note(메모 id, name 에 글)
-- day  : 'YYYY-MM-DD'. 이틀 지난 행은 앱을 켤 때 지운다
CREATE TABLE IF NOT EXISTS member_day_items (
    member_id  INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    day        TEXT    NOT NULL,
    kind       TEXT    NOT NULL CHECK (kind IN ('checked', 'left_out', 'note')),
    item_key   TEXT    NOT NULL,
    name       TEXT,
    at         TEXT    NOT NULL,
    PRIMARY KEY (member_id, day, kind, item_key)
);

-- 사람의 답 [알고 있어요]. 물건마다 사람마다 (공용 물건은 주인마다 따로 답한다). 그 사람이 귀가하면 지운다
CREATE TABLE IF NOT EXISTS belonging_acks (
    belonging_id  INTEGER NOT NULL REFERENCES belongings(id) ON DELETE CASCADE,
    member_id     INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    at            TEXT    NOT NULL,
    PRIMARY KEY (belonging_id, member_id)
);

CREATE INDEX IF NOT EXISTS idx_presence_belonging ON belonging_presence(belonging_id, seen_from);
CREATE INDEX IF NOT EXISTS idx_member_event ON member_events(member_id, kind, at);

-- 온보딩 생활 패턴 : 사람당 한 행. 답하지 않은 항목은 NULL
-- weekday_place : work · school · home · flexible · custom
-- schedule_mode : fixed(정해진 시각) · calendar(캘린더 첫 일정 기준) · manual(나갈 때마다 확인) · both · none(통근 없음)
-- leave_time · return_time : 'HH:MM'.  days : 요일 비트 (월=1, 화=2, … 일=64).  remind_before : 출발 몇 분 전부터 체크리스트
-- transport : car · transit · walk · varies.  weekend : rest · out · varies
CREATE TABLE IF NOT EXISTS member_profile (
    member_id      INTEGER PRIMARY KEY REFERENCES members(id) ON DELETE CASCADE,
    weekday_place  TEXT,
    schedule_mode  TEXT,
    leave_time     TEXT,
    return_time    TEXT,
    days           INTEGER,
    remind_before  INTEGER,
    transport      TEXT,
    weekend        TEXT,
    updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 사람이 손으로 확인할 "꼭 챙길 것" (휴대폰 · 교통카드 …). 트레이 소지품은 belongings 로 따로 확인한다
CREATE TABLE IF NOT EXISTS member_essentials (
    member_id  INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    name       TEXT    NOT NULL,
    PRIMARY KEY (member_id, name)
);

-- 외출 전 점검 항목 (전기장판 · 고데기 · 현관문 · 가스밸브 …). 센서가 있는 가전은 전력 노드가 확인한다
CREATE TABLE IF NOT EXISTS member_checks (
    member_id  INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    name       TEXT    NOT NULL,
    PRIMARY KEY (member_id, name)
);
''';

const String seedSql = '''
INSERT OR IGNORE INTO situation (name) VALUES ('출근'), ('외출');

INSERT OR IGNORE INTO items (label, display_name) VALUES
    ('car_key', '차키'),
    ('wallet',  '지갑');
''';
