import 'package:intl/intl.dart';
import 'dart:core';

String dateToString() {
  // 获取当前的 UTC 时间
  DateTime now = DateTime.now().toUtc();

  // 定义日期格式，不使用 Z，而是手动添加 GMT+0000
  DateFormat dateFormat = DateFormat(
      "EEE MMM dd yyyy HH:mm:ss 'GMT+0000' '(Coordinated Universal Time)'");

  // 格式化日期并返回
  return dateFormat.format(now);
}

void main() {
  // 测试函数
  //print(dateToString());
  // DateTime.now().toUtc().millisecondsSinceEpoch / 1000 + 0.0;
  print(DateTime.now().toUtc().microsecondsSinceEpoch / 1000000);
}
