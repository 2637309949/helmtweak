@echo off
setlocal
chcp 65001 >nul
title HelmTweak OCR

rem ============================================================
rem  ocr.bat - Offline Chinese OCR via built-in Windows.Media.Ocr
rem
rem  Usage: ocr.bat <image> [-mode:none|word|line] [-out:<file>]
rem
rem  Arguments:
rem    <image>   Required. Path to a PNG/JPG image.
rem    -mode:    Optional. Coordinate output mode (case-insensitive):
rem                none  plain recognized text only, no coordinates (default)
rem                word  JSON; every recognized word with box x y w h
rem                line  JSON; every line with its overall box x y w h
rem    -out:     Optional. Write result to file (UTF-8). Default: console.
rem
rem  Notes:
rem    - Uses the OS built-in Windows.Media.Ocr engine. Fully offline.
rem      No tesseract / third-party OCR tools required.
rem    - Auto-loads the Simplified Chinese language pack zh-Hans-CN.
rem    - Images are decoded by the built-in BitmapDecoder and converted
rem      to the OCR-required pixel format (BGRA8 + Premultiplied), so
rem      PNG and JPG both work.
rem    - Single .bat file with embedded PowerShell logic (no external
rem      scripts, no extra executables). All Chinese/JSON output is
rem      emitted as UTF-8 by PowerShell, so it never garbles.
rem ============================================================

rem ---- validate required argument: image path ----
if "%~1"=="" (
    echo [ERROR] Missing required argument: image path
    echo Usage: ocr.bat IMAGE [-mode:none/word/line] [-out:OUTPUT]
    echo Example: ocr.bat test.jpg -mode:word -out:result.json
    exit /b 1
)

rem ---- validate image file exists ----
if not exist "%~1" (
    echo [ERROR] File not found: %~1
    exit /b 1
)

rem ---- resolve to full path (supports paths with spaces) ----
for %%I in ("%~1") do set "OCR_IMG=%%~fI"

rem ---- parse optional args (default mode: none = plain text) ----
set "OCR_MODE=none"
set "OCR_OUT="
:argloop
shift
if "%~1"=="" goto :argdone
set "ARG=%~1"
if /i "%ARG:~0,6%"=="-mode:" set "OCR_MODE=%ARG:~6%"
if /i "%ARG:~0,5%"=="-out:" set "OCR_OUT=%ARG:~5%"
goto :argloop
:argdone

rem ---- validate -mode value (only none / word / line allowed) ----
if /i "%OCR_MODE%"=="none" goto :mode_ok
if /i "%OCR_MODE%"=="word" goto :mode_ok
if /i "%OCR_MODE%"=="line" goto :mode_ok
echo [ERROR] Invalid -mode value: "%OCR_MODE%" ^(allowed: none / word / line^)
exit /b 1
:mode_ok

rem ---- invoke embedded PowerShell using the OS OCR engine ----
rem ---- image path / mode / out are passed via environment variables ----
rem ---- -ExecutionPolicy Bypass bypasses the local execution policy ----
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$ErrorActionPreference='Stop';[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;Add-Type -AssemblyName System.Runtime.WindowsRuntime;$null=[Windows.Foundation.IAsyncOperation`1,Windows.Foundation,ContentType=WindowsRuntime];$null=[Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime];$null=[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime];$null=[Windows.Graphics.Imaging.BitmapDecoder,Windows.Foundation,ContentType=WindowsRuntime];$null=[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Foundation,ContentType=WindowsRuntime];$asTaskGeneric=([System.WindowsRuntimeSystemExtensions].GetMethods()|Where-Object{$_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'})[0];function Await($t,$rt){$a=$asTaskGeneric.MakeGenericMethod($rt);$nt=$a.Invoke($null,@($t));$nt.Wait(-1)|Out-Null;return $nt.Result};$img=$env:OCR_IMG;$mode=$env:OCR_MODE;$out=$env:OCR_OUT;$netStream=[System.IO.File]::OpenRead($img);$stream=[System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($netStream);$decoder=Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder]);$bmp=Await ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,[Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied)) ([Windows.Graphics.Imaging.SoftwareBitmap]);$width=$bmp.PixelWidth;$height=$bmp.PixelHeight;$ocrLang=New-Object 'Windows.Globalization.Language' -ArgumentList 'zh-Hans-CN';$engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($ocrLang);if($null -eq $engine){[Console]::WriteLine('错误: 缺少中文简体 OCR 语言包 zh-Hans-CN，无法创建中文 OCR 引擎。');[Console]::WriteLine('请到「设置 - 时间和语言 - 语言」中为中文(简体)安装 OCR 功能后重试。');$avail=@([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages);$names=@($avail|ForEach-Object{$_.LanguageTag});if($names.Count -gt 0){[Console]::WriteLine('当前可用 OCR 语言: '+($names -join ', '))};exit 2};$result=Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult]);$resultText='';if($mode -eq 'word'){$items=New-Object System.Collections.ArrayList;foreach($line in $result.Lines){foreach($word in $line.Words){$r=$word.BoundingRect;$null=$items.Add(@{text=$word.Text;x=[int]$r.X;y=[int]$r.Y;w=[int]$r.Width;h=[int]$r.Height})}}$payload=@{image_width=$width;image_height=$height;items=@($items)};$resultText=($payload|ConvertTo-Json -Depth 4)};if($mode -eq 'line'){$items=New-Object System.Collections.ArrayList;foreach($line in $result.Lines){$minX=[double]::MaxValue;$minY=[double]::MaxValue;$maxR=[double]::MinValue;$maxB=[double]::MinValue;foreach($word in $line.Words){$r=$word.BoundingRect;$minX=[Math]::Min($minX,$r.X);$minY=[Math]::Min($minY,$r.Y);$maxR=[Math]::Max($maxR,$r.X+$r.Width);$maxB=[Math]::Max($maxB,$r.Y+$r.Height)}if(@($line.Words).Count -eq 0){$x=0;$y=0;$w=0;$h=0}else{$x=[int]$minX;$y=[int]$minY;$w=[int]($maxR-$minX);$h=[int]($maxB-$minY)}$null=$items.Add(@{text=$line.Text;x=$x;y=$y;w=$w;h=$h})}$payload=@{image_width=$width;image_height=$height;items=@($items)};$resultText=($payload|ConvertTo-Json -Depth 4)};if($mode -eq 'none'){$resultText=[string]$result.Text};if($mode -ne 'none'){$resultText=[regex]::Replace($resultText,'\\u([0-9a-fA-F]{4})',{param($m)[char][Convert]::ToInt32($m.Groups[1].Value,16)})};if($out -and $out.Length -gt 0){[System.IO.File]::WriteAllText($out,$resultText,(New-Object 'System.Text.UTF8Encoding' -ArgumentList $false));[Console]::WriteLine('已写入输出文件: '+$out)}else{[Console]::WriteLine($resultText)};exit 0}catch{$e=$_.Exception;while($e.InnerException){$e=$e.InnerException};[Console]::WriteLine('识别失败: '+$e.Message);exit 3}"
exit /b %errorlevel%

rem ============================================================
rem  Examples:
rem   1. Plain text only (default, no coordinates):
rem      ocr.bat test.jpg
rem   2. Word-level coordinate JSON printed to console:
rem      ocr.bat test.jpg -mode:word
rem   3. Line-level coordinates written to result.json:
rem      ocr.bat test.png -mode:line -out:result.json
rem ============================================================
