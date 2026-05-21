-- 뷰 소스코드를 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';

SPOOL output/&1/views.json

DECLARE
    v_json CLOB;
    v_first BOOLEAN := TRUE;
    v_source CLOB;
    v_line VARCHAR2(32767);
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);
    DBMS_LOB.APPEND(v_json, '[');

    FOR v IN (SELECT VIEW_NAME, TEXT FROM USER_VIEWS ORDER BY VIEW_NAME) LOOP
        DBMS_LOB.CREATETEMPORARY(v_source, TRUE);

        IF v.TEXT IS NOT NULL THEN
            DBMS_LOB.COPY(v_source, v.TEXT, DBMS_LOB.GETLENGTH(v.TEXT), 1, 1);
        END IF;

        IF NOT v_first THEN
            DBMS_LOB.APPEND(v_json, ',');
        END IF;

        v_line := '{"name":"' || v.VIEW_NAME || '","source":"';
        DBMS_LOB.APPEND(v_json, v_line);

        FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_source) / 30000) LOOP
            DECLARE
                v_chunk VARCHAR2(30000);
            BEGIN
                v_chunk := DBMS_LOB.SUBSTR(v_source, 30000, (i - 1) * 30000 + 1);
                v_chunk := REPLACE(REPLACE(v_chunk, '\', '\\'), '"', '\"');
                v_chunk := REPLACE(v_chunk, CHR(10), '\n');
                v_chunk := REPLACE(v_chunk, CHR(13), '');
                DBMS_LOB.APPEND(v_json, v_chunk);
            END;
        END LOOP;

        DBMS_LOB.APPEND(v_json, '"}');
        v_first := FALSE;

        DBMS_LOB.FREETEMPORARY(v_source);
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