# TailCall ローカル統合テスト計画

## テスト環境
- エミュレータ1: Pixel_6_API_35 (管制オペレーター)
- エミュレータ2: Pixel_6_Driver (ドライバー)
- シグナリングサーバー: localhost:8080 (エミュレータから 10.0.2.2:8080)
- Redis: Docker tailcall-redis (localhost:6379)

## テスト手順

### 前提: サーバー起動
```bash
cd server && npm run dev
```

### 前提: エミュレータ起動
```bash
emulator -avd Pixel_6_API_35 -port 5554 &
emulator -avd Pixel_6_Driver -port 5556 &
```

### 前提: APKインストール
```bash
flutter build apk --debug
adb -s emulator-5554 install app/build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5556 install app/build/app/outputs/flutter-apk/app-debug.apk
```

---

## テスト実行可能なシナリオ

### T-007: シグナリングサーバーダウン (✅ エミュレータ可)
1. 両端末で通話確立
2. サーバープロセスをkill
3. 既存P2P通話が継続することを確認
4. サーバー再起動
5. 期待: 既存通話に影響なし

### T-010: ICE Restart 2回失敗 → PC再生成 (⚠️ 部分テスト)
1. 通話確立
2. ネットワーク断をシミュレート
3. ICE Restart失敗を観察
4. PC再生成フォールバックを確認

### T-011: バックグラウンド移行 (✅ エミュレータ可)
1. 通話確立
2. ドライバーエミュレータでホームボタン押下
3. 通知バーにForeground Service表示確認
4. 音声が継続することを確認

### T-012: Dozeモード (⚠️ adbコマンド)
```bash
adb -s emulator-5556 shell dumpsys deviceidle force-idle
# → 通話が維持されることを確認
adb -s emulator-5556 shell dumpsys deviceidle unforce
```

### T-013: 高パケットロス (✅ エミュレータ可)
エミュレータの拡張コントロールでパケットロス設定:
- Settings > Extended controls > Cellular > Signal strength
- または: adb shell tc でネットワーク条件を操作

### T-014: 帯域制限 (✅ エミュレータ可)
エミュレータの拡張コントロールで帯域制限:
- Settings > Extended controls > Cellular > Network type > Edge

### T-001: 機内モード擬似 (⚠️ adbコマンド)
```bash
# 機内モードON
adb -s emulator-5556 shell cmd connectivity airplane-mode enable
# 30秒待機
sleep 30
# 機内モードOFF
adb -s emulator-5556 shell cmd connectivity airplane-mode disable
# → 5秒以内に再接続を確認
```
