# McBopomofo 小麥注音 LLM 實驗分支

本專案是從 [OpenVanilla McBopomofo](https://github.com/openvanilla/McBopomofo) fork
出來的獨立實驗分支，主要用來開發與測試以雲端 LLM 改善同音選字的功能。本專案並非
OpenVanilla 官方發行版本，LLM 功能與此分支所產生的問題也不由 OpenVanilla 維護。

## 下載測試版

不想自行編譯的使用者，可以前往本專案的
[GitHub Releases](https://github.com/plutocyw/McBopomofo/releases) 下載安裝程式。

目前提供的
[LLM Edit-action Reranking 測試版](https://github.com/plutocyw/McBopomofo/releases/tag/llm-edit-reranking-test-2026-07-26)
有以下限制：

- 僅支援 Apple Silicon（arm64）。
- 這是 Debug、ad-hoc signed 且尚未經 Apple notarization 的測試版本。
- 第一次執行時，可能需要右鍵選擇「打開」，或到「系統設定 → 隱私權與安全性」允許執行。
- LLM 功能需要使用者自行設定 provider、model 與 API key；安裝檔不包含任何 API key。

## 系統需求

此分支目前以 macOS 12.0 以上版本為執行目標。如果您要自行編譯此分支，或參與開發，您需要：

- macOS 26 或更高版本
- Xcode 26 或更高版本
- Python 3.9 (使用 Xcode 安裝後內附的就可以，也可使用 homebrew 等方式安裝)

## 開發流程

用 Xcode 開啟 `McBopomofo.xcodeproj`，選 "McBopomofo Installer" target，build 完之後直接執行該安裝程式，就可以安裝小麥注音。

第一次安裝完，日後程式碼或詞庫有任何修改，只要重複上述流程，再次安裝小麥注音即可。

要注意的是 macOS 可能會限制同一次 login session 能 kill 同一個輸入法 process 的次數（安裝程式透過 kill input method process 來讓新版的輸入法生效）。如果安裝若干次後，發現程式修改的結果並沒有出現，或甚至輸入法已無法再選用，只要登出目前帳號再重新登入即可。

## 這個分支和原版的差異

此分支加入了「雲端 LLM 輸入緩衝校正」功能，目標是降低同音選字錯誤，並盡量不打斷原本輸入節奏。

目前行為重點：

- 預設模式使用 LLM 校正整段 compose buffer。
- 實驗性的 edit-action reranking 會讓 LLM 從輸入法產生的候選句中選擇，再將結果套回輸入緩衝；此功能預設關閉。
- 目前不會使用 LLM 重新排列使用者看到的候選字清單。
- 輸入進行中不會每鍵觸發；會在使用者停頓一段時間後才呼叫。
- 使用者進入方向鍵選字等手動修正流程時，會暫停自動校正；回到句尾繼續輸入後再恢復。

## 如何使用 LLM 功能

1. 從 [GitHub Releases](https://github.com/plutocyw/McBopomofo/releases) 下載測試版，或自行 build 並安裝輸入法（建議使用 `McBopomofoInstaller` target）。
2. 在輸入法偏好設定 `Advanced` 頁籤開啟：
   - `Use Cloud LLM Buffer Correction`
3. 取得免費的 Google Gemini API Key：
   - 開啟 [Google AI Studio API Keys](https://aistudio.google.com/apikey)，並登入 Google 帳號。
   - 選擇既有專案或建立新專案，再按下建立 API key。
   - 複製產生的金鑰，貼到偏好設定的 `Google API Key` 欄位。也可以直接按欄位右側的
     `Get Free API Key` 按鈕開啟申請頁面。
   - Gemini API Free Tier 不需要綁定付款方式，但有每分鐘與每日用量限制；實際額度請在
     [Google AI Studio](https://aistudio.google.com/) 查看。
   - Google 可能使用 Free Tier 的輸入與輸出改善其產品。輸入內容可能包含私人資訊時，
     請先閱讀 [Gemini API 資料使用說明](https://ai.google.dev/gemini-api/terms)；
     需要付費服務的資料處理條款時，請改用已啟用計費的專案。
4. 先套用推薦設定（可作為大多數使用者的起始值）：
   - `Cloud Provider`: `Google`
   - `Thinking Level`: `Off`
   - `Google API Key`: 你的 Google API Key
   - `Cloud Endpoint`: `https://generativelanguage.googleapis.com/v1beta`
   - `Cloud Model`: `gemini-3.6-flash`
   - `LLM Trigger Mode`: `Continuous`
   - `LLM Pause Before Trigger (ms)`: `600`
   - `LLM Timeout (ms)`: `2500`
   - `Show LLM Activity Indicator`: `Off`
   - `Show LLM Debug Alert (Prompt/Response)`: `Off`
   - `Use Cloud LLM Buffer Correction`: `On`

5. 如需改用 OpenAI：
   - `Cloud Provider`: `OpenAI`
   - `OpenAI API Key`: 你的 OpenAI API Key
   - `Cloud Endpoint` 與 `Cloud Model` 可依需求調整。

補充：

- `Google API Key` 欄位右側提供 `Get Free API Key` 與 `Show/Hide` 按鈕，方便申請及檢查
  金鑰。
- Google 的 `Cloud Endpoint` 與 `Cloud Model` 提供下拉預設值，並可按 `Custom` 輸入自訂值。
- 如需觀察實際請求與回應，可開啟 `Show LLM Debug Alert (Prompt/Response)`。
- 如需快速確認是否有觸發，可開啟 `Show LLM Activity Indicator`。
- 如需測試候選句重新排序，可開啟 `Use Edit-Action Reranking (Experimental)`；此選項仍屬實驗功能，預設關閉。

## 問題回報與社群公約

歡迎使用者回報此分支的問題與提供建議。請將問題回報到
[plutocyw/McBopomofo Issues](https://github.com/plutocyw/McBopomofo/issues)。

請不要將 LLM 功能、此分支的安裝程式，或其他僅在此 fork 發生的問題回報到
`openvanilla/McBopomofo`。只有在問題也能於未修改的上游官方版本重現時，才適合依照
上游專案的規範向 OpenVanilla 回報。

參與此 fork 的討論與開發時，請遵守
[Contributor Covenant](https://www.contributor-covenant.org/zh-tw/version/1/4/code-of-conduct/)。

## 軟體授權

本專案沿用上游的 MIT License，使用者可自由使用及散播本軟體，惟散播時必須完整保留
版權聲明及軟體授權（[詳全文](LICENSE.txt)）。
