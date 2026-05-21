-- 테이블 기본 정보를 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';

SPOOL output/&1/tables.json

DECLARE
    v_json CLOB;
    v_first BOOLEAN := TRUE;
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);
    DBMS_LOB.APPEND(v_json, '[');

    FOR t IN (SELECT TABLE_NAME, LAST_ANALYZED FROM USER_TABLES ORDER BY TABLE_NAME) LOOP
        DECLARE
            v_row_count NUMBER;
            v_line VARCHAR2(32767);
        BEGIN
            BEGIN
                EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || t.TABLE_NAME INTO v_row_count;
            EXCEPTION
                WHEN OTHERS THEN
                    v_row_count := NULL;
            END;

            IF NOT v_first THEN
                DBMS_LOB.APPEND(v_json, ',');
            END IF;

            v_line := '{"name":"' || t.TABLE_NAME || '","rows":' || NVL(TO_CHAR(v_row_count), 'null') || ',"lastAnalyzed":' ||
                     CASE WHEN t.LAST_ANALYZED IS NOT NULL THEN '"' || TO_CHAR(t.LAST_ANALYZED, 'YYYY-MM-DD HH24:MI:SS') || '"' ELSE 'null' END ||
                     '}';
            DBMS_LOB.APPEND(v_json, v_line);
            v_first := FALSE;
        END;
    END LOOP;

    DBMS_LOB.APPEND(v_json, ']');

    FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_json) / 32767) LOOP
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_json, 32767, (i - 1) * 32767 + 1));
    END LOOP;

    DBMS_LOB.FREETEMPORARY(v_json);
END;
/

SPOOL OFF
EXIT;