-- 외래키(FK) 관계를 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';

SPOOL output/&1/fks.json

DECLARE
    v_json CLOB;
    v_first BOOLEAN := TRUE;
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);
    DBMS_LOB.APPEND(v_json, '[');

    FOR fk IN (SELECT uc.CONSTRAINT_NAME, uc.TABLE_NAME, ucc.COLUMN_NAME,
                      uc.R_CONSTRAINT_NAME
               FROM USER_CONSTRAINTS uc
               JOIN USER_CONS_COLUMNS ucc ON uc.CONSTRAINT_NAME = ucc.CONSTRAINT_NAME
               WHERE uc.CONSTRAINT_TYPE = 'R'
               ORDER BY uc.TABLE_NAME, uc.CONSTRAINT_NAME, ucc.POSITION) LOOP

        DECLARE
            v_r_table_name USER_CONSTRAINTS.TABLE_NAME%TYPE;
            v_r_column_name USER_CONS_COLUMNS.COLUMN_NAME%TYPE;
            v_line VARCHAR2(32767);
        BEGIN
            SELECT c.TABLE_NAME, cc.COLUMN_NAME
            INTO v_r_table_name, v_r_column_name
            FROM USER_CONSTRAINTS c
            JOIN USER_CONS_COLUMNS cc ON c.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
            WHERE c.CONSTRAINT_NAME = fk.R_CONSTRAINT_NAME
            AND cc.POSITION = 1;

            IF NOT v_first THEN
                DBMS_LOB.APPEND(v_json, ',');
            END IF;

            v_line := '{"name":"' || fk.CONSTRAINT_NAME || '","table":"' || fk.TABLE_NAME ||
                     '","column":"' || fk.COLUMN_NAME || '","refTable":"' || v_r_table_name ||
                     '","refColumn":"' || v_r_column_name || '"}';
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