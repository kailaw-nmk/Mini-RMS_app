# TailCall - Tailscale常時接続通話アプリ

Tailscale VPN上で動作し、ネットワーク断→復帰時にセッションを自動リジュームする常時音声通話アプリ。トラックドライバーと管制オペレーター間の1対1通話に特化。

## Tech Stack

### Mobile App
- Flutter 3.x + flutter_webrtc (WebRTC P2P)
- Riverpod (状態管理)
- connectivity_plus, wakelock_plus, flutter_callkeep
- flutter_secure_storage (JWT), sqflite (ログDB)

### Signaling Server
- Node.js 20 LTS (ESM modules)
- ws (WebSocket), ioredis (Redis), jsonwebtoken (JWT), pino (logging)

### Infrastructure
- Redis 7.x (session store)
- Tailscale VPN (WireGuard encrypted network)
- Oracle Cloud Always Free (server hosting)

## Project Structure

```
tailcall/
  app/                          # Flutter mobile app
    lib/
      core/                     # Config, constants, errors
      features/
        call/                   # WebRTC voice call, state machine
        auth/                   # JWT auth, pairing flow
        session/                # Session management, local cache
        network/                # 4-layer network monitoring
        metrics/                # RTP/RTCP quality metrics
      services/                 # Foreground Service, CallKit
      ui/                       # Screens, widgets, themes
    android/                    # Foreground Service config
    ios/                        # CallKit/PushKit (Phase 2)
    test/
  server/                       # Signaling server
    src/
      ws/                       # WebSocket handlers
      auth/                     # JWT middleware
      session/                  # Redis session management
      logging/                  # Pino structured logging
    test/
  docs/                         # Specifications
```

## Coding Conventions

- **Dart**: effective_dart準拠、Riverpodで状態管理、freezedでimmutableモデル
- **Node.js**: ESM (import/export)、async/await、コールバック禁止
- **言語**: コード・コメントは英語、UIテキストは日本語
- **エラー処理**: サイレント無視禁止、必ずコンテキスト付きログ出力
- **状態遷移**: 全遷移を明示的に定義しログに記録

## Key Domain Concepts

### Connection States
`CONNECTED` → `RECONNECTING_NETWORK` / `RECONNECTING_PEER` → `SUSPENDED` → `DISCONNECTED`

### 4-Layer Detection (優先度順)
1. **Layer 4: RTP/RTCP** — 実通信の真の状態（最優先）
2. **Layer 3: ICE** — WebRTCレベルの接続状態
3. **Layer 1: OS** — ネットワーク有無の大枠
4. **Layer 2: Tailscale** — ピア存在確認（参考情報）

### Reconnect Strategy
ICE Restart (max 2回) → PeerConnection再生成 → 指数バックオフ (0.5s→30s max)

### Session
- TTL: 30分（設定変更可能）
- 5分切断 → SUSPENDED、30分切断 → DISCONNECTED
- クライアント側キャッシュでシグナリング障害時もフォールバック

## Critical Constraints

1. **ドライバー操作不要**: リコネクトに一切のユーザー操作を要求しない
2. **Foreground Service必須**: Android通話維持にForeground Service + PARTIAL_WAKE_LOCK
3. **音声優先**: デフォルト音声のみ、ビデオはPhase 2でオンデマンド
4. **Tailscale網内限定**: シグナリングサーバーはインターネット非公開
5. **管制→ドライバー方向のみ**: 通話開始・終了は原則管制側のみ

## Testing

- **Flutter**: `flutter test` — widget tests (UI), unit tests (state machine, reconnect logic)
- **Server**: `npm test` (vitest) — WebSocket handler, session management
- **Integration**: 手動テスト — 機内モード切替、WiFi↔LTE切替、電波弱環境
- **Key scenarios**: T-001〜T-014 (docs/functional-spec.md参照)

## WebSocket Message Types

`auth`, `auth_result`, `call_initiate`, `call_end`, `sdp_offer`, `sdp_answer`, `ice_candidate`, `ice_restart`, `pc_recreate`, `state_change`, `video_request`, `session_expired`, `error`

## Development Phases

- **Phase 1 (MVP)**: 音声通話 + 自動リコネクト + Android (6-10週)
- **Phase 2**: ビデオ + iOS対応 + 熱管理 (4-6週)
- **Phase 3**: 管制ダッシュボード + 運用機能 (3-4週)
