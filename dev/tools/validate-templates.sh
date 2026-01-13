#!/bin/bash
# Template Validation Script for MSSTLite
# This script validates all template files for missing includes and syntax errors

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "MSSTLite Template Validation"
echo "============================"

# Initialize counters
ERRORS=0
WARNINGS=0

# Function to check template includes
check_template_includes() {
    local template_file="$1"
    local template_dir=$(dirname "$template_file")
    
    # Find all INCLUDE statements in the template
    while IFS= read -r include_line; do
        # Extract the included file name
        include_file=$(echo "$include_line" | sed -n 's/.*INCLUDE[[:space:]]*"\([^"]*\)".*/\1/p')
        
        if [ ! -z "$include_file" ]; then
            # Check if the included file exists
            # First check relative to the template directory
            if [ ! -f "$template_dir/$include_file" ]; then
                # Check in Standard templates directory
                if [ ! -f "/opt/znuny/Kernel/Output/HTML/Templates/Standard/$include_file" ] && 
                   [ ! -f "/opt/znuny-6.5.15/Kernel/Output/HTML/Templates/Standard/$include_file" ]; then
                    echo -e "${RED}✗ ERROR: Missing include file '$include_file' referenced in $template_file${NC}"
                    echo "  Line: $include_line"
                    ((ERRORS++))
                fi
            fi
        fi
    done < <(grep -n "INCLUDE" "$template_file" 2>/dev/null || true)
}

# Function to validate template syntax
check_template_syntax() {
    local template_file="$1"
    
    # Check for unclosed template tags
    local open_tags=$(grep -o '\[%' "$template_file" | wc -l)
    local close_tags=$(grep -o '%\]' "$template_file" | wc -l)
    
    if [ "$open_tags" -ne "$close_tags" ]; then
        echo -e "${YELLOW}⚠ WARNING: Mismatched template tags in $template_file${NC}"
        echo "  Open tags [%: $open_tags, Close tags %]: $close_tags"
        ((WARNINGS++))
    fi
    
    # Check for common template variable patterns
    # Look for undefined environment variables (common mistake)
    if grep -q 'Env("CSRFToken")' "$template_file"; then
        echo -e "${YELLOW}⚠ WARNING: Found CSRFToken in $template_file - should use UserChallengeToken${NC}"
        ((WARNINGS++))
    fi
}

# Find all template files
echo "Scanning template files..."
echo ""

# Check Custom templates
if [ -d "Custom/Kernel/Output/HTML/Templates/Standard" ]; then
    while IFS= read -r template; do
        echo "Checking: $template"
        check_template_includes "$template"
        check_template_syntax "$template"
    done < <(find Custom/Kernel/Output/HTML/Templates/Standard -name "*.tt" -type f)
fi

# Also check copied templates if build was run
if [ -d "Kernel/Output/HTML/Templates/Standard" ]; then
    echo ""
    echo "Checking built templates..."
    while IFS= read -r template; do
        echo "Checking: $template"
        check_template_includes "$template"
        check_template_syntax "$template"
    done < <(find Kernel/Output/HTML/Templates/Standard -name "*.tt" -type f)
fi

echo ""
echo "============================"
echo "Validation Summary:"
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo -e "${RED}✗ Validation FAILED - Please fix errors before building${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✓ Validation PASSED${NC}"
    exit 0
fi