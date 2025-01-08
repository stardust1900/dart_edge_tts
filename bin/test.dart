import 'dart:convert';
import 'dart:typed_data';

Iterable<Uint8List> splitTextByByteLength(String text, int byteLength) sync* {
  if (byteLength <= 0) {
    throw ArgumentError("byte_length 必须大于 0");
  }

  // 将字符串转换为 UTF-8 编码的字节列表
  List<int> encodedText = utf8.encode(text);

  while (encodedText.isNotEmpty) {
    int splitAt = byteLength;

    // 查找前 byteLength 个字节中的最后一个空格位置
    int lastSpace = encodedText.lastIndexOf(32, byteLength - 1);
    if (lastSpace >= 0 && lastSpace < byteLength) {
      splitAt = lastSpace;
    }
    print("length:${encodedText.length} splitAt:$splitAt");
    if (splitAt > encodedText.length) {
      splitAt = encodedText.length;
    }
    print("===length:${encodedText.length} splitAt:$splitAt");
    // 确保所有 & 都被终止符 ; 结束
    for (int i = splitAt - 1; i >= 0; i--) {
      if (encodedText[i] == 38 /* '&' */) {
        // 检查 & 和 splitAt 之间的子列表中是否包含 ;
        bool isTerminated = encodedText.sublist(i, splitAt).contains(59);
        if (!isTerminated) {
          splitAt = i - 1;
          if (splitAt < 0) {
            throw ArgumentError("最大字节长度太小或文本格式无效");
          }
          if (splitAt == 0) {
            break;
          }
        } else {
          break;
        }
      }
    }

    // 确保 splitAt 不会切断多字节字符
    while (splitAt > 0) {
      try {
        // 尝试解码以验证 splitAt 是否有效
        utf8.decode(encodedText.sublist(0, splitAt));
        break;
      } catch (e) {
        // 如果解码失败，向前调整 splitAt
        splitAt--;
        if (splitAt < 0) {
          throw ArgumentError("最大字节长度太小或文本格式无效");
        }
      }
    }

    // 提取并返回新的段落
    Uint8List newSegment = Uint8List.fromList(encodedText.sublist(0, splitAt));
    if (newSegment.isNotEmpty) {
      yield newSegment;
    }

    // 如果 splitAt 为 0，避免无限循环
    if (splitAt == 0) {
      splitAt = 1;
    }

    // 移除已处理的部分
    encodedText = encodedText.sublist(splitAt);
  }

  // 返回剩余的字节
  if (encodedText.isNotEmpty) {
    Uint8List remainingSegment = Uint8List.fromList(encodedText);
    if (remainingSegment.isNotEmpty) {
      yield remainingSegment;
    }
  }
}

void main() {
  String text = "这是一个需要分割的示例文本，它将被分成多个较小的部分。";
  int byteLength = 20;

  for (final segment in splitTextByByteLength(text, byteLength)) {
    print(utf8.decode(segment));
  }
}
