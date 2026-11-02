# NotesPlus

Apple 메모를 iCloud로 연결해 네이티브 편집기에서 쓰고, 행간과 입력 규칙을 조절하는 macOS 앱입니다.

**0.8.0-beta.1 · Apple Silicon · macOS 26 이상 · Developer ID 서명 및 Apple 공증 없음**

[0.8 베타 DMG](https://github.com/Recrude/NotesPlus/releases/download/v0.8.0-beta.1/NotesPlus-0.8.0-beta.1-macOS-arm64.dmg) · [릴리스 및 체크섬](https://github.com/Recrude/NotesPlus/releases/tag/v0.8.0-beta.1) · [0.7 안정 버전](https://github.com/Recrude/NotesPlus/releases/tag/v0.7.0)

## 설치

기존 NotesPlus를 종료한 뒤 DMG의 앱을 Applications 폴더로 옮겨 교체합니다. 기존 설정과 로컬 초안은 삭제하지 않습니다. 0.8의 첫 연결은 앱의 Apple 로그인 페이지에서 직접 완료합니다. 비밀번호를 NotesPlus 자체 입력창으로 받지 않습니다.

미확인 개발자 경고가 나오면 앱을 한 번 실행한 후 **시스템 설정 → 개인정보 보호 및 보안 → NotesPlus의 ‘그래도 열기’**에서 확인합니다. 시스템 전체 보안 설정이나 SIP를 변경할 필요는 없습니다. [Apple의 앱 열기 안내](https://support.apple.com/ko-kr/102445)

설치·연결·보안 경고·이전 초안에 대한 자세한 설명은 DMG에 포함된 [READ-ME.txt](Release/READ-ME.txt)를 확인하세요.

## 0.8 베타

- 기존 개인 iCloud 폴더와 메모를 읽고, 본문·체크리스트·글머리·번호 목록을 편집합니다.
- 실제 표를 만들고 셀과 행·열을 편집합니다. 체크 상태와 표 구조가 Apple 메모에 반영됩니다.
- 입력과 저장을 분리합니다. 한글 조합 보호, 문서 읽기 묶음 처리, 메모별 저장 상태, 전체 초안 복원을 포함합니다.
- 저장 전 원본 구조를 로컬에 백업하고, 그 버전과 일치할 때만 업로드합니다. 일시적인 버전 경쟁은 재시도하고 실제 동시 편집 충돌은 양쪽 버전을 보관합니다.
- 기존 설정창, 기본 행간 1.6, 기호별 목록 자동화, 타임스탬프와 생성일 정렬을 통합했습니다.

⌃⌘T로 타임스탬프를 삽입합니다. 기본 형식은 `yyyy/MM/dd HH:mm`이며 설정에서 형식과 단축키를 바꿀 수 있습니다. `1.` / `1)` 자동 목록과 `*` / `-` / `+` 자동 목록은 각각 설정합니다. 기본값은 번호만 자동 변환합니다.

글꼴·크기·행간·여백은 NotesPlus의 표시 설정입니다. iPhone의 표시 설정을 바꾸지 않습니다.

## 보존 범위와 한계

이 연결은 Apple이 공개한 Notes API가 아니며, Apple의 비공개 문서 형식에 의존합니다. 모든 메모 유형과 미래 OS 버전의 호환성을 보장하지 않습니다.

잠금·공유·이미지/스캔 첨부·대용량 자산 본문, 표현할 수 없는 색상/강조/사용자 서체, 표 셀 안의 복합 서식은 편집하지 않습니다. 읽기 전용 화면은 텍스트 미리보기입니다. Gmail·나의 Mac 계정과 다른 사람이 공유한 별도 영역은 현재 대상이 아닙니다.

표 전체의 이동·삭제, 표 셀의 인라인 서식 변경은 미지원입니다. 표 구조 변경은 먼저 현재 입력이 저장된 뒤 실행합니다. 서로 다른 구조를 동시에 변경하면 저장을 거부하고 전체 초안을 유지할 수 있습니다.

초안·원본 백업·충돌 사본은 `~/Library/Application Support/NotesPlus/Structured/`에 사용자 전용 파일 권한으로 저장합니다. 별도 암호화·자동 정리는 없습니다. 0.7과 실험판의 초안을 자동으로 변환하거나 업로드하지 않으며 기존 보관 위치에 유지합니다.

## 업데이트

설정 하단과 앱 정보에서 버전·빌드를 확인합니다. **NotesPlus → 업데이트 확인…**으로 다음 베타를 설치하며 앱만 교체하므로 삭제 후 재설치할 필요가 없습니다.

0.7 안정 채널에는 베타를 자동으로 배포하지 않습니다. 첫 베타 설치는 DMG로 교체하고, 이후 베타는 별도로 서명된 베타 업데이트 피드를 사용합니다. 업데이트 파일과 피드의 Ed25519 검증은 Apple 공증과 별개입니다.

## 개발

```sh
cd CloudBridge
npm ci --ignore-scripts
cd ..
bash Tools/test-structured.sh
bash build.sh
bash package.sh
```

`NOTESPLUS_APP_PATH`로 빌드 앱 경로를 지정할 수 있습니다. 기본 산출물은 상위 `outputs/`입니다. Node 22.23.4 arm64와 Sparkle 2.10.1 공식 배포물을 고정 SHA-256으로 검증해 번들에 포함합니다. 앱의 네트워크 연결은 Apple iCloud와 GitHub의 업데이트 배포 경로를 사용합니다.

새 편집기와 연결 코드는 `Sources/Structured/`, `CloudBridge/src/`에 있습니다. 이전 HTML 자동화 구현은 회귀·참조용 소스로 남아 있지만 0.8 앱에 컴파일되지 않습니다.

[검증 기록](BETA-VALIDATION.md) · [앞선 구조 동기화 실험](STRUCTURED-EXPERIMENT.md)

필요한 wire codec/CRDT 코드는 [icloud-md](https://github.com/coddingtonbear/icloud-md)의 MIT 라이선스 소스를 고정 커밋으로 포함합니다. 변경 내역은 [UPSTREAM.md](CloudBridge/vendor/icloud-md/UPSTREAM.md)에 기록합니다. Node·Sparkle·의존성 라이선스는 앱에 포함됩니다.
