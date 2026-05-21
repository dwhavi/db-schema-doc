-- 컬럼 상세 정보를 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';

SPOOL output/&1/columns.json

DECLARE
    v_json CLOB;
    v_first BOOLEAN := TRUE;
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);
    DBMS_LOB.APPEND(v_json, '[');

    FOR c IN (SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, DATA_LENGTH,
                     DATA_PRECISION, DATA_SCALE, NULLABLE, COLUMN_ID
              FROM USER_TAB_COLUMNS
              ORDER BY TABLE_NAME, COLUMN_ID) LOOP

        DECLARE
            v_data_default LONG;
            v_default_value VARCHAR2(4000);
            v_default_json VARCHAR2(4000);
            v_line VARCHAR2(32767);
            v_nullable VARCHAR2(5);
        BEGIN
            BEGIN
                SELECT DATA_DEFAULT INTO v_data_default
                FROM USER_TAB_COLUMNS
                WHERE TABLE_NAME = c.TABLE_NAME AND COLUMN_NAME = c.COLUMN_NAME;

                IF v_data_default IS NOT NULL THEN
                    v_default_value := DBMS_LOB.SUBSTR(TO_LOB(v_data_default), 4000, 1);
                    v_default_json := '"' || REPLACE(REPLACE(v_default_value, '\', '\\'), '"', '\"') || '"';
                ELSE
                    v_default_json := 'null';
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    v_default_json := 'null';
            END;

            v_nullable := CASE WHEN c.NULLABLE = 'Y' THEN 'true' ELSE 'false' END;

            IF NOT v_first THEN
                DBMS_LOB.APPEND(v_json, ',');
            END IF;

            v_line := '{"table":"' || c.TABLE_NAME || '","name":"' || c.COLUMN_NAME ||
                     '","type":"' || c.DATA_TYPE || '","length":' || c.DATA_LENGTH ||
                     ',"precision":' || NVL(TO_CHAR(c.DATA_PRECISION), 'null') ||
                     ',"scale":' || NVL(TO_CHAR(c.DATA_SCALE), 'null') ||
                     ',"nullable":' || v_nullable ||
                     ',"default":' || v_default_json ||
                     ',"position":' || c.COLUMN_ID || '}';
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