## 공유 UIState enum — TradingScreen과 StatusBar가 동일한 상태 머신을 참조한다.
## 각 파일에서 `const UIState = UIStateTypes.UIState` 로 앨리어싱.
## GDD: design/gdd/settings-screen.md (TD-CR-11)
class_name UIStateTypes

enum UIState {
	LOADING,
	PRE_MARKET,
	MARKET_OPEN,
	PAUSED,
	SETTLEMENT,
	SEASON_RESULT,
}
