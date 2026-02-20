# OpenVanilla McBopomofo 小麥注音輸入法

## 系統需求

小麥注音輸入法可以在 macOS 10.15 以上版本運作。如果您要自行編譯小麥注音輸入法，或參與開發，您需要：

- macOS 14.7 以上版本
- Xcode 15.3 以上版本
- Python 3.9 (可使用 Xcode 安裝後內附的，或是使用 homebrew 等方式安裝)

## 開發流程

用 Xcode 開啟 `McBopomofo.xcodeproj`，選 "McBopomofo Installer" target，build 完之後直接執行該安裝程式，就可以安裝小麥注音。

第一次安裝完，日後程式碼或詞庫有任何修改，只要重複上述流程，再次安裝小麥注音即可。

要注意的是 macOS 可能會限制同一次 login session 能 kill 同一個輸入法 process 的次數（安裝程式透過 kill input method process 來讓新版的輸入法生效）。如果安裝若干次後，發現程式修改的結果並沒有出現，或甚至輸入法已無法再選用，只要登出目前帳號再重新登入即可。

## 這個分支和原版的差異

此分支加入了「雲端 LLM 輸入緩衝校正」功能，目標是降低同音選字錯誤，並盡量不打斷原本輸入節奏。

目前行為重點：

- LLM 主要用於「整段 compose buffer 校正」，不是候選清單排序。
- 輸入進行中不會每鍵觸發；會在使用者停頓一段時間後才呼叫。
- 使用者進入方向鍵選字等手動修正流程時，會暫停自動校正；回到句尾繼續輸入後再恢復。

## 如何使用 LLM 功能

1. Build 並安裝輸入法（建議用 `McBopomofoInstaller` target）。
2. 在輸入法偏好設定 `Advanced` 頁籤開啟：
   - `Use Cloud LLM Buffer Correction`
3. 取得 Google API Key：
   - 可參考 Google 官方說明：[Get an API key](https://support.google.com/googleapi/answer/6158862?hl=en)
4. 先套用推薦設定（可作為大多數使用者的起始值）：
   - `Thinking Level`: `Off`
   - `Google API Key`: 你的 Google API Key
   - `Cloud Endpoint`: `https://generativelanguage.googleapis.com/v1beta`
   - `Cloud Model`: `gemini-3-flash-preview`
   - `LLM Trigger Mode`: `Continuous`
   - `LLM Pause Before Trigger (ms)`: `600`
   - `LLM Timeout (ms)`: `2500`
   - `Show LLM Activity Indicator`: `Off`
   - `Show LLM Debug Alert (Prompt/Response)`: `Off`
   - `Use Cloud LLM Buffer Correction`: `On`

補充：

- `Google API Key` 欄位右側提供 `Show/Hide` 按鈕，方便檢查輸入是否正確。
- 如需觀察實際請求與回應，可開啟 `Show LLM Debug Alert (Prompt/Response)`。
- 如需快速確認是否有觸發，可開啟 `Show LLM Activity Indicator`。

## 社群公約

歡迎小麥注音用戶回報問題與指教，也歡迎大家參與小麥注音開發。

首先，請參考我們在「[常見問題](https://github.com/openvanilla/McBopomofo/wiki/常見問題)」中所提「[我可以怎麼參與小麥注音？](https://github.com/openvanilla/McBopomofo/wiki/常見問題#我可以怎麼參與小麥注音)」一節的說明。

我們採用了 GitHub 的[通用社群公約](https://github.com/openvanilla/McBopomofo/blob/master/CODE_OF_CONDUCT.md)。公約的中文版請參考[這裡的翻譯](https://www.contributor-covenant.org/zh-tw/version/1/4/code-of-conduct/)。

## 軟體授權

本專案採用 MIT License 釋出，使用者可自由使用、散播本軟體，惟散播時必須完整保留版權聲明及軟體授權（[詳全文](https://github.com/openvanilla/McBopomofo/blob/master/LICENSE.txt)）。
