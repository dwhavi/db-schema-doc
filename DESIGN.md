# DB Schema Doc — 개발 기획서

## 1. 프로젝트 개요

오프라인(폐쇄망) 환경에서 Oracle DB 스키마를 자동 수집하여 HTML 대시보드로 문서화하는 도구.

### 핵심 제약사항
- **OS:** Windows 10 Enterprise LTSC
- **네트워크:** 인터넷 차단 (폐쇄망)
- **DB:** Oracle (원격, 여러 물리적 서버)
- **DB 접속 도구:** Orange for Oracle
- **런타임:** SQL*Plus (Oracle Client에 포함), .NET 3.5 (낮음, 업데이트 불가)
- **Python:** 설치 불확실
- **소스 유출:** 절대 불가. 모든 산출물은 로컬 파일만

### 확정된 기술 스택
- **수집:** SQL*Plus 스크립트 (.bat + .sql)
- **중간 포맷:** JSON 파일
- **뷰어:** HTML 단일 파일 (JavaScript 내장, 외부 의존성 없음)

---

## 2. 아키텍처

```
┌─────────────────────────────────────────────────────┐
│  Step 1: 수집 (collect-schema.bat)                   │
│                                                       │
│  사용자가 DB 접속 정보 입력                            │
│  → SQL*Plus로 원격 Oracle DB에 접속                   │
│  → 메타데이터를 JSON으로 직접 출력 (SPOOL)             │
│  → output/{DB별칭}/schema.json 생성                   │
│                                                       │
│  여러 DB 반복 수집 가능 (Y/N 선택)                     │
└──────────────────┬──────────────────────────────────┘
                   │ JSON 파일들
                   ▼
┌─────────────────────────────────────────────────────┐
│  Step 2: 열람 (schema-viewer.html)                   │
│                                                       │
│  브라우저에서 HTML 파일 열기                           │
│  → JSON 파일들을 드래그앤드롭 또는 파일 선택            │
│  → DB별 콤보박스로 전환                               │
│  → 테이블/컬럼/FK/인덱스/패키지 열람                   │
│  → 검색, 필터, FK 클릭으로 참조 테이블 이동            │
└─────────────────────────────────────────────────────┘
```

---

## 3. 파일 구조

```
db-schema-doc/
├── collect-schema.bat          # 메인 수집 실행파일
├── sql/
│   ├── collect-tables.sql      # 테이블 기본 정보
│   ├── collect-columns.sql     # 컬럼 상세 정보
│   ├── collect-fks.sql         # FK 관계
│   ├── collect-indexes.sql     # 인덱스
│   ├── collect-views.sql       # 뷰 + 소스코드
│   ├── collect-triggers.sql    # 트리거
│   ├── collect-sequences.sql   # 시퀀스
│   ├── collect-comments.sql    # 테이블/컬럼 코멘트
│   ├── collect-packages.sql    # 패키지 헤더 + 바디 소스
│   ├── collect-procedures.sql  # 독립 프로시저/함수 소스
│   └── collect-sample-data.sql # 샘플 데이터 (상위 5건)
├── build-json.sql              # 모든 CSV를 JSON으로 병합 출력
├── schema-viewer.html          # HTML 뷰어 (단일 파일)
└── output/                     # 수집 결과 저장소
    ├── DB1/
    │   └── schema.json
    ├── DB2/
    │   └── schema.json
    └── ...
```

---

## 4. 수집 스크립트 상세

### 4.1 collect-schema.bat

```
동작 흐름:
1. chcp 949 (한글 안깨지게)
2. DB 접속 방식 선택 (TNS alias / EZ Connect)
3. 접속 정보 입력 (사용자명, 비밀번호, TNS alias 또는 host:port/sid)
4. output/{DB별칭}/ 폴더 생성
5. SQL*Plus로 각 .sql 스크립트 순차 실행 → JSON 출력
6. 다른 DB도 수집할지 Y/N
7. 완료 메시지

필수 규칙:
- setlocal enabledelayedexpansion 사용
- 변수는 !VAR! 사용 (%VAR% 아님)
- if/else 블록 대신 goto 분기 사용
- 괄호 특수문자 escape: ^) ^|
```

### 4.2 SQL 스크립트별 수집 내용

#### collect-tables.sql
```
출력: JSON 배열
수집 항목:
- TABLE_NAME
- NUM_ROWS (COUNT(*)로 정확한 값)
- LAST_ANALYZED
```

#### collect-columns.sql
```
출력: JSON 배열
수집 항목:
- TABLE_NAME
- COLUMN_NAME
- DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE
- NULLABLE (Y/N)
- DATA_DEFAULT
- COLUMN_ID (순서)
참조: USER_TAB_COLUMNS
```

#### collect-fks.sql
```
출력: JSON 배열
수집 항목:
- CONSTRAINT_NAME
- TABLE_NAME (FK 걸린 테이블)
- COLUMN_NAME (FK 걸린 컬럼)
- R_TABLE_NAME (참조 대상 테이블)
- R_COLUMN_NAME (참조 대상 컬럼)
참조: USER_CONSTRAINTS + USER_CONS_COLUMNS
```

#### collect-indexes.sql
```
출력: JSON 배열
수집 항목:
- INDEX_NAME
- TABLE_NAME
- UNIQUENESS (UNIQUE/NONUNIQUE)
- COLUMN_NAME
- COLUMN_POSITION
- DESCEND (ASC/DESC)
참조: USER_INDEXES + USER_IND_COLUMNS
```

#### collect-comments.sql
```
출력: JSON 배열
수집 항목:
- TABLE_NAME + TABLE_TYPE + COMMENTS (USER_TAB_COMMENTS)
- TABLE_NAME + COLUMN_NAME + COMMENTS (USER_COL_COMMENTS)
```

#### collect-views.sql
```
출력: JSON 배열
수집 항목:
- VIEW_NAME
- TEXT (뷰 소스코드)
참조: USER_VIEWS
```

#### collect-triggers.sql
```
출력: JSON 배열
수집 항목:
- TRIGGER_NAME
- TABLE_NAME
- TRIGGERING_EVENT (INSERT/UPDATE/DELETE)
- TRIGGER_TYPE (BEFORE/AFTER/INSTEAD OF)
- TRIGGER_BODY (소스코드)
참조: USER_TRIGGERS
```

#### collect-sequences.sql
```
출력: JSON 배열
수집 항목:
- SEQUENCE_NAME
- MIN_VALUE, MAX_VALUE
- INCREMENT_BY
- LAST_NUMBER
- CACHE_SIZE, CYCLE_FLAG
참조: USER_SEQUENCES
```

#### collect-packages.sql ★중요
```
출력: JSON 객체
수집 항목:
- PACKAGE_NAME
- HEADER_SOURCE (PACKAGE 소스 전체)
- BODY_SOURCE (PACKAGE BODY 소스 전체)
- PROCEDURES[] (자동 파싱 결과)
  - NAME (프로시저/함수명)
  - TYPE (PROCEDURE / FUNCTION)
  - RETURN_TYPE (FUNCTION인 경우만)
  - PARAMS[]
    - NAME
    - MODE (IN / OUT / IN OUT)
    - DATA_TYPE
참조: USER_SOURCE WHERE TYPE IN ('PACKAGE', 'PACKAGE BODY')

파싱 로직:
1. PACKAGE 소스에서 PROCEDURE/FUNCTION 선언 추출
2. 괄호 안 파라미터 파싱 (이름, 모드, 타입)
3. FUNCTION은 RETURN 타입 추출
4. 오버로딩 지원 (동일 이름 다른 파라미터 → 별도 항목)
5. 동적 SQL 분석은 제외
```

#### collect-procedures.sql
```
출력: JSON 배열 (패키지에 속하지 않는 독립 프로시저/함수)
수집 항목:
- OBJECT_NAME
- OBJECT_TYPE (PROCEDURE / FUNCTION)
- SOURCE (소스코드 전체)
- PROCEDURES[] (collect-packages.sql과 동일 파싱)
참조: USER_SOURCE WHERE TYPE IN ('PROCEDURE', 'FUNCTION')
```

#### collect-sample-data.sql
```
출력: JSON 객체 { TABLE_NAME: [ {COL: VAL, ...}, ... ] }
수집 항목:
- USER_TABLES의 모든 테이블에 대해
- SELECT * FROM {TABLE} WHERE ROWNUM <= 5
- 민감정보 마스킹 없음 (테스트 서버)
- 날짜는 ISO 포맷 (YYYY-MM-DD HH24:MI:SS)
- NULL 값은 JSON null로 표현
```

### 4.3 JSON 출력 형식

최종 schema.json 구조:
```json
{
  "metadata": {
    "dbAlias": "ORCL",
    "collectedAt": "2026-05-21T14:30:00",
    "oracleVersion": "Oracle Database 19c...",
    "currentUser": "SCOTT",
    "serverHost": "192.168.1.10",
    "dbName": "TESTDB"
  },
  "tables": [
    {
      "name": "TB_EMPLOYEE",
      "rows": 1250,
      "comment": "직원 마스터",
      "columns": [
        {
          "name": "EMP_ID",
          "type": "NUMBER",
          "length": 10,
          "precision": null,
          "scale": null,
          "nullable": false,
          "default": null,
          "position": 1,
          "comment": "직원ID",
          "key": "PK"
        }
      ],
      "indexes": [
        {
          "name": "PK_EMPLOYEE",
          "unique": true,
          "columns": ["EMP_ID"]
        }
      ],
      "foreignKeys": [
        {
          "name": "FK_EMP_DEPT",
          "column": "DEPT_ID",
          "refTable": "TB_DEPARTMENT",
          "refColumn": "DEPT_ID"
        }
      ],
      "sampleData": [
        {"EMP_ID": 1001, "EMP_NM": "김개발", "DEPT_ID": 10}
      ]
    }
  ],
  "views": [
    {
      "name": "VW_EMP_DETAIL",
      "source": "CREATE OR REPLACE VIEW..."
    }
  ],
  "triggers": [
    {
      "name": "TRG_EMP_HIST",
      "table": "TB_EMPLOYEE",
      "event": "INSERT OR UPDATE",
      "type": "AFTER",
      "source": "BEGIN ..."
    }
  ],
  "sequences": [
    {
      "name": "SEQ_EMPLOYEE",
      "minValue": 1,
      "maxValue": 9999999999,
      "incrementBy": 1,
      "lastNumber": 1251
    }
  ],
  "packages": [
    {
      "name": "PKG_ORDER",
      "headerSource": "PACKAGE PKG_ORDER IS ...",
      "bodySource": "PACKAGE BODY PKG_ORDER IS ...",
      "procedures": [
        {
          "name": "SP_ORDER_CREATE",
          "type": "PROCEDURE",
          "returnType": null,
          "params": [
            {"name": "P_CUST_ID", "mode": "IN", "dataType": "NUMBER"},
            {"name": "P_TOTAL", "mode": "OUT", "dataType": "NUMBER"}
          ]
        },
        {
          "name": "FN_ORDER_STATUS",
          "type": "FUNCTION",
          "returnType": "VARCHAR2",
          "params": [
            {"name": "P_ORDER_ID", "mode": "IN", "dataType": "NUMBER"}
          ]
        }
      ]
    }
  ],
  "standaloneProcedures": [
    {
      "name": "SP_SYNC_DATA",
      "type": "PROCEDURE",
      "source": "CREATE OR REPLACE PROCEDURE...",
      "procedures": [
        {
          "name": "SP_SYNC_DATA",
          "type": "PROCEDURE",
          "returnType": null,
          "params": [...]
        }
      ]
    }
  ]
}
```

---

## 5. HTML 뷰어 상세

### 5.1 기본 요구사항
- 단일 HTML 파일 (CSS + JS 모두 내장)
- 외부 CDN, 외부 라이브러리 사용 금절 (오프라인)
- JSON 파일을 **드래그앤드롭** 또는 **파일 선택 버튼**으로 로드
- 여러 JSON 파일 로드 시 **콤보박스로 DB 선택**하여 전환

### 5.2 화면 구성

```
┌─────────────────────────────────────────────────────┐
│ 📊 DB Schema Doc   [DB선택 콤보박스▼]   [JSON열기]  │
├─────────────────────────────────────────────────────┤
│ [검색창________________________]                     │
├──────────┬──────────────────────────────────────────┤
│ 사이드바  │  메인 콘텐츠                               │
│          │                                            │
│ 테이블    │  선택한 테이블/패키지 상세 정보              │
│ ├ TB_xxx │                                            │
│ ├ TB_yyy │  탭: 컬럼 | 관계도 | 샘플데이터 | 인덱스    │
│ └ ...    │                                            │
│          │                                            │
│ 뷰       │  또는                                       │
│ ├ VW_xxx │                                            │
│          │  패키지 상세                                │
│ 패키지   │  ├ 프로시저 목록 (파라미터 포함)             │
│ ├ PKG_xx │  ├ 소스코드 보기                            │
│ └ ...    │                                            │
│          │                                            │
│ 트리거   │                                            │
│ 시퀀스   │                                            │
└──────────┴──────────────────────────────────────────┘
```

### 5.3 기능 목록

#### 검색
- 테이블명, 컬럼명, 패키지명, 프로시저명 통합 검색
- 입력 즉시 필터링 (디바운스 300ms)

#### 테이블 상세
- 컬럼 목록 (타입, NULL, 기본값, KEY, 코멘트)
- PK/FK 태그 표시
- FK 컬럼 클릭 → 참조 테이블로 이동
- 관계도 (텍스트 기반)
- 샘플 데이터 테이블
- 인덱스 목록

#### 패키지 상세 ★중요
- 패키지 내 프로시저/함수 목록
- 각 프로시저 파라미터 표 (이름, 모드 IN/OUT, 타입)
- FUNCTION은 RETURN 타입 표시
- 소스코드 보기 (헤더 / 바디 탭 분리)
- 소스코드에 줄번호 표시

#### 뷰 / 트리거 / 시퀀스
- 소스코드 보기 (뷰, 트리거)
- 속성 표시 (시퀀스: 증분, 마지막 값 등)

---

## 6. 파일 인코딩 규칙

| 파일 타입 | 인코딩 | 줄바꿈 | 비고 |
|-----------|--------|--------|------|
| .bat | CP949 (ANSI) | CRLF | chcp 949 필수 |
| .sql | UTF-8 | CRLF | Oracle SQL*Plus 호환 |
| .html | UTF-8 (BOM 없음) | LF/CRLF | charset=UTF-8 명시 |

### .bat 파일 필수 패턴
```bat
@echo off
chcp 949 >nul
setlocal enabledelayedexpansion

REM 변수 참조는 !VAR! 사용
REM if/else 블록 대신 goto 분기 사용
REM 괄호 escape: ^) ^|
```

---

## 7. SQL*Plus JSON 출력 기법

SQL*Plus에서 직접 JSON을 생성하는 방법:

```sql
-- SPOOL로 파일 출력
SET FEEDBACK OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET TERMOUT OFF
SET TRIMSPOOL ON

SPOOL output/schema.json

-- JSON 시작
SELECT '{' FROM DUAL;
SELECT '"tables": [' FROM DUAL;

-- 테이블별 JSON 생성 (LISTAGG 또는 커서 활용)
SELECT '  {"name": "' || TABLE_NAME || '", "rows": ' || COUNT(*) || '}' 
FROM USER_TABLES;

-- JSON 끝
SELECT ']}' FROM DUAL;

SPOOL OFF
EXIT;
```

**주의사항:**
- LINESIZE 최대 32767
- CLOB이 긴 경우 (패키지 소스) 청크 분할 필요
- JSON 이스케이프: `"` → `\"`, `\` → `\\`, 줄바꿈 → `\n`
- 날짜 포맷: `ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'`

---

## 8. 개발 순서

### Phase 1: 수집 스크립트
1. `collect-tables.sql` — 테이블 정보 → JSON
2. `collect-columns.sql` — 컬럼 정보 → JSON
3. `collect-fks.sql` — FK 관계 → JSON
4. `collect-indexes.sql` — 인덱스 → JSON
5. `collect-comments.sql` — 코멘트 → JSON
6. `collect-sample-data.sql` — 샘플 데이터 → JSON
7. `collect-views.sql` — 뷰 → JSON
8. `collect-triggers.sql` — 트리거 → JSON
9. `collect-sequences.sql` — 시퀀스 → JSON
10. `collect-packages.sql` — 패키지 + 파싱 → JSON
11. `collect-procedures.sql` — 독립 프로시저 → JSON
12. `build-json.sql` — 개별 결과를 하나의 schema.json으로 병합

### Phase 2: 배치 파일
13. `collect-schema.bat` — 전체 수집 오케스트레이션

### Phase 3: HTML 뷰어
14. `schema-viewer.html` — 전체 뷰어

### Phase 4: 패키징
15. CP949 + CRLF 변환
16. ZIP 패키징

---

## 9. 검증 방법

1. `collect-sample.bat` 실행 → SQL*Plus + DB 연결 확인
2. `collect-schema.bat` 실행 → output/{DB}/schema.json 생성 확인
3. `schema-viewer.html` 브라우저 열기 → JSON 드래그앤드롭 → 대시보드 렌더링 확인
4. 여러 DB JSON 로드 → 콤보박스 전환 확인
5. 패키지 → 프로시저 파라미터 목록 표시 확인
6. FK 클릭 → 참조 테이블 이동 확인
