@echo off
rem 一键同步：C 盘源码 -> E 盘编译工程（智慧伴学 Demo）
rem 用法：双击运行，或在任意终端执行
chcp 65001 >nul
set SRC=C:\Users\zao an\Documents\code\note\client\entry\src\main
set DST=E:\code\note\client\entry\src\main

del /f /q "%DST%\ets\pages\HomePage.ets" 2>nul
del /f /q "%DST%\ets\common\components\TwoPane.ets" 2>nul

xcopy "%SRC%\ets" "%DST%\ets" /e /y /i >nul
copy /y "%SRC%\module.json5" "%DST%\module.json5" >nul
copy /y "%SRC%\resources\base\element\string.json" "%DST%\resources\base\element\string.json" >nul

echo === C 盘 -^> E 盘 同步完成 ===
pause
