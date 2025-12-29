import 'package:flutter/material.dart';

// 輸入模式枚舉
enum InputMode {
  scanner, // 掃描槍模式（無按鈕，自動聚焦，掃描後自動送出）
  camera,  // 相機掃描模式（使用相機掃描條碼）
  manual,  // 手動輸入模式（顯示送出/清除按鈕）
}

extension InputModeExtension on InputMode {
  String get displayName {
    switch (this) {
      case InputMode.scanner:
        return '掃描槍';
      case InputMode.camera:
        return '相機';
      case InputMode.manual:
        return '手動輸入';
    }
  }

  IconData get icon {
    switch (this) {
      case InputMode.scanner:
        return Icons.qr_code_scanner;
      case InputMode.camera:
        return Icons.camera_alt;
      case InputMode.manual:
        return Icons.keyboard;
    }
  }
}

