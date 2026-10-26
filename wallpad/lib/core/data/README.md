# 데이터 계층

SQLite. 앱 안에서 직접 연다. 별도 서버 없음.

## 사용법

앱 시작 시 한 번 연다.

```dart
final database = AppDatabase()..open();
final repo = SqliteRepository(database);
```

이후 repo만 부르면 된다.

```dart
final members = await repo.fetchMembers();
final items = await repo.fetchChecklistItems(memberId: 1, situationId: 1);

await repo.deleteMember(1);   // 딸린 행도 같이 지워진다
await repo.deleteItem(1);
```

## DB 파일 위치

`$HOME/leaveguard.db`. 보드에서 `$HOME`은 플랫폼이 앱에 주는 `/data/profiles/0/appdata/<앱ID>/home/`.
파일이 없으면 만들고 스키마를 적용한다. 시드(`situation` · `items`)는 이미 있으면 건너뛴다.

## 테이블

| 테이블 | 내용 |
|---|---|
| `members` | 사용자 |
| `face_embeddings` | 얼굴 임베딩. 사람당 한 행, `front`/`left`/`right` 컬럼에 float32 128개 |
| `situation` | 외출 목적 |
| `situation_rule` | 상황 추정 규칙 (요일·시간). 비어 있음 |
| `items` | 트레이에서 객체탐지로 확인하는 물건 |
| `member_checklist_items` | 사용자·상황별 챙길 물건 |
| `belongings` · `belonging_owners` | 사람이 등록한 소지품과 주인 (여러 명이면 공용) |
| `belonging_views` | 소지품 사진 특징. 물건당 최대 6장 |
| `belonging_questions` · `belonging_rejects` | 확인 질문과 "아니에요" 한 모습 |
| `belonging_presence` | 물건이 트레이에 있던 구간 |
| `belonging_acks` | [알고 있어요] 답 |
| `member_events` | 출발 · 귀가 시각 |
| `member_day_items` | 하루 기록 (체크 · 두고 온 것 · 메모) |
| `member_profile` · `member_essentials` | 온보딩 생활 패턴 · 꼭 챙길 것 |

## 얼굴 인식 연결

서비스가 보낸 임베딩을 그대로 넣고, 인식 때는 같은 벡터로 찾는다.

```dart
await repo.saveEmbedding(memberId: 2, pose: 'front', embedding: vec);   // 등록 (front/left/right)
final me = await repo.findMemberByEmbedding(vec);             // 인식 (코사인 ≥ 0.363)
```
