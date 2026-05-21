-- 모든 테이블의 샘플 데이터(상위 5건)를 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';
SET SERVEROUTPUT ON SIZE UNLIMITED

SPOOL output/&1/sample-data.json

DECLARE
    v_json CLOB;
    v_first_table BOOLEAN := TRUE;
    v_first_row BOOLEAN;
    v_first_col BOOLEAN;
    v_col_value VARCHAR2(4000);
    v_col_name VARCHAR2(128);
    v_cursor_id INTEGER;
    v_col_count NUMBER;
    v_desc_tab DBMS_SQL.DESC_TAB;
    v_status NUMBER;
    v_val VARCHAR2(4000);
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);
    DBMS_LOB.APPEND(v_json, '{');

    FOR t IN (SELECT TABLE_NAME FROM USER_TABLES ORDER BY TABLE_NAME) LOOP
        IF NOT v_first_table THEN
            DBMS_LOB.APPEND(v_json, ',');
        END IF;

        DBMS_LOB.APPEND(v_json, '"' || t.TABLE_NAME || '":[');

        v_first_row := TRUE;

        BEGIN
            v_cursor_id := DBMS_SQL.OPEN_CURSOR;
            DBMS_SQL.PARSE(v_cursor_id, 'SELECT * FROM ' || t.TABLE_NAME || ' WHERE ROWNUM <= 5', DBMS_SQL.NATIVE);
            DBMS_SQL.DESCRIBE_COLUMNS(v_cursor_id, v_col_count, v_desc_tab);

            FOR i IN 1..v_col_count LOOP
                DBMS_SQL.DEFINE_COLUMN(v_cursor_id, i, v_val, 4000);
            END LOOP;

            v_status := DBMS_SQL.EXECUTE(v_cursor_id);

            WHILE DBMS_SQL.FETCH_ROWS(v_cursor_id) > 0 LOOP
                IF NOT v_first_row THEN
                    DBMS_LOB.APPEND(v_json, ',');
                END IF;

                DBMS_LOB.APPEND(v_json, '{');
                v_first_col := FALSE;

                FOR i IN 1..v_col_count LOOP
                    DBMS_SQL.COLUMN_VALUE(v_cursor_id, i, v_val);
                    v_col_name := v_desc_tab(i).COL_NAME;

                    IF v_first_col THEN
                        v_first_col := FALSE;
                    ELSE
                        DBMS_LOB.APPEND(v_json, ',');
                    END IF;

                    DBMS_LOB.APPEND(v_json, '"' || v_col_name || '":');

                    IF v_val IS NULL THEN
                        DBMS_LOB.APPEND(v_json, 'null');
                    ELSIF v_desc_tab(i).COL_TYPE IN (1, 2, 96) THEN
                        IF REGEXP_LIKE(v_val, '^-?\d+$') THEN
                            DBMS_LOB.APPEND(v_json, v_val);
                        ELSE
                            DBMS_LOB.APPEND(v_json, '"' || REPLACE(REPLACE(v_val, '\', '\\'), '"', '\"') || '"');
                        END IF;
                    ELSE
                        DBMS_LOB.APPEND(v_json, '"' || REPLACE(REPLACE(v_val, '\', '\\'), '"', '\"') || '"');
                    END IF;
                END LOOP;

                DBMS_LOB.APPEND(v_json, '}');
                v_first_row := FALSE;
            END LOOP;

            DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
        EXCEPTION
            WHEN OTHERS THEN
                IF DBMS_SQL.IS_OPEN(v_cursor_id) THEN
                    DBMS_SQL.CLOSE_CURSOR(v_cursor_id);
                END IF;
        END;

        DBMS_LOB.APPEND(v_json, ']');
        v_first_table := FALSE;
    END LOOP;

    DBMS_LOB.APPEND(v_json, '}');

    FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_json) / 32767) LOOP
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_json, 32767, (i - 1) * 32767 + 1));
    END LOOP;

    DBMS_LOB.FREETEMPORARY(v_json);
END;
/

SPOOL OFF
EXIT;