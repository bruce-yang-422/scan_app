import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/batch.dart';
import '../services/google_sheets_service.dart';
import '../services/database_service.dart';
import '../services/store_url_service.dart';
import '../utils/date_parser.dart';
import '../utils/timezone_helper.dart';

// Batch 匯入頁面
class BatchImportPage extends StatefulWidget {
  const BatchImportPage({super.key});

  @override
  State<BatchImportPage> createState() => _BatchImportPageState();
}

class _BatchImportPageState extends State<BatchImportPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  List<String> _savedNotes = [];
  Map<String, String> _savedStoreUrls = {};
  String? _selectedNote;

  @override
  void initState() {
    super.initState();
    _loadSavedStoreUrls();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // 載入已儲存的連結
  Future<void> _loadSavedStoreUrls() async {
    final storeUrls = await StoreUrlService.getAllStoreUrls();
    final notes = storeUrls.keys.toList()..sort();
    
    setState(() {
      _savedStoreUrls = storeUrls;
      _savedNotes = notes;
    });
  }

  // 選擇連結
  void _onLinkSelected(String? note) {
    setState(() {
      _selectedNote = note;
      if (note != null && _savedStoreUrls.containsKey(note)) {
        _urlController.text = _savedStoreUrls[note]!;
        _noteController.text = note;
      } else {
        _urlController.clear();
        _noteController.clear();
      }
    });
  }

  // 儲存或更新連結
  Future<void> _saveOrUpdateLink(String note, String url) async {
    if (note.trim().isNotEmpty && url.trim().isNotEmpty) {
      // 如果選擇的是現有連結，且備註有變更，需要刪除舊的並建立新的
      if (_selectedNote != null && _selectedNote != note.trim()) {
        await StoreUrlService.deleteStoreUrl(_selectedNote!);
      }
      await StoreUrlService.saveStoreUrl(note.trim(), url.trim());
      await _loadSavedStoreUrls();
      // 更新選中的連結
      setState(() {
        _selectedNote = note.trim();
      });
    }
  }

  Future<void> _importSheet() async {
    final url = _urlController.text.trim();
    
    if (url.isEmpty) {
      setState(() {
        _errorMessage = '請輸入 Google Sheet 連結';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // 使用多批次匯入方法，自動依據訂單日期分批管理
      final multiBatchResult = await GoogleSheetsService.importFromSheetMultiBatch(url);

      if (multiBatchResult.batches.isEmpty) {
        throw Exception('沒有有效的資料行');
      }

      // 處理每個 Batch
      String? firstBatchId; // 記錄第一個 Batch ID，用於自動導航
      int successBatchCount = 0;
      int skipBatchCount = 0;
      int totalItemsCount = 0;

      for (final entry in multiBatchResult.batches.entries) {
        final batchId = entry.key;
        final items = entry.value;
        final storeName = multiBatchResult.batchStoreNames[batchId] ?? '未命名來源';
        
        // 從 batchId 中提取 order_date
        // batchId 格式：{store_name}_{order_date}
        // 但 store_name 可能包含 _，所以需要從最後一個 _ 開始提取 order_date
        final lastUnderscoreIndex = batchId.lastIndexOf('_');
        if (lastUnderscoreIndex == -1 || lastUnderscoreIndex >= batchId.length - 1) {
          continue; // 跳過格式錯誤的 batchId
        }
        final orderDate = batchId.substring(lastUnderscoreIndex + 1);

        // 檢查是否已存在且已完成
        final existingBatch = await DatabaseService.getBatch(batchId);
        if (existingBatch != null && existingBatch.isFinished) {
          skipBatchCount++;
          continue; // 跳過已完成的批次
        }

        // 建立或更新 Batch
        // 使用 UTC 時間儲存（標準時間，從 NTP 同步）
        final batch = Batch(
          id: batchId,
          storeName: storeName,
          orderDate: orderDate,
          createdAt: (await TimezoneHelper.getUtcNow()).toIso8601String(),
        );

        await DatabaseService.insertOrUpdateBatch(batch);
        await DatabaseService.insertScanItems(items);

        // 記錄第一個 Batch ID（用於自動導航）
        if (firstBatchId == null) {
          firstBatchId = batchId;
        }

        successBatchCount++;
        totalItemsCount += items.length;
      }

      // 儲存連結（如果使用者有輸入備註）
      if (_noteController.text.trim().isNotEmpty) {
        await _saveOrUpdateLink(_noteController.text.trim(), url);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          // 建立成功訊息，包含各種統計資訊
          final List<String> messages = [];
          if (successBatchCount > 1) {
            messages.add('匯入成功！共 $successBatchCount 個批次，$totalItemsCount 筆資料');
          } else {
            messages.add('匯入成功！共 $totalItemsCount 筆資料');
          }
          
          if (skipBatchCount > 0) {
            messages.add('跳過 $skipBatchCount 個已完成批次');
          }
          if (multiBatchResult.blankCount > 0) {
            messages.add('空白 ${multiBatchResult.blankCount} 筆');
          }
          if (multiBatchResult.duplicateCount > 0) {
            messages.add('重複 ${multiBatchResult.duplicateCount} 筆');
          }
          if (multiBatchResult.skippedCount > 0) {
            messages.add('無效 ${multiBatchResult.skippedCount} 筆');
          }
          
          _successMessage = messages.join('，');
          _errorMessage = null;
        });

        // 顯示成功訊息（包含所有統計資訊）
        final List<String> snackMessages = [];
        if (successBatchCount > 1) {
          snackMessages.add('匯入成功！共 $successBatchCount 個批次，$totalItemsCount 筆資料');
        } else {
          snackMessages.add('匯入成功！共 $totalItemsCount 筆資料');
        }
        
        if (skipBatchCount > 0) {
          snackMessages.add('跳過 $skipBatchCount 個已完成批次');
        }
        if (multiBatchResult.blankCount > 0) {
          snackMessages.add('空白 ${multiBatchResult.blankCount} 筆');
        }
        if (multiBatchResult.duplicateCount > 0) {
          snackMessages.add('重複 ${multiBatchResult.duplicateCount} 筆');
        }
        if (multiBatchResult.skippedCount > 0) {
          snackMessages.add('無效 ${multiBatchResult.skippedCount} 筆');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackMessages.join('，')),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.green[700]
                : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // 延遲一下讓使用者看到訊息，然後返回並傳遞第一個 batchId 以便自動導航到掃描頁面
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pop(context, firstBatchId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
          _successMessage = null;
        });
      }
    }
  }

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


  Future<String> _downloadCsvDirect(String csvUrl) async {
    final response = await http.get(Uri.parse(csvUrl)).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw Exception('下載逾時，請檢查網路連線');
      },
    );
    if (response.statusCode != 200) {
      throw Exception('無法下載資料，狀態碼：${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes);
  }

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


  Future<void> _pasteUrl() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      _urlController.text = clipboardData!.text!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('出貨核對系統'),
        automaticallyImplyLeading: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '匯入 Google Sheet',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '請貼上公開的 Google Sheet 連結（必須設定為「知道連結的使用者都可以查看」）',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            // 連結選擇
            if (_savedNotes.isNotEmpty) ...[
              Text(
                '選擇連結（快速載入已儲存的 URL）',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedNote,
                decoration: InputDecoration(
                  hintText: '選擇連結...',
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: const Text('不使用已儲存的連結'),
                  ),
                  ..._savedNotes.map((note) => DropdownMenuItem(
                        value: note,
                        child: Text(note),
                      )),
                ],
                onChanged: _isLoading ? null : _onLinkSelected,
              ),
              const SizedBox(height: 16),
            ],
            // 連結備註輸入（用於儲存 URL）
            TextField(
              controller: _noteController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: '連結備註（選填，用於儲存此 URL）',
                hintText: '例如：台北一店、總店出貨單、供應商A等（可自由設定）',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // URL 輸入
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      labelText: 'Google Sheet 連結',
                      hintText: 'https://docs.google.com/spreadsheets/d/...',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: _isLoading ? null : _pasteUrl,
                  tooltip: '貼上',
                ),
                if (_urlController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(_selectedNote != null ? Icons.edit : Icons.save),
                    onPressed: _isLoading || _noteController.text.trim().isEmpty
                        ? null
                        : () async {
                            await _saveOrUpdateLink(
                              _noteController.text.trim(),
                              _urlController.text.trim(),
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_selectedNote != null 
                                    ? '連結已更新'
                                    : '連結已儲存'),
                                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.green[700]
                : Colors.green,
                                ),
                              );
                            }
                          },
                    tooltip: _selectedNote != null 
                      ? '更新連結'
                      : '儲存連結',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _importSheet,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('匯入資料'),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_successMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

