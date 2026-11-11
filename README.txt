PowerAutomateDesktop_動作 說明
=================================
產生日期：2026-11-10　PAD 版本：2.64.00104.26012

結構
  動作\<模組>\<分類>\<動作名稱>\<動作名稱>.txt
  每個 txt 只有可直接貼進 PAD 設計工具（Ctrl+V）的 Robin 代碼，沒有額外註解。
  有多種模式的動作（例如「啟動 Excel」）每種模式各一行（以空行分隔），只複製需要的那一行。
  `` 代表需要自己填的值：文字用 $'''內容''' 包起來，變數直接寫變數名稱。
  流程\ 是寫好的完整流程，整段貼上即可：
    - 台銀匯率存成Excel.txt：用「從網頁擷取資料」，含錯誤處理與執行記錄
    - 台銀匯率爬取\台銀匯率爬取.txt：用「在網頁上執行 JavaScript」，已確認可貼上

內容
  - 模組 DLL 自動擷取的動作：422 個（含 Excel、瀏覽器自動化、UI 自動化、檔案、文字、變數…）
  - Robin 內建語法（IF、LOOP、SET、WAIT…）：放在「條件」「迴圈」「流程控制」「變數\設定變數」
  - 動作總表.csv：所有動作的一覽表，可以用 Excel 開啟搜尋
  - 你原本手建的 3 個資料表動作保持不動

不包含
  - 雲端連接器動作（SharePoint、Outlook 365 等），它們的定義在雲端，不在本機。
    需要時在 PAD 拖一個進流程、Ctrl+C 複製出來，再照這個結構自己存一份即可。

貼上規則（2026-11-10 實測）
  - 只要有一行 PAD 解析不了，整段都不會貼上，而且不會顯示任何錯誤。
    遇到這種情況，把代碼分段貼上，找出是哪一行出問題。
  - $'''...''' 文字裡避免使用：單引號 '、< 、> 、|| 、%
      %  會被當成變數，例如 %DesktopPath%；真的要用時才寫
      \  要寫成 \\，例如 $'''%DesktopPath%\\檔名.xlsx'''
      "  可以用，照 PAD 自己的寫法寫成 \" 最保險
  - 在 JavaScript 裡：字串一律用雙引號；用 forEach 取代 for (i < n) 迴圈；
    用 if (!x) { x = ... } 取代 x || y；換行用 String.fromCharCode(10)，不要寫 \n。
  - 已在本機 PAD 確認可貼上的語法：
      # 註解、SET x TO ...、LOOP i FROM 1 TO 15 STEP 1、WAIT 2、
      IF x <> $'''''' THEN ... END、EXIT LOOP、EXIT Code: 0
  - 單獨貼上一段時，變數尚未定義而出現紅色錯誤是正常的，整段流程貼完就會消失。

實測校正（2026-11-11）
  - 拿「流程」資料夾裡能執行的流程比對動作庫，修正了以下問題：
      如果… 類動作（如果檔案已存在、如果網頁包含、如果影像、如果視窗…）要寫成
        IF (WebAutomation.IfWebPageContains.WebPageContainsElement ...) THEN
        END
      等待… 類動作（等待網頁內容、等候檔案、等待處理序、等待視窗…）要寫成
        WAIT (WebAutomation.WaitForWebPageContent.WebPageToContainElement ...) FOR 10
      原本動作名稱多了 Action（例如 IfWebPageContainsAction、WaitProcessAction），貼上會變成未知動作，已改掉。
      取代文字：只保留實測可用的 Text.Replace.ReplaceTextWithRegex（一般文字也能用，不是特殊符號就不用跳脫）。
      修剪文字、填補文字、顯示訊息：補上 Text、PaddingText、Title、Message 參數。
  - 要確認動作庫是否還有對不上的地方：執行 _工具\比對實測動作.ps1，
    會列出「流程」資料夾實際用到、但動作庫找不到或參數不同的寫法，並存成 _工具\比對結果.csv。
  - 動作名稱以實際能執行的流程為準；參數名稱和選項可以參考動作庫。
  - 有些參數是選填的，動作庫裡不會列出（例如 MatchMode、CommandLineArguments），需要時自行加上。

更新
  PAD 更新後執行 _工具\更新動作清單.ps1，只會新增缺少的動作，不會覆寫既有檔案。