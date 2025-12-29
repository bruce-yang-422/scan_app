import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/scan_item.dart';
import '../models/scan_status.dart';
import '../models/input_mode.dart';
import '../services/scan_service.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/share_service.dart';
import '../services/app_settings_service.dart';
import '../utils/timezone_helper.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

// Batch 掃描頁面
class BatchScanPage extends StatefulWidget {
  final String batchId;

  const BatchScanPage({
    super.key,
    required this.batchId,
  });

  @override
  State<BatchScanPage> createState() => _BatchScanPageState();
}

class _BatchScanPageState extends State<BatchScanPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  MobileScannerController? _cameraController;
  
  List<ScanItem> _items = [];
  bool _isLoading = true;
  bool _isFinished = false; // 批次是否已完成
  String? _lastScanMessage;
  ScanStatus? _lastScanStatus;
  String _currentStatusMessage = ''; // 當前狀態訊息（會在 build 時初始化）
  InputMode _inputMode = InputMode.scanner; // 預設為掃描槍模式
  bool _isScanning = false; // 相機掃描狀態
  Set<int> _selectedItems = {}; // 選中的項目 ID（用於批次刪除）
  Timer? _statusTimer; // 狀態顯示計時器
  bool _isSelectionMode = false; // 是否處於選擇模式
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
    // 初始化狀態訊息（使用本地化字串）
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
    _cameraController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
    });

    // 檢查批次是否已完成
    final batch = await DatabaseService.getBatch(widget.batchId);
    final isFinished = batch?.isFinished ?? false;
    
    final items = await DatabaseService.getScanItemsByBatch(widget.batchId);
    
    if (mounted) {
      setState(() {
        _items = items;
        _isFinished = isFinished;
        _isLoading = false;
      });
    }
  }

  Future<void> _onScan(String logisticsNo) async {
    if (logisticsNo.trim().isEmpty) {
      return;
    }

    // 如果批次已完成，仍然允許掃描（用於補掃漏掉的項目）
    // 但會提示需要重新匯出才能看到最新狀態
    if (_isFinished) {
      // 允許掃描，但會在掃描成功後提示
    }

    // 防止重複掃描
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      final result = await ScanService.scanLogisticsNo(
        widget.batchId,
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

      // 立即更新狀態（快速連續掃描時直接切換）
      setState(() {
        _lastScanStatus = result.status;
        _lastScanMessage = result.message;
        _currentStatusMessage = statusMessage;
      });

      // 重新載入資料
      await _loadItems();

      // 如果批次已完成但掃描成功，提示需要重新匯出
      if (_isFinished && result.status == ScanStatus.scanned && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('掃描成功！請重新匯出以更新報告'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.primary
                : Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      }

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
            content: Text(result.message),
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
      // 停止相機
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
      // 如果控制器已存在但未啟動，先停止
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

  // 停止相機
  Future<void> _stopCamera() async {
    if (_cameraController != null) {
      try {
        await _cameraController!.stop();
      } catch (e) {
        debugPrint('停止相機時發生錯誤：$e');
      }
    }
  }

  // 處理相機掃描結果
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

  Future<void> _exportBatch() async {
    try {
      // 檢查批次是否已完成
      final batch = await DatabaseService.getBatch(widget.batchId);
      final isFinished = batch?.isFinished ?? false;
      
      // 確認對話框
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isFinished 
            ? '重新匯出'
            : '確認匯出'),
          content: Text(
            isFinished
                ? '此批次已完成匯出。將重新產生匯出檔案，可用於重新分享。'
                : '匯出後此批次將標記為已完成，無法再修改。確定要匯出嗎？',
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

      // 匯出（允許重新匯出）
      final files = await ExportService.exportBatch(widget.batchId, allowReexport: true);

      // 關閉載入中
      if (mounted) {
        Navigator.pop(context);
      }

      // 顯示匯出成功對話框，包含檔案位置和操作選項
      if (mounted) {
        await _showExportSuccessDialog(files);
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
  Future<void> _showExportSuccessDialog(ExportFiles files) async {
    // 讀取 TXT 內容用於複製
    String txtContent = '';
    try {
      final txtFile = File(files.txtPath);
      if (await txtFile.exists()) {
        txtContent = await txtFile.readAsString(encoding: utf8);
      }
    } catch (e) {
      // 忽略讀取錯誤
    }

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
                const Text(
                  '檔案已匯出至：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  files.txtPath,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  files.jsonPath,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
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
                        content: const Text('已複製到剪貼簿，可貼到 LINE'),
                        backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.green[700]
                : Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            // 開啟 TXT 檔案（使用分享功能開啟）
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('開啟 TXT'),
              onPressed: () async {
                try {
                  // 使用分享功能來開啟檔案（系統會提供開啟選項）
                  await ShareService.shareFiles(files.txtPath);
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
                  await ShareService.shareFiles(files.txtPath);
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
                  await ShareService.shareFiles(files.jsonPath);
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
        title: const Text('出貨核對系統'),
        automaticallyImplyLeading: true,
      ),
      body: Column(
        children: [
          // 如果已完成，顯示提示訊息
          if (_isFinished)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '此批次已完成，僅供查看',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          // 輸入模式選擇器（已完成時隱藏）
          if (!_isFinished) _buildInputModeSelector(),
          // 掃描輸入區（已完成時隱藏）
          if (!_isFinished)
            if (_inputMode == InputMode.camera)
              Expanded(
                flex: 2,
                child: _buildInputArea(),
              )
            else
              _buildInputArea(),
          // 狀態顯示欄位（僅在相機模式且未完成時顯示，位於列表上方）
          if (!_isFinished && _inputMode == InputMode.camera)
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
            flex: _isFinished || _inputMode != InputMode.camera ? 1 : 3,
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
          child: _isSelectionMode
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(_isAllSelected() ? Icons.check_box_outline_blank : Icons.check_box),
                        label: Text(_isAllSelected() 
                          ? '取消全選'
                          : '全選'),
                        onPressed: _toggleSelectAll,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.delete),
                        label: Text('刪除選中項目 (${_selectedItems.length})'),
                        onPressed: _selectedItems.isEmpty ? null : _deleteSelectedItems,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.red[700]
                : Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text('取消'),
                        onPressed: () {
                          setState(() {
                            _isSelectionMode = false;
                            _selectedItems.clear();
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.checklist),
                        label: const Text('選擇'),
                        onPressed: () {
                          setState(() {
                            _isSelectionMode = true;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.file_download),
                        label: const Text('匯出'),
                        onPressed: _exportBatch,
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

  Widget _buildItemList() {
    if (_items.isEmpty) {
      return Center(
        child: const Text('尚無資料'),
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
          _buildSectionHeader(
            '待掃描 (${pendingItems.length})', 
            Theme.of(context).colorScheme.primary
          ),
          ...pendingItems.map((item) => _buildItemCard(item)),
        ],
        if (scannedItems.isNotEmpty) ...[
          _buildSectionHeader(
            '已掃描 (${scannedItems.length})', 
            Colors.green
          ),
          ...scannedItems.map((item) => _buildItemCard(item)),
        ],
        if (errorItems.isNotEmpty) ...[
          _buildSectionHeader(
            '錯誤 (${errorItems.length})', 
            Colors.red
          ),
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
    final isSelected = _isSelectionMode && item.id != null && _selectedItems.contains(item.id);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected ? Colors.blue[50] : null,
      child: ListTile(
        leading: _isSelectionMode && item.id != null
            ? Checkbox(
                value: isSelected,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedItems.add(item.id!);
                    } else {
                      _selectedItems.remove(item.id!);
                    }
                  });
                },
              )
            : null,
        title: Text(item.logisticsNo),
            subtitle: Builder(
              builder: (context) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                overflow: TextOverflow.ellipsis,
                                maxLines: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
        trailing: _isSelectionMode
            ? null
            : Row(
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
                      // 已完成批次不顯示刪除選項
                      if (!_isFinished)
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
        isThreeLine: true,
        onTap: _isSelectionMode && item.id != null
            ? () {
                setState(() {
                  if (_selectedItems.contains(item.id!)) {
                    _selectedItems.remove(item.id!);
                  } else {
                    _selectedItems.add(item.id!);
                  }
                });
              }
            : null,
      ),
    );
  }

  // 檢查是否已全選
  bool _isAllSelected() {
    if (_items.isEmpty) return false;
    final selectableItems = _items.where((item) => item.id != null).toList();
    if (selectableItems.isEmpty) return false;
    return _selectedItems.length == selectableItems.length;
  }

  // 切換全選/取消全選
  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected()) {
        // 取消全選
        _selectedItems.clear();
      } else {
        // 全選
        _selectedItems = _items
            .where((item) => item.id != null)
            .map((item) => item.id!)
            .toSet();
      }
    });
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

  // 刪除選中的項目
  Future<void> _deleteSelectedItems() async {
    if (_selectedItems.isEmpty) return;

    final count = _selectedItems.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認批次刪除'),
        content: Text('確定要刪除選中的 $count 筆資料嗎？此操作無法復原。'),
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
        await DatabaseService.deleteScanItems(_selectedItems.toList());
        setState(() {
          _selectedItems.clear();
          _isSelectionMode = false;
        });
        await _loadItems();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已刪除 $count 筆資料'),
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
      case ScanStatus.pending:
        color = Theme.of(context).colorScheme.primary;
        break;
      case ScanStatus.scanned:
        color = Colors.green;
        break;
      case ScanStatus.duplicate:
        color = Colors.red;
        break;
      case ScanStatus.invalid:
        color = Colors.red;
        break;
    }

    return Chip(
      label: Text(
        status.displayName,
        style: const TextStyle(fontSize: 12),
      ),
      backgroundColor: color.withOpacity(0.1),
      labelStyle: TextStyle(color: color),
    );
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
              child: ChoiceChip(
                label: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(mode.icon, size: 18),
                    const SizedBox(width: 4),
                    Text(mode.displayName),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    _switchInputMode(mode);
                  }
                },
                selectedColor: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.primary
                    : Colors.blue[200],
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.white,
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
          child: CircularProgressIndicator(color: Colors.white),
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
}

