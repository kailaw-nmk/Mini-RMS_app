# Tailscale 常時接続通話アプリ — 仕様書

**プロジェクト名**: TailCall（仮称）
**バージョン**: v0.2.0（MVP）— レビュー反映改訂版
**作成日**: 2026-03-28
**改訂日**: 2026-03-28
**対象**: 個人開発・プロトタイプ

---

## 改訂履歴

| バージョン | 日付 | 変更内容 |
|-----------|------|---------|
| v0.1.0 | 2026-03-28 | 初版作成 |
| v0.2.0 | 2026-03-28 | レビュー反映改訂。主要変更: デフォルト音声優先化、Android Foreground Service必須化、iOS CallKit/PushKit別設計、PeerConnection再生成戦略追加、通信品質メトリクス導入、シグナリング障害対策、認証設計追加、ログ設計追加、開発計画6〜10週に修正 |

---

## 1. プロジェクト概要

### 1.1 背景と課題

トラック運転業務において、ドライバーと管制オペレーターが常時通話で接続される必要がある。既存のMicrosoft Teamsでは、スマートフォンが圏外になった際にセッションが切断され、手動で再接続する必要があり、運転中のドライバーにとって安全上の問題がある。

### 1.2 プロダクトビジョン

Tailscale VPN上で動作し、ネットワーク断→復帰時にセッションを自動リジュームする常時通話アプリを構築する。デフォルトは音声通話とし、必要時のみビデオを有効化する設計とする。

### 1.3 設計原則

1. **音声優先**: デフォルトは音声のみ。帯域・熱・バッテリーの制約を最小化する
2. **OS制約の尊重**: Android/iOSのバックグラウンド制約に正面から対処する
3. **段階的フォールバック**: 一つの手段が失敗しても次の手段に自動移行する
4. **Tailscale依存の緩和**: Tailscaleの状態だけに頼らず、実通信の品質で判断する

### 1.4 ユースケース

| 項目 | 内容 |
|------|------|
| 利用者A | トラックドライバー（スマートフォン） |
| 利用者B | 管制オペレーター（スマートフォン or PC） |
| 利用形態 | 1対1の常時音声通話（必要時ビデオ追加） |
| 通話時間 | 数時間〜終日の連続接続 |
| ネットワーク | LTE/5G（トンネル・山間部で頻繁に圏外） |

---

## 2. 機能要件

### 2.1 MVP（Phase 1）

#### F-001: 音声通話（デフォルトモード）

- Tailscale VPN上の2端末間でWebRTC P2P音声通話を確立する
- コーデック: Opus（以下の最適化設定を適用）
  - ビットレート: 24kbps（通常） / 16kbps（低帯域時）
  - FEC（Forward Error Correction）: 有効
  - DTX（Discontinuous Transmission）: 有効（無音区間で帯域節約）
  - パケットロス耐性: 20%まで音声品質維持
- 遅延目標: 300ms以下

#### F-002: 自動リコネクト（最重要機能）

- ネットワーク断を検知後、セッションを破棄せず「RECONNECTING」状態に遷移する
- 指数バックオフで再接続を試行する（0.5s → 1s → 2s → 4s → ... → 最大30s間隔）
- ネットワーク復帰をOS・Tailscale・WebRTC ICE・RTP/RTCPの4層で検知する
- 復帰検知後、ICE Restartを第一手段として試行する
- ICE Restartが2回連続失敗した場合、PeerConnectionの完全再生成にフォールバックする
- ドライバー側の操作は一切不要とする

#### F-003: 接続状態の表示

- 画面上に接続状態をリアルタイム表示する
  - 🟢 CONNECTED（接続中）— 通信品質インジケーター付き
  - 🟡 RECONNECTING_NETWORK（再接続中・圏外）— 「電波を探しています」
  - 🟡 RECONNECTING_PEER（再接続中・相手未接続）— 「相手の接続を待っています」
  - 🟠 SUSPENDED（長時間切断・自動復帰待ち）— 「接続待機中」
  - ⚪ DISCONNECTED（セッション終了）

#### F-004: セッション管理

- セッションをサーバー側で永続化し、両端末の再起動後もリジュームを可能にする
- クライアント側にもセッション情報をキャッシュし、シグナリングサーバー障害時にも復帰可能にする
- セッションTTL: 30分（運行スケジュールに応じて設定変更可能）

#### F-005: 通話の開始と終了

- 管制オペレーターがドライバーを呼び出す（管制→ドライバー方向のみ）
- 通常の通話終了は管制オペレーター側のみ可能とする（ドライバーの誤操作防止）
- ドライバー側に緊急終了機能を設ける（終了ボタン3秒長押し→確認ダイアログ→終了）

#### F-006: デバイス認証（v0.1からの追加）

- Tailscale IPのみに依存せず、JWT（JSON Web Token）ベースのデバイス認証を導入する
- 初回ペアリング時にデバイストークンを発行し、以降のセッション確立に使用する
- トークン有効期限: 30日（自動更新）

### 2.2 Phase 2

#### F-101: オンデマンドビデオ

- 音声通話中に管制オペレーターがビデオを有効化できる
- ドライバー側はビデオ有効化リクエストを自動承認する（操作不要設定可）
- コーデック: VP8 or H.264（端末サポートに応じて自動選択）
- ネットワーク復帰時はまず音声で再接続し、帯域安定後にビデオを追加する

#### F-102: 帯域・品質適応制御

- 以下のメトリクスを総合判断して品質を動的に調整する
  - RTT（Round Trip Time）
  - Jitter（パケット到着間隔のばらつき）
  - Packet Loss（パケットロス率）
  - 利用可能帯域

| 品質レベル | 条件 | 動作 |
|-----------|------|------|
| EXCELLENT | RTT<100ms, Loss<1%, BW>2Mbps | 720p/30fps + 高品質音声 |
| GOOD | RTT<200ms, Loss<3%, BW>500Kbps | 480p/15fps + 通常音声 |
| FAIR | RTT<500ms, Loss<10%, BW>100Kbps | 音声のみ（Opus 24kbps） |
| POOR | RTT>500ms or Loss>10% | 音声のみ（Opus 16kbps + FEC強化） |
| CRITICAL | 通信断 | RECONNECTING状態へ遷移 |

#### F-103: 熱管理（v0.1からの追加）

- 端末温度を監視し、サーマルスロットリングを事前回避する
  - 温度「警告」: ビデオを自動OFF（音声のみに切替）
  - 温度「危険」: Opus を16kbpsに下げ、画面輝度を下げる
- 管制側に温度警告を通知する

#### F-104: オフライン音声メモ

- 圏外中にドライバーが音声メモを録音できる
- ネットワーク復帰後、管制オペレーターに自動送信する

### 2.3 Phase 3

#### F-201: 管制ダッシュボード

- 複数ドライバーの接続状態を一覧表示する
- ドライバー選択→通話開始の操作フロー
- 各ドライバーの通信品質インジケーター表示

#### F-202: 通話ログ・運用ログ

- 通話開始/終了/切断/復帰のタイムスタンプを記録する
- 切断回数・累積切断時間のレポート
- 接続状態遷移ログ、ICEイベントログ、RTT/Loss履歴の永続保存

#### F-203: アラート通知

- 切断が5分以上続いた場合、管制オペレーターにプッシュ通知する
- 端末温度が危険レベルの場合に通知する

---

## 3. 非機能要件

### 3.1 パフォーマンス

| 指標 | 目標値 |
|------|--------|
| 音声遅延 | 300ms以下 |
| 映像遅延 | 500ms以下 |
| リコネクト所要時間（ICE Restart成功時） | ネットワーク復帰後3秒以内 |
| リコネクト所要時間（PeerConnection再生成時） | ネットワーク復帰後8秒以内 |
| 同時セッション数 | MVP: 1セッション / 将来: 20セッション |

### 3.2 可用性

- シグナリングサーバー: 99%稼働（個人運用の現実的な目標）
- P2P通話はシグナリングサーバーがダウンしていても既存セッションは継続する
- シグナリングサーバーダウン中の再接続: クライアント側セッションキャッシュで対応

### 3.3 セキュリティ

- 通信はすべてTailscale WireGuardトンネル上で暗号化される
- シグナリングサーバーはTailscale網内のみに公開（インターネット非公開）
- WebRTC DTLSによるメディア暗号化
- JWTベースのデバイス認証（Tailscale IPのみに依存しない）

### 3.4 バッテリー消費

- Android: Foreground Serviceで安定動作（通知バーに常駐）
- iOS: CallKit + PushKit による省電力設計
- リコネクト中の指数バックオフにより無駄なポーリングを抑制する
- 長時間切断（5分超）時はSUSPENDED状態に移行し、OSのネットワーク復帰コールバックをトリガーにする
- 音声優先設計により、Teamsのビデオ通話比でバッテリー消費を大幅に削減
- 目標: 8時間連続音声通話で端末バッテリー残量30%以上（車載充電なしの場合）

### 3.5 対応環境

| プラットフォーム | 最低要件 |
|------------------|----------|
| Android | 10以上（Foreground Service対応） |
| iOS | 16以上（CallKit + PushKit対応） |
| Web（管制用） | Chrome 100+ / Safari 16+ |

---

## 4. システムアーキテクチャ

### 4.1 全体構成図

```
┌──────────────────────────────────────────────────┐
│                  Tailscale Network                │
│                                                   │
│  ┌──────────────┐         ┌───────────────┐      │
│  │  ドライバー    │         │  管制オペレーター │      │
│  │  スマートフォン │         │  スマホ / PC   │      │
│  │  100.64.0.12  │         │  100.64.0.5   │      │
│  │               │         │               │      │
│  │ ┌───────────┐│         │┌────────────┐ │      │
│  │ │Foreground ││         ││ CallKit/   │ │      │
│  │ │Service    ││         ││ Web Client │ │      │
│  │ │(Android)  ││         │└────────────┘ │      │
│  │ │ / CallKit ││         │               │      │
│  │ │(iOS)      ││         │               │      │
│  │ └───────────┘│         │               │      │
│  └──────┬───────┘         └──────┬────────┘      │
│         │                        │               │
│         │    WebRTC P2P          │               │
│         │◄──────────────────────►│               │
│         │   (音声 / 必要時ビデオ)  │               │
│         │                        │               │
│         │    WebSocket           │               │
│         ▼                        ▼               │
│  ┌─────────────────────────────────────┐         │
│  │      シグナリングサーバー              │         │
│  │      100.64.0.50                    │         │
│  │  ┌──────────┐ ┌───────┐ ┌───────┐  │         │
│  │  │WS Server │ │ Redis │ │ JWT   │  │         │
│  │  │(Node.js) │ │(Cache)│ │ Auth  │  │         │
│  │  └──────────┘ └───────┘ └───────┘  │         │
│  └─────────────────────────────────────┘         │
│                                                   │
│  ┌──────────────────────────┐                    │
│  │  クライアント側キャッシュ    │ ← シグナリング     │
│  │  (セッション情報の          │   障害時の          │
│  │   ローカル保持)             │   フォールバック     │
│  └──────────────────────────┘                    │
└──────────────────────────────────────────────────┘
```

### 4.2 コンポーネント一覧

| コンポーネント | 技術 | 役割 |
|----------------|------|------|
| モバイルアプリ | Flutter + flutter_webrtc | UI・WebRTC・状態管理 |
| Android常駐 | Foreground Service + PARTIAL_WAKE_LOCK | バックグラウンド通信維持 |
| iOS常駐 | CallKit + PushKit | OS連携の通話維持 |
| シグナリングサーバー | Node.js + ws | SDP/ICE候補の交換 |
| セッションストア | Redis | セッション永続化 |
| 認証 | JWT（jsonwebtoken） | デバイス認証 |
| VPN | Tailscale（各端末にインストール） | 暗号化ネットワーク |

### 4.3 通信プロトコル

```
[アプリ] ──WebSocket──→ [シグナリングサーバー]  : SDP Offer/Answer, ICE候補, 認証
[アプリ] ◄──WebRTC P2P──► [アプリ]              : 音声（/映像）ストリーム
[アプリ] ──HTTP──→ [Tailscale Local API]        : 接続状態の監視
[アプリ] ──内部──→ [RTP/RTCP Stats]             : 通信品質メトリクス収集
```

---

## 5. モバイルOS対策 詳細設計（v0.2 新規セクション）

### 5.1 Android: Foreground Service設計

Android 10以降ではバックグラウンドアプリの通信がDozeモードにより制限される。音声通話を維持するにはForeground Serviceが必須。

#### 実装要件

```
AndroidManifest.xml:
  - <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  - <uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL" />
  - <uses-permission android:name="android.permission.WAKE_LOCK" />
  - <service android:foregroundServiceType="phoneCall" />

Foreground Service:
  - 通話開始時にForeground Serviceを起動
  - 通知バーに常駐表示（「TailCall — 管制と接続中」）
  - PARTIAL_WAKE_LOCKでCPUスリープ防止
  - 通話終了時にService停止

バッテリー最適化除外:
  - 初回起動時にユーザーへ設定案内ダイアログを表示
  - REQUEST_IGNORE_BATTERY_OPTIMIZATIONS で直接リクエスト
  - 設定されていない場合は通話開始時に警告表示
```

#### 通知チャネル設計

```
通知チャネル: "tailcall_active_call"
  - 優先度: IMPORTANCE_LOW（音を鳴らさない）
  - 内容: 接続状態のリアルタイム表示
    - 🟢 「管制と接続中 — 00:45:12」
    - 🟡 「再接続中... — 圏外 01:23」
    - 🟠 「接続待機中 — 復帰まで待機します」
```

### 5.2 iOS: CallKit + PushKit設計

iOSではバックグラウンドでの常時接続は原則不可能。VoIPアプリとしてCallKit + PushKitを活用し、OS標準の通話UIと統合する。

#### アーキテクチャ

```
[通常時]
  アプリがフォアグラウンド → 通常のWebRTC音声通話

[バックグラウンド移行時]
  CallKit で通話セッション登録
  → iOS標準の通話画面に統合
  → 音声処理はOSが維持

[アプリ終了/強制終了時]
  PushKit VoIP Push で再起動
  → シグナリングサーバーからPush送信
  → アプリ再起動 + 自動リジューム
```

#### PushKit連携フロー

```
1. ドライバーのアプリがバックグラウンドで通信断を検知
2. シグナリングサーバーがドライバーのPushKit tokenに通知送信
3. iOS がアプリを再起動（バックグラウンドで30秒の実行猶予）
4. アプリがセッションキャッシュからリジューム
5. CallKit で通話を再表示
```

#### 制約事項

- PushKit VoIP Pushを送るにはAPNs（Apple Push Notification service）連携が必要
- Apple Developer Programへの登録必須（年額¥15,000）
- PushKit利用にはCallKitとの統合が必須（Apple審査要件）
- バックグラウンド実行時間は30秒に限定されるため、その間にリコネクトを完了する必要がある

### 5.3 プラットフォーム差異の整理

| 項目 | Android | iOS |
|------|---------|-----|
| バックグラウンド維持 | Foreground Service | CallKit統合 |
| スリープ対策 | PARTIAL_WAKE_LOCK | CallKit管理 |
| 圏外からの復帰 | ネットワークコールバック | PushKit VoIP Push |
| バッテリー最適化 | 除外設定が必要 | CallKitが自動管理 |
| 通話UI | アプリ独自UI | iOS標準通話UI + アプリUI |
| 実装難度 | 中 | 高 |

---

## 6. 自動リコネクト 詳細設計（v0.2 改訂）

### 6.1 状態遷移図

```
                    ┌─────────────┐
          通話開始 → │  CONNECTED  │
                    └──────┬──────┘
                           │
                    ネットワーク断検知
                    (4層検知のいずれか)
                           │
                    ┌──────┴──────┐
                    │             │
        ┌───────────▼──┐  ┌──────▼──────────┐
        │ RECONNECTING │  │ RECONNECTING    │
        │ _NETWORK     │  │ _PEER           │
        │ (自端末圏外)  │  │ (相手側未接続)   │
        └───────┬──────┘  └──────┬───────────┘
                │                │
                └───────┬────────┘
                        │
              ┌─────────▼─────────┐
              │  再接続試行        │
              │                   │
              │  Step 1: ICE Restart (最大2回) │
              │    ↓ 失敗                      │
              │  Step 2: PeerConnection再生成  │
              │    ↓ 失敗                      │
              │  Step 3: 指数バックオフ待機     │
              │    → Step 1に戻る              │
              └─────────┬─────────┘
                        │
                  ┌─────┴─────┐
                  │           │
                成功        5分経過
                  │           │
                  ▼           ▼
           ┌──────────┐ ┌───────────┐
           │CONNECTED │ │ SUSPENDED │
           └──────────┘ └─────┬─────┘
                              │
                        ネットワーク復帰
                        (OSコールバック /
                         PushKit Push)
                              │
                              ▼
                       再接続試行 → CONNECTED

                        30分経過
                              │
                              ▼
                       ┌──────────────┐
                       │ DISCONNECTED │
                       └──────────────┘
```

### 6.2 4層検知システム（v0.1の3層から拡張）

#### Layer 1: OS ネットワーク状態

```dart
// Flutter: connectivity_plus パッケージ
Connectivity().onConnectivityChanged.listen((result) {
  if (result == ConnectivityResult.none) {
    transitionTo(ConnectionState.reconnectingNetwork);
  } else {
    attemptReconnect();
  }
});
```

#### Layer 2: Tailscale ピア状態

```dart
// Tailscale Local API (127.0.0.1:41112)
// peer.online == true でも通信可能とは限らない → Layer 4と併用
Timer.periodic(Duration(seconds: 5), (_) async {
  final status = await getTailscaleStatus();
  final peerOnline = status.peers[targetIP]?.online ?? false;
  if (!peerOnline) {
    transitionTo(ConnectionState.reconnectingPeer);
  }
});
```

#### Layer 3: WebRTC ICE 接続状態

```dart
peerConnection.onIceConnectionState = (state) {
  switch (state) {
    case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
      startReconnectTimer();
      break;
    case RTCIceConnectionState.RTCIceConnectionStateFailed:
      performReconnectStrategy(); // ICE Restart → PC再生成の段階的試行
      break;
    case RTCIceConnectionState.RTCIceConnectionStateConnected:
      transitionTo(ConnectionState.connected);
      break;
  }
};
```

#### Layer 4: RTP/RTCP 通信品質メトリクス（v0.2 新規追加）

```dart
// WebRTC getStats() で実通信の品質を監視
// Tailscale peer.online だけでは通信可能かわからないため必須
Timer.periodic(Duration(seconds: 2), (_) async {
  final stats = await peerConnection.getStats();
  final metrics = extractMediaMetrics(stats);

  // RTT, PacketLoss, Jitter の総合判定
  final quality = assessQuality(
    rtt: metrics.rtt,
    packetLoss: metrics.packetLoss,
    jitter: metrics.jitter,
  );

  if (quality == QualityLevel.critical) {
    // 通信は接続状態だが品質が致命的に悪い
    // → UIに品質警告表示 + 品質改善待ち
    showQualityWarning();
  }

  // RTPパケットが一定期間届かない場合は実質切断と判断
  if (metrics.lastPacketReceivedAge > Duration(seconds: 5)) {
    transitionTo(ConnectionState.reconnectingNetwork);
  }
});
```

#### 4層の統合判定ロジック

```
判定優先度:
  1. Layer 4 (RTP/RTCP) — 実通信の真の状態を反映
  2. Layer 3 (ICE)      — WebRTCレベルの接続状態
  3. Layer 1 (OS)       — ネットワーク有無の大枠
  4. Layer 2 (Tailscale) — ピアの存在確認（参考情報）

例:
  - OS=online, Tailscale=peer.online, ICE=connected, RTP=パケットロス50%
    → CONNECTED だが品質警告表示（Layer 4が実態を反映）

  - OS=online, Tailscale=peer.online, ICE=connected, RTP=5秒間パケットなし
    → RECONNECTING_NETWORK（Layer 4で実質切断と判定）

  - OS=offline
    → RECONNECTING_NETWORK（Layer 1で即判定、他レイヤー確認不要）
```

### 6.3 再接続戦略（v0.2 改訂：段階的フォールバック）

#### Strategy 1: ICE Restart（第一手段）

```dart
Future<bool> attemptIceRestart() async {
  final offer = await peerConnection.createOffer({
    'iceRestart': true,
  });
  await peerConnection.setLocalDescription(offer);
  await sendOfferViaSignaling(offer);
  // 5秒以内にICE connectedにならなければ失敗
  return await waitForIceConnected(timeout: Duration(seconds: 5));
}
```

適用条件: ネットワーク復帰後の最初の試行。軽量で高速。

#### Strategy 2: PeerConnection 完全再生成（第二手段）

```dart
Future<bool> attemptFullReconnect() async {
  // 1. 既存のメディアストリームを保持
  final localStream = existingLocalStream;

  // 2. 古いPeerConnectionを破棄
  await peerConnection.close();

  // 3. 新しいPeerConnectionを生成
  peerConnection = await createPeerConnection(rtcConfig);

  // 4. メディアストリームを再アタッチ
  localStream.getTracks().forEach((track) {
    peerConnection.addTrack(track, localStream);
  });

  // 5. 完全なSDP交換をやり直す
  final offer = await peerConnection.createOffer();
  await peerConnection.setLocalDescription(offer);
  await sendOfferViaSignaling(offer);
  return await waitForIceConnected(timeout: Duration(seconds: 10));
}
```

適用条件: ICE Restartが2回連続失敗した場合。または端末のIPアドレスが変わった場合（WiFi↔LTE切替時など）。

#### IPアドレス変更の検知

```dart
// ネットワーク切替時にローカルIPを比較
String? _lastLocalIP;

void onNetworkChanged() async {
  final currentIP = await getLocalTailscaleIP();
  if (_lastLocalIP != null && currentIP != _lastLocalIP) {
    // IP変更を検知 → ICE Restartをスキップし直接PC再生成
    log('IP changed: $_lastLocalIP → $currentIP');
    await attemptFullReconnect();
  }
  _lastLocalIP = currentIP;
}
```

#### 再接続フロー全体

```
1. 切断検知（4層のいずれか）
   └→ 状態をRECONNECTING_NETWORK or RECONNECTING_PEERに遷移
   └→ UIに状態表示
   └→ ice_restart_fail_count = 0

2. ネットワーク復帰待ち
   └→ OS/Tailscaleのコールバックを待機
   └→ 指数バックオフで定期チェック（0.5s→1s→2s→...→30s）

3. ネットワーク復帰検知
   ├→ IPアドレスが変わっている → Step 5へ（PC再生成）
   └→ IPアドレスが同じ → Step 4へ（ICE Restart）

4. ICE Restart試行
   ├→ 成功 → CONNECTED
   └→ 失敗 → ice_restart_fail_count++
       ├→ 2回未満 → 2秒待機 → Step 4へ
       └→ 2回以上 → Step 5へ

5. PeerConnection再生成
   ├→ 成功 → CONNECTED
   └→ 失敗 → 指数バックオフ待機 → Step 3へ

6. 5分経過（リトライ継続中）
   └→ SUSPENDED に遷移
   └→ リトライ間隔を30s固定
   └→ Android: Foreground Serviceは維持
   └→ iOS: PushKit Push待ちに切替

7. 30分経過（設定変更可能）
   └→ DISCONNECTED に遷移
   └→ セッション終了
   └→ 管制オペレーターに通知
```

### 6.4 シグナリングサーバー障害時のフォールバック（v0.2 新規追加）

```
[通常時]
  クライアント → WebSocket → シグナリングサーバー → Redis
                                                    ↓
  クライアントローカルにもセッション情報をキャッシュ

[シグナリングサーバー障害時]
  1. WebSocket切断を検知
  2. 指数バックオフでWebSocket再接続を試行
  3. 既存のP2P通話は影響なし（シグナリング不要で継続）
  4. 通話切断→復帰が発生した場合:
     a. ローカルキャッシュからセッション情報を取得
     b. Tailscale IP宛に直接シグナリング（HTTP POST）を試行
        - 相手アプリに簡易HTTPエンドポイントを内蔵
        - SDP交換をP2P直接通信で実施
     c. 成功 → 通話再開
     d. 失敗 → シグナリングサーバー復帰まで待機

[サーバー復帰後]
  5. WebSocket再接続
  6. ローカルキャッシュとRedisのセッション状態を同期
```

#### クライアント側セッションキャッシュ

```dart
// SharedPreferences（軽量）またはSQLiteに保存
class SessionCache {
  Future<void> save(SessionInfo session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_session', jsonEncode({
      'session_id': session.id,
      'peer_tailscale_ip': session.peerIP,
      'last_sdp_offer': session.lastSdpOffer,
      'last_sdp_answer': session.lastSdpAnswer,
      'device_token': session.deviceToken,
      'cached_at': DateTime.now().toIso8601String(),
    }));
  }

  Future<SessionInfo?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('cached_session');
    if (json == null) return null;
    final data = jsonDecode(json);
    // キャッシュが30分以上前なら無効
    final cachedAt = DateTime.parse(data['cached_at']);
    if (DateTime.now().difference(cachedAt) > Duration(minutes: 30)) {
      return null;
    }
    return SessionInfo.fromJson(data);
  }
}
```

---

## 7. 通信品質メトリクス設計（v0.2 新規セクション）

### 7.1 収集メトリクス

```dart
class MediaMetrics {
  final double rtt;              // Round Trip Time (ms)
  final double jitter;           // パケット到着間隔のばらつき (ms)
  final double packetLoss;       // パケットロス率 (0.0〜1.0)
  final int availableBandwidth;  // 推定利用可能帯域 (bps)
  final Duration lastPacketReceivedAge; // 最後のパケット受信からの経過時間
  final int nackCount;           // NACKリクエスト数（映像品質指標）
  final int firCount;            // FIRリクエスト数（キーフレーム要求）
}
```

### 7.2 品質レベル判定

```dart
enum QualityLevel { excellent, good, fair, poor, critical }

QualityLevel assessQuality(MediaMetrics m) {
  // パケットが5秒以上届いていない → 実質切断
  if (m.lastPacketReceivedAge > Duration(seconds: 5)) {
    return QualityLevel.critical;
  }

  // 総合スコア計算（重み付き）
  double score = 0;
  score += (m.rtt < 100) ? 3 : (m.rtt < 200) ? 2 : (m.rtt < 500) ? 1 : 0;
  score += (m.packetLoss < 0.01) ? 3 : (m.packetLoss < 0.05) ? 2 : (m.packetLoss < 0.1) ? 1 : 0;
  score += (m.jitter < 30) ? 2 : (m.jitter < 100) ? 1 : 0;

  if (score >= 7) return QualityLevel.excellent;
  if (score >= 5) return QualityLevel.good;
  if (score >= 3) return QualityLevel.fair;
  return QualityLevel.poor;
}
```

### 7.3 品質に基づく自動制御

```
EXCELLENT → ビデオ有効化を許可、Opus 32kbps
GOOD      → ビデオ有効（品質制限付き）、Opus 24kbps
FAIR      → ビデオ自動OFF、Opus 24kbps、FEC強化
POOR      → 音声のみ、Opus 16kbps、FEC最大、DTX有効
CRITICAL  → RECONNECTING状態へ遷移
```

---

## 8. 認証設計（v0.2 新規セクション）

### 8.1 デバイス認証フロー

```
[初回ペアリング]
  1. 管制オペレーターがシグナリングサーバーでペアリングコードを生成
     → 6桁の一時コード（有効期限5分）
  2. ドライバーがアプリにペアリングコードを入力
  3. サーバーがデバイス情報を検証し、JWTを発行
     - payload: { device_id, tailscale_ip, role, exp }
     - 有効期限: 30日
  4. JWTをクライアントのSecure Storageに保存

[通常接続時]
  1. WebSocket接続時にJWTをヘッダーに含める
  2. サーバーがJWT検証 → セッション開始を許可
  3. 有効期限が7日以内の場合、新しいJWTを自動発行（リフレッシュ）

[トークン失効時]
  1. サーバーが401を返す
  2. アプリがペアリング画面を表示
  3. 再ペアリングで新トークン取得
```

### 8.2 セキュリティ考慮事項

- JWT署名鍵はシグナリングサーバー上で管理（環境変数）
- Tailscale網内のみで通信するため、トークン漏洩リスクは低い
- デバイスが盗難された場合: 管制側からトークンを無効化可能にする

---

## 9. ログ設計（v0.2 新規セクション）

### 9.1 ログレベルと保存先

| ログ種別 | 保存先 | 保持期間 | 用途 |
|---------|--------|---------|------|
| 接続状態遷移 | ローカルDB + サーバーRedis | 30日 | 運用レポート |
| ICEイベント | ローカルDB | 7日 | デバッグ |
| RTP/RTCP メトリクス | ローカルDB（5秒間隔サンプリング） | 3日 | 品質分析 |
| エラーログ | ローカルDB + サーバー | 30日 | 障害対応 |
| 通話開始/終了 | サーバーRedis | 90日 | 業務記録 |

### 9.2 ログスキーマ

```json
// 接続状態遷移ログ
{
  "timestamp": "2026-03-28T09:15:30.123Z",
  "session_id": "sess_20260328_001",
  "device_id": "driver_truck042",
  "event": "state_change",
  "from_state": "RECONNECTING_NETWORK",
  "to_state": "CONNECTED",
  "reconnect_method": "ice_restart",
  "reconnect_duration_ms": 2340,
  "retry_count": 2
}

// 通信品質ログ（5秒間隔）
{
  "timestamp": "2026-03-28T09:15:30.123Z",
  "session_id": "sess_20260328_001",
  "rtt_ms": 145,
  "jitter_ms": 23,
  "packet_loss": 0.02,
  "bandwidth_bps": 1200000,
  "quality_level": "GOOD",
  "audio_codec": "opus",
  "audio_bitrate": 24000
}
```

### 9.3 デバッグ支援

- 管制ダッシュボードからドライバー端末のログをリモート取得する機能（Phase 3）
- 接続障害発生時にログを自動エクスポートし、管制に送信する機能

---

## 10. シグナリングプロトコル

### 10.1 メッセージ形式（JSON over WebSocket）

#### 認証付き接続（v0.2追加）

```json
// WebSocket接続時の最初のメッセージ
{
  "type": "auth",
  "device_token": "eyJhbGciOiJIUzI1NiIs...",
  "device_id": "driver_truck042",
  "session_resume_id": "sess_20260328_001"
}
```

#### 認証応答

```json
{
  "type": "auth_result",
  "success": true,
  "session_resumed": true,
  "session_id": "sess_20260328_001"
}
```

#### 通話開始

```json
{
  "type": "call_initiate",
  "session_id": "sess_20260328_001",
  "from": "100.64.0.5",
  "to": "100.64.0.12",
  "mode": "audio",
  "timestamp": "2026-03-28T09:00:00Z"
}
```

#### SDP Offer / Answer

```json
{
  "type": "sdp_offer",
  "session_id": "sess_20260328_001",
  "sdp": "v=0\r\no=- ...",
  "ice_restart": false,
  "reconnect_strategy": "ice_restart"
}
```

```json
{
  "type": "sdp_answer",
  "session_id": "sess_20260328_001",
  "sdp": "v=0\r\no=- ..."
}
```

#### ICE Candidate

```json
{
  "type": "ice_candidate",
  "session_id": "sess_20260328_001",
  "candidate": {
    "candidate": "candidate:1 1 UDP ...",
    "sdpMid": "0",
    "sdpMLineIndex": 0
  }
}
```

#### ICE Restart要求（v0.2改訂: strategy追加）

```json
{
  "type": "ice_restart",
  "session_id": "sess_20260328_001",
  "reason": "network_recovery",
  "strategy": "ice_restart",
  "retry_count": 1,
  "ip_changed": false
}
```

#### PeerConnection再生成要求（v0.2 新規）

```json
{
  "type": "pc_recreate",
  "session_id": "sess_20260328_001",
  "reason": "ice_restart_failed_twice",
  "new_sdp_offer": "v=0\r\no=- ..."
}
```

#### 状態通知（v0.2改訂: メトリクス追加）

```json
{
  "type": "state_change",
  "session_id": "sess_20260328_001",
  "from_state": "RECONNECTING_NETWORK",
  "to_state": "CONNECTED",
  "reconnect_method": "pc_recreate",
  "metrics": {
    "rtt_ms": 145,
    "packet_loss": 0.02,
    "quality_level": "GOOD"
  },
  "timestamp": "2026-03-28T09:15:30Z"
}
```

#### ビデオ有効化リクエスト（v0.2 新規）

```json
{
  "type": "video_request",
  "session_id": "sess_20260328_001",
  "action": "enable",
  "requested_by": "operator"
}
```

#### 通話終了

```json
{
  "type": "call_end",
  "session_id": "sess_20260328_001",
  "reason": "operator_hangup",
  "timestamp": "2026-03-28T17:00:00Z"
}
```

### 10.2 Redisセッションスキーマ（v0.2改訂）

```json
// Key: session:{session_id}
// TTL: 1800秒（30分、設定変更可能）
{
  "session_id": "sess_20260328_001",
  "driver_device_id": "driver_truck042",
  "driver_ip": "100.64.0.12",
  "operator_device_id": "operator_hq01",
  "operator_ip": "100.64.0.5",
  "state": "CONNECTED",
  "mode": "audio",
  "created_at": "2026-03-28T09:00:00Z",
  "last_connected_at": "2026-03-28T09:15:30Z",
  "disconnect_count": 3,
  "total_disconnect_seconds": 185,
  "last_reconnect_method": "pc_recreate",
  "last_sdp_offer": "v=0\r\no=- ...",
  "last_sdp_answer": "v=0\r\no=- ...",
  "last_metrics": {
    "rtt_ms": 145,
    "packet_loss": 0.02,
    "quality_level": "GOOD"
  }
}
```

---

## 11. Opus音声コーデック最適化設定（v0.2 新規セクション）

### 11.1 SDP設定

```
// SDP内のOpusパラメータ
a=fmtp:111 minptime=10;useinbandfec=1;usedtx=1;maxaveragebitrate=24000

パラメータ説明:
  useinbandfec=1  — FEC有効化（パケットロス時の音声品質維持）
  usedtx=1        — DTX有効化（無音区間で帯域節約）
  maxaveragebitrate=24000 — 通常時24kbps
```

### 11.2 品質レベル別設定

| 品質レベル | ビットレート | FEC | DTX | ptime |
|-----------|------------|-----|-----|-------|
| EXCELLENT | 32kbps | ON | OFF | 20ms |
| GOOD | 24kbps | ON | ON | 20ms |
| FAIR | 24kbps | ON（強化） | ON | 40ms |
| POOR | 16kbps | ON（最大） | ON | 60ms |

### 11.3 動的ビットレート制御

```dart
void adjustAudioQuality(QualityLevel level) {
  final sender = peerConnection.senders
      .firstWhere((s) => s.track?.kind == 'audio');
  final params = sender.parameters;

  switch (level) {
    case QualityLevel.excellent:
      params.encodings[0].maxBitrate = 32000;
      break;
    case QualityLevel.good:
      params.encodings[0].maxBitrate = 24000;
      break;
    case QualityLevel.fair:
    case QualityLevel.poor:
      params.encodings[0].maxBitrate = 16000;
      break;
  }

  sender.setParameters(params);
}
```

---

## 12. UI設計（v0.2 改訂）

### 12.1 ドライバー画面（音声デフォルト）

```
┌─────────────────────────┐
│ 🟢 接続中  00:45:12      │  ← ステータスバー
│ ████████░░ 品質: 良好     │  ← 通信品質インジケーター
│─────────────────────────│
│                         │
│        👤               │
│    管制: 山田さん         │  ← 相手情報（音声モード）
│                         │
│                         │
│─────────────────────────│
│  🔇 ミュート              │  ← 通常操作（タップ）
│                         │
│  ⏹ 終了（3秒長押し）      │  ← 緊急終了（長押し）
└─────────────────────────┘
```

### 12.2 再接続中の表示（状態細分化）

#### 自端末が圏外

```
┌─────────────────────────┐
│ 🟡 再接続中  00:01:23     │
│─────────────────────────│
│                         │
│     📡                   │
│   電波を探しています...    │
│   電波が届き次第          │
│   自動的につながります      │
│                         │
│   切断: 1分23秒前         │
└─────────────────────────┘
```

#### 相手が未接続

```
┌─────────────────────────┐
│ 🟡 再接続中  00:00:45     │
│─────────────────────────│
│                         │
│     👤                   │
│   相手の接続を            │
│   待っています...          │
│                         │
│   待機: 45秒              │
└─────────────────────────┘
```

#### SUSPENDED（長時間切断）

```
┌─────────────────────────┐
│ 🟠 接続待機中  00:08:45   │
│─────────────────────────│
│                         │
│     💤                   │
│   接続待機中              │
│   復帰次第自動で           │
│   つながります             │
│                         │
│   省電力モードで待機中      │
└─────────────────────────┘
```

### 12.3 ビデオモード時（管制が有効化した場合）

```
┌─────────────────────────┐
│ 🟢 接続中  00:45:12      │
│ ████████░░ 品質: 良好     │
│─────────────────────────│
│                         │
│   管制オペレーターの映像    │  ← ビデオ有効時のみ表示
│                         │
│─────────────────────────│
│  [自分の映像]   🔇  📷   │
│              ⏹ 終了(長押) │
└─────────────────────────┘
```

### 12.4 管制オペレーター画面

```
┌─────────────────────────┐
│ TailCall — 管制          │
│─────────────────────────│
│                         │
│   👤 ドライバー: 佐藤     │  ← 音声モード時
│   (ビデオ有効時は映像表示)  │
│                         │
│─────────────────────────│
│  🔇 ミュート  📷 ビデオ   │  ← ビデオON/OFFトグル
│  📞 終了                 │
│─────────────────────────│
│  接続状態: 🟢 接続中       │
│  通話時間: 00:45:12       │
│  品質: ████████░░ 良好    │
│  切断回数: 3回            │
│  累計切断: 3分05秒        │
│  端末温度: 正常            │
└─────────────────────────┘
```

---

## 13. 技術スタック（v0.2 改訂）

### 13.1 モバイルアプリ

| 技術 | バージョン | 用途 |
|------|-----------|------|
| Flutter | 3.x | クロスプラットフォームUI |
| flutter_webrtc | ^0.12.x | WebRTC実装 |
| web_socket_channel | ^3.x | シグナリング通信 |
| connectivity_plus | ^6.x | ネットワーク状態監視 |
| riverpod | ^2.x | 状態管理 |
| wakelock_plus | ^1.x | 画面スリープ防止 |
| flutter_callkeep | ^0.4.x | CallKit/ConnectionService統合 |
| flutter_local_notifications | ^17.x | Android Foreground Service通知 |
| shared_preferences | ^2.x | セッションキャッシュ |
| flutter_secure_storage | ^9.x | JWT安全保存 |
| sqflite | ^2.x | ローカルログDB |
| battery_plus | ^6.x | バッテリー状態監視 |
| thermal | — | 端末温度監視（プラットフォームチャネル実装） |

### 13.2 シグナリングサーバー

| 技術 | バージョン | 用途 |
|------|-----------|------|
| Node.js | 20 LTS | ランタイム |
| ws | ^8.x | WebSocketサーバー |
| ioredis | ^5.x | Redis接続 |
| jsonwebtoken | ^9.x | JWT認証 |
| uuid | ^9.x | セッションID生成 |
| pino | ^9.x | 構造化ログ |

### 13.3 インフラ

| 項目 | 選択 | 備考 |
|------|------|------|
| VPN | Tailscale Free | 3ユーザー/100デバイス |
| サーバー | Oracle Cloud Always Free | ARM 4コア/24GB RAM |
| OS | Ubuntu 24.04 LTS | サーバー用 |
| Redis | Redis 7.x | サーバーに同居 |
| APNs | Apple Push Notification service | iOS PushKit用 |

---

## 14. 開発計画（v0.2 改訂: 6〜10週間）

### Phase 1: 音声通話 + 自動リコネクト（MVP）— 6〜10週間

| 週 | タスク | 重点 |
|----|--------|------|
| Week 1 | シグナリングサーバー構築（Node.js + WebSocket + Redis + JWT認証） | |
| Week 2 | Flutter WebRTCで音声P2P通話の基本実装 + Opus最適化 | |
| Week 3 | Android Foreground Service実装 + バッテリー最適化除外フロー | **最重要** |
| Week 4 | 4層ネットワーク監視 + 接続状態マシン実装 | **最重要** |
| Week 5 | ICE Restart実装 + 動作検証 | **最重要** |
| Week 6 | PeerConnection再生成戦略 + IP変更検知 + フォールバック | **最重要** |
| Week 7 | シグナリング障害時のクライアントキャッシュ + P2P直接シグナリング | |
| Week 8 | RTP/RTCPメトリクス収集 + 品質レベル判定 + 動的ビットレート制御 | |
| Week 9 | 実地テスト（機内モード切替・WiFi↔LTE切替・電波弱環境） | |
| Week 10 | バグ修正 + ログ実装 + ドライバー画面UI仕上げ | |

**Week 3〜6がMVP成功の鍵。ここに最も時間を投下する。**

### Phase 2: ビデオ + iOS対応 + 熱管理 — 4〜6週間

| 週 | タスク |
|----|--------|
| Week 11 | オンデマンドビデオ機能（管制側からのON/OFF制御） |
| Week 12 | 帯域・品質適応制御（RTT/Jitter/Loss総合判定） |
| Week 13 | iOS CallKit + PushKit対応（iOS別設計） |
| Week 14 | 熱管理（温度監視 + ビデオ自動OFF + ビットレート低下） |
| Week 15 | オフライン音声メモ機能 |
| Week 16 | 結合テスト + iOS/Android両プラットフォーム検証 |

### Phase 3: 管制ダッシュボード + 運用機能 — 3〜4週間

| 週 | タスク |
|----|--------|
| Week 17 | 管制ダッシュボード（複数ドライバー一覧 + 品質表示） |
| Week 18 | 通話ログ・接続ログのレポート画面 |
| Week 19 | アラート通知（5分切断・温度警告） + リモートログ取得 |
| Week 20 | 総合テスト + リリース準備 |

---

## 15. テスト計画（v0.2 改訂）

### 15.1 自動リコネクトのテストシナリオ

| # | シナリオ | 期待結果 |
|---|---------|---------|
| T-001 | 通話中に機内モードON→30秒後にOFF | 5秒以内に自動再接続（ICE Restart） |
| T-002 | WiFi→LTE切替（IP変更あり） | PC再生成で8秒以内に再接続 |
| T-003 | LTE→WiFi切替（IP変更あり） | PC再生成で8秒以内に再接続 |
| T-004 | 5分間の圏外→復帰 | SUSPENDED→RECONNECTING→CONNECTED |
| T-005 | 29分間の圏外→復帰 | セッション維持、自動再接続 |
| T-006 | 31分間の圏外→復帰 | セッション終了、管制に通知 |
| T-007 | シグナリングサーバーダウン中の切断→復帰 | P2P直接シグナリングで再接続 |
| T-008 | 両端末同時に圏外→片方復帰→もう片方復帰 | 両方復帰後に自動再接続 |
| T-009 | 1時間の通話中に10回の短時間切断 | すべて自動復帰、累計切断時間を記録 |
| T-010 | ICE Restart 2回連続失敗 | 自動的にPC再生成にフォールバック |
| T-011 | Androidアプリがバックグラウンド移行 | Foreground Serviceで通話維持 |
| T-012 | Android Dozeモード突入 | Foreground Service + WAKE_LOCKで維持 |
| T-013 | 高パケットロス環境（10%以上） | Opus FECで音声品質維持、UIに警告表示 |
| T-014 | 帯域制限環境（100kbps以下） | 自動的にOpus 16kbpsに切替 |

### 15.2 テスト環境

- スマートフォン2台（Android 2台でMVP。iOS追加はPhase 2）
- Tailscale Free アカウント
- テスト手法:
  - 機内モードの手動切替（基本的な切断シミュレーション）
  - WiFi ON/OFF（IP変更を伴う切替テスト）
  - Androidの開発者オプション「ネットワーク速度制限」（低帯域テスト）
  - 実車テスト: トンネル通過時の実地テスト

---

## 16. 費用見積もり

### 16.1 初期費用

| 項目 | 金額 |
|------|------|
| Google Play Developer登録 | ¥3,700（一回のみ） |
| Apple Developer Program | ¥15,000/年（Phase 2でiOS対応時） |
| テスト端末 | ¥0（手持ち利用） |
| **合計（MVP: Android のみ）** | **¥3,700** |
| **合計（Phase 2: iOS 含む）** | **¥18,700** |

### 16.2 月額ランニングコスト

| 項目 | 金額 |
|------|------|
| Tailscale | ¥0（Freeプラン） |
| サーバー（Oracle Cloud Free） | ¥0 |
| Redis（サーバー同居） | ¥0 |
| APNs | ¥0（Apple Developer Program に含まれる） |
| **合計** | **¥0/月** |

---

## 17. リスクと対策（v0.2 改訂）

| リスク | 影響度 | 対策 |
|--------|--------|------|
| **Android Doze/バックグラウンド制限で通信断** | **最高** | Foreground Service + PARTIAL_WAKE_LOCK + バッテリー最適化除外。初回起動時にユーザーガイド表示 |
| **iOS バックグラウンド制約** | **最高** | CallKit + PushKit による疑似常時接続。Phase 2で別設計として対応 |
| **ICE Restart が不安定** | **高** | 2回失敗でPeerConnection再生成にフォールバック。IP変更検知時は即座にPC再生成 |
| **Tailscale peer.online が実通信を反映しない** | **高** | RTP/RTCPメトリクス（Layer 4）で実通信品質を直接監視。Tailscale状態は参考情報に格下げ |
| **長時間通話でサーマルスロットリング** | **中** | 音声デフォルト化で大幅軽減。ビデオ有効時は温度監視で自動OFF |
| **シグナリングサーバーが単一障害点** | **中** | クライアント側セッションキャッシュ + P2P直接シグナリングでフォールバック |
| **長時間圏外でセッションTTL超過** | **中** | TTLを運行スケジュールに応じて設定変更可能にする |
| **Tailscale Freeプランの制限変更** | **低** | 必要に応じてPersonal Proへ移行（$48/年） |
| **Oracle Cloud Free Tier廃止** | **低** | 自宅サーバー or 格安VPSへ移行 |

---

## 18. 将来の拡張案

- ドライバー位置情報のリアルタイム表示（Tailscale経由GPS共有）
- グループ通話対応（管制1:ドライバーN）
- 通話録画・録音（コンプライアンス対応）
- AI音声認識による自動議事録
- Wear OS / CarPlay対応
- SFU（Selective Forwarding Unit）導入による多人数対応

---

## 付録A: 用語集

| 用語 | 説明 |
|------|------|
| ICE | Interactive Connectivity Establishment。P2P接続確立プロトコル |
| ICE Restart | 既存セッションを維持したまま新しいICE候補で再接続する機能 |
| PeerConnection再生成 | WebRTCのPeerConnectionオブジェクトを破棄し新規作成する。ICE Restartより重いが確実 |
| SDP | Session Description Protocol。メディア情報の記述フォーマット |
| DTLS | Datagram Transport Layer Security。WebRTCのメディア暗号化 |
| DERP | Designated Encrypted Relay for Packets。Tailscaleのリレーサーバー |
| Tailnet | Tailscaleで構成されるプライベートネットワーク |
| 指数バックオフ | リトライ間隔を指数的に増加させる手法（0.5s→1s→2s→4s→...） |
| Foreground Service | Androidで通知バーに常駐しバックグラウンド制限を回避するサービス |
| CallKit | iOSの通話UI統合フレームワーク。VoIPアプリをOS標準通話と統合 |
| PushKit | iOSのVoIP Push通知。アプリ終了状態からの復帰に使用 |
| FEC | Forward Error Correction。パケットロスを前方誤り訂正で補償する技術 |
| DTX | Discontinuous Transmission。無音区間で送信を停止し帯域を節約する技術 |
| RTT | Round Trip Time。パケットの往復遅延時間 |
| Jitter | パケット到着間隔のばらつき。大きいと音声品質が低下 |
| JWT | JSON Web Token。デバイス認証に使用するトークン形式 |

---

## 付録B: v0.1からの主要変更点サマリー

| 項目 | v0.1 | v0.2 |
|------|------|------|
| デフォルトモード | ビデオ通話 | **音声通話（ビデオはオンデマンド）** |
| Android常駐 | バッテリー最適化除外のみ | **Foreground Service + WAKE_LOCK** |
| iOS対応 | 同一設計 | **CallKit + PushKit別設計** |
| 検知レイヤー | 3層（OS/Tailscale/ICE） | **4層（+RTP/RTCPメトリクス）** |
| 再接続戦略 | ICE Restartのみ | **ICE Restart → PC再生成の段階的フォールバック** |
| シグナリング障害対策 | なし | **クライアントキャッシュ + P2P直接シグナリング** |
| 認証 | IPベース | **JWT デバイス認証** |
| 品質制御 | 帯域のみ | **RTT/Jitter/PacketLoss総合判定** |
| 状態表示 | RECONNECTING（1種） | **RECONNECTING_NETWORK / _PEER（2種）** |
| ドライバー終了操作 | 不可 | **3秒長押しで緊急終了可能** |
| 熱管理 | なし | **温度監視 + ビデオ自動OFF** |
| ログ | なし | **接続遷移/ICE/メトリクス/エラーの永続ログ** |
| Opusコーデック設定 | デフォルト | **FEC/DTX有効 + 動的ビットレート制御** |
| 開発期間 | 4〜6週間 | **6〜10週間（現実的見積もり）** |
