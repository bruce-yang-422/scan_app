import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'pages/batch_list_page.dart';
import 'services/cleanup_service.dart';
import 'services/app_settings_service.dart';
import 'services/network_service.dart';
import 'utils/timezone_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 設定系統 UI 樣式
  try {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
      ),
    );
  } catch (e) {
    debugPrint('設定系統 UI 樣式時發生錯誤：$e');
  }

  // App 啟動時清理 7 天前的資料
  try {
    await CleanupService.cleanupOldBatches();
  } catch (e) {
    // 忽略清理錯誤，不影響 App 啟動
    debugPrint('清理舊資料時發生錯誤：$e');
  }

  // App 啟動時清理過期的匯出檔案
  try {
    final fileResult = await CleanupService.cleanupOldExportFiles();
    if (fileResult.deletedFiles > 0 || fileResult.deletedDirs > 0) {
      debugPrint('已清理過期匯出檔案：刪除 ${fileResult.deletedFiles} 個檔案，${fileResult.deletedDirs} 個目錄');
    }
  } catch (e) {
    // 忽略清理錯誤，不影響 App 啟動
    debugPrint('清理過期匯出檔案時發生錯誤：$e');
  }

  // App 啟動時檢查並清除非清單內記錄（每天00:00台灣時區自動清除）
  try {
    await CleanupService.cleanupOffListRecordsIfNeeded();
  } catch (e) {
    // 忽略清理錯誤，不影響 App 啟動
    debugPrint('清除非清單內記錄時發生錯誤：$e');
  }

  // 初始化時區設定
  try {
    await TimezoneHelper.initialize();
  } catch (e) {
    debugPrint('初始化時區設定時發生錯誤：$e');
    // 即使時區初始化失敗，也繼續啟動 App
  }

  // 確保 App 能夠啟動，即使初始化過程中有錯誤
  runApp(const ScanApp());
}

class ScanApp extends StatefulWidget {
  const ScanApp({super.key});

  @override
  State<ScanApp> createState() => _ScanAppState();
}

class _ScanAppState extends State<ScanApp> {
  // 預設主題模式：跟隨系統（ThemeMode.system）
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    try {
      final mode = await AppSettingsService.getThemeMode();
      if (mounted) {
        setState(() {
          switch (mode) {
            case 'dark':
              _themeMode = ThemeMode.dark;
              break;
            case 'light':
              _themeMode = ThemeMode.light;
              break;
            case 'auto':
            default:
              // 預設跟隨系統主題
              _themeMode = ThemeMode.system;
              break;
          }
        });
      }
    } catch (e) {
      debugPrint('載入主題模式時發生錯誤：$e');
      // 使用預設主題模式（跟隨系統）
    if (mounted) {
      setState(() {
          _themeMode = ThemeMode.system;
      });
      }
    }
  }

  // 公開方法供子頁面調用以更新主題
  void updateThemeMode() {
    _loadThemeMode();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '出貨核對系統',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: BatchListPage(
        onThemeModeChanged: updateThemeMode,
      ),
    );
  }
}
