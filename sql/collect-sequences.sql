-- 시퀀스 정보를 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';

SPOOL output/&1/sequences.json

DECLARE
    v_json CLOB;
    v_first BOOLEAN := TRUE;
    v_line VARCHAR2(32767);
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);
    DBMS_LOB.APPEND(v_json, '[');

    FOR s IN (SELECT SEQUENCE_NAME, MIN_VALUE, MAX_VALUE, INCREMENT_BY,
                     LAST_NUMBER, CACHE_SIZE, CYCLE_FLAG
              FROM USER_SEQUENCES
              ORDER BY SEQUENCE_NAME) LOOP

        IF NOT v_first THEN
            DBMS_LOB.APPEND(v_json, ',');
        END IF;

        v_line := '{"name":"' || s.SEQUENCE_NAME ||
                  '","minValue":' || s.MIN_VALUE ||
                  ',"maxValue":' || s.MAX_VALUE ||
                  ',"incrementBy":' || s.INCREMENT_BY ||
                  ',"lastNumber":' || s.LAST_NUMBER ||
                  ',"cacheSize":' || s.CACHE_SIZE ||
                  ',"cycleFlag":"' || s.CYCLE_FLAG || '"}';
        DBMS_LOB.APPEND(v_json, v_line);
        v_first := FALSE;
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