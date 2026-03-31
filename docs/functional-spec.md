# TailCall 機能仕様書 (Functional Specification)

**Version**: 1.0 (derived from tailcall-spec-v0.2.md)
**Date**: 2026-03-30

---

## 1. Feature Inventory & Phase Mapping

### Phase 1: MVP (Weeks 1-10)

| ID | Feature | Priority | Dependencies | Week |
|----|---------|----------|-------------|------|
| F-001 | Audio Call (Opus) | P0 | Server | 2 |
| F-002 | Auto-Reconnect | P0 | F-001, F-003 | 4-6 |
| F-003 | Connection State UI | P0 | State Machine | 4 |
| F-004 | Session Management | P0 | Redis | 1 |
| F-005 | Call Start/End Control | P0 | F-004 | 2 |
| F-006 | Device Auth (JWT) | P0 | Server | 1 |

### Phase 2 (Weeks 11-16)

| ID | Feature | Priority | Dependencies |
|----|---------|----------|-------------|
| F-101 | On-demand Video | P1 | F-001 |
| F-102 | Adaptive Quality Control | P1 | F-001, Metrics |
| F-103 | Thermal Management | P1 | F-102 |
| F-104 | Offline Voice Memo | P2 | Storage |

### Phase 3 (Weeks 17-20)

| ID | Feature | Priority | Dependencies |
|----|---------|----------|-------------|
| F-201 | Operator Dashboard | P1 | F-004 |
| F-202 | Call Logs & Reports | P2 | F-201, Logging |
| F-203 | Alert Notifications | P2 | F-201 |

---

## 2. Feature Details & Acceptance Criteria

### F-001: Audio Call (Opus)

**Description**: Tailscale VPN上の2端末間でWebRTC P2P音声通話を確立する

**Acceptance Criteria**:
- [ ] 同一Tailnet上の2端末間で音声通話が確立できる
- [ ] Opus codec設定: FEC=on, DTX=on, bitrate=24kbps (default)
- [ ] 音声遅延が300ms以下 (getStats()で計測)
- [ ] パケットロス20%まで通話品質を維持
- [ ] Android: Foreground Serviceで通話がバックグラウンドでも継続
- [ ] SDP内にOpus最適化パラメータが設定される: `useinbandfec=1;usedtx=1;maxaveragebitrate=24000`

**Opus Quality Settings**:

| Quality Level | Bitrate | FEC | DTX | ptime |
|--------------|---------|-----|-----|-------|
| EXCELLENT | 32kbps | ON | OFF | 20ms |
| GOOD | 24kbps | ON | ON | 20ms |
| FAIR | 24kbps | ON (enhanced) | ON | 40ms |
| POOR | 16kbps | ON (max) | ON | 60ms |

---

### F-002: Auto-Reconnect

**Description**: ネットワーク断を検知し、ドライバー操作なしで自動再接続する (最重要機能)

**Acceptance Criteria**:
- [ ] 機内モードON 30秒→OFF: 5秒以内にICE Restartで再接続
- [ ] WiFi→LTE切替 (IP変更): 8秒以内にPC再生成で再接続
- [ ] LTE→WiFi切替 (IP変更): 8秒以内にPC再生成で再接続
- [ ] ICE Restart最大2回失敗後、PC再生成にフォールバック
- [ ] 指数バックオフ: 0.5s → 1s → 2s → 4s → ... → 30s max
- [ ] 5分切断 → SUSPENDED状態に遷移 (30s固定間隔リトライ)
- [ ] 30分切断 → DISCONNECTED (セッション終了、管制に通知)
- [ ] ドライバー側の操作は一切不要
- [ ] IP変更検知時はICE Restartをスキップし直接PC再生成
- [ ] 成功時にバックオフカウンターをリセット

**Reconnect Strategy Flow**:
```
切断検知 → IP変更? → Yes → PC再生成
                    → No  → ICE Restart (max 2回)
                              → 失敗 → PC再生成
                                        → 失敗 → バックオフ待機 → リトライ
```

---

### F-003: Connection State UI

**Description**: 接続状態をリアルタイムでドライバー画面に表示する

**Acceptance Criteria**:
- [ ] CONNECTED: 緑インジケーター + 通話時間 + 品質バー
- [ ] RECONNECTING_NETWORK: 黄インジケーター + "電波を探しています" + 切断経過時間
- [ ] RECONNECTING_PEER: 黄インジケーター + "相手の接続を待っています" + 待機時間
- [ ] SUSPENDED: オレンジインジケーター + "接続待機中" + "省電力モードで待機中"
- [ ] DISCONNECTED: 灰色インジケーター + セッション終了表示
- [ ] 状態遷移時にUIが即時更新される (100ms以内)
- [ ] Android通知バーにも接続状態をリアルタイム表示

---

### F-004: Session Management

**Description**: セッションをサーバー・クライアント両方で永続化し、リジュームを可能にする

**Acceptance Criteria**:
- [ ] セッション情報がRedisに保存される (TTL: 30分)
- [ ] クライアント側にセッション情報がキャッシュされる
- [ ] 両端末の再起動後もセッションリジュームが可能
- [ ] シグナリングサーバー障害時にクライアントキャッシュでリジューム可能
- [ ] セッションTTLは設定変更可能
- [ ] TTL超過時にセッションが自動終了し、管制に通知

---

### F-005: Call Start/End Control

**Description**: 通話の開始・終了の権限制御

**Acceptance Criteria**:
- [ ] 管制オペレーターがドライバーを呼び出せる (管制→ドライバー方向のみ)
- [ ] 通常の通話終了は管制オペレーター側のみ
- [ ] ドライバー側に緊急終了機能: 終了ボタン3秒長押し → 確認ダイアログ → 終了
- [ ] 通話開始時にセッションが生成される
- [ ] 通話終了時にセッションがクリーンアップされる

---

### F-006: Device Auth (JWT)

**Description**: JWTベースのデバイス認証

**Acceptance Criteria**:
- [ ] 初回ペアリング: 管制が6桁コード生成 (有効期限5分) → ドライバー入力 → JWT発行
- [ ] JWT payload: `{ device_id, tailscale_ip, role, iat, exp }`
- [ ] JWT有効期限: 30日 (自動更新)
- [ ] 有効期限7日以内で自動リフレッシュ
- [ ] JWTをSecure Storageに保存
- [ ] WebSocket接続時にJWTをヘッダーに含める
- [ ] サーバー側でJWT検証 → 失敗時401 → ペアリング画面表示
- [ ] 管制側からトークン無効化が可能

---

### F-101: On-demand Video (Phase 2)

**Acceptance Criteria**:
- [ ] 音声通話中に管制オペレーターがビデオを有効化できる
- [ ] ドライバー側はビデオ有効化リクエストを自動承認 (設定可)
- [ ] コーデック: VP8 or H.264 (端末サポートに応じて自動選択)
- [ ] ネットワーク復帰時はまず音声で再接続、帯域安定後にビデオ追加
- [ ] video_requestメッセージで制御

---

### F-102: Adaptive Quality Control (Phase 2)

**Acceptance Criteria**:
- [ ] RTT, Jitter, PacketLoss, 帯域の4指標で総合判定
- [ ] 5段階品質レベル (EXCELLENT/GOOD/FAIR/POOR/CRITICAL)
- [ ] 品質レベルに応じてビットレート・ビデオ・FECを自動調整
- [ ] CRITICAL判定時にRECONNECTING状態へ遷移

---

### F-103: Thermal Management (Phase 2)

**Acceptance Criteria**:
- [ ] 端末温度を監視
- [ ] 温度「警告」: ビデオ自動OFF
- [ ] 温度「危険」: Opus 16kbps + 画面輝度低下
- [ ] 管制側に温度警告を通知

---

### F-104: Offline Voice Memo (Phase 2)

**Acceptance Criteria**:
- [ ] 圏外中にドライバーが音声メモを録音できる
- [ ] ネットワーク復帰後、管制オペレーターに自動送信

---

### F-201: Operator Dashboard (Phase 3)

**Acceptance Criteria**:
- [ ] 複数ドライバーの接続状態を一覧表示
- [ ] ドライバー選択→通話開始の操作フロー
- [ ] 各ドライバーの通信品質インジケーター表示

---

### F-202: Call Logs & Reports (Phase 3)

**Acceptance Criteria**:
- [ ] 通話開始/終了/切断/復帰のタイムスタンプ記録
- [ ] 切断回数・累積切断時間のレポート
- [ ] 接続状態遷移ログ、ICEイベントログ、RTT/Loss履歴の永続保存

---

### F-203: Alert Notifications (Phase 3)

**Acceptance Criteria**:
- [ ] 切断5分以上で管制オペレーターにプッシュ通知
- [ ] 端末温度が危険レベルの場合に通知

---

## 3. API Contract: WebSocket Messages

### 3.1 Client → Server

| Type | Required Fields | When Sent |
|------|----------------|-----------|
| `auth` | device_token, device_id, session_resume_id | WebSocket接続直後 |
| `call_initiate` | session_id, from, to, mode, timestamp | 管制が通話開始 |
| `call_end` | session_id, reason, timestamp | 通話終了 |
| `sdp_offer` | session_id, sdp, ice_restart, reconnect_strategy | 通話開始/リコネクト |
| `sdp_answer` | session_id, sdp | Offerへの応答 |
| `ice_candidate` | session_id, candidate{candidate, sdpMid, sdpMLineIndex} | ICE候補発見時 |
| `ice_restart` | session_id, reason, strategy, retry_count, ip_changed | リコネクト試行 |
| `pc_recreate` | session_id, reason, new_sdp_offer | ICE Restart 2回失敗後 |
| `state_change` | session_id, from_state, to_state, metrics, timestamp | 状態遷移時 |
| `video_request` | session_id, action, requested_by | Phase 2: ビデオON/OFF |

### 3.2 Server → Client

| Type | Required Fields | When Sent |
|------|----------------|-----------|
| `auth_result` | success, session_resumed, session_id | auth応答 |
| `session_expired` | session_id, reason | TTL超過 |
| `error` | code, message | バリデーション/認証失敗 |
| *(relay)* | 上記Client→Serverメッセージをそのまま相手に転送 | 随時 |

### 3.3 Error Codes

| Code | Message | Trigger |
|------|---------|---------|
| `AUTH_FAILED` | Invalid or expired token | JWT検証失敗 |
| `SESSION_NOT_FOUND` | Session does not exist | 無効なsession_id |
| `SESSION_EXPIRED` | Session TTL exceeded | 30分超過 |
| `PEER_NOT_CONNECTED` | Target peer is not online | 相手未接続 |
| `INVALID_MESSAGE` | Unknown or malformed message | パース失敗 |
| `UNAUTHORIZED` | Action not permitted for role | 権限不足 |

### 3.4 REST Endpoints

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| POST | /api/pair | ペアリングコード生成 | JWT (operator) |
| POST | /api/pair/confirm | ペアリング確認 → JWT発行 | Pairing code |
| GET | /api/health | サーバーヘルスチェック | None |
| POST | /api/direct-signal | P2Pフォールバックシグナリング | JWT |

---

## 4. Data Models

### 4.1 Redis Session Schema

```
Key: session:{session_id}
TTL: 1800 seconds (30 min, configurable)
```

```json
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

### 4.2 Client Session Cache

```json
{
  "session_id": "sess_20260328_001",
  "peer_tailscale_ip": "100.64.0.5",
  "last_sdp_offer": "v=0\r\no=- ...",
  "last_sdp_answer": "v=0\r\no=- ...",
  "device_token": "eyJhbGciOiJIUzI1NiIs...",
  "cached_at": "2026-03-28T09:15:30Z"
}
```
Storage: SharedPreferences. Cache invalidation: 30 min from cached_at.

### 4.3 JWT Payload

```json
{
  "device_id": "driver_truck042",
  "tailscale_ip": "100.64.0.12",
  "role": "driver",
  "iat": 1711612800,
  "exp": 1714204800
}
```
Signing: HS256. Key: server environment variable. Expiry: 30 days. Auto-refresh: when < 7 days remaining.

### 4.4 Media Metrics

```json
{
  "rtt": 145.0,
  "jitter": 23.0,
  "packetLoss": 0.02,
  "availableBandwidth": 1200000,
  "lastPacketReceivedAge": "PT2S",
  "nackCount": 5,
  "firCount": 0
}
```

### 4.5 Log Schemas

**Connection State Transition Log**:
```json
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
```

**Quality Metrics Log (5s interval)**:
```json
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

**Log Retention**:

| Log Type | Storage | Retention |
|----------|---------|-----------|
| Connection state transitions | Local DB + Redis | 30 days |
| ICE events | Local DB | 7 days |
| RTP/RTCP metrics | Local DB (5s sampling) | 3 days |
| Error logs | Local DB + Server | 30 days |
| Call start/end | Redis | 90 days |

---

## 5. State Machine Specification

### 5.1 States

| State | Description | UI Color |
|-------|-------------|----------|
| CONNECTED | 通話中、通信正常 | Green |
| RECONNECTING_NETWORK | 自端末が圏外 | Yellow |
| RECONNECTING_PEER | 相手が未接続 | Yellow |
| SUSPENDED | 長時間切断 (5min+)、省電力待機 | Orange |
| DISCONNECTED | セッション終了 | Gray |

### 5.2 Transition Table

| From | To | Trigger | Action |
|------|----|---------|--------|
| CONNECTED | RECONNECTING_NETWORK | OS offline OR RTP silence >5s | Start backoff, reset ice_fail_count=0 |
| CONNECTED | RECONNECTING_PEER | Tailscale peer offline | Start backoff |
| RECONNECTING_NETWORK | CONNECTED | ICE/PC reconnect success | Reset counters, log duration |
| RECONNECTING_PEER | CONNECTED | ICE/PC reconnect success | Reset counters, log duration |
| RECONNECTING_NETWORK | SUSPENDED | 5 min elapsed | Set retry interval to 30s fixed |
| RECONNECTING_PEER | SUSPENDED | 5 min elapsed | Set retry interval to 30s fixed |
| SUSPENDED | CONNECTED | Network callback + reconnect | Resume normal operation |
| SUSPENDED | DISCONNECTED | 30 min TTL | End session, notify operator |
| Any | DISCONNECTED | Operator call_end | Clean up resources |
| Any | DISCONNECTED | Driver emergency end (3s hold) | Clean up, log as emergency |

### 5.3 4-Layer Detection Priority

```
Priority 1 (highest): Layer 4 — RTP/RTCP metrics
  - lastPacketReceivedAge > 5s → RECONNECTING_NETWORK
  - packetLoss > 50% → Quality warning

Priority 2: Layer 3 — WebRTC ICE state
  - disconnected → start reconnect timer
  - failed → performReconnectStrategy()
  - connected → CONNECTED

Priority 3: Layer 1 — OS network state
  - none → RECONNECTING_NETWORK (immediate)

Priority 4 (lowest): Layer 2 — Tailscale peer state
  - peer.offline → RECONNECTING_PEER (reference only)
```

---

## 6. Platform-Specific Requirements

### 6.1 Android (MVP)

**AndroidManifest.xml permissions**:
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_PHONE_CALL`
- `WAKE_LOCK`
- `<service android:foregroundServiceType="phoneCall" />`

**Foreground Service**:
- 通話開始時にService起動
- 通知バー常駐: "TailCall — 管制と接続中"
- PARTIAL_WAKE_LOCKでCPUスリープ防止
- 通話終了時にService停止

**Notification Channel**: `tailcall_active_call`
- Priority: IMPORTANCE_LOW (音を鳴らさない)
- Content: 接続状態リアルタイム表示

**Battery Optimization**:
- 初回起動時にバッテリー最適化除外の設定案内ダイアログ
- REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
- 未設定時は通話開始時に警告表示

### 6.2 iOS (Phase 2)

**CallKit Integration**:
- フォアグラウンド: 通常WebRTC通話
- バックグラウンド移行: CallKitで通話セッション登録 → iOS標準通話画面統合
- アプリ終了時: PushKit VoIP Pushで再起動 → 自動リジューム

**Requirements**:
- Apple Developer Program (¥15,000/year)
- APNs連携
- CallKit + PushKit統合 (Apple審査要件)
- バックグラウンド実行: 30秒制限内にリコネクト完了

---

## 7. Non-Functional Requirements

### 7.1 Performance

| Metric | Target |
|--------|--------|
| Audio latency | < 300ms |
| Video latency | < 500ms |
| Reconnect (ICE Restart) | < 3s after network recovery |
| Reconnect (PC recreate) | < 8s after network recovery |
| Concurrent sessions | MVP: 1 / Future: 20 |

### 7.2 Availability

- Signaling server: 99% uptime
- P2P call continues during server downtime
- Client cache enables reconnect during server outage

### 7.3 Security

- All traffic over Tailscale WireGuard tunnel
- Signaling server: Tailscale network only (no internet exposure)
- WebRTC DTLS media encryption
- JWT device authentication

### 7.4 Battery

- Target: 8hr continuous audio with 30%+ battery remaining (no car charger)
- Audio-first design minimizes consumption
- Exponential backoff prevents idle polling
- SUSPENDED state uses OS network callbacks (no active polling)

### 7.5 Supported Platforms

| Platform | Minimum Version |
|----------|----------------|
| Android | 10+ (Foreground Service) |
| iOS | 16+ (CallKit + PushKit) |
| Web (operator) | Chrome 100+ / Safari 16+ |

---

## 8. Test Scenarios

| ID | Scenario | Expected Result | Phase |
|----|----------|----------------|-------|
| T-001 | 通話中に機内モードON→30秒後OFF | 5秒以内にICE Restartで再接続 | MVP |
| T-002 | WiFi→LTE切替 (IP変更あり) | PC再生成で8秒以内に再接続 | MVP |
| T-003 | LTE→WiFi切替 (IP変更あり) | PC再生成で8秒以内に再接続 | MVP |
| T-004 | 5分間の圏外→復帰 | SUSPENDED→RECONNECTING→CONNECTED | MVP |
| T-005 | 29分間の圏外→復帰 | セッション維持、自動再接続 | MVP |
| T-006 | 31分間の圏外→復帰 | セッション終了、管制に通知 | MVP |
| T-007 | シグナリングサーバーダウン中の切断→復帰 | P2P直接シグナリングで再接続 | MVP |
| T-008 | 両端末同時に圏外→片方復帰→もう片方復帰 | 両方復帰後に自動再接続 | MVP |
| T-009 | 1時間通話中に10回の短時間切断 | すべて自動復帰、累計切断時間を記録 | MVP |
| T-010 | ICE Restart 2回連続失敗 | 自動的にPC再生成にフォールバック | MVP |
| T-011 | Androidアプリがバックグラウンド移行 | Foreground Serviceで通話維持 | MVP |
| T-012 | Android Dozeモード突入 | Foreground Service + WAKE_LOCKで維持 | MVP |
| T-013 | 高パケットロス環境 (10%以上) | Opus FECで品質維持、UIに警告表示 | MVP |
| T-014 | 帯域制限環境 (100kbps以下) | 自動的にOpus 16kbpsに切替 | MVP |

**Test Environment**:
- Android端末 2台 (MVP)
- Tailscale Freeアカウント
- 手法: 機内モード切替、WiFi ON/OFF、Android開発者オプション「ネットワーク速度制限」、実車テスト
