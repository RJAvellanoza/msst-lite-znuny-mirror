#!/bin/bash
# Test script to verify API blocking when no valid license exists
# This demonstrates that API access is blocked with 403 Forbidden

echo "======================================"
echo "MSSTLite API License Blocking Test"
echo "======================================"
echo ""

echo "Testing API endpoint without valid license..."
echo ""

# Make API call and capture response with headers
echo "Request: GET http://localhost/otrs/nph-genericinterface.pl/Webservice/Test"
echo ""
echo "Response:"
echo "---------"

response=$(curl -i -s http://localhost/otrs/nph-genericinterface.pl/Webservice/Test)
echo "$response"

echo ""
echo "Analysis:"
echo "---------"

# Check if we got 403
if echo "$response" | grep -q "403 Forbidden"; then
    echo "✅ SUCCESS: API returned 403 Forbidden"
else
    echo "❌ FAILED: API did not return 403"
fi

# Check for license error message
if echo "$response" | grep -q "Invalid or expired license"; then
    echo "✅ SUCCESS: License error message present"
else
    echo "❌ FAILED: License error message missing"
fi

# Check license status
if echo "$response" | grep -q '"LicenseStatus":"NotFound"'; then
    echo "✅ SUCCESS: License status is 'NotFound' (no license in database)"
elif echo "$response" | grep -q '"LicenseStatus":"Expired"'; then
    echo "✅ SUCCESS: License status is 'Expired'"
elif echo "$response" | grep -q '"LicenseStatus":"Invalid"'; then
    echo "✅ SUCCESS: License status is 'Invalid'"
else
    echo "❌ FAILED: Could not determine license status"
fi

echo ""
echo "======================================"
echo "Configuration:"
echo "- LicenseCheck::Enabled = 1"
echo "- LicenseCheck::BlockAPI = 1 (default)"
echo "======================================"