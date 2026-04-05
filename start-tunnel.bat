@echo off
echo ========================================
echo  TailCall - Cloudflare Tunnel Start
echo ========================================
echo.
echo  Domain: tailcall.remotecomfy-uone.jp -> localhost:3002
echo.
echo  ※ PC スリープするとTunnelが切断されます
echo.

cloudflared tunnel --config C:\AI-dev\Mini-RMS_app\server\cloudflare-config.yml run tailcall

pause
