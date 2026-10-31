# NotesPlus

Mac 기본 메모와 연결하면서 글꼴, 한글 행간, 입력 동작을 조절할 수 있는 macOS 앱입니다.

**Apple Silicon · macOS 26 이상 · Developer ID 서명 및 Apple 공증 없음**

[DMG 다운로드](https://github.com/Recrude/NotesPlus/releases/download/v0.6.0/NotesPlus-0.6.0-macOS-arm64.dmg) · [릴리스 및 체크섬](https://github.com/Recrude/NotesPlus/releases/tag/v0.6.0)

## 설치

1. DMG를 열고 `NotesPlus.app`을 `Applications` 폴더로 옮깁니다.
2. 응용 프로그램 폴더에서 NotesPlus를 실행합니다.
3. 첫 연결 때 기본 메모에 대한 자동화 권한을 허용합니다. iCloud 메모는 Mac 기본 메모에서 먼저 연결되어 있어야 합니다.

기존 버전을 사용 중이라면 앱을 종료하고 교체합니다. 기존 메모와 설정은 유지됩니다.

### 첫 실행 보안 경고

현재 버전은 Apple 공증을 받지 않았습니다. 이 저장소의 Releases에서 내려받은 파일인지 확인하세요.

개발자를 확인할 수 없거나 Apple이 악성 소프트웨어를 확인할 수 없다는 경고가 나오면, 앱을 한 번 실행한 뒤 **시스템 설정 → 개인정보 보호 및 보안 → NotesPlus의 ‘그래도 열기’ → ‘열기’**를 선택합니다. 요청되면 Mac 암호 또는 Touch ID로 확인합니다. 이후에는 평소처럼 실행할 수 있습니다. [Apple 공식 안내](https://support.apple.com/ko-kr/102445)

‘컴퓨터를 손상시킵니다’ 또는 ‘앱이 손상되었습니다’라는 경고는 별도로 확인해야 합니다. 다시 다운로드하고 릴리스의 SHA-256 값을 확인하거나 [Issues](https://github.com/Recrude/NotesPlus/issues)에 알려 주세요. [상세 설치 안내](Release/READ-ME.txt)

## 기능

- 글꼴·크기·행간·자간·문단 간격·본문 여백 설정. 기본 행간은 1.6배입니다.
- 입력과 저장 분리: 입력이 멈춘 뒤 기본 1.2초, 연속 입력 중 약 8초마다 자동 저장합니다.
- `1. `로 실제 번호 목록을 시작하고 Return으로 이어 작성합니다. `* `는 문자 그대로 남깁니다.
- `⌘⌃T`로 현재 커서 위치에 타임스탬프를 삽입합니다. 형식과 단축키를 설정에서 바꿀 수 있습니다.
- 날짜 형식 `yyyy/MM/dd HH:mm`, `yyyyMMdd HHmmss` 등을 지원합니다.
- 생성일 기준 최신 메모 먼저 정렬합니다. 수정일 또는 제목으로 바꿀 수도 있습니다.
- Mac 기본 메모에 도착한 새 메모와 변경 사항을 기본 3초 간격으로 확인합니다.

`⌘,`로 설정을 엽니다. 전체 옵션은 [SETTINGS.txt](SETTINGS.txt)를 참고하세요.

## 메모와 동기화

NotesPlus는 공개 Apple Events / Scripting Bridge로 Mac 기본 메모를 읽고 저장합니다. 기기 간 iCloud 동기화는 Apple 메모가 처리합니다. 별도 Apple 계정 암호를 받거나 별도 클라우드 저장소를 만들지 않습니다.

번호 목록을 iPhone 기본 메모에서 이어 작성하고, 그 내용이 NotesPlus로 돌아오는 것을 확인했습니다. 글꼴·행간 설정은 이 Mac의 NotesPlus에만 적용됩니다.

일반 텍스트, 단순 제목, 지원되는 번호 목록을 편집합니다. **글머리·체크리스트, 복잡한 서식, 표·첨부, 공유·잠긴 메모는 읽기 전용**입니다. 두 기기의 동시 수정은 자동 병합하지 않고 충돌을 알리며 초안을 보관합니다.

로컬 초안과 백업은 `~/Library/Application Support/NotesPlus/`에 보관합니다. 별도 암호화나 자동 정리 기능은 없습니다. Apple Notes의 모든 기능을 제공하는 앱은 아니며 Apple의 공식 제품이 아닙니다.

## 빌드 및 패키징

Apple Silicon Mac과 macOS 26 SDK가 포함된 Xcode Command Line Tools가 필요합니다.

```sh
bash build.sh
bash package.sh
```

앱과 배포 파일은 저장소의 상위 디렉터리 `outputs/`에 생성됩니다. 기본 빌드는 로컬 ad-hoc 서명을 사용하며 Developer ID 인증서나 공증 자격 증명이 필요하지 않습니다. 서식·저장·입력·설정 관련 107개 검사를 포함합니다.

[배포 절차](Release/DISTRIBUTION.txt) · [개발 기록](README.txt)
