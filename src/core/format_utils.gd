## FormatUtils — 숫자 포맷 공유 유틸리티 (static).
## class_name 등록으로 autoload 없이 프로젝트 전역 접근 가능.
## TD-04 (God Object 분리) 이전 임시 단일 소스 — trading_screen.gd,
## chart_renderer.gd, portfolio_view.gd, league_screen.gd 중복 제거.
class_name FormatUtils


## 정수를 쉼표 구분 문자열로 반환. 음수 지원.
## 예) 1234567 → "1,234,567"
static func number(value: int) -> String:
	var s: String = str(absi(value))
	var result: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	if value < 0:
		result = "-" + result
	return result


## 부동소수점 수익률을 부호 포함 퍼센트 문자열로 반환 (소수 1자리).
## 예) 12.3 → "+12.3%", -5.0 → "-5.0%"
static func pct(value: float) -> String:
	var sign_str: String = "+" if value >= 0.0 else ""
	return "%s%.1f%%" % [sign_str, value]
