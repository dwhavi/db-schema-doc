-- 인덱스 정보를 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';

SPOOL output/&1/indexes.json

DECLARE
    v_json CLOB;
    v_first_index BOOLEAN := TRUE;
    v_columns VARCHAR2(32767);
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);
    DBMS_LOB.APPEND(v_json, '[');

    FOR idx IN (SELECT INDEX_NAME, TABLE_NAME, UNIQUENESS
                FROM USER_INDEXES
                WHERE INDEX_TYPE = 'NORMAL'
                ORDER BY TABLE_NAME, INDEX_NAME) LOOP

        v_columns := '';

        FOR col IN (SELECT COLUMN_NAME, DESCEND
                    FROM USER_IND_COLUMNS
                    WHERE INDEX_NAME = idx.INDEX_NAME
                    ORDER BY COLUMN_POSITION) LOOP

            IF v_columns IS NOT NULL THEN
                v_columns := v_columns || ',';
            END IF;

            v_columns := v_columns || '"' || col.COLUMN_NAME || '"';
        END LOOP;

        IF NOT v_first_index THEN
            DBMS_LOB.APPEND(v_json, ',');
        END IF;

        DBMS_LOB.APPEND(v_json, '{"name":"' || idx.INDEX_NAME || '","table":"' || idx.TABLE_NAME ||
                      '","unique":' || CASE WHEN idx.UNIQUENESS = 'UNIQUE' THEN 'true' ELSE 'false' END ||
                      ',"columns":[' || v_columns || ']}');
        v_first_index := FALSE;
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