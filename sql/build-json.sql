-- 전체 스키마를 수집하여 최종 schema.json을 생성하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';

SPOOL output/&1/schema.json

DECLARE
    v_json CLOB;
    v_oracle_version VARCHAR2(4000);
    v_current_user VARCHAR2(128);
    v_server_host VARCHAR2(128);
    v_db_name VARCHAR2(128);
    v_collected_at VARCHAR2(100);
    v_db_alias VARCHAR2(128) := '&1';

    -- 헬퍼 함수: JSON 문자열 이스케이프
    FUNCTION escape_json(p_text IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN REPLACE(REPLACE(p_text, '\', '\\'), '"', '\"');
    END;

    -- 헬퍼 함수: JSON 값 출력 (NULL 체크 포함)
    FUNCTION json_str(p_val IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        IF p_val IS NULL THEN
            RETURN 'null';
        END IF;
        RETURN '"' || escape_json(p_val) || '"';
    END;

    -- 헬퍼 함수: JSON 값 출력 (숫자)
    FUNCTION json_num(p_val IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF p_val IS NULL THEN
            RETURN 'null';
        END IF;
        RETURN TO_CHAR(p_val);
    END;

    -- 헬퍼 함수: JSON 값 출력 (BOOLEAN)
    FUNCTION json_bool(p_val IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        IF p_val = 'Y' OR p_val = 'TRUE' THEN
            RETURN 'true';
        ELSE
            RETURN 'false';
        END IF;
    END;

    -- 패키지에서 프로시저/함수 파싱하는 함수
    FUNCTION parse_procedures(p_pkg_name IN VARCHAR2, p_source IN CLOB) RETURN CLOB IS
        v_result CLOB;
        v_source_upper VARCHAR2(32000);
        v_pos NUMBER := 1;
        v_proc_name VARCHAR2(128);
        v_proc_type VARCHAR2(20);
        v_params_part VARCHAR2(32000);
        v_return_type VARCHAR2(4000);
        v_first_proc BOOLEAN := TRUE;
        v_signature VARCHAR2(32000);
        v_line_text VARCHAR2(32000);
        v_prev_line VARCHAR2(32000);
        v_match VARCHAR2(4000);
    BEGIN
        DBMS_LOB.CREATETEMPORARY(v_result, TRUE);
        DBMS_LOB.APPEND(v_result, '[');

        v_source_upper := UPPER(DBMS_LOB.SUBSTR(p_source, 32000, 1));

        FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(p_source) / 32000) LOOP
            v_source_upper := UPPER(DBMS_LOB.SUBSTR(p_source, 32000, (i - 1) * 32000 + 1));

            FOR j IN 1..10 LOOP
                v_pos := REGEXP_INSTR(v_source_upper, 'PROCEDURE|FUNCTION', v_pos, 1, 0, 'i');

                IF v_pos = 0 THEN
                    EXIT;
                END IF;

                v_signature := REGEXP_SUBSTR(DBMS_LOB.SUBSTR(p_source, 32000, (i - 1) * 32000 + 1),
                    'PROCEDURE\s+\w+\s*\(.*\)|FUNCTION\s+\w+\s*\(.*\)\s+RETURN\s+\w+(?:\([^)]*\))?', 1, j, 'i');

                IF v_signature IS NULL THEN
                    EXIT;
                END IF;

                IF REGEXP_LIKE(v_signature, 'FUNCTION', 'i') THEN
                    v_proc_type := 'FUNCTION';
                ELSE
                    v_proc_type := 'PROCEDURE';
                END IF;

                v_proc_name := REGEXP_SUBSTR(v_signature, '\w+', 1, 1, 'i');

                v_params_part := NULL;
                IF REGEXP_INSTR(v_signature, '\(', 1, 1) > 0 AND REGEXP_INSTR(v_signature, '\)', 1, 1) > 0 THEN
                    v_params_part := REGEXP_SUBSTR(v_signature, '\((.*)\)', 1, 1, 'i');
                END IF;

                v_return_type := NULL;
                IF v_proc_type = 'FUNCTION' AND REGEXP_LIKE(v_signature, 'RETURN', 'i') THEN
                    v_return_type := REGEXP_SUBSTR(v_signature, 'RETURN\s+(\w+(?:\([^)]*\))?)', 1, 1, 'i', 1);
                END IF;

                IF NOT v_first_proc THEN
                    DBMS_LOB.APPEND(v_result, ',');
                END IF;

                DBMS_LOB.APPEND(v_result, '{"name":"' || v_proc_name || '","type":"' || v_proc_type ||
                              '","returnType":' || NVL('"' || v_return_type || '"', 'null') || ',"params":[');

                IF v_params_part IS NOT NULL THEN
                    DECLARE
                        v_param_list VARCHAR2(32000) := v_params_part;
                        v_param VARCHAR2(1000);
                        v_first_param BOOLEAN := TRUE;
                        v_pos_comma NUMBER;
                        v_pos_paren NUMBER;
                        v_depth NUMBER;
                        v_p_name VARCHAR2(128);
                        v_p_mode VARCHAR2(20) := 'IN';
                        v_p_type VARCHAR2(4000);
                        v_param_upper VARCHAR2(1000);
                    BEGIN
                        WHILE LENGTH(v_param_list) > 0 LOOP
                            v_depth := 0;
                            v_pos_comma := 0;

                            FOR k IN 1..LENGTH(v_param_list) LOOP
                                IF SUBSTR(v_param_list, k, 1) = '(' THEN
                                    v_depth := v_depth + 1;
                                ELSIF SUBSTR(v_param_list, k, 1) = ')' THEN
                                    v_depth := v_depth - 1;
                                ELSIF SUBSTR(v_param_list, k, 1) = ',' AND v_depth = 0 THEN
                                    v_pos_comma := k;
                                    EXIT;
                                END IF;
                            END LOOP;

                            IF v_pos_comma > 0 THEN
                                v_param := TRIM(SUBSTR(v_param_list, 1, v_pos_comma - 1));
                                v_param_list := TRIM(SUBSTR(v_param_list, v_pos_comma + 1));
                            ELSE
                                v_param := TRIM(v_param_list);
                                v_param_list := '';
                            END IF;

                            v_param_upper := UPPER(v_param);

                            IF REGEXP_LIKE(v_param_upper, '\bIN\s+OUT\b') THEN
                                v_p_mode := 'IN OUT';
                            ELSIF REGEXP_LIKE(v_param_upper, '\bOUT\b') THEN
                                v_p_mode := 'OUT';
                            ELSE
                                v_p_mode := 'IN';
                            END IF;

                            v_p_name := REGEXP_SUBSTR(v_param, '\w+', 1, 1, 'i');
                            v_p_type := REGEXP_REPLACE(v_param, '(IN\s+OUT|OUT|IN)\s*', '', 1, 0, 'i');

                            IF NOT v_first_param THEN
                                DBMS_LOB.APPEND(v_result, ',');
                            END IF;

                            DBMS_LOB.APPEND(v_result, '{"name":"' || v_p_name || '","mode":"' || v_p_mode ||
                                          '","dataType":"' || v_p_type || '"}');
                            v_first_param := FALSE;
                        END LOOP;
                    END;
                END IF;

                DBMS_LOB.APPEND(v_result, ']}');
                v_first_proc := FALSE;
            END LOOP;
        END LOOP;

        DBMS_LOB.APPEND(v_result, ']');
        RETURN v_result;
    END;

    -- 독립 프로시저/함수 파싱하는 함수
    FUNCTION parse_single_procedure(p_proc_name IN VARCHAR2, p_type IN VARCHAR2, p_source IN CLOB) RETURN CLOB IS
        v_result CLOB;
        v_signature VARCHAR2(32000);
        v_params_part VARCHAR2(32000);
        v_return_type VARCHAR2(4000);
        v_proc_type VARCHAR2(20);
    BEGIN
        DBMS_LOB.CREATETEMPORARY(v_result, TRUE);
        DBMS_LOB.APPEND(v_result, '[');

        v_proc_type := p_type;
        v_signature := UPPER(DBMS_LOB.SUBSTR(p_source, 32000, 1));

        v_params_part := NULL;
        IF REGEXP_INSTR(v_signature, '\(', 1, 1) > 0 AND REGEXP_INSTR(v_signature, '\)', 1, 1) > 0 THEN
            v_params_part := REGEXP_SUBSTR(v_signature, '\((.*)\)', 1, 1, 'i');
        END IF;

        v_return_type := NULL;
        IF v_proc_type = 'FUNCTION' AND REGEXP_LIKE(v_signature, 'RETURN', 'i') THEN
            v_return_type := REGEXP_SUBSTR(v_signature, 'RETURN\s+(\w+(?:\([^)]*\))?)', 1, 1, 'i', 1);
        END IF;

        DBMS_LOB.APPEND(v_result, '{"name":"' || p_proc_name || '","type":"' || v_proc_type ||
                      '","returnType":' || NVL('"' || v_return_type || '"', 'null') || ',"params":[');

        IF v_params_part IS NOT NULL THEN
            DECLARE
                v_param_list VARCHAR2(32000) := v_params_part;
                v_param VARCHAR2(1000);
                v_first_param BOOLEAN := TRUE;
                v_pos_comma NUMBER;
                v_depth NUMBER;
                v_p_name VARCHAR2(128);
                v_p_mode VARCHAR2(20) := 'IN';
                v_p_type VARCHAR2(4000);
                v_param_upper VARCHAR2(1000);
            BEGIN
                WHILE LENGTH(v_param_list) > 0 LOOP
                    v_depth := 0;
                    v_pos_comma := 0;

                    FOR k IN 1..LENGTH(v_param_list) LOOP
                        IF SUBSTR(v_param_list, k, 1) = '(' THEN
                            v_depth := v_depth + 1;
                        ELSIF SUBSTR(v_param_list, k, 1) = ')' THEN
                            v_depth := v_depth - 1;
                        ELSIF SUBSTR(v_param_list, k, 1) = ',' AND v_depth = 0 THEN
                            v_pos_comma := k;
                            EXIT;
                        END IF;
                    END LOOP;

                    IF v_pos_comma > 0 THEN
                        v_param := TRIM(SUBSTR(v_param_list, 1, v_pos_comma - 1));
                        v_param_list := TRIM(SUBSTR(v_param_list, v_pos_comma + 1));
                    ELSE
                        v_param := TRIM(v_param_list);
                        v_param_list := '';
                    END IF;

                    v_param_upper := UPPER(v_param);

                    IF REGEXP_LIKE(v_param_upper, '\bIN\s+OUT\b') THEN
                        v_p_mode := 'IN OUT';
                    ELSIF REGEXP_LIKE(v_param_upper, '\bOUT\b') THEN
                        v_p_mode := 'OUT';
                    ELSE
                        v_p_mode := 'IN';
                    END IF;

                    v_p_name := REGEXP_SUBSTR(v_param, '\w+', 1, 1, 'i');
                    v_p_type := REGEXP_REPLACE(v_param, '(IN\s+OUT|OUT|IN)\s*', '', 1, 0, 'i');

                    IF NOT v_first_param THEN
                        DBMS_LOB.APPEND(v_result, ',');
                    END IF;

                    DBMS_LOB.APPEND(v_result, '{"name":"' || v_p_name || '","mode":"' || v_p_mode ||
                                  '","dataType":"' || v_p_type || '"}');
                    v_first_param := FALSE;
                END LOOP;
            END;
        END IF;

        DBMS_LOB.APPEND(v_result, ']}]');
        RETURN v_result;
    END;

BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);

    -- 메타데이터 수집
    SELECT BANNER INTO v_oracle_version FROM V$VERSION WHERE ROWNUM = 1;
    v_current_user := USER;
    v_server_host := SYS_CONTEXT('USERENV', 'HOST');
    v_db_name := SYS_CONTEXT('USERENV', 'DB_NAME');
    v_collected_at := TO_CHAR(SYSDATE, 'YYYY-MM-DD') || 'T' || TO_CHAR(SYSDATE, 'HH24:MI:SS');

    DBMS_LOB.APPEND(v_json, '{');
    DBMS_LOB.APPEND(v_json, '"metadata":{');
    DBMS_LOB.APPEND(v_json, '"dbAlias":' || json_str(v_db_alias) || ',');
    DBMS_LOB.APPEND(v_json, '"collectedAt":' || json_str(v_collected_at) || ',');
    DBMS_LOB.APPEND(v_json, '"oracleVersion":' || json_str(v_oracle_version) || ',');
    DBMS_LOB.APPEND(v_json, '"currentUser":' || json_str(v_current_user) || ',');
    DBMS_LOB.APPEND(v_json, '"serverHost":' || json_str(v_server_host) || ',');
    DBMS_LOB.APPEND(v_json, '"dbName":' || json_str(v_db_name));
    DBMS_LOB.APPEND(v_json, '},');
    DBMS_LOB.APPEND(v_json, '"tables":[');

    -- 테이블 수집 (컬럼, 인덱스, FK, 코멘트, 샘플데이터 포함)
    DECLARE
        v_first_table BOOLEAN := TRUE;
        v_row_count NUMBER;
        v_table_comment VARCHAR2(4000);
        v_first_col BOOLEAN;
        v_data_default LONG;
        v_default_value VARCHAR2(4000);
        v_default_json VARCHAR2(4000);
        v_first_idx BOOLEAN;
        v_idx_columns VARCHAR2(32767);
        v_first_fk BOOLEAN;
        v_r_table_name USER_CONSTRAINTS.TABLE_NAME%TYPE;
        v_r_column_name USER_CONS_COLUMNS.COLUMN_NAME%TYPE;
        v_first_row BOOLEAN;
        v_first_col_in_row BOOLEAN;
        v_cursor_id INTEGER;
        v_col_count NUMBER;
        v_desc_tab DBMS_SQL.DESC_TAB;
        v_status NUMBER;
        v_val VARCHAR2(4000);
    BEGIN
        FOR t IN (SELECT TABLE_NAME, LAST_ANALYZED FROM USER_TABLES ORDER BY TABLE_NAME) LOOP
            -- 행 수 조회
            BEGIN
                EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || t.TABLE_NAME INTO v_row_count;
            EXCEPTION
                WHEN OTHERS THEN
                    v_row_count := NULL;
            END;

            -- 테이블 코멘트 조회
            BEGIN
                SELECT COMMENTS INTO v_table_comment
                FROM USER_TAB_COMMENTS
                WHERE TABLE_NAME = t.TABLE_NAME AND TABLE_TYPE = 'TABLE';
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_table_comment := NULL;
            END;

            IF NOT v_first_table THEN
                DBMS_LOB.APPEND(v_json, ',');
            END IF;

            DBMS_LOB.APPEND(v_json, '{"name":"' || t.TABLE_NAME || '"');
            DBMS_LOB.APPEND(v_json, ',"rows":' || json_num(v_row_count));
            DBMS_LOB.APPEND(v_json, ',"comment":' || json_str(v_table_comment));
            DBMS_LOB.APPEND(v_json, ',"columns":[');

            -- 컬럼 수집
            v_first_col := TRUE;
            FOR c IN (SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, DATA_LENGTH,
                             DATA_PRECISION, DATA_SCALE, NULLABLE, COLUMN_ID
                      FROM USER_TAB_COLUMNS
                      WHERE TABLE_NAME = t.TABLE_NAME
                      ORDER BY COLUMN_ID) LOOP

                -- 기본값 조회
                BEGIN
                    SELECT DATA_DEFAULT INTO v_data_default
                    FROM USER_TAB_COLUMNS
                    WHERE TABLE_NAME = c.TABLE_NAME AND COLUMN_NAME = c.COLUMN_NAME;

                    IF v_data_default IS NOT NULL THEN
                        v_default_value := DBMS_LOB.SUBSTR(TO_LOB(v_data_default), 4000, 1);
                        v_default_json := '"' || escape_json(v_default_value) || '"';
                    ELSE
                        v_default_json := 'null';
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_default_json := 'null';
                END;

                IF NOT v_first_col THEN
                    DBMS_LOB.APPEND(v_json, ',');
                END IF;

                DBMS_LOB.APPEND(v_json, '{"name":"' || c.COLUMN_NAME || '"');
                DBMS_LOB.APPEND(v_json, ',"type":"' || c.DATA_TYPE || '"');
                DBMS_LOB.APPEND(v_json, ',"length":' || json_num(c.DATA_LENGTH));
                DBMS_LOB.APPEND(v_json, ',"precision":' || json_num(c.DATA_PRECISION));
                DBMS_LOB.APPEND(v_json, ',"scale":' || json_num(c.DATA_SCALE));
                DBMS_LOB.APPEND(v_json, ',"nullable":' || json_bool(c.NULLABLE));
                DBMS_LOB.APPEND(v_json, ',"default":' || v_default_json);
                DBMS_LOB.APPEND(v_json, ',"position":' || json_num(c.COLUMN_ID));

                -- 컬럼 코멘트
                DECLARE
                    v_col_comment VARCHAR2(4000);
                BEGIN
                    SELECT COMMENTS INTO v_col_comment
                    FROM USER_COL_COMMENTS
                    WHERE TABLE_NAME = c.TABLE_NAME AND COLUMN_NAME = c.COLUMN_NAME;
                    DBMS_LOB.APPEND(v_json, ',"comment":' || json_str(v_col_comment));
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        NULL;
                END;

                DBMS_LOB.APPEND(v_json, '}');
                v_first_col := FALSE;
            END LOOP;

            DBMS_LOB.APPEND(v_json, ']');

            -- 인덱스 수집
            DBMS_LOB.APPEND(v_json, ',"indexes":[');
            v_first_idx := TRUE;
            FOR idx IN (SELECT INDEX_NAME, TABLE_NAME, UNIQUENESS
                        FROM USER_INDEXES
                        WHERE TABLE_NAME = t.TABLE_NAME AND INDEX_TYPE = 'NORMAL'
                        ORDER BY INDEX_NAME) LOOP

                v_idx_columns := '';

                FOR col IN (SELECT COLUMN_NAME
                            FROM USER_IND_COLUMNS
                            WHERE INDEX_NAME = idx.INDEX_NAME
                            ORDER BY COLUMN_POSITION) LOOP

                    IF v_idx_columns IS NOT NULL THEN
                        v_idx_columns := v_idx_columns || ',';
                    END IF;

                    v_idx_columns := v_idx_columns || '"' || col.COLUMN_NAME || '"';
                END LOOP;

                IF NOT v_first_idx THEN
                    DBMS_LOB.APPEND(v_json, ',');
                END IF;

                DBMS_LOB.APPEND(v_json, '{"name":"' || idx.INDEX_NAME || '"');
                DBMS_LOB.APPEND(v_json, ',"unique":' || json_bool(idx.UNIQUENESS));
                DBMS_LOB.APPEND(v_json, ',"columns":[' || v_idx_columns || ']}');
                v_first_idx := FALSE;
            END LOOP;

            DBMS_LOB.APPEND(v_json, ']');

            -- FK 수집
            DBMS_LOB.APPEND(v_json, ',"foreignKeys":[');
            v_first_fk := TRUE;
            FOR fk IN (SELECT uc.CONSTRAINT_NAME, uc.TABLE_NAME, ucc.COLUMN_NAME, uc.R_CONSTRAINT_NAME
                       FROM USER_CONSTRAINTS uc
                       JOIN USER_CONS_COLUMNS ucc ON uc.CONSTRAINT_NAME = ucc.CONSTRAINT_NAME
                       WHERE uc.CONSTRAINT_TYPE = 'R' AND uc.TABLE_NAME = t.TABLE_NAME
                       ORDER BY uc.CONSTRAINT_NAME, ucc.POSITION) LOOP

                BEGIN
                    SELECT c.TABLE_NAME, cc.COLUMN_NAME
                    INTO v_r_table_name, v_r_column_name
                    FROM USER_CONSTRAINTS c
                    JOIN USER_CONS_COLUMNS cc ON c.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
                    WHERE c.CONSTRAINT_NAME = fk.R_CONSTRAINT_NAME
                    AND cc.POSITION = 1;

                    IF NOT v_first_fk THEN
                        DBMS_LOB.APPEND(v_json, ',');
                    END IF;

                    DBMS_LOB.APPEND(v_json, '{"name":"' || fk.CONSTRAINT_NAME || '"');
                    DBMS_LOB.APPEND(v_json, ',"column":"' || fk.COLUMN_NAME || '"');
                    DBMS_LOB.APPEND(v_json, ',"refTable":"' || v_r_table_name || '"');
                    DBMS_LOB.APPEND(v_json, ',"refColumn":"' || v_r_column_name || '"}');
                    v_first_fk := FALSE;
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL;
                END;
            END LOOP;

            DBMS_LOB.APPEND(v_json, ']');

            -- 샘플 데이터 수집
            DBMS_LOB.APPEND(v_json, ',"sampleData":[');
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
                    v_first_col_in_row := TRUE;

                    FOR i IN 1..v_col_count LOOP
                        DBMS_SQL.COLUMN_VALUE(v_cursor_id, i, v_val);

                        IF v_first_col_in_row THEN
                            v_first_col_in_row := FALSE;
                        ELSE
                            DBMS_LOB.APPEND(v_json, ',');
                        END IF;

                        DBMS_LOB.APPEND(v_json, '"' || v_desc_tab(i).COL_NAME || '":');

                        IF v_val IS NULL THEN
                            DBMS_LOB.APPEND(v_json, 'null');
                        ELSIF v_desc_tab(i).COL_TYPE IN (1, 2, 96) THEN
                            IF REGEXP_LIKE(v_val, '^-?\d+$') THEN
                                DBMS_LOB.APPEND(v_json, v_val);
                            ELSE
                                DBMS_LOB.APPEND(v_json, '"' || escape_json(v_val) || '"');
                            END IF;
                        ELSE
                            DBMS_LOB.APPEND(v_json, '"' || escape_json(v_val) || '"');
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

            DBMS_LOB.APPEND(v_json, '}');
            v_first_table := FALSE;
        END LOOP;
    END;

    DBMS_LOB.APPEND(v_json, '],');
    DBMS_LOB.APPEND(v_json, '"views":[');

    -- 뷰 수집
    DECLARE
        v_first_view BOOLEAN := TRUE;
        v_source CLOB;
        v_chunk VARCHAR2(30000);
    BEGIN
        FOR v IN (SELECT VIEW_NAME, TEXT FROM USER_VIEWS ORDER BY VIEW_NAME) LOOP
            DBMS_LOB.CREATETEMPORARY(v_source, TRUE);

            IF v.TEXT IS NOT NULL THEN
                DBMS_LOB.COPY(v_source, v.TEXT, DBMS_LOB.GETLENGTH(v.TEXT), 1, 1);
            END IF;

            IF NOT v_first_view THEN
                DBMS_LOB.APPEND(v_json, ',');
            END IF;

            DBMS_LOB.APPEND(v_json, '{"name":"' || v.VIEW_NAME || '","source":"');

            FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_source) / 30000) LOOP
                v_chunk := DBMS_LOB.SUBSTR(v_source, 30000, (i - 1) * 30000 + 1);
                v_chunk := escape_json(v_chunk);
                v_chunk := REPLACE(v_chunk, CHR(10), '\n');
                v_chunk := REPLACE(v_chunk, CHR(13), '');
                DBMS_LOB.APPEND(v_json, v_chunk);
            END LOOP;

            DBMS_LOB.APPEND(v_json, '"}');
            v_first_view := FALSE;

            DBMS_LOB.FREETEMPORARY(v_source);
        END LOOP;
    END;

    DBMS_LOB.APPEND(v_json, '],');
    DBMS_LOB.APPEND(v_json, '"triggers":[');

    -- 트리거 수집
    DECLARE
        v_first_trigger BOOLEAN := TRUE;
        v_body CLOB;
        v_chunk VARCHAR2(30000);
    BEGIN
        FOR trg IN (SELECT TRIGGER_NAME, TABLE_NAME, TRIGGERING_EVENT, TRIGGER_TYPE, TRIGGER_BODY
                    FROM USER_TRIGGERS
                    ORDER BY TRIGGER_NAME) LOOP

            DBMS_LOB.CREATETEMPORARY(v_body, TRUE);

            IF trg.TRIGGER_BODY IS NOT NULL THEN
                DBMS_LOB.COPY(v_body, trg.TRIGGER_BODY, DBMS_LOB.GETLENGTH(trg.TRIGGER_BODY), 1, 1);
            END IF;

            IF NOT v_first_trigger THEN
                DBMS_LOB.APPEND(v_json, ',');
            END IF;

            DBMS_LOB.APPEND(v_json, '{"name":"' || trg.TRIGGER_NAME || '"');
            DBMS_LOB.APPEND(v_json, ',"table":"' || trg.TABLE_NAME || '"');
            DBMS_LOB.APPEND(v_json, ',"event":"' || trg.TRIGGERING_EVENT || '"');
            DBMS_LOB.APPEND(v_json, ',"type":"' || trg.TRIGGER_TYPE || '"');
            DBMS_LOB.APPEND(v_json, ',"source":"');

            FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_body) / 30000) LOOP
                v_chunk := DBMS_LOB.SUBSTR(v_body, 30000, (i - 1) * 30000 + 1);
                v_chunk := escape_json(v_chunk);
                v_chunk := REPLACE(v_chunk, CHR(10), '\n');
                v_chunk := REPLACE(v_chunk, CHR(13), '');
                DBMS_LOB.APPEND(v_json, v_chunk);
            END LOOP;

            DBMS_LOB.APPEND(v_json, '"}');
            v_first_trigger := FALSE;

            DBMS_LOB.FREETEMPORARY(v_body);
        END LOOP;
    END;

    DBMS_LOB.APPEND(v_json, '],');
    DBMS_LOB.APPEND(v_json, '"sequences":[');

    -- 시퀀스 수집
    DECLARE
        v_first_seq BOOLEAN := TRUE;
    BEGIN
        FOR s IN (SELECT SEQUENCE_NAME, MIN_VALUE, MAX_VALUE, INCREMENT_BY,
                         LAST_NUMBER, CACHE_SIZE, CYCLE_FLAG
                  FROM USER_SEQUENCES
                  ORDER BY SEQUENCE_NAME) LOOP

            IF NOT v_first_seq THEN
                DBMS_LOB.APPEND(v_json, ',');
            END IF;

            DBMS_LOB.APPEND(v_json, '{"name":"' || s.SEQUENCE_NAME || '"');
            DBMS_LOB.APPEND(v_json, ',"minValue":' || json_num(s.MIN_VALUE));
            DBMS_LOB.APPEND(v_json, ',"maxValue":' || json_num(s.MAX_VALUE));
            DBMS_LOB.APPEND(v_json, ',"incrementBy":' || json_num(s.INCREMENT_BY));
            DBMS_LOB.APPEND(v_json, ',"lastNumber":' || json_num(s.LAST_NUMBER));
            DBMS_LOB.APPEND(v_json, ',"cacheSize":' || json_num(s.CACHE_SIZE));
            DBMS_LOB.APPEND(v_json, ',"cycleFlag":"' || s.CYCLE_FLAG || '"}');
            v_first_seq := FALSE;
        END LOOP;
    END;

    DBMS_LOB.APPEND(v_json, '],');
    DBMS_LOB.APPEND(v_json, '"packages":[');

    -- 패키지 수집
    DECLARE
        v_first_pkg BOOLEAN := TRUE;
        v_header_source CLOB;
        v_body_source CLOB;
        v_procedures_json CLOB;
        v_chunk VARCHAR2(30000);
    BEGIN
        FOR pkg IN (SELECT DISTINCT NAME FROM USER_SOURCE WHERE TYPE IN ('PACKAGE', 'PACKAGE BODY') ORDER BY NAME) LOOP
            DBMS_LOB.CREATETEMPORARY(v_header_source, TRUE);
            DBMS_LOB.CREATETEMPORARY(v_body_source, TRUE);

            FOR s IN (SELECT TEXT FROM USER_SOURCE WHERE NAME = pkg.NAME AND TYPE = 'PACKAGE' ORDER BY LINE) LOOP
                DBMS_LOB.APPEND(v_header_source, s.TEXT);
            END LOOP;

            FOR s IN (SELECT TEXT FROM USER_SOURCE WHERE NAME = pkg.NAME AND TYPE = 'PACKAGE BODY' ORDER BY LINE) LOOP
                DBMS_LOB.APPEND(v_body_source, s.TEXT);
            END LOOP;

            v_procedures_json := parse_procedures(pkg.NAME, v_header_source);

            IF NOT v_first_pkg THEN
                DBMS_LOB.APPEND(v_json, ',');
            END IF;

            DBMS_LOB.APPEND(v_json, '{"name":"' || pkg.NAME || '","headerSource":"');

            FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_header_source) / 30000) LOOP
                v_chunk := DBMS_LOB.SUBSTR(v_header_source, 30000, (i - 1) * 30000 + 1);
                v_chunk := escape_json(v_chunk);
                v_chunk := REPLACE(v_chunk, CHR(10), '\n');
                v_chunk := REPLACE(v_chunk, CHR(13), '');
                DBMS_LOB.APPEND(v_json, v_chunk);
            END LOOP;

            DBMS_LOB.APPEND(v_json, '","bodySource":"');

            FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_body_source) / 30000) LOOP
                v_chunk := DBMS_LOB.SUBSTR(v_body_source, 30000, (i - 1) * 30000 + 1);
                v_chunk := escape_json(v_chunk);
                v_chunk := REPLACE(v_chunk, CHR(10), '\n');
                v_chunk := REPLACE(v_chunk, CHR(13), '');
                DBMS_LOB.APPEND(v_json, v_chunk);
            END LOOP;

            DBMS_LOB.APPEND(v_json, '","procedures":' || v_procedures_json || '}');
            v_first_pkg := FALSE;

            DBMS_LOB.FREETEMPORARY(v_header_source);
            DBMS_LOB.FREETEMPORARY(v_body_source);
            DBMS_LOB.FREETEMPORARY(v_procedures_json);
        END LOOP;
    END;

    DBMS_LOB.APPEND(v_json, '],');
    DBMS_LOB.APPEND(v_json, '"standaloneProcedures":[');

    -- 독립 프로시저/함수 수집
    DECLARE
        v_first_proc BOOLEAN := TRUE;
        v_source CLOB;
        v_procedures_json CLOB;
        v_chunk VARCHAR2(30000);
    BEGIN
        FOR obj IN (SELECT DISTINCT NAME, TYPE
                    FROM USER_SOURCE
                    WHERE TYPE IN ('PROCEDURE', 'FUNCTION')
                    ORDER BY NAME, TYPE) LOOP

            DBMS_LOB.CREATETEMPORARY(v_source, TRUE);

            FOR s IN (SELECT TEXT FROM USER_SOURCE WHERE NAME = obj.NAME AND TYPE = obj.TYPE ORDER BY LINE) LOOP
                DBMS_LOB.APPEND(v_source, s.TEXT);
            END LOOP;

            v_procedures_json := parse_single_procedure(obj.NAME, obj.TYPE, v_source);

            IF NOT v_first_proc THEN
                DBMS_LOB.APPEND(v_json, ',');
            END IF;

            DBMS_LOB.APPEND(v_json, '{"name":"' || obj.NAME || '"');
            DBMS_LOB.APPEND(v_json, ',"type":"' || obj.TYPE || '"');
            DBMS_LOB.APPEND(v_json, ',"source":"');

            FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_source) / 30000) LOOP
                v_chunk := DBMS_LOB.SUBSTR(v_source, 30000, (i - 1) * 30000 + 1);
                v_chunk := escape_json(v_chunk);
                v_chunk := REPLACE(v_chunk, CHR(10), '\n');
                v_chunk := REPLACE(v_chunk, CHR(13), '');
                DBMS_LOB.APPEND(v_json, v_chunk);
            END LOOP;

            DBMS_LOB.APPEND(v_json, '","procedures":' || v_procedures_json || '}');
            v_first_proc := FALSE;

            DBMS_LOB.FREETEMPORARY(v_source);
            DBMS_LOB.FREETEMPORARY(v_procedures_json);
        END LOOP;
    END;

    DBMS_LOB.APPEND(v_json, ']}');

    -- 출력
    FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_json) / 32767) LOOP
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_json, 32767, (i - 1) * 32767 + 1));
    END LOOP;

    DBMS_LOB.FREETEMPORARY(v_json);
END;
/

SPOOL OFF
EXIT;