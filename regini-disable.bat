@echo off
chcp 65001 >nul 2>&1
echo ========================================
  Method: REGINI (low-level registry)
  Bypasses some permission checks
=======================================
echo.
echo This batch file MUST be run as ADMINISTRATOR.
echo Right-click this file - Run as administrator
echo.

:: Create temp Regini script
set "RGINI=%TEMP%\defender.rig"
echo %RGINI% >nul

(
echo HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender [1 5 7 11 14]
echo HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection [1 5 7 11 14]
echo HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet [1 5 7 11 14]
echo HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates [1 5 7 11 14]
) > "%RGINI%"

echo [1] Setting registry permissions via REGINI...
regini "%RGINI%"
if errorlevel 1 (
  echo    REGINI failed, trying direct method...
) else (
  echo    Permissions set successfully.
)

echo.
echo [2] Writing policy values...

:: Disable Real-Time Protection via Policy path (not tamper-protected)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f 2>nul && echo OK: DisableAntiSpyware=1 || echo FAIL: DisableAntiSpyware

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiVirus /t REG_DWORD /d 1 /f 2>nul && echo OK: DisableAntiVirus=1 || echo FAIL: DisableAntiVirus

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f 2>nul && echo OK: RT Monitoring policy || echo FAIL: RT Monitoring

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableBehaviorMonitoring /t REG_DWORD /d 1 /f 2>nul && echo OK: Behavior Monitor || echo FAIL: Behavior Monitor

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableOnAccessProtection /t REG_DWORD /d 1 /f 2>nul && echo OK: OnAccess Protect || echo FAIL: OnAccess

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScanOnRealtimeEnable /t REG_DWORD /d 1 /f 2>nul && echo OK: Scan On Access || echo FAIL: ScanOnAccess

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" /v SubmitSamplesConsent /t REG_DWORD /d 0 /f 2>nul && echo OK: Spynet samples off || echo FAIL: Spynet

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" /v SpynetReporting /t REG_DWORD /d 0 /f 2>nul && echo OK: Spynet reporting off || echo FAIL: Spynet report

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates" /v ForceUpdateFromMU /t REG_DWORD /d 1 /f 2>nul && echo OK: Sig updates from MU || echo FAIL: Sig updates

echo.
echo [3] Killing processes...
taskkill /f /im MsMpEng.exe 2>nul & taskkill /f /im NisSrv.exe 2>nul & taskkill /f /im SecurityHealthService.exe 2>nul & taskkill /f /im SecurityHealthSystray.exe 2>nul & taskkill /f /im SmcGui.exe 2>nul
echo    Done.

echo.
echo [4] Verifying...
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware 2>nul
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiVirus 2>nul

del "%RGINI%" 2>nul

echo.
echo ========================================
echo IMPORTANT:
echo If you still see errors above,
echo the ONLY way is to turn off Tamper Protection:
echo   Settings ^> Update ^> Windows Security
echo   Virus ^> Manage settings ^>
echo   Turn OFF Tamper Protection
echo Then reboot and run this again.
echo ========================================
pause
