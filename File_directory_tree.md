# lib 目錄結構

```
lib/
├── main.dart
│
├── models/
│   ├── batch.dart
│   ├── export_result.dart
│   ├── input_mode.dart
│   ├── scan_item.dart
│   ├── scan_status.dart
│   └── timezone_config.dart
│
├── pages/
│   ├── batch_import_page.dart
│   ├── batch_list_page.dart
│   ├── batch_scan_page.dart
│   ├── settings_page.dart
│   └── total_shipment_scan_page.dart
│
├── services/
│   ├── app_settings_service.dart
│   ├── cleanup_service.dart
│   ├── database_service.dart
│   ├── export_service.dart
│   ├── google_sheets_service.dart
│   ├── ntp_service.dart
│   ├── scan_service.dart
│   ├── share_service.dart
│   ├── store_url_service.dart
│   └── timezone_service.dart
│
├── theme/
│   └── app_theme.dart
│
└── utils/
    ├── date_parser.dart
    ├── scan_status_helper.dart
    └── timezone_helper.dart
```

## 說明

### 根目錄
- `main.dart` - 應用程式入口點

### models/ - 資料模型
- `batch.dart` - 批次資料模型
- `export_result.dart` - 匯出結果模型
- `input_mode.dart` - 輸入模式列舉
- `scan_item.dart` - 掃描項目模型
- `scan_status.dart` - 掃描狀態列舉
- `timezone_config.dart` - 時區設定模型

### pages/ - 頁面元件
- `batch_import_page.dart` - 批次匯入頁面
- `batch_list_page.dart` - 批次列表頁面（主頁）
- `batch_scan_page.dart` - 批次掃描頁面
- `settings_page.dart` - 設定頁面
- `total_shipment_scan_page.dart` - 總出貨掃描頁面

### services/ - 服務層
- `app_settings_service.dart` - 應用程式設定服務
- `cleanup_service.dart` - 資料清理服務
- `database_service.dart` - 資料庫服務
- `export_service.dart` - 匯出服務
- `google_sheets_service.dart` - Google Sheets 服務
- `ntp_service.dart` - NTP 時間同步服務
- `scan_service.dart` - 掃描服務
- `share_service.dart` - 分享服務
- `store_url_service.dart` - 來源 URL 服務（來源名稱可自由設定，如分店、供應商等）
- `timezone_service.dart` - 時區服務

### theme/ - 主題設定
- `app_theme.dart` - 應用程式主題定義（淺色/深色）

### utils/ - 工具函數
- `date_parser.dart` - 日期解析工具
- `scan_status_helper.dart` - 掃描狀態輔助函數
- `timezone_helper.dart` - 時區輔助函數

