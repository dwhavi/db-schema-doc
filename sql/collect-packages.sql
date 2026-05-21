-- 패키지와 프로시저/함수 정보를 파싱하여 JSON으로 수집하는 스크립트
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON
SET VERIFY OFF
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';
SET SERVEROUTPUT ON SIZE UNLIMITED

SPOOL output/&1/packages.json

DECLARE
    v_json CLOB;
    v_first_pkg BOOLEAN := TRUE;
    v_header_source CLOB;
    v_body_source CLOB;
    v_procedures_json CLOB;
    v_line VARCHAR2(32767);

    FUNCTION escape_json(p_text IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN REPLACE(REPLACE(p_text, '\', '\\'), '"', '\"');
    END;

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
BEGIN
    DBMS_LOB.CREATETEMPORARY(v_json, TRUE);
    DBMS_LOB.APPEND(v_json, '[');

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

        v_line := '{"name":"' || pkg.NAME || '","headerSource":"';
        DBMS_LOB.APPEND(v_json, v_line);

        FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_header_source) / 30000) LOOP
            DECLARE
                v_chunk VARCHAR2(30000);
            BEGIN
                v_chunk := DBMS_LOB.SUBSTR(v_header_source, 30000, (i - 1) * 30000 + 1);
                v_chunk := escape_json(v_chunk);
                v_chunk := REPLACE(v_chunk, CHR(10), '\n');
                v_chunk := REPLACE(v_chunk, CHR(13), '');
                DBMS_LOB.APPEND(v_json, v_chunk);
            END;
        END LOOP;

        v_line := '","bodySource":"';
        DBMS_LOB.APPEND(v_json, v_line);

        FOR i IN 1..CEIL(DBMS_LOB.GETLENGTH(v_body_source) / 30000) LOOP
            DECLARE
                v_chunk VARCHAR2(30000);
            BEGIN
                v_chunk := DBMS_LOB.SUBSTR(v_body_source, 30000, (i - 1) * 30000 + 1);
                v_chunk := escape_json(v_chunk);
                v_chunk := REPLACE(v_chunk, CHR(10), '\n');
                v_chunk := REPLACE(v_chunk, CHR(13), '');
                DBMS_LOB.APPEND(v_json, v_chunk);
            END;
        END LOOP;

        DBMS_LOB.APPEND(v_json, '","procedures":' || v_procedures_json || '}');
        v_first_pkg := FALSE;

        DBMS_LOB.FREETEMPORARY(v_header_source);
        DBMS_LOB.FREETEMPORARY(v_body_source);
        DBMS_LOB.FREETEMPORARY(v_procedures_json);
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