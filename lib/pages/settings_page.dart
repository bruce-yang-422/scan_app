import 'package:flutter/material.dart';
import '../services/app_settings_service.dart';
import '../services/database_service.dart';
import '../utils/timezone_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';

// 設定頁面主頁
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<SettingsCategory> _buildCategories(BuildContext context) {
    return [
      SettingsCategory(
        title: '設定個資',
        icon: Icons.person,
        page: PersonalInfoSettingsPage(),
      ),
      SettingsCategory(
        title: '掃描設定',
        icon: Icons.scanner,
        page: ScanSettingsPage(),
      ),
      SettingsCategory(
        title: '時區資訊',
        icon: Icons.access_time,
        page: TimezoneSettingsPage(),
      ),
      SettingsCategory(
        title: '顯示模式',
        icon: Icons.brightness_6,
        page: ThemeModeSettingsPage(),
      ),
      SettingsCategory(
        title: 'APP 資訊',
        icon: Icons.info,
        page: AppInfoPage(),
      ),
      SettingsCategory(
        title: '隱私政策',
        icon: Icons.privacy_tip,
        page: PrivacyPolicyPage(),
      ),
      SettingsCategory(
        title: '資料管理',
        icon: Icons.storage,
        page: DataManagementPage(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final categories = _buildCategories(context);
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('設定'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: '返回主頁',
            onPressed: () {
              // 返回到主頁（BatchListPage）
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Text(
                '設定',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // 返回主頁選項
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('返回主頁'),
              onTap: () {
                Navigator.pop(context); // 關閉 Drawer
                // 返回到主頁（BatchListPage）
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
            const Divider(),
            ...List.generate(categories.length, (index) {
              final category = categories[index];
              final isSelected = _selectedIndex == index;
              return ListTile(
                leading: Icon(
                  category.icon,
                  color: isSelected 
                      ? Theme.of(context).primaryColor 
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
                title: Text(
                  category.title,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected 
                        ? Theme.of(context).primaryColor 
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                selected: isSelected,
                selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                onTap: () {
                  setState(() {
                    _selectedIndex = index;
                  });
                  Navigator.pop(context); // 關閉 Drawer
                },
              );
            }),
          ],
        ),
      ),
      body: categories[_selectedIndex].page,
    );
  }
}

class SettingsCategory {
  final String title;
  final IconData icon;
  final Widget page;

  SettingsCategory({
    required this.title,
    required this.icon,
    required this.page,
  });
}

// 設定個資頁面
class PersonalInfoSettingsPage extends StatefulWidget {
  const PersonalInfoSettingsPage({super.key});

  @override
  State<PersonalInfoSettingsPage> createState() => _PersonalInfoSettingsPageState();
}

class _PersonalInfoSettingsPageState extends State<PersonalInfoSettingsPage> {
  final TextEditingController _scannerNameController = TextEditingController();
  final TextEditingController _scannerIdController = TextEditingController();
  String _originalScannerName = '';
  String _originalScannerId = '';
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _scannerNameController.dispose();
    _scannerIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final scannerName = await AppSettingsService.getScannerName();
    final scannerId = await AppSettingsService.getScannerId();
    setState(() {
      _scannerNameController.text = scannerName;
      _scannerIdController.text = scannerId;
      _originalScannerName = scannerName;
      _originalScannerId = scannerId;
      _hasChanges = false;
    });
  }

  void _checkChanges() {
    setState(() {
      _hasChanges = _scannerNameController.text != _originalScannerName ||
          _scannerIdController.text != _originalScannerId;
    });
  }

  Future<void> _saveSettings() async {
    await AppSettingsService.setScannerName(_scannerNameController.text);
    await AppSettingsService.setScannerId(_scannerIdController.text);
    setState(() {
      _originalScannerName = _scannerNameController.text;
      _originalScannerId = _scannerIdController.text;
      _hasChanges = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('設定已儲存'),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.green[700]
              : Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasChanges) {
          final shouldDiscard = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('尚未儲存'),
              content: const Text('您有未儲存的變更，確定要放棄嗎？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('放棄'),
                ),
              ],
            ),
          );
          if (shouldDiscard == true && mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '設定個資',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _scannerNameController,
                      decoration: InputDecoration(
                        labelText: '掃描人員姓名',
                        hintText: '請輸入掃描人員姓名',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => _checkChanges(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _scannerIdController,
                      decoration: InputDecoration(
                        labelText: '掃描人員編號/ID',
                        hintText: '請輸入掃描人員編號或ID',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => _checkChanges(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '（此資訊會包含在匯出的 TXT 和 JSON 檔案中）',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_hasChanges)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.orange[50],
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '您有未儲存的變更',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.orange[200]
                              : Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('儲存'),
                onPressed: _hasChanges ? _saveSettings : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _hasChanges 
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.primary
                          : Colors.blue)
                      : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// 掃描設定頁面
class ScanSettingsPage extends StatefulWidget {
  const ScanSettingsPage({super.key});

  @override
  State<ScanSettingsPage> createState() => _ScanSettingsPageState();
}

class _ScanSettingsPageState extends State<ScanSettingsPage> {
  int _statusDelaySeconds = 2;
  bool _vibrationEnabled = true;
  bool _soundEnabled = true;
  int _cameraDuplicateIntervalSeconds = 10;
  int _originalStatusDelaySeconds = 2;
  bool _originalVibrationEnabled = true;
  bool _originalSoundEnabled = true;
  int _originalCameraDuplicateIntervalSeconds = 10;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final statusDelaySeconds = await AppSettingsService.getStatusDelaySeconds();
    final vibrationEnabled = await AppSettingsService.isVibrationEnabled();
    final soundEnabled = await AppSettingsService.isSoundEnabled();
    final cameraDuplicateIntervalSeconds = await AppSettingsService.getCameraDuplicateIntervalSeconds();
    setState(() {
      _statusDelaySeconds = statusDelaySeconds;
      _vibrationEnabled = vibrationEnabled;
      _soundEnabled = soundEnabled;
      _cameraDuplicateIntervalSeconds = cameraDuplicateIntervalSeconds;
      _originalStatusDelaySeconds = statusDelaySeconds;
      _originalVibrationEnabled = vibrationEnabled;
      _originalSoundEnabled = soundEnabled;
      _originalCameraDuplicateIntervalSeconds = cameraDuplicateIntervalSeconds;
      _hasChanges = false;
    });
  }

  void _checkChanges() {
    setState(() {
      _hasChanges = _statusDelaySeconds != _originalStatusDelaySeconds ||
          _vibrationEnabled != _originalVibrationEnabled ||
          _soundEnabled != _originalSoundEnabled ||
          _cameraDuplicateIntervalSeconds != _originalCameraDuplicateIntervalSeconds;
    });
  }

  Future<void> _saveSettings() async {
    await AppSettingsService.setStatusDelaySeconds(_statusDelaySeconds);
    await AppSettingsService.setVibrationEnabled(_vibrationEnabled);
    await AppSettingsService.setSoundEnabled(_soundEnabled);
    await AppSettingsService.setCameraDuplicateIntervalSeconds(_cameraDuplicateIntervalSeconds);
    setState(() {
      _originalStatusDelaySeconds = _statusDelaySeconds;
      _originalVibrationEnabled = _vibrationEnabled;
      _originalSoundEnabled = _soundEnabled;
      _originalCameraDuplicateIntervalSeconds = _cameraDuplicateIntervalSeconds;
      _hasChanges = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('設定已儲存'),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.green[700]
              : Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasChanges) {
          final shouldDiscard = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('尚未儲存'),
              content: const Text('您有未儲存的變更，確定要放棄嗎？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('放棄'),
                ),
              ],
            ),
          );
          if (shouldDiscard == true && mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '掃描設定',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '狀態顯示時間：$_statusDelaySeconds 秒',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Slider(
                      value: _statusDelaySeconds.toDouble(),
                      min: 0,
                      max: 5,
                      divisions: 5,
                      label: '$_statusDelaySeconds 秒',
                      onChanged: (value) {
                        setState(() {
                          _statusDelaySeconds = value.toInt();
                          _checkChanges();
                        });
                      },
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('掃描成功震動'),
                      subtitle: const Text('掃描成功時是否震動提示'),
                      value: _vibrationEnabled,
                      onChanged: (value) {
                        setState(() {
                          _vibrationEnabled = value;
                          _checkChanges();
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('掃描成功聲音（逼聲）'),
                      subtitle: const Text('掃描成功時是否播放提示音'),
                      value: _soundEnabled,
                      onChanged: (value) {
                        setState(() {
                          _soundEnabled = value;
                          _checkChanges();
                        });
                      },
                    ),
                    const Divider(),
                    Text(
                      '相機掃描重複判斷間隔：$_cameraDuplicateIntervalSeconds 秒',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '在設定時間內重複掃描不算重複，超過時間間隔後再次掃描才算重複',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    Slider(
                      value: _cameraDuplicateIntervalSeconds.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11, // (60-5)/5 = 11
                      label: '$_cameraDuplicateIntervalSeconds 秒',
                      onChanged: (value) {
                        setState(() {
                          _cameraDuplicateIntervalSeconds = value.toInt();
                          _checkChanges();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_hasChanges)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.orange[50],
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '您有未儲存的變更',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.orange[200]
                              : Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('儲存'),
                onPressed: _hasChanges ? _saveSettings : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _hasChanges 
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.primary
                          : Colors.blue)
                      : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// 時區資訊頁面（只讀顯示）
class TimezoneSettingsPage extends StatelessWidget {
  const TimezoneSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final timezone = TimezoneHelper.getCurrentTimezone();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '時區資訊',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.access_time),
                    title: const Text('顯示時區'),
                    subtitle: Text(
                      '${timezone.displayName} (Asia/Taipei)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    '系統內部時間一律以 UTC 儲存與運算',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '前端顯示與匯出資料均轉換為 UTC+8 (Asia/Taipei)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '系統時間已從國際標準時間伺服器同步',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 顯示模式設定頁面
class ThemeModeSettingsPage extends StatefulWidget {
  const ThemeModeSettingsPage({super.key});

  @override
  State<ThemeModeSettingsPage> createState() => _ThemeModeSettingsPageState();
}

class _ThemeModeSettingsPageState extends State<ThemeModeSettingsPage> {
  String? _selectedMode;
  String? _originalMode;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final mode = await AppSettingsService.getThemeMode();
    setState(() {
      _selectedMode = mode;
      _originalMode = mode;
      _hasChanges = false;
    });
  }

  Future<void> _saveThemeMode() async {
    if (_selectedMode != null) {
      await AppSettingsService.setThemeMode(_selectedMode!);
      setState(() {
        _originalMode = _selectedMode;
        _hasChanges = false;
      });
      
      // 通知主應用程式更新主題（返回 true 表示需要更新主題）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('設定已儲存'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.green[700]
              : Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        // 返回 true 通知主應用程式更新主題
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasChanges) {
          final shouldDiscard = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('尚未儲存'),
              content: const Text('您有未儲存的變更，確定要放棄嗎？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('放棄'),
                ),
              ],
            ),
          );
          if (shouldDiscard == true && mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '顯示模式',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioListTile<String>(
                      title: const Text('自動（建議）'),
                      subtitle: const Text('跟隨系統設定'),
                      value: 'auto',
                      groupValue: _selectedMode,
                      onChanged: (value) {
                        setState(() {
                          _selectedMode = value;
                          _hasChanges = _selectedMode != _originalMode;
                        });
                      },
                    ),
                    const Divider(),
                    RadioListTile<String>(
                      title: const Text('深色（高對比）'),
                      subtitle: const Text('深色背景，適合戶外強光環境'),
                      value: 'dark',
                      groupValue: _selectedMode,
                      onChanged: (value) {
                        setState(() {
                          _selectedMode = value;
                          _hasChanges = _selectedMode != _originalMode;
                        });
                      },
                    ),
                    const Divider(),
                    RadioListTile<String>(
                      title: const Text('淺色（室內）'),
                      subtitle: const Text('淺色背景，適合室內環境'),
                      value: 'light',
                      groupValue: _selectedMode,
                      onChanged: (value) {
                        setState(() {
                          _selectedMode = value;
                          _hasChanges = _selectedMode != _originalMode;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_hasChanges)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.orange[50],
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '您有未儲存的變更',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.orange[200]
                              : Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('儲存'),
                onPressed: _hasChanges ? _saveThemeMode : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _hasChanges 
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.primary
                          : Colors.blue)
                      : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// APP 資訊頁面（唯讀，不需要儲存）
class AppInfoPage extends StatefulWidget {
  const AppInfoPage({super.key});

  @override
  State<AppInfoPage> createState() => _AppInfoPageState();
}

class _AppInfoPageState extends State<AppInfoPage> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'APP 資訊',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('應用程式名稱'),
                    subtitle: const Text('出貨核對系統\nShipment Verification'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.business),
                    title: const Text('開發單位'),
                    subtitle: const Text('宜加寵物生活館'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('系統開發'),
                    subtitle: const Text('Bruce Yang'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.tag),
                    title: const Text('版本號'),
                    subtitle: const Text('v1.0.0'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.description),
                    title: const Text('說明'),
                    subtitle: const Text('公司內部出貨核對工具，\n用於掃描物流單號與出貨清單核對。'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 隱私政策頁面（唯讀，不需要儲存）
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '隱私政策',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '資料儲存',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 所有資料均儲存在裝置本地，不會上傳至任何伺服器\n• 掃描記錄僅儲存在本機 SQLite 資料庫\n• 匯出檔案儲存在裝置的 Documents 目錄',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '資料使用',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 本 App 僅用於掃描和比對物流單號\n• 不會收集或分享任何個人資料\n• 所有資料僅供使用者本地使用',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '資料保留',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 批次資料自動保留 7 天\n• 使用者可手動刪除資料\n• 匯出檔案由使用者自行管理',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 資料管理頁面
class DataManagementPage extends StatelessWidget {
  const DataManagementPage({super.key});

  Future<void> _clearAllData(BuildContext context) async {
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認清空資料'),
        content: const Text(
          '此操作將刪除所有批次資料、掃描記錄和匯出檔案。\n\n此操作無法復原，確定要繼續嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('確定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 顯示載入中
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      // 清空資料庫
      final batches = await DatabaseService.getAllBatches();
      for (final batch in batches) {
        await DatabaseService.deleteBatch(batch.id);
      }

      // 刪除匯出檔案
      final appDocDir = await getApplicationDocumentsDirectory();
      final reportsDir = Directory('${appDocDir.path}/reports');
      if (await reportsDir.exists()) {
        await reportsDir.delete(recursive: true);
      }

      // 關閉載入中
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('所有資料已清空'),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.green[700]
              : Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // 關閉載入中
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清空資料失敗：${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '資料管理',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.red.withOpacity(0.2)
                : Colors.red[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning, 
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.red[300]
                            : Colors.red[700],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '資料管理',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.red[300]
                              : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('清空所有資料'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () => _clearAllData(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '此操作將刪除所有批次、掃描記錄和匯出檔案',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
