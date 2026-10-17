import 'dart:convert';

import 'package:nest_fe/core/storage/secure_token_storage.dart';

/// One account the device has logged into. Holds its own token pair so switching never needs a
/// password again.
class SavedAccount {
  const SavedAccount({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String username;
  final String fullName;
  final String accessToken;
  final String refreshToken;

  SavedAccount withTokens(String access, String refresh) => SavedAccount(
        userId: userId,
        username: username,
        fullName: fullName,
        accessToken: access,
        refreshToken: refresh,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'username': username,
        'fullName': fullName,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        userId: json['userId'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String? ?? '',
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
      );
}

/// The device's list of logged-in accounts (Instagram-style multi-account), kept in secure
/// storage. [SecureTokenStorage]'s own access/refresh keys remain the *active* account's tokens -
/// the HTTP layer only ever reads those - so this store is purely the roster plus each account's
/// latest tokens.
class AccountStore {
  AccountStore._();

  static final AccountStore instance = AccountStore._();

  static const _accountsKey = 'nest.accounts';
  static const _activeKey = 'nest.activeAccountId';

  final _storage = SecureTokenStorage.instance;

  Future<List<SavedAccount>> all() async {
    final raw = await _storage.readKey(_accountsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => SavedAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> activeId() => _storage.readKey(_activeKey);

  Future<void> _save(List<SavedAccount> accounts) =>
      _storage.writeKey(_accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));

  /// Adds the account, or refreshes its tokens if it is already on the device, and makes it active.
  Future<void> upsertActive(SavedAccount account) async {
    final accounts = await all();
    final index = accounts.indexWhere((a) => a.userId == account.userId);
    if (index >= 0) {
      accounts[index] = account;
    } else {
      accounts.add(account);
    }
    await _save(accounts);
    await _storage.writeKey(_activeKey, account.userId);
  }

  Future<void> setActive(String userId) => _storage.writeKey(_activeKey, userId);

  /// Called when a silent token refresh rotates the active account's tokens, so the roster never
  /// holds a refresh token the server has already invalidated.
  Future<void> updateActiveTokens(String access, String refresh) async {
    final activeId = await this.activeId();
    if (activeId == null) return;
    final accounts = await all();
    final index = accounts.indexWhere((a) => a.userId == activeId);
    if (index < 0) return;
    accounts[index] = accounts[index].withTokens(access, refresh);
    await _save(accounts);
  }

  /// Removes [userId] from the device and returns whoever is left.
  Future<List<SavedAccount>> remove(String userId) async {
    final accounts = (await all()).where((a) => a.userId != userId).toList();
    await _save(accounts);
    return accounts;
  }
}
