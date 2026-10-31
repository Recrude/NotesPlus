NotesPlus 0.6 — 타임스탬프와 생성일 정렬

실행: ../outputs/NotesPlus.app
배포 파일: ../outputs/NotesPlus-0.6.0-macOS-arm64.dmg / .zip
대상: Apple Silicon / macOS 26 이상. 실제 연결 검증: macOS 26.5 / iPhone 12 mini.

0.6 변경 사항
- ⌘⌃T로 현재 커서 위치에 타임스탬프를 삽입합니다. 선택한 텍스트가 있으면 그 자리에 넣습니다.
- 기본 형식은 yyyy/MM/dd HH:mm이며, 설정 → 시간에서 형식과 단축키를 변경합니다.
- yyyyMMdd HHmmss 빠른 선택도 제공합니다. 날짜는 Gregorian 달력, 시간대는 현재 Mac을 따릅니다.
- 삽입한 문자열은 일반 입력처럼 자동 저장/동기화됩니다. 실행 취소/다시 실행을 지원하고 번호 목록 안에서도 목록 구조를 보존합니다.
- 읽기 전용 메모와 한글 조합 중에는 삽입하지 않습니다. 단축키는 NotesPlus의 메모 본문에서 사용합니다.
- 메모 정렬 기본값을 생성일 기준 최신 먼저로 변경했습니다. 수정할 때 기존 메모가 맨 위로 이동하지 않습니다.
- 이전 버전의 수정일 정렬은 이번 업데이트에서 생성일로 한 번 전환하며, 이후 사용자가 다시 고른 정렬은 유지합니다.
- 서식 23개 + 자동 저장/정렬 40개 + 설정/편집 44개 = 총 107개 검사 통과.
- 실제 앱에서 기본 단축키 및 ⌃⇧⌘Y로의 변경, 두 형식, 실행 취소/다시 실행, 기본 메모 저장을 확인했습니다.
- ZIP/DMG/체크섬/배포 상태 파일과 서명·공증 자동화 스크립트를 준비했습니다.
- 현재는 Developer ID 인증서와 Apple 공증 없이 GitHub Releases에 제공하는 ad-hoc 시험 빌드입니다.
- 첫 실행 보안 경고의 앱별 실행 허용 방법을 README.md와 DMG 내부 READ-ME.txt에 안내합니다.
배포 절차: Release/DISTRIBUTION.txt. 사용자 안내: Release/READ-ME.txt.

0.5 변경 사항
- 타이핑 때 문서 전체 서식을 다시 입히거나 메모 목록 전체를 갱신하던 경로를 제거했습니다.
- 입력 편집과 저장 작업을 분리했습니다. HTML 변환, 초안 및 백업 파일 쓰기는 백그라운드에서 처리합니다.
- 기본 저장 시점: 입력이 멈춘 뒤 1.2초. 계속 입력하면 미저장 변경을 약 8초마다 나누어 저장합니다.
- 저장 중에 입력한 내용은 다음 저장에 포함합니다. 메모/폴더 이동, 앱 비활성화, 창 닫기, 종료 때는 남은 변경을 저장합니다.
- 한글 조합 중에는 자동 저장과 목록 변환을 미룹니다. API 응답 시간과 조합 상태에 따라 저장 간격은 더 길어질 수 있습니다.
- 줄 시작에서 1. 또는 1) 뒤에 공백을 입력하면 실제 번호 목록으로 바뀝니다. Return으로 다음 번호가 이어집니다.
- 번호는 일반 텍스트가 아니라 NSTextList와 Notes의 ol/li 구조로 유지됩니다. 아이폰에서도 목록으로 이어 편집할 수 있습니다.
- 별표, 대시, 더하기 뒤 공백은 그대로 남습니다. 붙여넣은 텍스트는 자동으로 목록으로 바꾸지 않습니다.
- 빈 목록 항목에서 Return으로 목록을 끝낼 수 있으며 실행 취소/다시 실행도 목록 구조를 보존합니다.
- 현재 폴더의 새 메모와 변경 사항을 기본 3초 간격으로 확인합니다. 앱이 활성화될 때도 목록을 갱신합니다.
- 미리보기 조회는 순서대로 처리하고 편집/저장 중에는 미뤄 저장 요청과 경쟁하지 않게 했습니다.
- 기존 설정을 보존합니다. 새로 설치하거나 초기화했을 때의 저장 대기 기본값은 1.2초입니다.

글머리·체크리스트의 현재 제한
실제 기본 메모의 체크리스트를 공개 자동화 API로 읽으면 체크 상태 없는 ul/li로 반환됐습니다.
일반 글머리 목록과 확실하게 구별할 수 없어, 이 버전은 글머리·체크리스트가 있는 메모 전체를 읽기 전용으로 엽니다.
체크 상태 보존을 위해 해당 메모는 기본 앱에서 편집합니다. 관련 자동 변환 설정은 설명과 함께 비활성 상태입니다.
번호 목록은 구조를 구분할 수 있어 NotesPlus에서 직접 편집하고 저장합니다.

사용법과 설정
첫 연결 때 메모 자동화 권한이 필요합니다. 이후 실행 시 자동 연결합니다.
Command+N: 새로운 메모. Command+,: 상세 설정. 상단의 그룹 이름을 누르면 해당 위치로 이동합니다.
기본, 서체·여백, 목록, 입력, 시간, 화면, 저장의 옵션을 펼쳐 놓았으며 각 그룹 초기화와 JSON 내보내기/불러오기를 제공합니다.
글꼴·크기·행간·여백은 이 Mac의 NotesPlus 표시 설정입니다. iPhone의 표시 설정은 바뀌지 않습니다.
새 메모 첫 줄 서식과 실제 번호 목록 구조는 메모 내용이므로 iCloud로 함께 저장됩니다.
정상 저장 알림이나 별도 저장 버튼은 없습니다. 연결 실패와 충돌이 있을 때만 안내합니다.
아이콘은 설치된 기본 메모 원본의 노란 헤더만 #007AFF 계열로 치환했으며 앱 강조색과 맞췄습니다.
상세 옵션: SETTINGS.txt.

데이터 연결과 새 메모 불러오기
NotesPlus → Mac 기본 메모 → iCloud → iPhone 기본 메모.
Apple Events / Scripting Bridge를 사용합니다. SIP나 Notes 데이터베이스를 변경하지 않습니다.
Apple 계정 암호를 별도로 받거나 별도 iCloud 저장소를 만들지 않습니다.
Mac 기본 메모에서 생성한 메모도 같은 계정/폴더에서 자동으로 불러옵니다.
iPhone에서 생성한 메모는 iCloud를 통해 Mac 기본 메모에 도착한 뒤 조회됩니다.
조회 주기는 기본 3초이며 앱 활성화 때도 갱신합니다. 새 폴더 조회는 편집하지 않을 때 약 30초 간격입니다.
자동 저장 시점과 iCloud 서버의 전송 완료 시점은 다릅니다. iCloud 전송 완료를 보증하는 상태를 표시하지 않습니다.
오프라인이면 기기 간 반영은 원본 Notes와 iCloud가 연결된 뒤 진행됩니다.

현재 동일하지 않은 부분
이 버전은 Apple Notes의 모든 기능을 복제한 제품은 아닙니다.
- 일반 텍스트, 단순 제목, 지원되는 번호 목록을 편집합니다. 공유/잠금/첨부/표/복잡한 서식/글머리·체크리스트는 읽기 전용입니다.
- 서식, 체크리스트, 표, 첨부 도구는 해당 메모를 기본 앱에서 여는 동작입니다.
- 공유 버튼은 텍스트 사본 공유이며 iCloud 공동 편집 초대 기능이 아닙니다.
- 검색은 제목과 이미 불러온 미리보기를 대상으로 합니다. 전체 본문 검색은 아직 없습니다.
- 모든 계정 통합 목록, Quick Notes, 고정, 태그, 스마트 폴더, 삭제/이동, 협업 병합은 아직 구현하지 않았습니다.
- 두 기기의 동시 수정은 자동 병합하지 않고 원본이 바뀌면 저장을 중단하고 초안을 보관합니다.
- Notes 자동화 API에는 원자적 비교/저장이 없어 원본 확인과 쓰기 사이의 짧은 경쟁 가능성이 남습니다.
- 기본 계정(Siri), 나의 Mac 계정 활성화, 빠른 메모 재개, 완료 항목 정렬, 멘션 알림, 잠금 암호와 Touch ID는 기본 앱에서 관리합니다.
Apple 기본 설정 안내: https://support.apple.com/ko-kr/guide/notes/apd97da26aed/mac

초안과 백업
~/Library/Application Support/NotesPlus/
draft-*.json: 미저장 초안. 입력 중 묶어서 갱신하며 재시작 시 복원해 충돌이 없으면 자동 저장합니다.
Backups/*.json: 최초 저장 전 원본. 연속 편집 중에는 5분 간격으로 백업을 합칩니다.
recovered-*.json: 충돌 화면에서 원본을 불러올 때 별도로 보관한 초안.
폴더 0700 / 파일 0600. 로컬 사본에 별도 암호화나 자동 삭제/복원 UI는 없습니다.

0.5 검증 (2026-10-31)
- 서식/문서 변환 23개, 자동 저장/모델 39개, 설정/실제 NSTextView 29개: 총 91개 검사 통과.
- 56,003자 제목 포함 문서에서 100회 입력할 동안 문서 전체 서식 재적용 0회.
- 위 독립 NSTextView 검사에서 입력 처리 p95 약 0.149ms, 최대 약 1.019ms. 전체 화면 렌더링이나 실제 한글 입력기의 지연을 측정한 수치는 아닙니다.
- 구조화 목록 생성, Return 이어쓰기/종료, 실행 취소/다시 실행, 목록 형식만 변경한 경우의 저장을 검증했습니다.
- 연속 입력 중 주기적 저장, 저장 중 추가 입력, 동시에 들어온 종료/이동 저장 요청, 한글 조합 유예, 충돌 보호를 검사했습니다.
- 실제 NotesPlus에서 세 번째 항목을 추가하고 iPhone 기본 메모에서 확인했습니다.
- iPhone에서 Return을 누르자 네 번째 번호가 자동 생성됐으며, 입력한 NP-IOS-LIST-05가 NotesPlus로 돌아왔습니다.
- Notes가 돌려준 HTML에 두 개의 실제 ol 그룹과 여섯 개의 li 항목이 남고 별표 줄은 일반 div임을 확인했습니다.
- 기본 메모에서 만든 'NotesPlus 기본앱 생성 NP-NATIVE-05'가 NotesPlus에 표시되는 것을 확인했습니다.
- 체크리스트의 공개 API 출력에서 체크 상태를 구분할 수 없음을 확인하고 읽기 전용 보호를 적용했습니다.
- 실제 한글 IME 조합의 종단 간 성능은 아직 실기 측정하지 않았습니다.
상세 기록: build/smooth-list-verification.json, build/*-test-results.txt, build/native-list-probe.json.
이전 버전 기록: build/autosave-verification.json, build/iphone-sync-verification.json, build/icon-verification.json.

빌드
Command Line Tools가 설치된 Mac에서 bash build.sh
Sources/MainWindow.swift: 앱 수명 주기, 메인 화면
Sources/NotesPlusApp.swift, EditorSettings.swift: 설정창, 영속성/유효성/이관/내보내기/불러오기
Sources/NoteEditor.swift, RichTextBridge.swift: 네이티브 텍스트 편집기와 목록 구조
Sources/NoteDocument.swift, TextCodec.swift: 문서 모델과 HTML 변환/서식 판별
Sources/ListRules.swift: 입력 명령 판별
Sources/Timestamp.swift: 타임스탬프 형식과 단축키
package.sh: ZIP/DMG 패키징 및 선택적 Developer ID 서명/공증
Sources/Model.swift, DraftWriter.swift: 자동 저장, 초안/백업, 충돌 처리
Sources/NotesBackend.swift, NotesStore.m: 공개 Notes 연결
Tests/AutosaveTests.swift, CodecTests.swift, SettingsTests.swift: 검증 코드
아이콘 재생성: Tools/ExportNativeIcon.swift → Tools/RecolorIcon.py → Tools/PackIcon.py
최종 아이콘 원본: Resources/Icon/NotesPlus-blue-exact.png
Archive와 이전 NotesPatch/Bridge는 과거 실험 자료이며 현재 실행 앱에 포함하지 않습니다.

배포
GitHub Releases용 ad-hoc 서명 시험 빌드입니다. Developer ID 서명/공증/자동 업데이트 채널은 없습니다.
저장소: https://github.com/Recrude/NotesPlus
다운로드: https://github.com/Recrude/NotesPlus/releases/tag/v0.6.0
Apple의 공식 제품이 아닙니다.
