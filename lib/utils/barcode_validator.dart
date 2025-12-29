// 條碼驗證工具
class BarcodeValidator {
  // 驗證蝦皮物流格式：15字元，開頭"TW"
  static bool isValidShopeeLogistics(String barcode) {
    if (barcode.length != 15) {
      return false;
    }
    if (!barcode.startsWith('TW')) {
      return false;
    }
    return true;
  }
}

