# 出貨掃描比對系統

一個 **公司內部使用的出貨掃描比對 App**，  
用於掃描物流單號並比對應出貨清單，支援離線使用與結果匯出。

---

## 📌 專案定位

- **類型**：內部工具 / 出貨掃描系統
- **使用對象**：公司內部人員（倉儲、出貨作業）
- **平台**：Android / iOS
- **安裝方式**：內部 APK 安裝

---

## 🧱 系統架構

```text
[ Google Sheet（公開連結） ]
    ↓ 匯入
[ Flutter App（SQLite 本地儲存） ]
    ↓ 掃描物流單號
[ 本地比對邏輯（Batch 管理） ]
    ↓ 比對結果
[ 顯示狀態 / 匯出 TXT/JSON ]
    ↓ 分享
[ Line / Google Drive / 其他應用 ]
```

### 核心特性

- ✅ **本地儲存**：使用 SQLite 儲存訂單資料，支援離線使用
- ✅ **Batch 管理**：依來源名稱和訂單日期分組管理（來源可自由設定，如分店、供應商等）
- ✅ **狀態追蹤**：PENDING → SCANNED → DUPLICATE / INVALID
- ✅ **自動清理**：App 啟動時自動清理 7 天前的已完成批次
- ✅ **匯出檔案自動清理**：App 啟動時自動清理超過 10 天的匯出檔案
- ✅ **網路狀態檢查**：App 啟動時自動檢查網路連線，無網路時顯示警告
- ✅ **結果匯出**：支援 TXT（人可讀）和 JSON（機器可用）格式
- ✅ **中斷恢復**：App 被殺掉後可恢復掃描狀態
- ✅ **總出貨模式**：支援跨多個來源同時掃描
- ✅ **多種輸入方式**：掃描槍、相機、手動輸入
- ✅ **即時狀態顯示**：掃描後即時顯示狀態訊息
- ✅ **掃描人員資料**：可設定掃描人員資訊，包含在匯出檔案中
- ✅ **批次更新**：支援單店或全店批次更新資料
- ✅ **NTP 時間同步**：從國際標準時間伺服器同步時間
- ✅ **非清單內出貨紀錄**：總出貨模式支援記錄非清單內的蝦皮物流條碼（15字元，開頭"TW"）
- ✅ **相機掃描重複判斷間隔**：可設定 5-60 秒，在時間內重複掃描不算重複

---

---

## 📱 主要功能

### 1. Google Sheet 匯入
- 從公開的 Google Sheet 匯入應出貨清單
- 欄位順序固定：`分店名稱,訂單日期,訂單編號,物流公司,物流單號,備註`
- 自動產生 Batch ID：`{store_name}_{order_date}`
- 支援跨日掃描（今天掃描昨天或前天的訂單）
- **日期限制**：系統會自動過濾超過7天的訂單資料，不會匯入過時的訂單（超過7天的資料會被跳過，計入跳過筆數）

**重要說明**：
- Google Sheets 可同時包含數個過去日期尚未完成出貨的訂單資料
- 系統於匯入時，會依據訂單日期自動分批管理（每個 `{store_name}_{order_date}` 為一個 Batch）
- Google Sheets 視為**最近數日的待處理工作清單**，而非歷史最終依據
- **實際出貨結果以掃描完成後產生之匯出報告為準**
- 匯出報告（TXT/JSON）才是最終的出貨記錄，包含實際掃描時間、狀態等資訊

### 2. 物流單號掃描與比對
- **三種輸入模式**：
  - **掃描槍模式**：自動聚焦，掃描後自動送出
    - 掃描槍輸入後自動檢測並提交（300ms 延遲，無需按回车）
    - 每次掃描都會自動輸入並處理
  - **相機模式**：使用相機掃描條碼
    - 相機初始化帶有錯誤處理和重試機制，確保穩定運行
    - 狀態顯示欄位位於列表上方，不遮擋掃描區域
  - **手動輸入模式**：手動輸入物流單號，點擊「送出」按鈕
    - 輸入框會監聽文字變化，自動啟用送出按鈕
- 掃描物流單號進行比對
- 狀態轉換邏輯：
  - `PENDING` → `SCANNED`（首次掃描成功）
  - `SCANNED` → `DUPLICATE`（重複掃描）
  - 查無資料 → `INVALID`（不在清單內）
- 即時狀態顯示：輸入欄位下方即時顯示掃描狀態（成功、重複、無此資料等）
- 掃描成功提示：可設定震動和聲音（逼聲）提示
- 備註功能：可為掃描項目新增或編輯備註
- 訂單日期顯示：每個掃描項目會顯示訂單日期（小字）

### INVALID（不在清單）掃描資料的處理方式

當掃描的物流單號在該 Batch 的 `scan_items` 表中查無資料時，系統產生 `INVALID` 狀態，處理方式如下：

- **SQLite 寫入**：`INVALID` 狀態的掃描記錄**不會寫入** `scan_items` 表
- **資料持久化**：`INVALID` 僅存在於記憶體中，作為 `ScanService.scanLogisticsNo()` 的返回值，不會持久化到資料庫
- **匯出資料來源**：匯出 TXT / JSON 時，`INVALID` 統計數字為 0，因為匯出資料來自 `DatabaseService.getScanItemsByBatch()`，該方法僅查詢 `scan_items` 表中的記錄
- **設計理由**：
  - `scan_items` 表僅儲存從 Google Sheet 匯入的「預期出貨清單」
  - `INVALID` 代表「不在預期清單內」的掃描，屬於異常情況，不應與正常清單混雜
  - 避免 `scan_items` 表因誤掃而膨脹，保持資料庫結構清晰
  - 若需記錄 `INVALID` 掃描歷史，應在 UI 層或日誌層處理，而非資料庫層

**實作細節**：`ScanService.scanLogisticsNo()` 在查無資料時直接返回 `ScanResult(status: ScanStatus.invalid)`，不呼叫 `DatabaseService.updateScanItem()`。匯出服務中的 `invalid` 統計僅用於程式碼完整性，實際執行時應為 0。

### 3. 結果匯出與分享
- **三種匯出格式**：
  - **LINE 版本**：簡潔格式（寬度20字符），不列出掃描成功清單，只顯示結果摘要和錯誤/瑕疵清單，適合直接貼到 LINE
  - **TXT 版本**：完整格式（寬度40字符），包含所有詳細資訊，適合文件分享
  - **JSON 版本**：機器可讀格式，適合程式處理和留存
- 匯出檔案包含掃描人員資訊（姓名和ID）
- 可選擇複製 LINE 版本、複製 TXT 內容、分享 TXT 或 JSON 檔案
- 分享到 LINE 時，文件會正確附加（不會顯示為文本）
- 可重新匯出已完成批次
- 透過系統分享選單分享到 Line、Google Drive 等
- 匯出後標記 Batch 為已完成（仍可查看和重新匯出）

### 4. 資料管理
- 支援多個 Batch 同時存在
- 顯示每個 Batch 的掃描進度
- 已完成批次保留在列表中（變灰顯示），可查看和刪除
- 支援批次刪除功能（長按已完成批次可刪除）
- 支援單筆或批次刪除掃描項目
- 自動清理 7 天前的已完成批次
- 支援批次更新：可更新單一來源或所有來源的最新資料
- URL 記憶功能：可儲存來源對應的 Google Sheet URL（來源名稱可自由設定），方便快速匯入

### 5. 總出貨模式
- 支援跨多個來源同時掃描
- 適合倉庫人員一次處理多個來源的訂單
- 掃描時自動在所有未完成的 Batch 中查找
- 顯示掃描結果時標示所屬來源
- 可一次匯出所有 Batch 的結果
- **非清單內出貨紀錄模式**：
  - 在總出貨掃描頁面右上角提供開關按鈕
  - 啟用後，如果掃描的條碼不在出貨清單內，且符合蝦皮物流格式（15字元，開頭"TW"），會自動記錄到資料庫
  - 目前支援蝦皮物流格式：15字元，開頭"TW"
  - 例如：`TW254833743744Z`、`TW251087895529U`、`TW2557292761802`

### 6. 系統設定
- **時區資訊**：固定為 UTC+8 (Asia/Taipei)，僅顯示不可編輯
  - 系統內部使用 UTC 時間儲存（標準時間）
  - 前端顯示與匯出資料均轉換為 UTC+8 (Asia/Taipei)，並於欄位或檔名標示時區
- **顯示模式**：可選擇自動（建議）、深色（高對比）、淺色（室內）
- **掃描人員資料**：可設定掃描人員姓名和編號/ID
  - 此資訊會包含在匯出的 TXT 和 JSON 檔案中
- **掃描設定**：
  - 狀態顯示時間：可設定 0-5 秒
  - 掃描成功震動：開關控制
  - 掃描成功聲音（逼聲）：開關控制
  - 相機掃描重複判斷間隔：可設定 5-60 秒（預設 10 秒）
    - 在設定時間內重複掃描不算重複，超過時間間隔後再次掃描才算重複
- **NTP 時間同步**：系統時間從國際標準時間伺服器同步
- **設定介面**：右上角齒輪圖示，點擊後顯示半頁設定面板
- **自動更新機制**：
  - 匯入或更新批次後，批次列表自動刷新（無需手動下拉更新）
  - 設定更改後立即生效（顯示模式無需重啟 App）

---

## 🛠 技術架構

### 技術選型

- **Flutter**：跨平台 UI 框架
- **SQLite (sqflite)**：本地資料庫
- **path_provider**：系統 Documents 目錄存取
- **share_plus**：檔案分享功能
- **http**：Google Sheets CSV 下載
- **intl**：日期時間格式化
- **path**：路徑處理
- **mobile_scanner**：相機條碼掃描
- **vibration**：震動回饋
- **audioplayers**：聲音播放
- **ntp**：NTP 時間同步
- **shared_preferences**：設定儲存
- **package_info_plus**：應用程式資訊
- **connectivity_plus**：網路狀態檢查

### 資料庫結構（SQLite）

#### batches 表

- `id` (TEXT, PK): batch_id = {store_name}_{order_date}
- `store_name` (TEXT): 來源名稱（可自由設定，如分店、供應商等）
- `order_date` (TEXT): 訂單日期 (YYYY-MM-DD)
- `created_at` (TEXT): 建立時間 (ISO 8601)
- `finished_at` (TEXT, nullable): 完成時間（匯出後，ISO 8601）

#### scan_items 表

- `id` (INTEGER, PK, AUTOINCREMENT): 自動遞增
- `batch_id` (TEXT, FK): 批次 ID
- `order_date` (TEXT): 訂單日期
- `order_no` (TEXT): 訂單編號
- `logistics_company` (TEXT, nullable): 物流公司
- `logistics_no` (TEXT): 物流單號（掃描唯一 Key）
- `sheet_note` (TEXT, nullable): Google Sheet 備註
- `scan_status` (TEXT): 掃描狀態（PENDING/SCANNED/DUPLICATE/INVALID）
- `scan_time` (TEXT, nullable): 掃描時間 (ISO 8601)
- `scan_note` (TEXT, nullable): 使用者手動備註
- UNIQUE(batch_id, logistics_no)

#### off_list_records 表（非清單內記錄）

- `id` (INTEGER, PK, AUTOINCREMENT): 自動遞增
- `logistics_no` (TEXT, UNIQUE): 物流單號（蝦皮物流格式）
- `scan_time` (TEXT): 掃描時間 (ISO 8601)
- `created_at` (TEXT): 建立時間 (ISO 8601)

#### 索引

- `idx_batch_id`: scan_items(batch_id)
- `idx_logistics_no`: scan_items(logistics_no)
- `idx_order_date`: batches(order_date)
- `idx_off_list_logistics_no`: off_list_records(logistics_no)
- `idx_off_list_scan_time`: off_list_records(scan_time)

### 檔案系統結構

```text
<App Documents Directory>/
├── db/
│   └── scan_app.db                    # SQLite 資料庫
└── reports/
    └── store={store_name}/
        └── order_date={order_date}/
            ├── scan_result_{store_name}_{yyyyMMdd_HHmm}.txt
            └── scan_result_{store_name}_{yyyyMMdd_HHmm}.json
```

### 資料流程

#### 匯入流程

```text
Google Sheet (公開連結)
  ↓
GoogleSheetsService.importFromSheet()
  ↓
解析 CSV（取得 store_name, order_date）
  ↓
產生 batch_id = {store_name}_{order_date}
  ↓
建立 Batch 記錄
  ↓
批量插入 ScanItem（狀態 = PENDING）
```

#### 掃描流程

```text
使用者掃描物流單號
  ↓
ScanService.scanLogisticsNo(batch_id, logistics_no)
  ↓
查詢 SQLite (batch_id + logistics_no)
  ↓
狀態轉換：
  - PENDING → SCANNED（寫入 scan_time）
  - SCANNED → DUPLICATE
  - 查無資料 → INVALID
  ↓
更新 ScanItem
```

#### 匯出流程

```text
使用者點擊「匯出結果」
  ↓
ExportService.exportBatch(batch_id)
  ↓
讀取 Batch 所有 ScanItem
  ↓
產生 TXT 和 JSON 檔案
  ↓
寫入 reports 目錄
  ↓
標記 Batch 為 finished（寫入 finished_at）
  ↓
ShareService.shareFiles() 分享檔案
```

#### 清理流程

```text
App 啟動時
  ↓
CleanupService.cleanupOldBatches()
  ↓
查詢：order_date < today - 7 days AND finished_at IS NOT NULL
  ↓
刪除相關 scan_items
  ↓
刪除 batches
  ↓
CleanupService.cleanupOldExportFiles()
  ↓
檢查匯出檔案修改時間
  ↓
刪除超過 10 天的匯出檔案
  ↓
清理空目錄
```

---

## 📁 專案結構

```text
lib/
├── main.dart                          # App 入口（啟動時執行 7 天清理）
├── models/
│   ├── batch.dart                    # Batch 模型
│   ├── export_result.dart            # 匯出結果模型
│   ├── input_mode.dart               # 輸入模式枚舉
│   ├── scan_item.dart                # 掃描項目模型
│   ├── scan_status.dart              # 掃描狀態枚舉
│   └── timezone_config.dart          # 時區設定模型
├── pages/
│   ├── batch_import_page.dart        # Batch 匯入頁面
│   ├── batch_list_page.dart          # Batch 列表頁面（主頁）
│   ├── batch_scan_page.dart          # Batch 掃描頁面
│   ├── settings_page.dart             # 設定頁面
│   └── total_shipment_scan_page.dart # 總出貨掃描頁面
├── services/
│   ├── app_settings_service.dart     # 應用程式設定服務
│   ├── cleanup_service.dart          # 清理服務（7 天清理批次，10 天清理檔案）
│   ├── database_service.dart         # SQLite 資料庫服務
│   ├── export_service.dart           # 匯出服務（TXT/JSON）
│   ├── google_sheets_service.dart    # Google Sheets 匯入服務
│   ├── network_service.dart          # 網路狀態檢查服務
│   ├── ntp_service.dart              # NTP 時間同步服務
│   ├── scan_service.dart             # 掃描比對服務
│   ├── share_service.dart            # 分享服務
│   ├── store_url_service.dart        # 來源 URL 服務
│   └── timezone_service.dart         # 時區服務
├── theme/
│   └── app_theme.dart                # App 主題設定（淺色/深色）
└── utils/
    ├── date_parser.dart              # 日期解析工具
    ├── scan_status_helper.dart       # ScanStatus 輔助函數
    └── timezone_helper.dart          # 時區輔助函數
```

**注意**：`lib/l10n` 文件夹已移除，系统仅支持繁体中文。

---

## 🚀 快速開始

### 1. 準備 Google Sheet

建立一個 Google Sheet，欄位順序固定（第一行為標題）：

**欄位順序**：`分店名稱,訂單日期,訂單編號,物流公司,物流單號,備註`

| 分店名稱   | 訂單日期   | 訂單編號 | 物流公司   | 物流單號 | 備註 |
| ---------- | ---------- | -------- | ---------- | -------- | ---- |
| 台北一店   | 2025-12-22 | ORD001   | 黑貓       | SHIP001  |      |
| 供應商A    | 2025-12-22 | ORD002   | 新竹物流   | SHIP002  | 急件 |

**注意事項**：
- 分店名稱、物流公司、備註為非必填（可空白）
- 分店名稱可自由設定（如分店、供應商、或其他任何名稱）
- 訂單日期支援多種格式（會自動正規化為 `YYYY-MM-DD`）：
  - `YYYY-MM-DD`（例如：2025-12-22）
  - `YYYY/MM/DD`（例如：2025/12/22）
  - `MM/DD/YYYY`（例如：12/22/2025）
  - `DD/MM/YYYY`（例如：22/12/2025）
  - `YYYY年MM月DD日`（例如：2025年12月22日）
  - Google Sheets Date 型別（會自動轉換）
  - 其他常見日期格式
- 訂單編號和物流單號為必填
- 設定 Sheet 為「知道連結的使用者都可以查看」

### 2. 匯入批次

1. 打開 App
2. 點擊右上角「+」按鈕
3. 貼上 Google Sheet 公開連結
4. 點擊「匯入資料」
5. 等待匯入完成

### 3. 開始掃描

1. 在 Batch 列表選擇要掃描的批次（或點擊「總出貨」進行跨來源掃描）
2. 進入掃描頁面
3. 選擇輸入模式：
   - **掃描槍模式**：自動聚焦，掃描後自動送出
     - 掃描槍輸入後自動檢測並提交（300ms 延遲，無需按回车）
     - 每次掃描都會自動輸入並處理
   - **相機模式**：使用相機掃描條碼
     - 相機初始化帶有錯誤處理和重試機制，確保穩定運行
     - 狀態顯示欄位位於列表上方，不遮擋掃描區域
   - **手動輸入模式**：手動輸入物流單號，點擊「送出」按鈕
     - 輸入框會監聽文字變化，自動啟用送出按鈕
4. 掃描物流單號
5. 查看比對結果（輸入欄位下方即時顯示狀態）：
   - ✅ **成功**：首次掃描成功（綠色）
   - ⚠️ **重複**：重複掃描（橙色）
   - ❌ **無此資料**：不在清單內（紅色）
6. 可為掃描項目新增或編輯備註
7. 每個掃描項目會顯示訂單日期（小字）

### 4. 匯出結果

1. 掃描完成後，點擊頁尾「匯出」按鈕
2. 確認匯出（已完成批次可重新匯出）
3. 系統產生 TXT 和 JSON 檔案
4. 匯出成功後會顯示簡潔的對話框，包含簡化的提示資訊，可選擇：
   - **複製 LINE 版本**：複製簡潔格式到剪貼簿，適合直接貼到 LINE（寬度20字符，不列出掃描成功清單）
   - **複製 TXT 內容**：複製完整格式到剪貼簿
   - **分享 TXT**：分享 TXT 檔案（文件會正確附加到 LINE，不會顯示為文本）
   - **分享 JSON**：分享 JSON 檔案（用於程式處理）
5. 透過分享選單選擇目標應用（Line、Google Drive 等）
6. 已完成批次會保留在列表中（變灰顯示），可查看和重新匯出

---

## 📋 Google Sheet 格式規範

### 欄位順序（固定，第一行為標題）

欄位順序：`分店名稱,訂單日期,訂單編號,物流公司,物流單號,備註`

1. **分店名稱**（非必填）：例如「台北一店」、「供應商A」等（可自由設定）
2. **訂單日期**（必填）：支援多種格式，會自動正規化為 `YYYY-MM-DD`
3. **訂單編號**（必填）：例如 `ORD001`
4. **物流公司**（非必填）：例如「黑貓」、「新竹物流」
5. **物流單號**（必填）：掃描唯一 Key，例如 `SHIP001`
6. **備註**（非必填）：額外說明

### 訂單日期格式支援

系統會自動解析並正規化以下日期格式：

- `YYYY-MM-DD`（例如：2025-12-22）
- `YYYY/MM/DD`（例如：2025/12/22）
- `MM/DD/YYYY`（例如：12/22/2025）
- `DD/MM/YYYY`（例如：22/12/2025）
- `YYYY年MM月DD日`（例如：2025年12月22日）
- `YYYY.MM.DD`（例如：2025.12.22）
- Google Sheets Date 型別（自動轉換為日期）
- 其他常見日期格式

**注意**：所有日期在系統內部統一使用 `YYYY-MM-DD` 格式。

### 訂單日期正規化的錯誤處理策略

當訂單日期無法被成功解析為合法日期時，系統採用以下處理策略：

- **資料行處理**：該筆資料行會被跳過，不進行後續處理
- **SQLite 寫入**：不會寫入 `scan_items` 表
- **Batch 計數**：不會計入該 Batch 的資料筆數
- **使用者通知**：匯入完成後，成功訊息僅顯示成功匯入的筆數（例如：「匯入成功！共 95 筆資料」），不會單獨提示略過的筆數
- **錯誤原因**：日期解析失敗的原因包括：
  - 日期格式無法識別
  - 日期值超出合理範圍（例如：月份 > 12）
  - 日期值為空字串（已在必填欄位驗證階段處理）

**實作細節**：`GoogleSheetsService.importFromSheet()` 在解析每筆資料時，若 `DateParser.normalizeDate()` 拋出 `FormatException`，該筆資料會被 `continue` 跳過，不加入 `items` 列表。

### 範例

```csv
來源名稱,訂單日期,訂單編號,物流公司,物流單號,備註
台北一店,2025-12-22,ORD001,黑貓,SHIP001,
台北一店,2025/12/22,ORD002,新竹物流,SHIP002,急件
,12/23/2025,ORD003,,SHIP003,
```

---

## 🔄 Batch 系統說明

### Batch 定義

一個 Batch 代表：**來源名稱 + 訂單日期**

- **batch_id** 規則：`{store_name}_{order_date}`
- 例如：`台北一店_2025-12-22` 或 `供應商A_2025-12-22`
- 來源名稱可自由設定（如分店、供應商、或其他任何名稱）

### 支援跨日掃描

- 今天可以掃描昨天或前天的訂單
- 同一來源、不同訂單日期會分開管理
- 每個 Batch 獨立顯示進度

### 資料暫存規則

- SQLite 中的 Batch 僅保留 7 天
- 清理條件：`order_date < today - 7 days` 且 `finished_at IS NOT NULL`
- 清理時機：App 啟動時自動執行
- **匯出檔案保留規則**：
  - 預設保留天數：10 天
  - 超過保留天數的匯出檔案會自動刪除
  - 空目錄會自動清理
  - 清理時機：App 啟動時自動執行

### 同一 Batch 重新匯入的覆蓋策略

當對相同 `batch_id`（來源名稱 + 訂單日期）重新匯入 Google Sheet 時，系統採用以下策略：

- **已完成 Batch 限制**：若該 Batch 的 `finished_at` 欄位不為 NULL（已完成匯出），系統會拋出異常，不允許重新匯入
- **未完成 Batch 處理**：
  - `batches` 表：使用 `INSERT OR REPLACE` 策略，保留原記錄的 `id`，更新 `store_name`、`order_date`、`created_at` 欄位
  - `scan_items` 表：採用「部分覆蓋」策略：
    - 新匯入的 `scan_items` 使用 `INSERT OR REPLACE`（依據 `batch_id + logistics_no` 唯一約束）
    - 若新資料中的 `logistics_no` 已存在，則覆蓋該筆記錄（狀態重置為 `PENDING`）
    - 若新資料中的 `logistics_no` 不存在，則插入新記錄
    - **舊資料保留**：不在新匯入列表中的舊 `scan_items` 記錄不會被刪除，仍保留在資料庫中
- **狀態重置**：重新匯入時，所有新匯入或覆蓋的 `scan_items` 的 `scan_status` 會被重置為 `PENDING`，`scan_time` 和 `scan_note` 會被清空

**實作細節**：`DatabaseService.insertScanItems()` 使用 `ConflictAlgorithm.replace`，依據 `UNIQUE(batch_id, logistics_no)` 約束進行覆蓋判斷。此設計允許部分更新，避免因 Sheet 資料不完整而遺失已掃描的記錄。

---

## 🔨 Build & 安裝

### 開發環境執行

```bash
flutter pub get
flutter run
```

### 產生 APK

```bash
flutter build apk
```

產出位置：`build/app/outputs/flutter-apk/app-release.apk`

---

## 📊 輸出檔案規格

### 檔名規則

```text
scan_result_{store_name}_{yyyyMMdd_HHmm}.{ext}
```

例如：`scan_result_台北一店_20251224_1548.txt`

### TXT 格式（人可讀）

包含：
- 店名、訂單日期、掃描完成時間
- 統計摘要（總筆數、已掃描、未掃描、錯誤）
- **未掃描清單**（重點）
- 錯誤／重複明細
- 已掃描清單

### JSON 格式（機器可用）

```json
{
  "store_name": "台北一店",
  "order_date": "2025-12-22",
  "scan_finish_time": "2025-12-24T15:48:00Z",
  "summary": {
    "total": 100,
    "scanned": 95,
    "not_scanned": 3,
    "error": 2
  },
  "items": [
    {
      "order_no": "ORD001",
      "logistics_company": "黑貓",
      "logistics_no": "SHIP001",
      "scan_status": "SCANNED",
      "scan_time": "2025-12-24T10:30:00Z",
      "scan_note": null,
      "sheet_note": null
    }
  ]
}
```

---

## 🔒 資料安全

- 所有資料儲存在 App 本地（SQLite）
- 不連線到外部伺服器（除了下載 Google Sheets）
- 匯出檔案儲存在 App Documents 目錄（應用程式私有目錄）
- 支援離線使用（匯入後無需網路）
- **網路狀態檢查**：
  - App 啟動時自動檢查網路連線狀態
  - 如果沒有偵測到手機網路或 WiFi，會立即顯示警告對話框
  - 必須點擊「確認」按鈕才能繼續使用 App
  - 部分功能（如匯入 Google Sheets）需要網路連線

## ⏰ 時區管理

### 時區設定原則

- **系統內部**：使用 UTC 時間儲存（標準時間）
- **前端顯示**：固定為 UTC+8 (Asia/Taipei)，僅顯示不可編輯
- **匯出檔案**：所有匯出資料於輸出時轉換為 Asia/Taipei，並於欄位或檔名標示時區

### 時區資訊

- 時區固定為 UTC+8 (Asia/Taipei)，不可編輯
- 可在設定頁面查看時區資訊（唯讀）

### 時間格式說明

- **UTC 時間**：系統內部儲存的標準時間（例如：`2025-12-24T10:30:00Z`）
- **本地時間**：轉換為 UTC+8 (Asia/Taipei) 的時間（例如：`2025-12-24 18:30:00 (UTC+8 Asia/Taipei)`）
- **檔名時間戳記**：使用本地時間（例如：`scan_result_台北一店_20251224_1830.txt`）

---

## 🧭 開發原則

1. **本地優先**：所有資料和邏輯在本地執行
2. **離線可用**：匯入後無需網路即可使用
3. **中斷恢復**：App 被殺掉後可恢復掃描狀態
4. **資料可匯出**：支援多種格式匯出
5. **自動清理**：避免資料無限累積（批次 7 天，檔案 10 天）
6. **自動更新**：匯入後自動刷新列表，設定更改立即生效
7. **網路檢查**：啟動時檢查網路狀態，無網路時提醒用戶

---

## 🎨 使用者體驗設計

### UX 檢查點

根據目前的程式設計，系統已針對以下 UX 檢查點進行優化：

1. **打開 APP 是否 0.5 秒內可掃**
   - ✅ App 啟動時自動載入批次列表
   - ✅ 匯入後自動導航到掃描頁面
   - ✅ 掃描頁面輸入框自動聚焦（掃描槍模式）
   - ✅ 支援快速連續掃描

2. **不看文字只看顏色，能不能知道結果**
   - ✅ 即時狀態顯示使用顏色區分：
     - 🟢 **綠色**：成功（首次掃描成功）
     - 🟠 **橙色**：重複（重複掃描）
     - 🔴 **紅色**：無此資料（不在清單內）
   - ✅ 列表項目使用顏色標籤：
     - 待掃描：橙色標籤
     - 已掃描：綠色標籤
     - 錯誤：紅色標籤
   - ✅ 進度條顏色：綠色表示已完成

3. **戶外/倉庫光線下是否清楚**
   - ✅ 支援深色模式（高對比）：深色背景，適合戶外強光環境
   - ✅ 支援淺色模式（室內）：淺色背景，適合室內環境
   - ✅ 自動模式：跟隨系統設定
   - ✅ 按鈕和文字在深色模式下使用高對比顏色

4. **單手是否能完成 100% 操作**
   - ✅ 所有功能按鈕位於底部導航欄，方便單手操作
   - ✅ 掃描輸入框位於頁面中下方，易於單手輸入
   - ✅ 狀態顯示位於輸入框下方，無需滾動即可查看
   - ✅ 重要操作（匯入、匯出、總出貨）都在底部，單手可及

5. **新人 30 秒內是否會用**
   - ✅ 簡潔的介面設計：主頁直接顯示批次列表
   - ✅ 清晰的按鈕標籤：匯入、總出貨、批次更新
   - ✅ 即時狀態反饋：掃描後立即顯示結果
   - ✅ 自動導航：匯入後自動進入掃描頁面
   - ✅ 顏色視覺提示：無需閱讀文字即可理解狀態
   - ✅ 底部操作欄：所有主要功能集中於底部，易於發現

---

## 📝 備註

- 本專案為內部工具，重點在穩定、可維護、易於使用
- 支援離線使用，適合倉儲環境
- 匯出後 Batch 無法再修改，請確認後再匯出

---

## 🔄 版本資訊

### v1.0.0（開發中）

目前版本為 v1.0.0，尚未正式推出。

**主要功能**：
- ✅ **總出貨模式**：支援跨多個來源同時掃描，資訊顯示區域已優化（緊湊布局）
- ✅ **多種輸入方式**：掃描槍、相機、手動輸入
  - 掃描槍模式：自動檢測並提交（300ms 延遲，無需按回车）
  - 相機模式：穩定的初始化機制，帶錯誤處理和重試
  - 手動輸入模式：自動啟用送出按鈕
- ✅ **即時狀態顯示**：輸入欄位下方即時顯示掃描狀態
- ✅ **掃描人員資料**：可設定掃描人員資訊，包含在匯出檔案中
- ✅ **掃描成功提示**：震動和聲音（逼聲）提示，可開關
- ✅ **備註功能**：可為掃描項目新增或編輯備註
- ✅ **批次更新**：支援單一來源或所有來源批次更新資料
- ✅ **URL 記憶功能**：可儲存來源對應的 Google Sheet URL（來源名稱可自由設定）
- ✅ **已完成批次保留**：匯出後不會消失，可查看和重新匯出
- ✅ **非清單內出貨紀錄模式**：總出貨模式支援記錄非清單內的蝦皮物流條碼（15字元，開頭"TW"）
- ✅ **相機掃描重複判斷間隔**：可設定 5-60 秒（預設 10 秒），在時間內重複掃描不算重複，超過時間間隔後再次掃描才算重複
- ✅ **匯出對話框優化**：移除文件路徑顯示，精簡提示資訊，提供更簡潔的使用體驗
- ✅ **批次刪除功能**：可刪除已完成批次
- ✅ **分享功能增強**：可選擇分享 TXT 或 JSON
- ✅ **複製 TXT 內容**：可複製到剪貼簿
- ✅ **NTP 時間同步**：從國際標準時間伺服器同步時間
- ✅ **設定頁面**：完整的設定介面，包含個資、掃描設定、時區資訊、顯示模式等
- ✅ **匯入後自動導航**：匯入成功後自動進入掃描頁面
- ✅ **Batch 系統**：依來源名稱和訂單日期分組管理（來源名稱可自由設定）
- ✅ **SQLite 儲存**：使用 SQLite 本地資料庫儲存
- ✅ **支援跨日掃描**：可掃描不同日期的訂單
- ✅ **7 天自動清理機制**：自動清理舊資料
- ✅ **掃描狀態管理**：PENDING/SCANNED/DUPLICATE/INVALID
- ✅ **結果匯出功能**：支援 TXT 和 JSON 格式
- ✅ **分享功能**：支援分享到 Line、Google Drive 等
- ✅ **深色模式優化**：所有按鈕和 UI 元素適配深色模式，使用主題色
- ✅ **訂單日期顯示**：每個掃描項目顯示訂單日期（小字）
- ✅ **總出貨資訊簡化**：來源和日期顯示自動簡化，避免過長
- ✅ **單一語言**：僅支持繁體中文，已移除多語言支持
- ✅ **匯出對話框優化**：移除文件路徑顯示，精簡提示資訊，提供更簡潔的使用體驗
