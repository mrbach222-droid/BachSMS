@echo off
setlocal
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (echo Cannot find .NET Framework C# compiler. & pause & exit /b 1)
"%CSC%" /nologo /target:exe /out:"%~dp0BachCrmSyncAgent.exe" /reference:System.dll /reference:System.Core.dll /reference:System.Data.dll /reference:System.Web.Extensions.dll /reference:System.Security.dll "%~dp0BachCrmSyncAgent.cs" 1>"%~dp0Build_Sync_Log.txt" 2>&1
if errorlevel 1 (type "%~dp0Build_Sync_Log.txt" & pause & exit /b 1)
echo Agent built. Run BachCrmSyncAgent.exe --configure, then --watch.
pause