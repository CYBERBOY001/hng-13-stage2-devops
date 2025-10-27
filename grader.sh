#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Accept optional IP address, default to localhost
HOST="${1:-localhost}"

echo "=========================================="
echo "Blue/Green Deployment Failover Test"
echo "=========================================="
echo "Target Host: $HOST"
echo ""

# Cleanup from previous test runs
echo -e "${YELLOW}Cleanup: Stopping any existing chaos...${NC}"
curl -s -X POST http://$HOST:8081/chaos/stop > /dev/null 2>&1
curl -s -X POST http://$HOST:8082/chaos/stop > /dev/null 2>&1
echo "Waiting 3 seconds for services to stabilize..."
sleep 3
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""
echo "=========================================="
echo ""

# Test 1: Baseline - Blue active (consecutive requests)
echo -e "${YELLOW}Test 1: Baseline State (Blue Active)${NC}"
echo "Testing http://$HOST:8080/version with consecutive requests"
echo ""

baseline_blue_count=0
baseline_failed=0
baseline_requests=5

for i in $(seq 1 $baseline_requests); do
    response=$(curl -s -i http://$HOST:8080/version)
    status_code=$(echo "$response" | grep HTTP | awk '{print $2}')
    app_pool=$(echo "$response" | grep -i "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
    release_id=$(echo "$response" | grep -i "X-Release-Id:" | awk '{print $2}' | tr -d '\r')

    if [ "$status_code" = "200" ] && [ "$app_pool" = "blue" ]; then
        ((baseline_blue_count++))
        echo -e "${GREEN}Request $i: SUCCESS (Status: $status_code, Pool: $app_pool, Release: $release_id)${NC}"
    else
        ((baseline_failed++))
        echo -e "${RED}Request $i: FAILED (Status: $status_code, Pool: $app_pool)${NC}"
    fi
    sleep 0.2
done

echo ""
echo "Results: $baseline_blue_count/$baseline_requests from Blue, $baseline_failed failed"

if [ $baseline_failed -eq 0 ] && [ $baseline_blue_count -eq $baseline_requests ]; then
    echo -e "${GREEN}✓ Test 1 PASSED - All consecutive requests from Blue${NC}"
else
    echo -e "${RED}✗ Test 1 FAILED - Not all requests returned 200 from Blue${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo ""

# Test 2: Induce chaos on Blue
echo -e "${YELLOW}Test 2: Inducing Chaos on Blue${NC}"
echo "POST http://$HOST:8081/chaos/start?mode=error"
echo ""

chaos_response=$(curl -s -X POST http://$HOST:8081/chaos/start?mode=error)
echo "Response: $chaos_response"
echo -e "${GREEN}✓ Chaos induced on Blue${NC}"

echo ""

# Test 3: Verify immediate switch to Green
echo -e "${YELLOW}Test 3: Automatic Failover to Green${NC}"
echo "Testing http://$HOST:8080/version"
echo ""

response=$(curl -s -i http://$HOST:8080/version)
status_code=$(echo "$response" | grep HTTP | awk '{print $2}')
app_pool=$(echo "$response" | grep -i "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
release_id=$(echo "$response" | grep -i "X-Release-Id:" | awk '{print $2}' | tr -d '\r')

echo "Status Code: $status_code"
echo "X-App-Pool: $app_pool"
echo "X-Release-Id: $release_id"

if [ "$status_code" = "200" ] && [ "$app_pool" = "green" ]; then
    echo -e "${GREEN}✓ Test 3 PASSED - Automatic failover successful${NC}"
else
    echo -e "${RED}✗ Test 3 FAILED - No failover detected${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo ""

# Test 4: Stability under failure (within ~10 seconds)
echo -e "${YELLOW}Test 4: Stability Test (30 requests in ~10s) - Verify Zero Failures${NC}"
echo ""

failed_count=0
green_count=0
blue_count=0
total_requests=30

for i in $(seq 1 $total_requests); do
    response=$(curl -s -i http://$HOST:8080/version)
    status_code=$(echo "$response" | grep HTTP | awk '{print $2}')
    app_pool=$(echo "$response" | grep -i "X-App-Pool:" | awk '{print $2}' | tr -d '\r')

    if [ "$status_code" = "200" ]; then
        if [ "$app_pool" = "green" ]; then
            ((green_count++))
            echo -e "${GREEN}Request $i: SUCCESS (Status: $status_code, Pool: green)${NC}"
        elif [ "$app_pool" = "blue" ]; then
            ((blue_count++))
            echo -e "${GREEN}Request $i: SUCCESS (Status: $status_code, Pool: blue)${NC}"
        else
            echo -e "${YELLOW}Request $i: SUCCESS (Status: $status_code, Pool: unknown)${NC}"
        fi
    else
        ((failed_count++))
        echo -e "${RED}Request $i: FAILED (Status: $status_code, Pool: $app_pool)${NC}"
    fi

    sleep 0.3
done

echo ""
echo "Results:"
echo "  Total requests: $total_requests"
echo "  Green responses: $green_count"
echo "  Blue responses: $blue_count"
echo "  Failed requests: $failed_count"

success_rate=$((($total_requests - $failed_count) * 100 / $total_requests))
green_percentage=$(($green_count * 100 / $total_requests))

echo "  Success rate: $success_rate%"
echo "  Green percentage: $green_percentage%"

if [ $failed_count -eq 0 ] && [ $green_percentage -ge 95 ]; then
    echo -e "${GREEN}✓ Test 4 PASSED - Zero failures, ≥95% from Green${NC}"
else
    echo -e "${RED}✗ Test 4 FAILED${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo ""

# Test 5: Stop chaos and verify
echo -e "${YELLOW}Test 5: Stopping Chaos${NC}"
echo "POST http://$HOST:8081/chaos/stop"
echo ""

stop_response=$(curl -s -X POST http://$HOST:8081/chaos/stop)
echo "Response: $stop_response"
echo -e "${GREEN}✓ Chaos stopped on Blue${NC}"

echo ""
echo "=========================================="
echo ""

# Test 6: Verify Blue service becomes healthy again
echo -e "${YELLOW}Test 6: Verify Blue Service Recovers${NC}"
echo "Checking Blue service health at http://$HOST:8081/healthz"
echo ""

# Give Blue a moment to recover
sleep 2

health_response=$(curl -s -i http://$HOST:8081/healthz)
health_status=$(echo "$health_response" | grep HTTP | awk '{print $2}')

echo "Status Code: $health_status"

if [ "$health_status" = "200" ]; then
    echo -e "${GREEN}✓ Test 6 PASSED - Blue service is healthy${NC}"
else
    echo -e "${RED}✗ Test 6 FAILED - Blue service still unhealthy${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo ""

# Test 7: Verify Blue can serve traffic again after fail_timeout
echo -e "${YELLOW}Test 7: Verify Blue Returns to Traffic After fail_timeout (5s)${NC}"
echo "Waiting 5 seconds for Nginx fail_timeout to expire..."
sleep 5
echo ""
echo "Testing traffic distribution..."
echo ""

blue_recovered_count=0
green_count=0
failed_count=0
test_requests=10

for i in $(seq 1 $test_requests); do
    response=$(curl -s -i http://$HOST:8080/version)
    status_code=$(echo "$response" | grep HTTP | awk '{print $2}')
    app_pool=$(echo "$response" | grep -i "X-App-Pool:" | awk '{print $2}' | tr -d '\r')

    if [ "$status_code" = "200" ]; then
        if [ "$app_pool" = "blue" ]; then
            ((blue_recovered_count++))
            echo -e "${GREEN}Request $i: SUCCESS (Status: $status_code, Pool: blue - recovered)${NC}"
        elif [ "$app_pool" = "green" ]; then
            ((green_count++))
            echo -e "${GREEN}Request $i: SUCCESS (Status: $status_code, Pool: green)${NC}"
        else
            echo -e "${YELLOW}Request $i: SUCCESS (Status: $status_code, Pool: unknown)${NC}"
        fi
    else
        ((failed_count++))
        echo -e "${RED}Request $i: FAILED (Status: $status_code, Pool: $app_pool)${NC}"
    fi

    sleep 0.3
done

echo ""
echo "Results:"
echo "  Blue responses: $blue_recovered_count"
echo "  Green responses: $green_count"
echo "  Failed requests: $failed_count"

if [ $blue_recovered_count -gt 0 ] && [ $failed_count -eq 0 ]; then
    echo -e "${GREEN}✓ Test 7 PASSED - Blue is back in rotation with zero failures${NC}"
else
    if [ $blue_recovered_count -eq 0 ]; then
        echo -e "${RED}✗ Test 7 FAILED - Blue not serving traffic${NC}"
    fi
    if [ $failed_count -gt 0 ]; then
        echo -e "${RED}✗ Test 7 FAILED - $failed_count failed requests detected${NC}"
    fi
    exit 1
fi

echo ""
echo "=========================================="
echo ""
echo -e "${GREEN}ALL TESTS PASSED!${NC}"
echo ""
echo "Summary:"
echo "  ✓ Baseline state verified (Blue active)"
echo "  ✓ Chaos induced on Blue"
echo "  ✓ Automatic failover to Green"
echo "  ✓ Zero failed requests during chaos"
echo "  ✓ ≥95% responses from Green after failover"
echo "  ✓ Chaos stopped successfully"
echo "  ✓ Blue service became healthy again"
echo "  ✓ Blue returned to traffic after fail_timeout"
echo "  ✓ System returned to normal state"
echo ""