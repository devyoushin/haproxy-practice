# HAProxy Lua 스크립팅 완전 가이드

HAProxy는 Lua 5.3 스크립트를 내장하여 복잡한 로직을 구현할 수 있습니다.
ACL, http-request 규칙만으로 처리하기 어려운 동적 로직을 Lua로 구현합니다.

---

## 1. Lua 활성화

```haproxy
global
    # Lua 스크립트 로드 (여러 파일 가능)
    lua-load /etc/haproxy/scripts/auth.lua
    lua-load /etc/haproxy/scripts/routing.lua
    lua-load /etc/haproxy/scripts/logging.lua

    # 로그 설정 (Lua 스크립트에서 core.log() 사용)
    log /dev/log local0 info
```

---

## 2. Lua 기본 API

### core 오브젝트 (전역)
```lua
-- 로그 출력
core.log(core.info, "Hello from Lua!")
core.log(core.warning, "Warning message")
core.log(core.err, "Error message")

-- HAProxy 버전 확인
local version = core.version

-- DNS 조회
local ip = core.lookup_hostname("api.example.com")

-- 현재 타임스탬프
local ts = core.now()
local ts_ms = core.now().sec * 1000 + core.now().usec / 1000

-- 소켓 생성 (외부 서비스 연결)
local socket = core.tcp()

-- 맵 접근
local backend = core.map.lookup("/etc/haproxy/domains.map", "example.com")
```

### core.register_* 함수
```lua
-- Action 등록 (http-request 등에서 사용)
core.register_action("my_action", {"http-req", "http-res"}, function(txn)
    -- 처리 로직
end)

-- 서비스 등록 (완전한 HTTP 응답 처리)
core.register_service("my_service", "http", function(applet)
    -- HTTP 응답 생성
end)

-- Fetch 함수 등록 (ACL 조건에서 사용)
core.register_fetches("my_fetch", function(txn)
    -- 값 반환
    return "some_value"
end)

-- 컨버터 등록 (변환 파이프라인에서 사용)
core.register_converters("my_converter", function(input)
    return input:upper()
end)

-- 필터 등록 (HAProxy 2.2+)
core.register_filter("my_filter", {
    new = function(flt)
        return flt
    end,
    start_analyze = function(flt, txn, channel)
        return 0
    end
})
```

---

## 3. txn (Transaction) 오브젝트

```lua
-- http-request action 내에서 txn 사용
core.register_action("process_request", {"http-req"}, function(txn)

    -- HTTP 요청 정보 조회
    local method = txn.f:method()
    local path   = txn.f:path()
    local src_ip = txn.f:src()

    -- HTTP 요청 헤더 조회/수정
    local host = txn.http:req_get_headers()["host"][0]
    txn.http:req_set_header("X-Processed-By", "haproxy-lua")
    txn.http:req_del_header("X-Internal-Token")
    txn.http:req_add_header("X-Request-Time", tostring(core.now().sec))

    -- 응답 헤더 수정 (http-res action에서)
    -- txn.http:res_set_header("X-Custom-Header", "value")

    -- 변수 설정/조회 (HAProxy 변수 공간)
    txn:set_var("txn.my_var", "my_value")
    local val = txn:get_var("txn.my_var")

    -- 요청 body 읽기 (option http-buffer-request 필요)
    local body = txn.req:dup()

    -- 트랜잭션 종료 (즉시 응답)
    -- txn:done()  -- 요청 처리 중단

end, 0)  -- 0 = 추가 인자 없음
```

---

## 4. applet (Service) 오브젝트

```lua
-- 완전한 HTTP 응답 생성 (서버 없이 HAProxy가 직접 응답)
core.register_service("health_check", "http", function(applet)

    local response = '{"status":"ok","version":"1.0","timestamp":' .. tostring(os.time()) .. '}'

    applet:set_status(200)
    applet:add_header("Content-Type", "application/json")
    applet:add_header("Content-Length", tostring(#response))
    applet:add_header("Cache-Control", "no-cache")
    applet:start_response()
    applet:send(response)

end)
```

HAProxy 설정에서 서비스 사용:
```haproxy
frontend web
    bind *:80
    mode http

    # 특정 경로에서 Lua 서비스 사용
    http-request use-service lua.health_check if { path /health }

    default_backend web_backend
```

---

## 5. 실전 예시 1: JWT 토큰 검증

```lua
-- /etc/haproxy/scripts/jwt_auth.lua
-- 주의: 완전한 JWT 검증은 외부 라이브러리 필요
-- 이 예시는 기본적인 구조만 보여줌

local function base64_decode(input)
    -- Base64 URL 디코딩
    local s = input:gsub('-', '+'):gsub('_', '/')
    -- 패딩 추가
    local padding = 4 - #s % 4
    if padding < 4 then
        s = s .. string.rep('=', padding)
    end
    -- 기본 base64 디코딩 (HAProxy는 base64 decode 내장 미포함, 직접 구현 필요)
    return s  -- 실제 구현 필요
end

local function split(s, sep)
    local parts = {}
    for part in s:gmatch("[^" .. sep .. "]+") do
        table.insert(parts, part)
    end
    return parts
end

-- JWT 페이로드 디코드 (서명 검증 없음 - 신뢰할 수 없는 환경에서 사용 금지)
local function decode_jwt_payload(token)
    local parts = split(token, ".")
    if #parts ~= 3 then
        return nil, "Invalid JWT format"
    end

    local payload_b64 = parts[2]
    -- Base64 디코딩 후 JSON 파싱
    -- 실제로는 JSON 파서 라이브러리 필요
    return payload_b64
end

core.register_action("check_jwt", {"http-req"}, function(txn)
    local auth_header = txn.http:req_get_headers()["authorization"]

    if not auth_header or not auth_header[0] then
        txn.http:req_set_header("X-Auth-Status", "missing")
        return
    end

    local token = auth_header[0]:match("^Bearer%s+(.+)$")
    if not token then
        txn.http:req_set_header("X-Auth-Status", "invalid_format")
        return
    end

    -- 토큰 구조 확인
    local parts = {}
    for part in token:gmatch("[^.]+") do
        table.insert(parts, part)
    end

    if #parts ~= 3 then
        txn.http:req_set_header("X-Auth-Status", "malformed")
        return
    end

    txn.http:req_set_header("X-Auth-Status", "present")
    txn.http:req_set_header("X-Auth-Token-Length", tostring(#token))

    core.log(core.debug, "JWT token processed for " .. (txn.f:src() or "unknown"))
end)
```

---

## 6. 실전 예시 2: 동적 라우팅 (데이터베이스 기반)

```lua
-- /etc/haproxy/scripts/dynamic_routing.lua
-- 파일 기반 라우팅 테이블 (실시간 재로드 가능)

local routing_table = {}
local last_loaded = 0
local routing_file = "/etc/haproxy/routing_table.txt"

-- 라우팅 테이블 로드
local function load_routing_table()
    local current_time = os.time()

    -- 30초마다 파일 다시 읽기
    if current_time - last_loaded < 30 then
        return
    end

    local f = io.open(routing_file, "r")
    if not f then
        core.log(core.warning, "Cannot open routing table: " .. routing_file)
        return
    end

    local new_table = {}
    for line in f:lines() do
        -- 주석 제외
        if not line:match("^%s*#") and line:match("%S") then
            local pattern, backend = line:match("^(%S+)%s+(%S+)%s*$")
            if pattern and backend then
                new_table[pattern] = backend
            end
        end
    end
    f:close()

    routing_table = new_table
    last_loaded = current_time
    core.log(core.info, "Routing table reloaded: " .. #routing_table .. " entries")
end

-- 경로 기반 백엔드 결정
core.register_fetches("get_backend_for_path", function(txn)
    load_routing_table()

    local path = txn.f:path()

    -- 정확 일치 먼저
    if routing_table[path] then
        return routing_table[path]
    end

    -- 접두사 매칭
    for pattern, backend in pairs(routing_table) do
        if path:sub(1, #pattern) == pattern then
            return backend
        end
    end

    return "default_backend"
end)
```

routing_table.txt 파일:
```
# 패턴   백엔드이름
/api/v1/ api_v1_backend
/api/v2/ api_v2_backend
/auth/   auth_backend
/admin/  admin_backend
```

---

## 7. 실전 예시 3: 요청 변환 (JSON 필드 필터링)

```lua
-- /etc/haproxy/scripts/request_filter.lua
-- HTTP 요청 body에서 민감한 필드 제거

core.register_action("remove_sensitive_fields", {"http-req"}, function(txn)
    local content_type = ""
    local ct_headers = txn.http:req_get_headers()["content-type"]

    if ct_headers and ct_headers[0] then
        content_type = ct_headers[0]:lower()
    end

    -- JSON 요청만 처리
    if not content_type:find("application/json") then
        return
    end

    -- 요청 body 읽기 (option http-buffer-request 필요)
    local body = txn.req:dup()
    if not body or #body == 0 then
        return
    end

    -- 민감한 필드 제거 (간단한 패턴 매칭)
    -- 실제 JSON 파서 사용 권장
    local cleaned = body:gsub('"password"%s*:%s*"[^"]*"', '"password":"[REDACTED]"')
    cleaned = cleaned:gsub('"credit_card"%s*:%s*"[^"]*"', '"credit_card":"[REDACTED]"')
    cleaned = cleaned:gsub('"ssn"%s*:%s*"[^"]*"', '"ssn":"[REDACTED]"')

    -- 수정된 body로 교체
    if cleaned ~= body then
        txn.req:remove(0, #body)
        txn.req:append(cleaned)
        txn.http:req_set_header("Content-Length", tostring(#cleaned))
        core.log(core.debug, "Sensitive fields removed from request")
    end
end)
```

---

## 8. 실전 예시 4: 커스텀 로깅

```lua
-- /etc/haproxy/scripts/custom_logging.lua

local log_socket_path = "/var/log/haproxy-custom.sock"

-- 구조화된 로그를 파일로 직접 작성
core.register_action("custom_log", {"http-req"}, function(txn)
    local log_entry = {
        timestamp = os.time(),
        method    = txn.f:method(),
        path      = txn.f:path(),
        src_ip    = txn.f:src(),
        user_agent = ""
    }

    local ua_headers = txn.http:req_get_headers()["user-agent"]
    if ua_headers and ua_headers[0] then
        log_entry.user_agent = ua_headers[0]
    end

    -- 변수에 저장 (응답 후 로그에 추가 정보 포함)
    txn:set_var("txn.req_time", tostring(log_entry.timestamp))
    txn:set_var("txn.req_method", log_entry.method or "")
    txn:set_var("txn.req_path", log_entry.path or "")
end)

-- 응답 후 로깅
core.register_action("log_response", {"http-res"}, function(txn)
    local req_time = txn:get_var("txn.req_time") or ""
    local method   = txn:get_var("txn.req_method") or ""
    local path     = txn:get_var("txn.req_path") or ""
    local status   = txn.http:res_get_headers()[":status"]

    core.log(core.info, string.format(
        '{"time":%s,"method":"%s","path":"%s","ip":"%s"}',
        req_time, method, path, txn.f:src() or ""
    ))
end)
```

---

## 9. 실전 예시 5: IP 평판 서비스 연동

```lua
-- /etc/haproxy/scripts/ip_reputation.lua
-- 외부 API를 통한 IP 평판 조회 (비동기 처리)

local cache = {}
local cache_ttl = 300  -- 5분 캐시

local function check_ip_reputation(ip)
    -- 캐시 확인
    local cached = cache[ip]
    if cached and (os.time() - cached.time) < cache_ttl then
        return cached.result
    end

    -- 외부 API 호출 (TCP 소켓 사용)
    local socket = core.tcp()
    socket:settimeout(2)  -- 2초 타임아웃

    local ok, err = socket:connect("reputation-api.internal", 8080)
    if not ok then
        core.log(core.warning, "Cannot connect to reputation API: " .. (err or "unknown"))
        cache[ip] = {time = os.time(), result = "unknown"}
        socket:close()
        return "unknown"
    end

    -- API 요청
    socket:send("GET /check?ip=" .. ip .. " HTTP/1.0\r\nHost: reputation-api.internal\r\n\r\n")

    -- 응답 읽기
    local response = socket:receive("*l")
    socket:close()

    local result = "clean"
    if response and response:find("malicious") then
        result = "malicious"
    elseif response and response:find("suspicious") then
        result = "suspicious"
    end

    -- 캐시 저장
    cache[ip] = {time = os.time(), result = result}

    return result
end

core.register_action("check_reputation", {"http-req"}, function(txn)
    local ip = txn.f:src()
    if not ip then return end

    local reputation = check_ip_reputation(ip)

    txn.http:req_set_header("X-IP-Reputation", reputation)
    txn:set_var("txn.ip_reputation", reputation)

    if reputation == "malicious" then
        core.log(core.warning, "Blocking malicious IP: " .. ip)
        -- txn을 통해 차단할 수 없으므로 헤더로 표시하고
        -- HAProxy 규칙에서 처리
    end
end)
```

HAProxy 설정에서 사용:
```haproxy
frontend web
    bind *:80
    mode http

    # Lua로 IP 평판 확인
    http-request lua.check_reputation

    # 악성 IP 차단 (Lua가 설정한 헤더 기반)
    acl is_malicious req.hdr(X-IP-Reputation) -m str malicious
    http-request deny deny_status 403 if is_malicious

    default_backend web_backend
```

---

## 10. 실전 예시 6: 헬스체크 응답 서비스

```lua
-- /etc/haproxy/scripts/health_service.lua
-- 동적 헬스체크 응답 (백엔드 상태 포함)

core.register_service("health_service", "http", function(applet)
    local response_data = {
        status = "ok",
        timestamp = os.time(),
        version = "1.0.0",
        checks = {}
    }

    -- 간단한 JSON 생성 (실제로는 JSON 라이브러리 사용 권장)
    local response = '{'
    response = response .. '"status":"' .. response_data.status .. '",'
    response = response .. '"timestamp":' .. response_data.timestamp .. ','
    response = response .. '"version":"' .. response_data.version .. '"'
    response = response .. '}'

    applet:set_status(200)
    applet:add_header("Content-Type", "application/json; charset=utf-8")
    applet:add_header("Content-Length", tostring(#response))
    applet:add_header("Cache-Control", "no-cache, no-store")
    applet:add_header("X-Health-Check", "haproxy-lua")
    applet:start_response()
    applet:send(response)
end)

-- 상세 상태 페이지 (인증 필요)
core.register_service("detailed_health", "http", function(applet)
    -- 인증 확인
    local auth = applet:get_var("req.auth_ok")

    if not auth or auth ~= "1" then
        local resp = '{"error":"unauthorized"}'
        applet:set_status(401)
        applet:add_header("Content-Type", "application/json")
        applet:add_header("Content-Length", tostring(#resp))
        applet:add_header("WWW-Authenticate", 'Basic realm="Health Check"')
        applet:start_response()
        applet:send(resp)
        return
    end

    -- 상세 정보 제공
    local resp = '{"status":"ok","details":{"cpu":"normal","memory":"normal"}}'
    applet:set_status(200)
    applet:add_header("Content-Type", "application/json")
    applet:add_header("Content-Length", tostring(#resp))
    applet:start_response()
    applet:send(resp)
end)
```

---

## 11. Lua 디버깅

```bash
# HAProxy 로그에서 Lua 관련 메시지 확인
grep -i lua /var/log/haproxy.log | tail -20

# 설정 파일 검증 (Lua 스크립트 로드 오류 확인)
haproxy -f /etc/haproxy/haproxy.cfg -c

# 전체 설정으로 디버그 모드 실행 (포그라운드)
haproxy -f /etc/haproxy/haproxy.cfg -d 2>&1 | grep -i lua

# Lua 스크립트 문법 검사 (독립적으로)
luac -p /etc/haproxy/scripts/auth.lua
```

---

## 12. Lua 사용 시 주의사항

| 주의사항 | 설명 |
|---------|------|
| 블로킹 I/O | 외부 서비스 호출 시 core.tcp() 사용, 일반 I/O 금지 |
| 타임아웃 설정 | socket:settimeout()으로 타임아웃 필수 설정 |
| 에러 처리 | pcall()로 예외 처리, 스크립트 오류 시 HAProxy 전체에 영향 |
| 메모리 누수 | 전역 변수로 캐시 사용 시 크기 제한 필요 |
| 스레드 안전성 | Lua는 단일 스레드, 공유 상태에 주의 |
| JSON 처리 | 내장 JSON 파서 없음, 외부 라이브러리(cjson 등) 필요 |
| 성능 | 복잡한 로직은 C 모듈보다 느림, 필요한 경우에만 사용 |

```lua
-- 안전한 에러 처리 예시
core.register_action("safe_action", {"http-req"}, function(txn)
    local ok, err = pcall(function()
        -- 위험한 작업
        local socket = core.tcp()
        socket:settimeout(1)

        local connected, err = socket:connect("external-api", 8080)
        if not connected then
            error("Connection failed: " .. (err or "unknown"))
        end

        -- 작업 수행
        socket:close()
    end)

    if not ok then
        core.log(core.err, "Lua error in safe_action: " .. tostring(err))
        -- 에러 시 기본 동작 계속
    end
end)
```
