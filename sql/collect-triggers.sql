-- 트리거 소스코드를 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';

SPOOL output/&1/triggers.json

DECLARE
    v_json CLOB;
    v_first BOOLEAN := TRUE;
    v_body CLOB;
    v_line VARCHAR2(32767);
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);
    DBMS_LOB.APPEND(v_json, '[');

    FOR trg IN (SELECT TRIGGER_NAME, TABLE_NAME, TRIGGERING_EVENT, TRIGGER_TYPE, TRIGGER_BODY
                FROM USER_TRIGGERS
                ORDER BY TRIGGER_NAME) LOOP

        DBMS_LOB.CREATETEMPORARY(v_body, TRUE);

        IF trg.TRIGGER_BODY IS NOT NULL THEN
            DBMS_LOB.COPY(v_body, trg.TRIGGER_BODY, DBMS_LOB.GETLENGTH(trg.TRIGGER_BODY), 1, 1);
        END IF;

        IF NOT v_first THEN
            DBMS_LOB.APPEND(v_json, ',');
        END IF;

        v_line := '{"name":"' || trg.TRIGGER_NAME || '","table":"' || trg.TABLE_NAME ||
                  '","event":"' || trg.TRIGGERING_EVENT || '","type":"' || trg.TRIGGER_TYPE ||
                  '","source":"';
        DBMS_LOB.APPEND(v_json, v_line);

        FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_body) / 30000) LOOP
            DECLARE
                v_chunk VARCHAR2(30000);
            BEGIN
                v_chunk := DBMS_LOB.SUBSTR(v_body, 30000, (i - 1) * 30000 + 1);
                v_chunk := REPLACE(REPLACE(v_chunk, '\', '\\'), '"', '\"');
                v_chunk := REPLACE(v_chunk, CHR(10), '\n');
                v_chunk := REPLACE(v_chunk, CHR(13), '');
                DBMS_LOB.APPEND(v_json, v_chunk);
            END;
        END LOOP;

        DBMS_LOB.APPEND(v_json, '"}');
        v_first := FALSE;

        DBMS_LOB.FREETEMPORARY(v_body);
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