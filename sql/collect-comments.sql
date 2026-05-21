-- 테이블/컬럼 코멘트를 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';

SPOOL output/&1/comments.json

DECLARE
    v_tables_json CLOB;
    v_columns_json CLOB;
    v_first_table BOOLEAN := TRUE;
    v_first_column BOOLEAN := TRUE;
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_tables_json, TRUE);
    DBMS_LOB.CREATETEMPORARY(v_columns_json, TRUE);

    DBMS_LOB.APPEND(v_tables_json, '{"tables":[');
    DBMS_LOB.APPEND(v_columns_json, '"columns":[');

    FOR t IN (SELECT TABLE_NAME, COMMENTS
              FROM USER_TAB_COMMENTS
              WHERE TABLE_TYPE = 'TABLE' AND COMMENTS IS NOT NULL
              ORDER BY TABLE_NAME) LOOP

        IF NOT v_first_table THEN
            DBMS_LOB.APPEND(v_tables_json, ',');
        END IF;

        DBMS_LOB.APPEND(v_tables_json, '{"name":"' || t.TABLE_NAME ||
                      '","comment":"' || REPLACE(REPLACE(t.COMMENTS, '\', '\\'), '"', '\"') || '"}');
        v_first_table := FALSE;
    END LOOP;

    FOR c IN (SELECT TABLE_NAME, COLUMN_NAME, COMMENTS
              FROM USER_COL_COMMENTS
              WHERE COMMENTS IS NOT NULL
              ORDER BY TABLE_NAME, COLUMN_NAME) LOOP

        IF NOT v_first_column THEN
            DBMS_LOB.APPEND(v_columns_json, ',');
        END IF;

        DBMS_LOB.APPEND(v_columns_json, '{"table":"' || c.TABLE_NAME ||
                      '","column":"' || c.COLUMN_NAME ||
                      '","comment":"' || REPLACE(REPLACE(c.COMMENTS, '\', '\\'), '"', '\"') || '"}');
        v_first_column := FALSE;
    END LOOP;

    DBMS_LOB.APPEND(v_tables_json, '],');
    DBMS_LOB.APPEND(v_tables_json, v_columns_json);
    DBMS_LOB.APPEND(v_tables_json, ']}');

    FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_tables_json) / 32767) LOOP
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_tables_json, 32767, (i - 1) * 32767 + 1));
    END LOOP;

    DBMS_LOB.FREETEMPORARY(v_tables_json);
    DBMS_LOB.FREETEMPORARY(v_columns_json);
END;
/

SPOOL OFF
EXIT;