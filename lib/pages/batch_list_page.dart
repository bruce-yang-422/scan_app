import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/batch.dart' as models;
import '../services/database_service.dart';
import '../services/scan_service.dart';
import '../services/google_sheets_service.dart';
import '../services/store_url_service.dart';
import '../utils/timezone_helper.dart';
import '../utils/date_parser.dart';
import 'batch_import_page.dart';
import 'batch_scan_page.dart';
import 'total_shipment_scan_page.dart';
import 'settings_page.dart';

// Batch 列表頁面
class BatchListPage extends StatefulWidget {
  const BatchListPage({super.key});

  @override
  State<BatchListPage> createState() => _BatchListPageState();
}

class _BatchListPageState extends State<BatchListPage> {
  List<models.Batch> _batches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 取得所有批次（包括已完成的）
      final allBatches = await DatabaseService.getAllBatches();
      
      // 分離未完成和已完成的批次
      final unfinishedBatches = allBatches.where((b) => !b.isFinished).toList();
      final finishedBatches = allBatches.where((b) => b.isFinished).toList();
      
      // 未完成的在前，已完成的在後
      final sortedBatches = [...unfinishedBatches, ...finishedBatches];
      
      if (mounted) {
        setState(() {
          _batches = sortedBatches;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('載入批次列表時發生錯誤：$e');
      if (mounted) {
        setState(() {
          _batches = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('出貨核對系統'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
              ? _buildEmptyState()
              : _buildBatchList(),
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
                  icon: const Icon(Icons.all_inclusive),
                  label: const Text('總出貨'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TotalShipmentScanPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('批次更新'),
                  onPressed: _showBatchUpdateDialog,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('匯入'),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BatchImportPage(),
                      ),
                    );
                    if (result != null) {
                      // 重新載入批次列表
                      _loadBatches();
                      // 如果返回的是 batchId（字串），自動導航到該 Batch 的掃描頁面
                      if (result is String) {
                        // 等待列表載入完成
                        await Future.delayed(const Duration(milliseconds: 300));
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BatchScanPage(batchId: result),
                            ),
                          );
                        }
                      }
                    }
                  },
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.inbox,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            '尚無批次資料',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '請點擊下方「匯入」按鈕匯入新批次',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchList() {
    return RefreshIndicator(
      onRefresh: _loadBatches,
      child: ListView.builder(
        itemCount: _batches.length,
        itemBuilder: (context, index) {
          final batch = _batches[index];
          return _buildBatchCard(batch);
        },
      ),
    );
  }

  Widget _buildBatchCard(models.Batch batch) {
    final isFinished = batch.isFinished;
    
    return FutureBuilder(
      future: Future.wait([
        ScanService.getBatchStatistics(batch.id),
        DatabaseService.getBatchDateRange(batch.id),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return ListTile(
            title: const Text('載入中...'),
          );
        }

        final results = snapshot.data!;
        final stats = results[0] as BatchStatistics;
        final dateRange = results[1] as Map<String, String?>;
        final progress = stats.total > 0 ? stats.scanned / stats.total : 0.0;
        
        // 已完成批次使用灰色文字
        final textColor = isFinished ? Colors.grey : null;

        // 格式化匯入時間（created_at 轉換為本地時間）
        String importTimeStr = '';
        try {
          final importTime = DateTime.parse(batch.createdAt);
          final localTime = TimezoneHelper.toLocalTime(importTime);
          importTimeStr = '${localTime.year}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
        } catch (e) {
          importTimeStr = batch.createdAt;
        }

        // 取得日期範圍
        final minDate = dateRange['min_date'];
        final maxDate = dateRange['max_date'];
        String dateRangeStr = '';
        if (minDate != null && maxDate != null) {
          if (minDate == maxDate) {
            dateRangeStr = minDate;
          } else {
            dateRangeStr = '$minDate ~ $maxDate';
          }
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isFinished 
              ? (Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[900]
                  : Colors.grey[50])
              : null,
          child: InkWell(
            onTap: () async {
              // 已完成和未完成的批次都可以點擊查看
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BatchScanPage(batchId: batch.id),
                ),
              );
              if (result == true) {
                _loadBatches();
              }
            },
            onLongPress: () {
              // 長按顯示刪除選單
              _showDeleteBatchDialog(batch);
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          batch.storeName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (isFinished) ...[
                        const Icon(
                          Icons.check_circle,
                          color: Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        importTimeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor ?? Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  if (dateRangeStr.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '日期範圍：$dateRangeStr',
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor ?? Colors.blue,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[700]
                        : Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isFinished 
                          ? Colors.grey.shade500
                          : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.green[400]!
                              : Colors.green),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '已掃描：${stats.scanned} / ${stats.total}',
                        style: TextStyle(
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                      if (stats.pending > 0)
                        Text(
                          '待掃描：${stats.pending}',
                          style: TextStyle(
                            fontSize: 14,
                            color: textColor ?? Colors.orange,
                          ),
                        ),
                    ],
                  ),
                  if (stats.error > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '錯誤：${stats.error}',
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor ?? Colors.red,
                        ),
                      ),
                    ),
                  if (isFinished) ...[
                    const SizedBox(height: 8),
                    Text(
                      '（已完成，長按可刪除）',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 顯示刪除批次對話框
  Future<void> _showDeleteBatchDialog(models.Batch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除批次'),
        content: Text(
          '確定要刪除批次「${batch.storeName}」嗎？\n\n此操作將刪除該批次的所有掃描記錄，且無法復原。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseService.deleteBatch(batch.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已刪除批次「${batch.storeName}」'),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.green[700]
                  : Colors.green,
            ),
          );
          _loadBatches();
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

  // 顯示批次更新對話框
  Future<void> _showBatchUpdateDialog() async {
    final storeUrls = await StoreUrlService.getAllStoreUrls();
    final storeNames = storeUrls.keys.toList()..sort();

    if (storeUrls.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('沒有已儲存的來源 URL，請先匯入並儲存來源 URL'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.orange[700]
                : Colors.orange,
          ),
        );
      }
      return;
    }

    String? selectedStoreName;
    bool updateAllStores = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('批次更新'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                title: const Text('更新所有來源'),
                value: true,
                groupValue: updateAllStores,
                onChanged: (value) {
                  setState(() {
                    updateAllStores = value ?? false;
                    selectedStoreName = null;
                  });
                },
              ),
              RadioListTile<bool>(
                title: const Text('選擇單一來源'),
                value: false,
                groupValue: updateAllStores,
                onChanged: (value) {
                  setState(() {
                    updateAllStores = value ?? false;
                  });
                },
              ),
              if (!updateAllStores) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedStoreName,
                  decoration: InputDecoration(
                    labelText: '選擇來源',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.surface
                        : null,
                  ),
                  items: storeNames.map((name) => DropdownMenuItem(
                        value: name,
                        child: Text(name),
                      )).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedStoreName = value;
                    });
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: updateAllStores || selectedStoreName != null
                  ? () => Navigator.pop(context, {
                        'updateAll': updateAllStores,
                        'storeName': selectedStoreName,
                      })
                  : null,
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _performBatchUpdate(
        updateAll: result['updateAll'] as bool,
        storeName: result['storeName'] as String?,
        storeUrls: storeUrls,
      );
    }
  }

  // 執行批次更新
  Future<void> _performBatchUpdate({
    required bool updateAll,
    String? storeName,
    required Map<String, String> storeUrls,
  }) async {
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

    try {
      final storesToUpdate = updateAll
          ? storeUrls.entries.toList()
          : storeName != null && storeUrls.containsKey(storeName)
              ? [MapEntry(storeName, storeUrls[storeName]!)]
              : [];

      int successCount = 0;
      int failCount = 0;
      final errors = <String>[];

      for (final entry in storesToUpdate) {
        try {
          final url = entry.value;
          
          // 使用多批次匯入方法，自動依據訂單日期分批管理
          final multiBatchResult = await GoogleSheetsService.importFromSheetMultiBatch(url);

          if (multiBatchResult.batches.isEmpty) {
            throw Exception('沒有有效的資料行');
          }

          // 處理每個 Batch
          int batchSuccessCount = 0;
          int batchSkipCount = 0;

          for (final batchEntry in multiBatchResult.batches.entries) {
            final batchId = batchEntry.key;
            final items = batchEntry.value;
            final storeName = multiBatchResult.batchStoreNames[batchId] ?? entry.key;
            
            // 從 batchId 中提取 order_date
            // batchId 格式：{store_name}_{order_date}
            // 但 store_name 可能包含 _，所以需要從最後一個 _ 開始提取 order_date
            final lastUnderscoreIndex = batchId.lastIndexOf('_');
            if (lastUnderscoreIndex == -1 || lastUnderscoreIndex >= batchId.length - 1) {
              continue; // 跳過格式錯誤的 batchId
            }
            final orderDate = batchId.substring(lastUnderscoreIndex + 1);

            // 檢查是否已完成
            final existingBatch = await DatabaseService.getBatch(batchId);
            if (existingBatch != null && existingBatch.isFinished) {
              batchSkipCount++;
              continue; // 跳過已完成的批次
            }

            // 強制重新初始化資料庫連線（確保連線有效）
            await DatabaseService.resetConnection();

            // 更新 Batch
            final batch = models.Batch(
              id: batchId,
              storeName: storeName,
              orderDate: orderDate,
              createdAt: (await TimezoneHelper.getUtcNow()).toIso8601String(),
            );

            await DatabaseService.insertOrUpdateBatch(batch);
            await DatabaseService.insertScanItems(items);

            batchSuccessCount++;
          }

          if (batchSuccessCount > 0) {
            successCount++;
          } else if (batchSkipCount > 0) {
            // 如果所有批次都已完成，也算成功（但會記錄在訊息中）
            successCount++;
          } else {
            throw Exception('沒有可更新的批次');
          }
        } catch (e) {
          failCount++;
          errors.add('${entry.key}: ${e.toString()}');
        }
      }

      // 關閉載入中
      if (mounted) {
        Navigator.pop(context);
      }

      // 顯示結果
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('批次更新完成'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('成功：$successCount 個來源'),
                  Text('失敗：$failCount 個來源'),
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('錯誤詳情：', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...errors.map((e) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(e, style: const TextStyle(fontSize: 12, color: Colors.red)),
                        )),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadBatches();
                },
                child: const Text('確定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // 關閉載入中
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('批次更新失敗：${e.toString()}'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.red[700]
                : Colors.red,
          ),
        );
      }
    }
  }

  // 轉換 Google Sheet URL 為 CSV URL
  String _convertToCsvUrl(String sheetUrl) {
    final sheetIdMatch = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)').firstMatch(sheetUrl);
    if (sheetIdMatch == null) {
      throw Exception('無效的 Google Sheet URL');
    }
    final sheetId = sheetIdMatch.group(1)!;
    final gidMatch = RegExp(r'[#&]gid=(\d+)').firstMatch(sheetUrl);
    final gid = gidMatch?.group(1) ?? '0';
    return 'https://docs.google.com/spreadsheets/d/$sheetId/export?format=csv&gid=$gid';
  }

  // 解析 CSV 行
  List<String> _parseCsvLine(String line) {
    final List<String> fields = [];
    final StringBuffer currentField = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          currentField.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        fields.add(currentField.toString());
        currentField.clear();
      } else {
        currentField.write(char);
      }
    }
    fields.add(currentField.toString());
    return fields;
  }

}


