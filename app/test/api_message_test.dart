import 'package:flutter_test/flutter_test.dart';
import 'package:miaolegemi/core/api_client.dart';

void main() {
  test('known server messages are localized to Chinese', () {
    expect(
      ApiException(20005, 'invalid username or password').userMessage,
      '用户名或密码错误',
    );
    expect(ApiException(30003, 'not found').userMessage, '记录不存在或已被删除');
    expect(
      ApiException(30007, 'only the owner can edit this pet').userMessage,
      '只有主人可以编辑宠物',
    );
  });

  test('unknown messages fall back to a neutral Chinese message', () {
    final message = ApiException(99999, 'something went wrong').userMessage;
    expect(message, '操作失败，请稍后重试');
    expect(RegExp(r'[A-Za-z]').hasMatch(message), isFalse);
  });

  test('code based fallback covers token errors', () {
    expect(
      ApiException(20002, 'invalid or revoked token').userMessage,
      '登录已失效，请重新登录',
    );
  });
}
