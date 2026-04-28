---
name: Cleanup temp files
description: Always clean up temporary files/folders after use — don't leave them behind
type: feedback
---

임시 파일/폴더를 만든 뒤 반드시 정리할 것.

**Why:** 사용자가 직접 확인하기 전까지 1.2GB+ 임시 파일이 /tmp에 남아 있었음. 디스크 낭비.

**How to apply:** curl/unzip 등으로 /tmp에 파일을 만들 때, 작업 완료 직후 rm으로 정리. 다운로드 → 설치 → 정리를 하나의 흐름으로 처리.
