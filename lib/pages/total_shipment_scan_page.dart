import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/scan_item.dart';
import '../models/scan_status.dart';
import '../models/input_mode.dart';
import '../models/batch.dart' as models;
import '../services/scan_service.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/share_service.dart';
import '../services/app_settings_service.dart';
import '../utils/timezone_helper.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';

// 總出貨掃描頁面（跨多個 Batch）
class TotalShipmentScanPage extends StatefulWidget {
  const TotalShipmentScanPage({super.key});

  @override
  State<TotalShipmentScanPage> createState() => _TotalShipmentScanPageState();
}

class _TotalShipmentScanPageState extends State<TotalShipmentScanPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  MobileScannerController? _cameraController;
  
  List<ScanItem> _items = [];
  List<models.Batch> _batches = []; // 未完成的批次列表
  bool _isLoading = true;
  String? _lastScanMessage;
  ScanStatus? _lastScanStatus;
  String _currentStatusMessage = ''; // 當前狀態訊息（會在 build 時初始化）
  InputMode _inputMode = InputMode.scanner; // 預設為掃描槍模式
  bool _isScanning = false; // 相機掃描狀態
  Timer? _statusTimer; // 狀態顯示計時器
  final AudioPlayer _audioPlayer = AudioPlayer(); // 音效播放器
  Timer? _scannerInputTimer; // 掃描槍輸入計時器（用於自動提交）

  @override
  void initState() {
    super.initState();
    _loadItems();
    // 掃描槍模式：自動聚焦
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inputMode == InputMode.scanner) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 初始化狀態訊息
    if (_currentStatusMessage.isEmpty) {
      _currentStatusMessage = '待掃描/輸入';
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _scannerInputTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _stopCamera(); // 使用統一的停止方法
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
    });

    // 取得所有可掃描的 Batch（未完成的 + 最近 7 天內已完成的）
    // 這樣可以支援「今天漏掉一筆，明天補掃」的場景
    final batches = await DatabaseService.getScannableBatches();
    final allItems = <ScanItem>[];
    
    for (final batch in batches) {
      final items = await DatabaseService.getScanItemsByBatch(batch.id);
      allItems.addAll(items);
    }
    
    if (mounted) {
      setState(() {
        _batches = batches;
        _items = allItems;
        _isLoading = false;
      });
    }
  }
  
  // 取得統計資訊
  Map<String, dynamic> _getStatistics() {
    final total = _items.length;
    final scanned = _items.where((item) => item.scanStatus == ScanStatus.scanned).length;
    final pending = _items.where((item) => item.scanStatus == ScanStatus.pending).length;
    final duplicate = _items.where((item) => item.scanStatus == ScanStatus.duplicate).length;
    
    // 取得所有店家名稱（去重）
    final storeNames = <String>[];
    for (final batch in _batches) {
      if (batch.storeName != null && batch.storeName!.isNotEmpty) {
        storeNames.add(batch.storeName!);
      }
    }
    final uniqueStoreNames = storeNames.toSet().toList();
    
    // 取得所有訂單日期（去重並排序）
    final orderDates = <String>[];
    for (final batch in _batches) {
      if (batch.orderDate != null) {
        orderDates.add(batch.orderDate!);
      }
    }
    final uniqueOrderDates = orderDates.toSet().toList()..sort();
    
    return {
      'total': total,
      'scanned': scanned,
      'pending': pending,
      'duplicate': duplicate,
      'storeNames': uniqueStoreNames,
      'orderDates': uniqueOrderDates,
      'batchCount': _batches.length,
    };
  }

  Future<void> _onScan(String logisticsNo) async {
    if (logisticsNo.trim().isEmpty) {
      return;
    }

    // 防止重複掃描
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      // 使用跨 Batch 掃描
      final result = await ScanService.scanLogisticsNoAcrossBatches(
        logisticsNo.trim(),
      );

      // 取消之前的計時器（如果存在）- 快速連續掃描時立即切換狀態
      _statusTimer?.cancel();
      _statusTimer = null;

      // 更新狀態訊息
      String statusMessage;
      switch (result.status) {
        case ScanStatus.scanned:
          statusMessage = '成功';
          break;
        case ScanStatus.duplicate:
          statusMessage = '重複';
          break;
        case ScanStatus.invalid:
          statusMessage = '無此資料';
          break;
        case ScanStatus.pending:
          statusMessage = '待掃描/輸入';
          break;
      }

      // 取得分店資訊（如果有）
      String? storeName;
      if (result.item != null) {
        final batch = await DatabaseService.getBatch(result.item!.batchId);
        storeName = batch?.storeName;
      }

      // 立即更新狀態（快速連續掃描時直接切換）
      setState(() {
        _lastScanStatus = result.status;
        _lastScanMessage = storeName != null 
            ? '${result.message}（${storeName}）'
            : result.message;
        _currentStatusMessage = statusMessage;
      });

      // 重新載入資料
      await _loadItems();

      // 如果掃描成功，執行震動和聲音（如果啟用）
      if (result.status == ScanStatus.scanned) {
        final vibrationEnabled = await AppSettingsService.isVibrationEnabled();
        final soundEnabled = await AppSettingsService.isSoundEnabled();
        
        // 震動
        if (vibrationEnabled && await Vibration.hasVibrator() == true) {
          Vibration.vibrate(duration: 100);
        }
        
        // 聲音（逼聲）
        if (soundEnabled) {
          try {
            // 使用系統提示音（Android/iOS 都支援）
            await SystemSound.play(SystemSoundType.alert);
          } catch (e) {
            // 如果系統聲音不可用，忽略錯誤（不影響掃描功能）
            debugPrint('播放聲音失敗：$e');
          }
        }
      }

      // 根據輸入模式處理
      if (_inputMode == InputMode.scanner) {
        // 掃描槍模式：取消輸入計時器，清空輸入框並重新聚焦
        _scannerInputTimer?.cancel();
        _controller.clear();
        _focusNode.requestFocus();
      } else if (_inputMode == InputMode.camera) {
        // 相機模式：重新啟動相機
        _cameraController?.start();
      } else {
        // 手動輸入模式：清空輸入框
        _controller.clear();
      }

      // 取得狀態顯示時間設定（所有狀態共用）
      final statusDelaySeconds = await AppSettingsService.getStatusDelaySeconds();

      // 設定計時器，在指定時間後恢復為「待掃描/輸入」
      if (mounted) {
        _statusTimer = Timer(Duration(seconds: statusDelaySeconds), () {
          if (mounted) {
            setState(() {
              _currentStatusMessage = '待掃描/輸入';
              _lastScanStatus = null;
              _lastScanMessage = null;
            });
          }
        });
      }

      // 顯示訊息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_lastScanMessage ?? result.message),
            backgroundColor: result.status == ScanStatus.scanned
                ? Colors.green
                : result.status == ScanStatus.duplicate
                    ? Theme.of(context).colorScheme.primary
                    : Colors.red,
            duration: Duration(seconds: statusDelaySeconds),
          ),
        );
      }
    } catch (e) {
      // 取消之前的計時器
      _statusTimer?.cancel();
      _statusTimer = null;

      // 取得狀態顯示時間
      final statusDelaySeconds = await AppSettingsService.getStatusDelaySeconds();

      setState(() {
        _currentStatusMessage = '失敗';
        _lastScanStatus = null;
        _lastScanMessage = '掃描失敗：${e.toString()}';
      });

      // 設定計時器，在指定時間後恢復為「待掃描/輸入」
      if (mounted) {
        _statusTimer = Timer(Duration(seconds: statusDelaySeconds), () {
          if (mounted) {
            setState(() {
              _currentStatusMessage = '待掃描/輸入';
              _lastScanMessage = null;
            });
          }
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('掃描失敗：${e.toString()}'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.red[700]
                : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  // 切換輸入模式
  void _switchInputMode(InputMode mode) {
    setState(() {
      _inputMode = mode;
    });
    
    // 根據模式初始化（在 setState 外執行，避免在 setState 中執行異步操作）
    if (mode == InputMode.camera) {
      _initializeCamera();
    } else {
      // 停止並釋放相機
      _stopCamera();
      if (mode == InputMode.scanner) {
        // 掃描槍模式：自動聚焦
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      }
    }
  }

  // 初始化相機（帶錯誤處理和重試）
  Future<void> _initializeCamera() async {
    try {
      // 如果控制器已存在，先停止並釋放
      if (_cameraController != null) {
        try {
          await _cameraController!.stop();
        } catch (e) {
          // 忽略停止錯誤，繼續初始化
          debugPrint('停止相機時發生錯誤：$e');
        }
        await _cameraController!.dispose();
        _cameraController = null;
      }

      // 創建新的控制器
      _cameraController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );

      // 延遲啟動，確保 Widget 已構建完成
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (mounted && _inputMode == InputMode.camera) {
        await _cameraController!.start();
        // 更新狀態以觸發重建
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('初始化相機失敗：$e');
      // 重試一次
      if (mounted && _inputMode == InputMode.camera) {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          if (_cameraController != null) {
            await _cameraController!.dispose();
            _cameraController = null;
          }
          _cameraController = MobileScannerController(
            detectionSpeed: DetectionSpeed.noDuplicates,
            facing: CameraFacing.back,
          );
          await Future.delayed(const Duration(milliseconds: 100));
          if (mounted && _inputMode == InputMode.camera) {
            await _cameraController!.start();
            if (mounted) {
              setState(() {});
            }
          }
        } catch (e2) {
          debugPrint('相機重試失敗：$e2');
          if (mounted) {
            setState(() {
              // 保持狀態，但相機可能無法使用
            });
          }
        }
      }
    }
  }

  // 停止並釋放相機
  Future<void> _stopCamera() async {
    if (_cameraController != null) {
      try {
        await _cameraController!.stop();
      } catch (e) {
        debugPrint('停止相機時發生錯誤：$e');
      }
      try {
        await _cameraController!.dispose();
      } catch (e) {
        debugPrint('釋放相機時發生錯誤：$e');
      }
      _cameraController = null;
    }
  }

  // 相機掃描
  void _onCameraScan(String? barcode) {
    if (barcode != null && barcode.isNotEmpty && !_isScanning) {
      _onScan(barcode);
    }
  }

  // 手動送出
  void _onManualSubmit() async {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !_isScanning) {
      await _onScan(text);
    }
  }

  // 清除輸入
  void _onClear() {
    _controller.clear();
    _focusNode.requestFocus();
  }

  // 匯出總出貨結果
  Future<void> _exportTotalShipment() async {
    try {
      // 取得「今天有掃描活動」的批次
      // 包含：
      // 1. 未完成的批次（今天可能有掃描）
      // 2. 已完成的批次，但今天有掃描活動（今天補掃的）
      final batches = await DatabaseService.getBatchesWithTodayScans();
      
      if (batches.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('今天沒有掃描活動，無可匯出的批次'),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.primary,
            ),
          );
        }
        return;
      }

      // 檢查是否有已完成的批次（需要重新匯出）
      final hasFinishedBatches = batches.any((b) => b.isFinished);
      
      // 確認對話框
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(hasFinishedBatches ? '重新匯出總出貨結果' : '確認匯出總出貨結果'),
          content: Text(
            hasFinishedBatches
                ? '將重新匯出 ${batches.length} 個今天有掃描活動的批次（包含今天補掃的已完成批次）。將重新產生匯出檔案，可用於重新分享。'
                : '將匯出 ${batches.length} 個今天有掃描活動的批次。確定要匯出嗎？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確定'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      // 顯示載入中
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // 匯出所有「今天有掃描活動」的 Batch（匯總為一個檔案）
      ExportFiles? exportFiles;
      try {
        final batchIds = batches.map((b) => b.id).toList();
        exportFiles = await ExportService.exportMultipleBatches(batchIds);
      } catch (e) {
        debugPrint('匯出總出貨失敗：$e');
      }

      // 關閉載入中
      if (mounted) {
        Navigator.pop(context);
      }

      // 顯示匯出成功對話框
      if (mounted && exportFiles != null) {
        await _showExportSuccessDialog([exportFiles]);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('匯出失敗：無法產生匯總檔案'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.red[700]
                : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 關閉載入中
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('匯出失敗：${e.toString()}'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.red[700]
                : Colors.red,
          ),
        );
      }
    }
  }

  // 顯示匯出成功對話框
  Future<void> _showExportSuccessDialog(List<ExportFiles> files) async {
    if (files.isEmpty) return;
    
    // 讀取 TXT 內容用於複製（總出貨模式只有一個匯總檔案）
    String txtContent = '';
    try {
      final txtFile = File(files.first.txtPath);
      if (await txtFile.exists()) {
        txtContent = await txtFile.readAsString(encoding: utf8);
      }
    } catch (e) {
      // 忽略讀取錯誤
      debugPrint('讀取 TXT 內容失敗：$e');
    }

    // 取得檔案的路徑（用於顯示和開啟）
    final txtPath = files.first.txtPath;
    final jsonPath = files.first.jsonPath;

    if (mounted) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('匯出成功'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已匯出總出貨結果（匯總所有批次）',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (txtPath.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '檔案已匯出至：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    txtPath,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  '請選擇操作：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            // 複製 TXT 內容
            if (txtContent.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('複製 TXT 內容'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: txtContent));
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('已複製總出貨內容到剪貼簿，可貼到 LINE'),
                        backgroundColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.green[700]
                            : Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            // 開啟 TXT 檔案
            if (txtPath.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('開啟 TXT'),
                onPressed: () async {
                  try {
                    // 使用分享功能來開啟檔案（系統會提供開啟選項）
                    await ShareService.shareFiles(txtPath);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('開啟檔案失敗：${e.toString()}'),
                          backgroundColor: Theme.of(context).brightness == Brightness.dark
                              ? Colors.red[700]
                              : Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            // 分享 TXT
            TextButton.icon(
              icon: const Icon(Icons.share, size: 18),
              label: const Text('分享 TXT'),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  if (txtPath.isNotEmpty) {
                    await ShareService.shareFiles(txtPath);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('分享失敗：${e.toString()}。您可以稍後重新匯出並再次嘗試分享。'),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                }
              },
            ),
            // 分享 JSON
            TextButton.icon(
              icon: const Icon(Icons.share, size: 18),
              label: const Text('分享 JSON'),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  if (jsonPath.isNotEmpty) {
                    await ShareService.shareFiles(jsonPath);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('分享失敗：${e.toString()}。您可以稍後重新匯出並再次嘗試分享。'),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                }
              },
            ),
            // 關閉
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('關閉'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('總出貨核對'),
        automaticallyImplyLeading: true,
      ),
      body: Column(
        children: [
          // 資訊顯示區
          _buildInfoSection(),
          // 輸入模式選擇器
          _buildInputModeSelector(),
          // 掃描輸入區
          if (_inputMode == InputMode.camera)
            Expanded(
              flex: 2,
              child: _buildInputArea(),
            )
          else
            _buildInputArea(),
          // 狀態顯示欄位（僅在相機模式時顯示，位於列表上方）
          if (_inputMode == InputMode.camera)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[900]
                  : Colors.grey[100],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getStatusIcon(_lastScanStatus ?? ScanStatus.pending),
                      color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentStatusMessage,
                            style: TextStyle(
                              color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (_lastScanMessage != null && _lastScanMessage != _currentStatusMessage) ...[
                            const SizedBox(height: 4),
                            Text(
                              _lastScanMessage!,
                              style: TextStyle(
                                color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending).withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 列表區
          Expanded(
            flex: _inputMode == InputMode.camera ? 3 : 1,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildItemList(),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.file_download),
                  label: const Text('匯出全部'),
                  onPressed: _exportTotalShipment,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 建立資訊顯示區
  Widget _buildInfoSection() {
    final stats = _getStatistics();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.blue[900]!.withOpacity(0.3)
          : Colors.blue[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline, 
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.primary
                    : Colors.blue[700], 
                size: 18
              ),
              const SizedBox(width: 6),
              Text(
                '總出貨資訊',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(context).colorScheme.primary
                      : Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 批次數、來源、訂單日期（緊湊顯示）
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '批次：', 
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  Text(
                    '${stats['batchCount']}',
                    style: TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              if ((stats['storeNames'] as List).isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '來源：', 
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        _formatStoreNames((stats['storeNames'] as List<String>)),
                        style: TextStyle(
                          fontSize: 12, 
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              if ((stats['orderDates'] as List).isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '日期：', 
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        _formatOrderDates((stats['orderDates'] as List<String>)),
                        style: TextStyle(
                          fontSize: 12, 
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 統計資訊
          Row(
            children: [
              Expanded(
                child: _buildStatItem('總筆數', '${stats['total']}', Colors.blue),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatItem('待掃描', '${stats['pending']}', Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatItem('已掃描', '${stats['scanned']}', Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // 建立統計項目
  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // 建立輸入模式選擇器
  Widget _buildInputModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.blue[900]!.withOpacity(0.3)
          : Colors.blue[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: InputMode.values.map((mode) {
          final isSelected = _inputMode == mode;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton.icon(
                icon: Icon(
                  mode.icon,
                  color: isSelected 
                      ? Colors.white 
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.7)
                          : Colors.blue),
                ),
                label: Text(
                  mode.displayName,
                  style: TextStyle(
                    color: isSelected 
                        ? Colors.white 
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue[300]
                            : Colors.blue),
                    fontSize: 12,
                  ),
                ),
                onPressed: () => _switchInputMode(mode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected 
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.primary
                          : Colors.blue)
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[800]
                          : Colors.white),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 建立輸入區域
  Widget _buildInputArea() {
    if (_inputMode == InputMode.camera) {
      return _buildCameraView();
    } else {
      return _buildTextInput();
    }
  }

  // 建立文字輸入（掃描槍/手動輸入）
  Widget _buildTextInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey[900]
          : Colors.grey[100],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: _inputMode == InputMode.scanner,
                  enabled: !_isScanning,
                  decoration: InputDecoration(
                    hintText: _inputMode == InputMode.scanner
                        ? '請掃描物流單號（掃描槍模式）'
                        : '請輸入物流單號',
                    border: const OutlineInputBorder(),
                    suffixIcon: _inputMode == InputMode.manual
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _isScanning ? null : _onClear,
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    if (_inputMode == InputMode.manual) {
                      // 手動輸入模式：監聽文字變化以更新按鈕狀態
                      setState(() {});
                    } else if (_inputMode == InputMode.scanner) {
                      // 掃描槍模式：取消之前的計時器
                      _scannerInputTimer?.cancel();
                      
                      // 如果輸入框有內容，設置計時器自動提交（掃描槍通常快速輸入後會停止）
                      if (value.isNotEmpty && !_isScanning) {
                        _scannerInputTimer = Timer(const Duration(milliseconds: 300), () {
                          // 300ms 內沒有新輸入，認為掃描完成，自動提交
                          if (mounted && _inputMode == InputMode.scanner && _controller.text.trim().isNotEmpty && !_isScanning) {
                            _onScan(_controller.text.trim());
                          }
                        });
                      }
                    }
                  },
                  onSubmitted: _inputMode == InputMode.scanner ? _onScan : null,
                ),
              ),
              if (_inputMode == InputMode.manual) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (_isScanning || _controller.text.trim().isEmpty)
                      ? null
                      : _onManualSubmit,
                  child: const Text('送出'),
                ),
              ],
            ],
          ),
          // 狀態顯示欄位（始終顯示）
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getStatusIcon(_lastScanStatus ?? ScanStatus.pending),
                  color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentStatusMessage,
                        style: TextStyle(
                          color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (_lastScanMessage != null && _lastScanMessage != _currentStatusMessage) ...[
                        const SizedBox(height: 4),
                        Text(
                          _lastScanMessage!,
                          style: TextStyle(
                            color: _getStatusColor(_lastScanStatus ?? ScanStatus.pending).withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 建立相機視圖
  Widget _buildCameraView() {
    if (_cameraController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            '相機初始化中...',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _cameraController!,
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null) {
                _onCameraScan(barcode.rawValue);
                break; // 只處理第一個條碼
              }
            }
          },
        ),
        // 掃描框指示器
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        // 提示文字
        Positioned(
          bottom: 50,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '將條碼對準掃描框',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 建立項目列表
  Widget _buildItemList() {
    if (_items.isEmpty) {
      return const Center(
        child: Text('尚無資料'),
      );
    }

    // 分類顯示
    final pendingItems = _items.where((i) => i.scanStatus == ScanStatus.pending).toList();
    final scannedItems = _items.where((i) => i.scanStatus == ScanStatus.scanned).toList();
    final errorItems = _items.where((i) => 
      i.scanStatus == ScanStatus.duplicate || i.scanStatus == ScanStatus.invalid
    ).toList();

    return ListView(
      children: [
        if (pendingItems.isNotEmpty) ...[
          _buildSectionHeader('待掃描 (${pendingItems.length})', Theme.of(context).colorScheme.primary),
          ...pendingItems.map((item) => _buildItemCard(item)),
        ],
        if (scannedItems.isNotEmpty) ...[
          _buildSectionHeader('已掃描 (${scannedItems.length})', Colors.green),
          ...scannedItems.map((item) => _buildItemCard(item)),
        ],
        if (errorItems.isNotEmpty) ...[
          _buildSectionHeader('錯誤 (${errorItems.length})', Colors.red),
          ...errorItems.map((item) => _buildItemCard(item)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withOpacity(0.1),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildItemCard(ScanItem item) {
    return FutureBuilder(
      future: DatabaseService.getBatch(item.batchId),
      builder: (context, snapshot) {
        final batch = snapshot.data;
        final storeName = batch?.storeName ?? '未知來源';
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            title: Text(item.logisticsNo),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('來源：$storeName'),
                Text('訂單日期：${item.orderDate}'),
                Text('訂單編號：${item.orderNo}'),
                if (item.logisticsCompany != null)
                  Text('物流公司：${item.logisticsCompany}'),
                if (item.scanTime != null)
                  Text('掃描時間：${_formatDateTime(item.scanTime!)}'),
                if (item.scanNote != null && item.scanNote!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.blue[900]!.withOpacity(0.3)
                          : Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.primary
                            : Colors.blue[200]!,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.note, 
                          size: 16, 
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).colorScheme.primary
                              : Colors.blue[700],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '備註：${item.scanNote}',
                            style: TextStyle(
                              fontSize: 12, 
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.blue[200]
                                  : Colors.blue[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusChip(item.scanStatus),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit_note',
                      child: Row(
                        children: [
                          const Icon(Icons.edit, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(item.scanNote != null && item.scanNote!.isNotEmpty 
                            ? '編輯備註'
                            : '新增備註'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete, color: Colors.red),
                          const SizedBox(width: 8),
                          const Text('刪除'),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit_note' && item.id != null) {
                      _editScanNote(item);
                    } else if (value == 'delete' && item.id != null) {
                      _deleteItem(item.id!);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 編輯掃描備註
  Future<void> _editScanNote(ScanItem item) async {
    final controller = TextEditingController(text: item.scanNote ?? '');
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.scanNote != null && item.scanNote!.isNotEmpty 
          ? '編輯備註'
          : '新增備註'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '請輸入備註（選填）',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('確定'),
          ),
        ],
      ),
    );

    if (result != null && item.id != null) {
      try {
        // 如果結果為空字串，設為 null
        final scanNote = result.isEmpty ? null : result;
        await ScanService.updateScanNote(item.id!, scanNote);
        await _loadItems(); // 重新載入列表
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(scanNote == null 
                ? '已清除備註'
                : '備註已更新'),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.green[700]
                : Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('更新備註失敗：${e.toString()}'),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.red[700]
                : Colors.red,
            ),
          );
        }
      }
    }
  }

  // 刪除單筆項目
  Future<void> _deleteItem(int itemId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('確定要刪除此筆資料嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseService.deleteScanItem(itemId);
        await _loadItems();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('已刪除'),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.green[700]
                : Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('刪除失敗：${e.toString()}'),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.red[700]
                : Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildStatusChip(ScanStatus status) {
    Color color;
    switch (status) {
      case ScanStatus.scanned:
        color = Colors.green;
        break;
      case ScanStatus.duplicate:
        color = Theme.of(context).colorScheme.primary;
        break;
      case ScanStatus.invalid:
        color = Colors.red;
        break;
      case ScanStatus.pending:
        color = Theme.of(context).colorScheme.primary;
        break;
    }

    return Chip(
      label: Text(
        _getStatusDisplayName(status),
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
      backgroundColor: color,
      labelStyle: TextStyle(color: color),
    );
  }

  String _getStatusDisplayName(ScanStatus status) {
    switch (status) {
      case ScanStatus.scanned:
        return '已掃描';
      case ScanStatus.duplicate:
        return '重複';
      case ScanStatus.invalid:
        return '無效';
      case ScanStatus.pending:
        return '待掃描';
    }
  }

  Color _getStatusColor(ScanStatus? status) {
    if (status == null) return Colors.blue; // 預設為藍色（待掃描/輸入）
    switch (status) {
      case ScanStatus.scanned:
        return Colors.green;
      case ScanStatus.duplicate:
        return Theme.of(context).colorScheme.primary;
      case ScanStatus.invalid:
        return Colors.red;
      case ScanStatus.pending:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(ScanStatus? status) {
    if (status == null) return Icons.input; // 預設為輸入圖示
    switch (status) {
      case ScanStatus.scanned:
        return Icons.check_circle;
      case ScanStatus.duplicate:
        return Icons.warning;
      case ScanStatus.invalid:
        return Icons.error;
      case ScanStatus.pending:
        return Icons.input;
    }
  }

  String _formatDateTime(String isoString) {
    try {
      DateTime.parse(isoString); // 驗證日期格式
      return TimezoneHelper.formatLocalTime(isoString);
    } catch (e) {
      return isoString;
    }
  }

  // 格式化來源名稱（簡化顯示）
  String _formatStoreNames(List<String> storeNames) {
    if (storeNames.isEmpty) return '';
    if (storeNames.length <= 3) {
      return storeNames.join('、');
    }
    // 超過3個時，只顯示前3個，其餘用「等X個來源」表示
    return '${storeNames.take(3).join('、')}等${storeNames.length}個來源';
  }

  // 格式化訂單日期（簡化顯示）
  String _formatOrderDates(List<String> orderDates) {
    if (orderDates.isEmpty) return '';
    // 去重並排序
    final uniqueDates = orderDates.toSet().toList()..sort();
    if (uniqueDates.length <= 3) {
      return uniqueDates.join('、');
    }
    // 超過3個時，顯示範圍（最早到最晚）
    if (uniqueDates.length > 3) {
      return '${uniqueDates.first} 至 ${uniqueDates.last}（共${uniqueDates.length}個日期）';
    }
    return uniqueDates.join('、');
  }
}

