REM Oracle DB 스키마 수집 오케스트레이터 - 11개 SQL 스크립트 순차 실행 및 JSON 병합

@echo off
chcp 949 >nul
setlocal enabledelayedexpansion

title Oracle DB Schema Collector

:MAIN_LOOP
echo.
echo ================================================================
echo                   Oracle DB Schema Collector
echo ================================================================
echo.

echo DB 접속 방식을 선택하세요:
echo   1: TNS Alias ^(예: ORCL^)
echo   2: EZ Connect ^(예: 192.168.1.10:1521/ORCL^)
echo.
set /p CHOICE=선택 ^(1 또는 2^): 

if "!CHOICE!"=="1" goto TNS_INPUT
if "!CHOICE!"=="2" goto EZ_INPUT
echo 잘못된 선택입니다. 1 또는 2를 입력하세요.
goto MAIN_LOOP

:TNS_INPUT
echo.
set /p DB_ALIAS=DB 별칭 입력 ^(출력 폴더명^): 
set /p USERNAME=사용자명 ^(Oracle username^): 
set /p PASSWORD=비밀번호: 
set /p TNS_ALIAS=TNS Alias: 
set CONNECT=!USERNAME!/!PASSWORD!@!TNS_ALIAS!
goto CREATE_FOLDER

:EZ_INPUT
echo.
set /p DB_ALIAS=DB 별칭 입력 ^(출력 폴더명^): 
set /p USERNAME=사용자명 ^(Oracle username^): 
set /p PASSWORD=비밀번호: 
set /p EZ_CONNECT=Host:Port/SID ^(예: 192.168.1.10:1521/ORCL^): 
set CONNECT=!USERNAME!/!PASSWORD!@!EZ_CONNECT!
goto CREATE_FOLDER

:CREATE_FOLDER
echo.
echo 출력 폴더 생성: output/!DB_ALIAS!/
if not exist "output\!DB_ALIAS!" (
    mkdir "output\!DB_ALIAS!"
    if errorlevel 1 (
        echo 오류: 폴더 생성 실패
        goto MAIN_LOOP
    )
)

echo.
echo DB 연결 테스트 중...
sqlplus -S !CONNECT! @sql/test-connection.sql >nul 2>&1
if errorlevel 1 (
    echo.
    echo DB 연결 실패. 접속 정보를 확인하세요.
    echo.
    set /p RETRY=재시도 하시겠습니까? ^(Y/N^): 
    if /i "!RETRY!"=="Y" goto MAIN_LOOP
    goto END
)

echo.
echo ================================================================
echo                        스키마 수집 시작
echo ================================================================
echo.

sqlplus -S !CONNECT! @sql/collect-tables.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-tables.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-columns.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-columns.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-fks.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-fks.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-indexes.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-indexes.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-comments.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-comments.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-views.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-views.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-triggers.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-triggers.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-sequences.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-sequences.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-packages.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-packages.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-procedures.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-procedures.sql 수집 실패. 계속 진행합니다.
)

sqlplus -S !CONNECT! @sql/collect-sample-data.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: collect-sample-data.sql 수집 실패. 계속 진행합니다.
)

echo.
echo ================================================================
echo                      JSON 병합 시작
echo ================================================================
echo.

sqlplus -S !CONNECT! @sql/build-json.sql !DB_ALIAS!
if errorlevel 1 (
    echo 경고: build-json.sql 실행 실패.
    goto ASK_CONTINUE
)

if exist "output\!DB_ALIAS!\schema.json" (
    for %%F in ("output\!DB_ALIAS!\schema.json") do set FILE_SIZE=%%~zF
    set /a SIZE_KB=!FILE_SIZE!/1024
    echo.
    echo ================================================================
    echo                     수집 완료
    echo ================================================================
    echo 출력 파일: output\!DB_ALIAS!\schema.json
    echo 파일 크기: !SIZE_KB! KB ^(!FILE_SIZE! bytes^)
    echo ================================================================
) else (
    echo 경고: schema.json 파일이 생성되지 않았습니다.
)

:ASK_CONTINUE
echo.
set /p CONTINUE=다른 DB도 수집하시겠습니까? ^(Y/N^): 
if /i "!CONTINUE!"=="Y" goto MAIN_LOOP

:END
echo.
echo schema-viewer.html을 브라우저에서 열어 결과를 확인하세요.
echo.
endlocal